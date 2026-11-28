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

import Foundation
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// Acceptance cells of the mock cycle kind: mocks of cycles of instantiators, with an override at every place of the
/// configuration tree, each recording the configuration path it was read from. `Walks.swift` walks each mock's
/// instantiators and lazy wrappers from seeded choices, three and four laps of its cycle deep, and returns each step
/// and the override it read, the place the step entered: the comparator prints those for each walk and compares the
/// mock laid out from node records with the mock's walk (`MockKindsAcceptance`), which reads what 2.4.0 reads on these
/// graphs. The rule: a step to a property already on the path returns to that place with its configuration; any other
/// step enters a new place, configured as the nearest place of its type on the path, else the parent's field, else an
/// empty configuration. The last cells are the value harness's graphs whose overrides differed from 2.4.0 on the mock
/// writer. Written by `cycle_cells.py` beside the value harness, which reads each graph's configuration tree.
struct SafeDIToolMockKindsCycleValueTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenEachOfFiveTypesBuildsTheNextThree() async throws {
		// Five types, each builds the next three through `Instantiator`s: the lap-two difference.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(t0Builder: Instantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T0: Instantiable {
			    public init(t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>) {
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t3Builder: Instantiator<T3>
			}

			@Instantiable
			public final class T1: Instantiable {
			    public init(t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>, t4Builder: Instantiator<T4>) {
			        self.t2Builder = t2Builder
			        self.t3Builder = t3Builder
			        self.t4Builder = t4Builder
			    }

			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t3Builder: Instantiator<T3>
			    @Instantiated public let t4Builder: Instantiator<T4>
			}

			@Instantiable
			public final class T2: Instantiable {
			    public init(t3Builder: Instantiator<T3>, t4Builder: Instantiator<T4>, t0Builder: Instantiator<T0>) {
			        self.t3Builder = t3Builder
			        self.t4Builder = t4Builder
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t3Builder: Instantiator<T3>
			    @Instantiated public let t4Builder: Instantiator<T4>
			    @Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T3: Instantiable {
			    public init(t4Builder: Instantiator<T4>, t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>) {
			        self.t4Builder = t4Builder
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			    }

			    @Instantiated public let t4Builder: Instantiator<T4>
			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			}

			@Instantiable
			public final class T4: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>) {
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Root, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T3, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T4, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Root.SafeDIOverrides {
			    .init(t0Builder: .init(t1Builder: .init(t2Builder: .init(t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder"); return T2(t3Builder: a0, t4Builder: a1, t0Builder: a2) }), t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder"); return T1(t2Builder: a0, t3Builder: a1, t4Builder: a2) }), t2Builder: .init(t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder"); return T2(t3Builder: a0, t4Builder: a1, t0Builder: a2) }), t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder"); return T0(t1Builder: a0, t2Builder: a1, t3Builder: a2) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Root.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 15)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 20)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 20)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenEachOfTenTypesBuildsTheNextThree() async throws {
		// Ten types, each builds the next three.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(t0Builder: Instantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T0: Instantiable {
			    public init(t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>) {
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t3Builder: Instantiator<T3>
			}

			@Instantiable
			public final class T1: Instantiable {
			    public init(t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>, t4Builder: Instantiator<T4>) {
			        self.t2Builder = t2Builder
			        self.t3Builder = t3Builder
			        self.t4Builder = t4Builder
			    }

			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t3Builder: Instantiator<T3>
			    @Instantiated public let t4Builder: Instantiator<T4>
			}

			@Instantiable
			public final class T2: Instantiable {
			    public init(t3Builder: Instantiator<T3>, t4Builder: Instantiator<T4>, t5Builder: Instantiator<T5>) {
			        self.t3Builder = t3Builder
			        self.t4Builder = t4Builder
			        self.t5Builder = t5Builder
			    }

			    @Instantiated public let t3Builder: Instantiator<T3>
			    @Instantiated public let t4Builder: Instantiator<T4>
			    @Instantiated public let t5Builder: Instantiator<T5>
			}

			@Instantiable
			public final class T3: Instantiable {
			    public init(t4Builder: Instantiator<T4>, t5Builder: Instantiator<T5>, t6Builder: Instantiator<T6>) {
			        self.t4Builder = t4Builder
			        self.t5Builder = t5Builder
			        self.t6Builder = t6Builder
			    }

			    @Instantiated public let t4Builder: Instantiator<T4>
			    @Instantiated public let t5Builder: Instantiator<T5>
			    @Instantiated public let t6Builder: Instantiator<T6>
			}

			@Instantiable
			public final class T4: Instantiable {
			    public init(t5Builder: Instantiator<T5>, t6Builder: Instantiator<T6>, t7Builder: Instantiator<T7>) {
			        self.t5Builder = t5Builder
			        self.t6Builder = t6Builder
			        self.t7Builder = t7Builder
			    }

			    @Instantiated public let t5Builder: Instantiator<T5>
			    @Instantiated public let t6Builder: Instantiator<T6>
			    @Instantiated public let t7Builder: Instantiator<T7>
			}

			@Instantiable
			public final class T5: Instantiable {
			    public init(t6Builder: Instantiator<T6>, t7Builder: Instantiator<T7>, t8Builder: Instantiator<T8>) {
			        self.t6Builder = t6Builder
			        self.t7Builder = t7Builder
			        self.t8Builder = t8Builder
			    }

			    @Instantiated public let t6Builder: Instantiator<T6>
			    @Instantiated public let t7Builder: Instantiator<T7>
			    @Instantiated public let t8Builder: Instantiator<T8>
			}

			@Instantiable
			public final class T6: Instantiable {
			    public init(t7Builder: Instantiator<T7>, t8Builder: Instantiator<T8>, t9Builder: Instantiator<T9>) {
			        self.t7Builder = t7Builder
			        self.t8Builder = t8Builder
			        self.t9Builder = t9Builder
			    }

			    @Instantiated public let t7Builder: Instantiator<T7>
			    @Instantiated public let t8Builder: Instantiator<T8>
			    @Instantiated public let t9Builder: Instantiator<T9>
			}

			@Instantiable
			public final class T7: Instantiable {
			    public init(t8Builder: Instantiator<T8>, t9Builder: Instantiator<T9>, t0Builder: Instantiator<T0>) {
			        self.t8Builder = t8Builder
			        self.t9Builder = t9Builder
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t8Builder: Instantiator<T8>
			    @Instantiated public let t9Builder: Instantiator<T9>
			    @Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T8: Instantiable {
			    public init(t9Builder: Instantiator<T9>, t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>) {
			        self.t9Builder = t9Builder
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			    }

			    @Instantiated public let t9Builder: Instantiator<T9>
			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			}

			@Instantiable
			public final class T9: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>) {
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Root, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t5Builder"); walk(value.t5Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T3, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t5Builder"); walk(value.t5Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t6Builder"); walk(value.t6Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T4, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t5Builder"); walk(value.t5Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t6Builder"); walk(value.t6Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t7Builder"); walk(value.t7Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T5, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t6Builder"); walk(value.t6Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t7Builder"); walk(value.t7Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t8Builder"); walk(value.t8Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T6, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t7Builder"); walk(value.t7Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t8Builder"); walk(value.t8Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t9Builder"); walk(value.t9Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T7, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t8Builder"); walk(value.t8Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t9Builder"); walk(value.t9Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T8, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t9Builder"); walk(value.t9Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T9, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Root.SafeDIOverrides {
			    .init(t0Builder: .init(t1Builder: .init(t2Builder: .init(t3Builder: .init(t4Builder: .init(t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder"); return T5(t6Builder: a0, t7Builder: a1, t8Builder: a2) }), t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder"); return T4(t5Builder: a0, t6Builder: a1, t7Builder: a2) }), t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder"); return T5(t6Builder: a0, t7Builder: a1, t8Builder: a2) }), t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder"); return T3(t4Builder: a0, t5Builder: a1, t6Builder: a2) }), t4Builder: .init(t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder"); return T5(t6Builder: a0, t7Builder: a1, t8Builder: a2) }), t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder"); return T4(t5Builder: a0, t6Builder: a1, t7Builder: a2) }), t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder"); return T5(t6Builder: a0, t7Builder: a1, t8Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder"); return T2(t3Builder: a0, t4Builder: a1, t5Builder: a2) }), t3Builder: .init(t4Builder: .init(t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder"); return T5(t6Builder: a0, t7Builder: a1, t8Builder: a2) }), t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder"); return T4(t5Builder: a0, t6Builder: a1, t7Builder: a2) }), t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder"); return T5(t6Builder: a0, t7Builder: a1, t8Builder: a2) }), t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder"); return T3(t4Builder: a0, t5Builder: a1, t6Builder: a2) }), t4Builder: .init(t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder"); return T5(t6Builder: a0, t7Builder: a1, t8Builder: a2) }), t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder"); return T4(t5Builder: a0, t6Builder: a1, t7Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder"); return T1(t2Builder: a0, t3Builder: a1, t4Builder: a2) }), t2Builder: .init(t3Builder: .init(t4Builder: .init(t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder"); return T5(t6Builder: a0, t7Builder: a1, t8Builder: a2) }), t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder"); return T4(t5Builder: a0, t6Builder: a1, t7Builder: a2) }), t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder"); return T5(t6Builder: a0, t7Builder: a1, t8Builder: a2) }), t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder"); return T3(t4Builder: a0, t5Builder: a1, t6Builder: a2) }), t4Builder: .init(t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder"); return T5(t6Builder: a0, t7Builder: a1, t8Builder: a2) }), t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder"); return T4(t5Builder: a0, t6Builder: a1, t7Builder: a2) }), t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder"); return T5(t6Builder: a0, t7Builder: a1, t8Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder"); return T2(t3Builder: a0, t4Builder: a1, t5Builder: a2) }), t3Builder: .init(t4Builder: .init(t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder"); return T5(t6Builder: a0, t7Builder: a1, t8Builder: a2) }), t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder"); return T4(t5Builder: a0, t6Builder: a1, t7Builder: a2) }), t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder"); return T5(t6Builder: a0, t7Builder: a1, t8Builder: a2) }), t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t6Builder.t7Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t6Builder.t7Builder"); return T7(t8Builder: a0, t9Builder: a1, t0Builder: a2) }), t8Builder: .init(t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t6Builder.t8Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t6Builder.t8Builder"); return T8(t9Builder: a0, t0Builder: a1, t1Builder: a2) }), t9Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t6Builder.t9Builder"); return T9(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t6Builder"); return T6(t7Builder: a0, t8Builder: a1, t9Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder"); return T3(t4Builder: a0, t5Builder: a1, t6Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder"); return T0(t1Builder: a0, t2Builder: a1, t3Builder: a2) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Root.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 30)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 40)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 40)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 40)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 40)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 40)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 40)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 40)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 40)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 40)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenRingOfTenTypesBuildsTheNext() async throws {
		// A ring of ten `Instantiator`s.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(t0Builder: Instantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T0: Instantiable {
			    public init(t1Builder: Instantiator<T1>) {
			        self.t1Builder = t1Builder
			    }

			    @Instantiated public let t1Builder: Instantiator<T1>
			}

			@Instantiable
			public final class T1: Instantiable {
			    public init(t2Builder: Instantiator<T2>) {
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t2Builder: Instantiator<T2>
			}

			@Instantiable
			public final class T2: Instantiable {
			    public init(t3Builder: Instantiator<T3>) {
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t3Builder: Instantiator<T3>
			}

			@Instantiable
			public final class T3: Instantiable {
			    public init(t4Builder: Instantiator<T4>) {
			        self.t4Builder = t4Builder
			    }

			    @Instantiated public let t4Builder: Instantiator<T4>
			}

			@Instantiable
			public final class T4: Instantiable {
			    public init(t5Builder: Instantiator<T5>) {
			        self.t5Builder = t5Builder
			    }

			    @Instantiated public let t5Builder: Instantiator<T5>
			}

			@Instantiable
			public final class T5: Instantiable {
			    public init(t6Builder: Instantiator<T6>) {
			        self.t6Builder = t6Builder
			    }

			    @Instantiated public let t6Builder: Instantiator<T6>
			}

			@Instantiable
			public final class T6: Instantiable {
			    public init(t7Builder: Instantiator<T7>) {
			        self.t7Builder = t7Builder
			    }

			    @Instantiated public let t7Builder: Instantiator<T7>
			}

			@Instantiable
			public final class T7: Instantiable {
			    public init(t8Builder: Instantiator<T8>) {
			        self.t8Builder = t8Builder
			    }

			    @Instantiated public let t8Builder: Instantiator<T8>
			}

			@Instantiable
			public final class T8: Instantiable {
			    public init(t9Builder: Instantiator<T9>) {
			        self.t9Builder = t9Builder
			    }

			    @Instantiated public let t9Builder: Instantiator<T9>
			}

			@Instantiable
			public final class T9: Instantiable {
			    public init(t0Builder: Instantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Root, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T3, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T4, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t5Builder"); walk(value.t5Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T5, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t6Builder"); walk(value.t6Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T6, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t7Builder"); walk(value.t7Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T7, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t8Builder"); walk(value.t8Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T8, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t9Builder"); walk(value.t9Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T9, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Root.SafeDIOverrides {
			    .init(t0Builder: .init(t1Builder: .init(t2Builder: .init(t3Builder: .init(t4Builder: .init(t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init({ a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t0Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder"); return T6(t7Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder"); return T5(t6Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder"); return T4(t5Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder"); return T3(t4Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder"); return T2(t3Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder"); return T1(t2Builder: a0) }), { a0 in recorder.record("t0Builder"); return T0(t1Builder: a0) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Root.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 30)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 30)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 40)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 40)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 40)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 40)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 40)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 40)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 40)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 40)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 40)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenRingOfThirtyTypesBuildsTheNext() async throws {
		// A ring of thirty `Instantiator`s.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(t0Builder: Instantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T0: Instantiable {
			    public init(t1Builder: Instantiator<T1>) {
			        self.t1Builder = t1Builder
			    }

			    @Instantiated public let t1Builder: Instantiator<T1>
			}

			@Instantiable
			public final class T1: Instantiable {
			    public init(t2Builder: Instantiator<T2>) {
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t2Builder: Instantiator<T2>
			}

			@Instantiable
			public final class T2: Instantiable {
			    public init(t3Builder: Instantiator<T3>) {
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t3Builder: Instantiator<T3>
			}

			@Instantiable
			public final class T3: Instantiable {
			    public init(t4Builder: Instantiator<T4>) {
			        self.t4Builder = t4Builder
			    }

			    @Instantiated public let t4Builder: Instantiator<T4>
			}

			@Instantiable
			public final class T4: Instantiable {
			    public init(t5Builder: Instantiator<T5>) {
			        self.t5Builder = t5Builder
			    }

			    @Instantiated public let t5Builder: Instantiator<T5>
			}

			@Instantiable
			public final class T5: Instantiable {
			    public init(t6Builder: Instantiator<T6>) {
			        self.t6Builder = t6Builder
			    }

			    @Instantiated public let t6Builder: Instantiator<T6>
			}

			@Instantiable
			public final class T6: Instantiable {
			    public init(t7Builder: Instantiator<T7>) {
			        self.t7Builder = t7Builder
			    }

			    @Instantiated public let t7Builder: Instantiator<T7>
			}

			@Instantiable
			public final class T7: Instantiable {
			    public init(t8Builder: Instantiator<T8>) {
			        self.t8Builder = t8Builder
			    }

			    @Instantiated public let t8Builder: Instantiator<T8>
			}

			@Instantiable
			public final class T8: Instantiable {
			    public init(t9Builder: Instantiator<T9>) {
			        self.t9Builder = t9Builder
			    }

			    @Instantiated public let t9Builder: Instantiator<T9>
			}

			@Instantiable
			public final class T9: Instantiable {
			    public init(t10Builder: Instantiator<T10>) {
			        self.t10Builder = t10Builder
			    }

			    @Instantiated public let t10Builder: Instantiator<T10>
			}

			@Instantiable
			public final class T10: Instantiable {
			    public init(t11Builder: Instantiator<T11>) {
			        self.t11Builder = t11Builder
			    }

			    @Instantiated public let t11Builder: Instantiator<T11>
			}

			@Instantiable
			public final class T11: Instantiable {
			    public init(t12Builder: Instantiator<T12>) {
			        self.t12Builder = t12Builder
			    }

			    @Instantiated public let t12Builder: Instantiator<T12>
			}

			@Instantiable
			public final class T12: Instantiable {
			    public init(t13Builder: Instantiator<T13>) {
			        self.t13Builder = t13Builder
			    }

			    @Instantiated public let t13Builder: Instantiator<T13>
			}

			@Instantiable
			public final class T13: Instantiable {
			    public init(t14Builder: Instantiator<T14>) {
			        self.t14Builder = t14Builder
			    }

			    @Instantiated public let t14Builder: Instantiator<T14>
			}

			@Instantiable
			public final class T14: Instantiable {
			    public init(t15Builder: Instantiator<T15>) {
			        self.t15Builder = t15Builder
			    }

			    @Instantiated public let t15Builder: Instantiator<T15>
			}

			@Instantiable
			public final class T15: Instantiable {
			    public init(t16Builder: Instantiator<T16>) {
			        self.t16Builder = t16Builder
			    }

			    @Instantiated public let t16Builder: Instantiator<T16>
			}

			@Instantiable
			public final class T16: Instantiable {
			    public init(t17Builder: Instantiator<T17>) {
			        self.t17Builder = t17Builder
			    }

			    @Instantiated public let t17Builder: Instantiator<T17>
			}

			@Instantiable
			public final class T17: Instantiable {
			    public init(t18Builder: Instantiator<T18>) {
			        self.t18Builder = t18Builder
			    }

			    @Instantiated public let t18Builder: Instantiator<T18>
			}

			@Instantiable
			public final class T18: Instantiable {
			    public init(t19Builder: Instantiator<T19>) {
			        self.t19Builder = t19Builder
			    }

			    @Instantiated public let t19Builder: Instantiator<T19>
			}

			@Instantiable
			public final class T19: Instantiable {
			    public init(t20Builder: Instantiator<T20>) {
			        self.t20Builder = t20Builder
			    }

			    @Instantiated public let t20Builder: Instantiator<T20>
			}

			@Instantiable
			public final class T20: Instantiable {
			    public init(t21Builder: Instantiator<T21>) {
			        self.t21Builder = t21Builder
			    }

			    @Instantiated public let t21Builder: Instantiator<T21>
			}

			@Instantiable
			public final class T21: Instantiable {
			    public init(t22Builder: Instantiator<T22>) {
			        self.t22Builder = t22Builder
			    }

			    @Instantiated public let t22Builder: Instantiator<T22>
			}

			@Instantiable
			public final class T22: Instantiable {
			    public init(t23Builder: Instantiator<T23>) {
			        self.t23Builder = t23Builder
			    }

			    @Instantiated public let t23Builder: Instantiator<T23>
			}

			@Instantiable
			public final class T23: Instantiable {
			    public init(t24Builder: Instantiator<T24>) {
			        self.t24Builder = t24Builder
			    }

			    @Instantiated public let t24Builder: Instantiator<T24>
			}

			@Instantiable
			public final class T24: Instantiable {
			    public init(t25Builder: Instantiator<T25>) {
			        self.t25Builder = t25Builder
			    }

			    @Instantiated public let t25Builder: Instantiator<T25>
			}

			@Instantiable
			public final class T25: Instantiable {
			    public init(t26Builder: Instantiator<T26>) {
			        self.t26Builder = t26Builder
			    }

			    @Instantiated public let t26Builder: Instantiator<T26>
			}

			@Instantiable
			public final class T26: Instantiable {
			    public init(t27Builder: Instantiator<T27>) {
			        self.t27Builder = t27Builder
			    }

			    @Instantiated public let t27Builder: Instantiator<T27>
			}

			@Instantiable
			public final class T27: Instantiable {
			    public init(t28Builder: Instantiator<T28>) {
			        self.t28Builder = t28Builder
			    }

			    @Instantiated public let t28Builder: Instantiator<T28>
			}

			@Instantiable
			public final class T28: Instantiable {
			    public init(t29Builder: Instantiator<T29>) {
			        self.t29Builder = t29Builder
			    }

			    @Instantiated public let t29Builder: Instantiator<T29>
			}

			@Instantiable
			public final class T29: Instantiable {
			    public init(t0Builder: Instantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Root, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T10, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t11Builder"); walk(value.t11Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T11, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t12Builder"); walk(value.t12Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T12, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t13Builder"); walk(value.t13Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T13, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t14Builder"); walk(value.t14Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T14, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t15Builder"); walk(value.t15Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T15, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t16Builder"); walk(value.t16Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T16, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t17Builder"); walk(value.t17Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T17, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t18Builder"); walk(value.t18Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T18, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t19Builder"); walk(value.t19Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T19, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t20Builder"); walk(value.t20Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T20, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t21Builder"); walk(value.t21Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T21, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t22Builder"); walk(value.t22Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T22, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t23Builder"); walk(value.t23Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T23, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t24Builder"); walk(value.t24Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T24, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t25Builder"); walk(value.t25Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T25, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t26Builder"); walk(value.t26Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T26, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t27Builder"); walk(value.t27Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T27, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t28Builder"); walk(value.t28Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T28, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t29Builder"); walk(value.t29Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T29, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T3, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T4, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t5Builder"); walk(value.t5Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T5, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t6Builder"); walk(value.t6Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T6, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t7Builder"); walk(value.t7Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T7, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t8Builder"); walk(value.t8Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T8, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t9Builder"); walk(value.t9Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T9, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t10Builder"); walk(value.t10Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Root.SafeDIOverrides {
			    .init(t0Builder: .init(t1Builder: .init(t2Builder: .init(t3Builder: .init(t4Builder: .init(t5Builder: .init(t6Builder: .init(t7Builder: .init(t8Builder: .init(t9Builder: .init(t10Builder: .init(t11Builder: .init(t12Builder: .init(t13Builder: .init(t14Builder: .init(t15Builder: .init(t16Builder: .init(t17Builder: .init(t18Builder: .init(t19Builder: .init(t20Builder: .init(t21Builder: .init(t22Builder: .init(t23Builder: .init(t24Builder: .init(t25Builder: .init(t26Builder: .init(t27Builder: .init(t28Builder: .init(t29Builder: .init({ a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder.t16Builder.t17Builder.t18Builder.t19Builder.t20Builder.t21Builder.t22Builder.t23Builder.t24Builder.t25Builder.t26Builder.t27Builder.t28Builder.t29Builder"); return T29(t0Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder.t16Builder.t17Builder.t18Builder.t19Builder.t20Builder.t21Builder.t22Builder.t23Builder.t24Builder.t25Builder.t26Builder.t27Builder.t28Builder"); return T28(t29Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder.t16Builder.t17Builder.t18Builder.t19Builder.t20Builder.t21Builder.t22Builder.t23Builder.t24Builder.t25Builder.t26Builder.t27Builder"); return T27(t28Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder.t16Builder.t17Builder.t18Builder.t19Builder.t20Builder.t21Builder.t22Builder.t23Builder.t24Builder.t25Builder.t26Builder"); return T26(t27Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder.t16Builder.t17Builder.t18Builder.t19Builder.t20Builder.t21Builder.t22Builder.t23Builder.t24Builder.t25Builder"); return T25(t26Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder.t16Builder.t17Builder.t18Builder.t19Builder.t20Builder.t21Builder.t22Builder.t23Builder.t24Builder"); return T24(t25Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder.t16Builder.t17Builder.t18Builder.t19Builder.t20Builder.t21Builder.t22Builder.t23Builder"); return T23(t24Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder.t16Builder.t17Builder.t18Builder.t19Builder.t20Builder.t21Builder.t22Builder"); return T22(t23Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder.t16Builder.t17Builder.t18Builder.t19Builder.t20Builder.t21Builder"); return T21(t22Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder.t16Builder.t17Builder.t18Builder.t19Builder.t20Builder"); return T20(t21Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder.t16Builder.t17Builder.t18Builder.t19Builder"); return T19(t20Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder.t16Builder.t17Builder.t18Builder"); return T18(t19Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder.t16Builder.t17Builder"); return T17(t18Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder.t16Builder"); return T16(t17Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder.t15Builder"); return T15(t16Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder.t14Builder"); return T14(t15Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder.t13Builder"); return T13(t14Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder.t12Builder"); return T12(t13Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder.t11Builder"); return T11(t12Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder.t10Builder"); return T10(t11Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder.t9Builder"); return T9(t10Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder.t8Builder"); return T8(t9Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder.t7Builder"); return T7(t8Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder"); return T6(t7Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder"); return T5(t6Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder"); return T4(t5Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder"); return T3(t4Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder"); return T2(t3Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder"); return T1(t2Builder: a0) }), { a0 in recorder.record("t0Builder"); return T0(t1Builder: a0) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Root.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 90)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 90)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 90)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 90)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 90)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 90)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 90)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 90)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 90)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 120)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 120)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 120)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 120)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 120)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 120)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 120)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 120)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 120)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenEvenTypesOfFiveTypeCycleHoldSendableInstantiators() async throws {
		// Five types, each builds the next three, the even ones through `SendableInstantiator`s: types reached under two properties, across `@Sendable` functions.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			import SafeDI

			@Instantiable(generateMock: true)
			public final class Hub: Instantiable {
				public init(id: String, t0Builder: Instantiator<T0>) {
					self.id = id
					self.t0Builder = t0Builder
				}

				@Forwarded public let id: String
				@Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T0: Instantiable {
				public init(t1Builder: SendableInstantiator<T1>, t2Builder: SendableInstantiator<T2>, t3Builder: SendableInstantiator<T3>) {
					self.t1Builder = t1Builder
					self.t2Builder = t2Builder
					self.t3Builder = t3Builder
				}

				@Instantiated public let t1Builder: SendableInstantiator<T1>
				@Instantiated public let t2Builder: SendableInstantiator<T2>
				@Instantiated public let t3Builder: SendableInstantiator<T3>
			}

			@Instantiable
			public final class T1: Instantiable {
				public init(t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>, t4Builder: Instantiator<T4>) {
					self.t2Builder = t2Builder
					self.t3Builder = t3Builder
					self.t4Builder = t4Builder
				}

				@Instantiated public let t2Builder: Instantiator<T2>
				@Instantiated public let t3Builder: Instantiator<T3>
				@Instantiated public let t4Builder: Instantiator<T4>
			}

			@Instantiable
			public final class T2: Instantiable {
				public init(t3Builder: SendableInstantiator<T3>, t4Builder: SendableInstantiator<T4>, t0Builder: SendableInstantiator<T0>) {
					self.t3Builder = t3Builder
					self.t4Builder = t4Builder
					self.t0Builder = t0Builder
				}

				@Instantiated public let t3Builder: SendableInstantiator<T3>
				@Instantiated public let t4Builder: SendableInstantiator<T4>
				@Instantiated public let t0Builder: SendableInstantiator<T0>
			}

			@Instantiable
			public final class T3: Instantiable {
				public init(t4Builder: Instantiator<T4>, t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>) {
					self.t4Builder = t4Builder
					self.t0Builder = t0Builder
					self.t1Builder = t1Builder
				}

				@Instantiated public let t4Builder: Instantiator<T4>
				@Instantiated public let t0Builder: Instantiator<T0>
				@Instantiated public let t1Builder: Instantiator<T1>
			}

			@Instantiable
			public final class T4: Instantiable {
				public init(t0Builder: SendableInstantiator<T0>, t1Builder: SendableInstantiator<T1>, t2Builder: SendableInstantiator<T2>) {
					self.t0Builder = t0Builder
					self.t1Builder = t1Builder
					self.t2Builder = t2Builder
				}

				@Instantiated public let t0Builder: SendableInstantiator<T0>
				@Instantiated public let t1Builder: SendableInstantiator<T1>
				@Instantiated public let t2Builder: SendableInstantiator<T2>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Hub, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T3, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T4, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Hub.SafeDIOverrides {
			    .init(t0Builder: .init(t1Builder: .init(t2Builder: .init(t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder"); return T2(t3Builder: a0, t4Builder: a1, t0Builder: a2) }), t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder"); return T1(t2Builder: a0, t3Builder: a1, t4Builder: a2) }), t2Builder: .init(t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder"); return T2(t3Builder: a0, t4Builder: a1, t0Builder: a2) }), t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder"); return T0(t1Builder: a0, t2Builder: a1, t3Builder: a2) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Hub.mock(id: "id", safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 15)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 20)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 20)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenEvenTypesOfSixTypeCycleHoldSendableInstantiators() async throws {
		// Six types, each builds the next three, the even ones through `SendableInstantiator`s.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			import SafeDI

			@Instantiable(generateMock: true)
			public final class Hub: Instantiable {
				public init(id: String, t0Builder: Instantiator<T0>) {
					self.id = id
					self.t0Builder = t0Builder
				}

				@Forwarded public let id: String
				@Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T0: Instantiable {
				public init(t1Builder: SendableInstantiator<T1>, t2Builder: SendableInstantiator<T2>, t3Builder: SendableInstantiator<T3>) {
					self.t1Builder = t1Builder
					self.t2Builder = t2Builder
					self.t3Builder = t3Builder
				}

				@Instantiated public let t1Builder: SendableInstantiator<T1>
				@Instantiated public let t2Builder: SendableInstantiator<T2>
				@Instantiated public let t3Builder: SendableInstantiator<T3>
			}

			@Instantiable
			public final class T1: Instantiable {
				public init(t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>, t4Builder: Instantiator<T4>) {
					self.t2Builder = t2Builder
					self.t3Builder = t3Builder
					self.t4Builder = t4Builder
				}

				@Instantiated public let t2Builder: Instantiator<T2>
				@Instantiated public let t3Builder: Instantiator<T3>
				@Instantiated public let t4Builder: Instantiator<T4>
			}

			@Instantiable
			public final class T2: Instantiable {
				public init(t3Builder: SendableInstantiator<T3>, t4Builder: SendableInstantiator<T4>, t5Builder: SendableInstantiator<T5>) {
					self.t3Builder = t3Builder
					self.t4Builder = t4Builder
					self.t5Builder = t5Builder
				}

				@Instantiated public let t3Builder: SendableInstantiator<T3>
				@Instantiated public let t4Builder: SendableInstantiator<T4>
				@Instantiated public let t5Builder: SendableInstantiator<T5>
			}

			@Instantiable
			public final class T3: Instantiable {
				public init(t4Builder: Instantiator<T4>, t5Builder: Instantiator<T5>, t0Builder: Instantiator<T0>) {
					self.t4Builder = t4Builder
					self.t5Builder = t5Builder
					self.t0Builder = t0Builder
				}

				@Instantiated public let t4Builder: Instantiator<T4>
				@Instantiated public let t5Builder: Instantiator<T5>
				@Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T4: Instantiable {
				public init(t5Builder: SendableInstantiator<T5>, t0Builder: SendableInstantiator<T0>, t1Builder: SendableInstantiator<T1>) {
					self.t5Builder = t5Builder
					self.t0Builder = t0Builder
					self.t1Builder = t1Builder
				}

				@Instantiated public let t5Builder: SendableInstantiator<T5>
				@Instantiated public let t0Builder: SendableInstantiator<T0>
				@Instantiated public let t1Builder: SendableInstantiator<T1>
			}

			@Instantiable
			public final class T5: Instantiable {
				public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>) {
					self.t0Builder = t0Builder
					self.t1Builder = t1Builder
					self.t2Builder = t2Builder
				}

				@Instantiated public let t0Builder: Instantiator<T0>
				@Instantiated public let t1Builder: Instantiator<T1>
				@Instantiated public let t2Builder: Instantiator<T2>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Hub, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t5Builder"); walk(value.t5Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T3, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t5Builder"); walk(value.t5Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T4, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t5Builder"); walk(value.t5Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T5, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Hub.SafeDIOverrides {
			    .init(t0Builder: .init(t1Builder: .init(t2Builder: .init(t3Builder: .init(t4Builder: .init(t5Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder"); return T5(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder"); return T4(t5Builder: a0, t0Builder: a1, t1Builder: a2) }), t5Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder"); return T5(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder"); return T3(t4Builder: a0, t5Builder: a1, t0Builder: a2) }), t4Builder: .init(t5Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder"); return T5(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder"); return T4(t5Builder: a0, t0Builder: a1, t1Builder: a2) }), t5Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder"); return T5(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder"); return T2(t3Builder: a0, t4Builder: a1, t5Builder: a2) }), t3Builder: .init(t4Builder: .init(t5Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder"); return T5(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder"); return T4(t5Builder: a0, t0Builder: a1, t1Builder: a2) }), t5Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder"); return T5(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder"); return T3(t4Builder: a0, t5Builder: a1, t0Builder: a2) }), t4Builder: .init(t5Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder"); return T5(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder"); return T4(t5Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder"); return T1(t2Builder: a0, t3Builder: a1, t4Builder: a2) }), t2Builder: .init(t3Builder: .init(t4Builder: .init(t5Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder"); return T5(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder"); return T4(t5Builder: a0, t0Builder: a1, t1Builder: a2) }), t5Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder"); return T5(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder"); return T3(t4Builder: a0, t5Builder: a1, t0Builder: a2) }), t4Builder: .init(t5Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder"); return T5(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder"); return T4(t5Builder: a0, t0Builder: a1, t1Builder: a2) }), t5Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder"); return T5(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder"); return T2(t3Builder: a0, t4Builder: a1, t5Builder: a2) }), t3Builder: .init(t4Builder: .init(t5Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder"); return T5(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder"); return T4(t5Builder: a0, t0Builder: a1, t1Builder: a2) }), t5Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder"); return T5(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder"); return T3(t4Builder: a0, t5Builder: a1, t0Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder"); return T0(t1Builder: a0, t2Builder: a1, t3Builder: a2) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Hub.mock(id: "id", safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 18)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 18)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 18)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 18)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 18)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 18)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 18)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 18)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 18)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 24)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 24)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 24)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 24)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 24)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 24)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 24)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 24)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 24)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenOneTypeOfSevenTypeCycleHoldsSendableInstantiators() async throws {
		// Seven types, each builds the next three, only `T4` through `SendableInstantiator`s.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			import SafeDI

			@Instantiable(generateMock: true)
			public final class Hub: Instantiable {
				public init(id: String, t0Builder: Instantiator<T0>) {
					self.id = id
					self.t0Builder = t0Builder
				}

				@Forwarded public let id: String
				@Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T0: Instantiable {
				public init(t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>) {
					self.t1Builder = t1Builder
					self.t2Builder = t2Builder
					self.t3Builder = t3Builder
				}

				@Instantiated public let t1Builder: Instantiator<T1>
				@Instantiated public let t2Builder: Instantiator<T2>
				@Instantiated public let t3Builder: Instantiator<T3>
			}

			@Instantiable
			public final class T1: Instantiable {
				public init(t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>, t4Builder: Instantiator<T4>) {
					self.t2Builder = t2Builder
					self.t3Builder = t3Builder
					self.t4Builder = t4Builder
				}

				@Instantiated public let t2Builder: Instantiator<T2>
				@Instantiated public let t3Builder: Instantiator<T3>
				@Instantiated public let t4Builder: Instantiator<T4>
			}

			@Instantiable
			public final class T2: Instantiable {
				public init(t3Builder: Instantiator<T3>, t4Builder: Instantiator<T4>, t5Builder: Instantiator<T5>) {
					self.t3Builder = t3Builder
					self.t4Builder = t4Builder
					self.t5Builder = t5Builder
				}

				@Instantiated public let t3Builder: Instantiator<T3>
				@Instantiated public let t4Builder: Instantiator<T4>
				@Instantiated public let t5Builder: Instantiator<T5>
			}

			@Instantiable
			public final class T3: Instantiable {
				public init(t4Builder: Instantiator<T4>, t5Builder: Instantiator<T5>, t6Builder: Instantiator<T6>) {
					self.t4Builder = t4Builder
					self.t5Builder = t5Builder
					self.t6Builder = t6Builder
				}

				@Instantiated public let t4Builder: Instantiator<T4>
				@Instantiated public let t5Builder: Instantiator<T5>
				@Instantiated public let t6Builder: Instantiator<T6>
			}

			@Instantiable
			public final class T4: Instantiable {
				public init(t5Builder: SendableInstantiator<T5>, t6Builder: SendableInstantiator<T6>, t0Builder: SendableInstantiator<T0>) {
					self.t5Builder = t5Builder
					self.t6Builder = t6Builder
					self.t0Builder = t0Builder
				}

				@Instantiated public let t5Builder: SendableInstantiator<T5>
				@Instantiated public let t6Builder: SendableInstantiator<T6>
				@Instantiated public let t0Builder: SendableInstantiator<T0>
			}

			@Instantiable
			public final class T5: Instantiable {
				public init(t6Builder: Instantiator<T6>, t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>) {
					self.t6Builder = t6Builder
					self.t0Builder = t0Builder
					self.t1Builder = t1Builder
				}

				@Instantiated public let t6Builder: Instantiator<T6>
				@Instantiated public let t0Builder: Instantiator<T0>
				@Instantiated public let t1Builder: Instantiator<T1>
			}

			@Instantiable
			public final class T6: Instantiable {
				public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>) {
					self.t0Builder = t0Builder
					self.t1Builder = t1Builder
					self.t2Builder = t2Builder
				}

				@Instantiated public let t0Builder: Instantiator<T0>
				@Instantiated public let t1Builder: Instantiator<T1>
				@Instantiated public let t2Builder: Instantiator<T2>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Hub, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t5Builder"); walk(value.t5Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T3, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t5Builder"); walk(value.t5Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t6Builder"); walk(value.t6Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T4, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t5Builder"); walk(value.t5Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t6Builder"); walk(value.t6Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T5, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t6Builder"); walk(value.t6Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T6, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Hub.SafeDIOverrides {
			    .init(t0Builder: .init(t1Builder: .init(t2Builder: .init(t3Builder: .init(t4Builder: .init(t5Builder: .init(t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t5Builder"); return T5(t6Builder: a0, t0Builder: a1, t1Builder: a2) }), t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder"); return T4(t5Builder: a0, t6Builder: a1, t0Builder: a2) }), t5Builder: .init(t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t5Builder"); return T5(t6Builder: a0, t0Builder: a1, t1Builder: a2) }), t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder"); return T3(t4Builder: a0, t5Builder: a1, t6Builder: a2) }), t4Builder: .init(t5Builder: .init(t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t5Builder"); return T5(t6Builder: a0, t0Builder: a1, t1Builder: a2) }), t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t4Builder"); return T4(t5Builder: a0, t6Builder: a1, t0Builder: a2) }), t5Builder: .init(t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t5Builder"); return T5(t6Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder"); return T2(t3Builder: a0, t4Builder: a1, t5Builder: a2) }), t3Builder: .init(t4Builder: .init(t5Builder: .init(t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t5Builder"); return T5(t6Builder: a0, t0Builder: a1, t1Builder: a2) }), t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder"); return T4(t5Builder: a0, t6Builder: a1, t0Builder: a2) }), t5Builder: .init(t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t5Builder"); return T5(t6Builder: a0, t0Builder: a1, t1Builder: a2) }), t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder"); return T3(t4Builder: a0, t5Builder: a1, t6Builder: a2) }), t4Builder: .init(t5Builder: .init(t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t5Builder"); return T5(t6Builder: a0, t0Builder: a1, t1Builder: a2) }), t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder"); return T4(t5Builder: a0, t6Builder: a1, t0Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder"); return T1(t2Builder: a0, t3Builder: a1, t4Builder: a2) }), t2Builder: .init(t3Builder: .init(t4Builder: .init(t5Builder: .init(t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t5Builder"); return T5(t6Builder: a0, t0Builder: a1, t1Builder: a2) }), t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t4Builder"); return T4(t5Builder: a0, t6Builder: a1, t0Builder: a2) }), t5Builder: .init(t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t5Builder"); return T5(t6Builder: a0, t0Builder: a1, t1Builder: a2) }), t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder"); return T3(t4Builder: a0, t5Builder: a1, t6Builder: a2) }), t4Builder: .init(t5Builder: .init(t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t5Builder"); return T5(t6Builder: a0, t0Builder: a1, t1Builder: a2) }), t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t4Builder"); return T4(t5Builder: a0, t6Builder: a1, t0Builder: a2) }), t5Builder: .init(t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder.t5Builder"); return T5(t6Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder"); return T2(t3Builder: a0, t4Builder: a1, t5Builder: a2) }), t3Builder: .init(t4Builder: .init(t5Builder: .init(t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t5Builder"); return T5(t6Builder: a0, t0Builder: a1, t1Builder: a2) }), t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder"); return T4(t5Builder: a0, t6Builder: a1, t0Builder: a2) }), t5Builder: .init(t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder.t5Builder"); return T5(t6Builder: a0, t0Builder: a1, t1Builder: a2) }), t6Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t6Builder"); return T6(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder"); return T3(t4Builder: a0, t5Builder: a1, t6Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder"); return T0(t1Builder: a0, t2Builder: a1, t3Builder: a2) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Hub.mock(id: "id", safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 21)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 21)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 21)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 21)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 21)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 21)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 21)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 21)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 21)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 28)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 28)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 28)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 28)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 28)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 28)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 28)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 28)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 28)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenEachOfFourTypesBuildsEveryOther() async throws {
		// Four types, each builds every other: the four-type graph.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(t0Builder: Instantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T0: Instantiable {
			    public init(t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>) {
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t3Builder: Instantiator<T3>
			}

			@Instantiable
			public final class T1: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>) {
			        self.t0Builder = t0Builder
			        self.t2Builder = t2Builder
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t3Builder: Instantiator<T3>
			}

			@Instantiable
			public final class T2: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t3Builder: Instantiator<T3>) {
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t3Builder: Instantiator<T3>
			}

			@Instantiable
			public final class T3: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>) {
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Root, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T3, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Root.SafeDIOverrides {
			    .init(t0Builder: .init(t1Builder: .init(t2Builder: .init(t3Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder"); return T3(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder"); return T2(t0Builder: a0, t1Builder: a1, t3Builder: a2) }), t3Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder"); return T3(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder"); return T1(t0Builder: a0, t2Builder: a1, t3Builder: a2) }), t2Builder: .init(t3Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder.t3Builder"); return T3(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t2Builder"); return T2(t0Builder: a0, t1Builder: a1, t3Builder: a2) }), t3Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder"); return T3(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder"); return T0(t1Builder: a0, t2Builder: a1, t3Builder: a2) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Root.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 16)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 16)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenEachOfThreeTypesBuildsEveryMemberAndItself() async throws {
		// A three-member all-to-all tangle, each member building itself too.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(t0Builder: Instantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T0: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>) {
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			}

			@Instantiable
			public final class T1: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>) {
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			}

			@Instantiable
			public final class T2: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>) {
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Root, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Root.SafeDIOverrides {
			    .init(t0Builder: .init(t1Builder: .init(t2Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t2Builder"); return T2(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder"); return T1(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), t2Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder"); return T2(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder"); return T0(t0Builder: a0, t1Builder: a1, t2Builder: a2) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Root.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 9)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenEachOfFourTypesBuildsEveryMemberAndItself() async throws {
		// A four-member all-to-all tangle, each member building itself too.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(t0Builder: Instantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T0: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>) {
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t3Builder: Instantiator<T3>
			}

			@Instantiable
			public final class T1: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>) {
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t3Builder: Instantiator<T3>
			}

			@Instantiable
			public final class T2: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>) {
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t3Builder: Instantiator<T3>
			}

			@Instantiable
			public final class T3: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>) {
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t3Builder: Instantiator<T3>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Root, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(4) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    case 2: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(4) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    case 2: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(4) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    case 2: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T3, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(4) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    case 2: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Root.SafeDIOverrides {
			    .init(t0Builder: .init(t1Builder: .init(t2Builder: .init(t3Builder: .init({ a0, a1, a2, a3 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder"); return T3(t0Builder: a0, t1Builder: a1, t2Builder: a2, t3Builder: a3) }), { a0, a1, a2, a3 in recorder.record("t0Builder.t1Builder.t2Builder"); return T2(t0Builder: a0, t1Builder: a1, t2Builder: a2, t3Builder: a3) }), t3Builder: .init({ a0, a1, a2, a3 in recorder.record("t0Builder.t1Builder.t3Builder"); return T3(t0Builder: a0, t1Builder: a1, t2Builder: a2, t3Builder: a3) }), { a0, a1, a2, a3 in recorder.record("t0Builder.t1Builder"); return T1(t0Builder: a0, t1Builder: a1, t2Builder: a2, t3Builder: a3) }), t2Builder: .init(t3Builder: .init({ a0, a1, a2, a3 in recorder.record("t0Builder.t2Builder.t3Builder"); return T3(t0Builder: a0, t1Builder: a1, t2Builder: a2, t3Builder: a3) }), { a0, a1, a2, a3 in recorder.record("t0Builder.t2Builder"); return T2(t0Builder: a0, t1Builder: a1, t2Builder: a2, t3Builder: a3) }), t3Builder: .init({ a0, a1, a2, a3 in recorder.record("t0Builder.t3Builder"); return T3(t0Builder: a0, t1Builder: a1, t2Builder: a2, t3Builder: a3) }), { a0, a1, a2, a3 in recorder.record("t0Builder"); return T0(t0Builder: a0, t1Builder: a1, t2Builder: a2, t3Builder: a3) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Root.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 16)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 16)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenMockRootIsInsideItsOwnCycle() async throws {
		// The mock’s root is a member of its cycle: a step back to its type enters a new place.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class T0: Instantiable {
			    public init(t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>) {
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t3Builder: Instantiator<T3>
			}

			@Instantiable
			public final class T1: Instantiable {
			    public init(t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>, t4Builder: Instantiator<T4>) {
			        self.t2Builder = t2Builder
			        self.t3Builder = t3Builder
			        self.t4Builder = t4Builder
			    }

			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t3Builder: Instantiator<T3>
			    @Instantiated public let t4Builder: Instantiator<T4>
			}

			@Instantiable
			public final class T2: Instantiable {
			    public init(t3Builder: Instantiator<T3>, t4Builder: Instantiator<T4>, t0Builder: Instantiator<T0>) {
			        self.t3Builder = t3Builder
			        self.t4Builder = t4Builder
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t3Builder: Instantiator<T3>
			    @Instantiated public let t4Builder: Instantiator<T4>
			    @Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T3: Instantiable {
			    public init(t4Builder: Instantiator<T4>, t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>) {
			        self.t4Builder = t4Builder
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			    }

			    @Instantiated public let t4Builder: Instantiator<T4>
			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			}

			@Instantiable
			public final class T4: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>) {
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T3, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T4, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> T0.SafeDIOverrides {
			    .init(t1Builder: .init(t2Builder: .init(t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("t1Builder.t2Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t1Builder.t2Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), t4Builder: .init({ a0, a1, a2 in recorder.record("t1Builder.t2Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t1Builder.t2Builder"); return T2(t3Builder: a0, t4Builder: a1, t0Builder: a2) }), t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("t1Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t1Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), t4Builder: .init({ a0, a1, a2 in recorder.record("t1Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t1Builder"); return T1(t2Builder: a0, t3Builder: a1, t4Builder: a2) }), t2Builder: .init(t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("t2Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t2Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), t4Builder: .init({ a0, a1, a2 in recorder.record("t2Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t2Builder"); return T2(t3Builder: a0, t4Builder: a1, t0Builder: a2) }), t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(T0.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 15)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 20)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 20)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenCycleIsEnteredFromRootAndFromBeneathIt() async throws {
		// `Root` enters the cycle at `T0`, and the `Entry` it builds enters it at `T2`.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(t0Builder: Instantiator<T0>, entry: Entry) {
			        self.t0Builder = t0Builder
			        self.entry = entry
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let entry: Entry
			}

			@Instantiable
			public final class T0: Instantiable {
			    public init(t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>) {
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t3Builder: Instantiator<T3>
			}

			@Instantiable
			public final class T1: Instantiable {
			    public init(t2Builder: Instantiator<T2>, t3Builder: Instantiator<T3>, t4Builder: Instantiator<T4>) {
			        self.t2Builder = t2Builder
			        self.t3Builder = t3Builder
			        self.t4Builder = t4Builder
			    }

			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t3Builder: Instantiator<T3>
			    @Instantiated public let t4Builder: Instantiator<T4>
			}

			@Instantiable
			public final class T2: Instantiable {
			    public init(t3Builder: Instantiator<T3>, t4Builder: Instantiator<T4>, t0Builder: Instantiator<T0>) {
			        self.t3Builder = t3Builder
			        self.t4Builder = t4Builder
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t3Builder: Instantiator<T3>
			    @Instantiated public let t4Builder: Instantiator<T4>
			    @Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T3: Instantiable {
			    public init(t4Builder: Instantiator<T4>, t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>) {
			        self.t4Builder = t4Builder
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			    }

			    @Instantiated public let t4Builder: Instantiator<T4>
			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			}

			@Instantiable
			public final class T4: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>) {
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			}

			@Instantiable
			public final class Entry: Instantiable {
			    public init(t2Builder: Instantiator<T2>) {
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t2Builder: Instantiator<T2>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Entry, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Root, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> entry"); walk(value.entry, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T3, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T4, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Root.SafeDIOverrides {
			    .init(t0Builder: .init(t1Builder: .init(t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1Builder"); return T1(t2Builder: a0, t3Builder: a1, t4Builder: a2) }), t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder"); return T0(t1Builder: a0, t2Builder: a1, t3Builder: a2) }), entry: .init(t2Builder: .init(t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("entry.t2Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("entry.t2Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), t4Builder: .init({ a0, a1, a2 in recorder.record("entry.t2Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), t0Builder: .init(t1Builder: .init(t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("entry.t2Builder.t0Builder.t1Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("entry.t2Builder.t0Builder.t1Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), t4Builder: .init({ a0, a1, a2 in recorder.record("entry.t2Builder.t0Builder.t1Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("entry.t2Builder.t0Builder.t1Builder"); return T1(t2Builder: a0, t3Builder: a1, t4Builder: a2) }), t3Builder: .init(t4Builder: .init({ a0, a1, a2 in recorder.record("entry.t2Builder.t0Builder.t3Builder.t4Builder"); return T4(t0Builder: a0, t1Builder: a1, t2Builder: a2) }), { a0, a1, a2 in recorder.record("entry.t2Builder.t0Builder.t3Builder"); return T3(t4Builder: a0, t0Builder: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("entry.t2Builder.t0Builder"); return T0(t1Builder: a0, t2Builder: a1, t3Builder: a2) }), { a0, a1, a2 in recorder.record("entry.t2Builder"); return T2(t3Builder: a0, t4Builder: a1, t0Builder: a2) }), { a0 in recorder.record("entry"); return Entry(t2Builder: a0) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Root.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 15)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 20)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 20)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenCycleTypeIsBuiltUnderTwoLabels() async throws {
		// `T1` is built under `t1Builder` and `sendableT1Builder`, so a new place of it takes the nearest configuration of its type.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(t0Builder: Instantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T0: Instantiable {
			    public init(t1Builder: Instantiator<T1>, sendableT1Builder: SendableInstantiator<T1>) {
			        self.t1Builder = t1Builder
			        self.sendableT1Builder = sendableT1Builder
			    }

			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let sendableT1Builder: SendableInstantiator<T1>
			}

			@Instantiable
			public final class T1: Instantiable {
			    public init(t2Builder: SendableInstantiator<T2>) {
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t2Builder: SendableInstantiator<T2>
			}

			@Instantiable
			public final class T2: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1Builder: Instantiator<T1>) {
			        self.t0Builder = t0Builder
			        self.t1Builder = t1Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Root, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> sendableT1Builder"); walk(value.sendableT1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Root.SafeDIOverrides {
			    .init(t0Builder: .init(t1Builder: .init(t2Builder: .init({ a0, a1 in recorder.record("t0Builder.t1Builder.t2Builder"); return T2(t0Builder: a0, t1Builder: a1) }), { a0 in recorder.record("t0Builder.t1Builder"); return T1(t2Builder: a0) }), sendableT1Builder: .init(t2Builder: .init({ a0, a1 in recorder.record("t0Builder.sendableT1Builder.t2Builder"); return T2(t0Builder: a0, t1Builder: a1) }), { a0 in recorder.record("t0Builder.sendableT1Builder"); return T1(t2Builder: a0) }), { a0, a1 in recorder.record("t0Builder"); return T0(t1Builder: a0, sendableT1Builder: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Root.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 9)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenRingOfSendableClassesCrossesSendableFunctions() async throws {
		// A ring of `SendableInstantiator`s of `Sendable` classes: every function on the cycle is `@Sendable`.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable, Sendable {
			    public init(t0Builder: SendableInstantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: SendableInstantiator<T0>
			}

			@Instantiable
			public final class T0: Instantiable, Sendable {
			    public init(t1Builder: SendableInstantiator<T1>) {
			        self.t1Builder = t1Builder
			    }

			    @Instantiated public let t1Builder: SendableInstantiator<T1>
			}

			@Instantiable
			public final class T1: Instantiable, Sendable {
			    public init(t2Builder: SendableInstantiator<T2>) {
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t2Builder: SendableInstantiator<T2>
			}

			@Instantiable
			public final class T2: Instantiable, Sendable {
			    public init(t3Builder: SendableInstantiator<T3>) {
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t3Builder: SendableInstantiator<T3>
			}

			@Instantiable
			public final class T3: Instantiable, Sendable {
			    public init(t4Builder: SendableInstantiator<T4>) {
			        self.t4Builder = t4Builder
			    }

			    @Instantiated public let t4Builder: SendableInstantiator<T4>
			}

			@Instantiable
			public final class T4: Instantiable, Sendable {
			    public init(t0Builder: SendableInstantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: SendableInstantiator<T0>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Root, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T3, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T4, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Root.SafeDIOverrides {
			    .init(t0Builder: .init(t1Builder: .init(t2Builder: .init(t3Builder: .init(t4Builder: .init({ a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder"); return T4(t0Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder"); return T3(t4Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder"); return T2(t3Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder"); return T1(t2Builder: a0) }), { a0 in recorder.record("t0Builder"); return T0(t1Builder: a0) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Root.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 15)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 20)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 20)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenRingOfSendableStructsCrossesSendableFunctions() async throws {
		// The same ring of `Sendable` structs.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public struct Root: Instantiable, Sendable {
			    public init(t0Builder: SendableInstantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: SendableInstantiator<T0>
			}

			@Instantiable
			public struct T0: Instantiable, Sendable {
			    public init(t1Builder: SendableInstantiator<T1>) {
			        self.t1Builder = t1Builder
			    }

			    @Instantiated public let t1Builder: SendableInstantiator<T1>
			}

			@Instantiable
			public struct T1: Instantiable, Sendable {
			    public init(t2Builder: SendableInstantiator<T2>) {
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t2Builder: SendableInstantiator<T2>
			}

			@Instantiable
			public struct T2: Instantiable, Sendable {
			    public init(t3Builder: SendableInstantiator<T3>) {
			        self.t3Builder = t3Builder
			    }

			    @Instantiated public let t3Builder: SendableInstantiator<T3>
			}

			@Instantiable
			public struct T3: Instantiable, Sendable {
			    public init(t4Builder: SendableInstantiator<T4>) {
			        self.t4Builder = t4Builder
			    }

			    @Instantiated public let t4Builder: SendableInstantiator<T4>
			}

			@Instantiable
			public struct T4: Instantiable, Sendable {
			    public init(t0Builder: SendableInstantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: SendableInstantiator<T0>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Root, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t3Builder"); walk(value.t3Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T3, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t4Builder"); walk(value.t4Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T4, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Root.SafeDIOverrides {
			    .init(t0Builder: .init(t1Builder: .init(t2Builder: .init(t3Builder: .init(t4Builder: .init({ a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder.t4Builder"); return T4(t0Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder.t3Builder"); return T3(t4Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder.t2Builder"); return T2(t3Builder: a0) }), { a0 in recorder.record("t0Builder.t1Builder"); return T1(t2Builder: a0) }), { a0 in recorder.record("t0Builder"); return T0(t1Builder: a0) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Root.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 15)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 15)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 20)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 20)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 20)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenCycleClosesOnLazilyInstantiated() async throws {
		// Each member closes the cycle on the `LazilyInstantiated<T0>` `Hub` declares.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Hub: Instantiable {
			    public init(t0: LazilyInstantiated<T0>) {
			        self.t0 = t0
			    }

			    @Instantiated public let t0: LazilyInstantiated<T0>
			}

			@Instantiable
			public final class T0: Instantiable {
			    public init(t1Builder: Instantiator<T1>, t2Builder: Instantiator<T2>) {
			        self.t1Builder = t1Builder
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t1Builder: Instantiator<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			}

			@Instantiable
			public final class T1: Instantiable {
			    public init(t0: LazilyInstantiated<T0>, t2Builder: Instantiator<T2>) {
			        self.t0 = t0
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t0: LazilyInstantiated<T0>
			    @Instantiated public let t2Builder: Instantiator<T2>
			}

			@Instantiable
			public final class T2: Instantiable {
			    public init(t0: LazilyInstantiated<T0>, t1Builder: Instantiator<T1>) {
			        self.t0 = t0
			        self.t1Builder = t1Builder
			    }

			    @Instantiated public let t0: LazilyInstantiated<T0>
			    @Instantiated public let t1Builder: Instantiator<T1>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Hub, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0"); walk(value.t0.instance, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> t0"); walk(value.t0.instance, depth - 1, &generator, recorder)
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> t0"); walk(value.t0.instance, depth - 1, &generator, recorder)
			    default: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Hub.SafeDIOverrides {
			    .init(t0: .init(t1Builder: .init(t2Builder: .init({ a0, a1 in recorder.record("t0.t1Builder.t2Builder"); return T2(t0: a0, t1Builder: a1) }), { a0, a1 in recorder.record("t0.t1Builder"); return T1(t0: a0, t2Builder: a1) }), t2Builder: .init({ a0, a1 in recorder.record("t0.t2Builder"); return T2(t0: a0, t1Builder: a1) }), { a0, a1 in recorder.record("t0"); return T0(t1Builder: a0, t2Builder: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Hub.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 9)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenCycleRunsThroughLazyWrappersAndTypeIsBuiltUnderTwoLabels() async throws {
		// A cycle through lazy wrappers, `T0` built under `t0Builder` and `other`.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Hub: Instantiable {
			    public init(t0Builder: Instantiator<T0>) {
			        self.t0Builder = t0Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			}

			@Instantiable
			public final class T0: Instantiable {
			    public init(t1: LazilyInstantiated<T1>, t2Builder: Instantiator<T2>) {
			        self.t1 = t1
			        self.t2Builder = t2Builder
			    }

			    @Instantiated public let t1: LazilyInstantiated<T1>
			    @Instantiated public let t2Builder: Instantiator<T2>
			}

			@Instantiable
			public final class T1: Instantiable {
			    public init(t2Builder: Instantiator<T2>, t0Builder: Instantiator<T0>, other: Instantiator<T0>) {
			        self.t2Builder = t2Builder
			        self.t0Builder = t0Builder
			        self.other = other
			    }

			    @Instantiated public let t2Builder: Instantiator<T2>
			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let other: Instantiator<T0>
			}

			@Instantiable
			public final class T2: Instantiable {
			    public init(t0Builder: Instantiator<T0>, t1: LazilyInstantiated<T1>, t1Builder: Instantiator<T1>) {
			        self.t0Builder = t0Builder
			        self.t1 = t1
			        self.t1Builder = t1Builder
			    }

			    @Instantiated public let t0Builder: Instantiator<T0>
			    @Instantiated public let t1: LazilyInstantiated<T1>
			    @Instantiated public let t1Builder: Instantiator<T1>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Hub, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> t1"); walk(value.t1.instance, depth - 1, &generator, recorder)
			    default: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T1, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t2Builder"); walk(value.t2Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> other"); walk(value.other.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T2, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(3) {
			    case 0: recorder.record("-> t0Builder"); walk(value.t0Builder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> t1"); walk(value.t1.instance, depth - 1, &generator, recorder)
			    default: recorder.record("-> t1Builder"); walk(value.t1Builder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Hub.SafeDIOverrides {
			    .init(t0Builder: .init(t1: .init(t2Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t1.t2Builder"); return T2(t0Builder: a0, t1: a1, t1Builder: a2) }), { a0, a1, a2 in recorder.record("t0Builder.t1"); return T1(t2Builder: a0, t0Builder: a1, other: a2) }), t2Builder: .init({ a0, a1, a2 in recorder.record("t0Builder.t2Builder"); return T2(t0Builder: a0, t1: a1, t1Builder: a2) }), { a0, a1 in recorder.record("t0Builder"); return T0(t1: a0, t2Builder: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Hub.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 9)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenValueAndItsLazyTwinShareOneSlotAndOneIsOffTheCycle() async throws {
		// Twins: `t0: T0` and `t0: LazilyInstantiated<T0>` are one place, whichever the path entered first.
		// The mock per-type plan builds no body for the value twin of a lazily built place, which today’s tree builds.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Hub: Instantiable {
			    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
			        self.aBuilder = aBuilder
			        self.bBuilder = bBuilder
			    }

			    @Instantiated public let aBuilder: Instantiator<A>
			    @Instantiated public let bBuilder: Instantiator<B>
			}

			@Instantiable
			public final class A: Instantiable {
			    public init(t0: T0, cBuilder: Instantiator<C>) {
			        self.t0 = t0
			        self.cBuilder = cBuilder
			    }

			    @Instantiated public let t0: T0
			    @Instantiated public let cBuilder: Instantiator<C>
			}

			@Instantiable
			public final class B: Instantiable {
			    public init(t0: LazilyInstantiated<T0>, cBuilder: Instantiator<C>) {
			        self.t0 = t0
			        self.cBuilder = cBuilder
			    }

			    @Instantiated public let t0: LazilyInstantiated<T0>
			    @Instantiated public let cBuilder: Instantiator<C>
			}

			@Instantiable
			public final class C: Instantiable {
			    public init(t0: T0) {
			        self.t0 = t0
			    }

			    @Instantiated public let t0: T0
			}

			@Instantiable
			public final class T0: Instantiable {
			    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, again: Instantiator<A>, other: Instantiator<B>) {
			        self.aBuilder = aBuilder
			        self.bBuilder = bBuilder
			        self.again = again
			        self.other = other
			    }

			    @Instantiated public let aBuilder: Instantiator<A>
			    @Instantiated public let bBuilder: Instantiator<B>
			    @Instantiated public let again: Instantiator<A>
			    @Instantiated public let other: Instantiator<B>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: A, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> t0"); walk(value.t0, depth - 1, &generator, recorder)
			    default: recorder.record("-> cBuilder"); walk(value.cBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: B, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> t0"); walk(value.t0.instance, depth - 1, &generator, recorder)
			    default: recorder.record("-> cBuilder"); walk(value.cBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: C, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0"); walk(value.t0, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Hub, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> aBuilder"); walk(value.aBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> bBuilder"); walk(value.bBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(4) {
			    case 0: recorder.record("-> aBuilder"); walk(value.aBuilder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> bBuilder"); walk(value.bBuilder.instantiate(), depth - 1, &generator, recorder)
			    case 2: recorder.record("-> again"); walk(value.again.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> other"); walk(value.other.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Hub.SafeDIOverrides {
			    .init(aBuilder: .init(t0: .init(bBuilder: .init({ a0, a1 in recorder.record("aBuilder.t0.bBuilder"); return B(t0: a0, cBuilder: a1) }), other: .init({ a0, a1 in recorder.record("aBuilder.t0.other"); return B(t0: a0, cBuilder: a1) }), { a0, a1, a2, a3 in recorder.record("aBuilder.t0"); return T0(aBuilder: a0, bBuilder: a1, again: a2, other: a3) }), cBuilder: .init(t0: .init(bBuilder: .init({ a0, a1 in recorder.record("aBuilder.cBuilder.t0.bBuilder"); return B(t0: a0, cBuilder: a1) }), other: .init({ a0, a1 in recorder.record("aBuilder.cBuilder.t0.other"); return B(t0: a0, cBuilder: a1) }), { a0, a1, a2, a3 in recorder.record("aBuilder.cBuilder.t0"); return T0(aBuilder: a0, bBuilder: a1, again: a2, other: a3) }), { a0 in recorder.record("aBuilder.cBuilder"); return C(t0: a0) }), { a0, a1 in recorder.record("aBuilder"); return A(t0: a0, cBuilder: a1) }), bBuilder: .init({ a0, a1 in recorder.record("bBuilder"); return B(t0: a0, cBuilder: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Hub.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 16)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 16)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenReenteredLazyCycleBuildsFreshDefault() async throws {
		// V1 (h5): a re-entered cycle builds a fresh `State` default, as 2.4.0 does.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"A.swift": #"""
			import SafeDI
			public final class State { public init() { } }
			@Instantiable(generateMock: true)
			public final class AppScreen: Instantiable {
			    public init(profile: Profile) { self.profile = profile }
			    @Instantiated let profile: Profile
			}
			@Instantiable(generateMock: true)
			public final class Profile: Instantiable {
			    public init(followersBuilder: Instantiator<Followers>, suggestedBuilder: Instantiator<Followers>, state: State = State()) { self.followersBuilder = followersBuilder; self.suggestedBuilder = suggestedBuilder; self.state = state }
			    @Instantiated let followersBuilder: Instantiator<Followers>
			    @Instantiated let suggestedBuilder: Instantiator<Followers>
			    let state: State
			}
			@Instantiable
			public final class Followers: Instantiable {
			    public init(profileBuilder: Instantiator<Profile>) { self.profileBuilder = profileBuilder }
			    @Instantiated let profileBuilder: Instantiator<Profile>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: AppScreen, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> profile"); walk(value.profile, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Followers, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> profileBuilder"); walk(value.profileBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Profile, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> followersBuilder"); walk(value.followersBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> suggestedBuilder"); walk(value.suggestedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Profile.SafeDIOverrides {
			    .init(followersBuilder: .init({ a0 in recorder.record("followersBuilder"); return Followers(profileBuilder: a0) }), suggestedBuilder: .init({ a0 in recorder.record("suggestedBuilder"); return Followers(profileBuilder: a0) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Profile.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 6)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 8)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 8)"),
			DifferentialValueProbe("{ let p0 = Profile.mock(); let p1 = p0.followersBuilder.instantiate().profileBuilder.instantiate(); let p2 = p1.followersBuilder.instantiate().profileBuilder.instantiate(); let p3 = p2.followersBuilder.instantiate().profileBuilder.instantiate(); return [p0.state === p1.state, p1.state === p2.state, p2.state === p3.state] }()"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenReenteredCycleBuildsFreshDefaultBeneathSibling() async throws {
		// V1 (h7): the same beneath `settingsBuilder`.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"A.swift": #"""
			import SafeDI
			public final class State { public init() { } }
			@Instantiable(generateMock: true)
			public final class AppScreen: Instantiable {
			    public init(profile: Profile) { self.profile = profile }
			    @Instantiated let profile: Profile
			}
			@Instantiable(generateMock: true)
			public final class Profile: Instantiable {
			    public init(followersBuilder: Instantiator<Followers>, settingsBuilder: Instantiator<Settings>) { self.followersBuilder = followersBuilder; self.settingsBuilder = settingsBuilder }
			    @Instantiated let followersBuilder: Instantiator<Followers>
			    @Instantiated let settingsBuilder: Instantiator<Settings>
			}
			@Instantiable
			public final class Followers: Instantiable {
			    public init(profileBuilder: Instantiator<Profile>) { self.profileBuilder = profileBuilder }
			    @Instantiated let profileBuilder: Instantiator<Profile>
			}
			@Instantiable
			public final class Settings: Instantiable {
			    public init(state: State = State()) { self.state = state }
			    let state: State
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: AppScreen, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> profile"); walk(value.profile, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Followers, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> profileBuilder"); walk(value.profileBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Profile, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> followersBuilder"); walk(value.followersBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> settingsBuilder"); walk(value.settingsBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Settings, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    _ = (value, depth, generator, recorder)
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Profile.SafeDIOverrides {
			    .init(followersBuilder: .init({ a0 in recorder.record("followersBuilder"); return Followers(profileBuilder: a0) }), settingsBuilder: .init({ a0 in recorder.record("settingsBuilder"); return Settings(state: a0) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Profile.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 6)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 8)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 8)"),
			DifferentialValueProbe("{ let p0 = Profile.mock(); let p1 = p0.followersBuilder.instantiate().profileBuilder.instantiate(); let p2 = p1.followersBuilder.instantiate().profileBuilder.instantiate(); return [p0.settingsBuilder.instantiate().state === p1.settingsBuilder.instantiate().state, p1.settingsBuilder.instantiate().state === p2.settingsBuilder.instantiate().state, p2.settingsBuilder.instantiate().state === p2.settingsBuilder.instantiate().state] }()"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenBuilderIsReachedThroughDeeperPath() async throws {
		// V2 (h11): a builder reached through a deeper path reads the deeper override.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"A.swift": #"""
			import SafeDI
			@Instantiable(generateMock: true)
			public final class App: Instantiable {
			    public init(homeBuilder: Instantiator<Home>) { self.homeBuilder = homeBuilder }
			    @Instantiated let homeBuilder: Instantiator<Home>
			}
			@Instantiable
			public final class Home: Instantiable {
			    public init(profileBuilder: Instantiator<Profile>, feedBuilder: Instantiator<Feed>) { self.profileBuilder = profileBuilder; self.feedBuilder = feedBuilder }
			    @Instantiated let profileBuilder: Instantiator<Profile>
			    @Instantiated let feedBuilder: Instantiator<Feed>
			}
			@Instantiable
			public final class Feed: Instantiable {
			    public init(profileBuilder: Instantiator<Profile>) { self.profileBuilder = profileBuilder }
			    @Instantiated let profileBuilder: Instantiator<Profile>
			}
			@Instantiable
			public final class Profile: Instantiable {
			    public init(homeBuilder: Instantiator<Home>, feedBuilder: Instantiator<Feed>, title: String = "default") { self.homeBuilder = homeBuilder; self.feedBuilder = feedBuilder; self.title = title }
			    @Instantiated let homeBuilder: Instantiator<Home>
			    @Instantiated let feedBuilder: Instantiator<Feed>
			    let title: String
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: App, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> homeBuilder"); walk(value.homeBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Feed, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> profileBuilder"); walk(value.profileBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Home, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> profileBuilder"); walk(value.profileBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> feedBuilder"); walk(value.feedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Profile, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> homeBuilder"); walk(value.homeBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> feedBuilder"); walk(value.feedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> App.SafeDIOverrides {
			    .init(homeBuilder: .init(profileBuilder: .init(title: "homeBuilder.profileBuilder.title", { a0, a1, a2 in recorder.record("homeBuilder.profileBuilder"); return Profile(homeBuilder: a0, feedBuilder: a1, title: a2) }), feedBuilder: .init(profileBuilder: .init(title: "homeBuilder.feedBuilder.profileBuilder.title", { a0, a1, a2 in recorder.record("homeBuilder.feedBuilder.profileBuilder"); return Profile(homeBuilder: a0, feedBuilder: a1, title: a2) }), { a0 in recorder.record("homeBuilder.feedBuilder"); return Feed(profileBuilder: a0) }), { a0, a1 in recorder.record("homeBuilder"); return Home(profileBuilder: a0, feedBuilder: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(App.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 9)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenBuilderIsReachedThroughDeeperPathOnLapTwo() async throws {
		// V2 (lap two of h11).
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"G.swift": #"""
			import SafeDI
			@Instantiable(generateMock: true) public final class App: Instantiable {
			  public init(homeBuilder: Instantiator<Home>) { self.homeBuilder = homeBuilder }
			  @Instantiated public let homeBuilder: Instantiator<Home>
			}
			@Instantiable public final class Home: Instantiable {
			  public init(profileBuilder: Instantiator<Profile>, feedBuilder: Instantiator<Feed>) { self.profileBuilder = profileBuilder; self.feedBuilder = feedBuilder }
			  @Instantiated public let profileBuilder: Instantiator<Profile>
			  @Instantiated public let feedBuilder: Instantiator<Feed>
			}
			@Instantiable public final class Feed: Instantiable {
			  public init(profileBuilder: Instantiator<Profile>) { self.profileBuilder = profileBuilder }
			  @Instantiated public let profileBuilder: Instantiator<Profile>
			}
			@Instantiable public final class Profile: Instantiable {
			  public init(homeBuilder: Instantiator<Home>, feedBuilder: Instantiator<Feed>, title: String = "default") { self.homeBuilder = homeBuilder; self.feedBuilder = feedBuilder; self.title = title }
			  @Instantiated public let homeBuilder: Instantiator<Home>
			  @Instantiated public let feedBuilder: Instantiator<Feed>
			  public let title: String
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: App, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> homeBuilder"); walk(value.homeBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Feed, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> profileBuilder"); walk(value.profileBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Home, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> profileBuilder"); walk(value.profileBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> feedBuilder"); walk(value.feedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Profile, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> homeBuilder"); walk(value.homeBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> feedBuilder"); walk(value.feedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> App.SafeDIOverrides {
			    .init(homeBuilder: .init(profileBuilder: .init(title: "homeBuilder.profileBuilder.title", { a0, a1, a2 in recorder.record("homeBuilder.profileBuilder"); return Profile(homeBuilder: a0, feedBuilder: a1, title: a2) }), feedBuilder: .init(profileBuilder: .init(title: "homeBuilder.feedBuilder.profileBuilder.title", { a0, a1, a2 in recorder.record("homeBuilder.feedBuilder.profileBuilder"); return Profile(homeBuilder: a0, feedBuilder: a1, title: a2) }), { a0 in recorder.record("homeBuilder.feedBuilder"); return Feed(profileBuilder: a0) }), { a0, a1 in recorder.record("homeBuilder"); return Home(profileBuilder: a0, feedBuilder: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(App.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 9)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenBuilderOfPublicPropertiesIsReachedThroughDeeperPathOnLapTwo() async throws {
		// V2 (lap two of h11, public properties).
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"G.swift": #"""
			import SafeDI
			@Instantiable(generateMock: true) public final class App: Instantiable {
			  public init(homeBuilder: Instantiator<Home>) { self.homeBuilder = homeBuilder }
			  @Instantiated public let homeBuilder: Instantiator<Home>
			}
			@Instantiable public final class Home: Instantiable {
			  public init(profileBuilder: Instantiator<Profile>, feedBuilder: Instantiator<Feed>) { self.profileBuilder = profileBuilder; self.feedBuilder = feedBuilder }
			  @Instantiated public let profileBuilder: Instantiator<Profile>
			  @Instantiated public let feedBuilder: Instantiator<Feed>
			}
			@Instantiable public final class Feed: Instantiable {
			  public init(profileBuilder: Instantiator<Profile>) { self.profileBuilder = profileBuilder }
			  @Instantiated public let profileBuilder: Instantiator<Profile>
			}
			@Instantiable public final class Profile: Instantiable {
			  public init(homeBuilder: Instantiator<Home>, feedBuilder: Instantiator<Feed>, title: String = "default") { self.homeBuilder = homeBuilder; self.feedBuilder = feedBuilder; self.title = title }
			  @Instantiated public let homeBuilder: Instantiator<Home>
			  @Instantiated public let feedBuilder: Instantiator<Feed>
			  public let title: String
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: App, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> homeBuilder"); walk(value.homeBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Feed, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> profileBuilder"); walk(value.profileBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Home, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> profileBuilder"); walk(value.profileBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> feedBuilder"); walk(value.feedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Profile, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> homeBuilder"); walk(value.homeBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> feedBuilder"); walk(value.feedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> App.SafeDIOverrides {
			    .init(homeBuilder: .init(profileBuilder: .init(title: "homeBuilder.profileBuilder.title", { a0, a1, a2 in recorder.record("homeBuilder.profileBuilder"); return Profile(homeBuilder: a0, feedBuilder: a1, title: a2) }), feedBuilder: .init(profileBuilder: .init(title: "homeBuilder.feedBuilder.profileBuilder.title", { a0, a1, a2 in recorder.record("homeBuilder.feedBuilder.profileBuilder"); return Profile(homeBuilder: a0, feedBuilder: a1, title: a2) }), { a0 in recorder.record("homeBuilder.feedBuilder"); return Feed(profileBuilder: a0) }), { a0, a1 in recorder.record("homeBuilder"); return Home(profileBuilder: a0, feedBuilder: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(App.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 9)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenBuilderOfInternalPropertiesIsReachedThroughDeeperPath() async throws {
		// V2 (h11 as the oracle’s refutation wrote it).
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"G.swift": #"""
			import SafeDI
			@Instantiable(generateMock: true)
			public final class App: Instantiable {
			    public init(homeBuilder: Instantiator<Home>) { self.homeBuilder = homeBuilder }
			    @Instantiated let homeBuilder: Instantiator<Home>
			}
			@Instantiable
			public final class Home: Instantiable {
			    public init(profileBuilder: Instantiator<Profile>, feedBuilder: Instantiator<Feed>) { self.profileBuilder = profileBuilder; self.feedBuilder = feedBuilder }
			    @Instantiated let profileBuilder: Instantiator<Profile>
			    @Instantiated let feedBuilder: Instantiator<Feed>
			}
			@Instantiable
			public final class Feed: Instantiable {
			    public init(profileBuilder: Instantiator<Profile>) { self.profileBuilder = profileBuilder }
			    @Instantiated let profileBuilder: Instantiator<Profile>
			}
			@Instantiable
			public final class Profile: Instantiable {
			    public init(homeBuilder: Instantiator<Home>, feedBuilder: Instantiator<Feed>, title: String = "default") { self.homeBuilder = homeBuilder; self.feedBuilder = feedBuilder; self.title = title }
			    @Instantiated let homeBuilder: Instantiator<Home>
			    @Instantiated let feedBuilder: Instantiator<Feed>
			    let title: String
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: App, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> homeBuilder"); walk(value.homeBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Feed, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> profileBuilder"); walk(value.profileBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Home, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> profileBuilder"); walk(value.profileBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> feedBuilder"); walk(value.feedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Profile, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> homeBuilder"); walk(value.homeBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> feedBuilder"); walk(value.feedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> App.SafeDIOverrides {
			    .init(homeBuilder: .init(profileBuilder: .init(title: "homeBuilder.profileBuilder.title", { a0, a1, a2 in recorder.record("homeBuilder.profileBuilder"); return Profile(homeBuilder: a0, feedBuilder: a1, title: a2) }), feedBuilder: .init(profileBuilder: .init(title: "homeBuilder.feedBuilder.profileBuilder.title", { a0, a1, a2 in recorder.record("homeBuilder.feedBuilder.profileBuilder"); return Profile(homeBuilder: a0, feedBuilder: a1, title: a2) }), { a0 in recorder.record("homeBuilder.feedBuilder"); return Feed(profileBuilder: a0) }), { a0, a1 in recorder.record("homeBuilder"); return Home(profileBuilder: a0, feedBuilder: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(App.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 9)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenSiblingOfCycleReadsItsOwnOverride() async throws {
		// V3 (h16): `footer` reads its own override, not its sibling `header`’s.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"A.swift": #"""
			import SafeDI
			public protocol CardProtocol { var title: String { get }; var detail: Instantiator<Detail> { get } }
			@Instantiable(generateMock: true)
			public final class App: Instantiable {
			    public init(feed: Feed) { self.feed = feed }
			    @Instantiated let feed: Feed
			}
			@Instantiable
			public final class Feed: Instantiable {
			    public init(header: Card, footer: any CardProtocol) { self.header = header; self.footer = footer }
			    @Instantiated let header: Card
			    @Instantiated let footer: any CardProtocol
			}
			@Instantiable(fulfillingAdditionalTypes: [CardProtocol.self])
			public final class Card: CardProtocol, Instantiable {
			    public init(detail: Instantiator<Detail>, title: String = "default") { self.detail = detail; self.title = title }
			    @Instantiated public let detail: Instantiator<Detail>
			    public let title: String
			}
			@Instantiable
			public final class Detail: Instantiable {
			    public init(feedBuilder: Instantiator<Feed>) { self.feedBuilder = feedBuilder }
			    @Instantiated let feedBuilder: Instantiator<Feed>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: App, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> feed"); walk(value.feed, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Card, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> detail"); walk(value.detail.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Detail, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> feedBuilder"); walk(value.feedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Feed, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> header"); walk(value.header, depth - 1, &generator, recorder)
			    default: recorder.record("-> footer"); walk((value.footer as! Card), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> App.SafeDIOverrides {
			    .init(feed: .init(header: .init(detail: .init({ a0 in recorder.record("feed.header.detail"); return Detail(feedBuilder: a0) }), title: "feed.header.title", { a0, a1 in recorder.record("feed.header"); return Card(detail: a0, title: a1) }), footer: .init(detail: .init({ a0 in recorder.record("feed.footer.detail"); return Detail(feedBuilder: a0) }), title: "feed.footer.title", { a0, a1 in recorder.record("feed.footer"); return Card(detail: a0, title: a1) }), { a0, a1 in recorder.record("feed"); return Feed(header: a0, footer: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(App.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 9)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenSiblingOfCycleReadsItsOwnOverrideOnLapTwo() async throws {
		// V3 (lap two of h16).
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"G.swift": #"""
			import SafeDI
			public protocol CardProtocol { var title: String { get }; var detail: Instantiator<Detail> { get } }
			@Instantiable(generateMock: true) public final class App: Instantiable {
			  public init(feed: Feed) { self.feed = feed }
			  @Instantiated public let feed: Feed
			}
			@Instantiable public final class Feed: Instantiable {
			  public init(header: Card, footer: any CardProtocol) { self.header = header; self.footer = footer }
			  @Instantiated public let header: Card
			  @Instantiated public let footer: any CardProtocol
			}
			@Instantiable(fulfillingAdditionalTypes: [CardProtocol.self]) public final class Card: Instantiable, CardProtocol {
			  public init(detail: Instantiator<Detail>, title: String = "default") { self.detail = detail; self.title = title }
			  @Instantiated public let detail: Instantiator<Detail>
			  public let title: String
			}
			@Instantiable public final class Detail: Instantiable {
			  public init(feedBuilder: Instantiator<Feed>) { self.feedBuilder = feedBuilder }
			  @Instantiated public let feedBuilder: Instantiator<Feed>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: App, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> feed"); walk(value.feed, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Card, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> detail"); walk(value.detail.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Detail, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> feedBuilder"); walk(value.feedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Feed, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> header"); walk(value.header, depth - 1, &generator, recorder)
			    default: recorder.record("-> footer"); walk((value.footer as! Card), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> App.SafeDIOverrides {
			    .init(feed: .init(header: .init(detail: .init({ a0 in recorder.record("feed.header.detail"); return Detail(feedBuilder: a0) }), title: "feed.header.title", { a0, a1 in recorder.record("feed.header"); return Card(detail: a0, title: a1) }), footer: .init(detail: .init({ a0 in recorder.record("feed.footer.detail"); return Detail(feedBuilder: a0) }), title: "feed.footer.title", { a0, a1 in recorder.record("feed.footer"); return Card(detail: a0, title: a1) }), { a0, a1 in recorder.record("feed"); return Feed(header: a0, footer: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(App.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 9)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenSiblingOfPublicPropertiesReadsItsOwnOverrideOnLapTwo() async throws {
		// V3 (lap two of h16, public properties).
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"G.swift": #"""
			import SafeDI
			public protocol CardProtocol { var title: String { get }; var detail: Instantiator<Detail> { get } }
			@Instantiable(generateMock: true) public final class App: Instantiable {
			  public init(feed: Feed) { self.feed = feed }
			  @Instantiated public let feed: Feed
			}
			@Instantiable public final class Feed: Instantiable {
			  public init(header: Card, footer: any CardProtocol) { self.header = header; self.footer = footer }
			  @Instantiated public let header: Card
			  @Instantiated public let footer: any CardProtocol
			}
			@Instantiable(fulfillingAdditionalTypes: [CardProtocol.self]) public final class Card: Instantiable, CardProtocol {
			  public init(detail: Instantiator<Detail>, title: String = "default") { self.detail = detail; self.title = title }
			  @Instantiated public let detail: Instantiator<Detail>
			  public let title: String
			}
			@Instantiable public final class Detail: Instantiable {
			  public init(feedBuilder: Instantiator<Feed>) { self.feedBuilder = feedBuilder }
			  @Instantiated public let feedBuilder: Instantiator<Feed>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: App, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> feed"); walk(value.feed, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Card, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> detail"); walk(value.detail.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Detail, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> feedBuilder"); walk(value.feedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Feed, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> header"); walk(value.header, depth - 1, &generator, recorder)
			    default: recorder.record("-> footer"); walk((value.footer as! Card), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> App.SafeDIOverrides {
			    .init(feed: .init(header: .init(detail: .init({ a0 in recorder.record("feed.header.detail"); return Detail(feedBuilder: a0) }), title: "feed.header.title", { a0, a1 in recorder.record("feed.header"); return Card(detail: a0, title: a1) }), footer: .init(detail: .init({ a0 in recorder.record("feed.footer.detail"); return Detail(feedBuilder: a0) }), title: "feed.footer.title", { a0, a1 in recorder.record("feed.footer"); return Card(detail: a0, title: a1) }), { a0, a1 in recorder.record("feed"); return Feed(header: a0, footer: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(App.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 9)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compilesAndBuildsWalksValues_whenActorNamedApartSitsOnLazyCycle() async throws {
		// D1: `Node`, an actor, is on the cycle through `Loop` and is named apart from `Peer`’s `node: Other`. Neither path compiles today (2.4.1 fails the same way): the cycle kind’s cell.
		try await withKnownIssue("D1: the function that closes the lazy cycle captures the actor’s builder, which reads overrides that are not Sendable") {
			try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
				"Types.swift": #"""
				@Instantiable(generateMock: true)
				public final class Host: Instantiable {
				    public init(node: Node, peer: Peer) { self.node = node; self.peer = peer }
				    @Instantiated let node: Node
				    @Received let peer: Peer
				}
				@Instantiable
				public actor Node: Instantiable {
				    public init(loopBuilder: Instantiator<Loop>) { self.loopBuilder = loopBuilder }
				    @Instantiated let loopBuilder: Instantiator<Loop>
				}
				@Instantiable
				public final class Loop: Instantiable {
				    public init(node: Node) { self.node = node }
				    @Instantiated let node: Node
				}
				@Instantiable
				public final class Peer: Instantiable {
				    public init(node: Other) { self.node = node }
				    @Received let node: Other
				}
				@Instantiable
				public final class Other: Instantiable { public init() {} }
				"""#,
				"Walks.swift": #"""
				/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
				public final class Recorder: @unchecked Sendable {
				    public init() {}
				    public private(set) var log = [String]()
				    public func record(_ entry: String) { log.append(entry) }
				}

				struct WalkGenerator {
				    var state: UInt64
				    mutating func next(_ bound: Int) -> Int {
				        state = state &* 6364136223846793005 &+ 1442695040888963407
				        return Int((state >> 33) % UInt64(bound))
				    }
				}

				func walk(_ value: Host, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
				    guard depth > 0 else { return }
				    switch generator.next(1) {
				    default: recorder.record("-> peer"); walk(value.peer, depth - 1, &generator, recorder)
				    }
				}

				func walk(_ value: Loop, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
				    _ = (value, depth, generator, recorder)
				}

				func walk(_ value: Other, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
				    _ = (value, depth, generator, recorder)
				}

				func walk(_ value: Peer, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
				    guard depth > 0 else { return }
				    switch generator.next(1) {
				    default: recorder.record("-> node"); walk(value.node, depth - 1, &generator, recorder)
				    }
				}

				#if DEBUG
				func overridesAtEveryPlace(_ recorder: Recorder) -> Host.SafeDIOverrides {
				    .init(node_Node: .init(loopBuilder: .init({ a0 in recorder.record("node_Node.loopBuilder"); return Loop(node: a0) }), { a0 in recorder.record("node_Node"); return Node(loopBuilder: a0) }), node_Other: { recorder.record("node_Other"); return Other() }, peer: { a0 in recorder.record("peer"); return Peer(node: a0) })
				}

				/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
				func walks(seeds: Range<Int>, depth: Int) -> [String] {
				    let recorder = Recorder()
				    for seed in seeds {
				        recorder.record("walk \(seed)")
				        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
				        walk(Host.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
				    }
				    return recorder.log
				}

				/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
				func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
				    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
				    var reads: UInt64 = 0
				    for entry in walks(seeds: seeds, depth: depth) {
				        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
				        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
				        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
				    }
				    return [reads, digest]
				}
				#endif
				"""#,
			], probes: [
				DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 6)"),
				DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 6)"),
				DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 6)"),
				DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 6)"),
				DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 6)"),
				DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 6)"),
				DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 6)"),
				DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 6)"),
				DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 6)"),
				DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 8)"),
				DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 8)"),
				DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 8)"),
				DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 8)"),
				DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 8)"),
				DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 8)"),
				DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 8)"),
				DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 8)"),
				DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 8)"),
				DifferentialValueProbe("{ let host = Host.mock(); return host.peer.node === host.peer.node }()"),
			], filesToDelete: &filesToDelete)
		} when: {
			// Both paths fail only where generated code is compiled: with `SAFEDI_SKIP_COMPILE_CHECK` set, as
			// `Scripts/changed-line-coverage.sh` sets it, nothing compiles, so nothing is recorded.
			compileVerificationIsEnabled
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsOnlyIfAvailableOverride_whenUnfulfilledDependencyIsNamedApartOnLazyCycle() async throws {
		// D4: `Node`’s unfulfilled `token` is offered as an override, and read on every lap of the cycle.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Host: Instantiable {
			    public init(node: Node, peer: Peer) { self.node = node; self.peer = peer }
			    @Instantiated let node: Node
			    @Received let peer: Peer
			}
			@Instantiable
			public final class Node: Instantiable {
			    public init(loopBuilder: Instantiator<Loop>, token: Token?) { self.loopBuilder = loopBuilder; self.token = token }
			    @Instantiated(onlyIfAvailable: true) let token: Token?
			    @Instantiated let loopBuilder: Instantiator<Loop>
			}
			@Instantiable
			public final class Loop: Instantiable {
			    public init(node: Node) { self.node = node }
			    @Instantiated let node: Node
			}
			@Instantiable
			public final class Peer: Instantiable {
			    public init(node: Other) { self.node = node }
			    @Received let node: Other
			}
			@Instantiable
			public final class Other: Instantiable { public init() {} }
			public final class Token { public init() {} }
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Host, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> node"); walk(value.node, depth - 1, &generator, recorder)
			    default: recorder.record("-> peer"); walk(value.peer, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Loop, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> node"); walk(value.node, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Node, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> loopBuilder"); walk(value.loopBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Other, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    _ = (value, depth, generator, recorder)
			}

			func walk(_ value: Peer, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> node"); walk(value.node, depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Host.SafeDIOverrides {
			    .init(node_Node: .init(loopBuilder: .init({ a0 in recorder.record("node_Node.loopBuilder"); return Loop(node: a0) }), { a0, a1 in recorder.record("node_Node"); return Node(loopBuilder: a0, token: a1) }), node_Other: { recorder.record("node_Other"); return Other() }, peer: { a0 in recorder.record("peer"); return Peer(node: a0) })
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Host.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 6)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 8)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 8)"),
			DifferentialValueProbe("{ let token = Token(); return Host.mock(safeDIOverrides: .init(token: token)).node.token === token }()"),
			DifferentialValueProbe("{ let token = Token(); return Host.mock(safeDIOverrides: .init(token: token)).node.loopBuilder.instantiate().node.token === token }()"),
			DifferentialValueProbe("{ let token = Token(); return Host.mock(safeDIOverrides: .init(token: token)).node.loopBuilder.instantiate().node.loopBuilder.instantiate().node.token === token }()"),
			DifferentialValueProbe("Host.mock().node.loopBuilder.instantiate().node.token == nil"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenLazyCycleOfSendableBuildersPassesItselfOnlyIfAvailableAndMemberNameSortsFirst() async throws {
		// W2: `Beta`’s mock builds `Alpha` (renamed `Zeta` in the other cell, so it sorts after `Beta`), which builds `Beta` again, passed itself only if available.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable
			public final class Service: Instantiable, Sendable { public init() {} }
			@Instantiable
			public final class Alpha: Instantiable, Sendable {
			    public init(betaBuilder: SendableInstantiator<Beta>, service: Service) { self.betaBuilder = betaBuilder; self.service = service }
			    @Instantiated let betaBuilder: SendableInstantiator<Beta>
			    @Received let service: Service
			}
			@Instantiable(generateMock: true, customMockName: "customMock")
			public final class Beta: Instantiable, Sendable {
			    public init(alphaBuilder: SendableInstantiator<Alpha>, betaBuilder: SendableInstantiator<Beta>?, service: Service) { self.alphaBuilder = alphaBuilder; self.betaBuilder = betaBuilder; self.service = service }
			    @Instantiated let alphaBuilder: SendableInstantiator<Alpha>
			    @Received(onlyIfAvailable: true) let betaBuilder: SendableInstantiator<Beta>?
			    @Received let service: Service
			    #if DEBUG
			    public static func customMock(alphaBuilder: SendableInstantiator<Alpha>, betaBuilder: SendableInstantiator<Beta>?, service: Service) -> Beta { Beta(alphaBuilder: alphaBuilder, betaBuilder: betaBuilder, service: service) }
			    #endif
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Alpha, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> betaBuilder"); walk(value.betaBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> service"); walk(value.service, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Beta, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> alphaBuilder"); walk(value.alphaBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> service"); walk(value.service, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Service, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    _ = (value, depth, generator, recorder)
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Beta.SafeDIOverrides {
			    .init(service: { recorder.record("service"); return Service() }, alphaBuilder: .init(betaBuilder: .init({ a0, a1, a2 in recorder.record("alphaBuilder.betaBuilder"); return Beta(alphaBuilder: a0, betaBuilder: a1, service: a2) }), { a0, a1 in recorder.record("alphaBuilder"); return Alpha(betaBuilder: a0, service: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Beta.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 6)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 8)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 8)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenLazyCycleOfSendableBuildersPassesItselfOnlyIfAvailableAndMemberNameSortsLast() async throws {
		// W2: `Beta`’s mock builds `Alpha` (renamed `Zeta` in the other cell, so it sorts after `Beta`), which builds `Beta` again, passed itself only if available.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable
			public final class Service: Instantiable, Sendable { public init() {} }
			@Instantiable
			public final class Zeta: Instantiable, Sendable {
			    public init(betaBuilder: SendableInstantiator<Beta>, service: Service) { self.betaBuilder = betaBuilder; self.service = service }
			    @Instantiated let betaBuilder: SendableInstantiator<Beta>
			    @Received let service: Service
			}
			@Instantiable(generateMock: true, customMockName: "customMock")
			public final class Beta: Instantiable, Sendable {
			    public init(zetaBuilder: SendableInstantiator<Zeta>, betaBuilder: SendableInstantiator<Beta>?, service: Service) { self.zetaBuilder = zetaBuilder; self.betaBuilder = betaBuilder; self.service = service }
			    @Instantiated let zetaBuilder: SendableInstantiator<Zeta>
			    @Received(onlyIfAvailable: true) let betaBuilder: SendableInstantiator<Beta>?
			    @Received let service: Service
			    #if DEBUG
			    public static func customMock(zetaBuilder: SendableInstantiator<Zeta>, betaBuilder: SendableInstantiator<Beta>?, service: Service) -> Beta { Beta(zetaBuilder: zetaBuilder, betaBuilder: betaBuilder, service: service) }
			    #endif
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: Beta, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> zetaBuilder"); walk(value.zetaBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> service"); walk(value.service, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Service, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    _ = (value, depth, generator, recorder)
			}

			func walk(_ value: Zeta, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> betaBuilder"); walk(value.betaBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> service"); walk(value.service, depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Beta.SafeDIOverrides {
			    .init(service: { recorder.record("service"); return Service() }, zetaBuilder: .init({ a0, a1 in recorder.record("zetaBuilder"); return Zeta(betaBuilder: a0, service: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Beta.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 6)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 8)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 8)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenReenteredCycleThroughLazyWrapperBuildsFreshDefault() async throws {
		// h5 through a `LazilyInstantiated`: `Profile` builds `followers` lazily, so each `Profile` the cycle builds again reads a fresh `State` default.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"A.swift": #"""
			import SafeDI
			public final class State { public init() { } }
			@Instantiable(generateMock: true)
			public final class AppScreen: Instantiable {
			    public init(profile: Profile) { self.profile = profile }
			    @Instantiated let profile: Profile
			}
			@Instantiable(generateMock: true)
			public final class Profile: Instantiable {
			    public init(followers: LazilyInstantiated<Followers>, suggestedBuilder: Instantiator<Followers>, state: State = State()) { self.followers = followers; self.suggestedBuilder = suggestedBuilder; self.state = state }
			    @Instantiated let followers: LazilyInstantiated<Followers>
			    @Instantiated let suggestedBuilder: Instantiator<Followers>
			    let state: State
			}
			@Instantiable
			public final class Followers: Instantiable {
			    public init(profileBuilder: Instantiator<Profile>) { self.profileBuilder = profileBuilder }
			    @Instantiated let profileBuilder: Instantiator<Profile>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: AppScreen, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> profile"); walk(value.profile, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Followers, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> profileBuilder"); walk(value.profileBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Profile, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> followers"); walk(value.followers.instance, depth - 1, &generator, recorder)
			    default: recorder.record("-> suggestedBuilder"); walk(value.suggestedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Profile.SafeDIOverrides {
			    .init(followers: .init({ a0 in recorder.record("followers"); return Followers(profileBuilder: a0) }), suggestedBuilder: .init({ a0 in recorder.record("suggestedBuilder"); return Followers(profileBuilder: a0) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Profile.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 6)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 8)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 8)"),
			DifferentialValueProbe("{ let p0 = Profile.mock(); let p1 = p0.followers.instance.profileBuilder.instantiate(); let p2 = p1.followers.instance.profileBuilder.instantiate(); let p3 = p2.followers.instance.profileBuilder.instantiate(); return [p0.state === p1.state, p1.state === p2.state, p2.state === p3.state] }()"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenReenteredCycleThroughLazyWrapperBuildsFreshDefaultBeneathSibling() async throws {
		// h7 through a `LazilyInstantiated`: the same beneath `settingsBuilder`, with `followers` built lazily.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"A.swift": #"""
			import SafeDI
			public final class State { public init() { } }
			@Instantiable(generateMock: true)
			public final class AppScreen: Instantiable {
			    public init(profile: Profile) { self.profile = profile }
			    @Instantiated let profile: Profile
			}
			@Instantiable(generateMock: true)
			public final class Profile: Instantiable {
			    public init(followers: LazilyInstantiated<Followers>, settingsBuilder: Instantiator<Settings>) { self.followers = followers; self.settingsBuilder = settingsBuilder }
			    @Instantiated let followers: LazilyInstantiated<Followers>
			    @Instantiated let settingsBuilder: Instantiator<Settings>
			}
			@Instantiable
			public final class Followers: Instantiable {
			    public init(profileBuilder: Instantiator<Profile>) { self.profileBuilder = profileBuilder }
			    @Instantiated let profileBuilder: Instantiator<Profile>
			}
			@Instantiable
			public final class Settings: Instantiable {
			    public init(state: State = State()) { self.state = state }
			    let state: State
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: AppScreen, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> profile"); walk(value.profile, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Followers, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> profileBuilder"); walk(value.profileBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Profile, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> followers"); walk(value.followers.instance, depth - 1, &generator, recorder)
			    default: recorder.record("-> settingsBuilder"); walk(value.settingsBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Settings, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    _ = (value, depth, generator, recorder)
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Profile.SafeDIOverrides {
			    .init(followers: .init({ a0 in recorder.record("followers"); return Followers(profileBuilder: a0) }), settingsBuilder: .init({ a0 in recorder.record("settingsBuilder"); return Settings(state: a0) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Profile.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 6)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 6)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 8)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 8)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 8)"),
			DifferentialValueProbe("{ let p0 = Profile.mock(); let p1 = p0.followers.instance.profileBuilder.instantiate(); let p2 = p1.followers.instance.profileBuilder.instantiate(); return [p0.settingsBuilder.instantiate().state === p1.settingsBuilder.instantiate().state, p1.settingsBuilder.instantiate().state === p2.settingsBuilder.instantiate().state, p2.settingsBuilder.instantiate().state === p2.settingsBuilder.instantiate().state] }()"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenLazyWrapperIsReachedThroughDeeperPathOnLapTwo() async throws {
		// Lap two of h11 through a `LazilyInstantiated`: `profile` is built lazily by `Home` and by `Feed`, and each `Profile` reads the override of the nearest place on its path.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"G.swift": #"""
			import SafeDI
			@Instantiable(generateMock: true) public final class App: Instantiable {
			  public init(homeBuilder: Instantiator<Home>) { self.homeBuilder = homeBuilder }
			  @Instantiated public let homeBuilder: Instantiator<Home>
			}
			@Instantiable public final class Home: Instantiable {
			  public init(profile: LazilyInstantiated<Profile>, feedBuilder: Instantiator<Feed>) { self.profile = profile; self.feedBuilder = feedBuilder }
			  @Instantiated public let profile: LazilyInstantiated<Profile>
			  @Instantiated public let feedBuilder: Instantiator<Feed>
			}
			@Instantiable public final class Feed: Instantiable {
			  public init(profile: LazilyInstantiated<Profile>) { self.profile = profile }
			  @Instantiated public let profile: LazilyInstantiated<Profile>
			}
			@Instantiable public final class Profile: Instantiable {
			  public init(homeBuilder: Instantiator<Home>, feedBuilder: Instantiator<Feed>, title: String = "default") { self.homeBuilder = homeBuilder; self.feedBuilder = feedBuilder; self.title = title }
			  @Instantiated public let homeBuilder: Instantiator<Home>
			  @Instantiated public let feedBuilder: Instantiator<Feed>
			  public let title: String
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: App, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> homeBuilder"); walk(value.homeBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Feed, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> profile"); walk(value.profile.instance, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Home, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> profile"); walk(value.profile.instance, depth - 1, &generator, recorder)
			    default: recorder.record("-> feedBuilder"); walk(value.feedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Profile, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> homeBuilder"); walk(value.homeBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> feedBuilder"); walk(value.feedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> App.SafeDIOverrides {
			    .init(homeBuilder: .init(profile: .init(title: "homeBuilder.profile.title", { a0, a1, a2 in recorder.record("homeBuilder.profile"); return Profile(homeBuilder: a0, feedBuilder: a1, title: a2) }), feedBuilder: .init(profile: .init(title: "homeBuilder.feedBuilder.profile.title", { a0, a1, a2 in recorder.record("homeBuilder.feedBuilder.profile"); return Profile(homeBuilder: a0, feedBuilder: a1, title: a2) }), { a0 in recorder.record("homeBuilder.feedBuilder"); return Feed(profile: a0) }), { a0, a1 in recorder.record("homeBuilder"); return Home(profile: a0, feedBuilder: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(App.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 9)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenSiblingOfCycleThroughLazyWrapperReadsItsOwnOverrideOnLapTwo() async throws {
		// Lap two of h16 through a `LazilyInstantiated`: each `Card` builds `detail` lazily, and `header` and `footer` each read their own override.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"G.swift": #"""
			import SafeDI
			public protocol CardProtocol { var title: String { get }; var detail: LazilyInstantiated<Detail> { get } }
			@Instantiable(generateMock: true) public final class App: Instantiable {
			  public init(feed: Feed) { self.feed = feed }
			  @Instantiated public let feed: Feed
			}
			@Instantiable public final class Feed: Instantiable {
			  public init(header: Card, footer: any CardProtocol) { self.header = header; self.footer = footer }
			  @Instantiated public let header: Card
			  @Instantiated public let footer: any CardProtocol
			}
			@Instantiable(fulfillingAdditionalTypes: [CardProtocol.self]) public final class Card: Instantiable, CardProtocol {
			  public init(detail: LazilyInstantiated<Detail>, title: String = "default") { self.detail = detail; self.title = title }
			  @Instantiated public let detail: LazilyInstantiated<Detail>
			  public let title: String
			}
			@Instantiable public final class Detail: Instantiable {
			  public init(feedBuilder: Instantiator<Feed>) { self.feedBuilder = feedBuilder }
			  @Instantiated public let feedBuilder: Instantiator<Feed>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: App, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> feed"); walk(value.feed, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Card, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> detail"); walk(value.detail.instance, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Detail, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> feedBuilder"); walk(value.feedBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Feed, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> header"); walk(value.header, depth - 1, &generator, recorder)
			    default: recorder.record("-> footer"); walk((value.footer as! Card), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> App.SafeDIOverrides {
			    .init(feed: .init(header: .init(detail: .init({ a0 in recorder.record("feed.header.detail"); return Detail(feedBuilder: a0) }), title: "feed.header.title", { a0, a1 in recorder.record("feed.header"); return Card(detail: a0, title: a1) }), footer: .init(detail: .init({ a0 in recorder.record("feed.footer.detail"); return Detail(feedBuilder: a0) }), title: "feed.footer.title", { a0, a1 in recorder.record("feed.footer"); return Card(detail: a0, title: a1) }), { a0, a1 in recorder.record("feed"); return Feed(header: a0, footer: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(App.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 9)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 9)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenLazyWrapperAndItsValueTwinShareOneSlotWithKindsSwapped() async throws {
		// Twins with the kinds swapped: `A` and `C` build `t0` lazily and `B` builds it by value; they are one place, whichever the path entered first.
		// The mock per-type plan builds no body for the value twin of a lazily built place, which today’s tree builds.
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [
			"Types.swift": #"""
			@Instantiable(generateMock: true)
			public final class Hub: Instantiable {
			    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
			        self.aBuilder = aBuilder
			        self.bBuilder = bBuilder
			    }

			    @Instantiated public let aBuilder: Instantiator<A>
			    @Instantiated public let bBuilder: Instantiator<B>
			}

			@Instantiable
			public final class A: Instantiable {
			    public init(t0: LazilyInstantiated<T0>, cBuilder: Instantiator<C>) {
			        self.t0 = t0
			        self.cBuilder = cBuilder
			    }

			    @Instantiated public let t0: LazilyInstantiated<T0>
			    @Instantiated public let cBuilder: Instantiator<C>
			}

			@Instantiable
			public final class B: Instantiable {
			    public init(t0: T0, cBuilder: Instantiator<C>) {
			        self.t0 = t0
			        self.cBuilder = cBuilder
			    }

			    @Instantiated public let t0: T0
			    @Instantiated public let cBuilder: Instantiator<C>
			}

			@Instantiable
			public final class C: Instantiable {
			    public init(t0: LazilyInstantiated<T0>) {
			        self.t0 = t0
			    }

			    @Instantiated public let t0: LazilyInstantiated<T0>
			}

			@Instantiable
			public final class T0: Instantiable {
			    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, again: Instantiator<A>, other: Instantiator<B>) {
			        self.aBuilder = aBuilder
			        self.bBuilder = bBuilder
			        self.again = again
			        self.other = other
			    }

			    @Instantiated public let aBuilder: Instantiator<A>
			    @Instantiated public let bBuilder: Instantiator<B>
			    @Instantiated public let again: Instantiator<A>
			    @Instantiated public let other: Instantiator<B>
			}
			"""#,
			"Walks.swift": #"""
			/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.
			public final class Recorder: @unchecked Sendable {
			    public init() {}
			    public private(set) var log = [String]()
			    public func record(_ entry: String) { log.append(entry) }
			}

			struct WalkGenerator {
			    var state: UInt64
			    mutating func next(_ bound: Int) -> Int {
			        state = state &* 6364136223846793005 &+ 1442695040888963407
			        return Int((state >> 33) % UInt64(bound))
			    }
			}

			func walk(_ value: A, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> t0"); walk(value.t0.instance, depth - 1, &generator, recorder)
			    default: recorder.record("-> cBuilder"); walk(value.cBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: B, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> t0"); walk(value.t0, depth - 1, &generator, recorder)
			    default: recorder.record("-> cBuilder"); walk(value.cBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: C, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(1) {
			    default: recorder.record("-> t0"); walk(value.t0.instance, depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: Hub, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(2) {
			    case 0: recorder.record("-> aBuilder"); walk(value.aBuilder.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> bBuilder"); walk(value.bBuilder.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			func walk(_ value: T0, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {
			    guard depth > 0 else { return }
			    switch generator.next(4) {
			    case 0: recorder.record("-> aBuilder"); walk(value.aBuilder.instantiate(), depth - 1, &generator, recorder)
			    case 1: recorder.record("-> bBuilder"); walk(value.bBuilder.instantiate(), depth - 1, &generator, recorder)
			    case 2: recorder.record("-> again"); walk(value.again.instantiate(), depth - 1, &generator, recorder)
			    default: recorder.record("-> other"); walk(value.other.instantiate(), depth - 1, &generator, recorder)
			    }
			}

			#if DEBUG
			func overridesAtEveryPlace(_ recorder: Recorder) -> Hub.SafeDIOverrides {
			    .init(aBuilder: .init(t0: .init(bBuilder: .init({ a0, a1 in recorder.record("aBuilder.t0.bBuilder"); return B(t0: a0, cBuilder: a1) }), other: .init({ a0, a1 in recorder.record("aBuilder.t0.other"); return B(t0: a0, cBuilder: a1) }), { a0, a1, a2, a3 in recorder.record("aBuilder.t0"); return T0(aBuilder: a0, bBuilder: a1, again: a2, other: a3) }), cBuilder: .init(t0: .init(bBuilder: .init({ a0, a1 in recorder.record("aBuilder.cBuilder.t0.bBuilder"); return B(t0: a0, cBuilder: a1) }), other: .init({ a0, a1 in recorder.record("aBuilder.cBuilder.t0.other"); return B(t0: a0, cBuilder: a1) }), { a0, a1, a2, a3 in recorder.record("aBuilder.cBuilder.t0"); return T0(aBuilder: a0, bBuilder: a1, again: a2, other: a3) }), { a0 in recorder.record("aBuilder.cBuilder"); return C(t0: a0) }), { a0, a1 in recorder.record("aBuilder"); return A(t0: a0, cBuilder: a1) }), bBuilder: .init({ a0, a1 in recorder.record("bBuilder"); return B(t0: a0, cBuilder: a1) }))
			}

			/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.
			func walks(seeds: Range<Int>, depth: Int) -> [String] {
			    let recorder = Recorder()
			    for seed in seeds {
			        recorder.record("walk \(seed)")
			        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
			        walk(Hub.mock(safeDIOverrides: overridesAtEveryPlace(recorder)), depth, &generator, recorder)
			    }
			    return recorder.log
			}

			/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.
			func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {
			    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
			    var reads: UInt64 = 0
			    for entry in walks(seeds: seeds, depth: depth) {
			        if !entry.hasPrefix("-> "), !entry.hasPrefix("walk ") { reads += 1 }
			        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
			        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3
			    }
			    return [reads, digest]
			}
			#endif
			"""#,
		], probes: [
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 12)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 12)"),
			DifferentialValueProbe("walks(seeds: 0 ..< 1, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 1 ..< 2, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 2 ..< 3, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 3 ..< 4, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 4 ..< 5, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 5 ..< 6, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 6 ..< 7, depth: 16)"),
			DifferentialValueProbe("walks(seeds: 7 ..< 8, depth: 16)"),
			DifferentialValueProbe("walkDigest(seeds: 0 ..< 400, depth: 16)"),
		], filesToDelete: &filesToDelete)
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
