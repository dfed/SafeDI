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

/// How a declaration's type is built, read from its record: a call of another module's seam or public mock, a fill, or
/// the type's own initializer. Whether a mock builds it with its hand-written mock is the world's choice per declaration,
/// which the mock track adds.
enum TypeFactsConstruction: UInt8, Sendable {
	case initializer
	case seamCall
	case publicMockCall
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
		reads = ReadsFromAbove(graph: graph, own: own, hidden: hidden)
		readTable = readInterner.reads
		labelTexts = labels.labels
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
		"\(graph.nodes[index].property?.asValidatedForDependencyCycles.asSource ?? "root") for \(graph.nodes[index].scope.instantiable.concreteInstantiable.asSource)"
	}

	/// What the graph's folds hold, beside the nodes it keeps for text: the 32-bit elements of its columns (each 64-bit
	/// word of a bit set counts two), which a test counts per node and per edge.
	var columnElementCount: Int {
		graph.columnElementCount + instantiatedEdgeCounts.count + constructions.count + readTable.count + 2 * reads.rows.wordCount
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
		// fill takes, which it reads as a receive only if available reads it (`Scope.callerArgument`).
		if !record.holeArguments.isEmpty {
			for property in Set(record.fillReceivedProperties.values.joined()).sorted() {
				reads.append(Read(.optional, label: labels.id(of: property.label)))
			}
		}
		return reads
	}

	private static func appendReceiveReads(of label: Int32, onlyIfAvailable: Bool, forMockGeneration: Bool, to reads: inout [Read]) {
		reads.append(Read(.value, label: label))
		if onlyIfAvailable {
			reads.append(Read(.optional, label: label))
			if forMockGeneration {
				reads.append(Read(.mock, label: label))
			}
		}
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
