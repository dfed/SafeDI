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

/// Whether a body is built in plain code or inside a `@Sendable` function: what a variant is built in, beside its
/// answers.
enum VariantFamily: UInt8, Sendable {
	case plain
	case sendable
}

/// Where the answer a call hands its callee for one read comes from: the only per-call answer, since a variant keeps only
/// the key its callers share.
struct AnswerSource: Equatable, Sendable {
	enum Kind: UInt8, Sendable {
		/// Nothing answers the read: no declaration above binds it.
		case none
		/// The caller binds the read at the call's edge, with the declaration `payload` names, answering `answer`.
		case bound
		/// The caller's own answer to the same read, at the position `payload` names in the caller's run of keys.
		case passedThrough
	}

	static let none = AnswerSource(kind: .none, payload: -1, answer: -1)

	static func bound(_ declaration: Int32, answer: Int32) -> AnswerSource {
		AnswerSource(kind: .bound, payload: declaration, answer: answer)
	}

	static func passedThrough(_ position: Int32) -> AnswerSource {
		AnswerSource(kind: .passedThrough, payload: position, answer: -1)
	}

	let kind: Kind
	let payload: Int32
	/// The answer a bound source gives, as the caller interns it; -1 for the others, whose answer is the caller's own,
	/// found through the calls into the caller.
	let answer: Int32
}

/// What a node binds for a read at one of its edges: the answer by value, as the caller interns it (form, whether it is
/// still being built, `nil`), and the declaration that gives it.
struct VariantBinding: Equatable, Sendable {
	let answer: Int32
	let declaration: Int32
}

/// The bodies of a world: one variant per (node, family, answers to the node's reads from above, as `key` projects
/// them), found by a worklist from the root. A call edge hands its callee the caller's answers, replaced by what the
/// caller binds at that edge, projected onto the callee's reads; a key met again is the variant made before, which is
/// where a recursive type closes. It ends because answers are compared by value, never by the declaration that gave
/// them, and each node has finitely many.
///
/// Every fact is a column of 32-bit IDs: a variant's node, family and run of keys (one per read of its node's reads from
/// above, in read order: what its callers' answers share, never one caller's answer), and for each of its node's edges in order the variant it calls and the run of
/// sources of what that call hands. A variant's ID is its position, in the order the worklist first makes it, so it
/// orders deterministically with no sort. It holds those columns for as long as its owner keeps it.
struct TypeFactsVariants: Sendable {
	/// The bucket of a variant's key: its node, family and keys hashed.
	static func hash(_ node: Int32, _ family: VariantFamily, _ keys: [Int32]) -> Int {
		var hasher = Hasher()
		hasher.combine(node)
		hasher.combine(family)
		for key in keys {
			hasher.combine(key)
		}
		return hasher.finalize()
	}

	/// - Parameters:
	///   - rootAnswer: What answers each read of the root's reads from above: a seam's parameter, or `nil` for none.
	///   - binding: What a node binds for a read of the edge's target at the edge (the edge's position among every node's
	///     edges, `OrderedGraph.edgeOffset(of:)` plus its index), or `nil` where it binds nothing for it there and the
	///     caller's own answer passes through.
	///   - family: The family a call at the edge builds its callee in, given the caller's. A world whose bodies are one per
	///     node whatever encloses them (production: `@Sendable` is a mark folded over call edges)
	///     returns the caller's, so the root's `.plain` reaches every node; only seam contracts and mocks whose parameter
	///     types differ by family key on it.
	///   - key: The value of an answer to a read that a variant is told apart by, at a call of `target` (the root's own
	///     reads: 0). The two parameter rules live here: a difference a parameter can carry projects to one key. It is applied once, to an answer a call binds or to -1 for
	///     none, never to a key a call passes through, so it need not be idempotent: a key collapsed at one call reaches
	///     every callee below unchanged.
	init(
		graph: OrderedGraph<some Hashable & Sendable>,
		reads: ReadsFromAbove,
		rootAnswer: (_ read: Int32) -> VariantBinding?,
		binding: (_ edge: Int, _ read: Int32) -> VariantBinding?,
		family: (_ edge: Int, _ callerFamily: VariantFamily) -> VariantFamily,
		key: (_ read: Int32, _ answer: Int32, _ target: Int32) -> Int32,
		bucket: (_ node: Int32, _ family: VariantFamily, _ keys: [Int32]) -> Int = TypeFactsVariants.hash,
	) {
		var columns = Columns()
		var bucketByHash = [Int: Int32]()
		var nextInBucket = [Int32]()
		var scratchKeys = [Int32]()
		var scratchSources = [AnswerSource]()
		var work = 0

		/// The variant of `node` in `family` with the scratch answers, made if no variant has its key.
		func variant(of node: Int32, family: VariantFamily) -> Int32 {
			let hash = bucket(node, family, scratchKeys)
			var candidate = bucketByHash[hash] ?? -1
			while candidate >= 0 {
				if columns.matches(Int(candidate), node: node, family: family, keys: scratchKeys) {
					return candidate
				}
				candidate = nextInBucket[Int(candidate)]
			}
			let made = columns.append(node: node, family: family, keys: scratchKeys)
			nextInBucket.append(bucketByHash[hash] ?? -1)
			bucketByHash[hash] = made
			return made
		}

		reads.rows.forEachColumn(inRow: 0) { read, _ in
			let answer = rootAnswer(read)
			scratchKeys.append(key(read, answer?.answer ?? -1, 0))
			columns.rootSources.append(answer.map { .bound($0.declaration, answer: $0.answer) } ?? .none)
		}
		_ = variant(of: 0, family: .plain)
		var next = 0
		while next < columns.nodes.count {
			let caller = next
			next += 1
			let node = Int(columns.nodes[caller])
			let callerFamily = columns.families[caller]
			columns.callOffsets.append(Int32(columns.callees.count))
			for (edgeIndex, target) in graph.edges(from: node).enumerated() {
				let edge = graph.edgeOffset(of: node) + edgeIndex
				scratchKeys.removeAll(keepingCapacity: true)
				scratchSources.removeAll(keepingCapacity: true)
				reads.rows.forEachColumn(inRow: Int(target)) { read, _ in
					work += 1
					if let bound = binding(edge, read) {
						scratchKeys.append(key(read, bound.answer, target))
						scratchSources.append(.bound(bound.declaration, answer: bound.answer))
					} else if let position = reads.rows.rank(of: read, inRow: node) {
						// The caller's key, as it is: an answer its callers share, which is all a body shared by them can
						// hand on. It is a key already, so `key` is never applied to it again.
						scratchKeys.append(columns.key(ofVariant: caller, at: position))
						scratchSources.append(.passedThrough(Int32(position)))
					} else {
						scratchKeys.append(key(read, -1, target))
						scratchSources.append(.none)
					}
				}
				columns.sourceOffsets.append(Int32(columns.sources.count))
				columns.sources.append(contentsOf: scratchSources)
				let callee = variant(of: target, family: family(edge, callerFamily))
				columns.callees.append(callee)
			}
		}
		columns.callOffsets.append(Int32(columns.callees.count))
		columns.sourceOffsets.append(Int32(columns.sources.count))
		var callsOfVariant = [Int32](repeating: 0, count: columns.nodes.count)
		for callee in columns.callees {
			callsOfVariant[Int(callee)] += 1
		}
		isCalledOnce = columns.nodes.indices.map { variant in
			variant != 0 && callsOfVariant[variant] == 1 && !graph.isOnCycle(Int(columns.nodes[variant]))
		}
		self.columns = columns
		self.work = work
	}

	var count: Int {
		columns.nodes.count
	}

	func node(of variant: Int) -> Int32 {
		columns.nodes[variant]
	}

	func family(of variant: Int) -> VariantFamily {
		columns.families[variant]
	}

	/// The keys every call into the variant shares, one per read of its node's reads from above, in read order. Not any
	/// one caller's answer, which only `sources(ofCall:)` gives.
	func keys(of variant: Int) -> ArraySlice<Int32> {
		columns.keys[Int(columns.keyOffsets[variant])..<Int(columns.keyOffsets[variant + 1])]
	}

	/// The variant each of the variant's node's edges calls, in edge order.
	func callees(of variant: Int) -> ArraySlice<Int32> {
		columns.callees[Int(columns.callOffsets[variant])..<Int(columns.callOffsets[variant + 1])]
	}

	/// Where each answer a call hands its callee comes from, in the callee's read order: `call` is the call's position
	/// among every variant's calls, `callOffset(of:)` plus the edge's index.
	func sources(ofCall call: Int) -> ArraySlice<AnswerSource> {
		columns.sources[Int(columns.sourceOffsets[call])..<Int(columns.sourceOffsets[call + 1])]
	}

	func callOffset(of variant: Int) -> Int {
		Int(columns.callOffsets[variant])
	}

	/// What answers each read of the root variant: a seam root's parameters, or none.
	var rootSources: [AnswerSource] {
		columns.rootSources
	}

	/// Whether each variant is called by exactly one call and its node is on no cycle: a fact the layout may use later to
	/// build it in line. It is not whether a body is a function, which today's layout decides by its own rule
	/// (`BuiltPlaceRecord.hasFunction`).
	let isCalledOnce: [Bool]

	/// The reads of edges' targets the worklist answered, summed over the variants it walked, for a test to count how its
	/// work grows.
	let work: Int

	/// The 32-bit elements the variants hold, for a test to count per variant and per call.
	var columnElementCount: Int {
		columns.nodes.count * 2 + columns.keys.count + columns.keyOffsets.count + columns.callees.count + columns.callOffsets.count + columns.sources.count * 3 + columns.sourceOffsets.count
	}

	private struct Columns {
		var nodes = [Int32]()
		var families = [VariantFamily]()
		var keyOffsets: [Int32] = [0]
		var keys = [Int32]()
		var callOffsets = [Int32]()
		var callees = [Int32]()
		var sourceOffsets = [Int32]()
		var sources = [AnswerSource]()
		var rootSources = [AnswerSource]()

		func key(ofVariant variant: Int, at position: Int) -> Int32 {
			keys[Int(keyOffsets[variant]) + position]
		}

		func matches(_ variant: Int, node: Int32, family: VariantFamily, keys candidateKeys: [Int32]) -> Bool {
			guard nodes[variant] == node, families[variant] == family else {
				return false
			}
			// One node's variants all hold one key per read of the node's reads from above, so the runs are of one length.
			let start = Int(keyOffsets[variant])
			for offset in 0..<candidateKeys.count where keys[start + offset] != candidateKeys[offset] {
				return false
			}
			return true
		}

		mutating func append(node: Int32, family: VariantFamily, keys newKeys: [Int32]) -> Int32 {
			nodes.append(node)
			families.append(family)
			keys.append(contentsOf: newKeys)
			keyOffsets.append(Int32(keys.count))
			return Int32(nodes.count - 1)
		}
	}

	private let columns: Columns
}
