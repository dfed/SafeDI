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

/// What each variant of a world uses for each of its reads from above: `nil`, a statement of the root's body that its
/// function captures, that statement read into a local before a `@Sendable` function that could not capture it, or a
/// parameter. It is the type key's `computeOutcomes` taken over the call edges between
/// variants instead of over the places of a tree, so that it costs one join per source of a call edge, however many
/// paths reach a variant.
///
/// Each cell, one per (variant, read), climbs a lattice once: unknown, then `nil` or one statement, then a parameter. A
/// call edge offers each read of its callee a candidate: `nil`; the statement the caller binds at the edge, which a
/// function can capture only when the caller's body is the root's; or the caller's own outcome for the read, passed
/// through. Two candidates that differ give a parameter, so two parents that each bind `id` share a variant whose
/// function takes `id`, and `nil` against a value is an `Optional` parameter (rule 1). The root's own reads are offered
/// by a call of the root from itself, so a seam's parameter is a statement of the root's body. The result does not
/// depend on the order the worklist visits cells, since a join is commutative.
///
/// Everything here is a 32-bit ID or a flag in a flat array: no file of the fold names a model of the source.
struct TypeFactsOutcomes: Sendable {
	init(_ input: Input) {
		let variantCount = input.readOffsets.count - 1
		let readOffsets = input.readOffsets
		let callOffsets = input.callOffsets
		let sourceOffsets = input.sourceOffsets
		let callees = input.callees

		// Which variants’ bodies are the root’s: the root’s, and the body of a variant every call of which builds it in the
		// body of a caller whose body is the root’s. A graph with no root, the mock worlds’ shared graph, has none: its
		// bodies are called from outside it.
		var bodyIsRoot = [Bool](repeating: input.hasRoot, count: variantCount)
		var outsideRoot = [Int32]()
		for call in callees.indices where !input.buildsInCallersBody[call] && callees[call] != 0 && bodyIsRoot[Int(callees[call])] {
			bodyIsRoot[Int(callees[call])] = false
			outsideRoot.append(callees[call])
		}
		while let caller = outsideRoot.popLast() {
			for callee in callees[Int(callOffsets[Int(caller)])..<Int(callOffsets[Int(caller) + 1])]
				where callee != 0 && bodyIsRoot[Int(callee)]
			{
				bodyIsRoot[Int(callee)] = false
				outsideRoot.append(callee)
			}
		}

		/// Each call with its caller, callee, edge and the run of its sources: first the root’s call of itself with the
		/// world’s sources, which are never still being built, at no edge.
		let rootSourcesAreBeingBuilt = [Bool](repeating: false, count: input.rootSources.count)
		func forEachCall(_ body: (_ caller: Int, _ callee: Int, _ edge: Int32, _ sources: ArraySlice<AnswerSource>, _ isBeingBuilt: ArraySlice<Bool>) -> Void) {
			if input.hasRoot {
				body(0, 0, -1, input.rootSources[...], rootSourcesAreBeingBuilt[...])
			}
			for caller in 0..<variantCount {
				for call in Int(callOffsets[caller])..<Int(callOffsets[caller + 1]) {
					let run = Int(sourceOffsets[call])..<Int(sourceOffsets[call + 1])
					body(caller, Int(callees[call]), input.callEdges[call], input.sources[run], input.sourceIsBeingBuilt[run])
				}
			}
		}

		var cells = Cells(rules: input.cellRules, readOffsets: readOffsets, families: input.families)

		// The callee cells that each caller cell feeds through a source that passes it through, as runs per caller cell.
		var dependentOffsets = [Int32](repeating: 0, count: cells.count + 1)
		forEachCall { caller, _, _, sources, _ in
			for source in sources where source.kind == .passedThrough {
				dependentOffsets[Int(readOffsets[caller] + source.payload) + 1] += 1
			}
		}
		for cell in 0..<cells.count {
			dependentOffsets[cell + 1] += dependentOffsets[cell]
		}
		var dependents = [Int32](repeating: 0, count: Int(dependentOffsets[cells.count]))
		var dependentEdges = dependents
		var nextDependent = dependentOffsets
		forEachCall { caller, callee, edge, sources, isBeingBuilt in
			for (read, (source, isBeingBuilt)) in zip(sources, isBeingBuilt).enumerated() {
				let cell = Int(readOffsets[callee]) + read
				switch source.kind {
				case .none:
					cells.join(.none, into: cell, through: edge)
				case .bound:
					cells.join(bodyIsRoot[caller] && !isBeingBuilt ? .statement(source.payload) : .parameter, into: cell, through: edge)
				case .passedThrough:
					let callerCell = Int(readOffsets[caller] + source.payload)
					dependents[Int(nextDependent[callerCell])] = Int32(cell)
					dependentEdges[Int(nextDependent[callerCell])] = edge
					nextDependent[callerCell] += 1
				}
			}
		}

		// A call from outside the graph offers each read of the variant it reaches the outcome its caller's graph found.
		// The seeds tell variants apart by the class of what each read is offered (`TypeFactsVariants.Seed`), and a
		// statement of a caller's root body is one statement whichever world offers it, so no join here changes an outcome.
		for (variant, offered) in input.seedOutcomes {
			for (read, outcome) in offered.enumerated() {
				cells.join(outcome, into: Int(readOffsets[Int(variant)]) + read, through: -1)
			}
		}

		while let cell = cells.nextChanged() {
			let outcome = cells.outcomes[cell]
			for index in Int(dependentOffsets[cell])..<Int(dependentOffsets[cell + 1]) {
				cells.join(outcome, into: Int(dependents[index]), through: dependentEdges[index])
			}
		}

		self.readOffsets = readOffsets
		forms = cells.outcomes.map(\.form)
		declarations = cells.outcomes.map(\.declaration)
		boundBefore = cells.outcomes.map(\.boundBefore)
		joins = cells.joins
	}

	/// The columns of a world’s variants that the fold reads.
	struct Input: Sendable {
		/// The columns of `variants`. `cellRule` gives the rule of each read of a variant, given the variant and the read’s
		/// position in its reads; `isBeingBuilt` whether an answer a call binds is still being built where its callee
		/// reads it; and `buildsInCallersBody` whether a variant’s call at an edge, given by its index among the variant’s
		/// calls, builds the callee in line in the caller’s own body, with no function of its own and none opened around it,
		/// which must be false wherever the layout gives the callee a function; and `edgeOffset` the offset of a
		/// declaration’s first edge among every declaration’s (`OrderedGraph.edgeOffset(of:)`).
		init(
			variants: TypeFactsVariants,
			cellRule: (_ variant: Int, _ position: Int) -> CellRule,
			isBeingBuilt: (_ answer: Int32) -> Bool,
			buildsInCallersBody: (_ variant: Int, _ edgeIndex: Int) -> Bool,
			edgeOffset: (_ declaration: Int) -> Int,
			hasRoot: Bool = true,
			seedOutcomes: [(variant: Int32, outcomes: [Outcome])] = [],
		) {
			self.hasRoot = hasRoot
			self.seedOutcomes = seedOutcomes
			readOffsets = [0]
			cellRules = []
			families = []
			callOffsets = [0]
			callees = []
			callEdges = []
			self.buildsInCallersBody = []
			sourceOffsets = [0]
			sources = []
			sourceIsBeingBuilt = []
			for variant in 0..<variants.count {
				for position in 0..<variants.keys(of: variant).count {
					cellRules.append(cellRule(variant, position))
				}
				readOffsets.append(Int32(cellRules.count))
				families.append(variants.family(of: variant))
				let firstEdge = edgeOffset(Int(variants.node(of: variant)))
				for (edgeIndex, callee) in variants.callees(of: variant).enumerated() {
					callees.append(callee)
					callEdges.append(Int32(firstEdge + edgeIndex))
					self.buildsInCallersBody.append(buildsInCallersBody(variant, edgeIndex))
					for source in variants.sources(ofCall: variants.callOffset(of: variant) + edgeIndex) {
						sources.append(source)
						sourceIsBeingBuilt.append(source.kind == .bound && isBeingBuilt(source.answer))
					}
					sourceOffsets.append(Int32(sources.count))
				}
				callOffsets.append(Int32(callees.count))
			}
			rootSources = variants.rootSources
		}

		init(
			readOffsets: [Int32],
			cellRules: [CellRule],
			families: [VariantFamily],
			callOffsets: [Int32],
			callees: [Int32],
			callEdges: [Int32],
			buildsInCallersBody: [Bool],
			sourceOffsets: [Int32],
			sources: [AnswerSource],
			sourceIsBeingBuilt: [Bool],
			rootSources: [AnswerSource],
		) {
			hasRoot = true
			seedOutcomes = []
			self.readOffsets = readOffsets
			self.cellRules = cellRules
			self.families = families
			self.callOffsets = callOffsets
			self.callees = callees
			self.callEdges = callEdges
			self.buildsInCallersBody = buildsInCallersBody
			self.sourceOffsets = sourceOffsets
			self.sources = sources
			self.sourceIsBeingBuilt = sourceIsBeingBuilt
			self.rootSources = rootSources
		}

		/// How a read’s outcome is decided.
		enum CellRule: UInt8, Sendable {
			/// The read carries a value, which a function captures when every call passes one statement of the root’s body.
			case value
			/// The read carries a value that is not `Sendable`, such as a mock’s configuration: a `@Sendable` function can
			/// neither capture it nor be passed it, so the statement is read into a local before the function.
			case valueOutsideSendableFunctions
			/// The read keys the variant (its channel does not carry a value), so every call answers it alike.
			case keysVariant

			/// The rule of a read of `channel`.
			init(channel: ReadChannel) {
				self = if !channel.carriesValue {
					.keysVariant
				} else if channel == .override {
					.valueOutsideSendableFunctions
				} else {
					.value
				}
			}
		}

		/// Per variant, where its reads begin in `cellRules`, with one more entry for the end. Variant 0 is the root.
		var readOffsets: [Int32]
		/// Per (variant, read), how its outcome is decided.
		var cellRules: [CellRule]
		/// Per variant, whether it is built inside a `@Sendable` function.
		var families: [VariantFamily]
		/// Per variant, where its call edges begin in `callees`, with one more entry for the end.
		var callOffsets: [Int32]
		/// Per call edge, the variant it calls.
		var callees: [Int32]
		/// Per call edge, the offset of its edge among every declaration’s edges (`OrderedGraph.edgeOffset(of:)` plus the
		/// edge’s index).
		var callEdges: [Int32]
		/// Per call edge, whether it builds its callee in line in the caller’s own body.
		var buildsInCallersBody: [Bool]
		/// Per call edge, where its sources begin in `sources`, with one more entry for the end. A call edge has one
		/// source per read of its callee, in the callee’s read order.
		var sourceOffsets: [Int32]
		var sources: [AnswerSource]
		/// Per source, whether it binds an answer still being built where the callee reads it, which no function can
		/// capture, so it is passed as an argument (rule 2).
		var sourceIsBeingBuilt: [Bool]
		/// Per read of the root, what the world binds for it: a seam root’s parameter, or none.
		var rootSources: [AnswerSource]
		/// Whether variant 0 is the root's: false for the mock worlds' shared graph, whose variants start from seeds.
		var hasRoot: Bool
		/// Per variant a call from outside the graph reaches, the outcome the call offers each of its reads, in its read
		/// order: what the caller's own graph found for the variant it calls there.
		var seedOutcomes: [(variant: Int32, outcomes: [Outcome])]
	}

	/// What a variant’s body uses for the value of one read: its form, the statement of the root’s body it reads where it
	/// reads one, and where that statement is read before a `@Sendable` function.
	struct Outcome: Hashable, Sendable {
		let form: TypeFactsOutcome
		/// The declaration of the statement a `captured` or `readBeforeSendableFunction` outcome reads, or -1 for any
		/// other form.
		let declaration: Int32
		/// For a `readBeforeSendableFunction` outcome, the offset of the edge that opens the outermost `@Sendable`
		/// function around the variant, before which the statement is read into a local; -1 for any other form. Two calls
		/// that open the function at different edges read two locals, which no one function captures.
		let boundBefore: Int32

		static let none = Outcome(form: .none, declaration: -1, boundBefore: -1)
		static let parameter = Outcome(form: .parameter, declaration: -1, boundBefore: -1)
		static let keysVariant = Outcome(form: .keysVariant, declaration: -1, boundBefore: -1)

		/// A statement of the root’s body, captured until a cell’s rule says how its variant reads it.
		static func statement(_ declaration: Int32) -> Outcome {
			Outcome(form: .captured, declaration: declaration, boundBefore: -1)
		}
	}

	/// The form of each read of `variant`’s outcome, in its read order (`TypeFactsWorld.outcomes(of:)`).
	func forms(of variant: Int32) -> ArraySlice<TypeFactsOutcome> {
		forms[Int(readOffsets[Int(variant)])..<Int(readOffsets[Int(variant) + 1])]
	}

	/// The declaration each read of `variant` reads, in its read order: the statement a `captured` or
	/// `readBeforeSendableFunction` outcome reads, -1 for any other.
	func declarations(of variant: Int32) -> ArraySlice<Int32> {
		declarations[Int(readOffsets[Int(variant)])..<Int(readOffsets[Int(variant) + 1])]
	}

	/// The edge each read of `variant` is bound before, in its read order (`TypeFactsWorld.boundBefore(of:)`).
	func boundBefore(of variant: Int32) -> ArraySlice<Int32> {
		boundBefore[Int(readOffsets[Int(variant)])..<Int(readOffsets[Int(variant) + 1])]
	}

	/// How many joins the fold made: one per constant source and at most two per passed-through source, which the tests
	/// hold to a constant times the sources of the world’s call edges.
	let joins: Int

	private let readOffsets: [Int32]
	private let forms: [TypeFactsOutcome]
	private let declarations: [Int32]
	private let boundBefore: [Int32]

	/// The lattice of every cell and the worklist of the cells that changed.
	private struct Cells {
		init(rules: [Input.CellRule], readOffsets: [Int32], families: [VariantFamily]) {
			var readsBeforeFunction = [Bool](repeating: false, count: rules.count)
			for (variant, family) in families.enumerated() where family == .sendable {
				for cell in Int(readOffsets[variant])..<Int(readOffsets[variant + 1]) where rules[cell] == .valueOutsideSendableFunctions {
					readsBeforeFunction[cell] = true
				}
			}
			self.readsBeforeFunction = readsBeforeFunction
			outcomes = rules.map { $0 == .keysVariant ? .keysVariant : .none }
			self.rules = rules
			isKnown = rules.map { $0 == .keysVariant }
			isQueued = [Bool](repeating: false, count: rules.count)
		}

		var count: Int {
			rules.count
		}

		private(set) var outcomes: [Outcome]
		private(set) var joins = 0

		/// Joins `offered`, which a call at `edge` hands, into the cell. A statement a `@Sendable` function cannot capture is
		/// read before it, as the cell’s rule says: before `edge`, which opens the function, unless a caller already reads it
		/// before an edge further out.
		mutating func join(_ offered: Outcome, into cell: Int, through edge: Int32) {
			joins += 1
			let candidate: Outcome = switch offered.form {
			case .captured:
				readsBeforeFunction[cell] ? Outcome(form: .readBeforeSendableFunction, declaration: offered.declaration, boundBefore: edge) : offered
			case .readBeforeSendableFunction:
				readsBeforeFunction[cell] ? offered : .statement(offered.declaration)
			case .none, .parameter, .keysVariant:
				offered
			}
			let joined: Outcome = if !isKnown[cell] || outcomes[cell] == candidate {
				candidate
			} else {
				.parameter
			}
			guard rules[cell] != .keysVariant, !isKnown[cell] || joined != outcomes[cell] else { return }
			outcomes[cell] = joined
			isKnown[cell] = true
			if !isQueued[cell] {
				isQueued[cell] = true
				changed.append(Int32(cell))
			}
		}

		mutating func nextChanged() -> Int? {
			guard let cell = changed.popLast() else { return nil }
			isQueued[Int(cell)] = false
			return Int(cell)
		}

		private let rules: [Input.CellRule]
		private let readsBeforeFunction: [Bool]
		private var isKnown: [Bool]
		private var isQueued: [Bool]
		private var changed = [Int32]()
	}
}
