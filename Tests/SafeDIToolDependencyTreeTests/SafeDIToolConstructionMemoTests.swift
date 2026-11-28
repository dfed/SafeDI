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
@testable import SafeDICore
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// A production tree reuses the generator of a place whose key and read log match an earlier place's. Each test here is
/// a shape where two places look alike to the memo in one way and differ in another; it generates the module with the
/// memo and without it and expects the same files, and `executeSafeDIToolTest` also builds every tree both ways and
/// compares them by reflection, path by path.
struct SafeDIToolConstructionMemoTests: ~Copyable {
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
	mutating func generate_generatesSameTreeWithMemoAsWithout_whenTwoPlacesReadEqualLogsFromDifferentProvidersUnderCycleWithParameters() async throws {
		// `A` is built beneath `Root` and beneath `D`; each declares `x` two levels above `B`, which receives it, so the two
		// places of `A` read equal logs from different declarations. `S`, between `A` and the scope closing the cycle on
		// it, declares `x` too, so `A`'s builder function takes `x` as a parameter.
		try await expectSameFilesWithMemoAsWithout(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let d: D"]),
			seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B", "@Instantiated let sBuilder: Instantiator<S>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesGeneratorHeldAtSomePlace_whenSharingScheduleDrawsBuildingAgain() async throws {
		// `X` is built at four places, each of which finds a candidate. A drawn schedule builds some of them again, and the
		// observer says so, while the generated files stay those of the run that shares wherever it can.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let a: A", "@Instantiated let b: B", "@Instantiated let c: C", "@Instantiated let d: D"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let x: X"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: X"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let x: X"]),
			seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: ["@Instantiated let y: Y"]),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		let shared = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		var observedChanges = [Bool]()
		for seed in UInt64(0)..<8 {
			let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
			let scheduled = try await ConstructionSharingSchedule.$current.withValue(ConstructionSharingSchedule(seed: seed, offersLaterPlacesCandidates: seed.isMultiple(of: 2))) { [fixture] in
				try await ConstructionSharingSchedule.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
					try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
				}
			}
			continuation.finish()
			for await changesHeldGenerator in stream {
				observedChanges.append(changesHeldGenerator)
			}
			#expect(scheduled.dependencyTreeFiles == shared.dependencyTreeFiles)
		}
		#expect(observedChanges.contains(true))
		#expect(observedChanges.contains(false))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesSameTreeWithMemoAsWithout_whenLazilyInstantiatedInstancesInScopeDifferWhereReadsDoNot() async throws {
		// `C` is built beneath `Root`, where `x`'s instance is in scope through its wrapper, and beneath `D`, whose own `x`
		// hides the wrapper; `C`'s tree reads no `x`.
		try await expectSameFilesWithMemoAsWithout(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let c: C", "@Instantiated let d: D"]),
			seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let c: C"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let e: E"]),
			seamFixtureType(named: "E", isFinalClass: true, declarations: []),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesSameTreeWithMemoAsWithout_whenPlacesReadAlikeDeclarationsAtDifferentDepths() async throws {
		// `C` receives `x`, which `Root` declares above the place `Root` builds and `D` declares again above the place `D`
		// builds, one level deeper: the two places read alike declarations answered at different depths, so the place that
		// reuses the other's generator records the read again at its own depth.
		try await expectSameFilesWithMemoAsWithout(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let c: C", "@Instantiated let d: D"]),
			seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let c: C"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received let x: X", "@Instantiated let e: E"]),
			seamFixtureType(named: "E", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsSameErrorWithMemoAsWithout_whenSiblingSubtreesSharingKeyThrow() async {
		// `P` and `Q` each build `G`, whose `childBuilder` spells a first generic that is not `Child`'s forwarded
		// properties, which construction throws; no partial build of `G` is kept.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let p: P", "@Instantiated let q: Q"]),
			seamFixtureType(named: "P", isFinalClass: true, declarations: ["@Instantiated let g: G"]),
			seamFixtureType(named: "Q", isFinalClass: true, declarations: ["@Instantiated let g: G"]),
			seamFixtureType(named: "G", isFinalClass: true, declarations: [#"@Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: ErasedInstantiator<Int, AnyChild>"#]),
			"""
			public final class AnyChild {
			    public init(_ child: Child) {}
			}
			""",
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Forwarded let name: String"]),
		]
		for isEnabled in [true, false] {
			await assertThrowsError(diagnostics: { fixtures in
				"""
				\(fixtures["G.swift"]):7:5: error: The first generic argument of `childBuilder: ErasedInstantiator<Int, AnyChild>` on `G` must be the @Forwarded properties of `Child`, which it builds. Declare it as `ErasedInstantiator<String, AnyChild>`.
				"""
			}) {
				try await ConstructionMemo.$isEnabled.withValue(isEnabled) { [fixture] in
					try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
				}
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsSendableOnClosedOnFunctionInBothRoots_whenOneRootDeclaresLazilyInstantiatedAndOtherConstantAndCycleClosesInsideSendableInstantiator() async throws {
		// `First` declares `a: LazilyInstantiated<A>` and `Second` declares `a: A`; in both, `C`, built in a `@Sendable`
		// function, closes the cycle on `a`'s builder function, which must therefore be `@Sendable` in both.
		let output = try await expectSameFilesWithMemoAsWithout(of: [
			seamFixtureType(named: "First", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let a: LazilyInstantiated<A>"]),
			seamFixtureType(named: "Second", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let a: A"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let cBuilder: SendableInstantiator<C>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let a: A"]),
		])
		#expect(output == [
			"First+SafeDI.swift": """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			extension First {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_a() -> A {
			            let cBuilder = SendableInstantiator<C>(__safeDI_cBuilder)
			            return A(cBuilder: cBuilder)
			        }
			        @Sendable nonisolated func __safeDI_cBuilder() -> C {
			            let a: A = __safeDI_a()
			            return C(a: a)
			        }
			        let a = LazilyInstantiated<A>(__safeDI_a)
			        self.init(a: a)
			    }
			}
			""",
			"Second+SafeDI.swift": """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			extension Second {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_a() -> A {
			            let cBuilder = SendableInstantiator<C>(__safeDI_cBuilder)
			            return A(cBuilder: cBuilder)
			        }
			        @Sendable nonisolated func __safeDI_cBuilder() -> C {
			            let a: A = __safeDI_a()
			            return C(a: a)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysNoPlaceInMemo_whenTreeBuildsEachTypeAtOnePlace() async throws {
		// `Root` builds `A` and `C`, and `A` builds `B`: no other place of the tree has a place's key, so none is keyed.
		let keyedTypes = try await typesKeyedInMemo(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let a: A", "@Instantiated let c: C"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: []),
			seamFixtureType(named: "C", isFinalClass: true, declarations: []),
		])
		#expect(keyedTypes == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysEveryPlaceInMemo_whenSharingScheduleOffersLaterPlacesCandidates() async throws {
		// The tree of `generate_keysNoPlaceInMemo_whenTreeBuildsEachTypeAtOnePlace`, whose places a discarded build of the
		// same pass stores first, so a place at one place can reuse what that build stored: every place is keyed.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let a: A", "@Instantiated let c: C"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: []),
			seamFixtureType(named: "C", isFinalClass: true, declarations: []),
		]
		let keyedTypes = try await ConstructionSharingSchedule.$current.withValue(ConstructionSharingSchedule(seed: nil, offersLaterPlacesCandidates: true)) {
			try await typesKeyedInMemo(of: fixture)
		}
		#expect(keyedTypes == ["A", "B", "C"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysOnlyPlacesOfTypesBuiltAtSeveralPlaces_whenTwoParentsBuildOneType() async throws {
		// `P` and `Q` each build `G`, which builds `H`: `G` and `H` are built at two places each, and `P` and `Q` at one.
		let keyedTypes = try await typesKeyedInMemo(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let p: P", "@Instantiated let q: Q"]),
			seamFixtureType(named: "P", isFinalClass: true, declarations: ["@Instantiated let g: G"]),
			seamFixtureType(named: "Q", isFinalClass: true, declarations: ["@Instantiated let g: G"]),
			seamFixtureType(named: "G", isFinalClass: true, declarations: ["@Instantiated let h: H"]),
			seamFixtureType(named: "H", isFinalClass: true, declarations: []),
		])
		#expect(keyedTypes == ["G", "H"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysEveryPlace_whenTypeBuildsBuilderOfTypeAboveIt() async throws {
		// `B` builds a builder of `A`, which builds `B`: the tree closes a cycle, so it may take a later pass, which reuses
		// what the pass before built only through its keys, so `C`, built at one place, is keyed too.
		let keyedTypes = try await typesKeyedInMemo(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let a: A", "@Instantiated let c: C"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: []),
		])
		#expect(keyedTypes == ["A", "B", "C"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsPlacesBeneathSettledPlaceOncePerTree_whenLazyCycleTakesSecondPass() async throws {
		// `B` receives `token`, which `A`, between the cycle `bBuilder` closes and the function it closes on, declares again:
		// the function takes `token`, which the first pass finds, so the tree takes a second pass. The chain `D0` to `D3`,
		// each built at one place, is keyed in the first pass, and the second reuses `D0`'s generator, settled, without
		// building `D1` to `D3` again: each place is counted where a pass keys it. The places of the cycle and of `Token`,
		// built at several places, are keyed at each place in each pass.
		let keyedPlaceCounts = try await keyedPlaceCountsInMemo(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let token: Token", "@Instantiated let a: A", "@Instantiated let d0: D0"]),
			seamFixtureType(named: "Token", isFinalClass: true, declarations: []),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let token: Token", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let token: Token", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "D0", isFinalClass: true, declarations: ["@Instantiated let d1: D1"]),
			seamFixtureType(named: "D1", isFinalClass: true, declarations: ["@Instantiated let d2: D2"]),
			seamFixtureType(named: "D2", isFinalClass: true, declarations: ["@Instantiated let d3: D3"]),
			seamFixtureType(named: "D3", isFinalClass: true, declarations: []),
		])
		#expect(keyedPlaceCounts == ["A": 4, "B": 4, "D0": 2, "D1": 1, "D2": 1, "D3": 1, "Token": 6])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysOnlyPlacesOfTypesBuiltAtSeveralPlaces_whenTreeIsSeamsOwn() async throws {
		// `Shell`'s own tree builds `A` at one place and `G`, with `H` beneath it, under both `P` and `Q`. `Root` builds `A`
		// too and calls `Shell`, so each tree builds `A` once: built inline, `A` would be built at two places and keyed.
		let keyedTypes = try await typesKeyedInMemo(
			of: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let a: A", "@Instantiated let shell: Shell"]),
				seamFixtureType(named: "Shell", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let a: A", "@Instantiated let p: P", "@Instantiated let q: Q"]),
				seamFixtureType(named: "A", isFinalClass: true, declarations: []),
				seamFixtureType(named: "P", isFinalClass: true, declarations: ["@Instantiated let g: G"]),
				seamFixtureType(named: "Q", isFinalClass: true, declarations: ["@Instantiated let g: G"]),
				seamFixtureType(named: "G", isFinalClass: true, declarations: ["@Instantiated let h: H"]),
				seamFixtureType(named: "H", isFinalClass: true, declarations: []),
			],
			moduleMembershipArguments: ["--module-name", "App"],
		)
		#expect(keyedTypes == ["G", "H"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysTypeBuiltOnceByItsTreeAndOnceAsFill_whenRootInstantiatesFulfillerOfSeamsHole() async throws {
		// `Core`'s seam `Feature` takes a builder of `any Service`, which `App`'s `DefaultService` fills. `App`'s root builds
		// `DefaultService` itself too, so the tree builds it at two places: once beneath `Root`, once as `Feature`'s fill.
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		_ = try await ConstructionMemoOracle.$keyedPlaceObserver.withValue(TaskLocalFunction { continuation.yield($0) }) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Core",
						packageName: "Shop",
						swiftFileContent: [
							"public protocol Service: AnyObject {}",
							seamFixtureType(named: "Feature", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let service: any Service"]),
						],
					),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Core

							@Instantiable(fulfillingAdditionalTypes: [Service.self])
							public final class DefaultService: Instantiable, Service {
							    public init() {}
							}
							""",
							"import Core\n\n" + seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let feature: Feature", "@Instantiated public let service: any Service"]),
						],
						dependencies: ["Core"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var keyedTypes = Set<String>()
		for await keyedType in stream {
			keyedTypes.insert(keyedType)
		}
		#expect(keyedTypes == ["DefaultService"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_asksOnlyMemoCandidatesItsContextAnswersAlike_whenScreensOpenEachOtherInCycles() async throws {
		// Screen `i` opens screens `i + 1` and `i + 3` (modulo the count) through an `Instantiator`, so every screen is built
		// inside many sets of other screens, and the memo keeps a candidate of its key for each set whose builders close
		// other cycles. A lookup follows what its own context answers each of those reads, so it asks at most the one
		// candidate built inside the same screens, at eight screens and at ten: asking each candidate of the key in turn
		// asked dozens per lookup, and more with every screen.
		var mostCandidatesAsked = [Int]()
		var lookupCounts = [Int]()
		for screenCount in [8, 10] {
			var fixture = [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let screen0Builder: Instantiator<Screen0>"]),
			]
			for screen in 0..<screenCount {
				fixture.append(seamFixtureType(named: "Screen\(screen)", isFinalClass: true, declarations: [1, 3].map {
					"@Instantiated let screen\((screen + $0) % screenCount)Builder: Instantiator<Screen\((screen + $0) % screenCount)>"
				}))
			}
			let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
			// Today's tree's look-ups: a plan's bodies share a memo of their own.
			_ = try await RootTreeChoiceObservation.$scopeGeneratorLimitOverride.withValue(.max) { try await GenerationWork.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) { [fixture] in
				try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, skipCompileVerification: true)
			} }
			continuation.finish()
			var candidatesAsked = [Int]()
			for await work in stream where work.step == .askingMemoCandidates {
				candidatesAsked.append(work.elementCount)
			}
			mostCandidatesAsked.append(candidatesAsked.max() ?? 0)
			lookupCounts.append(candidatesAsked.count)
		}
		#expect(mostCandidatesAsked == [1, 1])
		#expect(lookupCounts == [128, 224])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesTreeOutsideCycleInEveryBodyAfterTheFirst_whenParentsBuildTypeOnCycleUnderLabelsOfTheirOwn() async throws {
		// Each parent builds `A`, which opens itself, under a label of its own, so the root's plan builds a body of `A` for
		// each label. The tree of `T0` beneath `A` is built in the first body and reused in each other, through one memo for
		// the root's bodies: built once per body, it cost the number of labels times the tree (160 labels of a tree of 1,500
		// types took 30 seconds and 1.4 GB, against 1.2 seconds and 94 MB with the memo shared).
		var reusedTreeCounts = [Int]()
		var treeBuildCounts = [Int]()
		for parentCount in [2, 4] {
			var fixture = [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: (0..<parentCount).map { "@Instantiated let c\($0): C\($0)" }),
				seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let t0: T0", "@Instantiated let aBuilder: Instantiator<A>"]),
			]
			for parent in 0..<parentCount {
				fixture.append(seamFixtureType(named: "C\(parent)", isFinalClass: true, declarations: ["@Instantiated let a\(parent): A"]))
			}
			for type in 0..<7 {
				fixture.append(seamFixtureType(named: "T\(type)", isFinalClass: true, declarations: [2 * type + 1, 2 * type + 2].filter { $0 < 7 }.map { "@Instantiated let t\($0): T\($0)" }))
			}
			let (stream, continuation) = AsyncStream.makeStream(of: (type: String, isReuse: Bool).self)
			_ = try await ConstructionMemoOracle.$reusedPlaceObserver.withValue(TaskLocalFunction { concreteType, _ in continuation.yield((concreteType, true)) }) {
				try await ConstructionMemoOracle.$keyedPlaceObserver.withValue(TaskLocalFunction { continuation.yield(($0, false)) }) { [fixture] in
					try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
				}
			}
			continuation.finish()
			var reusedTrees = 0
			var treeBuilds = 0
			for await (type, isReuse) in stream {
				if isReuse, type == "T0" {
					reusedTrees += 1
				} else if !isReuse, type == "T6" {
					treeBuilds += 1
				}
			}
			reusedTreeCounts.append(reusedTrees)
			treeBuildCounts.append(treeBuilds)
		}
		// The tests' comparison builds today's tree beside the plan, which reuses `T0` as often again: half of each count.
		// With a memo per body the plan reuses nothing, and the counts are [2, 4].
		#expect(reusedTreeCounts == [4, 8])
		// The deepest type of the tree is keyed once by today's tree and once by the plan, however many labels build `A`.
		#expect(treeBuildCounts == [2, 2])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_filesNoMemoEntryUnderItsCycleReads_whenMockedRootBuildsChainOfFeatures() async throws {
		// A root with a generated mock builds feature 0 through an `Instantiator`, which builds feature 1, and so on: no
		// place is built twice, so each key of the memo holds one entry, which a lookup asks through its log. Filing each
		// entry under its cycle reads listed the reads of every feature beneath it, which grew with the square of the
		// chain's length: three times the time and five times the memory at 1,500 features.
		var cycleReadsFiled = [Int]()
		for featureCount in [20, 40] {
			var fixture = [
				seamFixtureType(named: "Service", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Root", isFinalClass: true, declarations: [
					"@Instantiated let service: Service",
					"@Instantiated let feature0Builder: Instantiator<Feature0>",
				]).replacingOccurrences(of: "@Instantiable", with: "@Instantiable(generateMock: true)"),
			]
			for feature in 0..<featureCount {
				fixture.append(seamFixtureType(named: "Feature\(feature)", isFinalClass: true, declarations: ["@Received let service: Service"] + (
					feature + 1 < featureCount ? ["@Instantiated let feature\(feature + 1)Builder: Instantiator<Feature\(feature + 1)>"] : []
				)))
			}
			let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
			_ = try await GenerationWork.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) { [fixture] in
				try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, skipCompileVerification: true)
			}
			continuation.finish()
			var filed = 0
			for await work in stream where work.step == .filingMemoEntryReads {
				filed += work.elementCount
			}
			cycleReadsFiled.append(filed)
		}
		#expect(cycleReadsFiled == [0, 0])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The sharing oracle's schedules: newest candidate first from a discarded build, and two seeds of drawn sharing.
	private static let sharingSchedules = [
		ConstructionSharingSchedule(seed: nil, offersLaterPlacesCandidates: true),
		ConstructionSharingSchedule(seed: 3, offersLaterPlacesCandidates: false),
		ConstructionSharingSchedule(seed: 5, offersLaterPlacesCandidates: true),
	]

	/// Generates `fixture` and returns the concrete type of each place a tree keyed in its construction memo.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func typesKeyedInMemo(of fixture: [String], moduleMembershipArguments: [String] = []) async throws -> Set<String> {
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		_ = try await ConstructionMemoOracle.$keyedPlaceObserver.withValue(TaskLocalFunction { continuation.yield($0) }) { [fixture] in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, moduleMembershipArguments: moduleMembershipArguments)
		}
		continuation.finish()
		var keyedTypes = Set<String>()
		for await keyedType in stream {
			keyedTypes.insert(keyedType)
		}
		return keyedTypes
	}

	/// Generates `fixture` and returns how many times a pass of a tree keyed a place of each concrete type in its
	/// construction memo.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func keyedPlaceCountsInMemo(of fixture: [String]) async throws -> [String: Int] {
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		// Today's tree's places: a plan's bodies share a memo of their own.
		_ = try await RootTreeChoiceObservation.$scopeGeneratorLimitOverride.withValue(.max) { try await ConstructionMemoOracle.$keyedPlaceObserver.withValue(TaskLocalFunction { continuation.yield($0) }) { [fixture] in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		} }
		continuation.finish()
		var keyedPlaceCounts = [String: Int]()
		for await keyedType in stream {
			keyedPlaceCounts[keyedType, default: 0] += 1
		}
		return keyedPlaceCounts
	}

	/// Generates `fixture` with the memo and without it, expects the same generated files, and returns them.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	@discardableResult
	private mutating func expectSameFilesWithMemoAsWithout(of fixture: [String]) async throws -> [String: String] {
		let withMemo = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let withoutMemo = try await ConstructionMemo.$isEnabled.withValue(false) { [fixture] in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(!withMemo.dependencyTreeFiles.isEmpty)
		#expect(withMemo.dependencyTreeFiles == withoutMemo.dependencyTreeFiles)
		// Which alike candidate a place takes, and whether it shares at all, reaches no output.
		for schedule in Self.sharingSchedules {
			let scheduled = try await ConstructionSharingSchedule.$current.withValue(schedule) { [fixture] in
				try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
			#expect(scheduled.dependencyTreeFiles == withMemo.dependencyTreeFiles)
		}
		return withMemo.dependencyTreeFiles
	}
}
