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
/// parameter (design section 4, point 3). It is the type key's `computeOutcomes` taken over the call edges between
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
		let variantCount = input.isInline.count
		let readOffsets = input.readOffsets
		let callOffsets = input.callOffsets
		let sourceOffsets = input.sourceOffsets
		let callees = input.callees

		// Which variants’ bodies are the root’s: the root’s, and an inline variant’s whose every caller’s body is the root’s.
		var bodyIsRoot = input.isInline
		bodyIsRoot[0] = true
		var outsideRoot = [Int32]()
		for variant in 1..<variantCount where !input.isInline[variant] {
			outsideRoot.append(Int32(variant))
		}
		while let caller = outsideRoot.popLast() {
			for callee in callees[Int(callOffsets[Int(caller)])..<Int(callOffsets[Int(caller) + 1])]
				where input.isInline[Int(callee)] && bodyIsRoot[Int(callee)]
			{
				bodyIsRoot[Int(callee)] = false
				outsideRoot.append(callee)
			}
		}

		/// Each call with its caller, callee and sources: first the root’s call of itself with the world’s sources.
		func forEachCall(_ body: (_ caller: Int, _ callee: Int, _ sources: ArraySlice<AnswerSource>) -> Void) {
			body(0, 0, input.rootSources[...])
			for caller in 0..<variantCount {
				for call in Int(callOffsets[caller])..<Int(callOffsets[caller + 1]) {
					body(caller, Int(callees[call]), input.sources[Int(sourceOffsets[call])..<Int(sourceOffsets[call + 1])])
				}
			}
		}

		var cells = Cells(rules: input.cellRules, readOffsets: readOffsets, families: input.families)

		// The callee cells that each caller cell feeds through a source that passes it through, as runs per caller cell.
		var dependentOffsets = [Int32](repeating: 0, count: cells.count + 1)
		forEachCall { caller, _, sources in
			for source in sources where source.kind == .passedThrough {
				dependentOffsets[Int(readOffsets[caller] + source.payload) + 1] += 1
			}
		}
		for cell in 0..<cells.count {
			dependentOffsets[cell + 1] += dependentOffsets[cell]
		}
		var dependents = [Int32](repeating: 0, count: Int(dependentOffsets[cells.count]))
		var nextDependent = dependentOffsets
		forEachCall { caller, callee, sources in
			for (read, source) in sources.enumerated() {
				let cell = Int(readOffsets[callee]) + read
				switch source.kind {
				case .none:
					cells.join(.none, into: cell)
				case .bound:
					cells.join(bodyIsRoot[caller] ? .statement(source.payload) : .parameter, into: cell)
				case .passedThrough:
					let callerCell = Int(readOffsets[caller] + source.payload)
					dependents[Int(nextDependent[callerCell])] = Int32(cell)
					nextDependent[callerCell] += 1
				}
			}
		}

		while let cell = cells.nextChanged() {
			let outcome = cells.outcomes[cell]
			for dependent in dependents[Int(dependentOffsets[cell])..<Int(dependentOffsets[cell + 1])] {
				cells.join(outcome, into: Int(dependent))
			}
		}

		self.readOffsets = readOffsets
		outcomes = cells.outcomes
		joins = cells.joins
	}

	/// The columns of a world’s variants that the fold reads.
	struct Input: Sendable {
		/// The columns of `variants`, with each cell’s rule from `cellRule`, given the variant, the read’s position in the
		/// variant’s reads, and the answer the variant was made with for it.
		init(variants: TypeFactsVariants, cellRule: (_ variant: Int, _ position: Int, _ answer: Int32) -> CellRule) {
			readOffsets = [0]
			cellRules = []
			families = []
			callOffsets = [0]
			callees = []
			sourceOffsets = [0]
			sources = []
			for variant in 0..<variants.count {
				for (position, answer) in variants.answers(of: variant).enumerated() {
					cellRules.append(cellRule(variant, position, answer))
				}
				readOffsets.append(Int32(cellRules.count))
				families.append(variants.family(of: variant))
				for (index, callee) in variants.callees(of: variant).enumerated() {
					callees.append(callee)
					sources += variants.sources(ofCall: variants.callOffset(of: variant) + index)
					sourceOffsets.append(Int32(sources.count))
				}
				callOffsets.append(Int32(callees.count))
			}
			isInline = variants.isInline
			rootSources = variants.rootSources
		}

		init(
			readOffsets: [Int32],
			cellRules: [CellRule],
			isInline: [Bool],
			families: [VariantFamily],
			callOffsets: [Int32],
			callees: [Int32],
			sourceOffsets: [Int32],
			sources: [AnswerSource],
			rootSources: [AnswerSource],
		) {
			self.readOffsets = readOffsets
			self.cellRules = cellRules
			self.isInline = isInline
			self.families = families
			self.callOffsets = callOffsets
			self.callees = callees
			self.sourceOffsets = sourceOffsets
			self.sources = sources
			self.rootSources = rootSources
		}

		/// How a read’s outcome is decided.
		enum CellRule: UInt8, Sendable {
			/// The read carries a value, which a function captures when every call passes one statement of the root’s body.
			case value
			/// The read carries a value that is still being built where the variant reads it, which no function can capture,
			/// so it is passed as an argument (rule 2).
			case valueBeingBuilt
			/// The read carries a value that is not `Sendable`, such as a mock’s configuration: a `@Sendable` function can
			/// neither capture it nor be passed it, so the statement is read into a local before the function.
			case valueOutsideSendableFunctions
			/// The read keys the variant (its channel does not carry a value), so every call answers it alike.
			case keysVariant

			/// The rule of a read of `channel` whose answer is or is not still being built.
			init(channel: ReadChannel, isBeingBuilt: Bool) {
				self = if !channel.carriesValue {
					.keysVariant
				} else if isBeingBuilt {
					.valueBeingBuilt
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
		/// Per variant, whether its caller builds it in line in its own body rather than calling a function.
		var isInline: [Bool]
		/// Per variant, whether it is built inside a `@Sendable` function.
		var families: [VariantFamily]
		/// Per variant, where its call edges begin in `callees`, with one more entry for the end.
		var callOffsets: [Int32]
		/// Per call edge, the variant it calls.
		var callees: [Int32]
		/// Per call edge, where its sources begin in `sources`, with one more entry for the end. A call edge has one
		/// source per read of its callee, in the callee’s read order.
		var sourceOffsets: [Int32]
		var sources: [AnswerSource]
		/// Per read of the root, what the world binds for it: a seam root’s parameter, or none.
		var rootSources: [AnswerSource]
	}

	/// What a variant’s body uses for the value of one read.
	enum Form: UInt8, Sendable {
		/// `nil`: every call passes `nil`.
		case none
		/// The statement of the root’s body named by the outcome’s declaration, which every call passes.
		case captured
		/// The statement of the root’s body named by the outcome’s declaration, which every call passes, read into a local
		/// before the `@Sendable` function that could not capture it, which captures the local.
		case readBeforeSendableFunction
		/// A parameter of the variant’s function: calls pass different values, `nil` against a value, or a value no
		/// function can capture. An inline variant reads it from the function whose body holds it.
		case parameter
		/// No outcome: the read keys the variant.
		case keysVariant
	}

	struct Outcome: Hashable, Sendable {
		let form: Form
		/// The declaration of the statement a `captured` or `readBeforeSendableFunction` outcome reads, or -1 for any
		/// other form.
		let declaration: Int32

		static let none = Outcome(form: .none, declaration: -1)
		static let parameter = Outcome(form: .parameter, declaration: -1)
		static let keysVariant = Outcome(form: .keysVariant, declaration: -1)

		/// A statement of the root’s body, captured until a cell’s rule says how its variant reads it.
		static func statement(_ declaration: Int32) -> Outcome {
			Outcome(form: .captured, declaration: declaration)
		}
	}

	/// The outcome of each read of `variant`, in its read order.
	func outcomes(of variant: Int32) -> ArraySlice<Outcome> {
		outcomes[Int(readOffsets[Int(variant)])..<Int(readOffsets[Int(variant) + 1])]
	}

	/// How many joins the fold made: one per constant source and at most two per passed-through source, which the tests
	/// hold to a constant times the sources of the world’s call edges.
	let joins: Int

	private let readOffsets: [Int32]
	private let outcomes: [Outcome]

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

		/// Joins `offered` into the cell. A statement the cell’s variant cannot capture becomes a parameter, or a read
		/// before the `@Sendable` function, as the cell’s rule says.
		mutating func join(_ offered: Outcome, into cell: Int) {
			joins += 1
			let candidate: Outcome = switch offered.form {
			case .captured, .readBeforeSendableFunction:
				if rules[cell] == .valueBeingBuilt {
					.parameter
				} else if readsBeforeFunction[cell] {
					Outcome(form: .readBeforeSendableFunction, declaration: offered.declaration)
				} else {
					Outcome(form: .captured, declaration: offered.declaration)
				}
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
