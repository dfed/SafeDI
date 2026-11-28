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

extension TypeFactsGraph {
	/// A call into the mock worlds' shared graph from a mock world's own graph, by value, since the two graphs number
	/// their reads, labels, properties and answers apart: the declaration called, the family and `@Sendable` mark of the
	/// caller's call, and the key the call hands each read of the declaration from above. The shared graph interns each
	/// key as its own (`init(roots:forMockGeneration:mockRootNames:seeds:)`).
	struct Seed: Hashable, Sendable {
		/// A read by value: its channel, and the label it asks about where it asks about one.
		struct Read: Hashable, Sendable {
			let channel: ReadChannel
			let label: String?
		}

		/// A key that names an answer, by value: its text and what the answers fold reads of it.
		struct Answer: Hashable, Sendable {
			let text: String
			let isBeingBuilt: Bool
			let isMadeAgain: Bool
			/// The declared kind's position among `Property.PropertyType.allCases`, which is not `Sendable`.
			let kindPosition: Int
			/// The declaration that answers, `nil` for an answer of none.
			let property: Property?
			let isInReadForm: Bool

			var kind: Property.PropertyType {
				Property.PropertyType.allCases.first { OnlyIfAvailableForm.position(of: $0) == kindPosition } ?? .constant
			}
		}

		/// A read's key: one of the keys that name no answer (none, and the optional parameters' keys), or an answer's.
		enum Key: Hashable, Sendable {
			case parameter(Int32)
			case answer(Answer)
		}

		struct Entry: Hashable, Sendable {
			let read: Read
			let key: Key
		}

		let declaration: TypeFactsDeclaration
		let family: VariantFamily
		let buildsInSendableFunction: Bool
		/// One entry per read of the declaration from above, in the caller's read order.
		let keys: [Entry]
	}

	/// What a call of `variant` hands it, by value: the seed the shared graph starts the variant's body from where this
	/// world's own graph makes the call.
	func seed(of variant: Int) -> Seed {
		let node = Int(variants.node(of: variant))
		var entries = [Seed.Entry]()
		for (position, key) in variants.keys(of: variant).enumerated() {
			let read = readTable[Int(readColumn[Int(readOffsets[node]) + position])]
			let seedRead = Seed.Read(channel: read.channel, label: read.label >= 0 ? labelTexts[Int(read.label)] : nil)
			guard key >= 0 else {
				entries.append(Seed.Entry(read: seedRead, key: .parameter(key)))
				continue
			}
			let answer = Int(key)
			entries.append(Seed.Entry(read: seedRead, key: .answer(Seed.Answer(
				text: answerTexts[answer],
				isBeingBuilt: answerIsBeingBuilt[answer],
				isMadeAgain: answerIsMadeAgain[answer],
				kindPosition: answerKindPositions[answer],
				property: answerProperties[answer] >= 0 ? propertyTable[Int(answerProperties[answer])] : nil,
				isInReadForm: answerIsInReadForm[answer],
			))))
		}
		return Seed(declaration: graph.nodes[node], family: variants.family(of: variant), buildsInSendableFunction: variantBuildsInSendableFunction[variant], keys: entries)
	}
}

extension TypeFactsGraph {
	/// A frontier's rows: what a declaration of the shared graph's subtree reads from above it and holds beneath it, by
	/// value, which a mock world's top graph, holding the declaration as a leaf, takes as its own (`init(topOf:…)`). Each
	/// row is the one the shared graph computed, after the declarations of the subtree hid what they hide.
	struct FrontierRows: Sendable {
		/// A form of a label the subtree reads only if available from above.
		struct FormRead: Hashable, Sendable {
			let label: String
			/// The kind's position among `Property.PropertyType.allCases`, which is not `Sendable`.
			let kindPosition: Int
		}

		/// A required receive of the subtree that a mock root's pins collect beneath the declaration: its label and the
		/// properties it reads (`TypeFactsMockRootPins`), each once.
		struct RequiredRead: Hashable, Sendable {
			let label: String
			let propertiesRead: Set<Property>
		}

		let required: [Property]
		let onlyIfAvailable: [Property]
		let onlyIfAvailableUnwrappedIncludingRequired: [Property]
		let requiredAliasFulfilling: [Property]
		let typesBeneath: [TypeDescription]
		let typesDeclaredEscaping: [TypeDescription]
		let reads: [Seed.Read]
		let formsRead: [FormRead]
		let requiredReads: [RequiredRead]
	}

	/// A mock world's top graph: the world's graph from `root`, in which each declaration `frontierRows` gives rows of is a
	/// leaf whose subtree is the mock worlds' shared graph's (`MockWorldsSharedGraph`). Its variants of a frontier are the
	/// calls the world makes into the shared graph, keyed as the world built whole keys them.
	init(topOf root: ConstructionScope, forMockGeneration: Bool, frontierRows: (TypeFactsDeclaration) -> FrontierRows?) {
		self.init(
			roots: [TypeFactsDeclaration(scope: root, property: nil, propertyID: nil, erasedToConcreteExistential: false, isFill: false)],
			forMockGeneration: forMockGeneration,
			mockRootNames: MockRootNames(),
			seeds: nil,
			frontierRows: frontierRows,
		)
	}

	/// Each node's rows by value, from the shared graph's own rows; the required receives the pins collect beneath a node
	/// are folded children first, along the edges the pins' walk enters (no leaf; the shared graph holds no fill), each
	/// label stopping beneath a node that declares it.
	static func frontierRows(
		of graph: OrderedGraph<TypeFactsDeclaration>,
		properties: [Property],
		types: [TypeDescription],
		labels: [String],
		reads: (table: [Read], rows: BitRows),
		forms: (table: [OnlyIfAvailableForm], rows: BitRows),
		receives: TypeFactsReceives,
		onlyIfAvailable: BitRows,
		onlyIfAvailableUnwrappedIncludingRequired: BitRows,
		typesBeneath: BitRows,
		typesDeclaredEscaping: BitRows,
	) -> [FrontierRows] {
		let nodes = graph.nodes
		// The shared graph is on no cycle, so each node is a component of its own, numbered as the walk completes it: in
		// that order every node follows the nodes it leads to.
		let completionOrder = nodes.indices.sorted { graph.componentByNode[$0] < graph.componentByNode[$1] }
		var requiredReadsByNode = [[FrontierRows.RequiredRead]](repeating: [], count: nodes.count)
		for node in completionOrder where nodes[node].key.leaf == .none {
			let scope = nodes[node].scope
			var requiredReads = DependencyTreeGenerator.propertiesReadByRequiredReceivesFromAbove(of: scope.instantiable, publicMockCall: scope.publicMockCall).map {
				FrontierRows.RequiredRead(label: $0.label, propertiesRead: $0.propertiesRead)
			}
			let declaredLabels = DependencyTreeGenerator.labelsDeclared(by: scope)
			for child in graph.edges(from: node) {
				for read in requiredReadsByNode[Int(child)] where !declaredLabels.contains(read.label) && !requiredReads.contains(read) {
					requiredReads.append(read)
				}
			}
			requiredReadsByNode[node] = requiredReads
		}
		return nodes.indices.map { node in
			FrontierRows(
				required: receives.required.columns(inRow: node).map { properties[Int($0)] },
				onlyIfAvailable: onlyIfAvailable.columns(inRow: node).map { properties[Int($0)] },
				onlyIfAvailableUnwrappedIncludingRequired: onlyIfAvailableUnwrappedIncludingRequired.columns(inRow: node).map { properties[Int($0)] },
				requiredAliasFulfilling: receives.requiredAliasFulfilling.columns(inRow: node).map { properties[Int($0)] },
				typesBeneath: typesBeneath.columns(inRow: node).map { types[Int($0)] },
				typesDeclaredEscaping: typesDeclaredEscaping.columns(inRow: node).map { types[Int($0)] },
				reads: reads.rows.columns(inRow: node).map { readID in
					let read = reads.table[Int(readID)]
					return Seed.Read(channel: read.channel, label: read.label >= 0 ? labels[Int(read.label)] : nil)
				},
				formsRead: forms.rows.columns(inRow: node).map { formID in
					let form = forms.table[Int(formID)]
					return FrontierRows.FormRead(label: labels[Int(form.label)], kindPosition: form.kind)
				},
				requiredReads: requiredReadsByNode[node],
			)
		}
	}
}

/// The mock worlds' shared graph: one `TypeFactsGraph` over the shareable declarations (`MockWorldsTable`) the module's
/// mock worlds call into, rooted at each world's frontier in turn, whose variants start from the worlds' calls into it
/// (`TypeFactsGraph.Seed`), so a body two worlds call with one key is one variant. It pins nothing and holds no place,
/// which the table's exclusions make true of every declaration in it, so it conforms as any world's graph does
/// (`NodeRecordSources`), with one root per seed.
///
/// Each world is built as a top graph (`TypeFactsGraph.init(topOf:forMockGeneration:frontierRows:)`): its own
/// declarations, and its frontier as leaves whose rows the shared graph gives by value. The shared graph is built twice:
/// once for its rows, which no seed changes and which the top graphs need, and once seeded with the calls the top graphs
/// make into it. Both builds grow with the shared declarations, never with the worlds that reach them; a later change can
/// split the graph's initializer so that its variants alone are found the second time.
///
/// Per world it keeps the top graph, the calls the world makes into the shared graph, each from a variant of a frontier
/// of the top graph to the shared variant it lands on, and, for each shared declaration the world reaches, the parents
/// the world reaches it through, in the world's order: a top declaration by its table ID, a shared one by its position
/// in the shared graph.
///
/// Built only where a test observes the mock worlds' sharing. It holds the shared graph, each world's top graph, and the
/// worlds' calls and parents for as long as `generateMockCode` keeps it: one run's mock generation. The build of the
/// shared graph for its rows dies with the initializer.
struct MockWorldsSharedGraph: Sendable {
	/// - Parameter table: The module's mock worlds' table.
	init(table: MockWorldsTable) {
		var roots = [TypeFactsDeclaration]()
		var topByWorld = [Set<Int32>]()
		for world in 0..<table.worldCount {
			roots.append(contentsOf: table.frontierDeclarations(ofWorld: world).map(table.declaration(ofID:)))
			topByWorld.append(Set(table.topDeclarations(ofWorld: world)))
		}
		let rowsGraph = TypeFactsGraph(roots: roots, forMockGeneration: true, mockRootNames: MockRootNames(), seeds: [])
		let topGraphs = topByWorld.enumerated().map { world, top in
			TypeFactsGraph(topOf: table.declaration(ofID: table.rootDeclaration(ofWorld: world)).scope, forMockGeneration: true) { declaration in
				guard let id = table.declarationID(of: declaration), !top.contains(id), let node = rowsGraph.graph.index(of: declaration) else { return nil }
				return rowsGraph.frontierRowsByNode[node]
			}
		}
		// Each top graph's node is a frontier where the table does not keep it in the world's own graph.
		let isFrontierByWorld = zip(topGraphs, topByWorld).map { world, top in
			world.graph.nodes.map { declaration in table.declarationID(of: declaration).map { !top.contains($0) } ?? false }
		}
		var seeds = [TypeFactsGraph.Seed]()
		var callsByWorld = [[(caller: Int32, edgeIndex: Int, callee: Int32, seed: Int)]]()
		for (world, isFrontier) in zip(topGraphs, isFrontierByWorld) {
			var calls = [(caller: Int32, edgeIndex: Int, callee: Int32, seed: Int)]()
			for variant in 0..<world.variants.count {
				let node = Int(world.variants.node(of: variant))
				for (edgeIndex, callee) in world.variants.callees(of: variant).enumerated() where isFrontier[Int(world.graph.edgeTargets[world.graph.edgeOffset(of: node) + edgeIndex])] {
					calls.append((Int32(variant), edgeIndex, callee, seeds.count))
					seeds.append(world.seed(of: Int(callee)))
				}
			}
			callsByWorld.append(calls)
		}
		let graph = TypeFactsGraph(roots: roots, forMockGeneration: true, mockRootNames: MockRootNames(), seeds: seeds)
		self.graph = graph
		worlds = zip(zip(topGraphs, topByWorld), zip(isFrontierByWorld, callsByWorld)).map { topAndSet, frontierAndCalls in
			let (topGraph, top) = topAndSet
			let (isFrontier, calls) = frontierAndCalls
			return World(
				topGraph: topGraph,
				frontierCalls: calls.map { FrontierCall(caller: $0.caller, edgeIndex: $0.edgeIndex, frontierVariant: $0.callee, sharedVariant: graph.variants.seedVariants[$0.seed]) },
				parentsByDeclaration: Self.parentsOfSharedDeclarations(topGraph: topGraph, isFrontier: isFrontier, shared: graph, table: table, top: top),
			)
		}
	}

	/// A node of a world walked whole across its top graph and the shared graph: a node of either, by its position there.
	private enum WorldNode: Hashable, Sendable {
		case top(Int)
		case shared(Int)
	}

	/// The shared declarations the world reaches, in the order the world built whole first reaches them, each with its
	/// parents in the world's order of edges: the world's walk, taking a top declaration's edges from its top graph and a
	/// shared one's from the shared graph, which the world built whole walks alike, since a declaration's edges are its
	/// scope's (`TypeFactsDeclaration.edges`). The walk dies with the call.
	private static func parentsOfSharedDeclarations(topGraph: TypeFactsGraph, isFrontier: [Bool], shared: TypeFactsGraph, table: MockWorldsTable, top: Set<Int32>) -> [(declaration: Int32, parents: [Parent])] {
		let walk = OrderedGraph(root: WorldNode.top(0)) { node in
			switch node {
			case let .top(index):
				topGraph.graph.edges(from: index).compactMap { target in
					isFrontier[Int(target)] ? shared.graph.index(of: topGraph.graph.nodes[Int(target)]).map(WorldNode.shared) : .top(Int(target))
				}
			case let .shared(index):
				// A declaration the world keeps top is one node of the world, reached from wherever its parents are.
				shared.graph.edges(from: index).compactMap { target in
					let declaration = shared.graph.nodes[Int(target)]
					return table.declarationID(of: declaration).map(top.contains) ?? false ? topGraph.graph.index(of: declaration).map(WorldNode.top) : .shared(Int(target))
				}
			}
		}
		var parentsByNode = [[Parent]](repeating: [], count: walk.nodes.count)
		for (index, node) in walk.nodes.enumerated() {
			let parent: Parent = switch node {
			case let .top(topIndex):
				.top(table.declarationID(of: topGraph.graph.nodes[topIndex]) ?? -1)
			case let .shared(sharedIndex):
				.shared(Int32(sharedIndex))
			}
			for target in walk.edges(from: index) {
				parentsByNode[Int(target)].append(parent)
			}
		}
		return walk.nodes.enumerated().compactMap { index, node in
			switch node {
			case .top:
				nil
			case let .shared(sharedIndex):
				(Int32(sharedIndex), parentsByNode[index])
			}
		}
	}

	/// A parent a world reaches a shared declaration through: a declaration of its own graph, by its table ID, or one of
	/// the shared graph, by its position there.
	enum Parent: Hashable, Sendable {
		case top(Int32)
		case shared(Int32)
	}

	/// A call a world's top declaration makes into the shared graph: the world's calling variant and the index of its
	/// edge, the variant of the frontier the call is in the top graph, and the shared variant the call's seed is.
	struct FrontierCall: Hashable, Sendable {
		let caller: Int32
		let edgeIndex: Int
		let frontierVariant: Int32
		let sharedVariant: Int32
	}

	/// What one world takes from the shared graph.
	struct World: Sendable {
		/// The world's own graph, whose frontier's variants are its calls into the shared graph.
		let topGraph: TypeFactsGraph
		/// The world's calls into the shared graph, in its variants' order, each variant's in edge order.
		let frontierCalls: [FrontierCall]
		/// Each shared declaration the world reaches, by its position in the shared graph, in the order the world first
		/// reaches them, with the parents the world reaches it through, in the world's order of edges.
		let parentsByDeclaration: [(declaration: Int32, parents: [Parent])]
	}

	/// The shared graph.
	let graph: TypeFactsGraph
	/// Each world's top graph, calls and parents, in the table's order of worlds.
	let worlds: [World]
}
