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

/// The mock worlds' shared graph: one `TypeFactsGraph` over the shareable declarations (`MockWorldsTable`) the module's
/// mock worlds call into, rooted at each world's frontier in turn, whose variants start from the worlds' calls into it
/// (`TypeFactsGraph.Seed`), so a body two worlds call with one key is one variant. It pins nothing and holds no place,
/// which the table's exclusions make true of every declaration in it, so it conforms as any world's graph does
/// (`NodeRecordSources`), with one root per seed.
///
/// Per world it keeps the calls the world makes into it, each with the shared variant it lands on, and, for each shared
/// declaration the world reaches, the parents the world reaches it through, in the world's order: a top declaration by
/// its table ID, a shared one by its position in the shared graph.
///
/// Built only where a test observes the mock worlds' sharing, from each world built whole, whose calls into the shared
/// declarations are the seeds. It holds the shared graph's columns and the worlds' calls and parents for as long as
/// `generateMockCode` keeps it: one run's mock generation.
struct MockWorldsSharedGraph: Sendable {
	/// - Parameters:
	///   - table: The module's mock worlds' table.
	///   - worldsBuiltWhole: Each world's graph built from its root, in the table's order of worlds.
	init(table: MockWorldsTable, worldsBuiltWhole: [TypeFactsGraph]) {
		var roots = [TypeFactsDeclaration]()
		var topByWorld = [Set<Int32>]()
		for world in 0..<table.worldCount {
			roots.append(contentsOf: table.frontierDeclarations(ofWorld: world).map(table.declaration(ofID:)))
			topByWorld.append(Set(table.topDeclarations(ofWorld: world)))
		}
		// Each world's node is shared where the table does not keep it in the world's own graph.
		let isSharedByWorld = zip(worldsBuiltWhole, topByWorld).map { world, top in
			world.graph.nodes.map { declaration in table.declarationID(of: declaration).map { !top.contains($0) } ?? false }
		}
		var seeds = [TypeFactsGraph.Seed]()
		var callsByWorld = [[(caller: Int32, edgeIndex: Int, callee: Int32, seed: Int)]]()
		for (world, isShared) in zip(worldsBuiltWhole, isSharedByWorld) {
			var calls = [(caller: Int32, edgeIndex: Int, callee: Int32, seed: Int)]()
			for variant in 0..<world.variants.count where !isShared[Int(world.variants.node(of: variant))] {
				let node = Int(world.variants.node(of: variant))
				for (edgeIndex, callee) in world.variants.callees(of: variant).enumerated() where isShared[Int(world.graph.edgeTargets[world.graph.edgeOffset(of: node) + edgeIndex])] {
					calls.append((Int32(variant), edgeIndex, callee, seeds.count))
					seeds.append(world.seed(of: Int(callee)))
				}
			}
			callsByWorld.append(calls)
		}
		let graph = TypeFactsGraph(roots: roots, forMockGeneration: true, mockRootNames: MockRootNames(), seeds: seeds)
		self.graph = graph
		worlds = zip(worldsBuiltWhole, zip(isSharedByWorld, callsByWorld)).map { world, sharedAndCalls in
			let (isShared, calls) = sharedAndCalls
			var parentsByDeclaration = [(declaration: Int32, parents: [Parent])]()
			for (node, declaration) in world.graph.nodes.enumerated() where isShared[node] {
				guard let sharedNode = graph.graph.index(of: declaration) else { continue }
				let parents = world.parents(of: node).map { parent -> Parent in
					let parentDeclaration = world.graph.nodes[Int(parent.parent)]
					if isShared[Int(parent.parent)], let sharedParent = graph.graph.index(of: parentDeclaration) {
						return .shared(Int32(sharedParent))
					} else {
						return .top(table.declarationID(of: parentDeclaration) ?? -1)
					}
				}
				parentsByDeclaration.append((Int32(sharedNode), parents))
			}
			return World(
				frontierCalls: calls.map { FrontierCall(caller: $0.caller, edgeIndex: $0.edgeIndex, worldCallee: $0.callee, sharedVariant: graph.variants.seedVariants[$0.seed]) },
				parentsByDeclaration: parentsByDeclaration,
			)
		}
	}

	/// A parent a world reaches a shared declaration through: a declaration of its own graph, by its table ID, or one of
	/// the shared graph, by its position there.
	enum Parent: Hashable, Sendable {
		case top(Int32)
		case shared(Int32)
	}

	/// A call a world's top declaration makes into the shared graph: the world's calling variant and the index of its
	/// edge, the variant the world built whole calls there, and the shared variant the call's seed is.
	struct FrontierCall: Hashable, Sendable {
		let caller: Int32
		let edgeIndex: Int
		let worldCallee: Int32
		let sharedVariant: Int32
	}

	/// What one world takes from the shared graph.
	struct World: Sendable {
		/// The world's calls into the shared graph, in its variants' order, each variant's in edge order.
		let frontierCalls: [FrontierCall]
		/// Each shared declaration the world reaches, by its position in the shared graph, in the order the world first
		/// reaches them, with the parents the world reaches it through, in the world's order of edges.
		let parentsByDeclaration: [(declaration: Int32, parents: [Parent])]
	}

	/// The shared graph.
	let graph: TypeFactsGraph
	/// Each world's calls and parents, in the table's order of worlds.
	let worlds: [World]
}
