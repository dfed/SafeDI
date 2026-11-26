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

/// Where the answer a call hands its callee for one read comes from.
struct AnswerSource: Equatable, Sendable {
	enum Kind: UInt8, Sendable {
		/// Nothing answers the read: no declaration above binds it.
		case none
		/// The caller binds the read at the call's edge, with the declaration `payload` names.
		case bound
		/// The caller's own answer to the same read, at the position `payload` names in the caller's run of answers.
		case passedThrough
	}

	static let none = AnswerSource(kind: .none, payload: -1)

	static func bound(_ declaration: Int32) -> AnswerSource {
		AnswerSource(kind: .bound, payload: declaration)
	}

	static func passedThrough(_ position: Int32) -> AnswerSource {
		AnswerSource(kind: .passedThrough, payload: position)
	}

	let kind: Kind
	let payload: Int32
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
/// Every fact is a column of 32-bit IDs: a variant's node, family and run of answers (one per read of its node's
/// reads from above, in read order), and for each of its node's edges in order the variant it calls and the run of
/// sources of what that call hands. A variant's ID is its position, in the order the worklist first makes it, so it
/// orders deterministically with no sort. It holds those columns for as long as its owner keeps it.
struct TypeFactsVariants: Sendable {
	/// - Parameters:
	///   - rootAnswer: What answers each read of the root's reads from above: a seam's parameter, or `nil` for none.
	///   - binding: What a node binds for a read of the edge's target at the edge (the edge's position among every node's
	///     edges, `OrderedGraph.edgeOffset(of:)` plus its index), or `nil` where it binds nothing for it there and the
	///     caller's own answer passes through.
	///   - family: The family a call at the edge builds its callee in, given the caller's.
	///   - key: The value of an answer to a read that a variant is told apart by. The two parameter rules live here: a
	///     difference a parameter can carry projects to one key.
	init(
		graph: OrderedGraph<some Hashable & Sendable>,
		reads: ReadsFromAbove,
		rootAnswer: (_ read: Int32) -> VariantBinding?,
		binding: (_ edge: Int, _ read: Int32) -> VariantBinding?,
		family: (_ edge: Int, _ callerFamily: VariantFamily) -> VariantFamily,
		key: (_ read: Int32, _ answer: Int32) -> Int32,
	) {
		var columns = Columns()
		var bucketByHash = [Int: Int32]()
		var nextInBucket = [Int32]()
		var scratchAnswers = [Int32]()
		var scratchKeys = [Int32]()
		var scratchSources = [AnswerSource]()
		var work = 0

		/// The variant of `node` in `family` with the scratch answers, made if no variant has its key.
		func variant(of node: Int32, family: VariantFamily) -> Int32 {
			var hasher = Hasher()
			hasher.combine(node)
			hasher.combine(family)
			for key in scratchKeys {
				hasher.combine(key)
			}
			let hash = hasher.finalize()
			var candidate = bucketByHash[hash] ?? -1
			while candidate >= 0 {
				if columns.matches(Int(candidate), node: node, family: family, keys: scratchKeys) {
					return candidate
				}
				candidate = nextInBucket[Int(candidate)]
			}
			let made = columns.append(node: node, family: family, answers: scratchAnswers, keys: scratchKeys)
			nextInBucket.append(bucketByHash[hash] ?? -1)
			bucketByHash[hash] = made
			return made
		}

		reads.rows.forEachColumn(inRow: 0) { read, _ in
			let answer = rootAnswer(read)
			scratchAnswers.append(answer?.answer ?? -1)
			scratchKeys.append(key(read, answer?.answer ?? -1))
			columns.rootSources.append(answer.map { .bound($0.declaration) } ?? .none)
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
				scratchAnswers.removeAll(keepingCapacity: true)
				scratchKeys.removeAll(keepingCapacity: true)
				scratchSources.removeAll(keepingCapacity: true)
				reads.rows.forEachColumn(inRow: Int(target)) { read, _ in
					work += 1
					let answer: Int32
					if let bound = binding(edge, read) {
						answer = bound.answer
						scratchSources.append(.bound(bound.declaration))
					} else if let position = reads.rows.rank(of: read, inRow: node) {
						answer = columns.answer(ofVariant: caller, at: position)
						scratchSources.append(.passedThrough(Int32(position)))
					} else {
						answer = -1
						scratchSources.append(.none)
					}
					scratchAnswers.append(answer)
					scratchKeys.append(key(read, answer))
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
		isInline = columns.nodes.indices.map { variant in
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

	/// The answers the variant was made with, one per read of its node's reads from above, in read order.
	func answers(of variant: Int) -> ArraySlice<Int32> {
		columns.answers[Int(columns.answerOffsets[variant])..<Int(columns.answerOffsets[variant + 1])]
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

	/// Whether each variant is built in line in the body of the one variant that calls it, rather than as a function:
	/// the root is not, nor is a variant called more than once or whose node is on a cycle.
	let isInline: [Bool]

	/// The reads of edges' targets the worklist answered, summed over the variants it walked, for a test to count how its
	/// work grows.
	let work: Int

	/// The 32-bit elements the variants hold, for a test to count per variant and per call.
	var columnElementCount: Int {
		columns.nodes.count * 2 + columns.answers.count * 2 + columns.answerOffsets.count + columns.callees.count + columns.callOffsets.count + columns.sources.count * 2 + columns.sourceOffsets.count
	}

	private struct Columns {
		var nodes = [Int32]()
		var families = [VariantFamily]()
		var answerOffsets: [Int32] = [0]
		var answers = [Int32]()
		var keys = [Int32]()
		var callOffsets = [Int32]()
		var callees = [Int32]()
		var sourceOffsets = [Int32]()
		var sources = [AnswerSource]()
		var rootSources = [AnswerSource]()

		func answer(ofVariant variant: Int, at position: Int) -> Int32 {
			answers[Int(answerOffsets[variant]) + position]
		}

		func matches(_ variant: Int, node: Int32, family: VariantFamily, keys candidateKeys: [Int32]) -> Bool {
			guard nodes[variant] == node, families[variant] == family else {
				return false
			}
			let start = Int(answerOffsets[variant])
			let end = Int(answerOffsets[variant + 1])
			guard end - start == candidateKeys.count else {
				return false
			}
			for offset in 0..<candidateKeys.count where keys[start + offset] != candidateKeys[offset] {
				return false
			}
			return true
		}

		mutating func append(node: Int32, family: VariantFamily, answers newAnswers: [Int32], keys newKeys: [Int32]) -> Int32 {
			nodes.append(node)
			families.append(family)
			answers.append(contentsOf: newAnswers)
			keys.append(contentsOf: newKeys)
			answerOffsets.append(Int32(answers.count))
			return Int32(nodes.count - 1)
		}
	}

	private let columns: Columns
}
