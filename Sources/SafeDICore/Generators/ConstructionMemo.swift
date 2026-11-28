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

/// The generators one pass of `Scope.createScopeGenerator` has finished, by what each was built from, so that a place
/// (a path to a scope) whose subtree would be built the same way reuses the generator an earlier place built.
///
/// A place's subtree is a function of its key and of what its subtree reads of the context above it: the stack of
/// properties being built, the nearest declarations of labels, and the parameters of the builder functions lazy cycles
/// close on. Each such read is logged with its answer and the depth of the scope whose declaration answered it, and a
/// place keeps the reads answered above it (`ConstructionLog.reads(answeredAbove:)`). Two places of one key whose
/// logged reads answer alike build the same subtree: the reads made in either build come in the same order up to the
/// first that differs, a read answered inside the subtree is answered by the same declaration in both, and a read
/// answered above it reads, at the other place, the context the other place inherits, which the log checks. So no read
/// differs, and the builds are equal.
///
/// A log is matched as a set of reads, each with its answer: a candidate is reused only when every read its log holds is
/// answered alike (`ConstructionLog.answeredAlike(in:)`), and the order decides only which read is asked first. A log is
/// not kept in the order its build made the reads: a place that reuses a child's generator takes the child's reads in
/// the order `answeredAlike(in:)` returns them, the reads of what a cycle closes on first, so two entries of one key can
/// hold alike reads in different orders, as the entries of the memo the mock roots share do on a module of twelve mocks.
/// So no lookup accepts a candidate on a matching prefix of its log, or compares two logs read by read in order.
///
/// A place is never stored or reused when it or anything in its subtree is a fill, is inside one, holds a hole, calls a
/// seam or public mock with holes, or is in a tree with seam holes, which read context this log does not cover. A
/// seam's or public mock's tree without holes is memoized, with a memo of its own: what it reads of its `SeamHoles` is
/// the same at every place of the tree, since `sitePath` is empty wherever `seamHoles` is. The memo lives for one pass,
/// so what is constant in a pass (the order a seam's places start in, the declared type names) is equal for every place
/// it compares. Only completed builds are stored: a pass that throws throws away its memo.
///
/// A memo shared across trees (`Sharing.acrossTrees`) carries every pass of each tree that finished to the trees created
/// after it with the same memo, which only the mock roots do: production trees keep a memo per tree. Each pass of a tree
/// starts from what the pass before held, so a later pass of one tree reuses a later pass of another where the two are
/// built from one generator of the pass before (a later pass's key names that generator) and read their context alike:
/// mock roots that reach one type in a lazy cycle reuse each other's first pass, so their second passes share it too. The
/// memo keeps alive every scope its keys name, and every generator and cycle parameter seed of a pass before that a key
/// can name, by holding each pass's tree and seed (`keepAlive(passTree:seed:)`), so no key names an object whose address
/// another object can take while the memo lives. A root's own place is never stored. A tree built with a seam root or a
/// mock root's builders reads its own `SeamHoles`, constant within the tree but not across trees, so it neither reads nor
/// keeps a shared memo. What is constant in a
/// pass of one tree and not across trees is either in the key (the flags) or kept to the tree (its `SeamHoles`, and the
/// start order of a tree with holes). The list of every input and stored value and why each is covered is
/// `.claude/rules/construction-memo.md`.
struct ConstructionMemo {
	/// Which trees a memo carries generators between.
	enum Sharing {
		/// Each tree's passes start empty, and nothing is kept once the tree is created.
		case perTree
		/// Each tree's first pass starts from what the trees created before it with this memo kept, and each later pass from
		/// what the pass before held.
		case acrossTrees
	}

	/// How `DependencyTreeGenerator` shares the memo between the mock roots it creates. Production trees always keep a
	/// memo per tree.
	@TaskLocal static var sharingBetweenMockRoots = Sharing.acrossTrees

	init(sharing: Sharing = .perTree) {
		self.sharing = sharing
	}

	let sharing: Sharing

	/// The memo a tree's pass starts from: for a tree's first pass, `nil`, this memo where it is shared across trees, and for a
	/// later pass, the memo the pass before held where this one is shared across trees. A memo per tree starts every pass
	/// empty.
	func memo(forPassAfter previousPassMemo: ConstructionMemo?) -> ConstructionMemo {
		switch sharing {
		case .perTree:
			ConstructionMemo()
		case .acrossTrees:
			previousPassMemo ?? self
		}
	}

	/// Keeps what the last pass of a tree that finished held, every pass before it included, when the memo is shared
	/// across trees.
	mutating func keepEntries(ofLastPass lastPassMemo: ConstructionMemo) {
		switch sharing {
		case .perTree:
			break
		case .acrossTrees:
			self = lastPassMemo
		}
	}

	/// Keeps alive `passTree`, a pass's tree, and `seed`, the cycle parameter seed it settled for the pass after it, which
	/// the keys of the pass after name (`Key.previousPassGenerator`, `Key.cycleParameterSeed`): a tree holds every
	/// generator of its pass, and a seed every seed of its children. Only a memo shared across trees, which keys of
	/// another tree can be looked up in after this tree's are released, needs them.
	mutating func keepAlive(passTree: ScopeGenerator, seed: CycleParameterSeed?) {
		switch sharing {
		case .perTree:
			break
		case .acrossTrees:
			passTrees.append(passTree)
			if let seed {
				seeds.append(seed)
			}
		}
	}

	/// What a place is built from besides the context it reads: compared whole.
	struct Key: Hashable {
		/// The scope the place builds, by its `ScopeRecord`.
		let scope: ObjectIdentifier
		/// The property the place builds, by its exact ID, which tells apart every two spellings generated code could write.
		let property: PropertyID
		let erasedToConcreteExistential: Bool
		let forMockGeneration: Bool
		let validatesForwardedProperties: Bool
		let buildsWithHandWrittenMocks: Bool
		/// Whether a declaration enclosing the tree holds a receive a mock passes `nil`
		/// (`NearestDeclarations.mayPassNil`): where none does, no place logs whether it passes one `nil`.
		let mayPassNil: Bool
		/// The received properties in scope at the place only as the instance of a `LazilyInstantiated` property.
		let lazilyInstantiatedInstanceProperties: Set<Property>
		let reboundProperties: Set<Property>
		/// The spellings of each property of the two sets, sorted, as UTF-8 bytes, one entry per set, which generated code
		/// spells as declared: `==` reads `any P` as `P`, so it alone would let a place reuse a generator that spells a
		/// property otherwise. Both sets are empty at nearly every place, so neither is interned.
		let spellings: [[UInt8]]
		/// The generator the pass before created for the place, whose children and findings the place's build reads. Two
		/// places of the pass before that shared a generator share it here too.
		let previousPassGenerator: ObjectIdentifier?
		/// The settled cycle parameters the place is built with (`CycleParameterSeed`), which it reads in place of what
		/// `previousPassGenerator` found, or `nil`.
		let cycleParameterSeed: ObjectIdentifier?

		/// This key with `previousPassGenerator` replaced.
		func withPreviousPassGenerator(_ previousPassGenerator: ObjectIdentifier?) -> Key {
			Key(
				scope: scope,
				property: property,
				erasedToConcreteExistential: erasedToConcreteExistential,
				forMockGeneration: forMockGeneration,
				validatesForwardedProperties: validatesForwardedProperties,
				buildsWithHandWrittenMocks: buildsWithHandWrittenMocks,
				mayPassNil: mayPassNil,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				reboundProperties: reboundProperties,
				spellings: spellings,
				previousPassGenerator: previousPassGenerator,
				cycleParameterSeed: cycleParameterSeed,
			)
		}
	}

	/// A finished place's generator, with the reads of the context above it its subtree made.
	struct Entry {
		let reads: ConstructionLog
		let generator: ScopeGenerator
		/// Whether the build found, everywhere in its subtree, what it read from the pass before: the same cycle parameters,
		/// loops of builders and fill struct labels. Building the place again from this generator then reads what the build
		/// read from the pass before, so it builds this generator again (see `settledReuse`).
		let isSettled: Bool
		/// The generator's `CycleClosingRedeclaredLabels`, which no generator keeps, for the parent of a place
		/// that reuses it to merge.
		let cycleClosingRedeclaredLabels: CycleClosingRedeclaredLabels
		/// The generators in the place's subtree, its own included, of calls of other modules' public mocks that pass fills
		/// (`ScopeGeneratorUnderConstruction.callGeneratorsBeneath`), each of which one tree holds at most once: a mock root's
		/// lowering keys a call's fills and builders by its generator (`MockLowering.FilledCallBuilders`), so a call generator at
		/// two places of one root would bind each of its fill places twice, and read one place's builder family at the other.
		let callGenerators: Set<ObjectIdentifier>
	}

	/// A reuse of an entry by another place: the entry, with the depths its reads are answered at in the place's context.
	struct Reuse {
		let entry: Entry
		let reads: ConstructionLog
	}

	/// The first entry of `key` whose reads `context` answers alike, with those reads as `context` answers them, or `nil`.
	/// A generator a sibling of the place holds is reused too: a scope tells its children apart by their indices.
	/// - Parameter draw: The sharing schedule's draw for this lookup, test only (`ConstructionSharingSchedule`): whether the
	///   place builds again, and the order the candidates are asked in.
	/// - Parameter callGeneratorsInTree: The call generators the tree already holds (`Entry.callGenerators`): an entry that
	///   holds one of them is not a candidate.
	func reuse(of key: Key, in context: ConstructionContext, besideCallGenerators callGeneratorsInTree: Set<ObjectIdentifier>, drawing draw: ConstructionSharingSchedule.Draw? = nil) -> Reuse? {
		guard let candidates = entriesByKey[key] else { return nil }
		func reuse(of entry: Entry) -> Reuse? {
			guard entry.callGenerators.isDisjoint(with: callGeneratorsInTree) else { return nil }
			return entry.reads.answeredAlike(in: context).map { Reuse(entry: entry, reads: $0) }
		}
		guard let draw else {
			// The places of one key differ mostly in what a cycle closes on or passes, the reads `answeredAlike(in:)` asks first,
			// which `context` answers the same for every candidate: so the candidates are found by following those answers
			// (`Candidates.entries(answeredAlikeBy:)`) rather than by asking each one. A candidate whose recorded answer to one
			// differs is never asked, as `answeredAlike(in:)` would set it aside at that read. The first candidate in the order
			// they were stored that `context` answers alike is reused, as before.
			let entries = candidates.entries(answeredAlikeBy: { context.answer($0).answer })
			GenerationWork.record(entries.count, by: .askingMemoCandidates)
			for entry in entries {
				if let reuse = reuse(of: entry) {
					return reuse
				}
			}
			return nil
		}
		return draw.reuse(among: candidates.entries, reuse)
	}

	/// The generator the pass before built settled at the place `key` names, when `key`'s other fields equal the key it was
	/// stored under and its reads are answered alike in `context`, with those reads as `context` answers them, or `nil`.
	///
	/// `key.previousPassGenerator` is that generator, `G`, which the pass before built from its own pass before's
	/// generator, `G′`. Settled, `G` holds everything a build reads from the pass before as `G′` held it (its cycle parameters
	/// and loops of builders, and its children, each settled in turn), so building the place from `G` takes the steps that
	/// building it from `G′` took, which built `G`: the key's other fields and the reads are what the memo compares within a
	/// pass. This memo is the pass before's.
	func settledReuse(of key: Key, in context: ConstructionContext) -> Reuse? {
		// A seeded place reads its cycle parameters from the seed, not from `G`.
		guard key.cycleParameterSeed == nil,
		      let previousPassGenerator = key.previousPassGenerator,
		      let (storedKey, entry) = entriesByGenerator[previousPassGenerator],
		      entry.isSettled,
		      storedKey == key.withPreviousPassGenerator(storedKey.previousPassGenerator),
		      let reads = entry.reads.answeredAlike(in: context)
		else { return nil }
		return Reuse(entry: entry, reads: reads)
	}

	/// Whether `generator` found the cycle parameters and loops of builders that `previousPassGenerator`, the generator the
	/// pass before built for its place, found, compared as a memo compares answers: by `==` and by spelling.
	/// - Parameter builtWithCycleParameters: The cycle parameters `generator`'s build read: `previousPassGenerator`'s, or a
	///   seed's in their place.
	static func foundAlike(by generator: ScopeGenerator, asBy previousPassGenerator: ScopeGenerator?, builtWithCycleParameters: [CycleParameter]) -> Bool {
		let loops = generator.receivedBuilderLoops
		let previousPassLoops = previousPassGenerator?.receivedBuilderLoops ?? ScopeGenerator.ReceivedBuilderLoops()
		return ConstructionLog.Answer.cycleParameterContext(generator.foundCycleParameters)
			.isAlike(.cycleParameterContext(builtWithCycleParameters))
			&& loops == previousPassLoops
			&& loops.reboundPropertiesByChildIndex.allSatisfy { index, properties in
				previousPassLoops.reboundPropertiesByChildIndex[index].map(properties.isSpelledAlike) ?? false
			}
	}

	/// Stores `entry` under `key`, keeping `scope`, the scope the key names, alive as long as the memo.
	mutating func store(_ entry: Entry, for key: Key, keepingAlive scope: ScopeRecord) {
		entriesByKey[key, default: Candidates()].append(entry)
		let generator = ObjectIdentifier(entry.generator)
		if entriesByGenerator[generator] == nil {
			entriesByGenerator[generator] = (key, entry)
		}
		keyedScopes.append(scope)
	}

	/// The entries of one key in the order they were stored. Once a key holds two, each is also filed under what its reads
	/// of the declaration a cycle closes on were answered, in the order its log asks them: most candidates of one key differ
	/// in those answers alone, and a tree with cycles stores a candidate for each set of declarations its place is built
	/// inside, so asking each candidate in turn made a lookup's work grow with the number stored.
	///
	/// A key's only entry is filed nowhere, since a lookup asks its log either way, and filing an entry lists every cycle
	/// read of its subtree: in a chain of places with one entry each, the lists grew with the square of the chain's length.
	private struct Candidates {
		/// A set of candidates whose first reads were answered alike: the candidates with no further read, and the nodes of
		/// the candidates that ask one.
		private struct Node {
			var candidates = [Int]()
			var next = Next.none
		}

		/// For each read a node's candidates ask next, the node of each answer recorded for it. Most nodes are followed by
		/// one read with one answer, which is held without a dictionary: a tree with cycles files a node for each read of
		/// each set of declarations a place is built inside.
		private enum Next {
			case none
			case one(read: ConstructionLog.Read, closedOn: PropertyID?, node: Int)
			case several([ConstructionLog.Read: [PropertyID?: Int]])
		}

		private(set) var entries = [Entry]()
		/// How many of `entries` are filed: none while the key holds one entry, all after.
		private var filedEntryCount = 0
		/// The first node holds every filed candidate before any read.
		private var nodes = [Node()]

		mutating func append(_ entry: Entry) {
			entries.append(entry)
			guard entries.count > 1 else { return }
			while filedEntryCount < entries.count {
				file(entries[filedEntryCount], at: filedEntryCount)
				filedEntryCount += 1
			}
		}

		private mutating func file(_ entry: Entry, at index: Int) {
			var node = 0
			var readCount = 0
			_ = entry.reads.forEachCycleRead { read, answer in
				readCount += 1
				switch answer {
				case let .declarationClosedOn(closedOn):
					node = nodeFollowing(node, at: read, answered: closedOn)
				case .cycleParameterContext, .nearestDeclaration, .binding, .passesNil:
					break
				}
				return true
			}
			GenerationWork.record(readCount, by: .filingMemoEntryReads)
			nodes[node].candidates.append(index)
		}

		/// The node of the candidates of `node` that ask `read` next and were answered `closedOn`, added when no candidate
		/// was yet.
		private mutating func nodeFollowing(_ node: Int, at read: ConstructionLog.Read, answered closedOn: PropertyID?) -> Int {
			switch nodes[node].next {
			case .none:
				nodes[node].next = .one(read: read, closedOn: closedOn, node: nodes.count)
			case let .one(onlyRead, onlyClosedOn, onlyNode):
				if onlyRead == read, onlyClosedOn == closedOn {
					return onlyNode
				} else {
					var nodeByAnswerByRead = [onlyRead: [onlyClosedOn: onlyNode]]
					nodeByAnswerByRead[read, default: [:]][closedOn] = nodes.count
					nodes[node].next = .several(nodeByAnswerByRead)
				}
			case var .several(nodeByAnswerByRead):
				if let next = nodeByAnswerByRead[read]?[closedOn] {
					return next
				} else {
					nodes[node].next = .none
					nodeByAnswerByRead[read, default: [:]][closedOn] = nodes.count
					nodes[node].next = .several(nodeByAnswerByRead)
				}
			}
			nodes.append(Node())
			return nodes.count - 1
		}

		/// The entries, in the order they were stored, whose every read of the declaration a cycle closes on `contextAnswer`
		/// answers as recorded; a key's only entry, whose reads are filed nowhere, whatever it answers.
		func entries(answeredAlikeBy contextAnswer: (ConstructionLog.Read) -> ConstructionLog.Answer) -> [Entry] {
			guard filedEntryCount > 0 else { return entries }
			var indices = [Int]()
			// Candidates can ask their reads in different orders, so a node can hold several next reads, each followed: the
			// indices found are sorted, so the order the reads are followed in reaches nothing.
			var nodesToVisit = [0]
			while let node = nodesToVisit.popLast() {
				indices.append(contentsOf: nodes[node].candidates)
				switch nodes[node].next {
				case .none:
					break
				case let .one(read, closedOn, next):
					if contextAnswer(read) == .declarationClosedOn(closedOn) {
						nodesToVisit.append(next)
					}
				case let .several(nodeByAnswerByRead):
					for (read, nodeByAnswer) in nodeByAnswerByRead {
						if case let .declarationClosedOn(closedOn) = contextAnswer(read), let next = nodeByAnswer[closedOn] {
							nodesToVisit.append(next)
						}
					}
				}
			}
			return indices.sorted().map { entries[$0] }
		}
	}

	private var entriesByKey = [Key: Candidates]()
	/// Each stored generator with the key and entry it was first stored under.
	private var entriesByGenerator = [ObjectIdentifier: (key: Key, entry: Entry)]()
	/// The scope identities `entriesByKey`'s keys name, kept so that no other identity can take one's address.
	private var keyedScopes = [ScopeRecord]()
	/// The trees and seeds of passes that a later pass's keys can name (`keepAlive(passTree:seed:)`), kept so that no other
	/// generator or seed can take one's address.
	private var passTrees = [ScopeGenerator]()
	private var seeds = [CycleParameterSeed]()

	/// The memo the memo oracle's build with the memo shares across the trees created with this memo
	/// (`ConstructionMemoOracle`).
	var oracleMemo: ConstructionMemo {
		get {
			var oracleMemo = ConstructionMemo(sharing: .acrossTrees)
			oracleMemo.entriesByKey = oracleEntriesByKey
			oracleMemo.entriesByGenerator = oracleEntriesByGenerator
			oracleMemo.keyedScopes = oracleKeyedScopes
			oracleMemo.passTrees = oraclePassTrees
			oracleMemo.seeds = oracleSeeds
			return oracleMemo
		}
		set {
			oracleEntriesByKey = newValue.entriesByKey
			oracleEntriesByGenerator = newValue.entriesByGenerator
			oracleKeyedScopes = newValue.keyedScopes
			oraclePassTrees = newValue.passTrees
			oracleSeeds = newValue.seeds
		}
	}

	private var oracleEntriesByKey = [Key: Candidates]()
	private var oracleEntriesByGenerator = [ObjectIdentifier: (key: Key, entry: Entry)]()
	private var oracleKeyedScopes = [ScopeRecord]()
	private var oraclePassTrees = [ScopeGenerator]()
	private var oracleSeeds = [CycleParameterSeed]()

	/// Whether `Scope.createScopeGenerator` reuses the generators of places it already built. Turned off only by the memo
	/// oracle, which compares the trees built with and without it.
	@TaskLocal static var isEnabled = true
}

/// The context a place of a tree inherits from the scopes above it, which its subtree reads (see `ConstructionMemo`).
struct ConstructionContext {
	/// The declarations being built above the place.
	let contextStack: ContextStack
	/// What the IDs of `contextStack` and of the reads project.
	let interner: ConstructionInterner
	let nearestDeclarations: NearestDeclarations
	let cycleParameterContexts: [ScopeGenerator.BuiltDeclaration: CycleParameterContext]

	/// The answer `context` gives `read`, with the depth of the scope whose declaration gives it.
	func answer(_ read: ConstructionLog.Read) -> (answer: ConstructionLog.Answer, depth: Int) {
		switch read {
		case let .nearestDeclaration(label):
			let (declaration, depth) = nearestDeclarations.resolving(label)
			return (.nearestDeclaration(declaration), depth)
		case let .binding(property), let .cycleArgumentBinding(property):
			let (binding, depth) = nearestDeclarations.resolvingBinding(of: property)
			return (.binding(binding), depth)
		case let .declarationClosedOn(property, concreteType):
			let closedOn = contextStack.entryClosedOn(byPropertyID: property, concreteTypeID: concreteType, interner: interner)
			return (.declarationClosedOn(closedOn?.entry.propertyID), closedOn?.entry.depth ?? -1)
		case let .cycleParameterContext(declaration):
			let context = cycleParameterContexts[declaration]
			return (.cycleParameterContext(context?.parameters), context?.depth ?? -1)
		case let .passesNil(property, dependency, receivingType):
			let (passesNil, depth) = nearestDeclarations.resolvingPassesNil(to: property, receivedBy: dependency, on: receivingType)
			return (.passesNil(passesNil), depth)
		}
	}
}

/// What a place's subtree read of the context above it, deduplicated by read (see `ConstructionMemo`).
struct ConstructionLog {
	/// A read of a place's context.
	enum Read: Hashable {
		/// The nearest declaration of a label, read whole (`NearestDeclarations.build(_:)` adds to it).
		case nearestDeclaration(String)
		/// The binding a receive of a property only if available reads (`NearestDeclarations.resolvingBinding(of:)`).
		case binding(Property)
		/// The binding a scope passes a parameter of the builder function a lazy cycle closes on that nothing requires,
		/// read as `binding` is and answered alike. It is a read of its own because it asks for what a cycle passes: the
		/// function's body may read none of it, where a declaration of the label inside the function hides the parameter.
		case cycleArgumentBinding(Property)
		/// The declaration a scope building a property for a concrete type closes a cycle on, if any, by their IDs.
		case declarationClosedOn(PropertyID, TypeID)
		/// The parameters of the builder function built for a declaration that a lazy cycle closes on, if any.
		case cycleParameterContext(ScopeGenerator.BuiltDeclaration)
		/// Whether a mock passes `nil` to a receive of a property only if available, by a dependency on a concrete type
		/// (`NearestDeclarations.resolvingPassesNil(to:receivedBy:on:)`).
		case passesNil(Property, Dependency, TypeDescription)

		/// Whether this read asks what a cycle closes on or passes: what most places of one key differ in.
		var isCycleRead: Bool {
			switch self {
			case .nearestDeclaration, .binding, .cycleArgumentBinding, .passesNil:
				false
			case .declarationClosedOn, .cycleParameterContext:
				true
			}
		}
	}

	/// The answer to a `Read`. Two answers are alike when the synthesized `==` of everything a generator is built from,
	/// diagnostics' payload included, holds, since a reused generator carries that payload into what it reports, and when
	/// every type they hold is spelled alike, since `==` reads `any P` as `P` and generated code spells each as declared:
	/// alike answers must build equal generators, not only equal code.
	enum Answer: Equatable {
		case nearestDeclaration(NearestDeclaration?)
		case binding(Property?)
		/// The ID of the declaration's property: the declaration is built for the concrete type the read names, and an ID
		/// is one spelling, so equal IDs are alike.
		case declarationClosedOn(PropertyID?)
		case cycleParameterContext([CycleParameter]?)
		case passesNil(Bool)

		func isAlike(_ other: Self) -> Bool {
			guard self == other else { return false }
			// `==` holds, so each property of one answer has exactly one `==` counterpart in the other, which it must be
			// spelled as: a `Set` or `Dictionary` holds no two properties `==` merges. `==` holds only between answers of one
			// case, so each arm's `guard` binds `other` as that case, and its `else` runs on no input.
			switch self {
			case let .nearestDeclaration(declaration):
				guard case let .nearestDeclaration(otherDeclaration) = other else { return false }
				guard let declaration, let otherDeclaration, !declaration.isUnchangedCopy(of: otherDeclaration) else { return true }
				return declaration.bindings.allSatisfy { key, value in
					guard let index = otherDeclaration.bindings.index(forKey: key) else { return false }
					let (otherKey, otherValue) = otherDeclaration.bindings[index]
					return key.isSpelledAlike(otherKey) && value.isSpelledAlike(otherValue)
				} && declaration.formsBeingBuilt.isSpelledAlike(otherDeclaration.formsBeingBuilt)
			case let .binding(property):
				guard case let .binding(otherProperty) = other else { return false }
				guard let property, let otherProperty else { return true }
				return property.isSpelledAlike(otherProperty)
			case let .cycleParameterContext(parameters):
				guard case let .cycleParameterContext(otherParameters) = other else { return false }
				guard let parameters, let otherParameters else { return true }
				return zip(parameters, otherParameters).allSatisfy { parameter, otherParameter in
					parameter.property.isSpelledAlike(otherParameter.property)
						&& parameter.receiver.property.isSpelledAlike(otherParameter.receiver.property)
						&& zip(parameter.receiver.chain, otherParameter.receiver.chain).allSatisfy { $0.isSpelledAlike($1) }
						&& parameter.redeclaration.property.isSpelledAlike(otherParameter.redeclaration.property)
						&& parameter.redeclaration.declaringType.isSpelledAlike(otherParameter.redeclaration.declaringType)
						&& parameter.receivedForms.isSpelledAlike(otherParameter.receivedForms)
						&& parameter.requiredForms.isSpelledAlike(otherParameter.requiredForms)
						&& parameter.requiredAliasFulfillingForms.isSpelledAlike(otherParameter.requiredAliasFulfillingForms)
						&& parameter.onlyIfAvailableUnwrappedForms.isSpelledAlike(otherParameter.onlyIfAvailableUnwrappedForms)
				}
			case .declarationClosedOn, .passesNil:
				// `==` holds, so the other answer names the same ID, which is one spelling, or passes `nil` exactly when this
				// one does.
				return true
			}
		}
	}

	/// - Parameter recording: Whether the log keeps what it is told: `false` for a place whose reads no memo entry can hold
	///   (`ScopeGeneratorUnderConstruction.recordsReads`), which keeps nothing.
	init(recording: Bool = true) {
		isRecording = recording
	}

	/// A log of `reads`, in order, each a distinct read.
	private init(reads: [RecordedRead]) {
		isRecording = true
		ownReads = reads
	}

	/// Records that `read` was answered `answer` by the declaration of the scope at `depth`, -1 for one above the tree.
	/// A read is kept once for each depth that answers it: a scope can read a label above itself and its child read it
	/// again where the scope declares it, and only the first answer tells another place's context apart.
	mutating func record(_ read: Read, answer: Answer, depth: Int) {
		guard isRecording else { return }
		let key = AnsweredRead(read: read, depth: depth)
		if ownReadsRecorded.insert(key).inserted {
			ownReads.append(RecordedRead(read: key, answer: answer))
		}
	}

	/// The reads of this log answered above the scope at `depth`. They are not copied: the result refers to this log's
	/// reads, frozen in a segment, and leaves out those answered at `depth` or below whenever it is read. A place's
	/// subtree holds a read for each scope beneath it, and every place above keeps the ones answered above it, so copying
	/// them made the logs of a chain of n places hold n²/2 reads.
	func reads(answeredAbove depth: Int) -> Self {
		var reads = Self()
		let allParts = allParts
		guard !allParts.isEmpty else { return reads }
		// A short log is copied, so that the many candidates a short log is asked to tell apart read one array, as a log did
		// before segments; only a long one, whose copies grow with the square of a chain, is frozen in a segment.
		if let readsAbove = Self.distinctReads(of: allParts, answeredAbove: depth, upTo: Self.copiedReadLimit) {
			ConstructionLogStorage.record(readsAbove.count)
			if !readsAbove.isEmpty {
				reads.parts = [.reads(readsAbove)]
			}
			return reads
		}
		let segment = Segment(parts: allParts)
		ConstructionLogStorage.record(segment.storedElementCount)
		if segment.shallowestDepth < depth {
			reads.parts = [.segment(segment, answeredAbove: depth)]
		}
		return reads
	}

	/// Adds `log`'s reads to this log's, after the reads it has: a read both hold keeps this log's answer.
	mutating func formUnion(_ log: Self) {
		guard isRecording else { return }
		closeOwnReads()
		parts.append(contentsOf: log.parts)
		if !log.ownReads.isEmpty {
			parts.append(.reads(log.ownReads))
		}
	}

	/// These reads as `context` answers them, or `nil` when `context` answers one otherwise.
	func answeredAlike(in context: ConstructionContext) -> Self? {
		// Most candidates differ in some read, so the answers are kept in an array until every read is answered alike.
		// The reads that tell most candidates apart, which closes a cycle and on what, are asked first, so a candidate that
		// differs is set aside after a read or two.
		var answers = [RecordedRead]()
		for asksCycleReads in [true, false] {
			let isAnsweredAlike = forEachRead(where: { $0.isCycleRead == asksCycleReads }) { recorded in
				let (answer, depth) = context.answer(recorded.read.read)
				guard answer.isAlike(recorded.answer) else { return false }
				// An alike answer at the same depth keeps the recorded read, which a fresh read would equal for every later
				// lookup: `isAlike` is the synthesized `==`, diagnostic payload included, and alike spellings, both transitive,
				// and a log's answers are read only by `isAlike`. The `==` here is identity for reuse, not a comparison for
				// meaning: the payload it includes only makes fewer answers alike, so fewer places reuse a generator.
				answers.append(depth == recorded.read.depth ? recorded : RecordedRead(read: AnsweredRead(read: recorded.read.read, depth: depth), answer: answer))
				return true
			}
			guard isAnsweredAlike else { return nil }
		}
		// Two reads that differ only in the depth that answered them are one read here, with one answer.
		var readsKept = Set<AnsweredRead>()
		readsKept.reserveCapacity(answers.count)
		return Self(reads: answers.filter { readsKept.insert($0.read).inserted })
	}

	/// Calls `body` with each read of what a cycle closes on or passes, the reads `answeredAlike(in:)` asks first, in the
	/// order it asks them, each with its recorded answer, until `body` returns `false`. A context whose answer to one is
	/// not `==` the recorded one answers the log otherwise (`Answer.isAlike` requires `==`).
	/// - Returns: Whether `body` returned `true` for every read.
	func forEachCycleRead(_ body: (Read, Answer) -> Bool) -> Bool {
		forEachRead(where: \.isCycleRead) { body($0.read.read, $0.answer) }
	}

	/// Calls `body` with each read of this log, in the order the reads were added, each read and depth once, with the first
	/// answer it was added with and the depth that answered it: what a test observes of a place (`TypeFactsObservation`).
	func forEachRead(_ body: (_ read: Read, _ answer: Answer, _ depth: Int) -> Void) {
		_ = forEachRead(where: { _ in true }) { recorded in
			body(recorded.read.read, recorded.answer, recorded.read.depth)
			return true
		}
	}

	/// The labels of the reads of this log that are no cycle reads: what a place's subtree asked of the declarations above
	/// it (`PlaceReadsObservation`).
	var labelsOfReadsOfDeclarations: Set<String> {
		var labels = Set<String>()
		_ = forEachRead(where: { _ in true }) { recorded in
			switch recorded.read.read {
			case let .nearestDeclaration(label):
				labels.insert(label)
			case let .binding(property), let .passesNil(property, _, _):
				labels.insert(property.label)
			case .declarationClosedOn, .cycleParameterContext, .cycleArgumentBinding:
				break
			}
			return true
		}
		return labels
	}

	/// Calls `body` with each read of this log whose kind `isIncluded` admits, in the order the reads were added, each read
	/// (and depth) once, with the first answer it was added with, until `body` returns `false`.
	/// - Returns: Whether `body` returned `true` for every read.
	private func forEachRead(where isIncluded: (Read) -> Bool, _ body: (RecordedRead) -> Bool) -> Bool {
		// Most candidates are set aside after a read or two, and most logs are one run of distinct reads: a log this one
		// recorded or answered alike, or a short one a place kept as a copy. Their reads are read in place, with no stack
		// and no set of the reads visited, which cost more than the reads.
		if let reads = distinctReadsInOneRun {
			for recorded in reads where isIncluded(recorded.read.read) {
				guard body(recorded) else { return false }
			}
			return true
		}
		var readsVisited = Set<AnsweredRead>()
		// A segment refers to the segments of the places beneath it, which can be as deep as the module has types, so the
		// walk keeps a stack of its own rather than recursing.
		var stack = [(parts: allParts, index: 0, answeredAbove: Int.max)]
		while let frame = stack.last {
			guard frame.index < frame.parts.count else {
				stack.removeLast()
				continue
			}
			stack[stack.count - 1].index += 1
			switch frame.parts[frame.index] {
			case let .reads(reads):
				for recorded in reads where recorded.read.depth < frame.answeredAbove && isIncluded(recorded.read.read) {
					guard readsVisited.insert(recorded.read).inserted else { continue }
					guard body(recorded) else { return false }
				}
			case let .segment(segment, answeredAbove):
				let answeredAbove = min(answeredAbove, frame.answeredAbove)
				if segment.shallowestDepth < answeredAbove {
					stack.append((segment.parts, 0, answeredAbove))
				}
			}
		}
		return true
	}

	/// This log's reads when they are one run of distinct reads, every one of which a walk reads: the one part of reads a
	/// place's copy (`reads(answeredAbove:)`) holds, or the reads it recorded.
	private var distinctReadsInOneRun: [RecordedRead]? {
		let allParts = allParts
		guard allParts.count == 1, case let .reads(reads) = allParts[0] else {
			return allParts.isEmpty ? [] : nil
		}
		return reads
	}

	/// The most reads a place's log keeps as a copy (`reads(answeredAbove:)`).
	private static let copiedReadLimit = 32

	/// The reads of `parts` answered above `depth`, in order, each read (and depth) once with the first answer it was added
	/// with, or `nil` when there are more than `limit`.
	private static func distinctReads(of parts: [Part], answeredAbove depth: Int, upTo limit: Int) -> [RecordedRead]? {
		var reads = [RecordedRead]()
		var readsVisited = Set<AnsweredRead>()
		var stack = [(parts: parts, index: 0, answeredAbove: depth)]
		while let frame = stack.last {
			guard frame.index < frame.parts.count else {
				stack.removeLast()
				continue
			}
			stack[stack.count - 1].index += 1
			switch frame.parts[frame.index] {
			case let .reads(partReads):
				for recorded in partReads where recorded.read.depth < frame.answeredAbove && readsVisited.insert(recorded.read).inserted {
					guard reads.count < limit else { return nil }
					reads.append(recorded)
				}
			case let .segment(segment, answeredAbove):
				let answeredAbove = min(answeredAbove, frame.answeredAbove)
				if segment.shallowestDepth < answeredAbove {
					stack.append((segment.parts, 0, answeredAbove))
				}
			}
		}
		return reads
	}

	/// The reads this log was told, in order: its parts, then the reads recorded since its last part.
	private var allParts: [Part] {
		var allParts = parts
		if !ownReads.isEmpty {
			allParts.append(.reads(ownReads))
		}
		return allParts
	}

	/// Ends the run of reads recorded since the last part, so that what is added next follows them.
	private mutating func closeOwnReads() {
		guard !ownReads.isEmpty else { return }
		parts.append(.reads(ownReads))
		ownReads = []
	}

	/// A read, with the depth of the scope whose declaration answered it (-1 above the tree).
	private struct AnsweredRead: Hashable {
		let read: Read
		let depth: Int
	}

	/// A read with its answer, held by reference: a log's reads are copied into every log that takes them, and a
	/// reference copies as one retain where the read and its answer copied every field.
	private final class RecordedRead: Sendable {
		init(read: AnsweredRead, answer: Answer) {
			self.read = read
			self.answer = answer
		}

		let read: AnsweredRead
		let answer: Answer
	}

	/// A run of a log's reads, in the order they were added.
	private enum Part {
		/// Reads recorded or added one by one.
		case reads([RecordedRead])
		/// The reads of another log, answered above `answeredAbove`: what a place keeps of a child's log.
		case segment(Segment, answeredAbove: Int)
	}

	/// The reads a log held when a place kept those answered above it (`reads(answeredAbove:)`), frozen, so that every
	/// place above it, and the memo entry of the place, refers to them rather than copying them. It holds immutable values
	/// only. It lives as long as the memo entry or the log of a place above that refers to it: for one pass, and for the
	/// memo shared by the mock roots, as long as that memo.
	private final class Segment: Sendable {
		/// The parts of this segment, in order. A part refers to the segment of a place beneath, so segments form a chain
		/// as deep as the tree, which the slot releases one level at a time (`DeferredReleaseSlot`).
		var parts: [Part] {
			partsSlot.value
		}

		private let partsSlot: DeferredReleaseSlot<[Part]>

		/// The shallowest depth that answered a read of `parts`, `Int.max` for none, so a walk that leaves out every read
		/// answered at or below a depth skips a segment that holds none above it.
		let shallowestDepth: Int

		init(parts: [Part]) {
			partsSlot = DeferredReleaseSlot(parts)
			var shallowestDepth = Int.max
			for part in parts {
				switch part {
				case let .reads(reads):
					for recorded in reads {
						shallowestDepth = min(shallowestDepth, recorded.read.depth)
					}
				case let .segment(segment, answeredAbove):
					if segment.shallowestDepth < answeredAbove {
						shallowestDepth = min(shallowestDepth, segment.shallowestDepth)
					}
				}
			}
			self.shallowestDepth = shallowestDepth
		}

		/// The elements this segment adds to what the logs hold: each read it holds itself, and each segment it refers to.
		var storedElementCount: Int {
			parts.reduce(0) { count, part in
				switch part {
				case let .reads(reads):
					count + reads.count
				case .segment:
					count + 1
				}
			}
		}
	}

	/// The parts of this log before `ownReads`, in order.
	private var parts = [Part]()
	/// The reads recorded since the last part, in order.
	private var ownReads = [RecordedRead]()
	/// The reads `ownReads` holds, and those recorded before it, so that each is recorded once. A log a place keeps
	/// (`reads(answeredAbove:)`) holds none.
	private var ownReadsRecorded = Set<AnsweredRead>()
	private let isRecording: Bool
}

extension Property {
	/// The label and the type as declared (see `ConstructionLog.Answer`).
	private var spelling: String {
		"\(label): \(typeDescription.asSource)"
	}

	/// The spellings of each set's properties, one entry per set, for a construction memo's key (see `ConstructionMemo.Key`).
	static func spellingsForConstructionMemo(of propertySets: Set<Property>...) -> [[UInt8]] {
		var spellings = [[UInt8]]()
		for properties in propertySets {
			spellings.append(Array(properties.map(\.spelling).sortedByUTF8().joined(separator: ",").utf8))
		}
		return spellings
	}
}

extension Property {
	/// Whether `other`, which `==` equates with this property, is spelled as it is, byte for byte.
	fileprivate func isSpelledAlike(_ other: Property) -> Bool {
		label.utf8.elementsEqual(other.label.utf8) && typeDescription.isSpelledAlike(other.typeDescription)
	}
}

extension TypeDescription {
	/// Whether `other`, which `==` equates with this type, is spelled as it is, byte for byte.
	fileprivate func isSpelledAlike(_ other: TypeDescription) -> Bool {
		isBuiltAlike(other) || asSource.utf8.elementsEqual(other.asSource.utf8)
	}

	/// Whether `other` is built of the same cases and names as this type, so that it is spelled alike without either
	/// spelling being made. `false` for a pair this does not compare, which `isSpelledAlike` then spells.
	fileprivate func isBuiltAlike(_ other: TypeDescription) -> Bool {
		switch (self, other) {
		case let (.simple(name, generics), .simple(otherName, otherGenerics)):
			name.utf8.elementsEqual(otherName.utf8) && generics.isBuiltAlike(otherGenerics)
		case let (.nested(name, parentType, generics), .nested(otherName, otherParentType, otherGenerics)):
			name.utf8.elementsEqual(otherName.utf8) && parentType.isBuiltAlike(otherParentType) && generics.isBuiltAlike(otherGenerics)
		case let (.optional(wrapped), .optional(otherWrapped)),
		     let (.any(wrapped), .any(otherWrapped)),
		     let (.some(wrapped), .some(otherWrapped)),
		     let (.array(wrapped), .array(otherWrapped)):
			wrapped.isBuiltAlike(otherWrapped)
		case (.simple, _), (.nested, _), (.optional, _), (.any, _), (.some, _), (.array, _), (.void, _), (.composition, _), (.implicitlyUnwrappedOptional, _), (.metatype, _), (.attributed, _), (.dictionary, _), (.tuple, _), (.closure, _), (.variadic, _), (.unknown, _):
			false
		}
	}
}

extension [TypeDescription] {
	/// Whether each of `other`'s types is built as this array's type at its index (see `TypeDescription.isBuiltAlike`).
	fileprivate func isBuiltAlike(_ other: [TypeDescription]) -> Bool {
		count == other.count && zip(self, other).allSatisfy { $0.isBuiltAlike($1) }
	}
}

extension Set<Property> {
	/// Whether `other`, which `==` equates with this set, spells each property as this set does.
	fileprivate func isSpelledAlike(_ other: Set<Property>) -> Bool {
		allSatisfy { property in
			other.firstIndex(of: property).map { property.isSpelledAlike(other[$0]) } ?? false
		}
	}
}

extension [String] {
	/// The strings in the order of their UTF-8 bytes. `String`'s `==` and `<` read canonically equivalent spellings as one,
	/// which generated code spells as declared, so spellings a memo compares are compared and ordered by their bytes.
	fileprivate func sortedByUTF8() -> [String] {
		sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
	}
}

/// The memo oracle's hook: test only.
public enum ConstructionMemoOracle {
	/// Called each time `Scope.createScopeGenerator` creates a tree, with two more builds of it, neither of which starts
	/// its code: one with the construction memo, shared across the trees created with one memo, and one without it. The
	/// two must hold the same data on every path. The build without the memo walks every place, which `typeFacts` holds
	/// beside the tree's graph of per-type facts, for the test to compare.
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable (_ treeBuiltWithMemo: any Sendable, _ treeBuiltWithoutMemo: any Sendable, _ typeFacts: TypeFactsReport) -> Void>?

	/// Whether `DependencyTreeGenerator` creates its mock roots in reverse type order, so that a memo shared between them
	/// carries other trees' generators to each; what it generates must not change.
	@TaskLocal public static var buildsMockRootsInReverseOrder = false

	/// Called with the concrete type of each place `Scope.createScopeGenerator` keys and looks up in a construction memo,
	/// when set: by the tests, never by the tool. The oracle's own builds are not reported.
	@TaskLocal public static var keyedPlaceObserver: TaskLocalFunction<@Sendable (_ concreteType: String) -> Void>?

	/// Called with the concrete type of each place `Scope.createScopeGenerator` reuses from a construction memo within a
	/// pass, and whether the pass is a tree's first, when set: by the tests, never by the tool. The oracle's own builds are
	/// not reported.
	@TaskLocal public static var reusedPlaceObserver: TaskLocalFunction<@Sendable (_ concreteType: String, _ isFirstPass: Bool) -> Void>?
}

/// What a place's log keeps of the reads its subtree made: the elements each place adds to what the logs and the memo
/// hold when it keeps the reads answered above it (`ConstructionLog.reads(answeredAbove:)`). Copying those reads made a
/// chain of places hold reads that grew with the square of its depth; the tests count the elements to check that they
/// grow with the places. Handed to `observer`, which the tests set, never the tool.
public enum ConstructionLogStorage {
	/// Called with the elements each place's kept log adds, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable (Int) -> Void>?

	/// Hands `observer`, when set, the elements a place's kept log adds.
	static func record(_ elementCount: Int) {
		if let observer {
			observer(elementCount)
		}
	}
}
