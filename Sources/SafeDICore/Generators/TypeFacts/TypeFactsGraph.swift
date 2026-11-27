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
/// a hole, or a world's root, built as no property. Never a path: every place of one declaration builds the same
/// children, so a world has as many nodes as its types have properties, however many paths reach them. Its position in
/// the world's graph is its declaration ID.
struct TypeFactsDeclaration: Hashable, Sendable {
	/// Two declarations are equal when they build the same record as the same property, by its exact ID, alike.
	struct Key: Hashable, Sendable {
		/// The record's identity: the declaration keeps the record alive.
		let record: ObjectIdentifier
		/// The raw `PropertyID` of the property built, or -1 for a world's root.
		let property: Int32
		let erasedToConcreteExistential: Bool
		/// Whether the declaration is a fill a call passes for a hole, which reads the fields of the case it fills, rather
		/// than a child the record's type instantiates.
		let isFill: Bool
	}

	init(scope: ConstructionScope, property: Property?, propertyID: Int32, erasedToConcreteExistential: Bool, isFill: Bool) {
		self.scope = scope
		self.property = property
		key = Key(record: ObjectIdentifier(scope.identity), property: propertyID, erasedToConcreteExistential: erasedToConcreteExistential, isFill: isFill)
	}

	let key: Key
	/// The scope built, which only the graph's build and text read.
	let scope: ConstructionScope
	/// The property built, `nil` for a world's root, which only text reads.
	let property: Property?

	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.key == rhs.key
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(key)
	}

	var construction: TypeFactsConstruction {
		if key.isFill {
			.fill
		} else if scope.seamCall != nil {
			.seamCall
		} else if scope.publicMockCall != nil {
			.publicMockCall
		} else {
			.initializer
		}
	}
}

/// How a declaration's type comes to exist, beside its kind (the property's form), which varies apart from it: an
/// `Instantiator<T>` whose `T` a hand-written mock builds is kind `instantiator`, construction `handWrittenMock`. Read
/// from the record: a call of another module's seam or public mock, a fill, or the type's own initializer. In a mock
/// world it is part of the declaration, and the mock track's column decides `handWrittenMock` and
/// `constructionFunction` per declaration (lanes/per-type-facts/track-d-columns.md, section 1); until then no node holds
/// either.
enum TypeFactsConstruction: UInt8, Sendable {
	case initializer
	case handWrittenMock
	case seamCall
	case publicMockCall
	case constructionFunction
	case fill
}

/// One world's graph: a node per declaration its root reaches, each with its edges in the order its scope builds them
/// (the properties it instantiates, then the fills it passes), the reads it makes itself, and the least sets of reads
/// each subtree takes from above it (`ReadsFromAbove`). A world is one tree to generate: a production root, a seam's own
/// tree, or a mock root.
///
/// Its facts are columns of 32-bit IDs and bit sets, one set per world: declarations by position, labels and reads by
/// dense IDs in the order the walk first meets them. `Property`, `TypeDescription` and label text are read only while the
/// graph is built and for text: each node keeps its scope and property, and the graph its labels' text, which only the
/// text of a node or a read reads. Built from the frozen
/// table alone, without unfolding a path. Today it is built only where a test observes it (`TypeFactsReport`), beside the
/// tree each path builds, to be compared with it; nothing generates from it yet. It holds its columns, and a record per
/// node, for as long as its owner keeps it; nothing of it is stored between runs or handed to another module's run.
struct TypeFactsGraph: Sendable {
	/// - Parameter forMockGeneration: Whether the world is a mock root's, whose receives only if available read what the
	///   mock root binds or pins (`ReadChannel.mock`).
	init(root: ConstructionScope, forMockGeneration: Bool) {
		// Building the graph is an edge: it reads each record's properties and labels once per node, and interns them. The
		// walk asks for a node's edges once, when it first reaches the node, so in node order.
		var instantiatedEdgeCounts = [Int32]()
		let graph = OrderedGraph(root: TypeFactsDeclaration(scope: root, property: nil, propertyID: -1, erasedToConcreteExistential: false, isFill: false)) { declaration in
			var targets = [TypeFactsDeclaration]()
			for case let .instantiated(property, child, erasedToConcreteExistential, propertyID) in declaration.scope.propertiesToGenerate {
				targets.append(TypeFactsDeclaration(scope: child, property: property, propertyID: propertyID.raw, erasedToConcreteExistential: erasedToConcreteExistential, isFill: false))
			}
			instantiatedEdgeCounts.append(Int32(targets.count))
			for case let .fill(hole, child, fillContext) in declaration.scope.holeArguments {
				targets.append(TypeFactsDeclaration(scope: child, property: hole.property, propertyID: fillContext.propertyID.raw, erasedToConcreteExistential: false, isFill: true))
			}
			return targets
		}
		let constructions = graph.nodes.map(\.construction)
		var labels = LabelInterner()
		var readInterner = ReadInterner()
		let ownReadsByNode = graph.nodes.indices.map { index in
			Self.ownReads(of: graph.nodes[index].scope.identity, builtAs: graph.nodes[index].property, forMockGeneration: forMockGeneration, labels: &labels).map { readInterner.id(of: $0) }
		}
		let own = BitRows(rowCount: graph.nodes.count, columnCount: readInterner.reads.count) { index, insert in
			ownReadsByNode[index].forEach(insert)
		}
		let readsByLabel = readInterner.readsByLabel(labelCount: labels.labels.count)
		let hidden = BitRows(rowCount: graph.nodes.count, columnCount: readInterner.reads.count) { index, insert in
			// A label no node reads has no ID, and hides nothing.
			for label in graph.nodes[index].scope.declaredLabels {
				guard let labelID = labels.existingID(of: label) else { continue }
				readsByLabel[Int(labelID)].forEach(insert)
			}
		}
		self.graph = graph
		self.instantiatedEdgeCounts = instantiatedEdgeCounts
		self.constructions = constructions
		let readsOfEdges = ReadsFromAbove(graph: graph, own: own, hidden: hidden)
		let loops = Self.loopsOfBuilders(graph: graph, instantiatedEdgeCounts: instantiatedEdgeCounts, reads: readsOfEdges, hidden: hidden, readInterner: readInterner, labels: labels)
		let reads: ReadsFromAbove
		let madeAgain: MadeAgainEdges?
		if let loops {
			// A member binds each label it rebinds at the top of its body, before every other statement, so it hides them
			// from the nodes above it, and its made-again calls are edges of the closure.
			func reboundReads(of index: Int, _ insert: (Int32) -> Void) {
				for target in loops.targetsByNode[index] {
					readsByLabel[Int(target.label)].forEach(insert)
				}
			}
			let rebound = BitRows(rowCount: graph.nodes.count, columnCount: readInterner.reads.count, columnsOfRow: reboundReads)
			let hiddenOrRebound = BitRows(rowCount: graph.nodes.count, columnCount: readInterner.reads.count) { index, insert in
				hidden.columns(inRow: index).forEach(insert)
				reboundReads(of: index, insert)
			}
			// The rebinding shadows the label for the member's own type too: its receive of a member it makes again reads the
			// rebinding, never what is above. Only the read of the label it is built as, `value` of its own label, still
			// reaches above, where its parent's declaration is being built.
			let ownAboveRebinding = BitRows(rowCount: graph.nodes.count, columnCount: readInterner.reads.count) { index, insert in
				let shadowed = Set(loops.targetsByNode[index].lazy.filter { $0.node != Int32(index) }.flatMap { readsByLabel[Int($0.label)] })
				for read in own.columns(inRow: index) where !shadowed.contains(read) {
					insert(read)
				}
			}
			let edges = MadeAgainEdges(
				graph: graph,
				targetsByNode: loops.targetsByNode.map { $0.map(\.node) },
				parentEdgesByNode: loops.targetsByNode.map { $0.map(\.parentEdge) },
				rebound: rebound,
			)
			madeAgain = edges
			reads = ReadsFromAbove(graph: graph, own: ownAboveRebinding, hidden: hiddenOrRebound, madeAgain: edges)
		} else {
			madeAgain = nil
			reads = readsOfEdges
		}
		self.madeAgain = madeAgain
		loopMembersSharedApart = loops?.membersSharedApart ?? []
		self.reads = reads
		readTable = readInterner.reads
		labelTexts = labels.labels
		var readColumn = [Int32]()
		var readOffsets = [Int32]()
		var labelColumn = [Int32]()
		var labelOffsets = [Int32]()
		var labelSeen = [Int32](repeating: -1, count: labels.labels.count)
		for index in graph.nodes.indices {
			readOffsets.append(Int32(readColumn.count))
			labelOffsets.append(Int32(labelColumn.count))
			reads.rows.forEachColumn(inRow: index) { read, _ in
				readColumn.append(read)
				let label = readInterner.reads[Int(read)].label
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
		let answers = Self.answers(of: graph, reads: reads, readTable: readInterner.reads, labels: labels, madeAgain: madeAgain, loops: loops)
		answerIsBeingBuilt = answers.isBeingBuilt
		answerIsMadeAgain = answers.isMadeAgain
		answerTexts = answers.texts
		answerKeys = answers.keys
		variants = answers.variants
		let isBeingBuilt = answers.isBeingBuilt
		let variantsOfAnswers = answers.variants
		let readsByID = readInterner.reads
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
		var cycleIDByKey = [String: Int32]()
		cycleIDs = graph.nodes.map { node in
			let key = Self.cycleKey(of: node)
			if let id = cycleIDByKey[key] {
				return id
			}
			let id = Int32(cycleIDByKey.count)
			cycleIDByKey[key] = id
			return id
		}
	}

	/// Each node's cycle identity (A4), interned from its cycle key in first-reach order.
	let cycleIDs: [Int32]

	/// The world's made-again calls, `nil` where it has no loop of builders.
	let madeAgain: MadeAgainEdges?

	/// The members of loops of builders whose parents' loops make different members again, in node order: the stand-in
	/// gives them no made-again calls, and a stage that writes from nodes refuses the world.
	let loopMembersSharedApart: [Int32]

	/// Each node's reads from above, in increasing read ID, one run per node at `readOffsets`: what `reads(of:)` slices.
	let readColumn: [Int32]
	let readOffsets: [Int32]

	/// Each node's labels read from above, each once, in read order, one run per node at `labelOffsets`.
	let labelColumn: [Int32]
	let labelOffsets: [Int32]

	/// Each answer ID's key: the answer without what a parameter carries.
	let answerKeys: [Int32]

	/// The variants of the world's bodies, answered by what each node binds at its edges (`answers(of:reads:…)`).
	let variants: TypeFactsVariants

	/// What each read of each variant comes to in its body.
	let outcomes: TypeFactsOutcomes

	/// Whether each answer ID's declaration is still being built where it answers.
	let answerIsBeingBuilt: [Bool]

	/// Whether each answer ID is a member of a loop of builders that the node answering makes again at its top.
	let answerIsMadeAgain: [Bool]

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

	/// What answers each read at each edge, by value: a node answers a read of a label it declares with the forms its
	/// declaration provides, being built where the edge builds that declaration. Interned at the edge, where the graph
	/// is built from the table; the worklist sees IDs only. Every declaration a node holds answers at every edge: which
	/// edges a declaration is bound before is the ordered bindings' column, owed by the table-side columns.
	///
	/// A member of a loop of builders binds each member it makes again at the top of its body, at every edge and at each
	/// made-again call, with the forms its parent declares that member with, made again: an answer that keys as the
	/// wrapper alone, as one being built does (rule 2), so a member made again keys as its parent's call of it does.
	private static func answers(
		of graph: OrderedGraph<TypeFactsDeclaration>,
		reads: ReadsFromAbove,
		readTable: [Read],
		labels: LabelInterner,
		madeAgain: MadeAgainEdges?,
		loops: LoopsOfBuilders?,
	) -> (variants: TypeFactsVariants, isBeingBuilt: [Bool], isMadeAgain: [Bool], texts: [String], keys: [Int32]) {
		var answerIDByText = [String: Int32]()
		var texts = [String]()
		var isBeingBuilt = [Bool]()
		var isMadeAgain = [Bool]()
		var keys = [Int32]()
		var kinds = [Property.PropertyType]()
		func answer(text: String, beingBuilt: Bool, madeAgain: Bool = false, keyText: String, kind: Property.PropertyType) -> Int32 {
			let keyID: Int32
			if let existing = answerIDByText[keyText] {
				keyID = existing
			} else {
				keyID = Int32(texts.count)
				answerIDByText[keyText] = keyID
				texts.append(keyText)
				isBeingBuilt.append(false)
				isMadeAgain.append(false)
				kinds.append(kind)
				keys.append(keyID)
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
			keys.append(keyID)
			return id
		}
		var sourceByEdge = [Int32]()
		var declarationByLabelByNode = [[Int32: (forms: String, kind: Property.PropertyType)]]()
		for index in graph.nodes.indices {
			for _ in graph.edges(from: index) {
				sourceByEdge.append(Int32(index))
			}
			var declarations = [Int32: (forms: String, kind: Property.PropertyType)]()
			for (property, forms) in graph.nodes[index].scope.sortedDeclaredPropertyForms {
				guard let label = labels.existingID(of: property.label) else { continue }
				declarations[label] = (forms.sorted().map(\.asSource).joined(separator: ", "), property.propertyType)
			}
			declarationByLabelByNode.append(declarations)
		}
		var edgeTargets = [Int32]()
		for index in graph.nodes.indices {
			edgeTargets.append(contentsOf: graph.edges(from: index))
		}
		// Each member's rebound labels, with the forms its parent declares them with: the parent declares each member it
		// builds.
		var reboundByLabelByNode = [[Int32: (forms: String, kind: Property.PropertyType)]](repeating: [:], count: loops == nil ? 0 : graph.nodes.count)
		if let loops {
			for (index, targets) in loops.targetsByNode.enumerated() {
				for target in targets {
					reboundByLabelByNode[index][target.label] = declarationByLabelByNode[Int(loops.parentByMember[index])][target.label]
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
			return VariantBinding(answer: answer(text: "\(keyText) made again", beingBuilt: false, madeAgain: true, keyText: keyText, kind: declaration.kind), declaration: Int32(node))
		}
		let variants = TypeFactsVariants(
			graph: graph,
			reads: reads,
			rootAnswer: { _ in nil },
			binding: { edge, readID in
				let read = readTable[Int(readID)]
				let node = Int(sourceByEdge[edge])
				guard read.channel.asksAboutLabel, let declaration = declarationByLabelByNode[node][read.label] else {
					return madeAgainAnswer(at: node, for: read)
				}
				let child = Int(edgeTargets[edge])
				let beingBuilt = graph.nodes[child].property.map { labels.existingID(of: $0.label) == read.label } ?? false
				let text = "\(read.channel.name) \(declaration.forms)\(beingBuilt ? " being built" : "")"
				// Rule 2: a wrapper still being built is passed and made again at the call, so it keys as the wrapper.
				let keyText = declaration.kind.isConstant ? text : "\(read.channel.name) \(declaration.forms)"
				return VariantBinding(answer: answer(text: text, beingBuilt: beingBuilt, keyText: keyText, kind: declaration.kind), declaration: Int32(node))
			},
			// Production bodies have one variant, `@Sendable` a mark folded over call edges (lead, 11-26 20:26Z); the family
			// a seam's cases, builders and mock bodies key by is the edge facts' `opens`, owed by the table-side columns.
			family: { _, family in family },
			key: { readID, answer in
				switch readTable[Int(readID)].channel {
				case .optional, .optionalValue:
					// Rule 1.
					optionalParameterKey(of: answer < 0 ? nil : kinds[Int(answer)])
				case .value, .alias, .madeAgain, .mock, .carrier, .fill, .family, .override:
					answer < 0 ? answer : keys[Int(answer)]
				}
			},
			madeAgain: madeAgain.map { edges in
				(edges, { node, readID in madeAgainAnswer(at: node, for: readTable[Int(readID)]) })
			},
		)
		return (variants, isBeingBuilt, isMadeAgain, texts, keys)
	}

	/// The declarations in the order a walk of the root's edges, depth first, first reaches each. A node keeps its scope
	/// and property only for the graph's build and for text: the folds read its position.
	let graph: OrderedGraph<TypeFactsDeclaration>

	/// What each node's subtree reads from above it, by read ID.
	let reads: ReadsFromAbove

	/// How many of each node's edges, the first ones, are properties its scope instantiates: the rest are the fills it
	/// passes.
	let instantiatedEdgeCounts: [Int32]

	let constructions: [TypeFactsConstruction]

	/// Each read ID's read.
	let readTable: [Read]

	/// Each label ID's text, which only the text of a read reads.
	let labelTexts: [String]

	/// The read as text.
	func readDescription(_ read: Int32) -> String {
		readTable[Int(read)].description(labels: labelTexts)
	}

	/// The declaration as text: the type built, and the property it is built as, `erased` and `fill` where they hold.
	func description(ofNode index: Int) -> String {
		let key = graph.nodes[index].key
		var description = graph.nodes[index].scope.instantiable.concreteInstantiable.asSource
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

	/// The property as cycle validation sees it, with the concrete type built: a place closes a cycle on a place above it
	/// of the same key (`Property.asValidatedForDependencyCycles`).
	func cycleKey(ofNode index: Int) -> String {
		Self.cycleKey(of: graph.nodes[index])
	}

	private static func cycleKey(of node: TypeFactsDeclaration) -> String {
		"\(node.property?.asValidatedForDependencyCycles.asSource ?? "root") for \(node.scope.instantiable.concreteInstantiable.asSource)"
	}

	/// What the graph's folds hold, beside the nodes it keeps for text: the 32-bit elements of its columns (each 64-bit
	/// word of a bit set counts two), which a test counts per node and per edge.
	var columnElementCount: Int {
		graph.columnElementCount + instantiatedEdgeCounts.count + constructions.count + readTable.count + 2 * reads.rows.wordCount
			+ cycleIDs.count + readColumn.count + readOffsets.count + labelColumn.count + labelOffsets.count + answerKeys.count + variants.columnElementCount
			+ (madeAgain?.columnElementCount ?? 0)
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

	/// The reads a declaration makes itself: the label of the property it is built as, whose nearest declaration its
	/// build adds forms being built to; each label its type receives, and, for a receive only if available, whether it is
	/// handed a value, and in a mock's world what the mock root pins of it; and the label an alias is fulfilled by, unless
	/// the type instantiates or forwards a property of that label, which the alias then renames; and, for a call that passes
	/// fills, each label the fills' trees receive, whose declaration the call hands them.
	private static func ownReads(of record: ScopeRecord, builtAs property: Property?, forMockGeneration: Bool, labels: inout LabelInterner) -> [Read] {
		var reads = [Read]()
		if let property {
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
				appendReceiveReads(of: labels.id(of: dependency.property.label), onlyIfAvailable: onlyIfAvailable, forMockGeneration: forMockGeneration, to: &reads)
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				if !createdLabels.contains(fulfillingProperty.label) {
					appendReceiveReads(of: labels.id(of: fulfillingProperty.label), onlyIfAvailable: onlyIfAvailable, forMockGeneration: forMockGeneration, to: &reads)
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

	/// The loops of builders of a world, and what each member makes again.
	private struct LoopsOfBuilders {
		/// A member a node makes again: its node, its label, and the parent's edge that builds it.
		struct Target: Equatable {
			let node: Int32
			let label: Int32
			let parentEdge: Int32
		}

		/// The members each node makes again, sorted by property as its body rebinds them (`ScopeGenerator.reboundProperties`).
		var targetsByNode: [[Target]]
		/// The parent that declares each member's loop, -1 for a node on none.
		var parentByMember: [Int32]
		var membersSharedApart: [Int32]
	}

	/// The loops of builders among each node's children, or `nil` for a world with none: a stand-in for the table lane's
	/// `TypeFactsEdge.loop` (`TypeFactsWorld.edgeFacts(from:)`), which replaces it once that column is filled, as
	/// `NodeBuildOrder` stands in for `buildPosition`. It is today's sibling rule (`ScopeGenerator.ReceivedBuilderLoops`)
	/// for required receives of the builders a node instantiates: an arrow from each builder child to each builder sibling
	/// its tree receives, and to itself where its tree receives its own label, and a loop for each strongly connected set
	/// of them with an arrow inside it. A receive only if available, a rename and a fill join no loop here; a stage that
	/// writes from nodes refuses each of them beside a loop. A node whose parents' loops make different members again (or
	/// a loop under one parent and none under another) is shared apart: it makes nothing again here, and is listed.
	///
	/// A member never declares a label it makes again: a declaration hides the label from the member's tree, which then
	/// receives nothing of it, so no arrow is drawn.
	private static func loopsOfBuilders(
		graph: OrderedGraph<TypeFactsDeclaration>,
		instantiatedEdgeCounts: [Int32],
		reads: ReadsFromAbove,
		hidden: BitRows,
		readInterner: ReadInterner,
		labels: LabelInterner,
	) -> LoopsOfBuilders? {
		var targetsUnderParent = [[LoopsOfBuilders.Target]?](repeating: nil, count: graph.nodes.count)
		var parentByMember = [Int32](repeating: -1, count: graph.nodes.count)
		var isSharedApart = [Bool](repeating: false, count: graph.nodes.count)
		var hasLoop = false
		for parent in graph.nodes.indices {
			// Each child once, with the parent's first edge to it.
			var children = [(node: Int32, edge: Int32)]()
			var isChild = Set<Int32>()
			for (edgeIndex, child) in graph.edges(from: parent).prefix(Int(instantiatedEdgeCounts[parent])).enumerated() where isChild.insert(child).inserted {
				children.append((child, Int32(graph.edgeOffset(of: parent) + edgeIndex)))
			}
			var targetsByChild = [[LoopsOfBuilders.Target]](repeating: [], count: children.count)
			// A fill's one child is the property it fills, whose builder function the seam's initializer declares.
			if !graph.nodes[parent].key.isFill {
				// The `value` read of each builder child's label, and the label.
				var valueReadBySlot = [Int32?](repeating: nil, count: children.count)
				var labelBySlot = [Int32](repeating: -1, count: children.count)
				var slotByValueRead = [Int32: Int]()
				for (slot, child) in children.enumerated() {
					guard let property = graph.nodes[Int(child.node)].property,
					      ScopeGenerator.isBuilder(property),
					      let label = labels.existingID(of: property.label),
					      let read = readInterner.existingID(of: Read(.value, label: label))
					else { continue }
					valueReadBySlot[slot] = read
					labelBySlot[slot] = label
					slotByValueRead[read] = slot
				}
				var arrows = [Set<Int>](repeating: [], count: children.count)
				var hasArrow = false
				for (slot, child) in children.enumerated() {
					guard let ownRead = valueReadBySlot[slot] else { continue }
					let node = Int(child.node)
					reads.rows.forEachColumn(inRow: node) { read, _ in
						if read != ownRead, let sibling = slotByValueRead[read] {
							arrows[slot].insert(sibling)
							hasArrow = true
						}
					}
					// The child's tree receives its own label where its type receives it, or a node beneath it does that the
					// child does not hide it from.
					let label = labels.labels[Int(labelBySlot[slot])]
					let receivesItself = graph.nodes[node].scope.instantiable.dependencies.contains {
						$0.source == .received(onlyIfAvailable: false) && $0.property.label == label
					}
					let treeReceivesItself = !hidden.contains(ownRead, inRow: node) && graph.edges(from: node).prefix(Int(instantiatedEdgeCounts[node])).contains {
						reads.rows.contains(ownRead, inRow: Int($0))
					}
					if receivesItself || treeReceivesItself {
						arrows[slot].insert(slot)
						hasArrow = true
					}
				}
				if hasArrow {
					let componentBySlot = ScopeGenerator.stronglyConnectedComponents(of: arrows)
					for slot in children.indices {
						let members = arrows[slot].filter { componentBySlot[$0] == componentBySlot[slot] }
						guard !members.isEmpty else { continue }
						// Each member is a builder, built as a property.
						targetsByChild[slot] = members.compactMap { member in
							graph.nodes[Int(children[member].node)].property.map { property in
								(property, LoopsOfBuilders.Target(node: children[member].node, label: labelBySlot[member], parentEdge: children[member].edge))
							}
						}
						.sorted { $0.0 < $1.0 }
						.map(\.1)
						hasLoop = true
					}
				}
			}
			for (slot, child) in children.enumerated() {
				if let targets = targetsUnderParent[Int(child.node)] {
					if targets.map(\.node) != targetsByChild[slot].map(\.node) {
						isSharedApart[Int(child.node)] = true
					}
				} else {
					targetsUnderParent[Int(child.node)] = targetsByChild[slot]
					if !targetsByChild[slot].isEmpty {
						parentByMember[Int(child.node)] = Int32(parent)
					}
				}
			}
		}
		guard hasLoop else { return nil }
		var membersSharedApart = [Int32]()
		var targetsByNode = [[LoopsOfBuilders.Target]]()
		for node in graph.nodes.indices {
			if isSharedApart[node] {
				membersSharedApart.append(Int32(node))
				targetsByNode.append([])
				parentByMember[node] = -1
			} else {
				targetsByNode.append(targetsUnderParent[node] ?? [])
			}
		}
		return LoopsOfBuilders(targetsByNode: targetsByNode, parentByMember: parentByMember, membersSharedApart: membersSharedApart)
	}

	/// A world's labels, by dense ID in the order the graph's build first meets them.
	private struct LabelInterner {
		mutating func id(of label: String) -> Int32 {
			if let id = idByLabel[label] {
				return id
			}
			let id = Int32(labels.count)
			idByLabel[label] = id
			labels.append(label)
			return id
		}

		func existingID(of label: String) -> Int32? {
			idByLabel[label]
		}

		private(set) var labels = [String]()
		private var idByLabel = [String: Int32]()
	}

	/// A world's reads, by dense ID in the order the graph's build first meets them.
	private struct ReadInterner {
		mutating func id(of read: Read) -> Int32 {
			if let id = idByRead[read] {
				return id
			}
			let id = Int32(reads.count)
			idByRead[read] = id
			reads.append(read)
			return id
		}

		func existingID(of read: Read) -> Int32? {
			idByRead[read]
		}

		/// The reads of each label, by label ID.
		func readsByLabel(labelCount: Int) -> [[Int32]] {
			var readsByLabel = [[Int32]](repeating: [], count: labelCount)
			for (id, read) in reads.enumerated() where read.channel.asksAboutLabel {
				readsByLabel[Int(read.label)].append(Int32(id))
			}
			return readsByLabel
		}

		private(set) var reads = [Read]()
		private var idByRead = [Read: Int32]()
	}
}
