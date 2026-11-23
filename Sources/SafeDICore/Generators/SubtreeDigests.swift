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

/// What a place's build reads of the generators the pass before built, as one ID per subtree: the key a construction memo
/// stores a place under in place of the identity of the pass before's generator (`ConstructionMemo.Key.previousPass`).
///
/// A place's build reads, of the generator the pass before built for it, the parameters of its builder function it found
/// (`foundCycleParameters`), or those a `CycleParameterSeed` settled in their place, the loops of builders it found among
/// its children (`receivedBuilderLoops`), what it found of the fills of a call it makes, and the same of each child's
/// generator, by index. So two places whose pass-before subtrees hold alike values everywhere are built alike from them,
/// and the digest of a subtree is interned from its own values, compared as the memo compares answers (by `==` and by
/// spelling), and its children's digests by index. A place with no generator of a pass before reads what an empty subtree
/// holds, so every subtree that holds nothing anywhere has the empty digest, the one a first pass keys every place by.
/// A generator that found anything of a call's fills has a digest of its own: its place, and every place above it, is
/// never stored (`ScopeGeneratorUnderConstruction.isMemoizable`).
///
/// A place that the pass before built settled, finding what it was built with everywhere beneath it, has the digest it was
/// built with, so the next pass finds the generator under the key it was stored under: no lookup of its own is needed.
///
/// Lives for the passes of one tree (`ScopeRecord.createdTree`). Its IDs are compared and hashed only, never ordered or
/// emitted; the tests intern them in other orders (`ConstructionInternerObservation.declarationOrder`). It keeps the
/// digest of each generator it was asked about only for one pass, since it names it by its identity, which is unique only
/// while the pass before's tree keeps it alive.
struct SubtreeDigests {
	/// One subtree's digest.
	///
	/// It stays `Hashable` and not `Comparable`, with its value `fileprivate`, so no output can depend on the order of
	/// digests. Making it `Comparable`, or exposing its value, is a determinism change, and the change that makes it needs
	/// an oracle of its own. The tests' block permutation (`ConstructionInternerObservation.declarationOrder`) reaches these
	/// IDs: `init()` permutes their values.
	struct ID: Hashable {
		fileprivate let value: Int

		/// The digest of a subtree that holds nothing anywhere, and of a place with no generator of a pass before.
		static let empty = ID(value: 0)
	}

	init() {
		// The tests give IDs other values, in blocks of 64 permuted as they permute what the interner interns.
		valueOrder = ConstructionInternerObservation.declarationOrder.map { $0(Self.valueOrderBlockSize) }
	}

	/// Forgets the digests of the generators of the pass before last, whose identities another object can now take.
	mutating func beginPass() {
		digestsByPlace = [:]
	}

	/// The digest of the subtree of `generator`, the pass before's generator at a place, with the parameters of `seed` in
	/// place of what it found where the seed has them, or `ID.empty` where there is neither.
	mutating func digest(of generator: ScopeGenerator?, seed: CycleParameterSeed?) -> ID {
		guard generator != nil || seed != nil else { return .empty }
		// A tree can be as deep as the module has types, so the walk keeps a stack of its own rather than recursing.
		var stack = [Frame(generator: generator, seed: seed)]
		var result = ID.empty
		while let frame = stack.last {
			if let digest = digestsByPlace[frame.place] {
				stack.removeLast()
				if stack.isEmpty {
					result = digest
				} else {
					stack[stack.count - 1].childDigests.append(digest)
				}
			} else if frame.childDigests.count < frame.childCount {
				let index = frame.childDigests.count
				let child = Frame(generator: frame.generator?.child(at: index), seed: frame.seed?.child(at: index))
				if child.generator == nil, child.seed == nil {
					stack[stack.count - 1].childDigests.append(.empty)
				} else {
					stack.append(child)
				}
			} else {
				digestsByPlace[frame.place] = digest(ownValue: ownValue(of: frame), childDigests: frame.childDigests)
			}
		}
		return result
	}

	/// The value of what `frame`'s own generator holds that a build reads, `0` for nothing.
	private mutating func ownValue(of frame: Frame) -> Int {
		if let generator = frame.generator,
		   !generator.fillDeferredLabelsHiddenByReenteringCalls.isEmpty
		   || !generator.fillDeferredLabelsReadInsideSendableFunction.isEmpty
		   || !generator.fillSendableWrapperReads.isEmpty
		   || !generator.fillLabelsReadOnlyAsPlaceField.isEmpty
		   || !generator.publicMockLevelReentries.isEmpty
		{
			return nextValue()
		}
		let found = Found(
			cycleParameters: frame.seed?.foundCycleParameters ?? frame.generator?.foundCycleParameters ?? [],
			loops: frame.generator?.receivedBuilderLoops ?? ScopeGenerator.ReceivedBuilderLoops(),
		)
		guard !found.cycleParameters.isEmpty || found.loops != ScopeGenerator.ReceivedBuilderLoops() else { return 0 }
		var hasher = Hasher()
		hasher.combine(found.cycleParameters)
		hasher.combine(found.loops.loopByChildIndex)
		hasher.combine(found.loops.reboundPropertiesByChildIndex)
		let hash = hasher.finalize()
		if let (_, value) = foundByHash[hash, default: []].first(where: { $0.found.isAlike(found) }) {
			return value
		}
		let value = nextValue()
		foundByHash[hash, default: []].append((found, value))
		return value
	}

	/// The digest of a subtree whose own generator holds `ownValue` and whose children have `childDigests`, by index.
	private mutating func digest(ownValue: Int, childDigests: [ID]) -> ID {
		var content = [ownValue]
		content.append(contentsOf: childDigests.map(\.value))
		while content.last == 0 {
			content.removeLast()
		}
		guard !content.isEmpty else { return .empty }
		if let digest = digestsByContent[content] {
			return digest
		}
		let digest = ID(value: nextValue())
		digestsByContent[content] = digest
		return digest
	}

	/// A value no ID or own value has had yet.
	private mutating func nextValue() -> Int {
		defer { valueCount += 1 }
		guard let valueOrder else { return valueCount + 1 }
		return valueCount - valueCount % Self.valueOrderBlockSize + valueOrder[valueCount % Self.valueOrderBlockSize] + 1
	}

	/// What a generator found that a build reads of it, besides its children and its fills.
	private struct Found {
		let cycleParameters: [CycleParameter]
		let loops: ScopeGenerator.ReceivedBuilderLoops

		/// Whether `other` is alike, as `ConstructionLog.Answer.isAlike` compares a cycle parameter context: by `==` and by
		/// the spelling of every property.
		func isAlike(_ other: Found) -> Bool {
			ConstructionLog.Answer.cycleParameterContext(cycleParameters).isAlike(.cycleParameterContext(other.cycleParameters))
				&& loops == other.loops
				&& loops.reboundPropertiesByChildIndex.allSatisfy { index, properties in
					other.loops.reboundPropertiesByChildIndex[index].map(properties.isSpelledAlike) ?? false
				}
		}
	}

	/// A generator of the pass before and its seed, by their identities.
	private struct Place: Hashable {
		let generator: ObjectIdentifier?
		let seed: ObjectIdentifier?
	}

	/// A subtree whose digest the walk is finding, with its children's digests found so far.
	private struct Frame {
		init(generator: ScopeGenerator?, seed: CycleParameterSeed?) {
			self.generator = generator
			self.seed = seed
			childCount = max(generator?.children.count ?? 0, seed?.children.count ?? 0)
		}

		let generator: ScopeGenerator?
		let seed: CycleParameterSeed?
		let childCount: Int
		var childDigests = [ID]()

		var place: Place {
			Place(generator: generator.map(ObjectIdentifier.init), seed: seed.map(ObjectIdentifier.init))
		}
	}

	private static let valueOrderBlockSize = 64
	private let valueOrder: [Int]?
	private var valueCount = 0
	private var foundByHash = [Int: [(found: Found, value: Int)]]()
	private var digestsByContent = [[Int]: ID]()
	private var digestsByPlace = [Place: ID]()
}

extension ScopeGenerator {
	/// The child at `index`, or `nil` where there is none.
	nonisolated fileprivate func child(at index: Int) -> ScopeGenerator? {
		let children = children
		return children.indices.contains(index) ? children[index] : nil
	}
}
