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
/// A place is never stored or reused when it or anything in its subtree is a fill, is inside one, holds a hole, calls a
/// seam or public mock with holes, or is in a tree with seam holes, which read context this log does not cover. A
/// seam's or public mock's tree without holes is memoized, with a memo of its own: what it reads of its `SeamHoles` is
/// the same at every place of the tree, since `sitePath` is empty wherever `seamHoles` is. The memo lives for one pass,
/// so what is constant in a pass (the order a seam's places start in, the declared type names) is equal for every place
/// it compares. Only completed builds are stored: a pass that throws throws away its memo.
///
/// A memo shared across trees (`Sharing.acrossTrees`) carries the first pass of each tree that finished to the trees
/// created after it with the same memo, which only the mock roots do: production trees keep a memo per tree. A first
/// pass's keys name no generator of a pass before, and the memo keeps alive every scope its keys name, so no key names an
/// object whose address another object can take while the memo lives. A root's own place is never stored. A tree built
/// with a seam root or a mock root's builders reads its own `SeamHoles`, constant within the tree but not across trees,
/// so it neither reads nor keeps a shared memo. A first pass starts each generator's code as it creates it, so every
/// generator a later tree reuses has started. What is constant in a pass of one tree and not across trees is either in
/// the key (the flags) or kept to the tree (its `SeamHoles`, and the start order of a tree with holes). The list of every
/// input and stored value and why each is covered is `.claude/rules/construction-memo.md`.
struct ConstructionMemo {
	/// Which trees a memo carries generators between.
	enum Sharing {
		/// Each tree's passes start empty, and nothing is kept once the tree is created.
		case perTree
		/// Each tree's first pass starts from what the trees created before it with this memo kept.
		case acrossTrees
	}

	/// How `DependencyTreeGenerator` shares the memo between the mock roots it creates. Production trees always keep a
	/// memo per tree.
	@TaskLocal static var sharingBetweenMockRoots = Sharing.acrossTrees

	init(sharing: Sharing = .perTree) {
		self.sharing = sharing
	}

	let sharing: Sharing

	/// The memo a tree's first pass starts from.
	var memoForFirstPass: ConstructionMemo {
		switch sharing {
		case .perTree:
			ConstructionMemo()
		case .acrossTrees:
			self
		}
	}

	/// Keeps what the first pass of a tree that finished stored, when the memo is shared across trees.
	mutating func keepEntries(ofFirstPass firstPassMemo: ConstructionMemo) {
		switch sharing {
		case .perTree:
			break
		case .acrossTrees:
			entriesByKey = firstPassMemo.entriesByKey
			keyedScopes = firstPassMemo.keyedScopes
		}
	}

	/// What a place is built from besides the context it reads: compared whole.
	struct Key: Hashable {
		/// The scope the place builds.
		let scope: ObjectIdentifier
		let property: Property
		let erasedToConcreteExistential: Bool
		let forMockGeneration: Bool
		let startsCodeGeneration: Bool
		let validatesForwardedProperties: Bool
		let buildsWithHandWrittenMocks: Bool
		/// The received properties in scope at the place only as the instance of a `LazilyInstantiated` property.
		let lazilyInstantiatedInstanceProperties: Set<Property>
		let reboundProperties: Set<Property>
		/// The spellings of `property`'s type and of each property of the two sets, sorted, which generated code spells as
		/// declared: `==` reads `any P` as `P`, so it alone would let a place reuse a generator that spells its property
		/// otherwise.
		let spellings: [String]
		/// The generator the pass before created for the place, whose children and findings the place's build reads. Two
		/// places of the pass before that shared a generator share it here too.
		let previousPassGenerator: ObjectIdentifier?
	}

	/// A finished place's generator, with the reads of the context above it its subtree made and its scope count, which
	/// the place's parent counts as its own child's.
	struct Entry {
		let reads: ConstructionLog
		let generator: ScopeGenerator
		let subtreeScopeCount: Int
	}

	/// A reuse of an entry by another place: the entry, with the depths its reads are answered at in the place's context.
	struct Reuse {
		let entry: Entry
		let reads: ConstructionLog
	}

	/// The first entry of `key` whose reads `context` answers alike, with those reads as `context` answers them, or `nil`.
	/// An entry whose generator is among `siblings`, the generators of the place's siblings, is never reused: a scope's
	/// children are told apart by their generators (a mock root can list one property twice).
	func reuse(of key: Key, in context: ConstructionContext, besides siblings: Set<ObjectIdentifier>) -> Reuse? {
		guard let candidates = entriesByKey[key] else { return nil }
		for entry in candidates where !siblings.contains(ObjectIdentifier(entry.generator)) {
			if let reads = entry.reads.answeredAlike(in: context) {
				return Reuse(entry: entry, reads: reads)
			}
		}
		return nil
	}

	/// Stores `entry` under `key`, keeping `scope`, the scope the key names, alive as long as the memo.
	mutating func store(_ entry: Entry, for key: Key, keepingAlive scope: Scope) {
		entriesByKey[key, default: []].append(entry)
		keyedScopes.append(scope)
	}

	private var entriesByKey = [Key: [Entry]]()
	/// The scopes `entriesByKey`'s keys name by identity, kept so that no other scope can take one's address.
	private var keyedScopes = [Scope]()

	/// The memo the memo oracle's build with the memo shares across the trees created with this memo
	/// (`ConstructionMemoOracle`).
	var oracleMemo: ConstructionMemo {
		get {
			var oracleMemo = ConstructionMemo(sharing: .acrossTrees)
			oracleMemo.entriesByKey = oracleEntriesByKey
			oracleMemo.keyedScopes = oracleKeyedScopes
			return oracleMemo
		}
		set {
			oracleEntriesByKey = newValue.entriesByKey
			oracleKeyedScopes = newValue.keyedScopes
		}
	}

	private var oracleEntriesByKey = [Key: [Entry]]()
	private var oracleKeyedScopes = [Scope]()

	/// Whether `Scope.createScopeGenerator` reuses the generators of places it already built. Turned off only by the memo
	/// oracle, which compares the trees built with and without it.
	@TaskLocal static var isEnabled = true
}

/// The context a place of a tree inherits from the scopes above it, which its subtree reads (see `ConstructionMemo`).
struct ConstructionContext {
	/// The properties being built above the place, innermost first.
	let propertyStack: [Property]
	/// The concrete types the properties of `propertyStack` are built for, beside it.
	let concreteTypeStack: [TypeDescription]
	/// The depth in the tree of the scope that put each entry of `propertyStack` on it, beside it.
	let depthStack: [Int]
	let nearestDeclarations: NearestDeclarations
	let cycleParameterContexts: [ScopeGenerator.BuiltDeclaration: CycleParameterContext]

	/// The declaration a scope that builds `property` for `concreteType` repeats, when it closes a cycle, with its index on
	/// `propertyStack` and the depth of the scope that built it: the innermost entry of the same property as cycle
	/// validation sees it (a lazily instantiated property as the constant it stands for), built for the same concrete type,
	/// and, where that entry is a lazily instantiated declaration's instance, the declaration, which the same scope put on
	/// the stack just outside it.
	func declarationClosedOn(by property: Property, concreteType: TypeDescription) -> (declaration: ScopeGenerator.BuiltDeclaration, index: Int, depth: Int)? {
		let validatedProperty = property.asValidatedForDependencyCycles
		guard let entryIndex = propertyStack.indices.first(where: {
			propertyStack[$0].asValidatedForDependencyCycles == validatedProperty && concreteTypeStack[$0] == concreteType
		}) else { return nil }
		let index = propertyStack.indices.contains(entryIndex + 1) && propertyStack[entryIndex + 1].asLazilyInstantiatedInstanceProperty == propertyStack[entryIndex] ? entryIndex + 1 : entryIndex
		return (ScopeGenerator.BuiltDeclaration(property: propertyStack[index], concreteType: concreteType), index, depthStack[index])
	}

	/// The answer `context` gives `read`, with the depth of the scope whose declaration gives it.
	func answer(_ read: ConstructionLog.Read) -> (answer: ConstructionLog.Answer, depth: Int) {
		switch read {
		case let .nearestDeclaration(label):
			let (declaration, depth) = nearestDeclarations.resolving(label)
			return (.nearestDeclaration(declaration), depth)
		case let .binding(property):
			let (binding, depth) = nearestDeclarations.resolvingBinding(of: property)
			return (.binding(binding), depth)
		case let .declarationClosedOn(property, concreteType):
			let closedOn = declarationClosedOn(by: property, concreteType: concreteType)
			return (.declarationClosedOn(closedOn?.declaration), closedOn?.depth ?? -1)
		case let .cycleParameterContext(declaration):
			let context = cycleParameterContexts[declaration]
			return (.cycleParameterContext(context?.parameters), context?.depth ?? -1)
		}
	}
}

/// What a place's subtree read of the context above it, deduplicated by read (see `ConstructionMemo`).
struct ConstructionLog {
	/// A read of a place's context.
	enum Read: Hashable {
		/// The nearest declaration of a label, read whole (`NearestDeclarations.build(_:)` adds to it).
		case nearestDeclaration(String)
		/// The binding a receive of a property only if available reads (`NearestDeclarations.binding(of:)`).
		case binding(Property)
		/// The declaration a scope building a property for a concrete type closes a cycle on, if any.
		case declarationClosedOn(Property, TypeDescription)
		/// The parameters of the builder function built for a declaration that a lazy cycle closes on, if any.
		case cycleParameterContext(ScopeGenerator.BuiltDeclaration)
	}

	/// The answer to a `Read`. Two answers are alike when the synthesized `==` of everything a generator is built from,
	/// diagnostics' payload included, holds, since a reused generator carries that payload into what it reports, and when
	/// every type they hold is spelled alike, since `==` reads `any P` as `P` and generated code spells each as declared:
	/// alike answers must build equal generators, not only equal code.
	enum Answer: Equatable {
		case nearestDeclaration(NearestDeclaration?)
		case binding(Property?)
		case declarationClosedOn(ScopeGenerator.BuiltDeclaration?)
		case cycleParameterContext([CycleParameter]?)

		func isAlike(_ other: Self) -> Bool {
			self == other && spellings == other.spellings
		}

		/// The spelling of every type the answer holds, in an order that depends only on the answer.
		private var spellings: [String] {
			switch self {
			case let .nearestDeclaration(declaration):
				guard let declaration else { return [] }
				return declaration.bindings.map { "\($0.key.spelling)=\($0.value.spelling)" }.sorted()
					+ declaration.formsBeingBuilt.map(\.spelling).sorted()
			case let .binding(property):
				return property.map { [$0.spelling] } ?? []
			case let .declarationClosedOn(declaration):
				return declaration.map { [$0.property.spelling, $0.concreteType.asSource] } ?? []
			case let .cycleParameterContext(parameters):
				return (parameters ?? []).flatMap { parameter in
					var spellings = [parameter.property.spelling, parameter.receiver.property.spelling, parameter.redeclaration.property.spelling, parameter.redeclaration.declaringType.asSource]
					spellings += parameter.receiver.chain.map(\.asSource)
					for forms in [parameter.receivedForms, parameter.requiredForms, parameter.requiredAliasFulfillingForms, parameter.onlyIfAvailableUnwrappedForms] {
						spellings.append(forms.map(\.spelling).sorted().joined(separator: ","))
					}
					return spellings
				}
			}
		}
	}

	/// Records that `read` was answered `answer` by the declaration of the scope at `depth`, -1 for one above the tree.
	/// A read is kept once for each depth that answers it: a scope can read a label above itself and its child read it
	/// again where the scope declares it, and only the first answer tells another place's context apart.
	mutating func record(_ read: Read, answer: Answer, depth: Int) {
		let key = AnsweredRead(read: read, depth: depth)
		if answersByRead[key] == nil {
			answersByRead[key] = answer
		}
	}

	/// The reads of this log answered above the scope at `depth`.
	func reads(answeredAbove depth: Int) -> Self {
		var reads = Self()
		for (read, answer) in answersByRead where read.depth < depth {
			reads.answersByRead[read] = answer
		}
		return reads
	}

	/// Adds `log`'s reads to this log's.
	mutating func formUnion(_ log: Self) {
		if answersByRead.isEmpty {
			answersByRead = log.answersByRead
		} else {
			answersByRead.merge(log.answersByRead) { existing, _ in existing }
		}
	}

	/// These reads as `context` answers them, or `nil` when `context` answers one otherwise.
	func answeredAlike(in context: ConstructionContext) -> Self? {
		var reads = Self()
		for (read, answered) in answersByRead {
			let (answer, depth) = context.answer(read.read)
			guard answer.isAlike(answered) else { return nil }
			reads.answersByRead[AnsweredRead(read: read.read, depth: depth)] = answer
		}
		return reads
	}

	/// A read, with the depth of the scope whose declaration answered it (-1 above the tree).
	private struct AnsweredRead: Hashable {
		let read: Read
		let depth: Int
	}

	private var answersByRead = [AnsweredRead: Answer]()
}

extension Property {
	/// The label and the type as declared (see `ConstructionLog.Answer`).
	fileprivate var spelling: String {
		"\(label): \(typeDescription.asSource)"
	}

	/// The spellings of `property`'s and `properties`' types, for a construction memo's key (see `ConstructionMemo.Key`).
	static func spellingsForConstructionMemo(of property: Property, _ propertySets: Set<Property>...) -> [String] {
		var spellings = [property.spelling]
		for properties in propertySets where !properties.isEmpty {
			spellings.append(properties.map(\.spelling).sorted().joined(separator: ","))
		}
		return spellings
	}
}

/// The memo oracle's hook: test only.
public enum ConstructionMemoOracle {
	/// Called each time `Scope.createScopeGenerator` creates a tree, with two more builds of it, neither of which starts
	/// its code: one with the construction memo, shared across the trees created with one memo, and one without it. The
	/// two must hold the same data on every path.
	@TaskLocal public static var observer: (@Sendable (_ treeBuiltWithMemo: any Sendable, _ treeBuiltWithoutMemo: any Sendable) -> Void)?

	/// Whether `DependencyTreeGenerator` creates its mock roots in reverse type order, so that a memo shared between them
	/// carries other trees' generators to each; what it generates must not change.
	@TaskLocal public static var buildsMockRootsInReverseOrder = false
}
