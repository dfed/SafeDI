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

		/// The outcome the caller's graph found for one read of the variant it calls (`TypeFactsOutcomes`), by its form
		/// alone: a statement of the caller's root body is the statement that binds the read's label in the answer its key
		/// names, whichever world's root it is, so two worlds whose roots each bind it offer one statement.
		struct Outcome: Hashable, Sendable {
			let form: TypeFactsOutcome

			/// The class the shared graph's variants are told apart by (`TypeFactsVariants.OfferedClass`).
			var offeredClass: TypeFactsVariants.OfferedClass {
				switch form {
				case .none:
					.nothing
				case .captured, .readBeforeSendableFunction:
					.rootStatement
				case .parameter:
					.parameter
				case .keysVariant:
					.unclassed
				}
			}
		}

		let declaration: TypeFactsDeclaration
		let family: VariantFamily
		let buildsInSendableFunction: Bool
		/// One entry per read of the declaration from above, in the caller's read order.
		let keys: [Entry]
		/// One outcome per entry of `keys`.
		let outcomes: [Outcome]
	}

	/// What a call of `variant` hands it, by value: the seed the shared graph starts the variant's body from where this
	/// world's own graph makes the call.
	func seed(of variant: Int) -> Seed {
		let node = Int(variants.node(of: variant))
		var entries = [Seed.Entry]()
		let seedOutcomes = outcomes.forms(of: Int32(variant)).map(Seed.Outcome.init(form:))
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
		return Seed(declaration: graph.nodes[node], family: variants.family(of: variant), buildsInSendableFunction: variantBuildsInSendableFunction[variant], keys: entries, outcomes: seedOutcomes)
	}

	/// The outcomes each seed offers the variant it is, in that variant's read order, matched to the seed's entries by
	/// read: a statement is the one that binds the read's label in the answer its key names (`Seed.Outcome`), one
	/// statement of the shared graph's for every world that offers it.
	static func seedOutcomes(of seeds: [Seed], variants: TypeFactsVariants, readTable: [Read], labels: [String], readColumn: [Int32], readOffsets: [Int32]) -> [(variant: Int32, outcomes: [TypeFactsOutcomes.Outcome])] {
		var statements = TypeFactsInterner<Seed.Entry>()
		return zip(seeds, variants.seedVariants).map { seed, variant in
			var offeredByRead = [Seed.Read: (entry: Seed.Entry, outcome: Seed.Outcome)]()
			for (entry, outcome) in zip(seed.keys, seed.outcomes) {
				offeredByRead[entry.read] = (entry, outcome)
			}
			let node = Int(variants.node(of: Int(variant)))
			let offered = readColumn[Int(readOffsets[node])..<Int(readOffsets[node + 1])].map { readID -> TypeFactsOutcomes.Outcome in
				let read = readTable[Int(readID)]
				guard let (entry, outcome) = offeredByRead[Seed.Read(channel: read.channel, label: read.label >= 0 ? labels[Int(read.label)] : nil)] else { return .none }
				return switch outcome.form {
				case .none:
					.none
				case .parameter:
					.parameter
				case .keysVariant:
					.keysVariant
				// A statement of the caller's world, read before a `@Sendable` function or not: whether the variant reads it
				// before one is the shared graph's to decide, from the variant's family, as for any statement it is offered.
				case .captured, .readBeforeSendableFunction:
					.statement(statements.id(of: entry))
				}
			}
			return (variant, offered)
		}
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

		let required: [Property]
		let onlyIfAvailable: [Property]
		let onlyIfAvailableUnwrappedIncludingRequired: [Property]
		let requiredAliasFulfilling: [Property]
		let typesBeneath: [TypeDescription]
		let typesDeclaredEscaping: [TypeDescription]
		let reads: [Seed.Read]
		let formsRead: [FormRead]
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

	/// Each node's rows by value, from the shared graph's own rows.
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
		graph.nodes.indices.map { node in
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
		for (topGraph, isFrontier) in zip(topGraphs, isFrontierByWorld) {
			var calls = [(caller: Int32, edgeIndex: Int, callee: Int32, seed: Int)]()
			for variant in 0..<topGraph.variants.count {
				let node = Int(topGraph.variants.node(of: variant))
				for (edgeIndex, callee) in topGraph.variants.callees(of: variant).enumerated() where isFrontier[Int(topGraph.graph.edgeTargets[topGraph.graph.edgeOffset(of: node) + edgeIndex])] {
					calls.append((Int32(variant), edgeIndex, callee, seeds.count))
					seeds.append(topGraph.seed(of: Int(callee)))
				}
			}
			callsByWorld.append(calls)
		}
		let graph = TypeFactsGraph(roots: roots, forMockGeneration: true, mockRootNames: MockRootNames(), seeds: seeds)
		self.graph = graph
		worlds = zip(zip(topGraphs, topByWorld), zip(isFrontierByWorld, callsByWorld)).map { topAndSet, frontierAndCalls in
			let (topGraph, top) = topAndSet
			let (isFrontier, calls) = frontierAndCalls
			let frontierCalls = calls.map { FrontierCall(caller: $0.caller, edgeIndex: $0.edgeIndex, frontierVariant: $0.callee, sharedVariant: graph.variants.seedVariants[$0.seed]) }
			return World(
				topGraph: topGraph,
				frontierCalls: frontierCalls,
				parentsByDeclaration: Self.parentsOfSharedDeclarations(topGraph: topGraph, isFrontier: isFrontier, shared: graph, table: table, top: top),
				builtWholeReason: Self.reachesVariantsApartOnlyByClass(from: frontierCalls, in: graph) ? .callsSharedDeclarationInOtherClasses : nil,
			)
		}
	}

	/// Whether the shared variants a world's calls reach, its frontier calls' and every variant those call in turn, hold two
	/// of one declaration in one family with one key that the shared graph tells apart only by the class a read is offered
	/// (`TypeFactsVariants.OfferedClass`): two frontier calls that offer one read in different classes, or two variants
	/// whose calls converge on one callee with a label passed through in different classes. Built whole, the world makes
	/// one variant of those calls, whose outcome joins the two classes and so equals neither shared variant's, so such a
	/// world is built whole. One walk of the variants this world reaches, which dies with the call; no fold across worlds.
	private static func reachesVariantsApartOnlyByClass(from calls: [FrontierCall], in graph: TypeFactsGraph) -> Bool {
		let variants = graph.variants
		var isReached = [Bool](repeating: false, count: variants.count)
		// The reached variants of each declaration, in the order the walk reaches them; read only to compare, so no order
		// of the dictionary reaches the result.
		var reachedByNode = [Int32: [Int32]]()
		var pending = calls.map(\.sharedVariant)
		while let variant = pending.popLast() {
			guard !isReached[Int(variant)] else { continue }
			isReached[Int(variant)] = true
			let node = variants.node(of: Int(variant))
			for other in reachedByNode[node, default: []] where variants.family(of: Int(other)) == variants.family(of: Int(variant)) && variants.keys(of: Int(other)).elementsEqual(variants.keys(of: Int(variant))) {
				return true
			}
			reachedByNode[node, default: []].append(variant)
			pending.append(contentsOf: variants.callees(of: Int(variant)))
		}
		return false
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
		/// Why the shared graph's facts cannot stand for the world's, so that it is built whole, or `nil` where they can.
		let builtWholeReason: MockWorldSharingReport.BuiltWholeReason?
	}

	/// The shared graph.
	let graph: TypeFactsGraph
	/// Each world's top graph, calls and parents, in the table's order of worlds.
	let worlds: [World]
}

extension MockWorldsSharedGraph {
	/// Every way the facts each world takes from the shared graph differ from those of the world built whole, in the order
	/// of the worlds: for each shared declaration the world reaches, its facts (`declarationFacts(of:)`), and for each
	/// shared variant the world's calls reach, its facts (`variantFacts(of:)`), paired with the world's own variant by the
	/// call that reaches both, each callee by its edge, so that two variants the world tells apart are never one shared
	/// variant, and every variant of a shared declaration the world builds is reached. What depends on the world's paths
	/// is left out: the parents, routes and cycles of a declaration, and whether a variant is called once.
	///
	/// A shared variant's outcomes (`TypeFactsOutcomes`) and the parameters that follow from them equal, in every world
	/// that calls it, those of the world's variant built whole, a statement compared by the label it binds and its form
	/// (`outcomeCells(of:)`): the seeds tell variants apart by what each read is offered (`TypeFactsVariants.Seed`), so
	/// no join across worlds changes an outcome.
	///
	/// - Parameter worldsBuiltWhole: Each world's graph built from its root, in the table's order of worlds.
	func differences(fromWorldsBuiltWhole worldsBuiltWhole: [TypeFactsGraph]) -> [String] {
		var differences = [String]()
		// A world built whole takes nothing of the shared graph, so nothing of it is compared.
		for (index, (world, whole)) in zip(worlds, worldsBuiltWhole).enumerated() where world.builtWholeReason == nil {
			var isShared = [Bool](repeating: false, count: whole.graph.nodes.count)
			for (declaration, _) in world.parentsByDeclaration {
				let wholeNode = whole.graph.index(of: graph.graph.nodes[Int(declaration)])
				differences += Self.difference(if: wholeNode == nil, "world \(index): shared d\(declaration) is no declaration of the world built whole")
				guard let node = wholeNode else { continue }
				isShared[node] = true
				let shared = graph.declarationFacts(of: Int(declaration))
				let built = whole.declarationFacts(of: node)
				differences += Self.difference(if: shared != built, "world \(index): shared d\(declaration) \(shared) ≠ built whole \(built)")
			}
			// The world built whole's variants of each shared declaration, by what a call of each hands it.
			var wholeVariantsBySeed = [TypeFactsGraph.Seed.Projection: [Int32]]()
			for variant in 0..<whole.variants.count where isShared[Int(whole.variants.node(of: variant))] {
				wholeVariantsBySeed[whole.seed(of: variant).projection, default: []].append(Int32(variant))
			}
			var sharedByWhole = [Int32: Int32]()
			var wholeByShared = [Int32: Int32]()
			var pending = [(shared: Int32, whole: Int32)]()
			for call in world.frontierCalls {
				let seed = world.topGraph.seed(of: Int(call.frontierVariant)).projection
				let matching = wholeVariantsBySeed[seed] ?? []
				differences += Self.difference(if: matching.count != 1, "world \(index): call of v\(call.sharedVariant) matches \(matching.count) variants of the world built whole")
				guard matching.count == 1 else { continue }
				pending.append((call.sharedVariant, matching[0]))
			}
			while let pair = pending.popLast() {
				let (sharedVariant, wholeVariant) = pair
				let isPaired = sharedByWhole[wholeVariant] != nil || wholeByShared[sharedVariant] != nil
				let pairsApart = isPaired && (sharedByWhole[wholeVariant] != sharedVariant || wholeByShared[sharedVariant] != wholeVariant)
				differences += Self.difference(if: pairsApart, "world \(index): shared v\(sharedVariant) and built whole v\(wholeVariant) pair apart")
				guard !isPaired else { continue }
				sharedByWhole[wholeVariant] = sharedVariant
				wholeByShared[sharedVariant] = wholeVariant
				let shared = graph.variantFacts(of: Int(sharedVariant))
				let built = whole.variantFacts(of: Int(wholeVariant))
				differences += Self.difference(if: shared != built, "world \(index): shared v\(sharedVariant) \(shared) ≠ built whole v\(wholeVariant) \(built)")
				let sharedOutcomes = graph.outcomeCells(of: Int(sharedVariant))
				let builtOutcomes = whole.outcomeCells(of: Int(wholeVariant))
				differences += Self.difference(if: sharedOutcomes != builtOutcomes, "world \(index): shared v\(sharedVariant) outcomes \(sharedOutcomes) ≠ built whole v\(wholeVariant) \(builtOutcomes)")
				let sharedParameters = graph.parameterFacts(of: Int(sharedVariant))
				let builtParameters = whole.parameterFacts(of: Int(wholeVariant))
				differences += Self.difference(if: sharedParameters != builtParameters, "world \(index): shared v\(sharedVariant) parameters \(sharedParameters) ≠ built whole v\(wholeVariant) \(builtParameters)")
				for (sharedCallee, wholeCallee) in zip(graph.variants.callees(of: Int(sharedVariant)), whole.variants.callees(of: Int(wholeVariant))) {
					pending.append((sharedCallee, wholeCallee))
				}
			}
			for variants in wholeVariantsBySeed.values {
				for variant in variants where sharedByWhole[variant] == nil {
					differences.append("world \(index): built whole v\(variant) of a shared declaration has no shared variant")
				}
			}
		}
		// The unpaired variants were met in dictionary order: sorted, they are reported alike on every run.
		return differences.sorted()
	}

	/// `text` as the one difference, where `isDifferent` holds; otherwise none. The text is spelled only for a difference,
	/// which a passing run never has.
	private static func difference(if isDifferent: Bool, _ text: @autoclosure () -> String) -> [String] {
		isDifferent ? [text()] : []
	}
}

extension TypeFactsGraph {
	/// One read's outcome, by value: the read's text, which names the label a statement binds, and the outcome's form.
	struct OutcomeCell: Hashable, Sendable {
		let read: String
		let form: TypeFactsOutcome
	}

	/// The outcome of each read of `variant`, in the order of the reads' texts.
	func outcomeCells(of variant: Int) -> [OutcomeCell] {
		let node = Int(variants.node(of: variant))
		let readTexts = reads(of: DeclarationID(node)).map { readTable[Int($0)].description(labels: labelTexts) }
		return zip(readTexts, outcomes.forms(of: Int32(variant))).map(OutcomeCell.init(read:form:)).sorted { $0.read < $1.read }
	}

	/// The parameters `variant`'s function takes, as text, in their order (`TypeFactsWorld.parameters(of:)`).
	func parameterFacts(of variant: Int) -> String {
		"\(parameters(of: VariantID(variant)).map { "\($0.property.asSource)\($0.readsInstanceOfWrapper ? " instance" : "")" })"
	}
}

extension TypeFactsGraph.Seed {
	/// The seed as two graphs compare it: its declaration, family and keys by value, whatever order each graph reads in.
	struct Projection: Hashable, Sendable {
		let declaration: TypeFactsDeclaration
		let family: VariantFamily
		let keys: Set<Entry>
	}

	var projection: Projection {
		Projection(declaration: declaration, family: family, keys: Set(keys))
	}
}

extension TypeFactsGraph {
	/// A declaration's facts as text, by value, every row sorted, so that two graphs that number their values apart give
	/// one text for one fact.
	func declarationFacts(of node: Int) -> String {
		func spelled(_ row: BitRows, _ spelling: (Int32) -> String) -> String {
			"[\(row.columns(inRow: node).map(spelling).sorted().joined(separator: ", "))]"
		}
		func property(_ id: Int32) -> String {
			id >= 0 ? propertyTable[Int(id)].asSource : "none"
		}
		var parts = ["\(kinds[node]) \(constructions[node]) \(property(nodeProperties[node])) \(typeTable[Int(builtTypes[node])].asSource)"]
		let edgeFacts = edgeFacts(from: DeclarationID(node))
		parts.append("edges [\(edgeFacts.map { "\(property(nodeProperties[Int($0.child)])) at \($0.buildPosition) loop \($0.loop) \($0.opens) fill \($0.isFill) after \($0.bindingsBefore)" }.joined(separator: ", "))]")
		let bindings = bindings[Int(bindingOffsets[node])..<Int(bindingOffsets[node + 1])]
		parts.append("bindings [\(bindings.map { "\(labelTexts[Int($0.label)]) \(property($0.property)) forwarded \($0.isForwarded) rebound \($0.isReboundByBuilderFunction)" }.joined(separator: ", "))]")
		parts.append("reads \(spelled(reads.rows) { readTable[Int($0)].description(labels: labelTexts) })")
		parts.append("received \(spelled(receives.received, property)) required \(spelled(receives.required, property))")
		parts.append("unwrapped \(spelled(receives.onlyIfAvailableUnwrapped, property)) through aliases \(spelled(receives.requiredAliasFulfilling, property))")
		parts.append("types \(spelled(typesBeneath) { typeTable[Int($0)].asSource }) escaping \(spelled(typesDeclaredEscaping) { typeTable[Int($0)].asSource })")
		parts.append("parameters \(parameterOrder(of: DeclarationID(node)).map { labelTexts[Int($0)] })")
		return parts.joined(separator: "; ")
	}

	/// A variant's facts as text, by value: its family, its keys, its `@Sendable` mark, and each call's sources by the read
	/// they answer; what a mock passes `nil` is a fact of a place, not of a variant. Its outcomes are folded over the calls into it, which are
	/// compared apart (`outcomeCells(of:)`), and its parameters follow from its keys and its outcomes.
	func variantFacts(of variant: Int) -> String {
		var parts = ["\(variants.family(of: variant)) sendable \(variantBuildsInSendableFunction[variant])"]
		parts.append("keys \(seed(of: variant).keys.map { "\($0)" }.sorted())")
		for (edgeIndex, callee) in variants.callees(of: variant).enumerated() {
			let calleeReads = reads(of: declaration(of: callee)).map { readTable[Int($0)].description(labels: labelTexts) }
			let sources = sources(ofCall: edgeIndex, of: VariantID(variant)).map { source in
				switch source.kind {
				case .none, .passedThrough:
					"\(source.kind)"
				case .bound:
					"bound \(answerTexts[Int(source.answer)])"
				}
			}
			parts.append("call \(edgeIndex) \(zip(calleeReads, sources).map { "\($0): \($1)" }.sorted())")
		}
		return parts.joined(separator: "; ")
	}
}
