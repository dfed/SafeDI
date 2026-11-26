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

import Testing
@testable import SafeDICore

struct TypeFactsOutcomesTests {
	@Test
	func outcomes_makesLabelParameter_whenTwoParentsEachBindIt() {
		// The root builds parents 1 and 2 in line, and each binds its own `id` (declarations 10 and 11) and calls the
		// shared variant 3, passing `id` and the root's `logger` (declaration 5).
		let outcomes = World(
			variants: [
				.init(reads: [], calls: [.init(callee: 1, sources: [.bound(5)]), .init(callee: 2, sources: [.bound(5)])]),
				.init(reads: [.value], isInline: true, calls: [.init(callee: 3, sources: [.bound(10), .passedThrough(0)])]),
				.init(reads: [.value], isInline: true, calls: [.init(callee: 3, sources: [.bound(11), .passedThrough(0)])]),
				.init(reads: [.value, .value]),
			],
		).outcomes

		#expect(outcomes.outcomes(of: 3) == [.parameter, .captured(5)])
	}

	@Test
	func outcomes_settlesEveryMemberOfCycle_whenMembersCallEachOther() {
		// The root calls 1 with its `user` (declaration 1) and `nil` for an optional read; 1 and 2 call each other, passing
		// both through, and 2 also calls 1 with a value of its own (declaration 7) for the optional read, which makes it a
		// parameter of both members.
		let outcomes = World(
			variants: [
				.init(reads: [], calls: [.init(callee: 1, sources: [.bound(1), .none])]),
				.init(reads: [.value, .value], calls: [.init(callee: 2, sources: [.passedThrough(0), .passedThrough(1)])]),
				.init(reads: [.value, .value], calls: [
					.init(callee: 1, sources: [.passedThrough(0), .passedThrough(1)]),
					.init(callee: 1, sources: [.passedThrough(0), .bound(7)]),
				]),
			],
		).outcomes

		#expect([1, 2].map { Array(outcomes.outcomes(of: $0)) } == [[.captured(1), .parameter], [.captured(1), .parameter]])
	}

	@Test
	func outcomes_passesNil_whenEveryCallPassesNil() {
		let outcomes = World(
			variants: [
				.init(reads: [], calls: [.init(callee: 1, sources: [.none])]),
				.init(reads: [.value], calls: [.init(callee: 2, sources: [.passedThrough(0)]), .init(callee: 2, sources: [.none])]),
				.init(reads: [.value]),
			],
		).outcomes

		#expect([1, 2].map { Array(outcomes.outcomes(of: $0)) } == [[.none], [.none]])
	}

	@Test
	func outcomes_capturesOnlyStatementsOfRootBody_whenInlineVariantsBindLabel() {
		// The root builds 1 in line and calls the function 2, which builds 3 in line. Each inline variant binds `id`
		// (declarations 4 and 9) and calls a function with it: only the root's body holds statements a function captures.
		let outcomes = World(
			variants: [
				.init(reads: [], calls: [.init(callee: 1, sources: []), .init(callee: 2, sources: [])]),
				.init(reads: [], isInline: true, calls: [.init(callee: 4, sources: [.bound(4)])]),
				.init(reads: [], calls: [.init(callee: 3, sources: [])]),
				.init(reads: [], isInline: true, calls: [.init(callee: 5, sources: [.bound(9)])]),
				.init(reads: [.value]),
				.init(reads: [.value]),
			],
		).outcomes

		#expect([4, 5].map { Array(outcomes.outcomes(of: $0)) } == [[.captured(4)], [.parameter]])
	}

	@Test
	func outcomes_leavesInlineVariantOutsideRootBody_whenOneOfItsCallersIsAFunction() {
		// The inline variant 2 is built in the root's body and in the body of the function 1, so the `id` it binds
		// (declaration 3) is not one statement of the root's body.
		let outcomes = World(
			variants: [
				.init(reads: [], calls: [.init(callee: 1, sources: []), .init(callee: 2, sources: [])]),
				.init(reads: [], calls: [.init(callee: 2, sources: [])]),
				.init(reads: [], isInline: true, calls: [.init(callee: 3, sources: [.bound(3)])]),
				.init(reads: [.value]),
			],
		).outcomes

		#expect(outcomes.outcomes(of: 3) == [.parameter])
	}

	@Test
	func outcomes_passesValueBeingBuilt_whenEveryCallPassesOneStatementOfRootBody() {
		let outcomes = World(
			variants: [
				.init(reads: [], calls: [.init(callee: 1, sources: [.bound(2), .bound(2)])]),
				.init(reads: [.valueBeingBuilt, .value]),
			],
		).outcomes

		#expect(outcomes.outcomes(of: 1) == [.parameter, .captured(2)])
	}

	@Test
	func outcomes_givesNoOutcome_whenReadKeysVariant() {
		let outcomes = World(
			variants: [
				.init(reads: [.keysVariant], calls: [.init(callee: 1, sources: [.passedThrough(0), .bound(3)])], rootSource: 3),
				.init(reads: [.keysVariant, .keysVariant]),
			],
		).outcomes

		#expect([0, 1].map { Array(outcomes.outcomes(of: $0)) } == [[.keysVariant], [.keysVariant, .keysVariant]])
	}

	@Test
	func outcomes_capturesRootParameter_whenSeamRootBindsRead() {
		// A seam's root binds its parameter (declaration 0) and passes nothing for its optional read.
		let outcomes = World(
			variants: [
				.init(reads: [.value, .value], calls: [.init(callee: 1, sources: [.passedThrough(0), .passedThrough(1)])], rootSources: [0, nil]),
				.init(reads: [.value, .value]),
			],
		).outcomes

		#expect(outcomes.outcomes(of: 1) == [.captured(0), .none])
	}

	@Test
	func outcomes_joinRootsOwnReads_whenAVariantCallsTheRoot() {
		// A seam's root binds its parameter (declaration 0) and calls 1, which calls the root back with a value of its own
		// for the first read and passes the second through.
		let outcomes = World(
			variants: [
				.init(reads: [.value, .value], calls: [.init(callee: 1, sources: [.passedThrough(0), .passedThrough(1)])], rootSources: [0, 0]),
				.init(reads: [.value, .value], calls: [.init(callee: 0, sources: [.bound(4), .passedThrough(1)])]),
			],
		).outcomes

		#expect([0, 1].map { Array(outcomes.outcomes(of: $0)) } == [[.parameter, .captured(0)], [.parameter, .captured(0)]])
	}

	@Test
	func outcomes_doNotDependOnOrderOfCallEdges_whenEdgesAreReversed() {
		// Six callers pass three statements and `nil` to one function, in every order the reversal gives.
		let sources: [[TypeFactsOutcomes.Input.Source]] = [[.bound(1), .none], [.bound(1), .bound(1)], [.bound(2), .bound(1)], [.passedThrough(0), .bound(1)], [.bound(1), .bound(1)], [.bound(3), .bound(1)]]
		let worlds = [sources, sources.reversed()].map { order in
			World(
				variants: [.init(reads: [.value], calls: order.map { .init(callee: 1, sources: $0) }, rootSource: 1), .init(reads: [.value, .value])],
			).outcomes
		}

		#expect(worlds.map { Array($0.outcomes(of: 1)) } == [[.parameter, .parameter], [.parameter, .parameter]])
	}

	@Test
	func outcomes_joinAtMostTwicePerSource_whenEveryLayerCallsBothVariantsOfNext() {
		// Each layer has two function variants that each call both of the next layer's, so 2^layers paths reach the last
		// layer, which calls the first again. Every variant reads eight labels: half are passed through, and half are bound
		// by the caller in one of two declarations, so each of those becomes a parameter on the way down.
		let readCount = 8
		for layerCount in [4, 16, 64] {
			var variants: [World.Variant] = [.init(reads: [], calls: [0, 1].map { .init(callee: Int32(1 + $0), sources: (0..<readCount).map { .bound(Int32($0)) }) })]
			for layer in 0..<layerCount {
				for side in 0..<2 {
					let next = layer + 1 < layerCount ? layer + 1 : 0
					variants.append(.init(
						reads: Array(repeating: .value, count: readCount),
						calls: [0, 1].map { nextSide in
							.init(callee: Int32(1 + 2 * next + nextSide), sources: (0..<readCount).map { read in
								read.isMultiple(of: 2) ? .passedThrough(Int32(read)) : .bound(Int32(100 + 2 * read + side))
							})
						},
					))
				}
			}
			let world = World(variants: variants)
			let outcomes = world.outcomes
			let sourceCount = world.input.sources.count

			#expect(sourceCount == (2 + 4 * layerCount) * readCount)
			#expect(outcomes.joins <= 2 * sourceCount)
			#expect(Array(outcomes.outcomes(of: Int32(2 * layerCount))) == (0..<readCount).map { $0.isMultiple(of: 2) ? .captured(Int32($0)) : .parameter })
		}
	}
}

/// A world's variants written out per variant, packed into the fold's columns.
private struct World {
	struct Call {
		let callee: Int32
		let sources: [TypeFactsOutcomes.Input.Source]
	}

	struct Variant {
		init(reads: [TypeFactsOutcomes.Input.CellRule], isInline: Bool = false, calls: [Call] = [], rootSource: Int32? = nil, rootSources: [Int32?]? = nil) {
			self.reads = reads
			self.isInline = isInline
			self.calls = calls
			self.rootSources = rootSources ?? reads.map { _ in rootSource }
		}

		let reads: [TypeFactsOutcomes.Input.CellRule]
		let isInline: Bool
		let calls: [Call]
		/// What the world binds for each read, read only of the root.
		let rootSources: [Int32?]
	}

	let variants: [Variant]

	var input: TypeFactsOutcomes.Input {
		var input = TypeFactsOutcomes.Input(readOffsets: [0], cellRules: [], isInline: [], callOffsets: [0], callees: [], sourceOffsets: [0], sources: [], rootSources: variants[0].rootSources)
		for variant in variants {
			input.cellRules += variant.reads
			input.readOffsets.append(Int32(input.cellRules.count))
			input.isInline.append(variant.isInline)
			for call in variant.calls {
				input.callees.append(call.callee)
				input.sources += call.sources
				input.sourceOffsets.append(Int32(input.sources.count))
			}
			input.callOffsets.append(Int32(input.callees.count))
		}
		return input
	}

	var outcomes: TypeFactsOutcomes {
		TypeFactsOutcomes(input)
	}
}

extension TypeFactsOutcomes.Outcome {
	static func captured(_ declaration: Int32) -> Self {
		.init(form: .captured, declaration: declaration)
	}
}
