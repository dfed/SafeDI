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
import SafeDICore
import Testing
@testable import SafeDIToolTestSupport

/// Random dependency graphs, run through SafeDITool and the compiler. See "Graph fuzzer" in CLAUDE.md.
struct SafeDIToolGraphFuzzerTests {
	// MARK: Smoke batch

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_produceNoFailures_whenRunThroughToolAndCompiler() async throws {
		for result in try await smokeResults.value {
			if let failure = result.failure {
				Issue.record(failure.issueComment(fixture: result.fixture))
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_exerciseEveryFeature_inGraphsTheToolAccepts() async throws {
		// Features are read from the emitted source, so a generator that stops emitting one fails here. A generator
		// feature's own feature is drawn only with the generator feature on, which the seam smoke batch checks.
		let features = try await smokeResults.value
			.filter { $0.isAccepted && $0.failure == nil }
			.reduce(into: Set<GraphFuzzerFeature>()) { $0.formUnion(GraphFuzzerFeature.features(of: $1.fixture, outcome: $1.outcome)) }
		#expect(Set(GraphFuzzerFeature.baseCases).subtracting(features).sorted() == [])
	}

	@Test
	func constantCycleCloser_isReadFromBindings_thatCallFunctionsTheirOwnBodiesDoNotDeclare() {
		// A constant or lazily instantiated dependency with a tree of its own declares its function just before its
		// binding, at the same indentation; one that closes a cycle calls, or hands its wrapper, a function declared
		// further out. An instantiator that closes a cycle hands its wrapper a function declared further out too, but is
		// `lazyCycle`'s.
		let closed = { (closer: String) in
			GraphFuzzerFeature.closesCycleWithConstantOrLazilyInstantiatedDependency("""
			extension Root {
			    public convenience init() {
			        func __safeDI_a(session: Session) -> A {
			            func __safeDI_b() -> B {
			\(closer.split(separator: "\n").map { "                \($0)" }.joined(separator: "\n"))
			                return B()
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a: A = __safeDI_a(session: session)
			        let lazyA = LazilyInstantiated<A> {
			            __safeDI_a(session: session)
			        }
			        func __safeDI_c() -> C {
			            C()
			        }
			        let c = LazilyInstantiated<C>(__safeDI_c)
			        let erasedC = AnyC(__safeDI_c())
			        self.init(a: a, lazyA: lazyA, c: c, erasedC: erasedC)
			    }
			}
			""")
		}
		#expect(!closed(""))
		#expect(closed("let a: A = __safeDI_a(session: session)"))
		#expect(closed("let a = AnyA(__safeDI_a(session: session))"))
		#expect(closed("let a = LazilyInstantiated<A> {\n    __safeDI_a(session: session)\n}"))
		#expect(closed("let a = SendableLazilyInstantiated<AnyA> {\n    AnyA(__safeDI_a(session: session))\n}"))
		#expect(!closed("let aBuilder = Instantiator<A> {\n    __safeDI_a(session: session)\n}"))
		#expect(!closed("let aBuilder = ErasedInstantiator<(), AnyA> {\n    AnyA(__safeDI_a(session: session))\n}"))
		// Reserved names that are values or members, not builder functions.
		#expect(!GraphFuzzerFeature.closesCycleWithConstantOrLazilyInstantiatedDependency("""
		extension Root {
		    static func mock(x __safeDI_x: @autoclosure @escaping @Sendable () -> X, builder __safeDI_builder: @escaping () -> Y) -> Root {
		        let __safeDI_z = Z.make
		        func __safeDI_a() -> A {
		            let x = __safeDI_x()
		            let y = __safeDI_builder()
		            let z = __safeDI_z()
		            let w = W.__safeDI_init(x: x, safeDIBuilder: nil)
		            return A(x: x, y: y, z: z, w: w)
		        }
		        let a: A = __safeDI_a()
		        return Root(a: a)
		    }
		}
		"""))
	}

	@Test
	func constantCycleCloser_isReadOnlyFromCallsThatReachTheirOwnFunction_whenTheTypeKeyDeclaresEveryFunctionInTheRootsBody() {
		// The type key declares every builder function in the root's body, so a function's call of another is further out
		// whether or not it closes a cycle. Only a call whose function reaches back to one the call is inside closes one.
		let closed = { (bCall: String) in
			GraphFuzzerFeature.closesCycleWithConstantOrLazilyInstantiatedDependency("""
			extension Root {
			    public convenience init() {
			        let a: A = __safeDI_a()
			        self.init(a: a)
			        func __safeDI_a() -> A {
			            let b: B = __safeDI_b()
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return A(b: b, cBuilder: cBuilder)
			        }
			        func __safeDI_b() -> B {
			            let leaf: Leaf = __safeDI_leaf()
			            return B(leaf: leaf)
			        }
			        func __safeDI_leaf() -> Leaf {
			            Leaf()
			        }
			        func __safeDI_cBuilder() -> C {
			\(bCall.split(separator: "\n").map { "            \($0)" }.joined(separator: "\n"))
			            return C()
			        }
			    }
			}
			""")
		}
		#expect(!closed(""))
		#expect(!closed("let b: B = __safeDI_b()"))
		#expect(closed("let a: A = __safeDI_a()"))
		#expect(closed("let a = LazilyInstantiated<A> {\n    __safeDI_a()\n}"))
		#expect(!closed("let leaf = LazilyInstantiated<Leaf>(__safeDI_leaf)"))
	}

	@Test
	func receivedBuilderLoopFeatures_readBuilderLeftNilBesideOwnBuilder_whenTypeReceivesItsOwnBuilderOnlyIfAvailable() {
		// `T4`'s builder function wraps its own function again, and passes `nil` for `t2Builder`, which a sibling builder
		// function is named for. Only where `T4` receives `t4Builder` only if available is that the feature: a required
		// receive was always given.
		let code = """
		extension Root {
		    public convenience init() {
		        func __safeDI_t4Builder() -> T4 {
		            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
		            return T4(t4Builder: t4Builder, t2Builder: nil)
		        }
		        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
		        let t3 = T3(t4Builder: t4Builder)
		        func __safeDI_t2Builder() -> T2 {
		            T2(t3: t3)
		        }
		        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
		        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
		    }
		}
		"""
		let features = { (onlyIfAvailableLabels: [String: Set<String>]) in
			GraphFuzzerFeature.receivedBuilderLoopFeatures(of: code, instantiatedLabelsByTypeName: [:], onlyIfAvailableReceivedLabelsByTypeName: onlyIfAvailableLabels).sorted()
		}
		#expect(features(["T4": ["t4Builder", "t2Builder"]]) == [.builderReceivedInsideItsTree, .builderReceivedInsideItsTreeBesideBuilderLeftNil])
		#expect(features(["T4": ["t2Builder"]]) == [.builderReceivedInsideItsTree])
		// The labels are read from the fixture's `@Received(onlyIfAvailable: true)` properties, by type.
		let fixture = GraphFuzzerFixture(seed: 0, swiftFileContent: ["""
		@Instantiable
		public final class T4: Instantiable {
		\t@Received(onlyIfAvailable: true) let t4Builder: Instantiator<T4>?
		\t@Received let t3: T3
		}
		"""])
		#expect(GraphFuzzerFeature.onlyIfAvailableReceivedLabelsByTypeName(of: fixture) == ["T4": ["t4Builder"]])
	}

	@Test
	func receivedBuilderLoopFeatures_areReadFromBindings_thatWrapBuilderFunctionsOfTheirFunctionsScopeFirst() {
		// A loop member's builder function begins by wrapping again a function its scope declares: its own, or the function
		// that wraps its own with cycle arguments, for an instantiator received inside its tree, and another member's
		// otherwise. An instantiator that closes an instantiated cycle wraps a function declared further out, or its own
		// function under a label its type instantiates.
		let features = { (code: String, instantiatedLabels: [String: Set<String>]) in
			GraphFuzzerFeature.receivedBuilderLoopFeatures(of: code, instantiatedLabelsByTypeName: instantiatedLabels).sorted()
		}
		let receivingEachOther = """
		extension Root {
		    public convenience init() {
		        func __safeDI_aBuilder() -> A {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            return A(bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        func __safeDI_bBuilder() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            return B(aBuilder: aBuilder)
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
		    }
		}
		"""
		#expect(features(receivingEachOther, [:]) == [.buildersReceivingEachOther])
		#expect(features(receivingEachOther.replacingOccurrences(of: "Instantiator<", with: "SendableInstantiator<").replacingOccurrences(of: "func __safeDI_", with: "@Sendable nonisolated func __safeDI_"), [:]) == [.sendableBuildersReceivingEachOther])
		let selfReceiving = """
		extension Root {
		    public convenience init() {
		        func __safeDI_nodeBuilder() -> Node {
		            let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
		            return Node(nodeBuilder: nodeBuilder)
		        }
		        let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
		        self.init(nodeBuilder: nodeBuilder)
		    }
		}
		"""
		#expect(features(selfReceiving, [:]) == [.builderReceivedInsideItsTree])
		// The same code, where `Node` instantiates `nodeBuilder` itself: a cycle that the instantiator closes.
		#expect(features(selfReceiving, ["Node": ["nodeBuilder"]]) == [])
		// A mock of a `Node` that instantiates an erased instantiator of itself: its builder function returns the erased
		// type, under which the fixture's instantiated labels are read too.
		let erasedSelfInstantiating = GraphFuzzerFixture(seed: 0, swiftFileContent: ["""
		@Instantiable(generateMock: true)
		public final class Node: Instantiable {
		\t@Instantiated(fulfilledByType: "Node", erasedToConcreteExistential: true) let anyNodeBuilder: ErasedInstantiator<(), AnyNode>
		}
		"""])
		#expect(features("""
		extension Node {
		    public static func mock() -> Node {
		        func __safeDI_anyNodeBuilder() -> AnyNode {
		            let anyNodeBuilder = ErasedInstantiator<(), AnyNode>(__safeDI_anyNodeBuilder)
		            return AnyNode(Node(anyNodeBuilder: anyNodeBuilder))
		        }
		        let anyNodeBuilder = ErasedInstantiator<(), AnyNode>(__safeDI_anyNodeBuilder)
		        return Node(anyNodeBuilder: anyNodeBuilder)
		    }
		}
		""", GraphFuzzerFeature.instantiatedLabelsByTypeName(of: erasedSelfInstantiating)) == [])
		#expect(features("""
		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_screenBuilder(session: Session) -> Screen {
		            let screenBuilder = SendableInstantiator<Screen> {
		                __safeDI_screenBuilder(session: session)
		            }
		            @Sendable nonisolated func __safeDI_stepBuilder() -> Step {
		                let session = Session()
		                let screenBuilder = SendableInstantiator<Screen> {
		                    __safeDI_screenBuilder(session: session)
		                }
		                return Step(session: session, screenBuilder: screenBuilder)
		            }
		            let stepBuilder = SendableInstantiator<Step>(__safeDI_stepBuilder)
		            return Screen(session: session, stepBuilder: stepBuilder, detail: Detail(screenBuilder: screenBuilder))
		        }
		        @Sendable nonisolated func __safeDI_screenBuilder_received() -> Screen {
		            __safeDI_screenBuilder(session: session)
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder_received)
		        self.init(session: session, screenBuilder: screenBuilder)
		    }
		}
		""", ["Step": ["session", "screenBuilder"]]) == [.sendableBuilderReceivedInsideItsTree, .sendableReceivedLoopMemberWithCycleParameters])
		#expect(features("""
		extension Root {
		    public convenience init() {
		        func __safeDI_otherBuilder() -> Other {
		            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
		            return Other(screenBuilder: screenBuilder)
		        }
		        let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
		        func __safeDI_screenBuilder(otherBuilder: Instantiator<Other>) -> Screen {
		            return Screen(detail: Detail(otherBuilder: otherBuilder))
		        }
		        func __safeDI_screenBuilder_received() -> Screen {
		            let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
		            return __safeDI_screenBuilder(otherBuilder: otherBuilder)
		        }
		        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
		        self.init(otherBuilder: otherBuilder, screenBuilder: screenBuilder)
		    }
		}
		""", [:]) == [.buildersReceivingEachOther, .receivedLoopMemberWithCycleParameters])
		// An instantiator that closes a longer cycle wraps a function declared further out than its function's siblings.
		#expect(features("""
		extension Root {
		    public convenience init() {
		        func __safeDI_aBuilder() -> A {
		            func __safeDI_bBuilder() -> B {
		                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		                return B(aBuilder: aBuilder)
		            }
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            return A(bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        self.init(aBuilder: aBuilder)
		    }
		}
		""", [:]) == [])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The value oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_compareRootAndMirroredPairsShowingEveryShape_whenRunThroughValueOracle() async throws {
		// The base smoke batch's graphs that pass compare a root's mock and a mocked type's mock with their production
		// builds, and between them show every shape the corpus's compared pairs show.
		var counts = GraphFuzzerValueOracleCounts()
		for result in try await smokeResults.value where result.failure == nil {
			if let valueOracle = result.valueOracle {
				counts.add(valueOracle, isCompared: result.isComparedByValueOracle)
			}
		}
		#expect(counts.rootPairCount > 0)
		#expect(counts.mirroredPairCount > 0)
		// The override oracle passes a sentinel through each kind of field.
		#expect(GraphFuzzerOverrideFieldKind.allCases.filter { counts.overrideFieldKindCounts[$0, default: 0] == 0 } == [])
		// And through each kind of dependency it judges.
		#expect(GraphFuzzerOverrideCandidateKind.allCases.filter { counts.overrideCandidateKindCounts[$0, default: 0] == 0 } == [])
		let shapesTheCorpusShows = GraphFuzzerValueOracleShape.allCases.filter { Self.corpusValueOracleCounts.shapeCounts[$0, default: 0] > 0 }
		#expect(shapesTheCorpusShows.filter { counts.shapeCounts[$0, default: 0] == 0 } == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func seamSmokeSeeds_produceNoUnknownFailures_whenRunThroughToolAndCompiler() async throws {
		// The smoke batch's graphs pass, but those the in-seam leak fails until its fix, and those with a hole, which
		// fail the builder surface until the planned builder structs, which must fail exactly as listed
		// (`seamSmokeKnownIssuesBySeed`).
		for result in try await seamSmokeResults.value {
			for finding in GraphFuzzerFinding.findings(failure: result.failure, laterFailures: result.laterFailures, knownIssue: Self.seamSmokeKnownIssuesBySeed[result.fixture.seed], retentionIsJudged: result.isJudgedForRetention) {
				switch finding {
				case .passed, .knownIssue:
					break
				case let .staleKnownIssue(knownIssue):
					Issue.record("Seed \(result.fixture.seed) no longer fails: \(knownIssue.reason)")
				case let .staleRenamedGraphDifference(knownIssue, aspect):
					Issue.record("Seed \(result.fixture.seed) sits on \"\(knownIssue.reason)\", which lists \(aspect.rawValue), but its renamed graphs do not show it.")
				case let .staleBuilderSurfaceSignature(knownIssue, kind):
					Issue.record("Seed \(result.fixture.seed) sits on \"\(knownIssue.reason)\", which lists \(kind.rawValue), but the graph does not show it.")
				case let .staleLeakEntry(knownIssue):
					Issue.record("Seed \(result.fixture.seed) sits on \"\(knownIssue.reason)\", which lists a leak the graph no longer shows.")
				case let .failure(failure):
					Issue.record(failure.issueComment(fixture: result.fixture))
				}
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func seamSmokeSeeds_judgeLevelFunctionCaptures_withSameCountsWithAndWithoutCompiles() async throws {
		// The level function capture check reads the generated text, so the call in `GraphFuzzerOracle.results(of:)` puts the
		// same findings and counts on each accepted graph's result whether or not the run compiles: these literals hold in
		// both modes.
		let captures = try await seamSmokeResults.value.reduce(into: [UInt64: GraphFuzzerLevelFunctionCaptures]()) { captures, result in
			captures[result.fixture.seed] = result.levelFunctionCaptures
		}

		#expect(captures == [
			1: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 0, namedMemberClosureCount: 0, conversionFunctionCount: 0, fillFunctionCount: 0),
			16: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 0, namedMemberClosureCount: 0, conversionFunctionCount: 0, fillFunctionCount: 0),
			24: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 26, namedMemberClosureCount: 1, conversionFunctionCount: 0, fillFunctionCount: 0),
			68: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 76, namedMemberClosureCount: 11, conversionFunctionCount: 0, fillFunctionCount: 1),
			84: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 68, namedMemberClosureCount: 6, conversionFunctionCount: 0, fillFunctionCount: 3),
			92: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 0, namedMemberClosureCount: 0, conversionFunctionCount: 0, fillFunctionCount: 0),
			93: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 67, namedMemberClosureCount: 6, conversionFunctionCount: 0, fillFunctionCount: 0),
			151: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 62, namedMemberClosureCount: 8, conversionFunctionCount: 0, fillFunctionCount: 2),
			153: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 67, namedMemberClosureCount: 4, conversionFunctionCount: 0, fillFunctionCount: 2),
			164: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 40, namedMemberClosureCount: 10, conversionFunctionCount: 0, fillFunctionCount: 0),
			180: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 52, namedMemberClosureCount: 2, conversionFunctionCount: 0, fillFunctionCount: 1),
			215: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 39, namedMemberClosureCount: 0, conversionFunctionCount: 0, fillFunctionCount: 0),
			227: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 66, namedMemberClosureCount: 2, conversionFunctionCount: 0, fillFunctionCount: 0),
			273: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 154, namedMemberClosureCount: 22, conversionFunctionCount: 0, fillFunctionCount: 2),
			277: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 50, namedMemberClosureCount: 2, conversionFunctionCount: 0, fillFunctionCount: 2),
			309: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 50, namedMemberClosureCount: 12, conversionFunctionCount: 0, fillFunctionCount: 2),
			347: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 80, namedMemberClosureCount: 15, conversionFunctionCount: 0, fillFunctionCount: 2),
			468: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 63, namedMemberClosureCount: 3, conversionFunctionCount: 0, fillFunctionCount: 1),
			594: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 75, namedMemberClosureCount: 26, conversionFunctionCount: 0, fillFunctionCount: 11),
			605: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 96, namedMemberClosureCount: 22, conversionFunctionCount: 0, fillFunctionCount: 1),
			705: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 42, namedMemberClosureCount: 1, conversionFunctionCount: 0, fillFunctionCount: 1),
			850: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 81, namedMemberClosureCount: 16, conversionFunctionCount: 0, fillFunctionCount: 3),
			881: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 0, namedMemberClosureCount: 0, conversionFunctionCount: 0, fillFunctionCount: 0),
			892: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 100, namedMemberClosureCount: 19, conversionFunctionCount: 0, fillFunctionCount: 7),
			934: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 54, namedMemberClosureCount: 1, conversionFunctionCount: 0, fillFunctionCount: 1),
			969: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 77, namedMemberClosureCount: 18, conversionFunctionCount: 0, fillFunctionCount: 11),
			1_020: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 83, namedMemberClosureCount: 25, conversionFunctionCount: 0, fillFunctionCount: 4),
			1_450: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 91, namedMemberClosureCount: 9, conversionFunctionCount: 0, fillFunctionCount: 4),
			1_837: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 0, namedMemberClosureCount: 0, conversionFunctionCount: 0, fillFunctionCount: 0),
			1_890: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 102, namedMemberClosureCount: 6, conversionFunctionCount: 0, fillFunctionCount: 4),
			1_986: GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 87, namedMemberClosureCount: 4, conversionFunctionCount: 0, fillFunctionCount: 2),
		])
	}

	@Test
	func seamSmokeKnownIssuesBeyondTheCorpus_listOnlySmokeSeedsBeyondTheCorpusOnce() {
		let seeds = Self.seamSmokeKnownIssuesBeyondTheCorpus.flatMap(\.seeds)
		#expect(seeds == seeds.sorted() && Set(seeds).count == seeds.count)
		#expect(seeds.allSatisfy { $0 >= UInt64(Self.seamCorpusSeedCount) && Self.seamSmokeSeeds.contains($0) })
	}

	@Test
	func passes_countsGraph_whenItsOnlyRenamedDifferenceIsTheBuilderOrderItsEntryLists() {
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "\(Self.seamBuilderOrderReason); and \(Self.inSeamLeakReason)",
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder)] + Self.inSeamLeakSignatures,
			seeds: [309],
		)
		let result = Self.acceptedResult(seed: 309, failingWith: [Self.renamedGraphFailure(seed: 309, aspect: .dependencyTreeListOrder)])

		#expect(result.passes(butForRetentionDocumentedBy: knownIssue, butForBuilderOrderDocumentedBy: Self.seamBuilderOrderShape(listedBy: knownIssue)))
	}

	@Test
	func passes_doesNotCountGraph_whenItsRenamedDifferenceIsOutsideTheBuilderOrderItsEntryLists() {
		// The entry lists the builder order and a lazy cycle's configuration field: only the first is sanctioned, so a
		// renamed graph's mock that drops a field still keeps the graph from counting.
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "\(Self.seamBuilderOrderReason); and \(Self.lazyCycleConfigurationFieldReason)",
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder), .renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [19],
		)
		let result = Self.acceptedResult(seed: 19, failingWith: [
			Self.renamedGraphFailure(seed: 19, aspect: .dependencyTreeListOrder),
			Self.renamedGraphFailure(seed: 19, aspect: .mockConfigurationFieldPresence),
		])

		#expect(!result.passes(butForRetentionDocumentedBy: knownIssue, butForBuilderOrderDocumentedBy: Self.seamBuilderOrderShape(listedBy: knownIssue)))
	}

	@Test
	func passes_doesNotCountGraph_whenItsEntryListsAnotherReasonForTheDependencyTreeDifference() {
		// A seam's pass-throughs sorted by label change the same generated code, but the entry does not list the builder
		// order, so no shape is handed over and the difference keeps the graph from counting.
		let knownIssue = GraphFuzzerKnownIssue(
			reason: Self.labelSortedPassThroughReason,
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder)],
			seeds: [950],
		)
		let result = Self.acceptedResult(seed: 950, failingWith: [Self.renamedGraphFailure(seed: 950, aspect: .dependencyTreeListOrder)])

		#expect(Self.seamBuilderOrderShape(listedBy: knownIssue) == nil)
		#expect(!result.passes(butForRetentionDocumentedBy: knownIssue, butForBuilderOrderDocumentedBy: Self.seamBuilderOrderShape(listedBy: knownIssue)))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_reportListOrder_whenTypeNameRenamingReordersSeamsBuilders() {
		let differences = Self.treeDifferences(code: Self.builderOrderCode, otherCode: Self.builderOrderReorderedCode, renaming: Self.movingTypeNames)

		#expect(differences == [GraphFuzzerOutcomeDifference(aspect: .dependencyTreeListOrder, fileName: "FuzzFeature/S1_HoleSeam+SafeDI.swift")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_reportListOrder_whenArgumentsSpanningSeveralLinesMove() {
		// Seed 163's kept outer seam calls `HoleSeam` with builder structs spelled over several lines, which the move of type
		// names reorders: each argument's lines move with it, so no line holds the same parts in both outcomes.
		let differences = Self.treeDifferences(code: Self.multiLineBuildersCode, otherCode: Self.multiLineBuildersReorderedCode, renaming: Self.movingTypeNames)

		#expect(differences == [GraphFuzzerOutcomeDifference(aspect: .dependencyTreeListOrder, fileName: "FuzzFeature/S1_HoleSeam+SafeDI.swift")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_reportTreeCode_whenFileNameReversalReordersSeamsBuilders() {
		// Reversing file names moves no label sort, so the same reorder is the file's code.
		let differences = Self.treeDifferences(code: Self.builderOrderCode, otherCode: Self.builderOrderReorderedCode, renaming: Self.reversingFileNames)

		#expect(differences == [GraphFuzzerOutcomeDifference(aspect: .dependencyTreeCode, fileName: "FuzzFeature/S1_HoleSeam+SafeDI.swift")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_reportTreeCode_whenReorderComesWithRespelledType() {
		// Seed 163's readable initializer: its builders reordered, and the forwarded `Int` spelled `Swift.Int`.
		let otherCode = Self.builderOrderReorderedCode.replacingOccurrences(of: "ErasedInstantiator<Int,", with: "ErasedInstantiator<Swift.Int,")
		#expect(otherCode != Self.builderOrderReorderedCode)

		let differences = Self.treeDifferences(code: Self.builderOrderCode, otherCode: otherCode, renaming: Self.movingTypeNames)

		#expect(differences == [GraphFuzzerOutcomeDifference(aspect: .dependencyTreeCode, fileName: "FuzzFeature/S1_HoleSeam+SafeDI.swift")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_reportTreeCode_whenArgumentValuesSwapBetweenLabels() {
		let code = "        self.init(holeService: holeService, holeTicket: holeTicket)\n"
		let otherCode = "        self.init(holeService: holeTicket, holeTicket: holeService)\n"

		let differences = Self.treeDifferences(code: code, otherCode: otherCode, renaming: Self.movingTypeNames)

		#expect(differences == [GraphFuzzerOutcomeDifference(aspect: .dependencyTreeCode, fileName: "FuzzFeature/S1_HoleSeam+SafeDI.swift")])
	}

	@Test(arguments: [
		// A value swapped between two nested calls: the same parts, each call's list another.
		(
			"        __safeDI_holeServiceBuilder(.holeSeam(.holeOwner(holeOwnerValues), .holeService(holeServiceValues)))\n",
			"        __safeDI_holeServiceBuilder(.holeSeam(.holeOwner(holeServiceValues), .holeService(holeOwnerValues)))\n",
		),
		// An argument moved from one call to another.
		(
			"        self.init(holeSeam: .init(holeService: holeService, holeTicket: holeTicket), holeOuter: .init(holeAnalytics: holeAnalytics))\n",
			"        self.init(holeSeam: .init(holeService: holeService), holeOuter: .init(holeTicket: holeTicket, holeAnalytics: holeAnalytics))\n",
		),
		// An argument moved into a call nested in its list.
		(
			"        self.init(holeSeam: .init(holeService: holeService), holeTicket: holeTicket)\n",
			"        self.init(holeSeam: .init(holeService: holeService, holeTicket: holeTicket))\n",
		),
		// A statement moved out of the `#sourceLocation` run it was in, in one block.
		(
			"    func __safeDI_holeSeam() -> HoleSeam {\n        #sourceLocation(file: \"HoleSeam.swift\", line: 3)\n        let holeService = HoleImpl()\n        #sourceLocation()\n        return HoleSeam(holeService: holeService)\n    }\n",
			"    func __safeDI_holeSeam() -> HoleSeam {\n        #sourceLocation(file: \"HoleSeam.swift\", line: 3)\n        #sourceLocation()\n        let holeService = HoleImpl()\n        return HoleSeam(holeService: holeService)\n    }\n",
		),
		// A statement moved from one function's body to another's.
		(
			"    func __safeDI_holeSeam() -> HoleSeam {\n        let holeService = HoleImpl()\n        let holeTicket = HoleTicket()\n        return HoleSeam(holeService: holeService)\n    }\n    func __safeDI_holeOuter() -> HoleOuter {\n        return HoleOuter()\n    }\n",
			"    func __safeDI_holeSeam() -> HoleSeam {\n        let holeService = HoleImpl()\n        return HoleSeam(holeService: holeService)\n    }\n    func __safeDI_holeOuter() -> HoleOuter {\n        let holeTicket = HoleTicket()\n        return HoleOuter()\n    }\n",
		),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_reportTreeCode_whenListsHoldOtherItemsThoughTheFileHoldsTheSameParts(code: String, otherCode: String) {
		let differences = Self.treeDifferences(code: code, otherCode: otherCode, renaming: Self.movingTypeNames)

		#expect(differences == [GraphFuzzerOutcomeDifference(aspect: .dependencyTreeCode, fileName: "FuzzFeature/S1_HoleSeam+SafeDI.swift")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_reportListOrder_whenCarrierMembersClosureNamesRootLevelsValuesInOtherLabelOrder() {
		// Seed 330's shape: a carrier member takes the seam root's values positionally, in its pass-throughs' label order,
		// so reversing the labels reorders the names of the caller's closure's parameters with the arguments of the call.
		let code = "extension Root {\n    func __safeDI_builder() -> Seam.__safeDI_ServiceCarrier<any Service> {\n        .init(service: { scope_tag, scope_note, scope_aBuilder in\n            let service: any Service = Impl()\n            return service\n        })\n    }\n}\n"
		let otherCode = code.replacingOccurrences(of: "scope_tag, scope_note,", with: "scope_note, scope_tag,")
		#expect(otherCode != code)

		let differences = Self.treeDifferences(code: code, otherCode: otherCode, renaming: Self.reversingLabels)

		#expect(differences == [GraphFuzzerOutcomeDifference(aspect: .dependencyTreeListOrder, fileName: "FuzzFeature/S1_HoleSeam+SafeDI.swift")])
	}

	@Test(arguments: [
		// Not a carrier member's names: no payload name joins them.
		"        _ = Carrier(service: { first, second in\n            0\n        })\n",
		// Not passed under an argument label.
		"        let service = { scope_tag, scope_note in\n            0\n        }\n",
		// Names of two payloads.
		"        _ = Carrier(service: { scope_tag, values_note in\n            0\n        })\n",
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_reportTreeCode_whenLabelOrderChangesClosureThatIsNoCarrierMembers(closure: String) throws {
		// The sort of a closure's parameter names is scoped to a caller's closure for a carrier's member: any other closure
		// whose names a label reversal reorders is the file's code.
		let code = "extension Root {\n    func make() {\n\(closure)    }\n}\n"
		let names = try #require(closure.range(of: #"\{ \w+, \w+ in"#, options: .regularExpression))
		let parts = closure[names].dropFirst(2).dropLast(3).components(separatedBy: ", ")
		let otherCode = code.replacingOccurrences(of: "{ \(parts[0]), \(parts[1]) in", with: "{ \(parts[1]), \(parts[0]) in")
		#expect(otherCode != code)

		let differences = Self.treeDifferences(code: code, otherCode: otherCode, renaming: Self.reversingLabels)

		#expect(differences == [GraphFuzzerOutcomeDifference(aspect: .dependencyTreeCode, fileName: "FuzzFeature/S1_HoleSeam+SafeDI.swift")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_reportTreeCode_whenClosureParameterNamesMoveIntoItsBody() {
		// Only the names of a carrier member closure's parameter clause are sorted: a name moved past `in` into the body is
		// the file's code.
		let code = "extension Root {\n    func make() -> Carrier {\n        .init(service: { scope_tag, scope_note in\n            scope_tag\n        })\n    }\n}\n"
		let otherCode = code.replacingOccurrences(of: "{ scope_tag, scope_note in\n            scope_tag", with: "{ scope_tag, scope_tag in\n            scope_note")

		let differences = Self.treeDifferences(code: code, otherCode: otherCode, renaming: Self.reversingLabels)

		#expect(differences == [GraphFuzzerOutcomeDifference(aspect: .dependencyTreeCode, fileName: "FuzzFeature/S1_HoleSeam+SafeDI.swift")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_reportListOrder_whenSiblingDeclarationsOfOneBlockMove() {
		// A seam's builder functions, declared in one body in label order, which the move of type names reorders with the
		// cases of a switch: each function's lines move with it, and its own statements keep their block.
		let code = "extension Root {\n    func __safeDI_holeServiceBuilder(_ scope: Scope) -> any HoleService {\n        switch scope {\n        case let .holeOwner(values): return HoleImpl(values.holeAnalytics)\n        case let .holeSeam(values): return HoleImpl(values.holeAnalytics)\n        }\n    }\n    func __safeDI_holeTicketBuilder(_ scope: Scope) -> any HoleTicket {\n        switch scope {\n        case let .holeTicketHolder(values): return HoleTicketImpl()\n        }\n    }\n}\n"
		let otherCode = "extension Root {\n    func __safeDI_holeTicketBuilder(_ scope: Scope) -> any HoleTicket {\n        switch scope {\n        case let .holeTicketHolder(values): return HoleTicketImpl()\n        }\n    }\n    func __safeDI_holeServiceBuilder(_ scope: Scope) -> any HoleService {\n        switch scope {\n        case let .holeSeam(values): return HoleImpl(values.holeAnalytics)\n        case let .holeOwner(values): return HoleImpl(values.holeAnalytics)\n        }\n    }\n}\n"

		let differences = Self.treeDifferences(code: code, otherCode: otherCode, renaming: Self.movingTypeNames)

		#expect(differences == [GraphFuzzerOutcomeDifference(aspect: .dependencyTreeListOrder, fileName: "FuzzFeature/S1_HoleSeam+SafeDI.swift")])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "An order-only difference is checked by compiling the renamed graph's code"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func results_reportTreeCode_whenRenamedGraphsOrderOnlyDifferenceReadsValueBeforeItsDeclaration() async throws {
		// A renamed graph whose code, with its renaming undone, differs from the graph's only in the order of two statements
		// of one block, the first of which now reads the value the second declares: the canonical form finds an order alone,
		// but the code does not compile with the graph, so the difference is the file's code.
		let renamedRuns = try #require(try await Self.seed454Runs(withRenamedCodeEditedBy: Self.codeReadingValueBeforeItsDeclaration(in:)))
		#expect(renamedRuns.renamedGraphFailures.map(\.renamedGraphDifference) == [.dependencyTreeListOrder])

		let result = try #require(try await GraphFuzzerOracle.results(of: [renamedRuns]).first)

		#expect(result.renamedGraphFailures.map(\.renamedGraphDifference) == [.dependencyTreeCode])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "An order-only difference is checked by comparing the renamed graph's values"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func listOrderRefutation_refutesOrder_whenRenamedCodeSwapsUnlabeledArgumentsOfOneType() async throws {
		// Two unlabeled arguments of one type swapped: the canonical form sorts a list's items, labeled or not, so it finds
		// an order alone, and the code compiles; its values differ, which refutes the order.
		let fixture = """
		public final class Holder {
		    public init(label: String) {
		        self.label = label
		    }
		    public let label: String
		}

		public final class Pair {
		    public init(_ first: Holder, _ second: Holder) {
		        self.first = first
		        self.second = second
		    }
		    public let first: Holder
		    public let second: Holder
		}
		"""
		let code = "extension Pair {\n    static func make() -> Pair {\n        let left = Holder(label: \"left\")\n        let right = Holder(label: \"right\")\n        return Pair(left, right)\n    }\n}\n"
		let swappedCode = code.replacingOccurrences(of: "Pair(left, right)", with: "Pair(right, left)")
		#expect(swappedCode != code)
		#expect(GraphFuzzerOutcomeDifference.listsInCanonicalOrder(of: swappedCode) == GraphFuzzerOutcomeDifference.listsInCanonicalOrder(of: code))
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}
		func comparison(of featureCode: String) async throws -> DifferentialValueComparison {
			try #require(try await DifferentialValueOracle.compare(
				feature: DifferentialValuePath(fixtureFiles: ["Pair.swift": fixture], generatedFiles: ["Pair+SafeDI.swift": featureCode]),
				knownRight: DifferentialValuePath(fixtureFiles: ["Pair.swift": fixture], generatedFiles: ["Pair+SafeDI.swift": code]),
				probes: [DifferentialValueProbe("Pair.make()")],
				filesToDelete: &filesToDelete,
			))
		}
		let ownComparison = try await comparison(of: code)
		let swappedComparison = try await comparison(of: swappedCode)
		#expect(ownComparison.differences.isEmpty)

		#expect(GraphFuzzerOracle.listOrderRefutation(of: .success(ownComparison), by: .success(swappedComparison)) != nil)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "An order-only difference is checked by compiling the renamed graph's code"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func listOrderRefutation_refutesOrder_whenRenamedCodeDoesNotCompileBesideOwnComparisonThatRanOutOfTraversals() async throws {
		// Seed 391's shape: the graph's own probes run out of traversals, so its own comparison fails as they run. A renamed
		// graph whose order-only difference reads a value before its declaration fails otherwise, as it compiles, so the
		// difference is still the file's code.
		let renamedRuns = try #require(try await Self.seed454Runs(withRenamedCodeEditedBy: Self.codeReadingValueBeforeItsDeclaration(in:)))
		let graph = try #require(GraphFuzzerOracle.seamValueGraph(of: renamedRuns))
		let (renamedIndex, renamedGraph) = try #require(GraphFuzzerOracle.listOrderGraphs(of: renamedRuns, beside: graph).first)
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}
		let renamedComparison = try #require(try await DifferentialValueOracle.compare(graphs: [renamedGraph], limits: DifferentialValueLimits(), filesToDelete: &filesToDelete)?.first)
		let ownFailure = DifferentialValueOracleError(path: .feature, stage: .runningProbes, description: "probe `S454_Root0()` spent its 200000 traversals")

		let refutation = try #require(GraphFuzzerOracle.listOrderRefutation(of: .failure(ownFailure), by: renamedComparison.result))

		#expect(renamedRuns.renamedGraphFailures(refutingOrderOf: [renamedIndex: refutation]).map(\.renamedGraphDifference) == [.dependencyTreeCode])
	}

	/// Seed 454's runs, with one renamed outcome: the graph's own generated code, one file of which `edit` changes (`nil`
	/// when `edit` finds nothing to change, or the tool rejects the graph).
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func seed454Runs(withRenamedCodeEditedBy edit: ([String: String]) -> (fileName: String, code: String)?) async throws -> GraphFuzzerToolRuns? {
		let runs = try await GraphFuzzerOracle.toolRuns(of: GraphFuzzerGenerator.fixture(forSeed: 454, features: [.generateDependencyTree]), renamings: [])
		guard case let .accepted(generatedFiles, warnings) = runs.firstOutcome, let (fileName, editedCode) = edit(generatedFiles) else { return nil }
		var renamedFiles = generatedFiles
		renamedFiles[fileName] = editedCode
		return GraphFuzzerToolRuns(
			fixture: runs.fixture,
			firstOutcome: runs.firstOutcome,
			secondOutcome: runs.secondOutcome,
			renamedOutcomes: [(movingTypeNames, .accepted(generatedFiles: renamedFiles, warnings: warnings))],
			inlineOutcome: runs.inlineOutcome,
			visibleOutcome: runs.visibleOutcome,
		)
	}

	/// The first generated file, by name, with a one-line `let` statement swapped with the one-line statement after it at
	/// its indentation that reads the value it declares, and that file's name; or `nil` when no file has such a pair.
	private static func codeReadingValueBeforeItsDeclaration(in generatedFiles: [String: String]) -> (fileName: String, code: String)? {
		for (fileName, code) in generatedFiles.sorted(by: { $0.key < $1.key }) {
			var lines = code.components(separatedBy: "\n")
			for index in lines.indices.dropLast() {
				let line = lines[index]
				let next = lines[index + 1]
				let indentation = line.prefix { $0 == " " }
				let statement = line.dropFirst(indentation.count)
				let name = statement.dropFirst("let ".count).prefix { $0.isLetter || $0.isNumber || $0 == "_" }
				func isIdentifierCharacter(_ character: Character) -> Bool {
					character.isLetter || character.isNumber || character == "_"
				}
				guard statement.hasPrefix("let "), !name.isEmpty, statement.contains(" = "),
				      next.prefix(while: { $0 == " " }) == indentation,
				      next.split(whereSeparator: { !isIdentifierCharacter($0) }).contains(name),
				      [line, next].allSatisfy({ $0.filter { "({[".contains($0) }.count == $0.filter { ")}]".contains($0) }.count })
				else { continue }
				lines.swapAt(index, index + 1)
				return (fileName, lines.joined(separator: "\n"))
			}
		}
		return nil
	}

	/// Seed 163's readable initializer, an excerpt of its generated `HoleSeam` file.
	private static let builderOrderCode = """
	    public convenience init(s163_HoleGadgetServiceBuilder: @escaping () -> any S163_HoleGadgetService, s163_HoleHandedBuilder: @escaping () -> S163_HoleHanded, s163_HoleServiceBuilder: @escaping () -> any S163_HoleService, s163_HoleTicketImpl_S163_HoleTicketServiceBuilder: @escaping ErasedInstantiator<Int, any S163_HoleTicketService>.Builder) {
	        self.init(__safeDI_s163_HoleGadgetServiceBuilder: .init(__safeDI_noScope: s163_HoleGadgetServiceBuilder), __safeDI_s163_HoleHandedBuilder: .init(__safeDI_noScope: s163_HoleHandedBuilder))
	    }

	"""

	/// Seed 163's call of `HoleSeam` from its kept outer seam `HoleOuter`, whose builder structs span several lines.
	private static let multiLineBuildersCode = """
	            return S163_HoleSeam(__safeDI_s163_HoleGadgetServiceBuilder: .init(
	                holeGadgetOwner: { __safeDI_holeGadgetOwnerValues in
	                    .init(holeGadget: { __safeDI_holeGadgetValues in __safeDI_s163_HoleGadgetServiceBuilder(.holeSeam(.holeGadgetOwner(__safeDI_holeGadgetOwnerValues, .holeGadget(__safeDI_holeGadgetValues)))) })
	                }
	            ), __safeDI_s163_HoleHandedBuilder: .init(
	                holeHandedHolder: { __safeDI_holeHandedHolderValues in
	                    .init(holeHandedBuilder: { __safeDI_holeHandedBuilderValues in { forwarded in __safeDI_s163_HoleHandedBuilder(.holeSeam(.holeHandedHolder(__safeDI_holeHandedHolderValues, .holeHandedBuilder(__safeDI_holeHandedBuilderValues, forwarded)))) } })
	                },
	                holeHandedErased: { __safeDI_holeHandedErasedValues in { forwarded in __safeDI_s163_HoleHandedBuilder(.holeSeam(.holeHandedErased(__safeDI_holeHandedErasedValues, forwarded))) } },
	                holeHandedValue: { __safeDI_holeHandedValueValues in __safeDI_s163_HoleHandedBuilder(.holeSeam(.holeHandedValue(__safeDI_holeHandedValueValues))) },
	                holeHandedLater: { __safeDI_holeHandedLaterValues in { _ in __safeDI_s163_HoleHandedBuilder(.holeSeam(.holeHandedLater(__safeDI_holeHandedLaterValues))) } }
	            ), __safeDI_s163_HoleServiceBuilder: .init(holeService: { __safeDI_holeServiceValues in __safeDI_s163_HoleServiceBuilder(.holeSeam(.holeService(__safeDI_holeServiceValues))) }, holeServiceLazy: { __safeDI_holeServiceLazyValues in __safeDI_s163_HoleServiceBuilder(.holeSeam(.holeServiceLazy(__safeDI_holeServiceLazyValues))) }), __safeDI_s163_HoleTicketImpl_S163_HoleTicketServiceBuilder: .init(
	                holeTicketBuilder: { __safeDI_holeTicketBuilderValues in { forwarded in __safeDI_s163_HoleTicketImpl_S163_HoleTicketServiceBuilder(.holeSeam(.holeTicketBuilder(__safeDI_holeTicketBuilderValues, forwarded))) } },
	                holeTicketHolder: { __safeDI_holeTicketHolderValues in
	                    .init(holeTicketOther: { __safeDI_holeTicketOtherValues in { forwarded in __safeDI_s163_HoleTicketImpl_S163_HoleTicketServiceBuilder(.holeSeam(.holeTicketHolder(__safeDI_holeTicketHolderValues, .holeTicketOther(__safeDI_holeTicketOtherValues, forwarded)))) } })
	                }
	            ))

	"""

	/// `multiLineBuildersCode` with its builders in the order the move of type names gives them.
	private static let multiLineBuildersReorderedCode = """
	            return S163_HoleSeam(__safeDI_s163_HoleGadgetServiceBuilder: .init(
	                holeGadgetOwner: { __safeDI_holeGadgetOwnerValues in
	                    .init(holeGadget: { __safeDI_holeGadgetValues in __safeDI_s163_HoleGadgetServiceBuilder(.holeSeam(.holeGadgetOwner(__safeDI_holeGadgetOwnerValues, .holeGadget(__safeDI_holeGadgetValues)))) })
	                }
	            ), __safeDI_s163_HoleTicketImpl_S163_HoleTicketServiceBuilder: .init(
	                holeTicketBuilder: { __safeDI_holeTicketBuilderValues in { forwarded in __safeDI_s163_HoleTicketImpl_S163_HoleTicketServiceBuilder(.holeSeam(.holeTicketBuilder(__safeDI_holeTicketBuilderValues, forwarded))) } },
	                holeTicketHolder: { __safeDI_holeTicketHolderValues in
	                    .init(holeTicketOther: { __safeDI_holeTicketOtherValues in { forwarded in __safeDI_s163_HoleTicketImpl_S163_HoleTicketServiceBuilder(.holeSeam(.holeTicketHolder(__safeDI_holeTicketHolderValues, .holeTicketOther(__safeDI_holeTicketOtherValues, forwarded)))) } })
	                }
	            ), __safeDI_s163_HoleHandedBuilder: .init(
	                holeHandedHolder: { __safeDI_holeHandedHolderValues in
	                    .init(holeHandedBuilder: { __safeDI_holeHandedBuilderValues in { forwarded in __safeDI_s163_HoleHandedBuilder(.holeSeam(.holeHandedHolder(__safeDI_holeHandedHolderValues, .holeHandedBuilder(__safeDI_holeHandedBuilderValues, forwarded)))) } })
	                },
	                holeHandedErased: { __safeDI_holeHandedErasedValues in { forwarded in __safeDI_s163_HoleHandedBuilder(.holeSeam(.holeHandedErased(__safeDI_holeHandedErasedValues, forwarded))) } },
	                holeHandedValue: { __safeDI_holeHandedValueValues in __safeDI_s163_HoleHandedBuilder(.holeSeam(.holeHandedValue(__safeDI_holeHandedValueValues))) },
	                holeHandedLater: { __safeDI_holeHandedLaterValues in { _ in __safeDI_s163_HoleHandedBuilder(.holeSeam(.holeHandedLater(__safeDI_holeHandedLaterValues))) } }
	            ), __safeDI_s163_HoleServiceBuilder: .init(holeService: { __safeDI_holeServiceValues in __safeDI_s163_HoleServiceBuilder(.holeSeam(.holeService(__safeDI_holeServiceValues))) }, holeServiceLazy: { __safeDI_holeServiceLazyValues in __safeDI_s163_HoleServiceBuilder(.holeSeam(.holeServiceLazy(__safeDI_holeServiceLazyValues))) }))

	"""

	/// `builderOrderCode` with its builders in another order, as a renaming that reorders their labels gives it.
	private static let builderOrderReorderedCode = """
	    public convenience init(s163_HoleHandedBuilder: @escaping () -> S163_HoleHanded, s163_HoleTicketImpl_S163_HoleTicketServiceBuilder: @escaping ErasedInstantiator<Int, any S163_HoleTicketService>.Builder, s163_HoleGadgetServiceBuilder: @escaping () -> any S163_HoleGadgetService, s163_HoleServiceBuilder: @escaping () -> any S163_HoleService) {
	        self.init(__safeDI_s163_HoleHandedBuilder: .init(__safeDI_noScope: s163_HoleHandedBuilder), __safeDI_s163_HoleGadgetServiceBuilder: .init(__safeDI_noScope: s163_HoleGadgetServiceBuilder))
	    }

	"""

	private static let reversingLabels = GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: true, reversesFileNames: false, movesTypeNamesAcrossWrapperNames: false)
	private static let movingTypeNames = GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: false, reversesFileNames: false, movesTypeNamesAcrossWrapperNames: true)

	private static let reversingFileNames = GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: false, reversesFileNames: true)

	/// The differences of a seam's dependency tree file whose code is `code` in one outcome and `otherCode` in the other.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func treeDifferences(code: String, otherCode: String, renaming: GraphFuzzerRenaming) -> [GraphFuzzerOutcomeDifference] {
		GraphFuzzerToolOutcome.differences(
			between: .accepted(generatedFiles: ["FuzzFeature/S1_HoleSeam+SafeDI.swift": code], warnings: []),
			and: .accepted(generatedFiles: ["FuzzFeature/S1_HoleSeam+SafeDI.swift": otherCode], warnings: []),
			renaming: renaming,
		)
	}

	private static func renamedGraphFailure(seed: UInt64, aspect: GraphFuzzerOutcomeDifference.Aspect) -> GraphFuzzerFailure {
		GraphFuzzerFailure(seed: seed, kind: .renamedGraphDiffers, details: "Moving its type names across wrapper names changes \(aspect.rawValue), in FuzzFeature/S\(seed)_HoleSeam+SafeDI.swift.\nThis graph:\n…", renamedGraphDifference: aspect)
	}

	private static func acceptedResult(seed: UInt64, failingWith failures: [GraphFuzzerFailure]) -> GraphFuzzerResult {
		GraphFuzzerResult(
			fixture: GraphFuzzerFixture(seed: seed, swiftFileContent: []),
			outcome: .accepted(generatedFiles: [:], warnings: []),
			failure: failures.first,
			laterFailures: Array(failures.dropFirst()),
			renamedGraphFailures: failures,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func seamSmokeSeeds_exerciseSeamFeature_inGraphsTheToolAccepts() async throws {
		// A graph drawn with the `generateDependencyTree` feature declares a seam, and the smoke batch holds graphs the
		// tool accepts whose generated code, read from what the oracle compiled, between them shows every
		// `GraphFuzzerSeamOutputFeature`, and one graph it rejects.
		let results = try await seamSmokeResults.value
		// A graph that fails only the builder surface, the retention oracle as a known issue lists, or a renamed graph by the
		// builder label sort its entry lists (`seamBuilderOrderShape(listedBy:)`), passed every other oracle.
		let acceptedResults = results.filter { result in
			let knownIssue = Self.seamSmokeKnownIssuesBySeed[result.fixture.seed]
			return result.isAccepted && result.passes(butForRetentionDocumentedBy: knownIssue, butForBuilderOrderDocumentedBy: Self.seamBuilderOrderShape(listedBy: knownIssue))
		}

		#expect(acceptedResults.allSatisfy { GraphFuzzerFeature.features(of: $0.fixture).contains(.generateDependencyTree) })
		#expect(acceptedResults.count >= 2, "Accepted \(acceptedResults.count) of \(Self.seamSmokeSeeds.count) graphs")
		let outputFeatures = acceptedResults.reduce(into: Set<GraphFuzzerSeamOutputFeature>()) { features, result in
			if case let .accepted(generatedFiles, _) = result.outcome {
				features.formUnion(GraphFuzzerFeature.seamOutputFeatures(of: result.fixture, generatedFiles: generatedFiles))
			}
		}
		#expect(Set(GraphFuzzerSeamOutputFeature.allCases).subtracting(outputFeatures).sorted() == [])
		// Graphs with a hole whose generated code shows every `GraphFuzzerHoleOutputFeature`.
		let holeOutputFeatures = acceptedResults.reduce(into: Set<GraphFuzzerHoleOutputFeature>()) { features, result in
			if case let .accepted(generatedFiles, _) = result.outcome {
				features.formUnion(GraphFuzzerFeature.holeOutputFeatures(generatedFiles: generatedFiles))
			}
		}
		#expect(Set(GraphFuzzerHoleOutputFeature.allCases).subtracting(holeOutputFeatures).sorted() == [])
		// Graphs split across modules – with a caller in another package, and with a caller or a seam's module without a
		// package – among those the tool accepts, so that the batch compiles each module of a split graph and the callers
		// of each package configuration.
		let drawFeatures = acceptedResults.reduce(into: Set<GraphFuzzerSeamDrawFeature>()) { $0.formUnion(GraphFuzzerFeature.seamDrawFeatures(of: $1.fixture)) }
		#expect(Set([GraphFuzzerSeamDrawFeature.moduleSplit, .otherPackageCaller, .samePackageCallerRunWithoutPackageName, .seamModuleRunWithoutPackageName, .seamDependency, .seamDependencyChain]).subtracting(drawFeatures).sorted() == [])
		// Every roll of `addingHoleShapes` beyond its base draw that draws a shape the tool accepts, in an accepted graph.
		#expect(Set([
			GraphFuzzerSeamDrawFeature.holeCrossPackage,
			.holeCrossPackageFulfillerInitializerPackage,
			.holeNarrowerField,
			.holeAliasOrOnlyIfAvailable,
			.holeReadOnlyIfAvailable,
			.holeOwnerAliasesField,
			.holeOwnerLabeledAsKeyword,
			.holeSendablePlaceLabeledAsKeyword,
			.holeMocks,
			.holeImplInNamespace,
			.holeSeamModuleWithoutPackageName,
			.holeReentryThroughPassingSeam,
			.holeReentryThroughSendablePassingSeam,
			.holeSecondHole,
			.holeSendableDiamond,
			.holeNestedSameLabelFill,
			.holeSecondHoleType,
			.holeLazyWrapperBesideByValuePlace,
			.holeSendableLazyWrapperBesideByValuePlace,
			.holeTwoSeamCycleWithSendableEdge,
			.holeInnerSeamPlainAndSendableRoutes,
			.holeInnerSeamWithBothEnums,
			.holeInnerSendablePlaceOnSendableRoute,
			.holePlaceInsideSendableFill,
			.holeSharedTypes,
			.holeSharedTypesThroughModel,
			.holePlaceInsidePlainFill,
			.holePlaceInsidePlainFillOnTwoInnerRoutes,
			.holePlaceInsidePlainFillReadsInnerLevel,
			.holePlaceInsidePlainFillTwoTypesDeep,
			.holePlaceInsidePlainFillTwoCalls,
			.holePlaceInsidePlainFillFulfillerReadsInnerLevel,
			.holePlacesInsideFillSpellTypeWithAndWithoutAny,
			.holeUnderLaterLoopMember,
			.holeUnderEveryLoopMember,
			.holeLoopOfThreeMembers,
			.holeLoopPlaceThroughSharedLeaf,
			.holeLoopBeneathSeam,
			.holeLoopMemberLevelReadByFill,
			.holeForwardingPlace,
			.holeLoopMemberAlsoBuiltByValue,
			.holeErasureInsidePlainFill,
			.holeErasureInsideSendableFill,
			.holeErasureBeneathSeamInSendableFamily,
		]).subtracting(drawFeatures).sorted() == [])
		// `addingCycleParameterShapes`' cycle, in accepted graphs: its hole between the cycle's ends at or beneath the type that
		// declares the label again, filled by a fill that reads it (seed 227); its hole on the seam (seed 705); the
		// note received after the label, and instantiator declarations in a nested cycle (seed 24); the label aliased, with
		// both kinds of wrapper (seed 1010); and opened by value inside `Sendable` wrappers, whose function the cycle closes on
		// is `@Sendable`, so the hole's place is a case of the `@Sendable` family (seed 277).
		#expect(Set([
			GraphFuzzerSeamDrawFeature.cycleParameterSeam,
			.cycleParameterFillReadsLabel,
			.cycleParameterHoleBetween,
			.cycleParameterHoleAtOrBeneathDeclaration,
			.cycleParameterHoleOnSeam,
			.cycleParameterNoteReceivedAfterLabel,
			.cycleParameterDeclaredAsAlias,
			.cycleParameterDeclaredAsInstantiators,
			.cycleParameterNestedCycle,
			.cycleParameterMixedWrapperKinds,
			.cycleParameterOpenedByValue,
			.cycleParameterSendableWrappers,
		]).subtracting(drawFeatures).sorted() == [])
		// The re-entered fill's read of a value one route holds, remedied by the seam built again receiving it, in an accepted
		// graph: the two unremedied reads are rejected by design.
		#expect(drawFeatures.contains(.reenteredFillReadsValueOfOneRouteRemedied))
		// A graph with a hole whose builder labels and case names the name-stability oracle compared with those of the graph
		// without its second place.
		#expect(acceptedResults.contains { $0.isComparedWithoutSecondHolePlace })
		// A graph with a hole whose retention the retention oracle judged, failing or not: on main the in-seam leak it gates
		// on fails each graph of the retention draw whose fill reads nothing.
		#expect(results.contains(where: \.isJudgedForRetention) || !compileVerificationIsEnabled)
		// A graph with types shared under a hole whose levels the second-path oracle compared with those of the graph without
		// its second path.
		#expect(acceptedResults.contains { $0.isComparedWithoutSecondPath })
		// A split graph whose modules all name their package, which the SwiftPM plugin flow agreed on with the module-info
		// flow, and one of them declaring a type in a flag's clause in the seam's module, whose decision the plugin flow
		// asserts in the caller's module too.
		#expect(acceptedResults.contains { $0.isComparedAcrossIntegrations })
		#expect(acceptedResults.contains { $0.isComparedAcrossIntegrations && GraphFuzzerFeature.seamDrawFeatures(of: $0.fixture).contains(.recordedInFlagClause) })
		// A split graph that declares a seam, whose modules generated the same code reading the stored seam signatures as
		// computing them again.
		#expect(acceptedResults.contains { $0.isComparedWithRecomputedSignatures })
		// Seams naming a type a block that guards mock-only declarations declares, with each way the block's other clauses,
		// or another file's, declare it, and one in the seam's module, which the oracle compiles as a release build too.
		#expect(Set([
			GraphFuzzerSeamDrawFeature.mockOnlyBlockTypeElseSameLevel,
			.mockOnlyBlockTypeElseWider,
			.mockOnlyBlockTypeElseNarrower,
			.mockOnlyBlockTypeRedeclaredWhereMockConditionIsInactive,
			.mockOnlyBlockAcrossModules,
		]).subtracting(drawFeatures).sorted() == [])
		// A graph whose generated code carries the comment naming a type no declaration SafeDI reads declares, which agreed
		// with its read twin.
		#expect(acceptedResults.contains { result in
			guard result.isComparedWithReadTwin, case let .accepted(generatedFiles, _) = result.outcome else { return false }
			return GraphFuzzerFeature.seamOutputFeatures(of: result.fixture, generatedFiles: generatedFiles).contains(.unreadTypeComment)
		})
		#expect(results.contains { !$0.isAccepted && $0.failure == nil }, "Rejected none of \(Self.seamSmokeSeeds.count) graphs")
	}

	@Test(arguments: [(UInt64(153), GraphFuzzerGeneratorFeature.generateDependencyTree), (150, .generateDependencyTree), (98, .generateMockPublic), (208, .generateMockPublic)])
	func seamDependencyDraw_importsOnlyTheModuleBeneath_whenDeclarationsMoveOrAChainIsDrawnBeneathSeamsModule(seed: UInt64, feature: GraphFuzzerGeneratorFeature) throws {
		// Each module imports only what it lists under the module-info flow. Each module of the chain beneath the seam's module
		// imports only the module beneath it, and a caller only the seam's module, except a module that lists every module
		// beneath it because it declares a root of the draws beneath the seam's module
		// (`GraphFuzzerFixture.modulesListingEveryModuleBeneath`), so that a caller that reads through the seam's module's
		// view, of which the graph holds at least one, reads the chain only through that view.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [feature])
		let modules = try #require(fixture.modules)
		let lists = fixture.dependencyLists(modules: modules, integration: .moduleInfo, listsTransitiveDependencies: false)
		let modulesListingEveryModuleBeneath = fixture.modulesListingEveryModuleBeneath
		// The one import past the module directly beneath: where `drawFulfillerOnlyCallingModuleCanBuild` lands, the file of
		// the seam's module that declares `OuterFakeClock`, a `mockOnly` fake of `OuterClock`, a protocol of `FuzzCore`,
		// imports `FuzzCore` too.
		// Of these seeds the draw lands on the public mock corpus's 208 alone, so a stray import on any other still fails.
		let outerFulfillerDrawLanded = GraphFuzzerPublicMockDraw.drawFeatures(of: fixture).contains(.outerFulfillerPublicMockCall)
		#expect(outerFulfillerDrawLanded == (seed == 208 && feature == .generateMockPublic), "Seed \(seed)")
		for (module, content) in zip(modules, fixture.swiftFileContent) {
			let importedModuleNames = content.split(separator: "\n").filter { $0.hasPrefix("import Fuzz") }.map { String($0.dropFirst("import ".count)) }
			#expect(Set(importedModuleNames).isSubset(of: (lists[module] ?? []).map(\.name)), "Seed \(seed), \(module.name)")
			if !modulesListingEveryModuleBeneath.contains(module) {
				var expectedModuleNames = module.dependencies.filter(modules.contains).map(\.name)
				if outerFulfillerDrawLanded, module == .seamModule, content.contains("OuterFakeClock") {
					expectedModuleNames.append(GraphFuzzerModule.seamDependencyBase.name)
				}
				#expect(importedModuleNames == expectedModuleNames, "Seed \(seed), \(module.name)")
			}
		}
		#expect(!GraphFuzzerSeamDependencyDraw.callersReadingThroughView(of: fixture).isEmpty, "Seed \(seed): no caller reads through the seam's module's view")
		let drawn = GraphFuzzerSeamDependencyDraw.drawn(in: fixture)
		// Seeds 150 and 208 move a declaration beside their chain: 150's since the carrier draw's types joined the seam's
		// module.
		let expected: [UInt64: (movesDeclaration: Bool, drawsChain: Bool)] = [153: (true, false), 150: (true, true), 98: (true, false), 208: (true, true)]
		#expect(drawn.movesDeclaration == expected[seed]?.movesDeclaration)
		#expect(drawn.drawsChain == expected[seed]?.drawsChain)
		#expect(Set(modules).isSuperset(of: drawn.drawsChain ? [.seamDependency, .seamDependencyBase, .seamDependencyLeaf] : [.seamDependency]))
	}

	/// A file of `module` declaring `S7_<name>` with `arguments`, whose property `label: type` has `attribute`, written as
	/// the fuzzer writes a type; `initializerModifier` spells its initializer's access, `nil` for none.
	private static func chainFile(module: GraphFuzzerModule, name: String, arguments: String, label: String, type: String, attribute: String = "@Instantiated", initializerModifier: String? = "public") -> String {
		let header = ([GraphFuzzerModule.marker + module.name] + module.dependencies.map { "import \($0.name)" }).joined(separator: "\n") + "\n\n"
		let attributeArguments = arguments.isEmpty ? "" : "(\(arguments))"
		let initializer = "\(initializerModifier.map { $0 + " " } ?? "")init(\(label): \(type)) {\n\t\tself.\(label) = \(label)\n\t}"
		return header + "@Instantiable\(attributeArguments)\npublic final class S7_\(name): Instantiable {\n\t\(initializer)\n\n\t\(attribute) let \(label): \(type)\n}\n"
	}

	/// The chain `GraphFuzzerSeamDependencyDraw.chainPercent` draws, beneath `S7_Screen` of the seam's module, declared with
	/// `screenArguments`: `S7_ChainLink` and `S7_ChainBase`, seams unless `chainIsPublicMocks` makes each a public mock with
	/// an `internal` initializer, as the public mock corpus draws them, and `S7_ChainLeaf`, each in the module beneath the
	/// one above, where the leaf receives `S7_ChainToken` only if available. `S7_Screen` instantiates `S7_ChainLink`, or with
	/// `screenReceivesBase` receives `S7_ChainBase`. `callerArguments`, when given, declares `S7_Caller` in the
	/// same-package caller's module, which instantiates `S7_Screen`.
	private static func chainFixture(screenArguments: String, screenReceivesBase: Bool = false, chainIsPublicMocks: Bool = false, callerArguments: String? = nil) -> GraphFuzzerFixture {
		let chainArguments = chainIsPublicMocks ? "generateMock: .public" : "generateDependencyTree: true"
		let chainInitializerModifier: String? = chainIsPublicMocks ? nil : "public"
		var files = [
			chainFile(module: .seamDependencyLeaf, name: "ChainLeaf", arguments: "", label: "chainToken", type: "S7_ChainToken?", attribute: "@Received(onlyIfAvailable: true)")
				+ "\npublic final class S7_ChainToken: Sendable {\n\tpublic init() {}\n}\n",
			chainFile(module: .seamDependencyBase, name: "ChainBase", arguments: chainArguments, label: "chainLeaf", type: "S7_ChainLeaf", initializerModifier: chainInitializerModifier),
			chainFile(module: .seamDependency, name: "ChainLink", arguments: chainArguments, label: "chainBase", type: "S7_ChainBase", initializerModifier: chainInitializerModifier),
			screenReceivesBase
				? chainFile(module: .seamModule, name: "Screen", arguments: screenArguments, label: "chainBase", type: "S7_ChainBase", attribute: "@Received")
				: chainFile(module: .seamModule, name: "Screen", arguments: screenArguments, label: "chainLink", type: "S7_ChainLink"),
		]
		if let callerArguments {
			files.append(chainFile(module: .samePackageCaller, name: "Caller", arguments: callerArguments, label: "screen", type: "S7_Screen"))
		}
		return GraphFuzzerFixture(seed: 7, swiftFileContent: files)
	}

	/// What each module of the chain lists under the module-info flow when no mock reaches beneath what it imports.
	private static let chainModulesImported: [GraphFuzzerModule: [GraphFuzzerModule]] = [
		.seamDependencyLeaf: [],
		.seamDependencyBase: [.seamDependencyLeaf],
		.seamDependency: [.seamDependencyBase],
		.seamModule: [.seamDependency],
	]

	@Test
	func moduleInfoDependencies_listModulesBeneathImportedOne_whenSeamModulesMockBuildsChainOfSeams() throws {
		// A mock builds a seam's tree itself, so `S7_Screen`'s mock builds `S7_ChainBase` and `S7_ChainLeaf`, which its
		// module imports nothing of: listed, as the Manual tells an adopter, as the SwiftPM plugin flow reads them.
		let fixture = Self.chainFixture(screenArguments: "generateMock: true")
		var expected = Self.chainModulesImported
		expected[.seamModule] = [.seamDependencyLeaf, .seamDependencyBase, .seamDependency]
		#expect(try GraphFuzzerSeamDependencyDraw.moduleInfoDependencies(of: fixture, modules: #require(fixture.modules)) == expected)
	}

	@Test
	func moduleInfoDependencies_listModulesBeneathImportedOne_whenSeamWithMockBuildsChain() throws {
		// Seam corpus seed 4867's shape: the chain hangs beneath a seam that declares a mock of its own.
		let fixture = Self.chainFixture(screenArguments: "generateDependencyTree: true, generateMock: true")
		var expected = Self.chainModulesImported
		expected[.seamModule] = [.seamDependencyLeaf, .seamDependencyBase, .seamDependency]
		#expect(try GraphFuzzerSeamDependencyDraw.moduleInfoDependencies(of: fixture, modules: #require(fixture.modules)) == expected)
	}

	@Test
	func moduleInfoDependencies_listModulesBeneathImportedOne_whenMockPromotesReceiveOfTypeTwoModulesDown() throws {
		// A mock builds what its tree receives where it can, so it builds `S7_ChainBase` and, through it, `S7_ChainLeaf`.
		let fixture = Self.chainFixture(screenArguments: "generateMock: true", screenReceivesBase: true)
		var expected = Self.chainModulesImported
		expected[.seamModule] = [.seamDependencyLeaf, .seamDependencyBase, .seamDependency]
		#expect(try GraphFuzzerSeamDependencyDraw.moduleInfoDependencies(of: fixture, modules: #require(fixture.modules)) == expected)
	}

	@Test
	func moduleInfoDependencies_listModulesBeneathImportedOne_whenCallersMockBuildsSeamModulesTypeAboveChain() throws {
		// The mock of a caller's type builds `S7_Screen`'s tree, and so the chain beneath it.
		let fixture = Self.chainFixture(screenArguments: "", callerArguments: "generateMock: true")
		var expected = Self.chainModulesImported
		expected[.samePackageCaller] = [.seamDependencyLeaf, .seamDependencyBase, .seamDependency, .seamModule]
		#expect(try GraphFuzzerSeamDependencyDraw.moduleInfoDependencies(of: fixture, modules: #require(fixture.modules)) == expected)
	}

	@Test
	func moduleInfoDependencies_listOnlyImportedModules_whenNoMockReachesChain() throws {
		let fixture = Self.chainFixture(screenArguments: "", callerArguments: "")
		var expected = Self.chainModulesImported
		expected[.samePackageCaller] = [.seamModule]
		#expect(try GraphFuzzerSeamDependencyDraw.moduleInfoDependencies(of: fixture, modules: #require(fixture.modules)) == expected)
	}

	@Test
	func moduleInfoDependencies_listOnlyImportedModules_whenMockCallsPublicMockOfChainLink() throws {
		// The public mock corpus's chain: `S7_ChainLink`'s initializer is `internal`, so `S7_Screen`'s mock calls its public
		// mock rather than build its tree, and reads only the module that declares it.
		let fixture = Self.chainFixture(screenArguments: "generateMock: true", chainIsPublicMocks: true)
		#expect(try GraphFuzzerSeamDependencyDraw.moduleInfoDependencies(of: fixture, modules: #require(fixture.modules)) == Self.chainModulesImported)
	}

	@Test
	func moduleInfoDependencies_listSameModules_whenTypeNamesMoveAcrossWrapperNames() throws {
		let fixture = Self.chainFixture(screenArguments: "generateMock: true")
		let renaming = GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: false, reversesFileNames: false, movesTypeNamesAcrossWrapperNames: true)
		let renamed = GraphFuzzerFixture(seed: 7, swiftFileContent: fixture.swiftFileContent.map { renaming.rename($0, typeNamePrefix: fixture.typeNamePrefix) })
		#expect(renamed.swiftFileContent != fixture.swiftFileContent)
		let modules = try #require(fixture.modules)
		#expect(GraphFuzzerSeamDependencyDraw.moduleInfoDependencies(of: renamed, modules: modules) == GraphFuzzerSeamDependencyDraw.moduleInfoDependencies(of: fixture, modules: modules))
	}

	/// `chainFixture`'s chain beneath a seam, `S7_Screen`, with `S7_Caller` in the same-package caller's module and
	/// `S7_OtherCaller` in the other package's, each instantiating `S7_Screen`, and, when `drawRootName` names one,
	/// `S7_<drawRootName>`, a root of a draw beneath the seam's module, declared in `drawRootModule`.
	private static func chainFixtureWithBothCallers(drawRootName: String?, drawRootModule: GraphFuzzerModule = .samePackageCaller) -> GraphFuzzerFixture {
		var files = chainFixture(screenArguments: "generateDependencyTree: true", callerArguments: "").swiftFileContent
		files.append(chainFile(module: .otherPackageCaller, name: "OtherCaller", arguments: "", label: "screen", type: "S7_Screen"))
		if let drawRootName {
			files.append(chainFile(module: drawRootModule, name: drawRootName, arguments: "isRoot: true", label: "screen", type: "S7_Screen"))
		}
		return GraphFuzzerFixture(seed: 7, swiftFileContent: files)
	}

	/// What each module of `chainFixtureWithBothCallers` lists when it lists every module beneath it.
	private static let chainModulesBeneath: [GraphFuzzerModule: [GraphFuzzerModule]] = [
		.seamDependencyLeaf: [],
		.seamDependencyBase: [.seamDependencyLeaf],
		.seamDependency: [.seamDependencyLeaf, .seamDependencyBase],
		.seamModule: [.seamDependencyLeaf, .seamDependencyBase, .seamDependency],
		.samePackageCaller: [.seamDependencyLeaf, .seamDependencyBase, .seamDependency, .seamModule],
		.otherPackageCaller: [.seamDependencyLeaf, .seamDependencyBase, .seamDependency, .seamModule],
	]

	@Test(arguments: MultiModuleIntegration.allCases, ["FillCallRoot", "CarriedRoot", "ReenteredRoot"])
	func dependencyLists_listEveryModuleBeneathOnlyInDrawRootsModuleAndBeneathCallers_whenGraphDeclaresDrawRoot(integration: MultiModuleIntegration, drawRootName: String) throws {
		// The module that declares the draw's root, and every module beneath the callers, which declare the draws' seams,
		// list every module beneath them, as the tool asks of a module that declares a root, a seam's included; the other
		// caller lists the seam's module alone, so it reads the chain through that module's view.
		let fixture = Self.chainFixtureWithBothCallers(drawRootName: drawRootName)
		var expected = Self.chainModulesBeneath
		expected[.otherPackageCaller] = [.seamModule]
		#expect(try fixture.dependencyLists(modules: #require(fixture.modules), integration: integration, listsTransitiveDependencies: false) == expected)
	}

	@Test
	func dependencyLists_listEveryModuleBeneathInOtherPackageCaller_whenItDeclaresDrawRoot() throws {
		let fixture = Self.chainFixtureWithBothCallers(drawRootName: "ReenteredRoot", drawRootModule: .otherPackageCaller)
		var expected = Self.chainModulesBeneath
		expected[.samePackageCaller] = [.seamModule]
		#expect(try fixture.dependencyLists(modules: #require(fixture.modules), integration: .moduleInfo, listsTransitiveDependencies: false) == expected)
	}

	@Test
	func dependencyLists_listImportedModules_whenGraphDeclaresNoDrawRoot() throws {
		let fixture = Self.chainFixtureWithBothCallers(drawRootName: nil)
		var expected = Self.chainModulesImported
		expected[.samePackageCaller] = [.seamModule]
		expected[.otherPackageCaller] = [.seamModule]
		#expect(try fixture.dependencyLists(modules: #require(fixture.modules), integration: .moduleInfo, listsTransitiveDependencies: false) == expected)
	}

	@Test
	func dependencyLists_listEveryModuleBeneathInEveryModule_whenRunListsTransitiveDependencies() throws {
		// The inline build and the known-right path, as 2.2.0 asked, whatever roots the graph declares.
		let fixture = Self.chainFixtureWithBothCallers(drawRootName: "FillCallRoot")
		#expect(try fixture.dependencyLists(modules: #require(fixture.modules), integration: .moduleInfo, listsTransitiveDependencies: true) == Self.chainModulesBeneath)
	}

	@Test
	func callersReadingThroughView_returnsCallerDeclaringNoDrawRoot_whenGraphDeclaresDrawRoot() {
		let fixture = Self.chainFixtureWithBothCallers(drawRootName: "CarriedRoot")
		#expect(fixture.declaresRootOfDrawBeneathSeamsModule)
		#expect(GraphFuzzerSeamDependencyDraw.callersReadingThroughView(of: fixture) == [.otherPackageCaller])
	}

	@Test
	func callersReadingThroughView_returnsBothCallers_whenGraphDeclaresNoDrawRoot() {
		#expect(GraphFuzzerSeamDependencyDraw.callersReadingThroughView(of: Self.chainFixtureWithBothCallers(drawRootName: nil)) == [.samePackageCaller, .otherPackageCaller])
	}

	@Test
	func callersReadingThroughView_returnsNone_whenOnlyCallerDeclaresDrawRoot() {
		let fixture = Self.chainFixtureWithBothCallers(drawRootName: "FillCallRoot")
		let withoutOtherCaller = GraphFuzzerFixture(seed: 7, swiftFileContent: fixture.swiftFileContent.filter { GraphFuzzerModule(declaredIn: $0) != .otherPackageCaller })
		#expect(GraphFuzzerSeamDependencyDraw.callersReadingThroughView(of: withoutOtherCaller) == [])
	}

	@Test
	func callersReadingThroughView_returnsNone_whenCallersMockBuildsChain() {
		// The mock of `S7_Caller` builds `S7_Screen`'s tree, chain and all, so its module lists the modules beneath.
		#expect(GraphFuzzerSeamDependencyDraw.callersReadingThroughView(of: Self.chainFixture(screenArguments: "", callerArguments: "generateMock: true")) == [])
	}

	@Test
	func callersReadingThroughView_returnsNone_whenModuleOmitsPackageName() {
		// The SwiftPM plugin flow runs only where every module names its package, so the integrations are not compared.
		let fixture = Self.chainFixtureWithBothCallers(drawRootName: nil)
		let withoutPackage = GraphFuzzerFixture(seed: 7, swiftFileContent: fixture.swiftFileContent.map { content in
			guard GraphFuzzerModule(declaredIn: content) == .otherPackageCaller else { return content }
			return content.replacingOccurrences(of: GraphFuzzerModule.marker + GraphFuzzerModule.otherPackageCaller.name, with: GraphFuzzerModule.marker + GraphFuzzerModule.otherPackageCaller.name + GraphFuzzerModule.packageNameOmittedMarker)
		})
		#expect(withoutPackage.modulesOmittingPackageName == [.otherPackageCaller])
		#expect(GraphFuzzerSeamDependencyDraw.callersReadingThroughView(of: withoutPackage) == [])
	}

	@Test(arguments: [(UInt64(471), GraphFuzzerSeamDrawFeature.seamDependencyReadThroughView), (347, .seamDependencyChainReadThroughView)])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func integrationsDisagreeFailure_returnsNil_whenOtherPackageCallerReadsThroughViewBesideDrawRoot(seed: UInt64, feature: GraphFuzzerSeamDrawFeature) async throws {
		// Seam corpus seed 471 moves declarations beneath the seam's module, and seed 347 draws the chain there, each in a
		// graph that declares a root of the draws beneath the seam's module: that root's module lists every module beneath
		// it, while `FuzzOther` lists the seam's module alone and computes what it calls from that module's view, which the
		// two flows compute alike.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])
		#expect(fixture.declaresRootOfDrawBeneathSeamsModule)
		#expect(GraphFuzzerFeature.seamDrawFeatures(of: fixture).contains(feature))
		#expect(GraphFuzzerSeamDependencyDraw.callersReadingThroughView(of: fixture) == [.otherPackageCaller])
		let moduleInfoOutcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
		guard case .accepted = moduleInfoOutcome else {
			Issue.record("Seed \(seed) is expected to be accepted:\n\(moduleInfoOutcome.description)")
			return
		}
		let runs = try await GraphFuzzerToolRuns(fixture: fixture, firstOutcome: moduleInfoOutcome, secondOutcome: moduleInfoOutcome, pluginOutcome: GraphFuzzerOracle.toolOutcome(of: fixture, integration: .swiftPackagePlugin))
		#expect(runs.integrationsDisagreeFailure == nil)
	}

	@Test(arguments: [UInt64(4_749), 4_867])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func integrationsDisagreeFailure_returnsNil_whenSeamCorpusMockBuildsChainBeneathItsModulesImport(seed: UInt64) async throws {
		// Seam corpus seeds 4749 and 4867 draw the chain beneath a seam that declares a mock, which builds the chain's tree
		// and so reads a module its module does not import: the module-info flow lists it, as the Manual tells an adopter,
		// and the two flows generate the same mock.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])
		#expect(GraphFuzzerSeamDependencyDraw.drawn(in: fixture).drawsChain)
		let moduleInfoOutcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
		let runs = try await GraphFuzzerToolRuns(fixture: fixture, firstOutcome: moduleInfoOutcome, secondOutcome: moduleInfoOutcome, pluginOutcome: GraphFuzzerOracle.toolOutcome(of: fixture, integration: .swiftPackagePlugin))
		#expect(runs.integrationsDisagreeFailure == nil)
	}

	@Test
	func seamCorpus_drawsEachShapeInThePinnedNumberOfGraphs_whenFixturesAreGeneratedWithoutTheTool() throws {
		// Each shape `addingSeam` draws lands in exactly the pinned number of the seam corpus's graphs, read from
		// their source: the draw is deterministic, so a change in a shape's share is a reviewed diff, as the
		// accepted-seed pins are, and a draw that stops landing – a filter that empties its sources, a roll that
		// never fires – fails here rather than in a review of the corpus. Every shape has a pin.
		var counts = [GraphFuzzerSeamDrawFeature: Int]()
		for seed in 0..<UInt64(Self.seamCorpusSeedCount) {
			for feature in GraphFuzzerFeature.seamDrawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])) {
				counts[feature, default: 0] += 1
			}
		}
		for feature in GraphFuzzerSeamDrawFeature.allCases {
			let pinnedCount = try #require(Self.seamCorpusDrawFeatureCounts[feature], "\(feature.rawValue) has no pinned count")
			#expect(counts[feature, default: 0] == pinnedCount, "\(feature.rawValue) drawn in \(counts[feature, default: 0]) graphs")
		}
	}

	@Test
	func retentionCounts_holdAtLeastTenGraphs_whereTheRetentionOracleGates() {
		// The retention check gates generator changes only while it judges at least ten graphs of each kind it gates on: in
		// the seam corpus, graphs with a hole, graphs of its own draw, and graphs whose hand-written builder it judged; in
		// the public mock corpus, graphs with a hole, graphs of its own draw, and graphs whose hand-written call of a mock that
		// takes a builder taking nothing it judged. The corpus runs pin each count exactly.
		#expect(Self.seamCorpusRetentionCounts.judged >= Self.gatingDrawJudgedGraphFloor)
		#expect(Self.seamCorpusRetentionCounts.judgedDrawingRetentionShape >= Self.gatingDrawJudgedGraphFloor)
		#expect(Self.seamCorpusRetentionCounts.judgedThroughHandWrittenBuilder >= Self.gatingDrawJudgedGraphFloor)
		// Graphs in which an experiment held a place's `ErasedInstantiator`, the wrapper the existential places are held in:
		// the constrained wrappers and the `Sendable` family are judged by values and by compiling, unfloored.
		#expect(Self.seamCorpusRetentionCounts.judgedHoldingForwardingWrapper["ErasedInstantiator", default: 0] >= Self.gatingDrawJudgedGraphFloor)
		#expect(Self.publicMockCorpusRetentionCounts.judged >= Self.gatingDrawJudgedGraphFloor)
		#expect(Self.publicMockCorpusRetentionCounts.judgedDrawingRetentionShape >= Self.gatingDrawJudgedGraphFloor)
		#expect(Self.publicMockCorpusRetentionCounts.judgedThroughHandWrittenBuilder >= Self.gatingDrawJudgedGraphFloor)
	}

	@Test
	func levelFunctionCaptureCounts_holdAtLeastTenGraphs_whereTheCheckJudges() {
		// The level function capture check is the first signal of a kept level's values only while it judges at least ten
		// graphs of the seam corpus with a level function, and ten with a member closure that names its parameter, and ten
		// graphs of the public mock corpus with a level function, which a generated call writes where it fills every place of
		// a builder that takes nothing. The corpus runs pin each count exactly.
		#expect(Self.seamCorpusLevelFunctionCaptureCounts.judged >= Self.gatingDrawJudgedGraphFloor)
		#expect(Self.seamCorpusLevelFunctionCaptureCounts.judgedWithNamed >= Self.gatingDrawJudgedGraphFloor)
		#expect(Self.publicMockCorpusLevelFunctionCaptureCounts.judged >= Self.gatingDrawJudgedGraphFloor)
	}

	@Test
	func acceptedDrawFeatureCounts_holdAtLeastTenGraphs_forEachGatingDraw() {
		// The gating draws – a seam and its caller forwarding one label, a public mock that builds itself again with a
		// place beneath, a place inside a public mock's fill, a seam or a public mock that binds a value before an
		// instantiator nothing beneath reads it from, and a loop of builders around places inside a seam (the retention
		// oracle's) – gate generator changes only while each of
		// their shapes lands in at least ten graphs the tool accepts, which the corpus runs pin exactly.
		for feature in GraphFuzzerSeamDrawFeature.allCases where feature.isForwardedLabelAcrossSeamCallShape || feature.isRetentionShape || feature.isForwardingPlaceShape || feature.isPassedUpPlaceReadingPassingSeamsValueShape || feature.isFixedSeamCallDefectShape || feature.isOptionalPlaceShape {
			#expect(Self.seamCorpusAcceptedDrawFeatureCounts[feature, default: 0] >= Self.gatingDrawJudgedGraphFloor, "\(feature.rawValue) is pinned in fewer than ten accepted graphs")
		}
		for feature in GraphFuzzerPublicMockDrawFeature.allCases where feature.isCountedWhenAccepted {
			#expect(Self.publicMockCorpusAcceptedDrawFeatureCounts[feature, default: 0] >= Self.gatingDrawJudgedGraphFloor, "\(feature.rawValue) is pinned in fewer than ten accepted graphs")
		}
	}

	@Test
	func corpusAcceptedFeatureCounts_holdAtLeastTenGraphs_forMockPassedLabelAboveAlias() {
		// A mock passed a label that a scope its tree builds declares again, above an `onlyIfAvailable` alias of it
		// (`addingMockPassedLabelAboveAliasCycle`), stands in for unit tests of where that alias binds only while it lands
		// in at least ten graphs the tool accepts, which the corpus runs pin exactly.
		#expect(Self.corpusAcceptedFeatureCounts[.onlyIfAvailableAliasBeneathLabelAMockIsPassed, default: 0] >= Self.gatingDrawJudgedGraphFloor)
	}

	@Test
	func corpusAcceptedFeatureCounts_holdAtLeastTenGraphs_forReceiveThroughCycleWalkedEarlier() {
		// A mock whose walk of what its tree receives reaches a screen again before the walk that first reached it has
		// finished (`addingReceiveThroughCycleWalkedEarlier`) stands in for unit tests of what such a mock binds only while
		// it lands in at least ten graphs the tool accepts, which the corpus runs pin exactly.
		#expect(Self.corpusAcceptedFeatureCounts[.receiveThroughCycleWalkedEarlier, default: 0] >= Self.gatingDrawJudgedGraphFloor)
	}

	@Test
	func acceptedDrawFeatureCounts_holdAtLeastTenGraphs_forTheAliasSpellingRoll() {
		// An existential's rename naming the protocol without `any` in `ofType:`, met before every other receive of the value,
		// stands in for unit tests of how a seam and a mock spell a value their tree's receivers spell apart only while it
		// lands in at least ten graphs the tool accepts, which the corpus run pins exactly.
		for feature in GraphFuzzerSeamDrawFeature.allCases where feature.isAliasSpellingRollShape {
			#expect(Self.seamCorpusAcceptedDrawFeatureCounts[feature, default: 0] >= Self.gatingDrawJudgedGraphFloor, "\(feature.rawValue) is pinned in fewer than ten accepted graphs")
		}
	}

	@Test
	func acceptedDrawFeatureCounts_holdAtLeastTenGraphs_forEachShapeReadThroughView() {
		// The integrations' comparison (`integrationsDisagree`) checks what a caller computes from the seam's module's view
		// – cell 5b's chain, and moved declarations – only in a graph whose caller lists the seam's module alone; it judges
		// them only while each lands in at least ten graphs the tool accepts, which the corpus runs pin exactly.
		for feature in GraphFuzzerSeamDrawFeature.allCases where feature.isReadThroughViewShape {
			#expect(Self.seamCorpusAcceptedDrawFeatureCounts[feature, default: 0] >= Self.gatingDrawJudgedGraphFloor, "\(feature.rawValue) is pinned in fewer than ten accepted graphs")
		}
	}

	@Test
	func seamCorpus_acceptsTenGraphsOfEachScreenPlaceNeighbour_whenPinsAreRead() {
		// A screen's place whose fill reads the screen's value stands in for the unit tests of the neighbours the tool must
		// accept beside the shape it rejects (`fieldOfReenteringPlace`) only while the corpus accepts enough of each.
		for feature in [GraphFuzzerSeamDrawFeature.holeScreenValueReadWithoutReentry, .holeScreenValueBuiltBySeam] {
			#expect(Self.seamCorpusAcceptedDrawFeatureCounts[feature, default: 0] >= Self.gatingDrawJudgedGraphFloor, "\(feature.rawValue) accepted in fewer than ten graphs")
		}
	}

	@Test
	func acceptedDrawFeatureCounts_holdAtLeastTenGraphs_forEachErasurePlace() {
		// The places of a builder whose filling type is not the type it returns – inside a plain fill, inside a `@Sendable`
		// fill, and beneath the seam in the `@Sendable` family – stand in for unit tests of their labels and their builders
		// only while each lands in at least ten graphs the tool accepts, which the corpus runs pin exactly.
		for feature in GraphFuzzerSeamDrawFeature.allCases where feature.isErasurePlaceShape {
			#expect(Self.seamCorpusAcceptedDrawFeatureCounts[feature, default: 0] >= Self.gatingDrawJudgedGraphFloor, "\(feature.rawValue) is pinned in fewer than ten accepted graphs")
		}
	}

	@Test
	func acceptedDrawFeatureCounts_holdAtLeastTenGraphs_forEachLazyRouteShape() {
		// Two routes to one case whose fill reads a value one route binds lazily and the caller holds by value – with a
		// `SendableLazilyInstantiated`, read only if available, and beneath an instantiator – stand in for unit tests of the
		// wrapper a seam's caller makes of its own value only while each lands in at least ten graphs the tool accepts, which
		// the corpus runs pin exactly.
		for feature in GraphFuzzerSeamDrawFeature.allCases where feature.isLazyRouteShape {
			#expect(Self.seamCorpusAcceptedDrawFeatureCounts[feature, default: 0] >= Self.gatingDrawJudgedGraphFloor, "\(feature.rawValue) is pinned in fewer than ten accepted graphs")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func toolRuns_acceptErasedPlaceOfForwardedPropertiesOfHandConformingType_whenSeamCorpusDrawsItBesideInstantiatorPlace() async throws {
		// Seed 135 holds `HoleHanded`, which declares that it forwards an `Int`, in a `SendableErasedInstantiator` of
		// `HoleHanded.ForwardedProperties` beside its `Instantiator` place, and the calling module fills both with
		// `HoleHandedImpl`, its subclass that forwards `holeHandedId`: the calling module trusts the class's conformance at
		// the erased place as at the instantiator place, and accepts the graph.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 135, features: [.generateDependencyTree])
		#expect(GraphFuzzerFeature.seamDrawFeatures(of: fixture).isSuperset(of: [.holeInstantiatorPlace, .holeInstantiatorPlaceBesideErased]))
		#expect(fixture.swiftFileContent.contains { $0.contains("public typealias ForwardedProperties = Int") })

		let runs = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: [])

		guard case .accepted = runs.firstOutcome else {
			Issue.record("Seed 135 is expected to be accepted:\n\(runs.firstOutcome.description)")
			return
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func toolRuns_acceptPlaceForwardingNothingBesidePlainPlace_whenSeamCorpusDeclaresHoleImplInNamespace() async throws {
		// Seed 153 declares `HoleImpl` in an extension of `HoleNamespace` and holds a place that forwards nothing beside the
		// plain place of `any HoleService`, of the same builder: the place names `HoleImpl` as its declaration spells it,
		// `HoleNamespace.HoleImpl`, which the calling module's fill declares, so the tool accepts the graph.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 153, features: [.generateDependencyTree])
		#expect(GraphFuzzerFeature.seamDrawFeatures(of: fixture).isSuperset(of: [.holeImplInNamespace, .holeNothingForwardedPlaceBesidePlain]))
		#expect(fixture.swiftFileContent.contains { $0.contains("@Instantiated(fulfilledByType: \"S153_HoleNamespace.S153_HoleImpl\") let holeServiceLater") })

		let runs = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: [])

		guard case .accepted = runs.firstOutcome else {
			Issue.record("Seed 153 is expected to be accepted:\n\(runs.firstOutcome.description)")
			return
		}
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The retention oracle runs compiled code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueComparisons_countGraphJudgedHoldingErasedInstantiatorAndFindNoLeak_whenRetentionDrawsLeafPlaceThatForwards() async throws {
		// Seed 454 holds `RetainLeaf`'s place in an `ErasedInstantiator<Int, any S454_RetainApi>`, which `RetainLive` fills
		// forwarding `retainTicket`: the retention oracle holds that wrapper, and the builder the seam keeps for it keeps
		// alive no value of `RetainHome`'s level, as inline. The graph's hole draws an instantiator place too, which the
		// oracle holds in its own experiment.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 454, features: [.generateDependencyTree])
		#expect(GraphFuzzerFeature.seamDrawFeatures(of: fixture).contains(.retentionSeamValueBeforeBuilderForwardingPlace))
		#expect(fixture.swiftFileContent.contains { $0.contains("let retainApiBuilder: ErasedInstantiator<Int, any S454_RetainApi>") })

		let comparisons = try await GraphFuzzerOracle.valueComparisons(of: [GraphFuzzerOracle.toolRuns(of: fixture, renamings: [])])

		#expect(comparisons.retentionCounts[454] == GraphFuzzerRetentionCounts(
			judged: 1,
			judgedDrawingRetentionShape: 1,
			judgedThroughHandWrittenBuilder: 1,
			unpairedExperiments: 0,
			judgedHoldingForwardingWrapper: ["Instantiator": 1, "ErasedInstantiator": 1],
		))
		#expect(comparisons.retentionFailures[454] == nil)
	}

	@Test
	func forwardedLabelAcrossSeamCallSamples_registerASampleOfEachForwardedLabel_whenSeamCorpusGraphDrawsTheShape() {
		// The comparator calls an instantiator whose type forwards a value only with a sample of that value, so every graph
		// of the forwarded-label draw must register one for `ForwardedOuter`'s label and `ForwardedInner`'s, or the value and
		// retention oracles never build the inner seam or its fill.
		let fixtures = (0..<UInt64(Self.seamCorpusSeedCount)).map { GraphFuzzerGenerator.fixture(forSeed: $0, features: [.generateDependencyTree], storingEveryParameter: true) }
		var seedsMissingASample = [UInt64]()
		for fixture in fixtures where GraphFuzzerFeature.seamDrawFeatures(of: fixture).contains(.forwardedLabelAcrossSeamCall) {
			let sampledTypes = Set(fixture.forwardedLabelAcrossSeamCallSamples.map(\.type))
			let outerForwards = !GraphFuzzerFeature.seamDrawFeatures(of: fixture).contains(.forwardedLabelAcrossSeamCallOuterDefers)
			var expectedTypes: Set = ["\(fixture.typeNamePrefix)ForwardedInner.ForwardedProperties"]
			if outerForwards {
				expectedTypes.insert("\(fixture.typeNamePrefix)ForwardedOuter.ForwardedProperties")
			}
			if sampledTypes != expectedTypes {
				seedsMissingASample.append(fixture.seed)
			}
		}
		#expect(seedsMissingASample == [])
		// Seed 59 forwards `forwardedId` as an `Int` into the inner seam and as a `String` into its caller; seed 69 forwards
		// `forwardedUser`, a class, into both.
		#expect(fixtures[59].forwardedLabelAcrossSeamCallSamples.sorted { $0.type < $1.type } == [
			DifferentialValueSample(type: "S59_ForwardedInner.ForwardedProperties", expression: "7"),
			DifferentialValueSample(type: "S59_ForwardedOuter.ForwardedProperties", expression: "\"7\""),
		])
		#expect(fixtures[69].forwardedLabelAcrossSeamCallSamples.sorted { $0.type < $1.type } == [
			DifferentialValueSample(type: "S69_ForwardedInner.ForwardedProperties", expression: "S69_ForwardedUser()"),
			DifferentialValueSample(type: "S69_ForwardedOuter.ForwardedProperties", expression: "S69_ForwardedUser()"),
		])
	}

	@Test
	func placeInFillInnerScreenSamples_registerASampleOfTheScreensForwardedValue_whenPublicMockCorpusGraphDeclaresTheScreen() {
		// The comparator calls `PlaceInFillInnerScreen`'s instantiator, which forwards `placeInFillId`, only with a sample of
		// it, so every graph that declares the screen must register one, or the value and retention oracles never build the
		// screen, its place or the fill that reads `placeInFillId`.
		var graphsWithTheScreen = 0
		var seedsWithOtherSamples = [UInt64]()
		for seed in 0..<UInt64(Self.publicMockCorpusSeedCount) {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic], storingEveryParameter: true)
			let screenName = "\(fixture.typeNamePrefix)PlaceInFillInnerScreen"
			let declaresTheScreen = fixture.swiftFileContent.contains { content in GraphFuzzerSourceLine.lines(of: content).contains { $0.declaredTypeName == screenName } }
			let expectedSamples = declaresTheScreen ? [DifferentialValueSample(type: "\(screenName).ForwardedProperties", expression: "7")] : []
			if declaresTheScreen {
				graphsWithTheScreen += 1
			}
			if fixture.placeInFillInnerScreenSamples != expectedSamples {
				seedsWithOtherSamples.append(seed)
			}
		}
		#expect(seedsWithOtherSamples == [])
		#expect(graphsWithTheScreen >= Self.gatingDrawJudgedGraphFloor)
	}

	@Test
	func fixtureWithoutSecondHolePlace_leavesOutAPlace_whenSeamCorpusGraphDrawsANestedBuildersShape() {
		// The name-stability oracle compares a graph with and without its second place of a hole, so every graph that draws
		// one of the nested builders' shapes – the cycle of two seams and the place inside a `@Sendable` fill among them –
		// must record a place to leave out, or the oracle never judges that shape.
		let nestedBuildersShapes: Set<GraphFuzzerSeamDrawFeature> = [
			.holeSecondHoleType,
			.holeLazyWrapperBesideByValuePlace,
			.holeSendableLazyWrapperBesideByValuePlace,
			.holeTwoSeamCycleWithSendableEdge,
			.holeInnerSeamPlainAndSendableRoutes,
			.holeInnerSeamWithBothEnums,
			.holeInnerSendablePlaceOnSendableRoute,
			.holePlaceInsideSendableFill,
		]
		var seedsWithoutPlace = [UInt64: [GraphFuzzerSeamDrawFeature]]()
		for seed in 0..<UInt64(Self.seamCorpusSeedCount) {
			let shapes = GraphFuzzerFeature.seamDrawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])).intersection(nestedBuildersShapes)
			guard !shapes.isEmpty, GraphFuzzerGenerator.fixtureWithoutSecondHolePlace(forSeed: seed, features: [.generateDependencyTree]) == nil else { continue }
			seedsWithoutPlace[seed] = shapes.sorted()
		}
		#expect(seedsWithoutPlace == [:])
	}

	@Test
	func isSeamOnlyRejection_tellsSeamsOwnErrorsFromInlinedValidations_whenDiagnosticsAreClassified() {
		// The differential oracle counts a rejection as a seam's own only when every error is reported about the
		// seam's generated initializer or a call of it.
		let collision = "/F/Screen.swift:1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `x` as `x: X` on `A` and `x: Y?` on `B`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.\n/F/A.swift:7:5: note: `A` receives `x: X` here."
		let missingModuleInfo = "/F/Screen.swift:1:1: error: SafeDI cannot generate a call to the initializer SafeDI generated for `Screen` in module `Core`: that initializer takes what the type’s dependency tree needs from the declarations `Core` sees, which include module `Base`’s, and this run was not given `Base`’s SafeDI module info."
		let unfulfillable = "/F/A.swift:7:5: error: @Received property `x: X` is not @Instantiated or @Forwarded in chain: Root -> Screen -> A."
		#expect(GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: collision, seamTypeNames: ["Screen"]))
		#expect(GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: missingModuleInfo, seamTypeNames: ["Screen"]))
		let parameterCapture = "/F/Detail.swift:7:5: error: @Received property `cache: LazilyInstantiated<Cache>?` cannot be received inside a `@Sendable` function in chain: Screen -> Detail. SafeDI builds `detailBuilder: SendableInstantiator<Detail>` on `Screen` in a `@Sendable` function, which cannot capture `cache: LazilyInstantiated<Cache>?`, which the tree of `Screen` receives from outside it, because `LazilyInstantiated<Cache>` is not `Sendable`."
		let declaredCapture = "/F/Detail.swift:7:5: error: @Received property `cache: Cache` cannot be received inside a `@Sendable` function in chain: Root -> Detail. SafeDI builds `detailBuilder: SendableInstantiator<Detail>` on `Root` in a `@Sendable` function, which cannot capture `cache: LazilyInstantiated<Cache>` on `Root`, because `LazilyInstantiated<Cache>` is not `Sendable`."
		#expect(GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: parameterCapture, seamTypeNames: ["Screen"]))
		#expect(!GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: declaredCapture, seamTypeNames: ["Screen"]))
		#expect(!GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: unfulfillable, seamTypeNames: ["Screen"]))
		#expect(!GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: "\(collision)\n\(unfulfillable)", seamTypeNames: ["Screen"]))
		#expect(!GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: "", seamTypeNames: ["Screen"]))
		// A caller's error that it holds a value its tier omits is a seam's own only in a graph split across modules: a
		// seam a graph in one module calls is called at its narrowest tier, which omits nothing.
		let omittedValue = "/F/Host.swift:3:2: error: `Host` provides `theme: Theme`, but the `public` initializer SafeDI generated for `Screen` in module `Feature`, the narrowest one module `App` can call, does not take it."
		#expect(!GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: omittedValue, seamTypeNames: ["Screen"]))
		#expect(GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: omittedValue, seamTypeNames: ["Screen"], excusingOmittedValues: true))
		// A hidden-label error in a chain that starts at a seam is the seam's: inline reports it only from a root that
		// provides the property, so a caller that holds nothing builds the graph inline.
		let hiddenAtSeam = "/F/Reader.swift:7:5: error: @Received property `token: Secret?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix."
		let hiddenAtRoot = "/F/Reader.swift:7:5: error: @Received property `token: Secret?` is hidden in chain: Root -> Screen -> Left -> Reader. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix."
		#expect(GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: hiddenAtSeam, seamTypeNames: ["Screen"]))
		#expect(!GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: hiddenAtSeam, seamTypeNames: []))
		#expect(!GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: hiddenAtRoot, seamTypeNames: ["Screen"]))
	}

	@Test
	func differentialFailure_reportsSeed_whenSeamRejectsGraphWithInlinedValidationsErrorAndInlineAccepts() {
		// A graph the tool rejects with the seam declared, with an error of the inlined validation, and accepts with
		// no seam is a defect of the seam world; one it rejects with a seam's own error is what the seam rules
		// reject, and one it rejects inline too is no seam's doing.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 0, features: [.generateDependencyTree])
		let unfulfillable = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/A.swift:7:5: error: @Received property `x: X` is not @Instantiated or @Forwarded in chain: Root -> Screen -> A.")
		let collision = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/Screen.swift:1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `x` as `x: X` on `A` and `x: Y?` on `B`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.")
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		let defect = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: unfulfillable, secondOutcome: unfulfillable, inlineOutcome: accepted)
		#expect(defect.differentialFailure?.kind == .seamRejectsGraphInlineAccepts)
		#expect(defect.differentialFailure?.details == "With the seam:\n/F/A.swift:7:5: error: @Received property `x: X` is not @Instantiated or @Forwarded in chain: Root -> Screen -> A.\nWithout it, the tool accepts the graph.")
		let seamsOwnError = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: collision, secondOutcome: collision, inlineOutcome: accepted)
		#expect(seamsOwnError.differentialFailure == nil)
		let rejectedInlineToo = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: unfulfillable, secondOutcome: unfulfillable, inlineOutcome: unfulfillable)
		#expect(rejectedInlineToo.differentialFailure == nil)
		let accepted2 = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: accepted, secondOutcome: accepted)
		#expect(accepted2.differentialFailure == nil)
	}

	@Test
	func acceptanceDifferentialFailure_reportsSeamAcceptsGraphInlineRejects_whenSingleModuleGraphIsAcceptedWithSeamAndRejectedWithout() {
		// In one module the seam world adds rules to the inlined validation and removes none, so a graph the seam accepts
		// and inline rejects is a defect. Across modules the inline build cannot construct another module's `internal`
		// types, so a split graph is not judged.
		let singleModuleFixture = GraphFuzzerGenerator.fixture(forSeed: 1, features: [.generateDependencyTree])
		let splitFixture = GraphFuzzerGenerator.fixture(forSeed: 31, features: [.generateDependencyTree])
		#expect(singleModuleFixture.modules == nil)
		#expect(splitFixture.modules != nil)
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		let rejected = GraphFuzzerToolOutcome.rejected(diagnostics: "Root.swift:1:1: error: e")
		let defect = GraphFuzzerToolRuns(fixture: singleModuleFixture, firstOutcome: accepted, secondOutcome: accepted, inlineOutcome: rejected)
		#expect(defect.acceptanceDifferentialFailure?.kind == .seamAcceptsGraphInlineRejects)
		#expect(defect.acceptanceDifferentialFailure?.details == "With the seam, the tool accepts the graph.\nWithout it:\nRoot.swift:1:1: error: e")
		#expect(GraphFuzzerToolRuns(fixture: splitFixture, firstOutcome: accepted, secondOutcome: accepted, inlineOutcome: rejected).acceptanceDifferentialFailure == nil)
		#expect(GraphFuzzerToolRuns(fixture: singleModuleFixture, firstOutcome: accepted, secondOutcome: accepted, inlineOutcome: accepted).acceptanceDifferentialFailure == nil)
	}

	@Test
	func integrationsDisagreeFailure_reportsDisagreement_whenPluginFlowRejectsWhatModuleInfoFlowAccepts() {
		// The SwiftPM plugin flow computes every seam signature, tier and public mock from source, and must give a split
		// graph the verdict the module-info flow gives it.
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzApp/S31_Root+SafeDI.swift": Self.rootInitializer], warnings: [])
		let rejected = GraphFuzzerToolOutcome.rejected(diagnostics: Self.rootError)
		#expect(Self.integrationRuns(moduleInfoOutcome: accepted, pluginOutcome: rejected).integrationsDisagreeFailure?.kind == .integrationsDisagree)
		#expect(Self.integrationRuns(moduleInfoOutcome: accepted, pluginOutcome: rejected).integrationsDisagreeFailure?.details.prefix { $0 != "\n" } == "The module-info flow accepts the graph, and the SwiftPM plugin flow rejects it.")
		#expect(Self.integrationRuns(moduleInfoOutcome: rejected, pluginOutcome: accepted).integrationsDisagreeFailure?.details.prefix { $0 != "\n" } == "The module-info flow rejects the graph, and the SwiftPM plugin flow accepts it.")
		#expect(Self.integrationRuns(moduleInfoOutcome: accepted, pluginOutcome: nil).integrationsDisagreeFailure == nil)
	}

	@Test
	func integrationsDisagreeFailure_reportsDisagreement_whenFlowsRejectGraphWithOtherDiagnostics() {
		// Both flows lay a module's files out at the same paths, so a rejection's diagnostics are compared as they are.
		let rejected = GraphFuzzerToolOutcome.rejected(diagnostics: Self.rootError)
		let rejectedOtherwise = GraphFuzzerToolOutcome.rejected(diagnostics: Self.rootError + "\n/x/<fixture-directory>/shop/Sources/FuzzApp/S31_Root.swift:2:1: error: f")
		#expect(Self.integrationRuns(moduleInfoOutcome: rejected, pluginOutcome: rejectedOtherwise).integrationsDisagreeFailure?.details.prefix { $0 != "\n" } == "The two flows report other diagnostics.")
		#expect(Self.integrationRuns(moduleInfoOutcome: rejected, pluginOutcome: rejected).integrationsDisagreeFailure == nil)
	}

	@Test
	func integrationsDisagreeFailure_reportsFirstDeclarationOneFlowGenerates_whenGeneratedCodeDiffers() {
		// A declaration only one of the flows generates is a disagreement, whichever flow and whatever file holds it.
		let optionalAlias = Self.rootInitializer.replacingOccurrences(of: "let authToken: S31_Secret = token", with: "let authToken: S31_Secret? = token")
		let runs = Self.integrationRuns(
			moduleInfoOutcome: .accepted(generatedFiles: ["FuzzApp/S31_Root+SafeDI.swift": Self.rootInitializer], warnings: []),
			pluginOutcome: .accepted(generatedFiles: ["FuzzApp/S31_Root+SafeDI.swift": optionalAlias], warnings: []),
		)
		#expect(runs.integrationsDisagreeFailure?.details.hasPrefix("Only the module-info flow generates, in FuzzApp:\n\(Self.rootExtension)\nThe module-info flow:\n") == true)
		let pluginOnlyRuns = Self.integrationRuns(
			moduleInfoOutcome: .accepted(generatedFiles: [:], warnings: []),
			pluginOutcome: .accepted(generatedFiles: ["FuzzApp/S31_Root+SafeDI.swift": Self.rootInitializer], warnings: []),
		)
		#expect(pluginOnlyRuns.integrationsDisagreeFailure?.details.hasPrefix("Only the SwiftPM plugin flow generates, in FuzzApp:\nextension S31_Root {") == true)
	}

	@Test
	func knownIssueMatches_matchesFailureOfSignaturesKind_whenDetailsContainSignaturesText() {
		// A known issue of either new oracle documents a failure of its kind whose details contain its text, and no other.
		let acceptance = GraphFuzzerKnownIssue(reason: "r", signatures: [.seamAcceptsGraphInlineRejects(containing: "error: e")], seeds: [1])
		let integrations = GraphFuzzerKnownIssue(reason: "r", signatures: [.integrationsDisagree(containing: "in FuzzApp")], seeds: [31])
		let acceptanceFailure = GraphFuzzerFailure(seed: 1, kind: .seamAcceptsGraphInlineRejects, details: "Without it:\nRoot.swift:1:1: error: e")
		let integrationsFailure = GraphFuzzerFailure(seed: 31, kind: .integrationsDisagree, details: "Only the SwiftPM plugin flow generates, in FuzzApp:")
		#expect(acceptance.matches(acceptanceFailure))
		#expect(!acceptance.matches(integrationsFailure))
		#expect(integrations.matches(integrationsFailure))
		#expect(!integrations.matches(acceptanceFailure))
	}

	@Test
	func integrationsDisagreeFailure_returnsNil_whenOutputsDifferOnlyBySourceLocationAndPluginHeader() {
		// Only a flow that knows the compiler's spelling of an alias's file refers to it with a `#sourceLocation`
		// directive, and every file the plugin writes opens with its header.
		let withDirective = Self.rootInitializer.replacingOccurrences(
			of: "        let authToken: S31_Secret = token\n",
			with: "        #sourceLocation(file: \"/x/<fixture-directory>/shop/Sources/FuzzApp/S31_Root.swift\", line: 8)\n        let authToken: S31_Secret = token\n        #sourceLocation()\n",
		)
		let withHeader = GraphFuzzerOracle.generatedFileHeaderLines.joined(separator: "\n") + "\n" + Self.rootInitializer
		let runs = Self.integrationRuns(
			moduleInfoOutcome: .accepted(generatedFiles: ["FuzzApp/S31_Root+SafeDI.swift": withDirective], warnings: []),
			pluginOutcome: .accepted(generatedFiles: ["FuzzApp/S31_Root+SafeDI.swift": withHeader], warnings: []),
		)
		#expect(withDirective != withHeader)
		#expect(runs.integrationsDisagreeFailure == nil)
	}

	@Test
	func integrationsDisagreeFailure_returnsNil_whenOutputsDifferOnlyByCommentsOneFlowWritesForWhatItCannotKnow() {
		// A flow that cannot spell an alias's file as the compiler does refers to it with a comment, a seam call carries a
		// comment saying what each flow does when the call does not compile, and a run without a target graph names the
		// types it counts as `public` because it reads no declaration of them.
		let withUnreadTypeComment = Self.rootInitializer
			.replacingOccurrences(
				of: "    public convenience init() {",
				with: "    // SafeDI counts `S31_Secret` as `public`: no module it reads declares it narrower. If `S31_Secret` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.\n    public convenience init() {",
			)
			.replacingOccurrences(of: "_ = S31_Screen.__safeDI_S31_Screen_0123456789ABCDEF.self", with: "_ = S31_Screen.__safeDI_S31_Screen_0123456789ABCDEF.self" + MultiModuleIntegration.moduleInfo.seamCallComment(type: "S31_Screen", declaringModule: "FuzzFeature"))
		let withComments = Self.rootInitializer
			.replacingOccurrences(of: "let authToken: S31_Secret = token", with: "let authToken: S31_Secret = token // Declared at Sources/FuzzApp/S31_Root.swift:8")
			.replacingOccurrences(of: "_ = S31_Screen.__safeDI_S31_Screen_0123456789ABCDEF.self", with: "_ = S31_Screen.__safeDI_S31_Screen_0123456789ABCDEF.self // If this line does not compile, add the SafeDI plugin to the target that declares S31_Screen.")
		let runs = Self.integrationRuns(
			moduleInfoOutcome: .accepted(generatedFiles: ["FuzzApp/S31_Root+SafeDI.swift": withUnreadTypeComment], warnings: []),
			pluginOutcome: .accepted(generatedFiles: ["FuzzApp/S31_Root+SafeDI.swift": withComments], warnings: []),
		)
		#expect(withComments.components(separatedBy: " // ").count == 3)
		#expect(withUnreadTypeComment != Self.rootInitializer)
		#expect(runs.integrationsDisagreeFailure == nil)
	}

	@Test
	func integrationsDisagreeFailure_returnsNil_whenOnlyPluginFlowAssertsDecisionAboutBlockInDependencysFile() {
		// The SwiftPM plugin flow reads a dependency's files under the reading module's conditions, so the reading module
		// asserts the decisions it made about the dependency's blocks, as it asserts a dependency's `@Instantiable`
		// decisions; the module-info flow reads the dependency's `.safedi` and leaves the assertion to the dependency.
		// Seed 326's `FuzzFeature` declares a type under `#if !FUZZ_FLAG`.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 326, features: [.generateDependencyTree])
		let flagAssertion = ConditionalCompilationDecision.compileTimeAssertions(for: [ConditionalCompilationDecision(condition: "!FUZZ_FLAG", isActive: true)])
		let runs = GraphFuzzerToolRuns(
			fixture: fixture,
			firstOutcome: .accepted(generatedFiles: ["FuzzApp/S31_Root+SafeDI.swift": Self.rootInitializer], warnings: []),
			secondOutcome: .accepted(generatedFiles: ["FuzzApp/S31_Root+SafeDI.swift": Self.rootInitializer], warnings: []),
			pluginOutcome: .accepted(generatedFiles: ["FuzzApp/S31_Root+SafeDI.swift": flagAssertion + Self.rootInitializer], warnings: []),
		)
		#expect(zip(fixture.swiftFileContent, fixture.modules ?? []).contains { $0.contains("#if !FUZZ_FLAG\n") && $1 == .seamModule })
		#expect(runs.integrationsDisagreeFailure == nil)
	}

	@Test
	func integrationsDisagreeFailure_reportsAssertion_whenItIsNotPluginFlowsAssertionAboutBlockInDependencysFile() {
		// Only the plugin flow's assertion of a decision about a block that a dependency's file spells, and the reading
		// module's do not, is excused: an assertion the module-info flow alone writes, one in the module that spells the
		// block, one about a condition no dependency spells, and a block that is not an assertion of one decision are
		// still differences.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 326, features: [.generateDependencyTree])
		let flagAssertion = ConditionalCompilationDecision.compileTimeAssertions(for: [ConditionalCompilationDecision(condition: "!FUZZ_FLAG", isActive: true)])
		let otherAssertion = ConditionalCompilationDecision.compileTimeAssertions(for: [ConditionalCompilationDecision(condition: "OTHER_FLAG", isActive: false)])
		let unbalancedAssertion = flagAssertion.replacingOccurrences(of: "#if !(!FUZZ_FLAG)", with: "#if FUZZ_FLAG")
		func failure(moduleInfoFiles: [String: String], pluginFiles: [String: String]) -> String? {
			GraphFuzzerToolRuns(
				fixture: fixture,
				firstOutcome: .accepted(generatedFiles: moduleInfoFiles, warnings: []),
				secondOutcome: .accepted(generatedFiles: moduleInfoFiles, warnings: []),
				pluginOutcome: .accepted(generatedFiles: pluginFiles, warnings: []),
			).integrationsDisagreeFailure?.details.components(separatedBy: "\nThe module-info flow:\n").first
		}
		#expect(failure(
			moduleInfoFiles: ["FuzzApp/S31_Root+SafeDI.swift": flagAssertion + Self.rootInitializer],
			pluginFiles: ["FuzzApp/S31_Root+SafeDI.swift": Self.rootInitializer],
		) == "Only the module-info flow generates, in FuzzApp:\n\(flagAssertion.trimmingCharacters(in: .whitespacesAndNewlines))")
		#expect(failure(
			moduleInfoFiles: ["FuzzFeature/S31_Screen+SafeDI.swift": "extension S31_Screen {}\n"],
			pluginFiles: ["FuzzFeature/S31_Screen+SafeDI.swift": flagAssertion + "extension S31_Screen {}\n"],
		) == "Only the SwiftPM plugin flow generates, in FuzzFeature:\n\(flagAssertion.trimmingCharacters(in: .whitespacesAndNewlines))")
		#expect(failure(
			moduleInfoFiles: ["FuzzApp/S31_Root+SafeDI.swift": Self.rootInitializer],
			pluginFiles: ["FuzzApp/S31_Root+SafeDI.swift": otherAssertion + Self.rootInitializer],
		) == "Only the SwiftPM plugin flow generates, in FuzzApp:\n\(otherAssertion.trimmingCharacters(in: .whitespacesAndNewlines))")
		#expect(failure(
			moduleInfoFiles: ["FuzzApp/S31_Root+SafeDI.swift": Self.rootInitializer],
			pluginFiles: ["FuzzApp/S31_Root+SafeDI.swift": unbalancedAssertion + Self.rootInitializer],
		) == "Only the SwiftPM plugin flow generates, in FuzzApp:\n\(unbalancedAssertion.trimmingCharacters(in: .whitespacesAndNewlines))")
	}

	/// The runs of seam smoke seed 31's graph, split across modules with every package name given, with `moduleInfoOutcome`
	/// as Bazel runs the tool and `pluginOutcome` as the SwiftPM plugin runs it.
	private static func integrationRuns(moduleInfoOutcome: GraphFuzzerToolOutcome, pluginOutcome: GraphFuzzerToolOutcome?) -> GraphFuzzerToolRuns {
		GraphFuzzerToolRuns(fixture: GraphFuzzerGenerator.fixture(forSeed: 31, features: [.generateDependencyTree]), firstOutcome: moduleInfoOutcome, secondOutcome: moduleInfoOutcome, pluginOutcome: pluginOutcome)
	}

	/// A root's generated file in the module of a split graph that calls a seam: its import and `rootExtension`.
	private static let rootInitializer = "import FuzzFeature\n\n\(rootExtension)\n"

	/// The extension declaring that root's generated initializer.
	private static let rootExtension = """
	extension S31_Root {
	    public convenience init() {
	        let token = S31_Secret()
	        let authToken: S31_Secret = token
	        func __safeDI_screen() -> S31_Screen {
	            _ = S31_Screen.__safeDI_S31_Screen_0123456789ABCDEF.self
	            return S31_Screen(__safeDI_token: token)
	        }
	        let screen: S31_Screen = __safeDI_screen()
	        self.init(authToken: authToken, screen: screen)
	    }
	}
	"""

	/// An error at the root of that module.
	private static let rootError = "/x/<fixture-directory>/shop/Sources/FuzzApp/S31_Root.swift:1:1: error: e"

	// MARK: Read twin

	@Test
	func readTwin_declaresEachUnreadTypePublicInLowestModuleNamingIt_whenGraphDrawsValueOfTypeSafeDIReadsNoDeclarationOf() throws {
		// Each seam and public mock corpus graph that draws a value of a type no declaration SafeDI reads declares has a read
		// twin, which renames the type wherever the graph names it and declares the twin once, at the end of the first file
		// naming it of the lowest module whose files name it, so that every module naming it can see it: renaming the twin
		// back and dropping that declaration gives the graph back. Between them the corpora twin every type the fuzzer draws.
		var twinnedTypeNames = Set<String>()
		for fixture in Self.corpusFixtures(drawingUnreadValue: true) {
			let readTwin = try #require(fixture.readTwin, "Seed \(fixture.seed) has no read twin")
			twinnedTypeNames.formUnion(readTwin.unreadTypes.map(\.name))
			let twinContent = readTwin.fixture.swiftFileContent
			#expect(twinContent.allSatisfy { content in !readTwin.unreadTypes.contains { $0.isNamed(in: content) } }, "Seed \(fixture.seed)")
			let declaringIndices = twinContent.indices.filter { twinContent[$0].hasSuffix(readTwin.declarations) }
			let declaringIndex = try #require(declaringIndices.count == 1 ? declaringIndices.first : nil, "Seed \(fixture.seed)")
			let restoredContent = twinContent.indices.map { index in
				readTwin.restoring(index == declaringIndex ? String(twinContent[index].dropLast(readTwin.declarations.count)) : twinContent[index])
			}
			#expect(restoredContent == fixture.swiftFileContent, "Seed \(fixture.seed)")
			let namingIndices = fixture.swiftFileContent.indices.filter { index in readTwin.unreadTypes.contains { $0.isNamed(in: fixture.swiftFileContent[index]) } }
			if let modules = fixture.modules {
				#expect(readTwin.declaringModule == modules[declaringIndex], "Seed \(fixture.seed)")
				#expect(namingIndices.allSatisfy { (modules[declaringIndex], declaringIndex) <= (modules[$0], $0) }, "Seed \(fixture.seed)")
				#expect(namingIndices.allSatisfy { modules[$0] == modules[declaringIndex] || modules[$0].dependencies.contains(modules[declaringIndex]) }, "Seed \(fixture.seed)")
			} else {
				#expect(readTwin.declaringModule == nil, "Seed \(fixture.seed)")
				#expect(namingIndices.first == declaringIndex, "Seed \(fixture.seed)")
			}
		}
		#expect(twinnedTypeNames == Set(GraphFuzzerReadTwin.UnreadType.all.map(\.name)))
	}

	@Test
	func readTwin_isNil_whenGraphDrawsNoValueOfTypeSafeDIReadsNoDeclarationOf() {
		// A graph naming no type no declaration SafeDI reads declares has nothing to twin: the base corpus's graphs, and the
		// seam and public mock corpus graphs that do not draw such a value.
		#expect((0..<UInt64(100)).filter { GraphFuzzerGenerator.fixture(forSeed: $0).readTwin != nil } == [])
		#expect(Self.corpusFixtures(drawingUnreadValue: false).filter { $0.readTwin != nil }.map(\.seed) == [])
	}

	@Test
	func readTwinFailure_reportsVerdict_whenReadTwinIsRejectedWhereGraphIsAccepted() throws {
		// SafeDI counts a type it reads no declaration of as `public`, so declaring the type `public` where SafeDI reads it
		// changes no verdict.
		let fixture = try Self.readTwinFixture()
		let runs = Self.readTwinRuns(
			of: fixture,
			outcome: .accepted(generatedFiles: Self.readTwinFiles(of: fixture, featureCommentNames: ["StaticString"]), warnings: []),
			readTwinOutcome: .rejected(diagnostics: "/x/<fixture-directory>/shop/Sources/FuzzFeature/\(fixture.typeNamePrefix)UnreadSeam.swift:3:1: error: e"),
		)
		#expect(runs.readTwinFailure?.kind == .readTwinDiffers)
		#expect(runs.readTwinFailure?.details.prefix { $0 != "\n" } == "Declaring `StaticString` `public` where SafeDI reads it changes its verdict.")
	}

	@Test
	func readTwinFailure_reportsComment_whenReadTwinsOwnModuleStillNamesTheReadType() throws {
		// The module that declares the twin reads its declaration, so its comment names no twinned type.
		let fixture = try Self.readTwinFixture()
		let files = Self.readTwinFiles(of: fixture, featureCommentNames: ["StaticString"])
		let runs = Self.readTwinRuns(of: fixture, outcome: .accepted(generatedFiles: files, warnings: []), readTwinOutcome: .accepted(generatedFiles: files, warnings: []))
		#expect(runs.readTwinFailure?.kind == .readTwinDiffers)
		#expect(runs.readTwinFailure?.details.prefix { $0 != "\n" } == "Declaring `StaticString` `public` where SafeDI reads it changes the types the comment in FuzzFeature names.")
	}

	@Test
	func readTwinFailure_reportsComment_whenModuleReadingTwinThroughModuleInfoStillNamesTheReadType() throws {
		// The module declaring the twin names it in a declaration, so even a `.safedi` written without a target graph, which
		// keeps no other `public` declaration, keeps the twin's: a module that depends on it reads the twin there.
		let fixture = try Self.readTwinFixture()
		let runs = Self.readTwinRuns(
			of: fixture,
			outcome: .accepted(generatedFiles: Self.readTwinFiles(of: fixture, featureCommentNames: ["StaticString"], appCommentNames: ["StaticString"]), warnings: []),
			readTwinOutcome: .accepted(generatedFiles: Self.readTwinFiles(of: fixture, featureCommentNames: nil, appCommentNames: ["StaticString"]), warnings: []),
		)
		#expect(runs.readTwinFailure?.details.prefix { $0 != "\n" } == "Declaring `StaticString` `public` where SafeDI reads it changes the types the comment in FuzzApp names.")
	}

	@Test
	func readTwinFailure_isNil_whenReadTwinsCommentsNameEveryTypeTheGraphsNameButTheReadType() throws {
		// Only the twinned type leaves the comment, in every module; a type no declaration SafeDI reads declares that the
		// twin does not rename stays in it, and the comment moves to whichever declaration then names one first.
		let fixture = try Self.readTwinFixture()
		let runs = Self.readTwinRuns(
			of: fixture,
			outcome: .accepted(generatedFiles: Self.readTwinFiles(of: fixture, featureCommentNames: ["Duration", "StaticString"], appCommentNames: ["StaticString"]), warnings: []),
			readTwinOutcome: .accepted(generatedFiles: Self.readTwinFiles(of: fixture, featureCommentNames: ["Duration"], appCommentNames: nil), warnings: []),
		)
		#expect(runs.readTwinFailure == nil)
	}

	@Test
	func readTwinFailure_reportsComment_whenReadTwinsCommentStopsNamingAnotherType() throws {
		// Declaring one type changes how SafeDI counts no other.
		let fixture = try Self.readTwinFixture()
		let runs = Self.readTwinRuns(
			of: fixture,
			outcome: .accepted(generatedFiles: Self.readTwinFiles(of: fixture, featureCommentNames: ["Duration", "StaticString"]), warnings: []),
			readTwinOutcome: .accepted(generatedFiles: Self.readTwinFiles(of: fixture, featureCommentNames: nil), warnings: []),
		)
		#expect(runs.readTwinFailure?.details.prefix { $0 != "\n" } == "Declaring `StaticString` `public` where SafeDI reads it changes the types the comment in FuzzFeature names.")
	}

	@Test
	func readTwinFailure_reportsGeneratedCode_whenReadTwinsSeamTakesTheReadTypeOnNarrowerTier() throws {
		// A `public` type and a type SafeDI reads no declaration of put a seam's parameter on the same tier.
		let fixture = try Self.readTwinFixture()
		let runs = Self.readTwinRuns(
			of: fixture,
			outcome: .accepted(generatedFiles: Self.readTwinFiles(of: fixture, featureCommentNames: ["StaticString"]), warnings: []),
			readTwinOutcome: .accepted(generatedFiles: Self.readTwinFiles(of: fixture, tier: "package", featureCommentNames: nil), warnings: []),
		)
		#expect(runs.readTwinFailure?.details.prefix { $0 != "\n" } == "Declaring `StaticString` `public` where SafeDI reads it changes its generated dependency tree code, in FuzzFeature/\(fixture.typeNamePrefix)UnreadSeam+SafeDI.swift.")
	}

	@Test
	func readTwinFailure_reportsPluginFlow_whenReadTwinDiffersOnlyAsSwiftPackagePluginRunsTheTool() throws {
		// The SwiftPM plugin reads the twin's declaration in every module that depends on its module, and writes no comment,
		// so there the twin's generated code is the graph's byte for byte.
		let fixture = try Self.readTwinFixture()
		let runs = Self.readTwinRuns(
			of: fixture,
			outcome: .accepted(generatedFiles: Self.readTwinFiles(of: fixture, featureCommentNames: ["StaticString"]), warnings: []),
			readTwinOutcome: .accepted(generatedFiles: Self.readTwinFiles(of: fixture, featureCommentNames: nil), warnings: []),
			pluginOutcome: .accepted(generatedFiles: Self.readTwinFiles(of: fixture, featureCommentNames: nil), warnings: []),
			readTwinPluginOutcome: .accepted(generatedFiles: Self.readTwinFiles(of: fixture, tier: "package", featureCommentNames: nil), warnings: []),
		)
		#expect(runs.readTwinFailure?.details.prefix { $0 != "\n" } == "Declaring `StaticString` `public` where SafeDI reads it changes its generated dependency tree code, in FuzzFeature/\(fixture.typeNamePrefix)UnreadSeam+SafeDI.swift, as the SwiftPM plugin runs the tool.")
	}

	/// The seam corpus's or the public mock corpus's graphs that draw a value of a type no declaration SafeDI reads
	/// declares (`unreadParameterType`), or those that do not.
	private static func corpusFixtures(drawingUnreadValue: Bool) -> [GraphFuzzerFixture] {
		let seamFixtures = (0..<UInt64(seamCorpusSeedCount)).map { GraphFuzzerGenerator.fixture(forSeed: $0, features: [.generateDependencyTree]) }
			.filter { GraphFuzzerFeature.seamDrawFeatures(of: $0).contains(.unreadParameterType) == drawingUnreadValue }
		let publicMockFixtures = (0..<UInt64(publicMockCorpusSeedCount)).map { GraphFuzzerGenerator.fixture(forSeed: $0, features: [.generateMockPublic]) }
			.filter { GraphFuzzerPublicMockDraw.drawFeatures(of: $0).contains(.unreadParameterType) == drawingUnreadValue }
		return seamFixtures + publicMockFixtures
	}

	/// The first seam corpus graph whose seam's module receives a `StaticString`, and no other type no declaration SafeDI
	/// reads declares, that a host in its callers' module forwards.
	private static func readTwinFixture() throws -> GraphFuzzerFixture {
		try #require((0..<UInt64(seamCorpusSeedCount)).lazy.map { GraphFuzzerGenerator.fixture(forSeed: $0, features: [.generateDependencyTree]) }.first { fixture in
			let drawFeatures = GraphFuzzerFeature.seamDrawFeatures(of: fixture)
			return drawFeatures.contains(.unreadParameterType) && drawFeatures.contains(.unreadAcrossModules)
				&& fixture.description.contains("StaticString") && !fixture.description.contains("CustomStringConvertible") && !fixture.description.contains("Unicode")
		})
	}

	/// The runs of `fixture` with `outcome` and `pluginOutcome` as the two flows gave them, and its read twin's, with the
	/// twin's rename undone.
	private static func readTwinRuns(
		of fixture: GraphFuzzerFixture,
		outcome: GraphFuzzerToolOutcome,
		readTwinOutcome: GraphFuzzerToolOutcome,
		pluginOutcome: GraphFuzzerToolOutcome? = nil,
		readTwinPluginOutcome: GraphFuzzerToolOutcome? = nil,
	) -> GraphFuzzerToolRuns {
		GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome, pluginOutcome: pluginOutcome, readTwinOutcome: readTwinOutcome, readTwinPluginOutcome: readTwinPluginOutcome)
	}

	/// Generated files of `fixture`'s modules: the seam's initializer on `tier`, which takes the `StaticString`, in
	/// FuzzFeature, and a public initializer that takes it in FuzzApp, each below the comment naming the given types, one
	/// or two, when there are any.
	private static func readTwinFiles(of fixture: GraphFuzzerFixture, tier: String = "public", featureCommentNames: [String]?, appCommentNames: [String]? = nil) -> [String: String] {
		let prefix = fixture.typeNamePrefix
		func comment(naming names: [String]?) -> String {
			guard let names else { return "" }
			let quotedNames = names.map { "`\($0)`" }
			return quotedNames.count == 1
				? "    // SafeDI counts \(quotedNames[0]) as `public`: no module it reads declares it narrower. If \(quotedNames[0]) is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.\n"
				: "    // SafeDI counts \(quotedNames.joined(separator: " and ")) as `public`: no module it reads declares them narrower. If one is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.\n"
		}
		return [
			"FuzzFeature/\(prefix)UnreadSeam+SafeDI.swift": "extension \(prefix)UnreadSeam {\n\(comment(naming: featureCommentNames))    \(tier) convenience init(unreadValue: StaticString) {\n        self.init(unreadChild: \(prefix)UnreadChild(unreadValue: unreadValue))\n    }\n}\n",
			"FuzzApp/\(prefix)UnreadOuter+SafeDI.swift": "extension \(prefix)UnreadOuter {\n\(comment(naming: appCommentNames))    public convenience init(unreadValue: StaticString) {\n        self.init(unreadSeam: \(prefix)UnreadSeam(unreadValue: unreadValue))\n    }\n}\n",
		]
	}

	@Test
	func nilArgumentFailure_reportsArgument_whenSeamPassesLiteralNilWhereInlinePassesValue() {
		// The nil count counts, over every generated file, the literal `nil` arguments of each construction of a type
		// of the graph: one more with the seam than without it is a receiver that loses a value. A seam type's own
		// constructions are not counted, so the `nil` a wider tier passes for what it omits is no failure – and so a
		// call of a tier that passes `nil` for a value the caller holds is not counted either, which the differential
		// value comparator sees; the sound case therefore passes the value at the call.
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: [
			"@Instantiable(generateDependencyTree: true)\npublic final class S7_Screen: Instantiable {\n\tpublic init(reader: S7_Reader) {\n\t\tself.reader = reader\n\t}\n\n\t@Instantiated let reader: S7_Reader\n}\n",
		])
		let inline = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S7_Root+SafeDI.swift": "let reader = S7_Reader(token: token, user: nil)\nreturn S7_Screen(reader: reader)"], warnings: [])
		let seamPassingNil = GraphFuzzerToolOutcome.accepted(generatedFiles: [
			"S7_Root+SafeDI.swift": "return S7_Screen(token: nil)",
			"S7_Screen+SafeDI.swift": "public init(token: S7_Token?) {\n    let reader = S7_Reader(token: nil, user: nil)\n    self.init(reader: reader)\n}",
		], warnings: [])
		let defect = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: seamPassingNil, secondOutcome: seamPassingNil, inlineOutcome: inline)
		#expect(defect.nilArgumentFailure?.kind == .seamPassesNilWhereInlinePassesValue)
		#expect(defect.nilArgumentFailure?.details.prefix { $0 != "\n" } == "`S7_Reader(token:)` is passed `nil` 1 times with the seam and 0 without it.")
		let seamPassingValue = GraphFuzzerToolOutcome.accepted(generatedFiles: [
			"S7_Root+SafeDI.swift": "let token = S7_Token()\nreturn S7_Screen(token: token)",
			"S7_Screen+SafeDI.swift": "public init(token: S7_Token?) {\n    let reader = S7_Reader(token: token, user: nil)\n    self.init(reader: reader)\n}",
		], warnings: [])
		let sound = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: seamPassingValue, secondOutcome: seamPassingValue, inlineOutcome: inline)
		#expect(sound.nilArgumentFailure == nil)
		#expect(sound.isInspectedByValueOracle)
		let rejected = GraphFuzzerToolOutcome.rejected(diagnostics: "error")
		#expect(GraphFuzzerToolRuns(fixture: fixture, firstOutcome: rejected, secondOutcome: rejected, inlineOutcome: inline).isInspectedByValueOracle == false)
	}

	@Test
	func nilArgumentFailure_countsInlinesNilAtTheConstructionsOfItsBuilderFunction_whenInlinePassesACycleParameterNil() {
		// Inline hands the builder function a lazy cycle closes on a literal `nil` for `mark`, which the construction in its
		// body passes on by name: that `nil` counts at the construction. The function is called twice, so it is shared and
		// stands for places its text does not count: a seam that writes `mark`'s `nil` at one construction or two matches
		// inline, and one that loses `token`, which inline never passes `nil`, does not.
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: [
			"@Instantiable(generateDependencyTree: true)\npublic final class S7_Screen: Instantiable {\n\tpublic init(reader: S7_Reader) {\n\t\tself.reader = reader\n\t}\n\n\t@Instantiated let reader: S7_Reader\n}\n",
		])
		let inlineFiles = [
			"S7_Root+SafeDI.swift": "func __safeDI_ownerBuilder(mark: S7_Mark?) -> S7_Owner {\n    let reader = S7_Reader(token: token, mark: mark)\n    return S7_Owner(reader: reader)\n}\nlet owner = __safeDI_ownerBuilder(mark: nil)\nlet other = __safeDI_ownerBuilder(mark: mark)",
		]
		#expect(GraphFuzzerOracle.nilArgumentCountsThroughBuilderFunctions(in: inlineFiles, typeNamePrefix: "S7_", excluding: []) == ["S7_Reader(mark:)": 1])
		let inline = GraphFuzzerToolOutcome.accepted(generatedFiles: inlineFiles, warnings: [])
		func runs(seamFile: String) -> GraphFuzzerToolRuns {
			let seam = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S7_Root+SafeDI.swift": seamFile], warnings: [])
			return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: seam, secondOutcome: seam, inlineOutcome: inline)
		}
		#expect(runs(seamFile: "let first = S7_Reader(token: token, mark: nil)\nlet second = S7_Reader(token: token, mark: mark)").nilArgumentFailure == nil)
		#expect(runs(seamFile: "let first = S7_Reader(token: token, mark: nil)\nlet second = S7_Reader(token: token, mark: nil)").nilArgumentFailure == nil)
		#expect(runs(seamFile: "let first = S7_Reader(token: nil, mark: nil)").nilArgumentFailure?.details.prefix { $0 != "\n" } == "`S7_Reader(token:)` is passed `nil` 1 times with the seam and 0 without it.")
	}

	@Test
	func nilArgumentFailure_comparesOnlyWhetherNilIsPassed_whenInlinePassesItInASharedBuilderFunction() {
		// The type key builds a type that two places build alike in one function, which each place calls, where the seam
		// writes the type's code at each place: the text of the shared function does not count its places, so a seam that
		// passes `token` `nil` any number of times matches inline, which passes it `nil` in the shared function, and one
		// that passes `nil` to an argument inline never passes `nil` does not.
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: [
			"@Instantiable(generateDependencyTree: true)\npublic final class S7_Screen: Instantiable {\n\tpublic init(reader: S7_Reader) {\n\t\tself.reader = reader\n\t}\n\n\t@Instantiated let reader: S7_Reader\n}\n",
		])
		let inlineFiles = [
			"S7_Root+SafeDI.swift": "func __safeDI_S7_Reader() -> S7_Reader {\n    let mark = S7_Mark(token: nil, user: user)\n    return S7_Reader(mark: mark)\n}\nlet first = __safeDI_S7_Reader()\nlet second = __safeDI_S7_Reader()",
		]
		#expect(GraphFuzzerOracle.nilArgumentKeysInSharedBuilderFunctions(in: inlineFiles, typeNamePrefix: "S7_", excluding: []) == ["S7_Mark(token:)"])
		let inline = GraphFuzzerToolOutcome.accepted(generatedFiles: inlineFiles, warnings: [])
		func runs(seamFile: String) -> GraphFuzzerToolRuns {
			let seam = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S7_Root+SafeDI.swift": seamFile], warnings: [])
			return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: seam, secondOutcome: seam, inlineOutcome: inline)
		}
		#expect(runs(seamFile: "let first = S7_Mark(token: nil, user: user)\nlet second = S7_Mark(token: nil, user: user)\nlet third = S7_Mark(token: nil, user: user)").nilArgumentFailure == nil)
		#expect(runs(seamFile: "let first = S7_Mark(token: nil, user: user)\nlet second = S7_Mark(token: nil, user: nil)").nilArgumentFailure?.details.prefix { $0 != "\n" } == "`S7_Mark(user:)` is passed `nil` 1 times with the seam and 0 without it.")
	}

	@Test
	func nilArgumentKeysInSharedBuilderFunctions_holdsOnlyFunctionsThatStandForMoreThanOnePlace_whenFunctionsAreReferencedOnceOrMore() {
		// A function referenced once from the root's body stands for one place, and so does one it alone references; one
		// referenced twice, one that references itself again, and one only such a function references, stand for more.
		let file = """
		func __safeDI_once() -> S7_A {
		    let b = __safeDI_onceInner()
		    return S7_A(b: b, x: nil)
		}
		func __safeDI_onceInner() -> S7_B {
		    S7_B(y: nil)
		}
		func __safeDI_twice() -> S7_C {
		    let d = __safeDI_twiceInner()
		    return S7_C(d: d, z: nil)
		}
		func __safeDI_twiceInner() -> S7_D {
		    S7_D(w: nil)
		}
		func __safeDI_loop() -> S7_E {
		    let next = Instantiator<S7_E>(__safeDI_loop)
		    return S7_E(next: next, v: nil)
		}
		let a = __safeDI_once()
		let c = __safeDI_twice()
		let other = __safeDI_twice()
		let e = Instantiator<S7_E>(__safeDI_loop)
		let f = S7_F(u: nil)
		"""
		#expect(GraphFuzzerOracle.nilArgumentKeysInSharedBuilderFunctions(in: ["S7_Root+SafeDI.swift": file], typeNamePrefix: "S7_", excluding: []) == ["S7_C(z:)", "S7_D(w:)", "S7_E(v:)"])
	}

	@Test
	func nilArgumentKeysInSharedBuilderFunctions_holdsAConstructionTwoFunctionsAway_whenASharedFunctionHandsOnTheNilItIsGiven() {
		// The type key's shared function for a subtree takes a received label, one of whose callers passes `nil`; the function
		// hands it on to the function of a child, which constructs with it, so the `nil` reaches a construction two calls away.
		let file = """
		let first = __safeDI_sub(mark: nil, label: label)
		let mark = S7_Mark()
		let second = __safeDI_sub(mark: mark, label: label)
		func __safeDI_sub(mark: S7_Mark?, label: S7_Label) -> S7_Sub {
		    let child = __safeDI_child(label: label, mark: mark)
		    return S7_Sub(mark: mark, child: child)
		}
		func __safeDI_child(label: S7_Label, mark: S7_Mark?) -> S7_Child {
		    let gadget = S7_Gadget(label: label, mark: mark)
		    return S7_Child(gadget: gadget)
		}
		"""
		#expect(GraphFuzzerOracle.nilArgumentKeysInSharedBuilderFunctions(in: ["S7_Root+SafeDI.swift": file], typeNamePrefix: "S7_", excluding: []) == ["S7_Sub(mark:)", "S7_Gadget(mark:)"])
	}

	@Test
	func nilArgumentKeysInSharedBuilderFunctions_holdsAConstructionReadingTheWrappersInstance_whenASharedFunctionTakesALazyCyclesWrapper() {
		// The type key's function for a type a lazy cycle closes on takes the cycle's optional wrapper, which the root passes
		// `nil` and the cycle's closer passes the wrapper; its constructions read the wrapper's instance.
		let file = """
		@Sendable nonisolated func __safeDI_a(tag: SendableLazilyInstantiated<S7_Tag>?) -> S7_A {
		    let reader = S7_Reader(tag: tag?.instance)
		    return S7_A(reader: reader)
		}
		@Sendable nonisolated func __safeDI_c(tag: SendableLazilyInstantiated<S7_Tag>) -> S7_C {
		    let a: S7_A = __safeDI_a(tag: tag)
		    return S7_C(a: a)
		}
		let a: S7_A = __safeDI_a(tag: nil)
		"""
		#expect(GraphFuzzerOracle.nilArgumentKeysInSharedBuilderFunctions(in: ["S7_Root+SafeDI.swift": file], typeNamePrefix: "S7_", excluding: []) == ["S7_Reader(tag:)"])
	}

	@Test
	func nilArgumentCountsThroughBuilderFunctions_countsAConstructionReadingTheWrappersInstance_whenACallPassesTheWrapperNil() {
		let file = """
		@Sendable nonisolated func __safeDI_a(tag: SendableLazilyInstantiated<S7_Tag>?) -> S7_A {
		    let reader = S7_Reader(tag: tag?.instance)
		    return S7_A(reader: reader)
		}
		let a: S7_A = __safeDI_a(tag: nil)
		"""
		#expect(GraphFuzzerOracle.nilArgumentCountsThroughBuilderFunctions(in: ["S7_Root+SafeDI.swift": file], typeNamePrefix: "S7_", excluding: []) == ["S7_Reader(tag:)": 1])
	}

	/// A seam's generated file whose plain enum holds `cases`, each `case <name>(<name>_Values)`, and whose initializer
	/// takes `builderLabel` over it, as a module that does not set `generatePlainDependencyTreeInitializers` generates it:
	/// only the initializer generated code calls, with its labels prefixed.
	private static func holeSeamFile(builderLabel: String, cases: [String]) -> String {
		"""
		extension S8_Feature {
		    @frozen public enum SafeDIScope_S8_Service {
		\(cases.map { "        case \($0)(\($0)_Values)\n\n        public struct \($0)_Values {\n            public let analytics: S8_Analytics\n        }" }.joined(separator: "\n\n"))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_\(builderLabel): @escaping (SafeDIScope_S8_Service) -> any S8_Service) {
		        let service: any S8_Service = __safeDI_\(builderLabel)(.\(cases[0])(SafeDIScope_S8_Service.\(cases[0])_Values(analytics: S8_Analytics())))
		        self.init(service: service)
		    }
		}

		"""
	}

	@Test
	func holeNameStabilityFailure_reportsRenamedCase_whenAddingSecondPlaceRenamesACaseOfTheGraphWithoutIt() {
		// A hand-written caller that switches over a seam's enum names its cases, so adding a place beneath the seam may add a
		// case but must rename none of the graph without it: here the larger graph names its first place's case apart.
		let fixture = GraphFuzzerFixture(seed: 8, swiftFileContent: ["// module: FuzzFeature\n"])
		let withoutPlace = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzFeature/S8_Feature+SafeDI.swift": Self.holeSeamFile(builderLabel: "s8_ServiceBuilder", cases: ["service"])], warnings: [])
		let withPlaceRenamingCase = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzFeature/S8_Feature+SafeDI.swift": Self.holeSeamFile(builderLabel: "s8_ServiceBuilder", cases: ["service_S8_Feature", "secondService"])], warnings: [])

		let runs = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: withPlaceRenamingCase, secondOutcome: withPlaceRenamingCase, withoutSecondHolePlaceOutcome: ("secondService", withoutPlace))

		#expect(runs.holeNameStabilityFailure?.kind == .holeNamesChangeWithSecondPlace)
		#expect(runs.holeNameStabilityFailure?.details.prefix { $0 != "\n" } == "Adding the second place `secondService` removes S8_Feature.SafeDIScope_S8_Service.service.")
	}

	@Test
	func placeLevelsFailure_reportsEachDisagreement_whenTwoBuildsOfATypeBindOtherValuesBeforeAProperty() {
		// A scope enum nested by type holds one level per type, so a type that binds other values before a property on
		// another path is a failure, naming both paths.
		let fixture = GraphFuzzerFixture(seed: 8, swiftFileContent: ["// module: FuzzFeature\n"])
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		let disagreement = "`T` holds [] before `api: any Api` on the path to the place `tBuilder.api` of `Hub`, but [cBuilder: Instantiator<C>] on the path to the place `cBuilder.tBuilder.api`."

		let runs = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome, placeLevelDisagreements: [disagreement])

		#expect(runs.placeLevelsFailure?.kind == .placeLevelsDifferBetweenBuildsOfType)
		#expect(runs.placeLevelsFailure?.details.prefix { $0 != "\n" } == Substring(disagreement))
	}

	@Test
	func placeLevelsFailure_isNil_whenEveryBuildOfATypeBindsTheSameValues() {
		let fixture = GraphFuzzerFixture(seed: 8, swiftFileContent: ["// module: FuzzFeature\n"])
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])

		let runs = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)

		#expect(runs.placeLevelsFailure?.kind == nil)
	}

	@Test
	func holeNameStabilityFailure_reportsRenamedBuilder_whenAddingSecondPlaceRenamesABuilderOfTheGraphWithoutIt() {
		// A builder that adding a second place relabels, which a hand-written caller passes by label.
		let fixture = GraphFuzzerFixture(seed: 8, swiftFileContent: ["// module: FuzzFeature\n"])
		let withoutPlace = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzFeature/S8_Feature+SafeDI.swift": Self.holeSeamFile(builderLabel: "s8_ServiceBuilder", cases: ["service"])], warnings: [])
		let withPlaceRenamingBuilder = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzFeature/S8_Feature+SafeDI.swift": Self.holeSeamFile(builderLabel: "s8_Service_S8_AnyServiceBuilder", cases: ["service"])], warnings: [])

		let runs = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: withPlaceRenamingBuilder, secondOutcome: withPlaceRenamingBuilder, withoutSecondHolePlaceOutcome: ("secondService", withoutPlace))

		#expect(runs.holeNameStabilityFailure?.details.prefix { $0 != "\n" } == "Adding the second place `secondService` removes S8_Feature(s8_ServiceBuilder:).")
	}

	@Test
	func holeNameStabilityFailure_isNil_whenAddingSecondPlaceOnlyAddsACase() {
		// The design's output stability: a new place of a hole type the seam already has adds a case and renames nothing.
		let fixture = GraphFuzzerFixture(seed: 8, swiftFileContent: ["// module: FuzzFeature\n"])
		let withoutPlace = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzFeature/S8_Feature+SafeDI.swift": Self.holeSeamFile(builderLabel: "s8_ServiceBuilder", cases: ["service"])], warnings: [])
		let withPlace = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzFeature/S8_Feature+SafeDI.swift": Self.holeSeamFile(builderLabel: "s8_ServiceBuilder", cases: ["service", "secondService"])], warnings: [])

		#expect(GraphFuzzerOracle.holeBuilderNames(in: ["FuzzFeature/S8_Feature+SafeDI.swift": Self.holeSeamFile(builderLabel: "s8_ServiceBuilder", cases: ["service"])]) == [
			"S8_Feature(s8_ServiceBuilder:)",
			"S8_Feature.SafeDIScope_S8_Service",
			"S8_Feature.SafeDIScope_S8_Service.service",
		])
		#expect(GraphFuzzerToolRuns(fixture: fixture, firstOutcome: withPlace, secondOutcome: withPlace, withoutSecondHolePlaceOutcome: ("secondService", withoutPlace)).holeNameStabilityFailure == nil)
	}

	@Test
	func holeBuilderNames_readsTheSameNames_whenModuleAlsoGeneratesPlainInitializer() {
		// A module that sets `generatePlainDependencyTreeInitializers` generates a plain initializer beside the one generated
		// code calls, and both name the same builders.
		let fileName = "FuzzFeature/S8_Feature+SafeDI.swift"
		let defaultFile = Self.holeSeamFile(builderLabel: "s8_ServiceBuilder", cases: ["service"])
		let plainInitializer = "    public init(s8_ServiceBuilder: @escaping (SafeDIScope_S8_Service) -> any S8_Service) {\n        self.init(__safeDI_s8_ServiceBuilder: s8_ServiceBuilder)\n    }\n\n"
		let optedInFile = defaultFile.replacingOccurrences(of: "    /// Only code SafeDI generates", with: plainInitializer + "    /// Only code SafeDI generates")

		#expect(optedInFile != defaultFile)
		#expect(GraphFuzzerOracle.holeBuilderNames(in: [fileName: optedInFile]) == GraphFuzzerOracle.holeBuilderNames(in: [fileName: defaultFile]))
	}

	@Test
	func holeBuilderNames_readsPublicMockBuildersAndScopes_whenMockTakesBuilderOverEnumOfItsPlaces() {
		// A public mock takes its builders on lines of their own, and a consumer's mock a flat builder typed by the called
		// mock's enum: both are names a hand-written caller spells.
		let mockFile = """
		#if DEBUG
		extension S9_Panel {
		    @frozen public enum SafeDIMockScope_S9_Service {
		        case row_service(row_service_Values)
		        indirect case panel(S9_Panel.SafeDIMockScope_S9_Service)
		    }

		    public static func mock(
		        s9_ServiceBuilder: @escaping (S9_Panel.SafeDIMockScope_S9_Service) -> any S9_Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> S9_Panel {
		        func __safeDI_build() -> S9_Panel {
		            switch scope {
		            case let .row_service(scope): fill(scope)
		            }
		        }
		    }
		}
		#endif
		"""

		#expect(GraphFuzzerOracle.holeBuilderNames(in: ["FuzzFeature/S9_Panel+SafeDIMock.swift": mockFile]) == [
			"S9_Panel(s9_ServiceBuilder:)",
			"S9_Panel.SafeDIMockScope_S9_Service",
			"S9_Panel.SafeDIMockScope_S9_Service.row_service",
			"S9_Panel.SafeDIMockScope_S9_Service.panel",
		])
	}

	@Test
	func tiersWiderThanParameterTypes_reportsTier_whenTierIsWiderThanTypeItsParameterNames() {
		// The ground truth: a tier a seam proved from the wrong declaration names a type narrower than itself, such as
		// a `public` tier taking a type the generator declared `package`. A tier as narrow as the type is sound.
		let unsoundTier = """
		extension S1_ProofSeam {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_proofTheme proofTheme: S1_ProofTheme?) {
		        self.init(__safeDI_proofTheme: proofTheme)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    package convenience init(__safeDI_proofCrate proofCrate: S1_ProofSpace.S1_ProofCrate, __safeDI_proofTheme proofTheme: S1_ProofTheme?) {
		        let proofBadge = S1_ProofBadge(proofTheme: proofTheme)
		        self.init(proofBadge: proofBadge)
		    }
		}

		extension S1_ProofSeam {
		    public enum __safeDI_S1_ProofSeam_0123456789ABCDEF {}
		}
		"""
		let typeAccess: [String: GraphFuzzerGenerator.AccessLevel] = ["S1_ProofTheme": .package, "S1_ProofSpace.S1_ProofCrate": .internal]

		#expect(GraphFuzzerOracle.tiersWiderThanParameterTypes(in: ["S1_ProofSeam+SafeDI.swift": unsoundTier], typeAccess: typeAccess) == [
			"S1_ProofSeam+SafeDI.swift: `S1_ProofSeam`’s `public` initializer takes `proofTheme: S1_ProofTheme?`, but `S1_ProofTheme` is `package`.",
			"S1_ProofSeam+SafeDI.swift: `S1_ProofSeam`’s `package` initializer takes `proofCrate: S1_ProofSpace.S1_ProofCrate`, but `S1_ProofSpace.S1_ProofCrate` is `internal`.",
		])
		#expect(GraphFuzzerOracle.tiersWiderThanParameterTypes(in: ["S1_ProofSeam+SafeDI.swift": unsoundTier], typeAccess: ["S1_ProofTheme": .package, "S1_ProofSpace.S1_ProofCrate": .package]) == [
			"S1_ProofSeam+SafeDI.swift: `S1_ProofSeam`’s `public` initializer takes `proofTheme: S1_ProofTheme?`, but `S1_ProofTheme` is `package`.",
		])
	}

	@Test(arguments: [
		// The provider's declaration, where the error is reported.
		"/F/Host.swift:3:2: error: `Host` provides `theme: Theme`, but the `public` initializer SafeDI generated for `Screen` in module `Feature`, the narrowest one module `App` can call, does not take it.",
		// The provider's file cannot be read, so the error is reported where the module refers to the call, naming the
		// provider's module.
		"/F/Root.swift:11:5: error: `Host` in module `Base` provides `theme: Theme`, but the `public` initializer SafeDI generated for `Screen` in module `Feature`, the narrowest one module `App` can call, does not take it.",
		// A fill of a public mock's place holds the value, which the called mock hands it.
		"/F/Screen.swift:12:5: error: `Panel`’s mock hands this fill `theme: Theme`, but the `public` mock SafeDI generated for `Service` in module `Impl`, the narrowest one module `App` can call, does not take it.",
		// The caller is an outer seam that takes the value from its own callers, as R5 says of a pass-through.
		"/F/Outer.swift:3:1: error: `Outer` takes `theme: Theme?` from its callers, but the `public` initializer SafeDI generated for `Service` in module `Base`, the narrowest one module `Mid` can call, does not take it: `Service` takes `theme` only on its `package` initializer, so this call would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline.",
	])
	func omittedValueLabel_readsLabel_whenErrorNamesProviderOrOuterSeamTakingIt(error: String) {
		// The omitted-value oracle recognizes an error that a caller holds a value its tier omits in each of its forms.
		#expect(GraphFuzzerOracle.isOmittedValueError(Substring(error)))
		#expect(GraphFuzzerOracle.omittedValueLabel(of: Substring(error)) == "theme")
	}

	@Test
	func omittedValueFailure_reportsOmission_whenCallOmitsParameterInlineBuildPassesAValue() {
		// A caller in another module calls the public tier, which omits `proofTheme`: inline, its module passes
		// `S1_ProofBadge` the value it holds, so the tool must report it; inline passing `nil`, the omission is sound.
		let runs = Self.omittedValueRuns(seamOutcome: .accepted(generatedFiles: Self.omittingCall, warnings: []), inlinePassing: "proofTheme")
		#expect(runs.omittedValueFailure?.kind == .seamTierOmitsValueInlinePasses)
		#expect(runs.omittedValueFailure?.details.prefix { $0 != "\n" } == "FuzzOther/S1_ProofOtherRoot+SafeDI.swift calls `S1_ProofSeam` without `proofTheme`, which the inline build of FuzzOther passes a receiver a value for, and the tool reports no error.")
		#expect(Self.omittedValueRuns(seamOutcome: .accepted(generatedFiles: Self.omittingCall, warnings: []), inlinePassing: "nil").omittedValueFailure == nil)
	}

	@Test
	func omittedValueFailure_reportsError_whenToolReportsOmittedValueInlineBuildPassesNil() {
		// The tool reports that the caller holds `proofTheme`, which its tier omits: inline, its module passes
		// `S1_ProofBadge` `nil`, so no receiver would lose a value; inline passing the value, the error is right.
		let error = GraphFuzzerToolOutcome.rejected(diagnostics: "/x/<fixture-directory>/other/Sources/FuzzOther/S1_ProofOtherHost.swift:3:2: error: `S1_ProofOtherHost` provides `proofTheme: S1_ProofTheme`, but the `public` initializer SafeDI generated for `S1_ProofSeam` in module `FuzzFeature`, the narrowest one module `FuzzOther` can call, does not take it.")
		#expect(Self.omittedValueRuns(seamOutcome: error, inlinePassing: "nil").omittedValueFailure?.kind == .seamTierOmitsProvidedValueReportedWhereInlinePassesNil)
		#expect(Self.omittedValueRuns(seamOutcome: error, inlinePassing: "proofTheme").omittedValueFailure == nil)
		// A split graph's omitted-value error is a seam's own, which this oracle judges, not an inlined validation's.
		#expect(Self.omittedValueRuns(seamOutcome: error, inlinePassing: "proofTheme").differentialFailure == nil)
	}

	@Test
	func omittedValueFailure_reportsNothing_whenOuterSeamThatTakesValueFromItsCallersReportsOmission() {
		// An outer seam that takes `proofTheme` from its callers reports that its call omits it whatever its callers hold:
		// the oracle takes it for a seam's own error, and does not judge it by what this graph's inline build passes.
		let error = GraphFuzzerToolOutcome.rejected(diagnostics: "/x/<fixture-directory>/other/Sources/FuzzOther/S1_ProofOtherHost.swift:3:1: error: `S1_ProofOtherHost` takes `proofTheme: S1_ProofTheme?` from its callers, but the `public` initializer SafeDI generated for `S1_ProofSeam` in module `FuzzFeature`, the narrowest one module `FuzzOther` can call, does not take it.")
		#expect(Self.omittedValueRuns(seamOutcome: error, inlinePassing: "nil").omittedValueFailure == nil)
		#expect(Self.omittedValueRuns(seamOutcome: error, inlinePassing: "nil").differentialFailure == nil)
	}

	/// The runs of a graph split across modules whose `S1_ProofBadge`, in the seam's tree, receives `proofTheme` only
	/// if available, with the inline build of the caller in another package passing it `argument`.
	private static func omittedValueRuns(seamOutcome: GraphFuzzerToolOutcome, inlinePassing argument: String) -> GraphFuzzerToolRuns {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"// module: FuzzFeature\n\n@Instantiable\npublic final class S1_ProofBadge: Instantiable {\n\tpackage init(proofTheme: S1_ProofTheme?) {\n\t\tself.proofTheme = proofTheme\n\t}\n\n\t@Received(onlyIfAvailable: true) let proofTheme: S1_ProofTheme?\n}\n",
		])
		let inline = GraphFuzzerToolOutcome.accepted(generatedFiles: [
			"FuzzOther/S1_ProofOtherRoot+SafeDI.swift": "extension S1_ProofOtherRoot {\n    public convenience init() {\n        let proofBadge = S1_ProofBadge(proofTheme: \(argument))\n        self.init(proofSeam: S1_ProofSeam(proofBadge: proofBadge))\n    }\n}\n",
		], warnings: [])
		return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: seamOutcome, secondOutcome: seamOutcome, inlineOutcome: inline)
	}

	/// A seam's tiers and a call of its public tier from a caller in another package.
	private static let omittingCall = [
		"FuzzFeature/S1_ProofSeam+SafeDI.swift": "extension S1_ProofSeam {\n    public convenience init() {\n        self.init(__safeDI_proofTheme: nil)\n    }\n\n    package convenience init(__safeDI_proofTheme proofTheme: S1_ProofTheme?) {\n        self.init(proofBadge: S1_ProofBadge(proofTheme: proofTheme))\n    }\n}\n\nextension S1_ProofSeam {\n    public enum __safeDI_S1_ProofSeam_0123456789ABCDEF {}\n}\n",
		"FuzzOther/S1_ProofOtherRoot+SafeDI.swift": "extension S1_ProofOtherRoot {\n    public convenience init() {\n        func __safeDI_proofSeam() -> S1_ProofSeam {\n            _ = S1_ProofSeam.__safeDI_S1_ProofSeam_0123456789ABCDEF.self\n            return S1_ProofSeam()\n        }\n        self.init(proofSeam: __safeDI_proofSeam())\n    }\n}\n",
	]

	@Test
	func seamParameterKinds_tellParameterReceivedOnlyIfAvailableFromRequiredOne_byReceivesInSeamsTree() {
		// A seam's generated initializer spells `x: X?` alike whether `x` is received only if available or required, so the
		// oracles read the kind from the graph: the seam's own receive as declared, and a pass-through by every receive of
		// its label in the seam's tree – followed into a type declared in a namespace, and not into a `mockOnly` fake or a
		// type outside the tree. A label the tree receives both ways is neither.
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"@Instantiable(generateDependencyTree: true)\npublic final class Screen: Instantiable {\n\t@Received(onlyIfAvailable: true) let session: Session?\n\t@Received let user: User?\n\t@Instantiated let detail: Detail\n\t@Instantiated let shelf: Space.Shelf\n}\n",
			"@Instantiable\npublic final class Detail: Instantiable {\n\t@Received(onlyIfAvailable: true) let logger: Logger?\n\t@Received let token: Token?\n\t@Received(onlyIfAvailable: true) let theme: Theme?\n\t@Received(fulfilledByDependencyNamed: \"mixed\", ofType: Mixed.self, onlyIfAvailable: true) let alias: Mixed?\n\t@Received let mixed: Mixed?\n}\n\n@Instantiable(mockOnly: true)\nstruct Fake {\n\t@Received let theme: Theme\n}\n",
			"public enum Space {}\n\nextension Space {\n\t@Instantiable\n\tpublic final class Shelf: Instantiable {\n\t\t@Received(onlyIfAvailable: true) let crate: Crate?\n\t}\n}\n",
			"@Instantiable\npublic final class Outside: Instantiable {\n\t@Received let logger: Logger\n}\n",
		])
		let kinds = GraphFuzzerSeamParameterKinds(fixture: fixture)
		let labels = ["session", "user", "logger", "token", "theme", "mixed", "crate"]
		#expect(labels.filter { kinds.isOnlyIfAvailable(label: $0, ofSeam: "Screen") } == ["session", "logger", "theme", "crate"])
		#expect(labels.filter { kinds.isRequiredPassThrough(label: $0, type: "T?", ofSeam: "Screen") } == ["token"])
		#expect(kinds.isRequiredPassThrough(label: "mixed", type: "Mixed", ofSeam: "Screen"))
		#expect(!kinds.isRequiredPassThrough(label: "user", type: "User", ofSeam: "Screen"))
	}

	@Test
	func seamRejectedWhereInlineAcceptsFailure_reportsSeed_whenAliasDrawsSeamIsRejectedWhereInlineAccepts() {
		// The alias draw's seam binds its alias from a parameter as inline binds it, and has no shape another seam rule
		// rejects, so any error about it in a graph inline accepts is a defect; another seam's error, or an error inline
		// reports too, is not.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 0, features: [.generateDependencyTree])
		let aliasSeam = "\(fixture.typeNamePrefix)AliasSeam"
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		let collision = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/Screen.swift:1:1: error: SafeDI cannot generate the dependency tree of `\(aliasSeam)`: its tree receives `x` as `x: X` on `A` and `x: Y?` on `B`.")
		let otherSeamsCollision = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/Screen.swift:1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `x` as `x: X` on `A` and `x: Y?` on `B`.")
		#expect(GraphFuzzerToolRuns(fixture: fixture, firstOutcome: collision, secondOutcome: collision, inlineOutcome: accepted).seamRejectedWhereInlineAcceptsFailure?.kind == .seamRejectedWhereInlineAccepts)
		#expect(GraphFuzzerToolRuns(fixture: fixture, firstOutcome: otherSeamsCollision, secondOutcome: otherSeamsCollision, inlineOutcome: accepted).seamRejectedWhereInlineAcceptsFailure == nil)
		#expect(GraphFuzzerToolRuns(fixture: fixture, firstOutcome: collision, secondOutcome: collision, inlineOutcome: collision).seamRejectedWhereInlineAcceptsFailure == nil)
	}

	@Test(arguments: ValueComparisonUnderTest.allCases)
	func finding_isKnownIssue_whenEveryValueDifferenceMatchesAValueSignature(comparison: ValueComparisonUnderTest) {
		let knownIssue = Self.valueDivergenceKnownIssue(of: comparison)
		let failure = GraphFuzzerFailure(seed: 430, kind: comparison.failureKind, details: Self.documentedDifference + "\nFeature path:\n…", valueDifferences: [Self.documentedDifference])

		#expect(GraphFuzzerFinding(failure: failure, knownIssue: knownIssue) == .knownIssue(knownIssue, failure))
	}

	@Test(arguments: ValueComparisonUnderTest.allCases)
	func finding_isFailure_whenValueFailureHoldsDifferenceNoValueSignatureMatchesBesideOneThatMatches(comparison: ValueComparisonUnderTest) {
		// A documented divergence beside an undocumented difference is a new failure: the shape's signature documents
		// the first difference, not the graph.
		let knownIssue = Self.valueDivergenceKnownIssue(of: comparison)
		let failure = GraphFuzzerFailure(seed: 430, kind: comparison.failureKind, details: Self.documentedDifference + "\n" + Self.undocumentedDifference + "\nFeature path:\n…", valueDifferences: [Self.documentedDifference, Self.undocumentedDifference])

		#expect(GraphFuzzerFinding(failure: failure, knownIssue: knownIssue) == .failure(failure))
	}

	@Test(arguments: ValueComparisonUnderTest.allCases)
	func finding_isFailure_whenKnownValueFailureIsFollowedByFailureTheKnownIssueDoesNotDocument(comparison: ValueComparisonUnderTest) {
		// A known value failure masks nothing: the failures after it in the oracle's chain are reported as they would
		// be alone. A place-level failure, unlike a renamed graph's difference, is masked by a known failure of most other
		// kinds, so it shows that the value failure is one that masks nothing.
		let knownIssue = Self.valueDivergenceKnownIssue(of: comparison)
		let known = GraphFuzzerFailure(seed: 430, kind: comparison.failureKind, details: Self.documentedDifference, valueDifferences: [Self.documentedDifference])
		let placeLevels = GraphFuzzerFailure(seed: 430, kind: .placeLevelsDifferBetweenBuildsOfType, details: "`Impl` binds `id` before `service` in one build and after it in another.")

		#expect(GraphFuzzerFinding(failure: known, laterFailures: [placeLevels], knownIssue: knownIssue) == .failure(placeLevels))
		#expect(GraphFuzzerFinding(failure: known, laterFailures: [], knownIssue: knownIssue) == .knownIssue(knownIssue, known))
	}

	@Test(arguments: ValueComparisonUnderTest.allCases)
	func knownIssue_matchesNoValueFailureOfTheOtherComparison_whenEveryDifferenceMatchesItsSignature(comparison: ValueComparisonUnderTest) {
		// A difference from a hole's visible build and one from the inline build are separate failures, so a signature of
		// one documents nothing of the other, though their descriptions match.
		let knownIssue = Self.valueDivergenceKnownIssue(of: comparison)
		let failure = GraphFuzzerFailure(seed: 430, kind: comparison.other.failureKind, details: Self.documentedDifference, valueDifferences: [Self.documentedDifference])

		#expect(!knownIssue.matches(failure))
	}

	@Test
	func finding_isFailure_whenKnownValueOracleRejectionIsFollowedByRenameFailureTheKnownIssueDoesNotDocument() {
		// A known rejection of the value-oracle fixture masks nothing: the comparison does not run, and the wrapper and
		// rename oracles judge the drawn graph, so a renamed graph that gives other results is reported as it would be alone.
		let knownIssue = Self.valueOracleRejectionKnownIssue
		let rejection = Self.valueOracleRejection(errorLines: [Self.hiddenInChainError])
		let renamed = GraphFuzzerFailure(seed: 47, kind: .renamedGraphDiffers, details: "Reversing its labels changes its generated mock code, in S47_Root0+SafeDIMock.swift.\nThis graph:\n…")

		#expect(GraphFuzzerFinding(failure: rejection, laterFailures: [renamed], knownIssue: knownIssue) == .failure(renamed))
		#expect(GraphFuzzerFinding(failure: rejection, laterFailures: [], knownIssue: knownIssue) == .knownIssue(knownIssue, rejection))
	}

	@Test
	func finding_isKnownIssue_whenKnownIssueDocumentsTheValueOracleRejectionAndTheRenameFailure() {
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "A root's mock rejects a receive of a hidden label, in a graph whose mock code changes under a renaming",
			signatures: [.valueOracleFixtureRejected(containing: "is hidden in chain"), .renamedGraphDiffers(.mockCode)],
			seeds: [47],
		)
		let rejection = Self.valueOracleRejection(errorLines: [Self.hiddenInChainError])
		let renamed = GraphFuzzerFailure(seed: 47, kind: .renamedGraphDiffers, details: "Reversing its labels changes its generated mock code, in S47_Root0+SafeDIMock.swift.\nThis graph:\n…", renamedGraphDifference: .mockCode)

		#expect(GraphFuzzerFinding(failure: rejection, laterFailures: [renamed], knownIssue: knownIssue) == .knownIssue(knownIssue, rejection))
	}

	@Test
	func knownIssue_matchesValueOracleRejection_onlyWhenEveryErrorLineMatchesASignature() {
		// The first error is the documented one; a second error of another shape is a new failure, not a known one.
		let knownIssue = Self.valueOracleRejectionKnownIssue
		let unfulfillableError = "/F/S47_T2.swift:5:2: error: @Received property `t4: S47_T4` is not @Instantiated or @Forwarded in chain: S47_Root0 -> S47_T2"

		#expect(knownIssue.matches(Self.valueOracleRejection(errorLines: [Self.hiddenInChainError, Self.hiddenInChainError])))
		#expect(!knownIssue.matches(Self.valueOracleRejection(errorLines: [Self.hiddenInChainError, unfulfillableError])))
		#expect(!knownIssue.matches(Self.valueOracleRejection(errorLines: [unfulfillableError, Self.hiddenInChainError])))
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The value comparator compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueFailures_reportsOtherValues_whenSeamBuildPassesNilWhereInlineBuildPassesValue() async throws {
		// The seam build of a smoke graph, with the root's call of a tier passing `nil` for a parameter received only if
		// available where it passed a value, builds other values than the inline build: the receiver beneath gets `nil`.
		let (runs, seamFiles, warnings) = try await Self.valueProbeRuns()
		let perturbed = try #require(Self.passingNil(forAnOnlyIfAvailableParameterIn: seamFiles, of: runs.fixture), "No smoke seam graph passes a value for a parameter received only if available")
		let perturbedRuns = GraphFuzzerToolRuns(fixture: runs.fixture, firstOutcome: .accepted(generatedFiles: perturbed.files, warnings: warnings), secondOutcome: .accepted(generatedFiles: perturbed.files, warnings: warnings), inlineOutcome: runs.inlineOutcome)

		let failures = try await GraphFuzzerOracle.valueFailures(of: [perturbedRuns])

		let failure = try #require(failures[runs.fixture.seed]?.first)
		#expect(failure.kind == .seamBuildsOtherValuesThanInline, Comment(rawValue: failure.details))
		// Seed 16's receiver beneath the spelling's seam gets `nil` where inline it gets the value its host forwards.
		#expect(failure.valueDifferences.first == "probe `S16_Root0().spellHostBuilder.instantiate(S16_SpellOuter.Item())` at <1> S16_SpellHost > spellSeam > spellChild > \(perturbed.label):\n  feature:     \(perturbed.label): nil\n  known right: \(perturbed.label): <2> S16_SpellOuter.Item (seen, first at <1> S16_SpellHost > spelled)")
		#expect(failure.valueDifferences.count == 1, "\(failure.valueDifferences)")
		#expect(failure.details.hasPrefix(failure.valueDifferences.joined(separator: "\n") + "\n"))
		#expect(try await GraphFuzzerOracle.valueFailures(of: [runs]).isEmpty)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The value comparator compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueFailures_reportsComparatorCouldNotDescribeGraph_whenSeamBuildDoesNotCompile() async throws {
		let (runs, seamFiles, warnings) = try await Self.valueProbeRuns()
		let fileName = try #require(seamFiles.keys.sorted().first)
		var brokenFiles = seamFiles
		brokenFiles[fileName] = (seamFiles[fileName] ?? "") + "\nfunc broken() -> Int { \"not an integer\" }\n"
		let brokenRuns = GraphFuzzerToolRuns(fixture: runs.fixture, firstOutcome: .accepted(generatedFiles: brokenFiles, warnings: warnings), secondOutcome: .accepted(generatedFiles: brokenFiles, warnings: warnings), inlineOutcome: runs.inlineOutcome)

		let failures = try await GraphFuzzerOracle.valueFailures(of: [brokenRuns])

		let failure = try #require(failures[runs.fixture.seed]?.first)
		#expect(failure.kind == .valueComparatorCouldNotDescribeGraph)
		#expect(failure.details.contains("not an integer"))
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The value comparator compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueFailures_reportsOtherValues_whenFillReadsAnotherLevelOfACycleThanItsVisibleBuild() async throws {
		// Seed 1637, beyond the seam corpus, draws `addingCycleParameterShapes`' cycle: `CycleB`, built inside the function `CycleSeam`'s
		// `cycle1ABuilder` closes on, declares `cycle6Tag` again beside its hole, whose fill, `CycleImpl`, reads it, so each
		// level's fill receives that level's `CycleB`'s tag, as the visible build's `CycleImpl` does. A seam that handed the
		// fill the tag the function's reader holds instead – the level above's – builds other values than the visible build,
		// which the value oracle reports without an oracle of its own.
		let (runs, perturbedFiles, warnings) = try await Self.cycleFillReadingLevelAboveRuns()
		let perturbedRuns = GraphFuzzerToolRuns(fixture: runs.fixture, firstOutcome: .accepted(generatedFiles: perturbedFiles, warnings: warnings), secondOutcome: .accepted(generatedFiles: perturbedFiles, warnings: warnings), visibleOutcome: runs.visibleOutcome)

		let failure = try #require(try await GraphFuzzerOracle.valueFailures(of: [perturbedRuns])[runs.fixture.seed]?.first)

		#expect(failure.kind == .holeBuildsOtherValuesThanVisibleBuild, Comment(rawValue: failure.details))
		#expect(failure.valueDifferences.allSatisfy { $0.contains("cycle0Service") }, "\(failure.valueDifferences)")
		#expect(try await GraphFuzzerOracle.valueFailures(of: [runs]).isEmpty)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The value comparator compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func results_reportInlineDifference_whenKnownIssueDocumentsOnlyTheFillsDifferenceFromItsVisibleBuild() async throws {
		// Seed 1637's seam, with its fill handed the tag of the level above, builds other values than its visible build and
		// than its inline build. A known issue that documents the difference from the visible build documents nothing about
		// the inline build, so the inline build's difference is the finding: a known value failure masks no later failure.
		let (runs, perturbedFiles, warnings) = try await Self.cycleFillReadingLevelAboveRuns()
		let perturbedRuns = GraphFuzzerToolRuns(fixture: runs.fixture, firstOutcome: .accepted(generatedFiles: perturbedFiles, warnings: warnings), secondOutcome: .accepted(generatedFiles: perturbedFiles, warnings: warnings), inlineOutcome: runs.inlineOutcome, visibleOutcome: runs.visibleOutcome)
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "A fill reads the tag of the level above its own",
			signatures: [.holeBuildsOtherValuesThanVisibleBuild(containing: "cycle0Service")],
			seeds: [runs.fixture.seed],
		)

		let result = try #require(try await GraphFuzzerOracle.results(of: [perturbedRuns]).first)

		let failure = try #require(result.failure)
		#expect(failure.kind == .holeBuildsOtherValuesThanVisibleBuild, Comment(rawValue: failure.details))
		let inlineFailure = try #require(result.laterFailures.first { $0.kind == .seamBuildsOtherValuesThanInline }, "\(result.laterFailures.map(\.kind))")
		#expect(inlineFailure.valueDifferences.allSatisfy { $0.contains("cycle0Service") }, "\(inlineFailure.valueDifferences)")
		#expect(GraphFuzzerFinding(failure: failure, laterFailures: result.laterFailures, knownIssue: knownIssue) == .failure(inlineFailure))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_includeAcceptedAndRejectedGraphs_whenRunThroughTool() async throws {
		let results = try await smokeResults.value
		let acceptedCount = results.count(where: { $0.isAccepted && $0.failure == nil })
		let rejectedCount = results.count(where: { !$0.isAccepted && $0.failure == nil })
		// Enough of both that a generator change which makes nearly every graph valid, or nearly every graph
		// invalid, fails here rather than quietly testing less.
		#expect(acceptedCount >= Self.smokeSeeds.count / 4, "Accepted \(acceptedCount) of \(Self.smokeSeeds.count) graphs")
		#expect(rejectedCount >= Self.smokeSeeds.count / 4, "Rejected \(rejectedCount) of \(Self.smokeSeeds.count) graphs")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_judgeConfigurationStorage_inGraphsTheToolAccepts() async throws {
		// The configuration storage oracle judges each configuration a graph generates, so a change that stops it finding
		// them fails here rather than quietly judging nothing.
		let judgedCount = try await smokeResults.value.count { result in
			guard case let .accepted(generatedFiles, _) = result.outcome else { return false }
			return GraphFuzzerConfigurationStorage.configurationCount(in: generatedFiles) > 0
		}
		#expect(judgedCount >= 10, "Judged \(judgedCount) of \(Self.smokeSeeds.count) graphs")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_judgeQuerySuppliers_inGraphsTheToolAccepts() async throws {
		// The query oracle compares the suppliers `query graph` exports with the generated code of each accepted graph in
		// one module, so a change that stops it exporting or reading them fails here rather than quietly judging nothing.
		let judgedCount = try await smokeResults.value.count(where: \.isJudgedByQueryOracle)
		#expect(judgedCount >= 10, "Judged \(judgedCount) of \(Self.smokeSeeds.count) graphs")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func queryGraph_marksDependenciesGenerateReports_inTenBaseCorpusGraphsWithPartialTrees() async throws {
		// The smoke batch holds too few graphs whose trees `query graph` builds around dependencies that cannot be
		// fulfilled for a floor, so this judges the first base corpus graphs the tool rejects as the marks oracle does,
		// with one run of the tool each. Only an export with partial trees counts, so a change that stops `query graph`
		// building them fails here rather than quietly judging nothing.
		//
		// What the marks and deletion oracles add to a long run, measured in a debug build on one core over base corpus
		// seeds 0..<1250, a shard: 221 seconds (the rejected graphs’ exports 69, the runs with missing types declared 8,
		// the two deletions with their exports 144), where one `generate` run of each of those graphs takes 277.
		var partialSeeds = [UInt64]()
		for seed in UInt64(0)..<120 {
			guard let marks = try await GraphFuzzerQueryJudgment.marks(of: GraphFuzzerGenerator.fixture(forSeed: seed)) else { continue }
			#expect(marks.problems == [], "Seed \(seed)")
			if marks.isPartial {
				partialSeeds.append(seed)
			}
		}
		#expect(partialSeeds.count >= 10, "Judged partial trees of seeds \(partialSeeds)")
	}

	@Test(arguments: [70, 79, 293, 335, 485, 896, 1_101, 1_342, 1_345, 1_354, 1_419] as [UInt64])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func queryGraph_marksReceivesGenerateReportsOnceMissingTypesAreDeclared_inBaseCorpusGraphThatHoldsBoth(seed: UInt64) async throws {
		// A graph that instantiates a type no declaration fulfills and receives a value nothing provides is rare, so the
		// marks oracle's checks against the graph with its missing types declared have named seeds: each further mark is
		// an error `generate` reports of that graph, and each error it reports of that graph is at a mark. Each seed must
		// still run the graph so and agree with it. With the receives the second build reports left unmarked, every one
		// of these seeds fails.
		let marks = try #require(await GraphFuzzerQueryJudgment.marks(of: GraphFuzzerGenerator.fixture(forSeed: seed)))
		#expect(marks.isPartial)
		#expect(marks.ranWithMissingTypesDeclared)
		#expect(marks.problems == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func queryGraph_handsEveryOtherReceiveItsValue_whenDeclarationIsDeletedFromTenBaseCorpusGraphs() async throws {
		// The deletion oracle exports a graph again without one type's declaration, and without one property that provides
		// a value, and requires every receive that read neither to keep its provenance. This judges the first base corpus
		// graphs so, with no run of the tool, so a change that stops it finding a declaration to delete, or a deletion that
		// leaves partial trees, fails here rather than quietly judging nothing.
		var seedsLeftWithUnfulfilledDependency = [UInt64]()
		var seedsLeftWithUnfulfilledReceive = [UInt64]()
		for seed in UInt64(0)..<60 {
			let deletions = try await GraphFuzzerQueryJudgment.deletions(of: GraphFuzzerGenerator.fixture(forSeed: seed))
			#expect(deletions.problems == [], "Seed \(seed)")
			if deletions.declarationLeavesDependencyUnfulfilled {
				seedsLeftWithUnfulfilledDependency.append(seed)
			}
			if deletions.propertyLeavesPartialTrees {
				seedsLeftWithUnfulfilledReceive.append(seed)
			}
		}
		#expect(seedsLeftWithUnfulfilledDependency.count >= 10, "Deleted a declaration a reached dependency requires from seeds \(seedsLeftWithUnfulfilledDependency)")
		#expect(seedsLeftWithUnfulfilledReceive.count >= 10, "Deleted a property a reached receive requires from seeds \(seedsLeftWithUnfulfilledReceive)")
	}

	@Test(arguments: [2, 25, 33, 35, 39, 77, 83, 114, 121, 146, 164, 170] as [UInt64])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func queryGraph_namesMarkedReceiveOfDeletedProperty_inBaseCorpusGraphWithReceiveBeneathIt(seed: UInt64) async throws {
		// A receive beneath a marked receive of the deleted property, whose value names the receive above, is in about one
		// base corpus graph in twelve, so those graphs have named seeds: each must still hold such a receive, which the
		// oracle judges.
		let deletions = try await GraphFuzzerQueryJudgment.deletions(of: GraphFuzzerGenerator.fixture(forSeed: seed))
		#expect(deletions.propertyLeavesPartialTrees)
		#expect(deletions.propertyLeavesReceiveBeneathMarkedReceive)
		#expect(deletions.problems == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func seamSmokeSeeds_judgeGeneratedOnlyInitializerDefaults_inGraphsTheToolAccepts() async throws {
		// The oracle judges each initializer only generated code calls, so a change that stops it finding them fails here
		// rather than quietly judging nothing.
		let judgedCount = try await seamSmokeResults.value.count { result in
			guard case let .accepted(generatedFiles, _) = result.outcome else { return false }
			return GraphFuzzerGeneratedOnlyInitializerDefaults.initializerCount(in: generatedFiles) > 0
		}
		#expect(judgedCount >= 10, "Judged \(judgedCount) of \(Self.seamSmokeSeeds.count) graphs")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_applyRemedies_inGraphsTheToolRejects() async throws {
		// The remedy oracle judges rejected graphs, so a change that stops it reading the tool's errors, or stops it applying
		// what they state, fails here rather than quietly judging nothing.
		let remedyKinds = try await Set(smokeResults.value.flatMap { $0.remedyRuns.map(\.remedy.kind) })
		#expect(remedyKinds.sorted() == Self.smokeRemedyKinds)
	}

	// MARK: Known issues

	@Test
	func knownIssues_listEachSeedOnceInIncreasingOrder_belowCorpusSeedCount() {
		#expect(Self.knownIssueListProblems() == [])
	}

	@Test
	func seamKnownIssues_listEachSeedOnceInIncreasingOrder_belowSeamCorpusSeedCount() {
		#expect(Self.knownIssueListProblems(Self.seamKnownIssues, corpusSeedCount: Self.seamCorpusSeedCount) == [])
		// A seed left out of the inherited shapes must be one of theirs, or the entry filters nothing.
		#expect(Self.seamCorpusSeedsOfOtherShapes.subtracting(Self.knownIssuesBesideReportedIssueShapes.flatMap(\.seeds)) == [])
		// A seed added to an inherited shape must name a shape, and be one its list lacks, or the entry adds nothing.
		#expect(Set(Self.seamCorpusSeedsAddedToInheritedShapes.keys).subtracting(Self.knownIssuesBesideReportedIssueShapes.map(\.reason)) == [])
		#expect(Set(Self.seamCorpusSeedsAddedToInheritedShapes.values.joined()).intersection(Self.knownIssuesBesideReportedIssueShapes.flatMap(\.seeds)) == [])
	}

	@Test
	func knownIssueListProblems_reportEachProblem_whenListIsMalformed() {
		let knownIssues = [
			GraphFuzzerKnownIssue(reason: "Unordered", signatures: [.compilerCrashInGeneratedMock], seeds: [20, 10]),
			GraphFuzzerKnownIssue(reason: "Repeated and out of range", signatures: [.compilerCrashInGeneratedMock], seeds: [10, 5_000]),
			GraphFuzzerKnownIssue(reason: "Unsigned", signatures: [], seeds: [30]),
		]

		#expect(Self.knownIssueListProblems(knownIssues) == [
			"The seeds of \"Unordered\" are not in increasing order.",
			"Seed 10 is listed as a known issue more than once.",
			"Seed 5000 is a known issue outside the corpus, seeds 0..<5000.",
			"The known issue \"Unsigned\" lists no seeds or no signatures.",
		])
	}

	@Test
	func finding_isFailure_whenKnownIssueSeedFailsAnotherWay() {
		let knownIssue = Self.compilerErrorKnownIssue
		let failure = GraphFuzzerFailure(seed: knownIssue.seeds[0], kind: .runsDiffer, details: "First run: …")

		let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssue)

		#expect(finding == .failure(failure))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "failure \(knownIssue.seeds[0]) two runs of the tool differ")
	}

	@Test(arguments: [GraphFuzzerFailure.Kind.seamRetainsWhatInlineFrees, .publicMockRetainsWhatKnownRightFrees])
	func finding_isFailure_whenKnownNonValueFailureIsFollowedByRetentionFailureTheKnownIssueDoesNotDocument(kind: GraphFuzzerFailure.Kind) {
		// No known failure hides a leak: the retention oracle judges last, and what a graph keeps alive does not depend on
		// how its generated code fails to compile or changes under a renaming.
		let knownIssue = Self.compilerErrorKnownIssue
		let compilerError = GraphFuzzerFailure(seed: knownIssue.seeds[0], kind: .generatedCodeDoesNotCompile, details: "Root+SafeDI.swift:3:5: error: invalid redeclaration of 'value'")
		let retention = GraphFuzzerFailure(seed: knownIssue.seeds[0], kind: kind, details: "probe `S84_Root()` keeps S84_Navigator alive holding detailBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path")

		#expect(GraphFuzzerFinding(failure: compilerError, laterFailures: [retention], knownIssue: knownIssue) == .failure(retention))
	}

	@Test
	func finding_reportsLevelFunctionKeepsValues_whenEarlierKnownFailureListsTheSeed() {
		// No known failure hides a level's values a kept closure holds: what a graph keeps alive does not depend on how its
		// generated code fails to compile, and no known issue documents this check's findings.
		let knownIssue = Self.compilerErrorKnownIssue
		let compilerError = GraphFuzzerFailure(seed: knownIssue.seeds[0], kind: .generatedCodeDoesNotCompile, details: "Root+SafeDI.swift:3:5: error: invalid redeclaration of 'value'")
		let captures = GraphFuzzerFailure(seed: knownIssue.seeds[0], kind: .levelFunctionKeepsValues, details: "App.swift:2: a closure or local function inside member `detailBuilder` of level function `__safeDI_apiBuilder_Home` refers to `values`, which holds a level's values, so what it builds keeps them alive")

		#expect(GraphFuzzerFinding(failure: compilerError, laterFailures: [captures], knownIssue: knownIssue) == .failure(captures))
	}

	@Test
	func finding_reportsPublicMockValueDifference_whenEarlierKnownFailureListsTheSeed() {
		// No known failure hides a value a public mock builds other than its known-right path does: the public mock corpus’s
		// value oracle is the only judge of the values a generated call of a public mock hands its builders, and what a graph
		// builds does not depend on how its generated code fails to compile.
		let knownIssue = Self.compilerErrorKnownIssue
		let compilerError = GraphFuzzerFailure(seed: knownIssue.seeds[0], kind: .generatedCodeDoesNotCompile, details: "Root+SafeDI.swift:3:5: error: invalid redeclaration of 'value'")
		let values = GraphFuzzerFailure(seed: knownIssue.seeds[0], kind: .publicMockBuildsOtherValuesThanKnownRight, details: "probe `S84_App.mock()`: S84_Token 1 on the feature path, 2 on the known-right path", valueDifferences: ["probe `S84_App.mock()`: S84_Token 1 on the feature path, 2 on the known-right path"])

		#expect(GraphFuzzerFinding(failure: compilerError, laterFailures: [values], knownIssue: knownIssue) == .failure(values))
	}

	@Test
	func finding_isFailure_whenKnownRenamedGraphDifferenceIsFollowedByRetentionFailureTheKnownIssueDoesNotDocument() {
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "A mock's parameters are sorted by label",
			signatures: [.renamedGraphDiffers(.mockCode)],
			seeds: [47],
		)
		let renamed = GraphFuzzerFailure(seed: 47, kind: .renamedGraphDiffers, details: "Reversing its labels changes its generated mock code, in S47_Root0+SafeDIMock.swift.\nThis graph:\n…", renamedGraphDifference: .mockCode)
		let retention = GraphFuzzerFailure(seed: 47, kind: .publicMockRetainsWhatKnownRightFrees, details: "probe `S47_App.mock()` keeps S47_Navigator alive holding detailBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path")

		#expect(GraphFuzzerFinding(failure: renamed, laterFailures: [retention], knownIssue: knownIssue) == .failure(retention))
	}

	@Test
	func finding_isKnownIssue_whenKnownIssueDocumentsTheRenamedGraphDifferenceAndTheRetentionFailure() {
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "A mock's parameters are sorted by label; and a public mock keeps a level's values alive",
			signatures: [.renamedGraphDiffers(.mockCode), .publicMockRetainsWhatKnownRightFrees(containing: "_Navigator alive holding detailBuilder")],
			seeds: [47],
		)
		let renamed = GraphFuzzerFailure(seed: 47, kind: .renamedGraphDiffers, details: "Reversing its labels changes its generated mock code, in S47_Root0+SafeDIMock.swift.\nThis graph:\n…", renamedGraphDifference: .mockCode)
		let retention = GraphFuzzerFailure(seed: 47, kind: .publicMockRetainsWhatKnownRightFrees, details: "probe `S47_App.mock()` keeps S47_Navigator alive holding detailBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path", valueDifferences: ["probe `S47_App.mock()` keeps S47_Navigator alive holding detailBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path"])

		#expect(GraphFuzzerFinding(failure: renamed, laterFailures: [retention], knownIssue: knownIssue) == .knownIssue(knownIssue, renamed))
	}

	@Test
	func finding_isFailure_whenKnownIssueSeedReportsAnotherCompilerError() {
		let knownIssue = Self.compilerErrorKnownIssue
		let failure = GraphFuzzerFailure(
			seed: knownIssue.seeds[0],
			kind: .generatedCodeDoesNotCompile,
			details: "Root+SafeDI.swift:3:5: error: cannot find 'missing' in scope",
		)

		let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssue)

		#expect(finding == .failure(failure))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "failure \(knownIssue.seeds[0]) generated code does not compile")
	}

	@Test
	func finding_isKnownIssue_whenKnownIssueSeedFailsAsDocumented() {
		let knownIssue = Self.compilerErrorKnownIssue
		let failure = GraphFuzzerFailure(
			seed: knownIssue.seeds[0],
			kind: .generatedCodeDoesNotCompile,
			details: "T4+SafeDIMock.swift:13:13: error: invalid redeclaration of 't5'",
		)

		let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssue)

		#expect(finding == .knownIssue(knownIssue, failure))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "known \(knownIssue.seeds[0]) \(knownIssue.reason)")
	}

	@Test
	func finding_isKnownIssue_whenKnownIssueSeedDrawsDocumentedWarning() {
		let knownIssue = Self.compilerWarningKnownIssue
		let failure = GraphFuzzerFailure(
			seed: knownIssue.seeds[0],
			kind: .generatedCodeDrawsWarning,
			details: "S84_Root0+SafeDI.swift:6:13: warning: initialization of immutable value '__safeDI_t1_fallback' was never used",
		)

		let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssue)

		#expect(finding == .knownIssue(knownIssue, failure))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "known \(knownIssue.seeds[0]) \(knownIssue.reason)")
	}

	@Test
	func finding_isFailure_whenCompilerWarningKnownIssueSeedFailsToCompileWithDocumentedText() {
		let knownIssue = Self.compilerWarningKnownIssue
		let failure = GraphFuzzerFailure(
			seed: knownIssue.seeds[0],
			kind: .generatedCodeDoesNotCompile,
			details: "S84_Root0+SafeDI.swift:6:13: error: initialization of immutable value '__safeDI_t1_fallback' was never used",
		)

		let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssue)

		#expect(finding == .failure(failure))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "failure \(knownIssue.seeds[0]) generated code does not compile")
	}

	@Test
	func finding_isFailure_whenCompilerErrorKnownIssueSeedDrawsWarningWithDocumentedText() {
		let knownIssue = Self.compilerErrorKnownIssue
		let failure = GraphFuzzerFailure(
			seed: knownIssue.seeds[0],
			kind: .generatedCodeDrawsWarning,
			details: "T4+SafeDIMock.swift:13:13: warning: invalid redeclaration of 't5'",
		)

		let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssue)

		#expect(finding == .failure(failure))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "failure \(knownIssue.seeds[0]) generated code draws a compiler warning")
	}

	@Test
	func finding_isStaleKnownIssue_whenKnownIssueSeedNoLongerFails() {
		let knownIssue = Self.compilerErrorKnownIssue

		let finding = GraphFuzzerFinding(failure: nil, knownIssue: knownIssue)

		#expect(finding == .staleKnownIssue(knownIssue))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "stale \(knownIssue.seeds[0]) \(knownIssue.reason)")
	}

	@Test(arguments: [
		GraphFuzzerKnownIssue.Signature.seamRetainsWhatInlineFrees(containing: "_RetainNavigator alive holding retainHome.retainDetailBuilder"),
		.publicMockRetainsWhatKnownRightFrees(containing: "_RetainNavigator alive holding retainHome.retainDetailBuilder"),
	])
	func finding_isPassed_whenRetentionOracleDidNotJudgeTheGraphOfAKnownIssueOfLeaksOnly(signature: GraphFuzzerKnownIssue.Signature) {
		// The retention oracle runs compiled code, so a run without compile verification judges no graph's retention: a
		// known issue that lists only leaks, its own and a hand-written builder's, is not stale where nothing judged them.
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "A seam's builder functions capture the values of each level on the way to a place; and a hand-written builder keeps them alive",
			signatures: [signature, .seamRetainsWhatInlineFrees(containing: "_RetainNavigator alive holding retainDetailBuilder")],
			seeds: [227],
		)

		#expect(GraphFuzzerFinding(failure: nil, knownIssue: knownIssue, retentionIsJudged: false) == .passed)
		#expect(GraphFuzzerFinding.findings(failure: nil, knownIssue: knownIssue, retentionIsJudged: false) == [.passed])
		#expect(GraphFuzzerFinding(failure: nil, knownIssue: knownIssue, retentionIsJudged: true) == .staleKnownIssue(knownIssue))
	}

	@Test
	func finding_isStaleKnownIssue_whenRetentionOracleDidNotJudgeTheGraphOfAKnownIssueThatListsMoreThanLeaks() {
		// Each signature is judged on its own: the leak's goes unjudged, but the compile error's was judged and is gone.
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "A shape whose generated code redeclares a label; and a seam's builder functions capture a level's values",
			signatures: [.compilerError(containing: "invalid redeclaration"), .seamRetainsWhatInlineFrees(containing: "_RetainNavigator alive holding retainHome.retainDetailBuilder")],
			seeds: [84],
		)

		#expect(GraphFuzzerFinding(failure: nil, knownIssue: knownIssue, retentionIsJudged: false) == .staleKnownIssue(knownIssue))
	}

	@Test
	func finding_isKnownIssue_whenMacroRejectsKnownIssueSeedsFixtureAsDocumented() {
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "A shape the macro rejects",
			signatures: [.macroRejectsFixture(containing: "require use of the argument `fulfilledByType`")],
			seeds: [12],
		)
		let failure = GraphFuzzerFailure(
			seed: 12,
			kind: .fixtureDoesNotCompile,
			details: "S12_T1.swift:9:2: error: `ErasedInstantiator` and `SendableErasedInstantiator` require use of the argument `fulfilledByType`",
		)

		#expect(GraphFuzzerFinding(failure: failure, knownIssue: knownIssue) == .knownIssue(knownIssue, failure))
	}

	@Test
	func finding_isFailure_whenMacroRejectionKnownIssueSeedsGeneratedCodeFailsToCompile() {
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "A shape the macro rejects",
			signatures: [.macroRejectsFixture(containing: "require use of the argument `fulfilledByType`")],
			seeds: [12],
		)
		let failure = GraphFuzzerFailure(
			seed: 12,
			kind: .generatedCodeDoesNotCompile,
			details: "S12_Root0+SafeDI.swift:3:5: error: `ErasedInstantiator` and `SendableErasedInstantiator` require use of the argument `fulfilledByType`",
		)

		#expect(GraphFuzzerFinding(failure: failure, knownIssue: knownIssue) == .failure(failure))
	}

	@Test
	func finding_isKnownIssue_whenKnownIssueSeedCrashesCompilerInGeneratedMock() {
		let knownIssue = Self.compilerCrashKnownIssue
		let failure = GraphFuzzerFailure(
			seed: knownIssue.seeds[0],
			kind: .compilerCrashedOnGeneratedCode,
			details: "The Swift compiler crashed.\nIn mock(t4:t1:safeDIOverrides:) at S705_T1+SafeDIMock.swift:19:5.",
		)

		#expect(GraphFuzzerFinding(failure: failure, knownIssue: knownIssue) == .knownIssue(knownIssue, failure))
	}

	@Test
	func finding_isFailure_whenKnownIssueSeedCrashesCompilerInShapeThatDoesNotCrash() {
		let knownIssue = Self.compilerErrorKnownIssue
		let failure = GraphFuzzerFailure(
			seed: knownIssue.seeds[0],
			kind: .compilerCrashedOnGeneratedCode,
			details: "The Swift compiler crashed.\nIn mock() at S9_Root0+SafeDIMock.swift:5:5.",
		)

		let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssue)

		#expect(finding == .failure(failure))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "failure \(knownIssue.seeds[0]) the Swift compiler crashed on generated code")
	}

	@Test
	func compilerCrash_namesCrashingDeclarationWithoutStackFrames_whenStandardErrorHoldsStackDump() throws {
		let standardError = """
		terminate called after throwing an instance of 'std::out_of_range'
		  what():  map::at
		Please submit a bug report (https://swift.org/contributing/#reporting-bugs) and include the crash backtrace.
		Stack dump:
		0.\tProgram arguments: /usr/bin/swift-frontend -frontend -c /tmp/safedi-verify-1/input_0_S705_Root0.swift
		1.\tSwift version 6.2.4 (swift-6.2.4-RELEASE)
		2.\tCompiling with the current language version
		3.\tWhile running pass #1021 SILFunctionTransform "SendNonSendable" on SILFunction "@$s4mock".
		 for 'mock(t4:t1:safeDIOverrides:)' (at /tmp/safedi-verify-1/S705_T1+SafeDIMock.swift:19:5)
		 #0 0x00005630b6cd92d8 llvm::sys::PrintStackTrace(llvm::raw_ostream&, int) (/usr/bin/swift-frontend+0x731f2d8)
		 #1 0x00005630b6cd70ae llvm::sys::RunSignalHandlers() (/usr/bin/swift-frontend+0x731d0ae)
		"""

		let crash = try #require(GraphFuzzerCompilerCrash(standardError: standardError))

		#expect(crash.fileName == "S705_T1+SafeDIMock.swift")
		#expect(crash.summary == """
		The Swift compiler crashed.
		1.\tSwift version 6.2.4 (swift-6.2.4-RELEASE)
		2.\tCompiling with the current language version
		3.\tWhile running pass #1021 SILFunctionTransform "SendNonSendable" on SILFunction "@$s4mock".
		In mock(t4:t1:safeDIOverrides:) at S705_T1+SafeDIMock.swift:19:5.
		""")
	}

	// MARK: Oracle sensitivity

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compilationFailures_reportEachBrokenGraph_whenGeneratedCodeFailsToTypeCheckOrToLowerOrDrawsWarning() async throws {
		// Each graph is one small type, so the four compiler invocations this takes stay cheap; the smoke batch
		// already compiles real graphs.
		let typeErrorSeed: UInt64 = 1_000_000_001
		let loweringErrorSeed: UInt64 = 1_000_000_002
		let warningSeed: UInt64 = 1_000_000_003
		let redirectedWarningSeed: UInt64 = 1_000_000_004
		let fixtureWarningSeed: UInt64 = 1_000_000_005
		let redirectedWarningPrefix = GraphFuzzerFixture.typeNamePrefix(forSeed: redirectedWarningSeed)
		let fixtureWarningPrefix = GraphFuzzerFixture.typeNamePrefix(forSeed: fixtureWarningSeed)
		let toolRuns = [
			// A type error, which the type checker reports.
			Self.probeGraph(seed: typeErrorSeed, generatedCode: "func broken() -> Int { \"not an integer\" }\n"),
			// A closure that captures a local declared after it, which only lowering to SIL reports, and which a
			// type error elsewhere in the same compilation would hide.
			Self.probeGraph(seed: loweringErrorSeed, generatedCode: """
			func brokenWhenLowered() -> Int {
				func read() -> Int { value }
				let value = read()
				return value
			}

			"""),
			// A warning in the generated file, which compiles.
			Self.probeGraph(seed: warningSeed, generatedCode: "func drawsWarning() {\n\tlet unused = 1\n}\n"),
			// A warning the compiler reports at the fixture's declaration, where a `#sourceLocation` directive in
			// the generated file attributes the line, as the tool's directives name the fixtures it was given.
			Self.probeGraph(seed: redirectedWarningSeed, generatedCode: """
			func drawsWarningAtDeclaration() {
				#sourceLocation(file: "/fuzzer/<fixture-directory>/\(redirectedWarningPrefix)Probe.swift", line: 3)
				let unused = 1
				#sourceLocation()
			}

			"""),
			// A warning the fixture draws too, which is not the generated code's to avoid. The two graphs above draw the
			// same message in their generated code and still fail, which pins that only a graph's own fixture excuses
			// its warning, although every graph is in the one compile.
			Self.probeGraph(
				seed: fixtureWarningSeed,
				fixtureDeclarations: "func \(fixtureWarningPrefix)drawsWarning() {\n\tlet unused = 1\n}\n",
				generatedCode: "func \(fixtureWarningPrefix)generatedDrawsWarning() {\n\tlet unused = 1\n}\n",
			),
		]

		let failures = try await GraphFuzzerOracle.compilationFailures(of: toolRuns)

		#expect(failures.keys.sorted() == [typeErrorSeed, loweringErrorSeed, warningSeed, redirectedWarningSeed])
		#expect(failures[typeErrorSeed]?.kind == .generatedCodeDoesNotCompile)
		#expect(failures[loweringErrorSeed]?.kind == .generatedCodeDoesNotCompile)
		#expect(failures[warningSeed]?.kind == .generatedCodeDrawsWarning)
		#expect(failures[warningSeed]?.details.contains("Broken.swift:3:6: warning: initialization of immutable value 'unused' was never used") == true)
		#expect(failures[redirectedWarningSeed]?.kind == .generatedCodeDrawsWarning)
		#expect(failures[redirectedWarningSeed]?.details.hasPrefix("/fuzzer/<fixture-directory>/\(redirectedWarningPrefix)Probe.swift:3:6: warning: initialization of immutable value 'unused' was never used") == true)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compilationFailures_reportWarning_whenGraphCompilesOnItsOwnAfterAnErrorThatNamesNoGraph() async throws {
		// The fixture's type name lacks its seed's prefix, so no graph's file is named in the error it draws, and the
		// oracle compiles each graph on its own.
		let unattributedErrorSeed: UInt64 = 1_000_000_006
		let warningSeed: UInt64 = 1_000_000_007
		let rejected = GraphFuzzerToolOutcome.rejected(diagnostics: "")
		let toolRuns = [
			GraphFuzzerToolRuns(
				fixture: GraphFuzzerFixture(seed: unattributedErrorSeed, swiftFileContent: [
					"@Instantiable\npublic final class UnprefixedProbe: Instantiable {\n\tpublic init() {}\n}\nfunc unprefixedBroken() -> Int { \"not an integer\" }\n",
				]),
				firstOutcome: rejected,
				secondOutcome: rejected,
			),
			Self.probeGraph(seed: warningSeed, generatedCode: "func drawsWarning() {\n\tlet unused = 1\n}\n"),
		]

		let failures = try await GraphFuzzerOracle.compilationFailures(of: toolRuns)

		#expect(failures.keys.sorted() == [unattributedErrorSeed, warningSeed])
		#expect(failures[unattributedErrorSeed]?.kind == .fixtureDoesNotCompile)
		#expect(failures[warningSeed]?.kind == .generatedCodeDrawsWarning)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compilationFailures_reportReleaseBuildFailure_whenGeneratedCodeCompilesOnlyWhereDebugIsDefined() async throws {
		// A graph the oracle compiles as a release build too (`GraphFuzzerFixture.compilesAsReleaseBuildToo`) fails there
		// when its generated code does not compile without `DEBUG`, and the failure says which build it was.
		let seed: UInt64 = 1_000_000_008
		let toolRuns = [Self.probeGraph(seed: seed, generatedCode: "#if !DEBUG\nfunc brokenInRelease() -> Int { \"not an integer\" }\n#endif\n")]

		#expect(try await GraphFuzzerOracle.compilationFailures(of: toolRuns).isEmpty)
		let failures = try await GraphFuzzerOracle.compilationFailures(of: toolRuns, definesDebug: false)

		#expect(failures.keys.sorted() == [seed])
		#expect(failures[seed]?.kind == .generatedCodeDoesNotCompile)
		#expect(failures[seed]?.details.hasPrefix("Compiled as a release build, without `DEBUG`:\n") == true)
	}

	/// A graph of one small type whose fixture also declares `fixtureDeclarations`, which the tool accepted with
	/// `generatedCode` as its one generated file.
	private static func probeGraph(seed: UInt64, fixtureDeclarations: String = "", generatedCode: String) -> GraphFuzzerToolRuns {
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
		let fixture = GraphFuzzerFixture(seed: seed, swiftFileContent: [
			"@Instantiable\npublic final class \(prefix)Probe: Instantiable {\n\tpublic init() {}\n}\n" + fixtureDeclarations,
		])
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["\(prefix)Broken.swift": generatedCode], warnings: [])
		return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func results_reportRunsDiffer_whenTwoRunsProduceDifferentOutput() async throws {
		let accepted = try #require(try await smokeResults.value.first { $0.isAccepted && $0.failure == nil })
		let runs = GraphFuzzerToolRuns(fixture: accepted.fixture, firstOutcome: accepted.outcome, secondOutcome: accepted.outcome)
		let differingRuns = GraphFuzzerToolRuns(
			fixture: accepted.fixture,
			firstOutcome: accepted.outcome,
			secondOutcome: runs.addingGeneratedFile(named: "Extra.swift", contents: "\n").firstOutcome,
		)

		// Graphs whose runs differ are not compiled, so this costs no compiler invocation.
		let results = try await GraphFuzzerOracle.results(of: [differingRuns])

		#expect(results.map(\.failure?.kind) == [.runsDiffer])
	}

	@Test
	func wrapperParameterFailure_reportsParameter_whenMockTakesLazilyInstantiatedParameterForReceive() {
		let runs = Self.mockedProbe(declaring: "@Received let value: LazilyInstantiated<S1_Value>", mockParameter: "value: LazilyInstantiated<S1_Value>")

		#expect(runs.wrapperParameterFailure?.kind == .mockTakesWrapperParameterForReceive)
		#expect(runs.wrapperParameterFailure?.details.prefix { $0 != "\n" } == "`S1_Probe.mock` takes `value: LazilyInstantiated<S1_Value>`.")
	}

	@Test
	func wrapperParameterFailure_isNil_whenPublicMockTakesWrapperItsTreeReceives() {
		// A public mock takes a value its tree receives lazily as the wrapper; its file declares the mock's guard enum.
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"@Instantiable(generateMock: .public)\npublic final class S1_Probe: Instantiable {\n\t@Received let value: LazilyInstantiated<S1_Value>\n}\n",
		])
		let outcome = GraphFuzzerToolOutcome.accepted(
			generatedFiles: ["S1_Probe+SafeDIMock.swift": "extension S1_Probe {\n    public static func mock(\n        value: LazilyInstantiated<S1_Value>\n    ) -> S1_Probe {}\n}\n\nextension S1_Probe {\n    public enum __safeDI_S1_Probe_mock_0123456789ABCDEF {}\n}\n"],
			warnings: [],
		)
		let runs = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)

		#expect(runs.wrapperParameterFailure == nil)
	}

	@Test
	func wrapperParameterFailure_isNil_whenMockTakesLazilyInstantiatedPropertyTheMockedTypeForwards() {
		let runs = Self.mockedProbe(declaring: "@Forwarded let value: LazilyInstantiated<S1_Value>", mockParameter: "value: LazilyInstantiated<S1_Value>")

		#expect(runs.wrapperParameterFailure == nil)
	}

	@Test
	func wrapperParameterFailure_isNil_whenMockTakesLazilyInstantiatedPropertyATypeInItsTreeInstantiatesAndItCannotBuild() {
		// `S1_HoleOwner`, which the mocked type builds through an instantiator, lazily instantiates a protocol beside its
		// by-value place that no declaration the mock sees fulfills, so the mock takes the wrapper.
		let runs = Self.mockedProbe(
			declaring: "@Instantiated let holeOwnerBuilder: Instantiator<S1_HoleOwner>",
			besideTypes: ["@Instantiable\npublic final class S1_HoleOwner: Instantiable {\n\t@Instantiated let holeService: any S1_HoleService\n\t@Instantiated let holeServiceLazy: LazilyInstantiated<any S1_HoleService>\n}\n"],
			mockParameters: ["holeService: any S1_HoleService", "holeServiceLazy: LazilyInstantiated<any S1_HoleService>"],
		)

		#expect(runs.wrapperParameterFailure == nil)
	}

	@Test
	func wrapperParameterFailure_reportsParameter_whenTypeInMockedTreeInstantiatesItsTypeUnderAnotherLabel() {
		// A type in the tree that instantiates the wrapper under another label does not account for the parameter.
		let runs = Self.mockedProbe(
			declaring: "@Instantiated let holeOwner: S1_HoleOwner",
			besideTypes: ["@Instantiable\npublic final class S1_HoleOwner: Instantiable {\n\t@Instantiated let holeServiceLazy: LazilyInstantiated<any S1_HoleService>\n\t@Received let value: LazilyInstantiated<any S1_HoleService>\n}\n"],
			mockParameters: ["holeServiceLazy: LazilyInstantiated<any S1_HoleService>", "value: LazilyInstantiated<any S1_HoleService>"],
		)

		#expect(runs.wrapperParameterFailure?.details.prefix { $0 != "\n" } == "`S1_Probe.mock` takes `value: LazilyInstantiated<any S1_HoleService>`.")
	}

	@Test
	func wrapperParameterFailure_reportsParameter_whenTypeInMockedTreeInstantiatesAWrapperTheMockCanBuild() {
		// `S1_Impl` fulfills the wrapper's instance and forwards nothing, so the mock builds the wrapper.
		let runs = Self.mockedProbe(
			declaring: "@Instantiated let a: S1_A",
			besideTypes: [
				"@Instantiable\npublic final class S1_A: Instantiable {\n\t@Instantiated let x: LazilyInstantiated<S1_Impl>\n}\n",
				"@Instantiable\npublic final class S1_Impl: Instantiable {\n\tpublic init() {}\n}\n",
			],
			mockParameters: ["x: LazilyInstantiated<S1_Impl>"],
		)

		#expect(runs.wrapperParameterFailure?.details.prefix { $0 != "\n" } == "`S1_Probe.mock` takes `x: LazilyInstantiated<S1_Impl>`.")
	}

	@Test
	func wrapperParameterFailure_reportsParameter_whenTypeTheMockReceivesAndCannotBuildInstantiatesItsType() {
		// The mock cannot build `S1_B`, which forwards a property, so it takes `b` and builds nothing `S1_B` instantiates.
		let runs = Self.mockedProbe(
			declaring: "@Received let b: S1_B",
			besideTypes: ["@Instantiable\npublic final class S1_B: Instantiable {\n\t@Forwarded let f: Int\n\t@Instantiated let x: LazilyInstantiated<any S1_Svc>\n}\n"],
			mockParameters: ["b: S1_B", "x: LazilyInstantiated<any S1_Svc>"],
		)

		#expect(runs.wrapperParameterFailure?.details.prefix { $0 != "\n" } == "`S1_Probe.mock` takes `x: LazilyInstantiated<any S1_Svc>`.")
	}

	@Test
	func wrapperParameterFailure_reportsParameter_whenMockTakesSendableAutoclosureOfWrapperForReceive() {
		let runs = Self.mockedProbe(
			declaring: "@Received let value: SendableLazilyInstantiated<S1_Value>",
			mockParameter: "value: @autoclosure @escaping @Sendable () -> SendableLazilyInstantiated<S1_Value>",
		)

		#expect(runs.wrapperParameterFailure?.details.prefix { $0 != "\n" } == "`S1_Probe.mock` takes `value: @autoclosure @escaping @Sendable () -> SendableLazilyInstantiated<S1_Value>`.")
	}

	@Test
	func wrapperParameterFailure_isNil_whenMockTakesSendableAutoclosureOfWrapperATypeInItsTreeInstantiatesAndItCannotBuild() {
		// Beneath a `Sendable` wrapper, the mock takes the wrapper `S1_HoleOwner` instantiates as a `@Sendable` autoclosure.
		let runs = Self.mockedProbe(
			declaring: "@Instantiated let holeOwnerBuilder: SendableInstantiator<S1_HoleOwner>",
			besideTypes: ["@Instantiable\npublic final class S1_HoleOwner: Instantiable {\n\t@Instantiated let holeServiceLazy: SendableLazilyInstantiated<any S1_HoleService>\n}\n"],
			mockParameters: ["holeServiceLazy: @autoclosure @escaping @Sendable () -> SendableLazilyInstantiated<any S1_HoleService>"],
		)

		#expect(runs.wrapperParameterFailure == nil)
	}

	/// The runs of a graph of one mocked type, `S1_Probe`, that declares `property`, beside the types `besideTypes`
	/// declares, whose generated mock takes `mockParameters`.
	private static func mockedProbe(declaring property: String, besideTypes: [String], mockParameters: [String]) -> GraphFuzzerToolRuns {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"@Instantiable(generateMock: true)\npublic final class S1_Probe: Instantiable {\n\t\(property)\n}\n",
		] + besideTypes)
		let parameters = mockParameters.map { "        \($0),\n" }.joined()
		let outcome = GraphFuzzerToolOutcome.accepted(
			generatedFiles: ["S1_Probe+SafeDIMock.swift": "extension S1_Probe {\n    static func mock(\n\(parameters)        safeDIOverrides: SafeDIOverrides = .init()\n    ) -> S1_Probe {}\n}\n"],
			warnings: [],
		)
		return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)
	}

	/// The runs of a graph of one mocked type, `S1_Probe`, that declares `property`, whose generated mock takes
	/// `mockParameter`.
	private static func mockedProbe(declaring property: String, mockParameter: String) -> GraphFuzzerToolRuns {
		mockedProbe(declaring: property, besideTypes: [], mockParameters: [mockParameter])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func results_reportIntegrationsDiffer_whenRenamedGraphAndSplitGraphBothGiveOtherResults() async throws {
		// One small type, so the compile this takes stays cheap, as in `compilationFailures_reportEachBrokenGraph…`.
		let seed: UInt64 = 1_000_000_008
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
		let fixture = GraphFuzzerFixture(seed: seed, swiftFileContent: [
			"@Instantiable\npublic final class \(prefix)Probe: Instantiable {\n\tpublic init() {}\n}\n",
		])
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		let multiModuleRuns = GraphFuzzerMultiModuleRuns(
			seed: seed,
			partition: GraphFuzzerPartition.partition(of: fixture),
			renaming: nil,
			moduleInfoOutcome: GraphFuzzerMultiModuleOutcome(verdicts: [.init(moduleName: "Alpha", kind: .accepted(GraphFuzzerGeneratedModule(units: [:], importsByFileName: ["Alpha.swift": []], warnings: [])))]),
			pluginOutcome: GraphFuzzerMultiModuleOutcome(verdicts: [.init(moduleName: "Alpha", kind: .rejected(diagnostics: "error"))]),
		)
		let toolRuns = GraphFuzzerToolRuns(
			fixture: fixture,
			firstOutcome: outcome,
			secondOutcome: outcome,
			renamedOutcomes: [(GraphFuzzerRenaming.all[0], .rejected(diagnostics: "renamed"))],
			multiModuleRuns: [multiModuleRuns],
		)

		let results = try await GraphFuzzerOracle.results(of: [toolRuns])

		#expect(results.map(\.failure?.kind) == [.integrationsDiffer])
		#expect(results.map { $0.renamedGraphFailures.map(\.kind) } == [[.renamedGraphDiffers]])
		#expect(results.map { $0.multiModuleFailures.map(\.kind) } == [[.integrationsDiffer]])
	}

	// MARK: Rename invariance

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func toolRuns_reportNoRenamedGraphFailure_whenFixtureDirectoryLiesUnderPathHoldingALabelTheRenamingReverses() async throws {
		// Seed 731 warns at a fixture file, so its warnings name the fixture directory's path, as a macOS runner's
		// temporary directory spells it: `/var/folders/h5/t85nd…/T/…`, whose `t8` undoing a label reversal rewrites.
		try await Self.expectNoRenamedGraphFailureUnderPathHoldingALabel(of: GraphFuzzerGenerator.fixture(forSeed: 731))
	}

	@Test(arguments: [UInt64(56), 88])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func toolRuns_rejectBothBuildsWithDeclarationBoundOnPathToReenteringCall_whenFillReadsValueOnlyOneRouteHoldsUnremedied(seed: UInt64) async throws {
		// `ReenteredGadgetImpl`, which fills a place `ReenteredHost` passes up, reads `reenteredMark` only if available, which
		// `ReenteredFirstImpl` binds before its call that builds `ReenteredSubB` again, so only that route holds it; seed
		// 88's `ReenteredHost` also binds the label above its call of `ReenteredTop`, which lifts nothing. The build
		// that fills the place from the roots' module and the visible build, which fills it in the seam's module, both reject
		// the read with `declarationBoundOnPathToReenteringCall`, naming the same reader and declaring type.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])
		let drawFeatures = GraphFuzzerFeature.seamDrawFeatures(of: fixture)
		#expect(drawFeatures.contains(.reenteredFillReadsValueOfOneRoute) || drawFeatures.contains(.reenteredFillReadsValueOfOneRouteBoundAboveCall))
		let runs = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: [])
		let prefix = fixture.typeNamePrefix
		let finding = "`\(prefix)ReenteredGadgetImpl` receives `reenteredMark: \(prefix)ReenteredMark?`, which `\(prefix)ReenteredFirstImpl` declares on the path from the builder for"
		for (build, outcome) in [("hole", Optional(runs.firstOutcome)), ("visible", runs.visibleOutcome)] {
			guard case let .rejected(diagnostics)? = outcome else {
				Issue.record("Seed \(seed)’s \(build) build is not rejected")
				continue
			}
			#expect(diagnostics.contains(finding), "Seed \(seed)’s \(build) build:\n\(diagnostics)")
		}
	}

	@Test(arguments: [
		(UInt64(384), GraphFuzzerSeamDrawFeature.placesOfOneCaseFillCapturesWrapperOfEveryPlace),
		(1_880, .placesOfOneCaseFillCapturesWrapperOfEveryPlace),
		(319, .placesOfOneCaseFillClosesCycleAtTwoDepths),
		(756, .placesOfOneCaseFillClosesCycleAtTwoDepths),
		(772, .placesOfOneCaseValueBoundAfterOnePlace),
		(835, .placesOfOneCaseValueBoundAfterOnePlace),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func toolRuns_rejectSharedAndUnsharedFillsWithSameDiagnostics_whenOnePlacesFillStandsForAnother(seed: UInt64, feature: GraphFuzzerSeamDrawFeature) async throws {
		// `StoodForLive` fills the place beneath each of `StoodForA` to `StoodForC`, and the fill of one stands for the
		// others'. Each shape is rejected by design, at every place: a `@Sendable` function in the fill captures the
		// `Instantiator` each parent declares, the fill closes a cycle on a declaration of the seam's tree that the places
		// reach at two depths, or it reads a value only one place binds after it. The run that shares fills and the run that
		// builds a fill of every place (`SeamFillSharing.buildsFillOfEveryPlace`) must print the same diagnostics, which
		// name every place with a finding: all three, or, for the value bound after its place, the last parent's, whose
		// fill the call does not build. With the capture walk not walking the places a fill stands for, seeds 384 and 1880
		// differ; with a closer's depth read from the path of the place the fill was built for, seeds 319 and 756 do; with
		// the places a fill stands for not judged, the build of seeds 772 and 835 that shares fills is accepted.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])
		#expect(GraphFuzzerFeature.seamDrawFeatures(of: fixture).contains(feature))
		let runs = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: [])
		guard case let .rejected(diagnostics) = runs.firstOutcome else {
			Issue.record("Seed \(seed)’s build that shares fills is not rejected")
			return
		}
		#expect(diagnostics.split(separator: "\n").contains { $0.contains(": error: ") && $0.contains("\(fixture.typeNamePrefix)StoodFor") }, "Seed \(seed):\n\(diagnostics)")
		#expect(runs.firstOutcome == runs.secondOutcome, "Seed \(seed)’s build of a fill of every place:\n\(runs.secondOutcome)")
	}

	@Test(arguments: [UInt64(593), 912, 1_187, 1_834])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func toolRuns_rejectRootsCallAtItsProperty_whenRootFillsPlaceWithSeamWhosePlaceNothingFulfills(seed: UInt64) async throws {
		// `NestedFillRoot` fills `NestedFillHome`'s place of `NestedFillPanel` with `NestedFillPanelImpl`, a seam of the roots'
		// module that instantiates `NestedFillGadget`, which nothing fulfills, so the fill's own call takes a builder no one
		// fills. The tool reports it at the root's property, as it reports a place of `NestedFillHome`'s own that no one
		// fills. With the root's check judging only the places of the call it makes, seed 1187 is accepted and its
		// generated call passes no builder for the gadget; the other three seeds are then rejected by other errors first.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])
		#expect(GraphFuzzerFeature.seamDrawFeatures(of: fixture).contains(.nestedFillHoleUnfilled))
		let runs = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: [])
		guard case let .rejected(diagnostics) = runs.firstOutcome else {
			Issue.record("Seed \(seed) is not rejected")
			return
		}
		let prefix = fixture.typeNamePrefix
		#expect(diagnostics.split(separator: "\n").contains { $0.contains("/\(prefix)NestedFillRoot.swift:") && $0.contains(": error: ") && $0.contains("fulfills `\(prefix)NestedFillGadget`") }, "Seed \(seed):\n\(diagnostics)")
	}

	@Test(arguments: [UInt64(654), 10_921])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func toolRuns_rejectBothBuildsWithEachDeferringSeamsTwoForms_whenCarriedLevelsFillReadsOptionalSendableWrapper(seed: UInt64) async throws {
		// `CarriedInner` defers `carriedToken` in a `LazilyInstantiated`, `CarriedInnerB` `@Sendable`, and
		// `CarriedWrapperReader`, in the fill of `CarriedGizmo` the roots' module makes, receives the `SendableLazilyInstantiated`
		// only if available, which no parameter of `CarriedTop`, whose place the fill fills, provides beside its value.
		// `CarriedTop`'s tree, built with the fill in its own module, receives `carriedToken` in two forms, so the build that
		// fills the place from the roots' module and the visible build, which fills it in the seam's module, both report that,
		// in the same words, every receive of the label named, and nothing else, where the fill once passed the reader `nil`
		// while inline passes it the declared wrapper. Neither graph declares `HoleSeam`.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])
		let drawFeatures = GraphFuzzerFeature.seamDrawFeatures(of: fixture)
		#expect(drawFeatures.contains(.carriedLevelFillReadsOptionalSendableWrapper))
		#expect(!drawFeatures.contains(.hole))
		let runs = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: [])
		let prefix = fixture.typeNamePrefix
		// Each error, without its location: the seams' files are in other modules.
		func errors(in diagnostics: String) -> [String] {
			diagnostics.split(separator: "\n").compactMap { line in
				line.range(of: ": error: ").map { String(line[$0.upperBound...]) }
			}
		}
		var errorsByBuild = [String: [String]]()
		for (build, outcome) in [("hole", Optional(runs.firstOutcome)), ("visible", runs.visibleOutcome)] {
			guard case let .rejected(diagnostics)? = outcome else {
				Issue.record("Seed \(seed)’s \(build) build is not rejected")
				continue
			}
			let buildErrors = errors(in: diagnostics)
			errorsByBuild[build] = buildErrors
			#expect(!buildErrors.isEmpty && buildErrors.allSatisfy { $0.contains("its tree receives `carriedToken` as ") && $0.contains("` on `\(prefix)CarriedWrapperReader`") && $0.hasSuffix(" as the form that provides the others: `@Received let carriedToken: SendableLazilyInstantiated<\(prefix)CarriedToken>`.") }, "Seed \(seed)’s \(build) build:\n\(diagnostics)")
		}
		#expect(errorsByBuild["hole"] == errorsByBuild["visible"])
	}

	@Test(arguments: [UInt64(609), 10_921])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func toolRuns_rejectBothBuildsWithDeferringSeamsTwoForms_whenCarriedOuterReceivesWrapperItsLevelsFillReadsOptionally(seed: UInt64) async throws {
		// The graph of the test above where `CarriedOuter`, which passes up the place whose fill builds `CarriedWorker`,
		// receives the `SendableLazilyInstantiated` `CarriedRoot` declares as its own property, which provides
		// `CarriedWrapperReader`'s optional read: the place's field is `CarriedOuter`'s, and the fill of `CarriedGizmo` takes
		// `CarriedInner`'s memo, which once gave the reader `nil` while inline passes it the declared wrapper. Built in one
		// module, `CarriedInner`'s tree receives `carriedToken` in two forms, which both builds report, in the same words,
		// at a seam that defers it. Neither graph declares `HoleSeam`.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])
		let drawFeatures = GraphFuzzerFeature.seamDrawFeatures(of: fixture)
		#expect(drawFeatures.contains(.carriedLevelFillReadsOptionalSendableWrapperOuterReceives))
		#expect(!drawFeatures.contains(.hole))
		let runs = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: [])
		let prefix = fixture.typeNamePrefix
		// Each error, without its location: the seams' files are in other modules.
		func errors(in diagnostics: String) -> [String] {
			diagnostics.split(separator: "\n").compactMap { line in
				line.range(of: ": error: ").map { String(line[$0.upperBound...]) }
			}
		}
		var errorsByBuild = [String: [String]]()
		for (build, outcome) in [("hole", Optional(runs.firstOutcome)), ("visible", runs.visibleOutcome)] {
			guard case let .rejected(diagnostics)? = outcome else {
				Issue.record("Seed \(seed)’s \(build) build is not rejected")
				continue
			}
			let buildErrors = errors(in: diagnostics)
			errorsByBuild[build] = buildErrors
			#expect(!buildErrors.isEmpty && buildErrors.allSatisfy { $0.hasPrefix("SafeDI cannot generate the dependency tree of `\(prefix)CarriedInner") && $0.contains("its tree receives `carriedToken` as ") && $0.contains("` on `\(prefix)CarriedWrapperReader`") && $0.hasSuffix(" as the form that provides the others: `@Received let carriedToken: SendableLazilyInstantiated<\(prefix)CarriedToken>`.") }, "Seed \(seed)’s \(build) build:\n\(diagnostics)")
		}
		#expect(errorsByBuild["hole"] == errorsByBuild["visible"])
	}

	@Test(arguments: [UInt64(80), 279, 306])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func toolRuns_rejectBothBuildsWithFieldOfReenteringPlace_whenCallerFillsPlaceInsideFillBuiltAgainUnremedied(seed: UInt64) async throws {
		// `ReenteredSubA` binds `reenteredTag` before `reenteredFirst`, whose fill `ReenteredFirstImpl` builds `ReenteredSubB`
		// again – in seed 279 through `ReenteredRelay`, a seam that builds `ReenteredSubB` and passes its place up – and
		// `ReenteredGadgetImpl`, which fills from the roots' module a place inside the fill of `reenteredSecond` that
		// `ReenteredHost` passes up, reads it, so only the place whose fill builds the seam again carries it: only if available
		// in seed 279, also beside `ReenteredHost`'s binding of the label above its call of `ReenteredTop` in seed 306, and
		// required in seed 80. None declares `HoleSeam`, whose graphs draw the remedy in place of these reads. The build that
		// fills the place from the roots' module, which reads what `ReenteredHost`'s module records on the place, and the
		// visible build, which fills it in the seam's module, both reject the read with `fieldOfReenteringPlace`, in the same
		// words, naming the call as written and offering the receive on `ReenteredSubB`, the seam built again: a receive on
		// `ReenteredRelay` would not reach the place it passes up.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])
		let drawFeatures = GraphFuzzerFeature.seamDrawFeatures(of: fixture)
		#expect(!drawFeatures.isDisjoint(with: [.reenteredFillReadsPlaceField, .reenteredFillReadsPlaceFieldBoundAboveCall, .reenteredFillRequiresPlaceField]))
		#expect(!drawFeatures.contains(.hole))
		let callsThroughRelay = drawFeatures.contains(.reenteredFillCallThroughSeamPassingPlaceUp)
		#expect(callsThroughRelay == (seed == 279))
		let runs = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: [])
		let prefix = fixture.typeNamePrefix
		// Each error about the reader's receive of `reenteredTag`, without its location: the reader's file is in another
		// module in each build.
		func findings(in diagnostics: String) -> [String] {
			diagnostics.split(separator: "\n").compactMap { line in
				guard line.contains("`\(prefix)ReenteredGadgetImpl` receives `reenteredTag: "), let range = line.range(of: ": error: ") else { return nil }
				return String(line[range.upperBound...])
			}
		}
		let call = callsThroughRelay
			? "that builder’s fill instantiates `\(prefix)ReenteredRelay` (`"
			: "that builder’s fill instantiates `\(prefix)ReenteredSubB` again (`"
		var findingsByBuild = [String: [String]]()
		for (build, outcome) in [("hole", Optional(runs.firstOutcome)), ("visible", runs.visibleOutcome)] {
			guard case let .rejected(diagnostics)? = outcome else {
				Issue.record("Seed \(seed)’s \(build) build is not rejected")
				continue
			}
			let buildFindings = findings(in: diagnostics)
			findingsByBuild[build] = buildFindings
			#expect(buildFindings.contains { $0.contains("carries from `\(prefix)ReenteredSubA`, and \(call)") }, "Seed \(seed)’s \(build) build:\n\(diagnostics)")
			#expect(buildFindings.contains { $0.contains("inside that `\(prefix)ReenteredSubB`, but") && $0.contains("` on `\(prefix)ReenteredSubB`, so SafeDI hands it to the builder") }, "Seed \(seed)’s \(build) build:\n\(diagnostics)")
			#expect(!buildFindings.contains { $0.contains("` on `\(prefix)ReenteredRelay`") }, "Seed \(seed)’s \(build) build:\n\(diagnostics)")
		}
		#expect(findingsByBuild["hole"] == findingsByBuild["visible"])
	}

	@Test(arguments: [UInt64(59)])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func toolRuns_acceptBothBuildsWithVisibleBuildsValues_whenSeamBuiltAgainReceivesLabelOnlyTheReenteringPlaceCarries(seed: UInt64) async throws {
		// The remedy `fieldOfReenteringPlace` offers, applied as the draw applies it: `ReenteredSubB`, the seam built again,
		// receives `reenteredTag` as `ReenteredGadgetImpl` does. Seed 59's fill calls `ReenteredRelay`, which builds
		// `ReenteredSubB` and passes its place up, so the receive goes on another seam than the one the call names. Both
		// builds accept the graph, and every oracle passes, the comparison of the hole build's values with the visible
		// build's included.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])
		let drawFeatures = GraphFuzzerFeature.seamDrawFeatures(of: fixture)
		#expect(drawFeatures.isSuperset(of: [.reenteredFillReadsPlaceFieldRemedied, .reenteredFillCallThroughSeamPassingPlaceUp]))
		let runs = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: [])
		for (build, outcome) in [("hole", Optional(runs.firstOutcome)), ("visible", runs.visibleOutcome)] {
			switch outcome {
			case .accepted?:
				break
			case let .rejected(diagnostics)?:
				Issue.record("Seed \(seed)’s \(build) build is rejected:\n\(diagnostics)")
			case nil:
				Issue.record("Seed \(seed) has no \(build) build")
			}
		}
		let results = try await GraphFuzzerOracle.results(of: [runs])
		#expect(results.map { $0.failure.map { "\($0.kind): \($0.details)" } } == [nil])
		#expect(results.flatMap { $0.laterFailures.map { "\($0.kind): \($0.details)" } } == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func toolRuns_reportNoRenamedGraphFailure_whenFixtureRootOfGraphSplitAcrossModulesLiesUnderPathHoldingALabelTheRenamingReverses() async throws {
		// Seed 155 of the seam corpus is split across modules and warns at a fixture file, so its warnings name the
		// fixture root's path.
		try await Self.expectNoRenamedGraphFailureUnderPathHoldingALabel(of: GraphFuzzerGenerator.fixture(forSeed: 155, features: [.generateDependencyTree]))
	}

	@Test
	func normalizer_reducesEachSpellingOfThePathToTheFixtureDirectory_withTheDirectoriesAboveIt() {
		let directory = "/var/folders/h5/t85nd63d71x27_8gl5gw3l_w0000gn/T/0F6A3B4C-1D2E-4F50-8172-93A4B5C6D7E8"
		let normalize = GraphFuzzerOracle.normalizer(fixtureDirectory: directory)

		#expect(normalize("\(directory)/S12_T1.swift:8:2: warning: one") == "<fixture-directory>/S12_T1.swift:8:2: warning: one")
		#expect(normalize("/private\(directory)/S12_T1.swift:8:2: warning: one") == "<fixture-directory>/S12_T1.swift:8:2: warning: one")
		#expect(normalize("            #sourceLocation(file: \"\(directory)/shop/Sources/FuzzApp/S12_T1.swift\", line: 8)") == "            #sourceLocation(file: \"<fixture-directory>/shop/Sources/FuzzApp/S12_T1.swift\", line: 8)")
		#expect(normalize("location: Optional(DeclarationLocation(filePath: \"\(directory)/S12_T1.swift\", line: 8") == "location: Optional(DeclarationLocation(filePath: \"<fixture-directory>/S12_T1.swift\", line: 8")
		#expect(normalize("chain: S12_Root0 -> S12_T1 at `\(directory)/S12_T1.swift`") == "chain: S12_Root0 -> S12_T1 at `<fixture-directory>/S12_T1.swift`")
		#expect(normalize("/var/folders/h5/t85nd63d71x27_8gl5gw3l_w0000gn/T/other/S12_T1.swift:8:2: warning: one") == "/var/folders/h5/t85nd63d71x27_8gl5gw3l_w0000gn/T/other/S12_T1.swift:8:2: warning: one")
	}

	/// Runs the oracle over `fixture` and the fixture with its labels reversed, with every fixture directory under a
	/// directory named as a macOS runner's temporary directory is, and expects the two to agree.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func expectNoRenamedGraphFailureUnderPathHoldingALabel(of fixture: GraphFuzzerFixture, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		let parentDirectory = TestTemporaryDirectory.root.appendingPathComponent("t85nd63d71x27_8gl5gw3l_w0000gn-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: parentDirectory)
		}
		let labelReversal = GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: true, reversesFileNames: false)
		let toolRuns = try await TestFixtureLocation.$parentDirectory.withValue(parentDirectory) {
			try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: [labelReversal], multiModuleRenamings: [])
		}

		guard case let .accepted(_, warnings) = toolRuns.firstOutcome else {
			Issue.record("The tool rejected seed \(fixture.seed):\n\(toolRuns.firstOutcome.description)", sourceLocation: sourceLocation)
			return
		}
		#expect(warnings.contains { $0.contains("<fixture-directory>/") }, "No warning of seed \(fixture.seed) names a fixture file", sourceLocation: sourceLocation)
		#expect(toolRuns.renamedGraphFailures.map(\.details) == [], sourceLocation: sourceLocation)
	}

	@Test
	func renaming_reversesTypeNamesAndLabelsWhereverTheyAppear_andRestoresThem() {
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: 12)
		let text = "S12_T1 S12_T3Protocol S12_AnyT2 S12_Root0 S12_Missing1 S12_Value t1Builder __safeDI_t3Builder lazyAnyT2 anyT4 missing0 items t4_S12_T4"
		let renaming = GraphFuzzerRenaming(reversesTypeNames: true, reversesLabels: true, reversesFileNames: false)

		#expect(renaming.rename(text, typeNamePrefix: prefix) == "S12_T8 S12_T6Protocol S12_AnyT7 S12_Root9 S12_Missing8 S12_Value t8Builder __safeDI_t6Builder lazyAnyT7 anyT5 missing9 items t5_S12_T5")
		#expect(renaming.restore(renaming.rename(text, typeNamePrefix: prefix), typeNamePrefix: prefix) == text)
	}

	@Test
	func renaming_renamesOnlyTheOrderItReverses() {
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: 12)
		let text = "S12_T1 t1Builder"

		#expect(GraphFuzzerRenaming(reversesTypeNames: true, reversesLabels: false, reversesFileNames: false).rename(text, typeNamePrefix: prefix) == "S12_T8 t1Builder")
		#expect(GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: true, reversesFileNames: false).rename(text, typeNamePrefix: prefix) == "S12_T1 t8Builder")
		#expect(GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: false, reversesFileNames: true).rename(text, typeNamePrefix: prefix) == text)
	}

	@Test
	func renaming_movesTypeNamesAcrossWrapperNamesWhereverTheyAppear_andRestoresThem() {
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: 12)
		let text = "S12_T1 S12_T2 S12_T2Protocol S12_AnyT2 S12_Root0 S12_Missing1 S12_Value S12_Leaf S12_Ext S12_Unbuildable0 t1_S12_T1 lazyAnyT2 Instantiator<S12_T1> x_SendableInstantiator__S12_T2 S12_T0+SafeDIMock.swift"
		let renaming = GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: false, reversesFileNames: false, movesTypeNamesAcrossWrapperNames: true)

		// A type and its protocol move together, and so does a name a generated name or a file name embeds; labels keep their indices.
		#expect(renaming.rename(text, typeNamePrefix: prefix) == "A12_T1 Z12_T2 Z12_T2Protocol Z12_AnyT2 A12_Root0 A12_Missing1 Z12_Value A12_Leaf Z12_Ext Z12_Unbuildable0 t1_A12_T1 lazyAnyT2 Instantiator<A12_T1> x_SendableInstantiator__Z12_T2 A12_T0+SafeDIMock.swift")
		#expect(renaming.restore(renaming.rename(text, typeNamePrefix: prefix), typeNamePrefix: prefix) == text)
	}

	@Test
	func renamedFixture_declaresTypesSortingBeforeAndAfterEveryWrapperName_whenRenamingMovesTypeNamesAcrossWrapperNames() throws {
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 2)
		let renaming = try #require(GraphFuzzerRenaming.all.first { $0.movesTypeNamesAcrossWrapperNames })
		let wrapperNames = ["ErasedInstantiator<", "Instantiator<", "LazilyInstantiated<", "SendableErasedInstantiator<", "SendableInstantiator<", "SendableLazilyInstantiated<"]
		func declaredTypeNamesAmongWrapperNames(of fixture: GraphFuzzerFixture) -> [String] {
			(fixture.swiftFileContent.flatMap(GraphFuzzerSourceLine.lines(of:)).compactMap(\.declaredTypeName) + wrapperNames).sorted()
		}

		// Every type name begins with `S2_`, which reversing indices keeps, so each sorts between the same two wrapper names.
		#expect(declaredTypeNamesAmongWrapperNames(of: fixture) == [
			"ErasedInstantiator<", "Instantiator<", "LazilyInstantiated<",
			"S2_Leaf", "S2_Root0", "S2_Root1", "S2_Root2", "S2_Service", "S2_T0", "S2_T1", "S2_T2", "S2_T3",
			"SendableErasedInstantiator<", "SendableInstantiator<", "SendableLazilyInstantiated<",
		])
		// Moved, some sort before every wrapper name and the rest after every one, and `T0` and `T1` now sort after `T2` and `T3`.
		#expect(declaredTypeNamesAmongWrapperNames(of: fixture.renamed(by: renaming)) == [
			"A2_Root0", "A2_Root1", "A2_Service", "A2_T2", "A2_T3",
			"ErasedInstantiator<", "Instantiator<", "LazilyInstantiated<", "SendableErasedInstantiator<", "SendableInstantiator<", "SendableLazilyInstantiated<",
			"Z2_Leaf", "Z2_Root2", "Z2_T0", "Z2_T1",
		])
	}

	// MARK: Sibling alias chains

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_declaresChainOfAliasesThroughOnlyIfAvailableAliasOfSiblingsOptionalFormBeneathOtherSibling_forSeed731() async throws {
		// `Root0` instantiates `t1: T1` and `lazyT0`, which builds `T0`. `T0` renames `t1` by its optional form only if
		// available; `Link0`, which only `T0` instantiates, renames that alias only if available; and `Link1`, which only
		// `Link0` instantiates, renames the second alias as required – a chain through child scopes, since no type renames
		// a rename it declares. So `t1` must be built before `lazyT0`. `S731_Ext.instantiate` receives `lazyT0`'s instance, but nothing `t1` builds receives `lazyT0`, so
		// the tool accepts the graph, creates the whole chain from `t1`, and the smoke batch compiles it.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 731)

		#expect(Self.propertyDeclarations(of: "S731_Root0", in: fixture).prefix(2) == [
			"@Instantiated let t1: S731_T1",
			"@Instantiated let lazyT0: SendableLazilyInstantiated<S731_T0>",
		])
		#expect(Self.propertyDeclarations(of: "S731_T0", in: fixture).suffix(3) == [
			"@Received(fulfilledByDependencyNamed: \"t1\", ofType: S731_T1.self, erasedToConcreteExistential: true, onlyIfAvailable: true) let anyT1Alias: S731_AnyT1?",
			"@Received(fulfilledByDependencyNamed: \"t1\", ofType: S731_T1?.self, onlyIfAvailable: true) let t1Alias: S731_T1?",
			"@Instantiated let link0: S731_Link0",
		])
		#expect(Self.propertyDeclarations(of: "S731_Link0", in: fixture) == [
			"@Received(fulfilledByDependencyNamed: \"t1Alias\", ofType: S731_T1?.self, onlyIfAvailable: true) let t1AliasAlias: S731_T1?",
			"@Instantiated let link1: S731_Link1",
		])
		#expect(Self.propertyDeclarations(of: "S731_Link1", in: fixture) == [
			"@Received(fulfilledByDependencyNamed: \"t1AliasAlias\", ofType: S731_T1?.self) let t1AliasAliasAlias: S731_T1?",
		])
		#expect(Self.propertyDeclarations(of: "S731_T1", in: fixture) == [])
		#expect(GraphFuzzerFeature.features(of: fixture).isSuperset(of: [.aliasOfOptionalFormOfProperty, .aliasOfOnlyIfAvailableAlias, .onlyIfAvailableAlias, .requiredAlias]))
		let result = try #require(try await smokeResults.value.first { $0.fixture.seed == 731 })
		#expect(result.failure == nil)
		#expect(Self.generatedFiles(of: result.outcome)["S731_Root0+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension S731_Root0 {
		    public convenience init() {
		        let t1 = S731_T1()
		        @Sendable nonisolated func __safeDI_link0(t1Alias: S731_T1?) -> S731_Link0 {
		            #sourceLocation(file: "S731_Link0.swift", line: 8)
		            let t1AliasAlias: S731_T1? = t1Alias
		            #sourceLocation()
		            let link1: S731_Link1 = __safeDI_link1(t1AliasAlias: t1AliasAlias)
		            return S731_Link0(t1AliasAlias: t1AliasAlias, link1: link1)
		        }
		        @Sendable nonisolated func __safeDI_link1(t1AliasAlias: S731_T1?) -> S731_Link1 {
		            #sourceLocation(file: "S731_Link1.swift", line: 7)
		            let t1AliasAliasAlias: S731_T1? = t1AliasAlias
		            #sourceLocation()
		            return S731_Link1(t1AliasAliasAlias: t1AliasAliasAlias)
		        }
		        @Sendable nonisolated func __safeDI_lazyT0() -> S731_T0 {
		            #sourceLocation(file: "S731_T0.swift", line: 9)
		            let anyT1Alias: S731_AnyT1? = S731_AnyT1(t1)
		            #sourceLocation()
		            #sourceLocation(file: "S731_T0.swift", line: 10)
		            let t1Alias: S731_T1? = t1
		            #sourceLocation()
		            let link0: S731_Link0 = __safeDI_link0(t1Alias: t1Alias)
		            return S731_T0(anyT1Alias: anyT1Alias, t1Alias: t1Alias, link0: link0)
		        }
		        let lazyT0 = SendableLazilyInstantiated<S731_T0>(__safeDI_lazyT0)
		        func __safeDI_t2Builder() -> S731_T2 {
		            #sourceLocation(file: "S731_T2.swift", line: 7)
		            let t1Alias: S731_T1? = t1
		            #sourceLocation()
		            return S731_T2(t1Alias: t1Alias)
		        }
		        let t2Builder = Instantiator<S731_T2>(__safeDI_t2Builder)
		        let ext: S731_Ext = S731_Ext.instantiate(lazyT0: lazyT0.instance)
		        self.init(t1: t1, lazyT0: lazyT0, t2Builder: t2Builder, ext: ext)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_declaresChainOfAliasesThroughChildScopeBeneathOtherSibling_forSeed2420() async throws {
		// `T0`, which no root reaches, so that only its mock builds it, instantiates `t6: T6` and `t2: T2`. `T2` renames
		// `t6` only if available; `Link0`, which only `T2` instantiates, renames that alias only if available; `Link1`,
		// which only `Link0` instantiates, renames the second alias only if available; and `Link2` receives the third
		// only if available – a chain through child scopes. The tool accepts the graph, `T0`'s mock builds `t6` before
		// `t2`, as declared, and creates the whole chain from it, and the smoke batch compiles it.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 2_420)

		#expect(Self.propertyDeclarations(of: "S2420_T0", in: fixture).prefix(2) == [
			"@Instantiated let t6: S2420_T6",
			"@Instantiated let t2: S2420_T2",
		])
		#expect(Self.propertyDeclarations(of: "S2420_T2", in: fixture).suffix(3) == [
			"@Instantiated let t1Builder: Instantiator<S2420_T1>",
			"@Received(fulfilledByDependencyNamed: \"t6\", ofType: S2420_T6.self, onlyIfAvailable: true) let t6Alias: S2420_T6?",
			"@Instantiated let link0: S2420_Link0",
		])
		#expect(Self.propertyDeclarations(of: "S2420_Link0", in: fixture) == [
			"@Received(fulfilledByDependencyNamed: \"t6Alias\", ofType: S2420_T6?.self, onlyIfAvailable: true) let t6AliasAlias: S2420_T6?",
			"@Instantiated let link1: S2420_Link1",
		])
		#expect(Self.propertyDeclarations(of: "S2420_Link1", in: fixture) == [
			"@Received(fulfilledByDependencyNamed: \"t6AliasAlias\", ofType: S2420_T6?.self, onlyIfAvailable: true) let t6AliasAliasAlias: S2420_T6?",
			"@Instantiated let link2: S2420_Link2",
		])
		#expect(Self.propertyDeclarations(of: "S2420_Link2", in: fixture) == ["@Received(onlyIfAvailable: true) let t6AliasAliasAlias: S2420_T6?"])
		let result = try #require(try await smokeResults.value.first { $0.fixture.seed == 2_420 })
		#expect(result.failure == nil)
		#expect(Self.generatedFiles(of: result.outcome)["S2420_T0+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension S2420_T0 {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            t6: (() -> S2420_T6)? = nil,
		            service: (() -> S2420_Service)? = nil,
		            t2: S2420_T2.SafeDIMockConfiguration = .init(),
		            anyT1: ((S2420_Service) -> S2420_AnyT1)? = nil,
		            t1Builder: ((S2420_Service) -> S2420_T1)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                t6: t6,
		                service: service,
		                t2: t2,
		                anyT1: anyT1,
		                t1Builder: t1Builder
		            )
		        }

		        var t6: (() -> S2420_T6)? { __safeDI_storage.t6 }
		        var service: (() -> S2420_Service)? { __safeDI_storage.service }
		        var t2: S2420_T2.SafeDIMockConfiguration { __safeDI_storage.t2 }
		        var anyT1: ((S2420_Service) -> S2420_AnyT1)? { __safeDI_storage.anyT1 }
		        var t1Builder: ((S2420_Service) -> S2420_T1)? { __safeDI_storage.t1Builder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                t6: (() -> S2420_T6)?,
		                service: (() -> S2420_Service)?,
		                t2: S2420_T2.SafeDIMockConfiguration,
		                anyT1: ((S2420_Service) -> S2420_AnyT1)?,
		                t1Builder: ((S2420_Service) -> S2420_T1)?
		            ) {
		                self.t6 = t6
		                self.service = service
		                self.t2 = t2
		                self.anyT1 = anyT1
		                self.t1Builder = t1Builder
		            }

		            let t6: (() -> S2420_T6)?
		            let service: (() -> S2420_Service)?
		            let t2: S2420_T2.SafeDIMockConfiguration
		            let anyT1: ((S2420_Service) -> S2420_AnyT1)?
		            let t1Builder: ((S2420_Service) -> S2420_T1)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> S2420_T0 {
		        let t6 = if let safeDIBuilder = safeDIOverrides.t6 { safeDIBuilder() } else { S2420_T6() }
		        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { S2420_Service.preview() }
		        func __safeDI_t2() -> S2420_T2 {
		            func __safeDI_t1Builder() -> S2420_T1 {
		                if let safeDIBuilder = safeDIOverrides.t2.t1Builder { safeDIBuilder(service) } else { S2420_T1.customMock(service: service) }
		            }
		            let t1Builder = Instantiator<S2420_T1>(__safeDI_t1Builder)
		            #sourceLocation(file: "S2420_T2.swift", line: 10)
		            let t6Alias: S2420_T6? = t6
		            #sourceLocation()
		            func __safeDI_link0() -> S2420_Link0 {
		                #sourceLocation(file: "S2420_Link0.swift", line: 8)
		                let t6AliasAlias: S2420_T6? = t6Alias
		                #sourceLocation()
		                func __safeDI_link1() -> S2420_Link1 {
		                    #sourceLocation(file: "S2420_Link1.swift", line: 8)
		                    let t6AliasAliasAlias: S2420_T6? = t6AliasAlias
		                    #sourceLocation()
		                    let link2 = if let safeDIBuilder = safeDIOverrides.t2.link0.link1.link2 { safeDIBuilder(t6AliasAliasAlias) } else { S2420_Link2(t6AliasAliasAlias: t6AliasAliasAlias) }
		                    return if let safeDIBuilder = safeDIOverrides.t2.link0.link1.safeDIBuilder { safeDIBuilder(t6AliasAliasAlias, link2) } else { S2420_Link1(t6AliasAliasAlias: t6AliasAliasAlias, link2: link2) }
		                }
		                let link1: S2420_Link1 = __safeDI_link1()
		                return if let safeDIBuilder = safeDIOverrides.t2.link0.safeDIBuilder { safeDIBuilder(t6AliasAlias, link1) } else { S2420_Link0(t6AliasAlias: t6AliasAlias, link1: link1) }
		            }
		            let link0: S2420_Link0 = __safeDI_link0()
		            return if let safeDIBuilder = safeDIOverrides.t2.safeDIBuilder { safeDIBuilder(t1Builder, t6Alias, link0) } else { S2420_T2(t1Builder: t1Builder, t6Alias: t6Alias, link0: link0) }
		        }
		        let t2: S2420_T2 = __safeDI_t2()
		        let anyT1 = if let safeDIBuilder = safeDIOverrides.anyT1 { safeDIBuilder(service) } else { S2420_AnyT1(S2420_T1.customMock(service: service)) }
		        func __safeDI_t1Builder() -> S2420_T1 {
		            if let safeDIBuilder = safeDIOverrides.t1Builder { safeDIBuilder(service) } else { S2420_T1.customMock(service: service) }
		        }
		        let t1Builder = Instantiator<S2420_T1>(__safeDI_t1Builder)
		        return S2420_T0(t6: t6, t2: t2, anyT1: anyT1, t1Builder: t1Builder, service: service)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_makesSiblingsTypeReceiveTheOtherSibling_forSeed4224() async throws {
		// `Root0` instantiates `t1: T1` and `t2: T2`. `T1` renames `t2` by its optional form only if available;
		// `Link0`, which only `T1` instantiates, renames that alias as required – a chain through a child scope; `Link1`,
		// which only `Link0` instantiates, renames the second alias only if available; and `Link2` receives the third only
		// if available. So `t2` must be built before `t1`, and `T2` renames `t1`, which it receives, so it cannot be: the
		// tool rejects the graph with the dependency cycle at that rename.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 4_224)

		#expect(Self.propertyDeclarations(of: "S4224_Root0", in: fixture).prefix(2) == [
			"@Instantiated let t1: S4224_T1",
			"@Instantiated let t2: S4224_T2",
		])
		#expect(Self.propertyDeclarations(of: "S4224_T1", in: fixture).suffix(2) == [
			"@Received(fulfilledByDependencyNamed: \"t2\", ofType: S4224_T2?.self, onlyIfAvailable: true) let t2Alias: S4224_T2?",
			"@Instantiated let link0: S4224_Link0",
		])
		#expect(Self.propertyDeclarations(of: "S4224_Link0", in: fixture) == [
			"@Received(fulfilledByDependencyNamed: \"t2Alias\", ofType: S4224_T2?.self) let t2AliasAlias: S4224_T2?",
			"@Instantiated let link1: S4224_Link1",
		])
		#expect(Self.propertyDeclarations(of: "S4224_Link1", in: fixture) == [
			"@Received(fulfilledByDependencyNamed: \"t2AliasAlias\", ofType: S4224_T2?.self, onlyIfAvailable: true) let t2AliasAliasAlias: S4224_T2?",
			"@Instantiated let link2: S4224_Link2",
		])
		#expect(Self.propertyDeclarations(of: "S4224_T2", in: fixture).last == "@Received(fulfilledByDependencyNamed: \"t1\", ofType: S4224_T1.self) let t1Alias: S4224_T1")
		let result = try #require(try await smokeResults.value.first { $0.fixture.seed == 4_224 })
		#expect(result.failure == nil)
		#expect(Self.diagnostics(of: result.outcome) == "S4224_T2.swift:9:2: error: Dependency cycle: @Instantiated `t1: S4224_T1` -> @Received `t2: S4224_T2?` -> @Received `t1: S4224_T1`. `t1: S4224_T1` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.")
	}

	// MARK: Mock passed a label above an alias cycle

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_rejectsMockPassedLabelThatScopeDeclaresAgainAboveAliasCycle_forSeed466() async throws {
		// No root reaches the tree. `PassedLabelHost`'s mock promotes `PassedLabelScope` and is passed `passedTracker:
		// PassedLabelTracker?`, which `PassedLabelReader` receives only if available. The scope declares `passedTracker`
		// again and builds `PassedLabelSibling`, whose alias of the tracker `PassedLabelLeaf` requires, so the tracker must
		// be built before the sibling, while the tracker receives the sibling. Beneath the scope the alias names the
		// scope's tracker, never the value the mock is passed, so the mock reports the cycle. The alias names the tracker's
		// own type here; seed 378 spells it with its optional form.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 466)

		#expect(Self.propertyDeclarations(of: "S466_PassedLabelHost", in: fixture) == [
			"@Instantiated let passedLabelReader: S466_PassedLabelReader",
			"@Received let passedLabelScope: S466_PassedLabelScope",
		])
		#expect(Self.propertyDeclarations(of: "S466_PassedLabelReader", in: fixture) == [
			"@Received(onlyIfAvailable: true) let passedTracker: S466_PassedLabelTracker?",
		])
		#expect(Self.propertyDeclarations(of: "S466_PassedLabelScope", in: fixture) == [
			"@Instantiated let passedSibling: S466_PassedLabelSibling",
			"@Instantiated let passedTracker: S466_PassedLabelTracker",
		])
		#expect(Self.propertyDeclarations(of: "S466_PassedLabelTracker", in: fixture) == [
			"@Received let passedSibling: S466_PassedLabelSibling",
		])
		#expect(Self.propertyDeclarations(of: "S466_PassedLabelSibling", in: fixture) == [
			"@Received(fulfilledByDependencyNamed: \"passedTracker\", ofType: S466_PassedLabelTracker.self, onlyIfAvailable: true) let passedTrackerAlias: S466_PassedLabelTracker?",
			"@Instantiated let passedLeaf: S466_PassedLabelLeaf",
		])
		#expect(Self.propertyDeclarations(of: "S466_PassedLabelLeaf", in: fixture) == [
			"@Received let passedTrackerAlias: S466_PassedLabelTracker?",
		])
		#expect(GraphFuzzerFeature.features(of: fixture).contains(.onlyIfAvailableAliasBeneathLabelAMockIsPassed))
		let result = try #require(try await smokeResults.value.first { $0.fixture.seed == 466 })
		#expect(result.failure == nil)
		#expect(Self.diagnostics(of: result.outcome) == "S466_PassedLabelTracker.swift:7:2: error: Dependency cycle: @Instantiated `passedSibling: S466_PassedLabelSibling` -> @Received `passedTracker: S466_PassedLabelTracker` -> @Received `passedSibling: S466_PassedLabelSibling`. `passedSibling: S466_PassedLabelSibling` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_rejectsMockPassedLabelThatScopeDeclaresAgainAboveAliasOfOptionalFormCycle_forSeed378() async throws {
		// Seed 466's cycle, with the alias spelled with the tracker's optional form (`ofType: PassedLabelTracker?.self`).
		// 2.2.0 accepted this graph and generated a mock whose leaf reads `passedTrackerAlias`, which nothing binds, so it
		// did not compile ("cannot find 'passedTrackerAlias' in scope").
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 378)

		#expect(Self.propertyDeclarations(of: "S378_PassedLabelHost", in: fixture) == [
			"@Instantiated let passedLabelReader: S378_PassedLabelReader",
			"@Received let passedLabelScope: S378_PassedLabelScope",
		])
		#expect(Self.propertyDeclarations(of: "S378_PassedLabelReader", in: fixture) == [
			"@Received(onlyIfAvailable: true) let passedTracker: S378_PassedLabelTracker?",
		])
		#expect(Self.propertyDeclarations(of: "S378_PassedLabelScope", in: fixture) == [
			"@Instantiated let passedTracker: S378_PassedLabelTracker",
			"@Instantiated let passedSibling: S378_PassedLabelSibling",
		])
		#expect(Self.propertyDeclarations(of: "S378_PassedLabelTracker", in: fixture) == [
			"@Received let passedSibling: S378_PassedLabelSibling",
		])
		#expect(Self.propertyDeclarations(of: "S378_PassedLabelSibling", in: fixture) == [
			"@Received(fulfilledByDependencyNamed: \"passedTracker\", ofType: S378_PassedLabelTracker?.self, onlyIfAvailable: true) let passedTrackerAlias: S378_PassedLabelTracker?",
			"@Instantiated let passedLeaf: S378_PassedLabelLeaf",
		])
		#expect(Self.propertyDeclarations(of: "S378_PassedLabelLeaf", in: fixture) == [
			"@Received let passedTrackerAlias: S378_PassedLabelTracker?",
		])
		#expect(GraphFuzzerFeature.features(of: fixture).contains(.onlyIfAvailableAliasBeneathLabelAMockIsPassed))
		let result = try #require(try await smokeResults.value.first { $0.fixture.seed == 378 })
		#expect(result.failure == nil)
		#expect(Self.diagnostics(of: result.outcome) == "S378_PassedLabelLeaf.swift:7:2: error: Dependency cycle: @Instantiated `passedTracker: S378_PassedLabelTracker` -> @Received `passedSibling: S378_PassedLabelSibling` -> @Received `passedTracker: S378_PassedLabelTracker?` -> @Received `passedTracker: S378_PassedLabelTracker`. `passedTracker: S378_PassedLabelTracker` is received while it is still being instantiated. `passedTrackerAlias: S378_PassedLabelTracker?` renames `passedTracker: S378_PassedLabelTracker?` only if available, so a type that receives `passedTrackerAlias` without `onlyIfAvailable` must be built after `passedTracker: S378_PassedLabelTracker?`. Receive `passedTrackerAlias` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `passedTracker: S378_PassedLabelTracker?` cannot be built first.")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_bindsAliasBeneathScopeToScopesOwnTracker_whenMockIsPassedTheLabelTheScopeDeclaresAgain_forSeed99() async throws {
		// `PassedLabelHost` instantiates `PassedLabelScope`, which declares `passedTracker`, and `PassedLabelReader`, which
		// receives `passedTracker: PassedLabelTracker?` only if available, so the mock takes it. The tracker receives
		// nothing, so the scope builds it first, and the alias `PassedLabelSibling` declares, which `PassedLabelLeaf`
		// requires, is the scope's tracker, not the value the mock is passed; the smoke batch compiles the mock.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 99)

		#expect(Self.propertyDeclarations(of: "S99_PassedLabelHost", in: fixture) == [
			"@Instantiated let passedLabelScope: S99_PassedLabelScope",
			"@Instantiated let passedLabelReader: S99_PassedLabelReader",
		])
		#expect(Self.propertyDeclarations(of: "S99_PassedLabelReader", in: fixture) == [
			"@Received(onlyIfAvailable: true) let passedTracker: S99_PassedLabelTracker?",
		])
		#expect(Self.propertyDeclarations(of: "S99_PassedLabelScope", in: fixture) == [
			"@Instantiated let passedTracker: S99_PassedLabelTracker",
			"@Instantiated let passedSibling: S99_PassedLabelSibling",
		])
		#expect(Self.propertyDeclarations(of: "S99_PassedLabelTracker", in: fixture) == [])
		#expect(Self.propertyDeclarations(of: "S99_PassedLabelSibling", in: fixture) == [
			"@Received(fulfilledByDependencyNamed: \"passedTracker\", ofType: S99_PassedLabelTracker?.self, onlyIfAvailable: true) let passedTrackerAlias: S99_PassedLabelTracker?",
			"@Instantiated let passedLeaf: S99_PassedLabelLeaf",
		])
		#expect(Self.propertyDeclarations(of: "S99_PassedLabelLeaf", in: fixture) == [
			"@Received let passedTrackerAlias: S99_PassedLabelTracker?",
		])
		#expect(GraphFuzzerFeature.features(of: fixture).contains(.onlyIfAvailableAliasBeneathLabelAMockIsPassed))
		let result = try #require(try await smokeResults.value.first { $0.fixture.seed == 99 })
		#expect(result.failure == nil)
		#expect(Self.generatedFiles(of: result.outcome)["S99_PassedLabelHost+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension S99_PassedLabelHost {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            passedLabelScope: S99_PassedLabelScope.SafeDIMockConfiguration = .init(),
		            passedLabelReader: ((S99_PassedLabelTracker?) -> S99_PassedLabelReader)? = nil,
		            passedTracker: S99_PassedLabelTracker? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                passedLabelScope: passedLabelScope,
		                passedLabelReader: passedLabelReader
		            )
		            self.passedTracker = passedTracker
		        }

		        var passedLabelScope: S99_PassedLabelScope.SafeDIMockConfiguration { __safeDI_storage.passedLabelScope }
		        var passedLabelReader: ((S99_PassedLabelTracker?) -> S99_PassedLabelReader)? { __safeDI_storage.passedLabelReader }
		        let passedTracker: S99_PassedLabelTracker?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                passedLabelScope: S99_PassedLabelScope.SafeDIMockConfiguration,
		                passedLabelReader: ((S99_PassedLabelTracker?) -> S99_PassedLabelReader)?
		            ) {
		                self.passedLabelScope = passedLabelScope
		                self.passedLabelReader = passedLabelReader
		            }

		            let passedLabelScope: S99_PassedLabelScope.SafeDIMockConfiguration
		            let passedLabelReader: ((S99_PassedLabelTracker?) -> S99_PassedLabelReader)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> S99_PassedLabelHost {
		        let passedTracker: S99_PassedLabelTracker? = safeDIOverrides.passedTracker
		        func __safeDI_passedLabelScope() -> S99_PassedLabelScope {
		            let passedTracker = if let safeDIBuilder = safeDIOverrides.passedLabelScope.passedTracker { safeDIBuilder() } else { S99_PassedLabelTracker() }
		            func __safeDI_passedSibling() -> S99_PassedLabelSibling {
		                #sourceLocation(file: "S99_PassedLabelSibling.swift", line: 8)
		                let passedTrackerAlias: S99_PassedLabelTracker? = passedTracker
		                #sourceLocation()
		                let passedLeaf = if let safeDIBuilder = safeDIOverrides.passedLabelScope.passedSibling.passedLeaf { safeDIBuilder(passedTrackerAlias) } else { S99_PassedLabelLeaf(passedTrackerAlias: passedTrackerAlias) }
		                return if let safeDIBuilder = safeDIOverrides.passedLabelScope.passedSibling.safeDIBuilder { safeDIBuilder(passedTrackerAlias, passedLeaf) } else { S99_PassedLabelSibling(passedTrackerAlias: passedTrackerAlias, passedLeaf: passedLeaf) }
		            }
		            let passedSibling: S99_PassedLabelSibling = __safeDI_passedSibling()
		            return if let safeDIBuilder = safeDIOverrides.passedLabelScope.safeDIBuilder { safeDIBuilder(passedTracker, passedSibling) } else { S99_PassedLabelScope(passedTracker: passedTracker, passedSibling: passedSibling) }
		        }
		        let passedLabelScope: S99_PassedLabelScope = __safeDI_passedLabelScope()
		        let passedLabelReader = if let safeDIBuilder = safeDIOverrides.passedLabelReader { safeDIBuilder(passedTracker) } else { S99_PassedLabelReader(passedTracker: passedTracker) }
		        return S99_PassedLabelHost(passedLabelScope: passedLabelScope, passedLabelReader: passedLabelReader)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_lowersHandWrittenMockArgumentsByLabel_forSeed1155() async throws {
		// A `customMock` whose argument takes a dependency the generated mock passes it by label. Stage D1's lowering once
		// matched the argument by label and type, left the argument out.
		try await Self.expectRollPasses(forSeed: 1_155)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_lowersHandWrittenMockArgumentsByLabel_forSeed1341() async throws {
		// `T3`'s `customMock(t1Builder:t3:)` takes `t3`, the `S1341_T3` the type receives under its own label, which the
		// generated mock passes `t3: t3`. Stage D1's lowering once left that argument out.
		try await Self.expectRollPasses(forSeed: 1_341)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_lowersPublicMockPassingNodeToOptionalFormItsTypeReceivesOnlyIfAvailable_forSeed137() async throws {
		// `T1`, whose public mock binds `badge: S137_Badge`, receives `badge: S137_Badge?` only if available, which the root
		// is passed `badge: badge`. Stage D1's lowering once passed a public mock's root no node's optional form.
		try await Self.expectRollPasses(forSeed: 137, features: [.generateMockPublic])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_lowersMockPassingNodeToOptionalFormItsTypeRequires_forSeed1095() async throws {
		// `T3` requires `t2BuilderAlias: Instantiator<S1095_T2>?`, which its mock's root binds non-optional and passes
		// `t2BuilderAlias: t2BuilderAlias`. Stage D1's lowering once passed a root a binding's optional form only where the
		// root received it only if available.
		try await Self.expectRollPasses(forSeed: 1_095)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_lowersMockBuildingByValueTypeThatForwardsValues_forSeed907() async throws {
		// The remedy oracle's graph forwards `lazyAnyT4` on `T1`, which `T0` builds by value as `AnyT1`, a graph production
		// rejects; its mocks pass the value by name from the scope. Stage D1's lowering once left such a node unsupported.
		try await Self.expectRollPasses(forSeed: 907)
	}

	/// Expects `seed`'s graph, drawn with `features`, to pass every oracle but its corpus's known issues of the seed, as
	/// the long run judges it: a roll of a shape stage D1's lowering of mocks once generated otherwise than the mock
	/// emitter it replaced.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func expectRollPasses(forSeed seed: UInt64, features: Set<GraphFuzzerGeneratorFeature> = []) async throws {
		let knownIssue = corpus(for: features).knownIssues.first { $0.seeds.contains(seed) }
		for result in try await GraphFuzzerOracle.results(forSeeds: [seed], features: features) {
			for finding in GraphFuzzerFinding.findings(failure: result.failure, laterFailures: result.laterFailures, knownIssue: knownIssue, retentionIsJudged: result.isJudgedForRetention) {
				record(finding, fixture: result.fixture)
			}
		}
	}

	@Test
	func fixture_drawsMockOnlyExtensionBeforeMockedStructServiceThatTypesReceive_forSeed0() {
		// Every root instantiates `Service`, a `struct` with `generateMock: true` in a mixed graph, and `T0` and `T2`
		// receive it. Its `mockOnly` extension, under `#if DEBUG` before its production declaration, names `preview()`
		// with `customMockName`, since the module generates `Service`'s `mock()`.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 0)

		#expect(fixture.swiftFileContent.contains("""
		#if DEBUG
		@Instantiable(mockOnly: true, customMockName: "preview")
		extension S0_Service {
			public static func preview() -> S0_Service {
				S0_Service()
			}
		}
		#endif

		@Instantiable(generateMock: true)
		public struct S0_Service: Instantiable, Sendable {
			public init() {}
		}

		"""))
		for rootName in ["S0_Root0", "S0_Root1", "S0_Root2"] {
			#expect(Self.propertyDeclarations(of: rootName, in: fixture).last == "@Instantiated let service: S0_Service")
		}
		for receiverName in ["S0_T0", "S0_T2"] {
			#expect(Self.propertyDeclarations(of: receiverName, in: fixture).last == "@Received let service: S0_Service")
		}
	}

	@Test
	func fixture_drawsMemberMocksUnderMockCondition_forSeed6() {
		// `T2`, which another type instantiates, declares a `mock` that takes every parameter of its initializer and passes
		// it on; `T4`, whose `mock()` is generated, declares such a mock named apart, with `customMockName`.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 6)
		let source = fixture.description

		#expect(source.contains("""
			@Received let t4BuilderAlias: Instantiator<S6_T4>
			@Instantiated let t3: S6_Unbuildable1

			#if DEBUG
			public static func mock(t0: S6_T0?, t5Builder: Instantiator<S6_T5>, t4BuilderAlias: Instantiator<S6_T4>, t3: S6_Unbuildable1) -> S6_T2 {
				S6_T2(t0: t0, t5Builder: t5Builder, t4BuilderAlias: t4BuilderAlias, t3: t3)
			}
			#endif
		}
		"""))
		#expect(source.contains("""
		@Instantiable(generateMock: true, customMockName: "customMock")
		public final class S6_T4: Instantiable, S6_T4Protocol {
		"""))
		#expect(source.contains("""
			@Forwarded let t2: S6_T2?

			#if DEBUG
			public static func customMock(t2: S6_T2?) -> S6_T4 {
				S6_T4(t2: t2)
			}
			#endif
		}
		"""))
	}

	@Test
	func fixture_listsInAdditionalMocksToGenerateOnlyATypeWithoutGeneratedOrMemberMock_forSmokeSeeds() {
		// The macro accepts `customMockName` only beside `generateMock: true` or `mockOnly: true`, and the tool rejects a
		// member `mock` on a listed type, so a listed type has neither; the listing is in the first root's file.
		var listedSeedCount = 0
		for seed in Self.smokeSeeds {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed)
			guard let listing = fixture.swiftFileContent[0].split(separator: "\n").first(where: { $0.hasPrefix("#SafeDIConfiguration(additionalMocksToGenerate: [") }) else { continue }
			listedSeedCount += 1
			let typeName = String(listing.split(separator: "\"")[1])
			let typeSource = fixture.swiftFileContent.first { $0.contains("final class \(typeName): ") } ?? ""
			#expect(typeSource.contains("@Instantiable\npublic final class \(typeName): "), "\(seed)")
			#expect(!typeSource.contains("-> \(typeName) {"), "\(seed)")
		}
		#expect(listedSeedCount >= 2)
	}

	/// The properties the type named `typeName` declares in `fixture`, each as `<attribute> let <label>: <type>`.
	private static func propertyDeclarations(of typeName: String, in fixture: GraphFuzzerFixture) -> [String] {
		var currentTypeName = ""
		return fixture.swiftFileContent.flatMap(GraphFuzzerSourceLine.lines(of:)).compactMap { line in
			switch line {
			case let .typeDeclaration(name):
				currentTypeName = name
				return nil
			case let .property(attribute, label, type):
				return currentTypeName == typeName ? "\(attribute) let \(label): \(type)" : nil
			case .instantiableAttribute, .instantiateMethod, .other:
				return nil
			}
		}
	}

	/// The files the tool generated, with each path to a fixture file reduced to the file's name, which is the same on
	/// every machine.
	private static func generatedFiles(of outcome: GraphFuzzerToolOutcome) -> [String: String] {
		switch outcome {
		case let .accepted(generatedFiles, _):
			generatedFiles.mapValues(GraphFuzzerRenaming.reducingFixturePathsToFileNames(in:))
		case .rejected:
			[:]
		}
	}

	/// The tool's diagnostics, with each path to a fixture file reduced to the file's name.
	private static func diagnostics(of outcome: GraphFuzzerToolOutcome) -> String? {
		switch outcome {
		case .accepted:
			nil
		case let .rejected(diagnostics):
			GraphFuzzerRenaming.reducingFixturePathsToFileNames(in: diagnostics)
		}
	}

	@Test
	func renaming_restoresTypeNamesItMovesAcrossWrapperNames_whenItAlsoReversesEveryOrder() throws {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			"@Instantiable\npublic final class S12_T1: Instantiable {\n\tpublic init(t2: S12_T2) {\n\t\tself.t2 = t2\n\t}\n\n\t@Instantiated let t2: S12_T2\n}\n",
			"@Instantiable\npublic final class S12_T2: Instantiable {\n\tpublic init() {}\n}\n",
		])
		let renaming = GraphFuzzerRenaming(reversesTypeNames: true, reversesLabels: true, reversesFileNames: true, movesTypeNamesAcrossWrapperNames: true)

		let fileNames = try #require(renaming.fileNames(of: fixture.renamed(by: renaming)))

		// `S12_T1` and `S12_T2` become `S12_T8` and `S12_T7`, which move to `A12_T8` and `Z12_T7`.
		#expect(fileNames == ["F98_Z12_T7.swift", "F99_A12_T8.swift"])
		#expect(renaming.restore("/tmp/<fixture-directory>/F99_A12_T8.swift:7:2: error: `t7: Z12_T7`", typeNamePrefix: fixture.typeNamePrefix) == "/tmp/<fixture-directory>/S12_T1.swift:7:2: error: `t2: S12_T2`")
	}

	@Test
	func renaming_reversesFileOrder_andRestoresFileNames() throws {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			"@Instantiable\npublic final class S12_T1: Instantiable {\n\tpublic init() {}\n}\n",
			"@Instantiable\npublic final class S12_T0: Instantiable {\n\tpublic init() {}\n}\n",
		])
		let renaming = GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: false, reversesFileNames: true)

		let fileNames = try #require(renaming.fileNames(of: fixture))

		#expect(fileNames == ["F98_S12_T1.swift", "F99_S12_T0.swift"])
		#expect(renaming.restore("/tmp/<fixture-directory>/F98_S12_T1.swift:1:1: error", typeNamePrefix: fixture.typeNamePrefix) == "/tmp/<fixture-directory>/S12_T1.swift:1:1: error")
	}

	@Test
	func renaming_reversesFileOrderAndRestoresFileNames_whenGraphHoldsMoreThanAHundredFiles() throws {
		// A seam corpus graph of the gating draws holds more than a hundred files, whose prefixes take a third digit, so
		// that each has one width and sorts as its number does.
		let typeNames = (0..<120).map { index in "S12_Node" + String(repeating: "0", count: 3 - String(index).count) + String(index) }
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: typeNames.map { "@Instantiable\npublic final class \($0): Instantiable {\n\tpublic init() {}\n}\n" })
		let renaming = GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: false, reversesFileNames: true)

		let fileNames = try #require(renaming.fileNames(of: fixture))

		#expect(fileNames.first == "F999_S12_Node000.swift")
		#expect(fileNames.last == "F880_S12_Node119.swift")
		#expect(fileNames.sorted() == fileNames.reversed())
		#expect(renaming.restore("/tmp/<fixture-directory>/F880_S12_Node119.swift:1:1: error", typeNamePrefix: fixture.typeNamePrefix) == "/tmp/<fixture-directory>/S12_Node119.swift:1:1: error")
	}

	@Test
	func renamedGraphFailures_reportCodeThatDiffers_butNotDiagnosticsInAnotherOrder() {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [])
		let renaming = GraphFuzzerRenaming.all[0]
		let diagnostics = GraphFuzzerToolOutcome.rejected(diagnostics: "/a/<fixture-directory>/S12_T0.swift:1:1: error: first\n/a/<fixture-directory>/S12_T1.swift:1:1: error: second")
		let reorderedDiagnostics = GraphFuzzerToolOutcome.rejected(diagnostics: "/b/<fixture-directory>/S12_T1.swift:1:1: error: second\n/b/<fixture-directory>/S12_T0.swift:1:1: error: first")
		let code = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S12_T0+SafeDIMock.swift": "let a = 1\nlet b = 2\n"], warnings: [])
		let reorderedCode = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S12_T0+SafeDIMock.swift": "let b = 2\nlet a = 1\n"], warnings: [])

		let diagnosticFailures = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: diagnostics, secondOutcome: diagnostics, renamedOutcomes: [(renaming, reorderedDiagnostics)]).renamedGraphFailures
		let codeFailures = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: code, secondOutcome: code, renamedOutcomes: [(renaming, reorderedCode)]).renamedGraphFailures

		#expect(diagnosticFailures == [])
		#expect(codeFailures.map { $0.details.prefix { $0 != "\n" } } == ["Reversing its type names changes its generated mock code, in S12_T0+SafeDIMock.swift."])
	}

	@Test
	func differences_reportEveryGeneratedFileThatDiffers_whenMoreThanOneFileDiffers() {
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S12_Root0+SafeDI.swift": "let a = 1\n", "S12_T0+SafeDIMock.swift": "let b = 1\n", "S12_T1+SafeDIMock.swift": "let c = 1\n", "SafeDIMockConfiguration.swift": "let d = 1\n"], warnings: [])
		let otherOutcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S12_Root0+SafeDI.swift": "let a = 2\n", "S12_T0+SafeDIMock.swift": "let b = 2\n", "S12_T1+SafeDIMock.swift": "let c = 1\n", "SafeDIMockConfiguration.swift": "let d = 2\n"], warnings: [])

		#expect(GraphFuzzerToolOutcome.differences(between: outcome, and: otherOutcome) == [
			GraphFuzzerOutcomeDifference(aspect: .dependencyTreeCode, fileName: "S12_Root0+SafeDI.swift"),
			GraphFuzzerOutcomeDifference(aspect: .mockCode, fileName: "S12_T0+SafeDIMock.swift"),
			GraphFuzzerOutcomeDifference(aspect: .mockConfigurationCode, fileName: "SafeDIMockConfiguration.swift"),
		])
	}

	@Test
	func differences_reportWarnings_whenAGeneratedFileAlsoDiffers() {
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S12_T0+SafeDIMock.swift": "let a = 1\n"], warnings: ["first"])
		let otherOutcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S12_T0+SafeDIMock.swift": "let a = 2\n"], warnings: ["second"])

		#expect(GraphFuzzerToolOutcome.differences(between: outcome, and: otherOutcome) == [
			GraphFuzzerOutcomeDifference(aspect: .mockCode, fileName: "S12_T0+SafeDIMock.swift"),
			GraphFuzzerOutcomeDifference(aspect: .warnings),
		])
	}

	@Test
	func differences_compareFilesBothOutcomesGenerate_whenTheirFileNamesDiffer() {
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S12_T0+SafeDIMock.swift": "let a = 1\n", "S12_T1+SafeDIMock.swift": "let b = 1\n"], warnings: [])
		let otherOutcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S12_T0+SafeDIMock.swift": "let a = 2\n", "S12_T2+SafeDIMock.swift": "let b = 1\n"], warnings: [])

		#expect(GraphFuzzerToolOutcome.differences(between: outcome, and: otherOutcome) == [
			GraphFuzzerOutcomeDifference(aspect: .generatedFileNames),
			GraphFuzzerOutcomeDifference(aspect: .mockCode, fileName: "S12_T0+SafeDIMock.swift"),
		])
	}

	@Test
	func differences_isEmpty_whenAGeneratedFileDiffersOnlyInTheOrderOfItsExtensions() {
		let first = "extension S12_T0 {\n    static let a = 1\n}\n"
		let second = "extension S12_T1 {\n    static let b = 1\n}\n"
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["SafeDIMockConfiguration.swift": "#if DEBUG\n\(first)\n\(second)#endif\n"], warnings: [])
		let otherOutcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["SafeDIMockConfiguration.swift": "#if DEBUG\n\(second)\n\(first)#endif\n"], warnings: [])

		#expect(GraphFuzzerToolOutcome.differences(between: outcome, and: otherOutcome, comparingCode: .inAnyOrderOfExtensions) == [])
	}

	@Test
	func differences_reportFile_whenExtensionsInAnotherOrderAlsoDifferInTheirContents() {
		let first = "extension S12_T0 {\n    static let a = 1\n}\n"
		let second = "extension S12_T1 {\n    static let b = 1\n}\n"
		let changedFirst = "extension S12_T0 {\n    static let a = 2\n}\n"
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["SafeDIMockConfiguration.swift": "\(first)\n\(second)"], warnings: [])
		let otherOutcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["SafeDIMockConfiguration.swift": "\(second)\n\(changedFirst)"], warnings: [])

		#expect(GraphFuzzerToolOutcome.differences(between: outcome, and: otherOutcome, comparingCode: .inAnyOrderOfExtensions) == [GraphFuzzerOutcomeDifference(aspect: .mockConfigurationCode, fileName: "SafeDIMockConfiguration.swift")])
	}

	@Test
	func differences_reportFile_whenAnExtensionMovesAcrossAConditionalCompilationBlock() {
		let first = "extension S12_T0 {\n    static let a = 1\n}\n"
		let second = "extension S12_T1 {\n    static let b = 1\n}\n"
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["SafeDIMockConfiguration.swift": "#if DEBUG\n\(first)#endif\n\(second)"], warnings: [])
		let otherOutcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["SafeDIMockConfiguration.swift": "#if DEBUG\n\(second)#endif\n\(first)"], warnings: [])

		#expect(GraphFuzzerToolOutcome.differences(between: outcome, and: otherOutcome, comparingCode: .inAnyOrderOfExtensions) == [GraphFuzzerOutcomeDifference(aspect: .mockConfigurationCode, fileName: "SafeDIMockConfiguration.swift")])
	}

	@Test
	func renamedGraphFailures_isEmpty_whenOneLineExtensionsDifferOnlyInTheirOrder() {
		#expect(Self.renamedGraphDifferences(betweenCode: "extension S12_T0 {}\n\nextension S12_T1 {}\n", and: "extension S12_T1 {}\n\nextension S12_T0 {}\n") == [])
	}

	@Test
	func renamedGraphFailures_isEmpty_whenPublicConfigurationsDifferOnlyInTheirOrderAndOneHasForwarders() {
		// A public mock's configuration is a struct, a blank line, an extension, and the forwarders right after the extension.
		let withForwarders = "/// Configuration for how `S12_T0` is constructed within the public mock trees of this module.\npublic struct S12_T0Configuration {\n}\n\nextension S12_T0 {\n    static func make() {}\n}\n@usableFromInline nonisolated func first() -> Int? { nil }\n@usableFromInline nonisolated func second() -> Int? { nil }"
		let withoutForwarders = "/// Configuration for how `S12_T1` is constructed within the public mock trees of this module.\npublic struct S12_T1Configuration {\n}\n\nextension S12_T1 {\n    static func make() {}\n}"

		#expect(Self.renamedGraphDifferences(betweenCode: "\(withForwarders)\n\n\(withoutForwarders)\n", and: "\(withoutForwarders)\n\n\(withForwarders)\n") == [])
	}

	@Test
	func renamedGraphFailures_reportFile_whenADeclarationAfterAnExtensionMovesWithItToAnotherPlaceAmongTheExtensions() {
		let first = "extension S12_T0 {\n    static let a = 1\n}\n"
		let second = "extension S12_T1 {\n    static let b = 1\n}\n"

		#expect(Self.renamedGraphDifferences(betweenCode: "\(first)struct Top {}\n\(second)", and: "\(second)\(first)struct Top {}\n") == [.mockConfigurationCode])
	}

	@Test
	func renamedGraphFailures_reportFile_whenACommentAfterAnExtensionMovesWithItToAnotherPlaceAmongTheExtensions() {
		let first = "extension S12_T0 {\n    static let a = 1\n}\n"
		let second = "extension S12_T1 {\n    static let b = 1\n}\n"

		#expect(Self.renamedGraphDifferences(betweenCode: "\(first)// c\n\(second)", and: "\(second)\(first)// c\n") == [.mockConfigurationCode])
	}

	@Test(arguments: [
		("#if DEBUG\nimport A\nimport B\n#endif\n", "#if DEBUG\nimport A\n\nimport B\n#endif\n"),
		("let x = 1\nlet y = 2\n", "let x = 1\n\n\n\nlet y = 2\n"),
		("extension S12_T0 {\n}\n", "extension S12_T0 {\n}   \n"),
		("extension S12_T0 {\n}\n\nextension S12_T1 {\n}\n", "extension S12_T0 {\n}\n\n\n\nextension S12_T1 {\n}\n"),
		("extension S12_T0 {\n}\n", "extension S12_T0 {\n}\n\n"),
	])
	func renamedGraphFailures_reportFile_whenFilesDifferOnlyInBlankLinesOrTrailingWhitespace(code: String, otherCode: String) {
		#expect(Self.renamedGraphDifferences(betweenCode: code, and: otherCode) == [.mockConfigurationCode])
	}

	@Test
	func renamedGraphFailures_isEmpty_whenAPublicConfigurationAndAnExtensionTakeEachOthersPlaces() {
		#expect(Self.renamedGraphDifferences(betweenCode: "\(PublicConfiguration.first)\n\n\(GeneratedExtension.second)", and: "\(GeneratedExtension.second)\n\(PublicConfiguration.first)\n") == [])
	}

	@Test
	func renamedGraphFailures_isEmpty_whenStructsOfPublicConfigurationsWithoutTheirExtensionsDifferOnlyInTheirOrder() {
		// A module's combined output is decomposed into one file per type, which leaves each struct in the configurations' file.
		#expect(Self.renamedGraphDifferences(betweenCode: "\(PublicConfiguration.firstStruct)\n\n\(PublicConfiguration.secondStruct)\n", and: "\(PublicConfiguration.secondStruct)\n\n\(PublicConfiguration.firstStruct)\n") == [])
	}

	@Test
	func renamedGraphFailures_isEmpty_whenStructsOfPublicConfigurationsWithoutTheirExtensionsDifferOnlyInTheirOrderAndOneHasForwarders() {
		// Decomposing a module's combined output files the forwarders of a configuration's defaults after its struct,
		// each a block of its own, so they move with the struct (public mock corpus seeds 2291 and 2877).
		let forwarder = "@usableFromInline nonisolated func __safeDI_FuzzFeature_S12_T1_mockDefault_name() -> String? { S12_T1.__safeDI_mockDefault_name() }"
		#expect(Self.renamedGraphDifferences(betweenCode: "\(PublicConfiguration.firstStruct)\n\n\(PublicConfiguration.secondStruct)\n\n\(forwarder)\n", and: "\(PublicConfiguration.secondStruct)\n\n\(forwarder)\n\n\(PublicConfiguration.firstStruct)\n") == [])
	}

	@Test
	func renamedGraphFailures_reportFile_whenForwarderMovesToAnotherStructOfPublicConfigurationWithoutItsExtension() {
		let forwarder = "@usableFromInline nonisolated func __safeDI_FuzzFeature_S12_T1_mockDefault_name() -> String? { S12_T1.__safeDI_mockDefault_name() }"
		#expect(Self.renamedGraphDifferences(betweenCode: "\(PublicConfiguration.firstStruct)\n\n\(PublicConfiguration.secondStruct)\n\n\(forwarder)\n", and: "\(PublicConfiguration.firstStruct)\n\n\(forwarder)\n\n\(PublicConfiguration.secondStruct)\n") == [.mockConfigurationCode])
	}

	@Test(arguments: [
		// A configuration's struct that takes the place of an extension.
		("\(PublicConfiguration.firstStruct)\n\n\(GeneratedExtension.first)", "\(GeneratedExtension.first)\n\(PublicConfiguration.firstStruct)\n"),
		// Each configuration's struct above the other's extension.
		("\(PublicConfiguration.firstStruct)\n\n\(PublicConfiguration.firstExtension)\n\n\(PublicConfiguration.secondStruct)\n\n\(PublicConfiguration.secondExtension)\n", "\(PublicConfiguration.firstStruct)\n\n\(PublicConfiguration.secondExtension)\n\n\(PublicConfiguration.secondStruct)\n\n\(PublicConfiguration.firstExtension)\n"),
	])
	func renamedGraphFailures_reportFile_whenAPublicConfigurationDoesNotMoveAsOneUnitWithItsExtension(code: String, otherCode: String) {
		#expect(Self.renamedGraphDifferences(betweenCode: code, and: otherCode) == [.mockConfigurationCode])
	}

	@Test(arguments: [
		// A block nested in another with no space after its directive.
		("#if DEBUG\n#if(TEST)\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n#endif\n", "#if DEBUG\n#if(TEST)\n\(GeneratedExtension.second)#endif\n\n#if DEBUG\n\(GeneratedExtension.first)#endif\n#endif\n"),
		// A block nested in another with only its `#if` indented.
		("#if DEBUG\n  #if TEST\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n#endif\n", "#if DEBUG\n  #if TEST\n\(GeneratedExtension.second)#endif\n\n#if DEBUG\n\(GeneratedExtension.first)#endif\n#endif\n"),
		// A block nested in another with its directives indented.
		("#if DEBUG\n  #if TEST\n\(GeneratedExtension.first)  #endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n#endif\n", "#if DEBUG\n  #if TEST\n\(GeneratedExtension.second)  #endif\n\n#if DEBUG\n\(GeneratedExtension.first)#endif\n#endif\n"),
	])
	func renamedGraphFailures_reportFile_whenExtensionsMoveBetweenBlocksOfOtherConditionsHoweverTheirDirectivesAreSpelled(code: String, otherCode: String) {
		#expect(Self.renamedGraphDifferences(betweenCode: code, and: otherCode) == [.mockConfigurationCode])
	}

	@Test(arguments: [
		// An extension on one line with trailing whitespace.
		"extension S12_T0 {}  ",
		// An extension on one line with a trailing comment.
		"extension S12_T0 {} // c",
		// An extension whose closing brace is indented.
		"extension S12_T0 {\n  }",
		// Documentation like a public configuration's, on a declaration that is no struct.
		"/// Configuration for how X",
	])
	func renamedGraphFailures_reportFile_whenADeclarationMovesWithAnExtensionItFollows(firstLines: String) {
		let code = "\(firstLines)\nlet moved = 1\n\(GeneratedExtension.second)\nextension S12_T2 {}\n"
		let otherCode = "extension S12_T2 {}\n\n\(firstLines)\nlet moved = 1\n\(GeneratedExtension.second)"

		#expect(Self.renamedGraphDifferences(betweenCode: code, and: otherCode) == [.mockConfigurationCode])
	}

	@Test
	func renamedGraphFailures_reportFile_whenAnExtensionMovesIntoAnExtensionWhoseFirstLineEndsInABrace() {
		let code = "extension S12_T1 {}\n\nextension S12_T0 { var x: Int { 1 }\n}\n"
		let otherCode = "extension S12_T0 { var x: Int { 1 }\n\nextension S12_T1 {}\n}\n"

		#expect(Self.renamedGraphDifferences(betweenCode: code, and: otherCode) == [.mockConfigurationCode])
	}

	@Test(arguments: [
		("let s = \"\"\"\nextension S12_T0 {}\n\nextension S12_T1 {}\n\"\"\"\n", "let s = \"\"\"\nextension S12_T1 {}\n\nextension S12_T0 {}\n\"\"\"\n"),
		("/*\nextension S12_T0 {}\n\nextension S12_T1 {}\n*/\n", "/*\nextension S12_T1 {}\n\nextension S12_T0 {}\n*/\n"),
	])
	func renamedGraphFailures_reportFile_whenLinesThatReadAsExtensionsMoveInsideAStringOrAComment(code: String, otherCode: String) {
		#expect(Self.renamedGraphDifferences(betweenCode: code, and: otherCode) == [.mockConfigurationCode])
	}

	@Test(arguments: [
		("let caf\u{E9} = 1\n", "let cafe\u{301} = 1\n"),
		("extension S12_T0 {\n    static let caf\u{E9} = 1\n}\n", "extension S12_T0 {\n    static let cafe\u{301} = 1\n}\n"),
	])
	func renamedGraphFailures_reportFile_whenCodeDiffersOnlyBetweenCanonicallyEquivalentSpellings(code: String, otherCode: String) {
		#expect(Self.renamedGraphDifferences(betweenCode: code, and: otherCode) == [.mockConfigurationCode])
	}

	@Test
	func renamedGraphFailures_reportFile_whenExtensionsMoveInAFileThatDoesNotParse() {
		#expect(Self.renamedGraphDifferences(betweenCode: "#if DEBUG\n\(GeneratedExtension.first)\n\(GeneratedExtension.second)", and: "#if DEBUG\n\(GeneratedExtension.second)\n\(GeneratedExtension.first)") == [.mockConfigurationCode])
	}

	@Test(arguments: [
		// Two blocks of one condition, each with one extension, as a module's combined output holds two roots' configurations.
		("#if DEBUG\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n", "#if DEBUG\n\(GeneratedExtension.second)#endif\n\n#if DEBUG\n\(GeneratedExtension.first)#endif\n"),
		// The same two blocks with no blank line between them.
		("#if DEBUG\n\(GeneratedExtension.first)#endif\n#if DEBUG\n\(GeneratedExtension.second)#endif\n", "#if DEBUG\n\(GeneratedExtension.second)#endif\n#if DEBUG\n\(GeneratedExtension.first)#endif\n"),
		// Each root's block, then the block of the configurations roots share, of which one takes a root's place.
		("#if DEBUG\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n\n#if DEBUG\n\(GeneratedExtension.third)\n\(GeneratedExtension.fourth)#endif\n", "#if DEBUG\n\(GeneratedExtension.third)#endif\n\n#if DEBUG\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.fourth)\n\(GeneratedExtension.second)#endif\n"),
		// Other content a block holds before its extension stays where it is.
		("#if DEBUG\nlet x = 1\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n", "#if DEBUG\nlet x = 1\n\(GeneratedExtension.second)#endif\n\n#if DEBUG\n\(GeneratedExtension.first)#endif\n"),
		// The first clause of a next block with another clause, which is under the same condition as the block before it.
		("#if DEBUG\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#else\nlet x = 1\n#endif\n", "#if DEBUG\n\(GeneratedExtension.second)#endif\n\n#if DEBUG\n\(GeneratedExtension.first)#else\nlet x = 1\n#endif\n"),
		("#if DEBUG\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#elseif TEST\nlet x = 1\n#endif\n", "#if DEBUG\n\(GeneratedExtension.second)#endif\n\n#if DEBUG\n\(GeneratedExtension.first)#elseif TEST\nlet x = 1\n#endif\n"),
		// Blocks of one condition with no space after the directive.
		("#if(DEBUG)\n\(GeneratedExtension.first)#endif\n\n#if(DEBUG)\n\(GeneratedExtension.second)#endif\n", "#if(DEBUG)\n\(GeneratedExtension.second)#endif\n\n#if(DEBUG)\n\(GeneratedExtension.first)#endif\n"),
	])
	func renamedGraphFailures_isEmpty_whenExtensionsTakeEachOthersPlacesInBlocksOfOneCondition(code: String, otherCode: String) {
		#expect(Self.renamedGraphDifferences(betweenCode: code, and: otherCode) == [])
	}

	@Test(arguments: [
		// Blocks with different conditions.
		("#if DEBUG\n\(GeneratedExtension.first)#endif\n\n#if TEST\n\(GeneratedExtension.second)#endif\n", "#if DEBUG\n\(GeneratedExtension.second)#endif\n\n#if TEST\n\(GeneratedExtension.first)#endif\n"),
		// A block and outside any block, after it and before it.
		("#if DEBUG\n\(GeneratedExtension.first)#endif\n\n\(GeneratedExtension.second)", "#if DEBUG\n\(GeneratedExtension.second)#endif\n\n\(GeneratedExtension.first)"),
		("\(GeneratedExtension.first)\n#if DEBUG\n\(GeneratedExtension.second)#endif\n", "\(GeneratedExtension.second)\n#if DEBUG\n\(GeneratedExtension.first)#endif\n"),
		// A block's clauses.
		("#if DEBUG\n\(GeneratedExtension.first)#else\n\(GeneratedExtension.second)#endif\n", "#if DEBUG\n\(GeneratedExtension.second)#else\n\(GeneratedExtension.first)#endif\n"),
		("#if DEBUG\n\(GeneratedExtension.first)#elseif TEST\n\(GeneratedExtension.second)#endif\n", "#if DEBUG\n\(GeneratedExtension.second)#elseif TEST\n\(GeneratedExtension.first)#endif\n"),
		// A block with a clause and the next block of its condition, from the clause and from before it.
		("#if DEBUG\n\(GeneratedExtension.first)#else\n\(GeneratedExtension.second)#endif\n\n#if DEBUG\n\(GeneratedExtension.third)#endif\n", "#if DEBUG\n\(GeneratedExtension.first)#else\n\(GeneratedExtension.third)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n"),
		("#if DEBUG\n\(GeneratedExtension.first)#else\nlet x = 1\n#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n", "#if DEBUG\n\(GeneratedExtension.second)#else\nlet x = 1\n#endif\n\n#if DEBUG\n\(GeneratedExtension.first)#endif\n"),
		// A block whose other content differs.
		("#if DEBUG\nlet x = 1\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n", "#if DEBUG\nlet x = 2\n\(GeneratedExtension.second)#endif\n\n#if DEBUG\n\(GeneratedExtension.first)#endif\n"),
		// A block's other content that moves with an extension.
		("#if DEBUG\n\(GeneratedExtension.first)// c\n#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n", "#if DEBUG\n\(GeneratedExtension.second)#endif\n\n#if DEBUG\n\(GeneratedExtension.first)// c\n#endif\n"),
		// A change inside an extension.
		("#if DEBUG\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n", "#if DEBUG\n\(GeneratedExtension.second)#endif\n\n#if DEBUG\n\(GeneratedExtension.changedFirst)#endif\n"),
		// A change to a block's condition line.
		("#if DEBUG\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n", "#if DEBUG\n\(GeneratedExtension.second)#endif\n\n#if TEST\n\(GeneratedExtension.first)#endif\n"),
		// A block nested in a block of the next block's condition.
		("#if DEBUG\n#if TEST\n\(GeneratedExtension.first)#endif\n#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n", "#if DEBUG\n#if TEST\n\(GeneratedExtension.second)#endif\n#endif\n\n#if DEBUG\n\(GeneratedExtension.first)#endif\n"),
		// A declaration between two blocks of one condition.
		("#if DEBUG\n\(GeneratedExtension.first)#endif\nlet x = 1\n#if DEBUG\n\(GeneratedExtension.second)#endif\n", "#if DEBUG\n\(GeneratedExtension.second)#endif\nlet x = 1\n#if DEBUG\n\(GeneratedExtension.first)#endif\n"),
		// Other blank lines between two blocks of one condition.
		("#if DEBUG\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n", "#if DEBUG\n\(GeneratedExtension.second)#endif\n\n\n#if DEBUG\n\(GeneratedExtension.first)#endif\n"),
		// A clause after the first of the next block, which is not under that block's condition.
		("#if DEBUG\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#else\n\(GeneratedExtension.third)#endif\n", "#if DEBUG\n\(GeneratedExtension.third)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#else\n\(GeneratedExtension.first)#endif\n"),
	])
	func renamedGraphFailures_reportFile_whenExtensionsMoveOtherwiseThanBetweenBlocksOfOneCondition(code: String, otherCode: String) {
		#expect(Self.renamedGraphDifferences(betweenCode: code, and: otherCode) == [.mockConfigurationCode])
	}

	@Test
	func findings_reportKnownIssueStale_whenAListedGraphOnlyMovesAnExtensionBetweenBlocksOfOneCondition() {
		let knownIssue = GraphFuzzerKnownIssue(reason: "An order", signatures: [.renamedGraphDiffers(.mockConfigurationCode)], seeds: [12])

		#expect(Self.findings(
			betweenCode: "#if DEBUG\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n",
			and: "#if DEBUG\n\(GeneratedExtension.second)#endif\n\n#if DEBUG\n\(GeneratedExtension.first)#endif\n",
			knownIssue: knownIssue,
		) == [.staleKnownIssue(knownIssue)])
	}

	@Test
	func findings_reportDifference_whenAnExtensionMovesBetweenBlocksOfOtherConditionsAndNoKnownIssueListsIt() throws {
		let knownIssue = GraphFuzzerKnownIssue(reason: "An order", signatures: [.renamedGraphDiffers(.mockCode)], seeds: [12])

		let findings = Self.findings(
			betweenCode: "#if DEBUG\n\(GeneratedExtension.first)#endif\n\n#if TEST\n\(GeneratedExtension.second)#endif\n",
			and: "#if DEBUG\n\(GeneratedExtension.second)#endif\n\n#if TEST\n\(GeneratedExtension.first)#endif\n",
			knownIssue: knownIssue,
		)

		guard case let .failure(failure) = try #require(findings.first), findings.dropFirst().elementsEqual([.staleRenamedGraphDifference(knownIssue, .mockCode)]) else {
			Issue.record("Expected a failure and the difference its entry lists and it does not show, got \(findings)")
			return
		}
		#expect(failure.renamedGraphDifference == .mockConfigurationCode)
	}

	@Test
	func findings_reportKnownIssue_whenAMoveBetweenBlocksOfOneConditionComesWithAChangeAnEntryDocuments() throws {
		let knownIssue = GraphFuzzerKnownIssue(reason: "A lazy cycle's field", signatures: [.renamedGraphDiffers(.mockConfigurationCode)], seeds: [12])

		let findings = Self.findings(
			betweenCode: "#if DEBUG\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n",
			and: "#if DEBUG\n\(GeneratedExtension.second)#endif\n\n#if DEBUG\n\(GeneratedExtension.changedFirst)#endif\n",
			knownIssue: knownIssue,
		)

		guard case .knownIssue = try #require(findings.first), findings.count == 1 else {
			Issue.record("Expected the known issue, got \(findings)")
			return
		}
	}

	/// What the fuzzer concludes about a renamed graph that generates `otherCode` where the graph generates `code`.
	private static func findings(betweenCode code: String, and otherCode: String, knownIssue: GraphFuzzerKnownIssue?) -> [GraphFuzzerFinding] {
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["SafeDIMockConfiguration.swift": code], warnings: [])
		let renamedOutcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["SafeDIMockConfiguration.swift": otherCode], warnings: [])
		let failures = GraphFuzzerToolRuns(fixture: GraphFuzzerFixture(seed: 12, swiftFileContent: []), firstOutcome: outcome, secondOutcome: outcome, renamedOutcomes: [(GraphFuzzerRenaming.all[0], renamedOutcome)]).renamedGraphFailures
		return GraphFuzzerFinding.findings(failure: failures.first, laterFailures: Array(failures.dropFirst()), knownIssue: knownIssue)
	}

	/// The aspects in which a renamed graph that generates `otherCode` differs from a graph that generates `code`.
	private static func renamedGraphDifferences(betweenCode code: String, and otherCode: String) -> [GraphFuzzerOutcomeDifference.Aspect?] {
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["SafeDIMockConfiguration.swift": code], warnings: [])
		let renamedOutcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["SafeDIMockConfiguration.swift": otherCode], warnings: [])
		return GraphFuzzerToolRuns(fixture: GraphFuzzerFixture(seed: 12, swiftFileContent: []), firstOutcome: outcome, secondOutcome: outcome, renamedOutcomes: [(GraphFuzzerRenaming.all[0], renamedOutcome)])
			.renamedGraphFailures.map(\.renamedGraphDifference)
	}

	@Test
	func readTwinDifference_namesOrderOfExtensions_whenAGeneratedFileDiffersOnlyInTheOrderOfItsExtensions() {
		#expect(Self.readTwinDifference(betweenCode: "extension A {\n}\n\nextension B {\n}\n", and: "extension B {\n}\n\nextension A {\n}\n") == "its generated mock configuration code (the order of its extensions only), in SafeDIMockConfiguration.swift")
	}

	@Test
	func readTwinDifference_namesOrderOfExtensions_whenAnExtensionMovesBetweenBlocksOfOneCondition() {
		#expect(Self.readTwinDifference(betweenCode: "#if DEBUG\n\(GeneratedExtension.first)#endif\n\n#if DEBUG\n\(GeneratedExtension.second)#endif\n", and: "#if DEBUG\n\(GeneratedExtension.second)#endif\n\n#if DEBUG\n\(GeneratedExtension.first)#endif\n") == "its generated mock configuration code (the order of its extensions only), in SafeDIMockConfiguration.swift")
	}

	@Test
	func readTwinDifference_namesFile_whenAGeneratedFileDiffersOnlyInBlankLines() {
		#expect(Self.readTwinDifference(betweenCode: "extension A {\n}\n\nextension B {\n}\n", and: "extension A {\n}\n\n\n\nextension B {\n}\n") == "its generated mock configuration code, in SafeDIMockConfiguration.swift")
	}

	/// How a read twin that generates `twinCode` differs from a graph that generates `code`, or `nil` when it does not.
	private static func readTwinDifference(betweenCode code: String, and twinCode: String) -> String? {
		GraphFuzzerReadTwin(fixture: GraphFuzzerFixture(seed: 12, swiftFileContent: []), declaringModule: nil, unreadTypes: []).difference(
			between: .accepted(generatedFiles: ["SafeDIMockConfiguration.swift": code], warnings: []),
			and: .accepted(generatedFiles: ["SafeDIMockConfiguration.swift": twinCode], warnings: []),
		)
	}

	@Test
	func renamedGraphFailures_reportEachDifferenceAsItsOwnFailure_whenASecondFileAndWarningsDiffer() {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [])
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S12_T0+SafeDIMock.swift": "let a = 1\n", "SafeDIMockConfiguration.swift": "let b = 1\n"], warnings: ["first"])
		let renamedOutcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S12_T0+SafeDIMock.swift": "let a = 2\n", "SafeDIMockConfiguration.swift": "let b = 2\n"], warnings: ["second"])

		let failures = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome, renamedOutcomes: [(GraphFuzzerRenaming.all[0], renamedOutcome)]).renamedGraphFailures

		#expect(failures.map(\.kind) == [.renamedGraphDiffers, .renamedGraphDiffers, .renamedGraphDiffers])
		#expect(failures.map(\.renamedGraphDifference) == [.mockCode, .mockConfigurationCode, .warnings])
		#expect(failures.map { $0.details.prefix { $0 != "\n" } } == [
			"Reversing its type names changes its generated mock code, in S12_T0+SafeDIMock.swift.",
			"Reversing its type names changes its generated mock configuration code, in SafeDIMockConfiguration.swift.",
			"Reversing its type names changes its warnings.",
		])
	}

	/// A type prefix that names no corpus graph, for the fixtures of the tests of a renamed graph's mock difference.
	private static let mockDifferencePrefix = GraphFuzzerFixture.typeNamePrefix(forSeed: 1_000_000_011)

	private static func mockedType(_ name: String, instantiating dependencies: [(label: String, type: String)], receivingOnlyIfAvailable receives: [(label: String, type: String)] = []) -> String {
		let parameters = (dependencies + receives).map { "\($0.label): \($0.type)" }.joined(separator: ", ")
		let assignments = (dependencies + receives).map { "\t\tself.\($0.label) = \($0.label)\n" }.joined()
		let instantiated = dependencies.map { "\t@Instantiated let \($0.label): \($0.type)\n" }.joined()
		let received = receives.map { "\t@Received(onlyIfAvailable: true) let \($0.label): \($0.type)\n" }.joined()
		return "@Instantiable(generateMock: true)\npublic final class \(mockDifferencePrefix)\(name): Instantiable {\n\tpublic init(\(parameters)) {\n\(assignments)\t}\n\(instantiated)\(received)}\n"
	}

	private static func plainType(_ name: String) -> String {
		"@Instantiable\npublic final class \(mockDifferencePrefix)\(name): Instantiable {\n\tpublic init() {}\n}\n"
	}

	/// A mocked type whose mock takes two values only if available, in the order of their labels.
	private static var mockWithTwoLabelsFixture: GraphFuzzerFixture {
		GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			mockedType("T3", instantiating: [], receivingOnlyIfAvailable: [("t4", "\(mockDifferencePrefix)T4?"), ("t5", "\(mockDifferencePrefix)T5?")]),
			plainType("T4"),
			plainType("T5"),
		])
	}

	/// A lazy cycle of two mocked types, whose mocks each drop the back-edge's override, chosen by type name.
	private static var lazyCycleFixture: GraphFuzzerFixture {
		GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			mockedType("T7", instantiating: [("t8Builder", "Instantiator<\(mockDifferencePrefix)T8>")]),
			mockedType("T8", instantiating: [("t7Builder", "Instantiator<\(mockDifferencePrefix)T7>")]),
		])
	}

	/// A lazy cycle whose first mocked type also takes two values only if available, in the order of their labels.
	private static var lazyCycleWithTwoLabelsFixture: GraphFuzzerFixture {
		GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			mockedType("T7", instantiating: [("t8Builder", "Instantiator<\(mockDifferencePrefix)T8>")], receivingOnlyIfAvailable: [("t4", "\(mockDifferencePrefix)T4?"), ("t5", "\(mockDifferencePrefix)T5?")]),
			mockedType("T8", instantiating: [("t7Builder", "Instantiator<\(mockDifferencePrefix)T7>")]),
			plainType("T4"),
			plainType("T5"),
		])
	}

	/// A lazy cycle of two mocked types erased where they are instantiated, the second of which also instantiates an erased leaf.
	private static var lazyCycleOfErasedTypesFixture: GraphFuzzerFixture {
		let prefix = mockDifferencePrefix
		return GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			"@Instantiable(generateMock: true)\npublic final class \(prefix)T7: Instantiable {\n\tpublic init(anyT8Builder: ErasedInstantiator<(), \(prefix)AnyT8>) {\n\t\tself.anyT8Builder = anyT8Builder\n\t}\n\t@Instantiated(fulfilledByType: \"\(prefix)T8\", erasedToConcreteExistential: true) let anyT8Builder: ErasedInstantiator<(), \(prefix)AnyT8>\n}\n",
			"@Instantiable(generateMock: true)\npublic final class \(prefix)T8: Instantiable {\n\tpublic init(anyT7Builder: ErasedInstantiator<(), \(prefix)AnyT7>, anyT4: \(prefix)AnyT4) {\n\t\tself.anyT7Builder = anyT7Builder\n\t\tself.anyT4 = anyT4\n\t}\n\t@Instantiated(fulfilledByType: \"\(prefix)T7\", erasedToConcreteExistential: true) let anyT7Builder: ErasedInstantiator<(), \(prefix)AnyT7>\n\t@Instantiated(fulfilledByType: \"\(prefix)T4\", erasedToConcreteExistential: true) let anyT4: \(prefix)AnyT4\n}\n",
			plainType("T4"),
			"public struct \(prefix)AnyT7 {\n\tpublic init(_ value: some AnyObject) {}\n}\n",
			"public struct \(prefix)AnyT8 {\n\tpublic init(_ value: some AnyObject) {}\n}\n",
			"public struct \(prefix)AnyT4 {\n\tpublic init(_ value: some AnyObject) {}\n}\n",
		])
	}

	/// A tree of mocked types with no cycle: `T0` instantiates `T1` and `T2`, each of which instantiates `T3`.
	private static var plainTreeFixture: GraphFuzzerFixture {
		GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			mockedType("T0", instantiating: [("t1", "\(mockDifferencePrefix)T1"), ("t2", "\(mockDifferencePrefix)T2")]),
			mockedType("T1", instantiating: [("t3", "\(mockDifferencePrefix)T3")]),
			mockedType("T2", instantiating: [("t3", "\(mockDifferencePrefix)T3")]),
			mockedType("T3", instantiating: []),
		])
	}

	/// A mocked type whose mock takes a forwarded value before its overrides.
	private static var mockWithForwardedValueFixture: GraphFuzzerFixture {
		GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			"@Instantiable(generateMock: true)\npublic final class \(mockDifferencePrefix)T6: Instantiable {\n\tpublic init(name: String, t1: \(mockDifferencePrefix)T1) {\n\t\tself.name = name\n\t\tself.t1 = t1\n\t}\n\t@Forwarded let name: String\n\t@Instantiated let t1: \(mockDifferencePrefix)T1\n}\n",
			mockedType("T1", instantiating: [("t3", "\(mockDifferencePrefix)T3")]),
			mockedType("T3", instantiating: []),
		])
	}

	/// A renaming that reorders everything a known reason of a mock's difference depends on, so that it rules neither out.
	private static let reversalOfEveryOrder = GraphFuzzerRenaming(reversesTypeNames: true, reversesLabels: true, reversesFileNames: true)

	/// The differences between `outcome` and the code `edit` makes of its file named `fileName`, as if `renaming` had made them.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func differences(of outcome: GraphFuzzerToolOutcome, editingFileNamed fileName: String, under renaming: GraphFuzzerRenaming = reversalOfEveryOrder, by edit: (String) -> String) -> [GraphFuzzerOutcomeDifference] {
		guard case let .accepted(generatedFiles, warnings) = outcome else {
			Issue.record("The fixture's graph is rejected: \(outcome.description)")
			return []
		}
		var editedFiles = generatedFiles
		editedFiles[fileName] = edit(generatedFiles[fileName, default: ""])
		return GraphFuzzerToolOutcome.differences(between: outcome, and: .accepted(generatedFiles: editedFiles, warnings: warnings), comparingCode: .inAnyOrderOfExtensions, renaming: renaming)
	}

	/// `code` with each `if let safeDIBuilder = <read>… { … } else { <construction> }` replaced by its construction.
	private static func constructingWithoutOverridesRead(by read: String, in code: String) -> String {
		code.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
			guard let condition = line.range(of: "if let safeDIBuilder = \(read)"),
			      let elseBranch = line.range(of: " } else { ", range: condition.upperBound..<line.endIndex)
			else { return String(line) }
			return "\(line[..<condition.lowerBound])\(line[elseBranch.upperBound...].dropLast(2))"
		}.joined(separator: "\n")
	}

	/// `code` with its text from the declaration of its `SafeDIMockConfiguration` on edited by `edit`.
	private static func editingConfigurationStruct(in code: String, by edit: (String) -> String) -> String {
		guard let declaration = code.range(of: "struct SafeDIMockConfiguration") else {
			Issue.record("The code declares no configuration struct: \(code)")
			return code
		}
		return "\(code[..<declaration.lowerBound])\(edit(String(code[declaration.lowerBound...])))"
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func renamedGraphFailures_nameTheOrderOfAMocksParametersAndFields_whenReversingLabelsReordersThem() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.mockWithTwoLabelsFixture, multiModuleRenamings: [])

		#expect(Set(toolRuns.renamedGraphFailures.map(\.renamedGraphDifference)) == [.mockParameterAndFieldOrder])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func renamedGraphFailures_nameThePresenceOfAConfigurationField_whenALazyCycleDropsAFieldByTypeName() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.lazyCycleFixture, multiModuleRenamings: [])

		#expect(Set(toolRuns.renamedGraphFailures.map(\.renamedGraphDifference)) == [.mockConfigurationFieldPresence])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func renamedGraphFailures_nameBothReasonsForOneFile_whenAReversalOfEveryOrderShowsBoth() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.lazyCycleWithTwoLabelsFixture, multiModuleRenamings: [])
		let reversalOfEveryOrder = try #require(toolRuns.renamedOutcomes.first { $0.renaming.reversesTypeNames && $0.renaming.reversesLabels })

		let differences = GraphFuzzerToolOutcome.differences(between: toolRuns.firstOutcome, and: reversalOfEveryOrder.outcome, comparingCode: .inAnyOrderOfExtensions, renaming: reversalOfEveryOrder.renaming)

		#expect(differences.filter { $0.fileName == "\(Self.mockDifferencePrefix)T7+SafeDIMock.swift" }.map(\.aspect) == [.mockParameterAndFieldOrder, .mockConfigurationFieldPresence])
		#expect(Set(toolRuns.renamedGraphFailures.map(\.renamedGraphDifference)) == [.mockParameterAndFieldOrder, .mockConfigurationFieldPresence])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenAMockPassesAnotherValueUnderTheSameLabels() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.mockWithTwoLabelsFixture, renamings: [], multiModuleRenamings: [])
		let construction = "\(Self.mockDifferencePrefix)T3(t4: t4, t5: t5)"

		let differences = Self.differences(of: toolRuns.firstOutcome, editingFileNamed: "\(Self.mockDifferencePrefix)T3+SafeDIMock.swift") { code in
			#expect(code.contains(construction))
			return code.replacingOccurrences(of: construction, with: "\(Self.mockDifferencePrefix)T3(t4: t5, t5: t4)")
		}

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenAFieldThatHoldsNoConfigurationIsAbsent() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.mockWithTwoLabelsFixture, renamings: [], multiModuleRenamings: [])
		let linesOfTheField = ["t5: \(Self.mockDifferencePrefix)T5? = nil,", "t5: \(Self.mockDifferencePrefix)T5? = nil", "self.t5 = t5", "let t5: \(Self.mockDifferencePrefix)T5?", "let t5: \(Self.mockDifferencePrefix)T5? = safeDIOverrides.t5"]

		let differences = Self.differences(of: toolRuns.firstOutcome, editingFileNamed: "\(Self.mockDifferencePrefix)T3+SafeDIMock.swift") { code in
			// The binding that reads the field goes too, or its read alone would differ.
			#expect(code.contains("let t5: \(Self.mockDifferencePrefix)T5? = safeDIOverrides.t5"))
			return code.split(separator: "\n", omittingEmptySubsequences: false)
				.filter { !linesOfTheField.contains($0.trimmingCharacters(in: .whitespaces)) }
				.joined(separator: "\n")
		}

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenAConfigurationFieldChangesItsType() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.lazyCycleFixture, renamings: [], multiModuleRenamings: [])
		let fileName = "\(Self.mockDifferencePrefix)T7+SafeDIMock.swift"
		let fieldType = "\(Self.mockDifferencePrefix)T8.SafeDIMockConfiguration"

		let differences = Self.differences(of: toolRuns.firstOutcome, editingFileNamed: fileName) { code in
			#expect(code.contains(fieldType))
			return code.replacingOccurrences(of: fieldType, with: "\(Self.mockDifferencePrefix)T7.SafeDIMockConfiguration")
		}

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenStatementsThatAreNotParameterBindingsChangePlaces() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.lazyCycleFixture, renamings: [], multiModuleRenamings: [])
		let binding = "        let t8Builder = Instantiator<\(Self.mockDifferencePrefix)T8>(__safeDI_t8Builder)"
		let construction = "        return \(Self.mockDifferencePrefix)T7(t8Builder: t8Builder)"
		var originalLines = [Substring]()
		var editedLines = [Substring]()

		let differences = Self.differences(of: toolRuns.firstOutcome, editingFileNamed: "\(Self.mockDifferencePrefix)T7+SafeDIMock.swift") { code in
			#expect(code.contains("\(binding)\n\(construction)"))
			let edited = code.replacingOccurrences(of: "\(binding)\n\(construction)", with: "\(construction)\n\(binding)")
			originalLines = code.split(separator: "\n")
			editedLines = edited.split(separator: "\n")
			return edited
		}

		// A sort of the lines would call this a reorder of the same content.
		#expect(originalLines.sorted() == editedLines.sorted())
		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenTheConstructionOfADroppedOverridesElseAlsoDiffers() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.lazyCycleFixture, multiModuleRenamings: [])
		let reversalOfTypeNames = try #require(toolRuns.renamedOutcomes.first { $0.renaming.reversesTypeNames && !$0.renaming.reversesLabels && !$0.renaming.reversesFileNames })
		guard case let .accepted(renamedFiles, renamedWarnings) = reversalOfTypeNames.outcome else {
			Issue.record("The fixture's graph is rejected.")
			return
		}
		let fileName = "\(Self.mockDifferencePrefix)T7+SafeDIMock.swift"
		let condition = "if let safeDIBuilder = safeDIOverrides.t8Builder.t7Builder.safeDIBuilder { safeDIBuilder(t8Builder) } else"
		let construction = "\(Self.mockDifferencePrefix)T7(t8Builder: t8Builder)"
		var editedRenamedFiles = renamedFiles
		#expect(renamedFiles[fileName]?.contains("\(condition) { \(construction) }") == true)
		// Only the `else` of the override the first outcome has no field for: the file's other override exists in both outcomes.
		editedRenamedFiles[fileName] = renamedFiles[fileName]?.replacingOccurrences(of: "\(condition) { \(construction) }", with: "\(condition) { Other\(construction) }")

		let differences = GraphFuzzerToolOutcome.differences(between: toolRuns.firstOutcome, and: .accepted(generatedFiles: editedRenamedFiles, warnings: renamedWarnings), comparingCode: .inAnyOrderOfExtensions, renaming: reversalOfTypeNames.renaming)

		#expect(differences.filter { $0.fileName == fileName }.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenAConfigurationFieldOutsideAnyCycleIsAbsent() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.plainTreeFixture, renamings: [], multiModuleRenamings: [])
		let fieldType = "\(Self.mockDifferencePrefix)T2.SafeDIMockConfiguration"
		let otherParameter = "            t1: \(Self.mockDifferencePrefix)T1.SafeDIMockConfiguration = .init()"

		let differences = Self.differences(of: toolRuns.firstOutcome, editingFileNamed: "\(Self.mockDifferencePrefix)T0+SafeDIMock.swift") { code in
			#expect(code.contains("\(otherParameter),\n            t2: \(fieldType) = .init()\n"))
			return Self.constructingWithoutOverridesRead(by: "safeDIOverrides.t2", in: code)
				.replacingOccurrences(of: "\(otherParameter),\n            t2: \(fieldType) = .init()\n", with: "\(otherParameter)\n")
				.replacingOccurrences(of: "            self.t2 = t2\n", with: "")
				.replacingOccurrences(of: "        let t2: \(fieldType)\n", with: "")
		}

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenAConfigurationFieldChangesItsLabel() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.plainTreeFixture, renamings: [], multiModuleRenamings: [])
		let fieldType = "\(Self.mockDifferencePrefix)T2.SafeDIMockConfiguration"

		let differences = Self.differences(of: toolRuns.firstOutcome, editingFileNamed: "\(Self.mockDifferencePrefix)T0+SafeDIMock.swift") { code in
			#expect(code.contains("t2: \(fieldType)"))
			return code
				.replacingOccurrences(of: "t2: \(fieldType)", with: "renamedLabel: \(fieldType)")
				.replacingOccurrences(of: "self.t2 = t2", with: "self.renamedLabel = renamedLabel")
				.replacingOccurrences(of: "safeDIOverrides.t2.", with: "safeDIOverrides.renamedLabel.")
		}

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenAFieldIsReplacedByOneThatConfiguresAnotherChild() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.plainTreeFixture, renamings: [], multiModuleRenamings: [])
		let fieldType = "\(Self.mockDifferencePrefix)T2.SafeDIMockConfiguration"
		let otherFieldType = "\(Self.mockDifferencePrefix)T3.SafeDIMockConfiguration"

		let differences = Self.differences(of: toolRuns.firstOutcome, editingFileNamed: "\(Self.mockDifferencePrefix)T0+SafeDIMock.swift") { code in
			#expect(code.contains("t2: \(fieldType)"))
			return Self.constructingWithoutOverridesRead(by: "safeDIOverrides.t2", in: code)
				.replacingOccurrences(of: "t2: \(fieldType)", with: "otherChild: \(otherFieldType)")
				.replacingOccurrences(of: "self.t2 = t2", with: "self.otherChild = otherChild")
		}

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenAFieldOfALazyCycleChangesItsLabel() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.lazyCycleFixture, renamings: [], multiModuleRenamings: [])
		guard case let .accepted(generatedFiles, warnings) = toolRuns.firstOutcome else {
			Issue.record("The fixture's graph is rejected.")
			return
		}
		let t7FileName = "\(Self.mockDifferencePrefix)T7+SafeDIMock.swift"
		let t8FileName = "\(Self.mockDifferencePrefix)T8+SafeDIMock.swift"
		let t7Configuration = "\(Self.mockDifferencePrefix)T7.SafeDIMockConfiguration"
		let t8Configuration = "\(Self.mockDifferencePrefix)T8.SafeDIMockConfiguration"
		var editedFiles = generatedFiles
		editedFiles[t7FileName] = Self.editingConfigurationStruct(in: generatedFiles[t7FileName, default: ""]) { configuration in
			configuration
				.replacingOccurrences(of: "t8Builder: \(t8Configuration)", with: "renamedLabel: \(t8Configuration)")
				.replacingOccurrences(of: "self.t8Builder = t8Builder", with: "self.renamedLabel = renamedLabel")
		}
		// The other direction of the cycle, so that the two outcomes' structs hold a cycle the renamed field lies on.
		editedFiles[t8FileName] = Self.editingConfigurationStruct(in: generatedFiles[t8FileName, default: ""]) { configuration in
			configuration
				.replacingOccurrences(of: "init(\n            _ safeDIBuilder", with: "init(\n            t7Builder: \(t7Configuration) = .init(),\n            _ safeDIBuilder")
				.replacingOccurrences(of: "            self.safeDIBuilder = safeDIBuilder\n", with: "            self.t7Builder = t7Builder\n            self.safeDIBuilder = safeDIBuilder\n")
				.replacingOccurrences(of: "        /// Overrides how this type", with: "        let t7Builder: \(t7Configuration)\n        /// Overrides how this type")
		}.replacingOccurrences(of: "safeDIOverrides.t7Builder.t8Builder.", with: "safeDIOverrides.t7Builder.renamedLabel.")

		let differences = GraphFuzzerToolOutcome.differences(between: toolRuns.firstOutcome, and: .accepted(generatedFiles: editedFiles, warnings: warnings), comparingCode: .inAnyOrderOfExtensions, renaming: Self.reversalOfEveryOrder)

		#expect(differences.map(\.aspect) == [.mockCode, .mockCode])
	}

	/// The aspects of the difference in `T7`'s mock between the graph of `lazyCycleWithTwoLabelsFixture` and its reversal of
	/// type names, with the body of the reversal's override of the field the graph drops replaced by `body`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func aspectsOfT7sMockWithDroppedOverride(editedTo body: String) async throws -> [GraphFuzzerOutcomeDifference.Aspect] {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: lazyCycleWithTwoLabelsFixture, multiModuleRenamings: [])
		let reversalOfTypeNames = try #require(toolRuns.renamedOutcomes.first { $0.renaming.reversesTypeNames && !$0.renaming.reversesLabels && !$0.renaming.reversesFileNames })
		guard case let .accepted(renamedFiles, renamedWarnings) = reversalOfTypeNames.outcome else {
			Issue.record("The fixture's graph is rejected.")
			return []
		}
		let fileName = "\(mockDifferencePrefix)T7+SafeDIMock.swift"
		let builderCall = "{ safeDIBuilder(t8Builder, t4, t5) }"
		var editedFiles = renamedFiles
		#expect(renamedFiles[fileName]?.contains(builderCall) == true)
		editedFiles[fileName] = renamedFiles[fileName]?.replacingOccurrences(of: builderCall, with: body)
		return GraphFuzzerToolOutcome.differences(between: toolRuns.firstOutcome, and: .accepted(generatedFiles: editedFiles, warnings: renamedWarnings), comparingCode: .inAnyOrderOfExtensions, renaming: reversalOfTypeNames.renaming)
			.filter { $0.fileName == fileName }
			.map(\.aspect)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_namePresence_whenADroppedOverridesBuilderTakesTheArgumentsOfItsConstruction() async throws {
		#expect(try await Self.aspectsOfT7sMockWithDroppedOverride(editedTo: "{ safeDIBuilder(t8Builder, t4, t5) }") == [.mockConfigurationFieldPresence])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenADroppedOverridesBuilderTakesItsArgumentsInAnotherOrder() async throws {
		#expect(try await Self.aspectsOfT7sMockWithDroppedOverride(editedTo: "{ safeDIBuilder(t8Builder, t5, t4) }") == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenADroppedOverrideDoesNotCallItsBuilder() async throws {
		#expect(try await Self.aspectsOfT7sMockWithDroppedOverride(editedTo: "{ fatalError() }") == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_namePresence_whenALazyCycleOfErasedTypesDropsAField() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.lazyCycleOfErasedTypesFixture, multiModuleRenamings: [])
		let reversalOfTypeNames = try #require(toolRuns.renamedOutcomes.first { $0.renaming.reversesTypeNames && !$0.renaming.reversesLabels && !$0.renaming.reversesFileNames })
		let fileName = "\(Self.mockDifferencePrefix)T8+SafeDIMock.swift"
		guard case let .accepted(generatedFiles, _) = toolRuns.firstOutcome else {
			Issue.record("The fixture's graph is rejected.")
			return
		}

		// Beneath the dropped field, an erased node with a configuration struct and an erased leaf.
		#expect(generatedFiles[fileName]?.contains("safeDIOverrides.anyT7Builder.anyT8Builder.safeDIBuilder { \(Self.mockDifferencePrefix)AnyT8(safeDIBuilder(anyT7Builder, anyT4)) }") == true)
		#expect(generatedFiles[fileName]?.contains("safeDIOverrides.anyT7Builder.anyT8Builder.anyT4 { safeDIBuilder() } else { \(Self.mockDifferencePrefix)AnyT4(\(Self.mockDifferencePrefix)T4()) }") == true)
		#expect(Set(GraphFuzzerToolOutcome.differences(between: toolRuns.firstOutcome, and: reversalOfTypeNames.outcome, comparingCode: .inAnyOrderOfExtensions, renaming: reversalOfTypeNames.renaming).map(\.aspect)) == [.mockConfigurationFieldPresence])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenADroppedOverrideErasesItsBuilderWithAnotherEraser() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.lazyCycleOfErasedTypesFixture, multiModuleRenamings: [])
		let reversalOfTypeNames = try #require(toolRuns.renamedOutcomes.first { $0.renaming.reversesTypeNames && !$0.renaming.reversesLabels && !$0.renaming.reversesFileNames })
		guard case let .accepted(generatedFiles, warnings) = toolRuns.firstOutcome else {
			Issue.record("The fixture's graph is rejected.")
			return
		}
		let fileName = "\(Self.mockDifferencePrefix)T8+SafeDIMock.swift"
		let condition = "if let safeDIBuilder = safeDIOverrides.anyT7Builder.anyT8Builder.safeDIBuilder { "
		var editedFiles = generatedFiles
		#expect(generatedFiles[fileName]?.contains("\(condition)\(Self.mockDifferencePrefix)AnyT8(safeDIBuilder(") == true)
		editedFiles[fileName] = generatedFiles[fileName]?.replacingOccurrences(of: "\(condition)\(Self.mockDifferencePrefix)AnyT8(safeDIBuilder(", with: "\(condition)Other\(Self.mockDifferencePrefix)AnyT8(safeDIBuilder(")

		let differences = GraphFuzzerToolOutcome.differences(between: .accepted(generatedFiles: editedFiles, warnings: warnings), and: reversalOfTypeNames.outcome, comparingCode: .inAnyOrderOfExtensions, renaming: reversalOfTypeNames.renaming)

		#expect(differences.filter { $0.fileName == fileName }.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenAConfigurationInitializersBuilderParameterMovesFirst() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.lazyCycleFixture, renamings: [], multiModuleRenamings: [])
		let child = "t8Builder: \(Self.mockDifferencePrefix)T8.SafeDIMockConfiguration = .init()"
		let builder = "_ safeDIBuilder: ((Instantiator<\(Self.mockDifferencePrefix)T8>) -> \(Self.mockDifferencePrefix)T7)? = nil"

		let differences = Self.differences(of: toolRuns.firstOutcome, editingFileNamed: "\(Self.mockDifferencePrefix)T7+SafeDIMock.swift") { code in
			#expect(code.contains("\(child),\n            \(builder)\n"))
			return code.replacingOccurrences(of: "\(child),\n            \(builder)\n", with: "\(builder),\n            \(child)\n")
		}

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenAConfigurationStructsBuilderFieldMovesFirst() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.lazyCycleFixture, renamings: [], multiModuleRenamings: [])
		let child = "        let t8Builder: \(Self.mockDifferencePrefix)T8.SafeDIMockConfiguration\n"
		let builder = "        let safeDIBuilder: ((Instantiator<\(Self.mockDifferencePrefix)T8>) -> \(Self.mockDifferencePrefix)T7)?\n"

		let differences = Self.differences(of: toolRuns.firstOutcome, editingFileNamed: "\(Self.mockDifferencePrefix)T7+SafeDIMock.swift") { code in
			Self.editingConfigurationStruct(in: code) { configuration in
				guard let childRange = configuration.range(of: child), let builderRange = configuration.range(of: builder, range: childRange.upperBound..<configuration.endIndex) else {
					Issue.record("The fields are not where the test expects them: \(configuration)")
					return configuration
				}
				let documentedBuilder = configuration[childRange.upperBound..<builderRange.upperBound]
				return configuration.replacingCharacters(in: childRange.lowerBound..<builderRange.upperBound, with: "\(documentedBuilder)\(child)")
			}
		}

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenAConfigurationInitializersBuilderAssignmentMovesFirst() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.lazyCycleFixture, renamings: [], multiModuleRenamings: [])
		// The initializer hands its storage each field, in the order of its fields.
		let assignments = "                t8Builder: t8Builder,\n                safeDIBuilder: safeDIBuilder\n"

		let differences = Self.differences(of: toolRuns.firstOutcome, editingFileNamed: "\(Self.mockDifferencePrefix)T7+SafeDIMock.swift") { code in
			#expect(code.contains(assignments))
			return code.replacingOccurrences(of: assignments, with: "                safeDIBuilder: safeDIBuilder,\n                t8Builder: t8Builder\n")
		}

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenAMocksOverridesParameterMovesFirst() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.mockWithForwardedValueFixture, renamings: [], multiModuleRenamings: [])
		let parameters = "        name: String,\n        safeDIOverrides: SafeDIOverrides = .init()\n"

		let differences = Self.differences(of: toolRuns.firstOutcome, editingFileNamed: "\(Self.mockDifferencePrefix)T6+SafeDIMock.swift") { code in
			#expect(code.contains(parameters))
			return code.replacingOccurrences(of: parameters, with: "        safeDIOverrides: SafeDIOverrides = .init(),\n        name: String\n")
		}

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	/// The runs of `mockWithTwoLabelsFixture`, given as `toolRuns`, as if `renaming` had swapped the parameters of `T3`'s overrides.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func runsSwappingParametersOfOverrides(of toolRuns: GraphFuzzerToolRuns, under renaming: GraphFuzzerRenaming) -> GraphFuzzerToolRuns {
		guard case let .accepted(generatedFiles, warnings) = toolRuns.firstOutcome else {
			Issue.record("The fixture's graph is rejected.")
			return toolRuns
		}
		let fileName = "\(mockDifferencePrefix)T3+SafeDIMock.swift"
		let t4 = "t4: \(mockDifferencePrefix)T4? = nil"
		let t5 = "t5: \(mockDifferencePrefix)T5? = nil"
		var editedFiles = generatedFiles
		#expect(generatedFiles[fileName]?.contains("\(t4),\n            \(t5)\n") == true)
		editedFiles[fileName] = generatedFiles[fileName]?.replacingOccurrences(of: "\(t4),\n            \(t5)\n", with: "\(t5),\n            \(t4)\n")
		return GraphFuzzerToolRuns(fixture: toolRuns.fixture, firstOutcome: toolRuns.firstOutcome, secondOutcome: toolRuns.firstOutcome, renamedOutcomes: [(renaming, .accepted(generatedFiles: editedFiles, warnings: warnings))])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func renamedGraphFailures_nameTheOrderOfParameters_whenARenamingThatReversesLabelsReordersThem() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.mockWithTwoLabelsFixture, renamings: [], multiModuleRenamings: [])

		for renaming in GraphFuzzerRenaming.all where renaming.reversesLabels {
			#expect(Self.runsSwappingParametersOfOverrides(of: toolRuns, under: renaming).renamedGraphFailures.map(\.renamedGraphDifference) == [.mockParameterAndFieldOrder])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func renamedGraphFailures_nameNeitherReason_whenARenamingThatKeepsLabelsReordersParameters() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.mockWithTwoLabelsFixture, renamings: [], multiModuleRenamings: [])

		for renaming in GraphFuzzerRenaming.all where !renaming.reversesLabels {
			#expect(Self.runsSwappingParametersOfOverrides(of: toolRuns, under: renaming).renamedGraphFailures.map(\.renamedGraphDifference) == [.mockCode])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func renamedGraphFailures_nameThePresenceOfAConfigurationField_whenARenamingThatChangesTypeNamesDropsIt() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.lazyCycleFixture, multiModuleRenamings: [])
		let reversalOfTypeNames = try #require(toolRuns.renamedOutcomes.first { $0.renaming.reversesTypeNames && !$0.renaming.reversesLabels && !$0.renaming.reversesFileNames })

		for renaming in GraphFuzzerRenaming.all where renaming.reversesTypeNames {
			let runs = GraphFuzzerToolRuns(fixture: toolRuns.fixture, firstOutcome: toolRuns.firstOutcome, secondOutcome: toolRuns.firstOutcome, renamedOutcomes: [(renaming, reversalOfTypeNames.outcome)])
			#expect(Set(runs.renamedGraphFailures.map(\.renamedGraphDifference)) == [.mockConfigurationFieldPresence])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func renamedGraphFailures_nameNeitherReason_whenARenamingThatKeepsTypeNamesChangesAConfigurationField() async throws {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: Self.lazyCycleFixture, multiModuleRenamings: [])
		let reversalOfTypeNames = try #require(toolRuns.renamedOutcomes.first { $0.renaming.reversesTypeNames && !$0.renaming.reversesLabels && !$0.renaming.reversesFileNames })

		for renaming in GraphFuzzerRenaming.all where !renaming.reversesTypeNames && !renaming.movesTypeNamesAcrossWrapperNames {
			let runs = GraphFuzzerToolRuns(fixture: toolRuns.fixture, firstOutcome: toolRuns.firstOutcome, secondOutcome: toolRuns.firstOutcome, renamedOutcomes: [(renaming, reversalOfTypeNames.outcome)])
			#expect(Set(runs.renamedGraphFailures.map(\.renamedGraphDifference)) == [.mockCode])
		}
	}

	// MARK: What each reason of a renamed graph's mock difference has to show

	private static let reversalOfLabels = GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: true, reversesFileNames: false)
	private static let reversalOfTypeNames = GraphFuzzerRenaming(reversesTypeNames: true, reversesLabels: false, reversesFileNames: false)
	private static let moveOfTypeNames = GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: false, reversesFileNames: false, movesTypeNamesAcrossWrapperNames: true)

	/// The file of the mock of the type named `name` in the fixtures of these tests.
	private static func mockFileName(of name: String) -> String {
		"\(mockDifferencePrefix)\(name)+SafeDIMock.swift"
	}

	/// `code` with `original` replaced by `replacement`, which the test expects the code to hold.
	private static func replacing(_ original: String, with replacement: String, in code: String?) -> String {
		#expect(code?.contains(original) == true, "\(original) is not in \(code ?? "nil")")
		return (code ?? "").replacingOccurrences(of: original, with: replacement)
	}

	/// What differs between the outcome of `fixture` and its outcome under `renaming`, each after its own edit of the
	/// generated files.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func differences(
		of fixture: GraphFuzzerFixture,
		under renaming: GraphFuzzerRenaming,
		editingOutcome editOutcome: (inout [String: String]) -> Void = { _ in },
		editingRenamedOutcome editRenamedOutcome: (inout [String: String]) -> Void = { _ in },
	) async throws -> [GraphFuzzerOutcomeDifference] {
		let toolRuns = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: [renaming], multiModuleRenamings: [])
		var files = generatedFiles(of: toolRuns.firstOutcome)
		var renamedFiles = try generatedFiles(of: #require(toolRuns.renamedOutcomes.first).outcome)
		editOutcome(&files)
		editRenamedOutcome(&renamedFiles)
		return GraphFuzzerToolOutcome.differences(between: .accepted(generatedFiles: files, warnings: []), and: .accepted(generatedFiles: renamedFiles, warnings: []), comparingCode: .inAnyOrderOfExtensions, renaming: renaming, of: fixture)
	}

	/// The names `T0` to `T9`, in order, with the first letter each takes under `moveOfTypeNames`.
	private static var lettersOfMovedTypeNames: [(name: String, letter: Character?)] {
		(0...9).map { index in
			let name = "T\(index)"
			return (name, moveOfTypeNames.rename("\(mockDifferencePrefix)\(name)", typeNamePrefix: mockDifferencePrefix).first)
		}
	}

	/// The first names among `T0` to `T9`, in their order, that take `letters` under `moveOfTypeNames`.
	private static func typeNames(takingLetters letters: [Character]) throws -> [String] {
		var names = [String]()
		for (name, letter) in lettersOfMovedTypeNames where names.count < letters.count && letter == letters[names.count] {
			names.append(name)
		}
		return try #require(names.count == letters.count ? names : nil)
	}

	/// A mock with three values only if available, in the order of their labels.
	private static var mockWithThreeLabelsFixture: GraphFuzzerFixture {
		GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			mockedType("T3", instantiating: [], receivingOnlyIfAvailable: [("t2", "\(mockDifferencePrefix)T4?"), ("t4", "\(mockDifferencePrefix)T5?"), ("t6", "\(mockDifferencePrefix)T6?")]),
			plainType("T4"),
			plainType("T5"),
			plainType("T6"),
		])
	}

	private static func overrideParameters(labeled labels: [String]) -> String {
		let typeByLabel = ["t2": "\(mockDifferencePrefix)T4", "t4": "\(mockDifferencePrefix)T5", "t6": "\(mockDifferencePrefix)T6"]
		return labels.map { "            \($0): \(typeByLabel[$0, default: ""])? = nil" }.joined(separator: ",\n")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameOrder_whenReversingLabelsReversesThreeParameters() async throws {
		let differences = try await Self.differences(of: Self.mockWithThreeLabelsFixture, under: Self.reversalOfLabels)

		#expect(differences.map(\.aspect) == [.mockParameterAndFieldOrder])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenParametersChangePlacesInAnOrderNoReversalMakes() async throws {
		let differences = try await Self.differences(of: Self.mockWithThreeLabelsFixture, under: Self.reversalOfLabels, editingRenamedOutcome: { files in
			let fileName = Self.mockFileName(of: "T3")
			files[fileName] = Self.replacing(Self.overrideParameters(labeled: ["t6", "t4", "t2"]), with: Self.overrideParameters(labeled: ["t4", "t2", "t6"]), in: files[fileName])
		})

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenParametersWhoseLabelsTheRenamingLeavesAloneChangePlaces() async throws {
		let prefix = Self.mockDifferencePrefix
		let fixture = GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			Self.mockedType("T3", instantiating: [], receivingOnlyIfAvailable: [("items", "\(prefix)T4?"), ("value", "\(prefix)T5?")]),
			Self.plainType("T4"),
			Self.plainType("T5"),
		])
		let items = "items: \(prefix)T4? = nil"
		let value = "value: \(prefix)T5? = nil"

		let differences = try await Self.differences(of: fixture, under: Self.reversalOfLabels, editingRenamedOutcome: { files in
			let fileName = Self.mockFileName(of: "T3")
			files[fileName] = Self.replacing("\(items),\n            \(value)\n", with: "\(value),\n            \(items)\n", in: files[fileName])
		})

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenTheChildrenOfAMocksOverridesChangePlaces() async throws {
		let prefix = Self.mockDifferencePrefix
		let t1 = "t1: \(prefix)T1.SafeDIMockConfiguration = .init()"
		let t2 = "t2: \(prefix)T2.SafeDIMockConfiguration = .init()"

		let differences = try await Self.differences(of: Self.plainTreeFixture, under: Self.reversalOfLabels, editingRenamedOutcome: { files in
			let fileName = Self.mockFileName(of: "T0")
			files[fileName] = Self.replacing("\(t1),\n            \(t2)\n", with: "\(t2),\n            \(t1)\n", in: files[fileName])
		})

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameOrder_whenAMocksParametersAreForwardedAndReceived() async throws {
		let prefix = Self.mockDifferencePrefix
		let fixture = GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			"@Instantiable(generateMock: true)\npublic final class \(prefix)T3: Instantiable {\n\tpublic init(t3: \(prefix)Other, t1: \(prefix)Other, t5: \(prefix)Other) {\n\t\tself.t3 = t3\n\t\tself.t1 = t1\n\t\tself.t5 = t5\n\t}\n\t@Forwarded let t3: \(prefix)Other\n\t@Received let t1: \(prefix)Other\n\t@Received let t5: \(prefix)Other\n}\n",
			"public final class \(prefix)Other {}\n",
		])

		let differences = try await Self.differences(of: fixture, under: Self.reversalOfLabels)

		#expect(differences.map(\.aspect) == [.mockParameterAndFieldOrder])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenAMocksReceivedParametersChangePlacesInAnOrderNoReversalMakes() async throws {
		let prefix = Self.mockDifferencePrefix
		let parameters = { (labels: [String]) in labels.map { "        \($0): \(prefix)Other" }.joined(separator: ",\n") }
		let fixture = GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			"@Instantiable(generateMock: true)\npublic final class \(prefix)T3: Instantiable {\n\tpublic init(t2: \(prefix)Other, t4: \(prefix)Other, t6: \(prefix)Other) {\n\t\tself.t2 = t2\n\t\tself.t4 = t4\n\t\tself.t6 = t6\n\t}\n\t@Received let t2: \(prefix)Other\n\t@Received let t4: \(prefix)Other\n\t@Received let t6: \(prefix)Other\n}\n",
			"public final class \(prefix)Other {}\n",
		])

		let differences = try await Self.differences(of: fixture, under: Self.reversalOfLabels, editingRenamedOutcome: { files in
			let fileName = Self.mockFileName(of: "T3")
			files[fileName] = Self.replacing(parameters(["t6", "t4", "t2"]), with: parameters(["t4", "t6", "t2"]), in: files[fileName])
		})

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameOrder_whenReversingLabelsReordersTheWrappersOfLazilyInstantiatedInstances() async throws {
		let prefix = Self.mockDifferencePrefix
		let fixture = GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			"@Instantiable(generateMock: true)\npublic final class \(prefix)T3: Instantiable {\n\tpublic init(t1: LazilyInstantiated<\(prefix)Other>, t5: LazilyInstantiated<\(prefix)Other>) {\n\t\tself.t1 = t1\n\t\tself.t5 = t5\n\t}\n\t@Received let t1: LazilyInstantiated<\(prefix)Other>\n\t@Received let t5: LazilyInstantiated<\(prefix)Other>\n}\n",
			"public final class \(prefix)Other {}\n",
		])

		let differences = try await Self.differences(of: fixture, under: Self.reversalOfLabels)

		#expect(differences.map(\.aspect) == [.mockParameterAndFieldOrder])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameOrder_whenReversingTypeNamesReordersOverridesOfOneLabel() async throws {
		let prefix = Self.mockDifferencePrefix
		// The same label, received only if available as two types, is two overrides ordered by type.
		let fixture = GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			Self.mockedType("T3", instantiating: [("child", "\(prefix)T4")], receivingOnlyIfAvailable: [("value", "\(prefix)T1?")]),
			"@Instantiable\npublic final class \(prefix)T4: Instantiable {\n\tpublic init(value: \(prefix)T2?) {\n\t\tself.value = value\n\t}\n\t@Received(onlyIfAvailable: true) let value: \(prefix)T2?\n}\n",
			Self.plainType("T1"),
			Self.plainType("T2"),
		])

		let differences = try await Self.differences(of: fixture, under: Self.reversalOfTypeNames)

		#expect(differences.map(\.aspect) == [.mockParameterAndFieldOrder])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenOverridesOfDifferentLabelsChangePlacesUnderAReversalOfTypeNames() async throws {
		let t2 = Self.overrideParameters(labeled: ["t2", "t4", "t6"])

		let differences = try await Self.differences(of: Self.mockWithThreeLabelsFixture, under: Self.reversalOfTypeNames, editingRenamedOutcome: { files in
			let fileName = Self.mockFileName(of: "T3")
			files[fileName] = Self.replacing(t2, with: Self.overrideParameters(labeled: ["t4", "t2", "t6"]), in: files[fileName])
		})

		#expect(differences.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameOrder_whenAWiderTierOfAPublicMockPassesItsParametersToTheNarrowest() async throws {
		// A graph of the public mock corpus whose `mock()` has a `public` tier and a `package` tier.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 407, features: [.generateMockPublic])

		let differences = try await Self.differences(of: fixture, under: Self.reversalOfLabels)

		#expect(differences.filter { $0.fileName == "FuzzApp/S407_T7+SafeDIMock.swift" }.map(\.aspect) == [.mockParameterAndFieldOrder])
	}

	/// A chain of three mocked types closed into a cycle, with a chord from the first to the third.
	private static var lazyCycleWithChordFixture: GraphFuzzerFixture {
		let prefix = mockDifferencePrefix
		return GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			mockedType("T7", instantiating: [("t8Builder", "Instantiator<\(prefix)T8>"), ("t9Builder", "Instantiator<\(prefix)T9>")]),
			mockedType("T8", instantiating: [("t9Builder", "Instantiator<\(prefix)T9>")]),
			mockedType("T9", instantiating: [("t7Builder", "Instantiator<\(prefix)T7>")]),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_namePresence_whenEveryDroppedFieldClosesACycleInTheOutcomeThatLacksIt() async throws {
		let differences = try await Self.differences(of: Self.lazyCycleWithChordFixture, under: Self.reversalOfTypeNames)

		#expect(Set(differences.map(\.aspect)) == [.mockConfigurationFieldPresence])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenADroppedFieldClosesNoCycleInTheOutcomeThatLacksIt() async throws {
		let t8Configuration = "\(Self.mockDifferencePrefix)T8.SafeDIMockConfiguration"
		let readThroughTheField = try NSRegularExpression(pattern: #"if let safeDIBuilder = [A-Za-z0-9_.]*\.t7Builder\.t8Builder[A-Za-z0-9_.]* \{ .*? \} else \{ (.*) \}$"#, options: [.anchorsMatchLines])

		let differences = try await Self.differences(of: Self.lazyCycleWithChordFixture, under: Self.reversalOfTypeNames, editingRenamedOutcome: { files in
			// `T7`'s field of `T8`, a tree edge of the search under this naming, goes, and the reads of it across the files with it.
			let fileName = Self.mockFileName(of: "T7")
			files[fileName] = Self.editingConfigurationStruct(in: files[fileName, default: ""]) { configuration in
				Self.replacing("            t8Builder: \(t8Configuration) = .init(),\n", with: "", in: Self.replacing("            self.t8Builder = t8Builder\n", with: "", in: Self.replacing("        let t8Builder: \(t8Configuration)\n", with: "", in: configuration)))
			}
			for name in files.keys {
				let source = files[name, default: ""]
				files[name] = readThroughTheField.stringByReplacingMatches(in: source, range: NSRange(location: 0, length: (source as NSString).length), withTemplate: "$1")
			}
		})

		#expect(differences.filter { $0.fileName == Self.mockFileName(of: "T7") }.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenARenamingKeepsTheOrderOfTheTypesOfACycle() async throws {
		let reversed = try await GraphFuzzerOracle.toolRuns(of: Self.lazyCycleFixture, renamings: [Self.reversalOfTypeNames], multiModuleRenamings: [])
		// `T7` and `T8` both take one letter here: the move keeps their order, so it cannot have dropped either field.
		let letters = Self.lettersOfMovedTypeNames.filter { $0.name == "T7" || $0.name == "T8" }.map(\.letter)
		#expect(letters.first == letters.last)

		let differences = try GraphFuzzerToolOutcome.differences(between: reversed.firstOutcome, and: #require(reversed.renamedOutcomes.first).outcome, comparingCode: .inAnyOrderOfExtensions, renaming: Self.moveOfTypeNames, of: Self.lazyCycleFixture)

		#expect(differences.map(\.aspect) == [.mockCode, .mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_namePresence_whenAMoveOfTypeNamesChangesTheOrderOfATwoTypeCycle() async throws {
		let prefix = Self.mockDifferencePrefix
		let names = try Self.typeNames(takingLetters: ["Z", "A"])
		let fixture = GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			Self.mockedType(names[0], instantiating: [("nextBuilder", "Instantiator<\(prefix)\(names[1])>")]),
			Self.mockedType(names[1], instantiating: [("firstBuilder", "Instantiator<\(prefix)\(names[0])>")]),
		])

		let differences = try await Self.differences(of: fixture, under: Self.moveOfTypeNames)

		#expect(Set(differences.map(\.aspect)) == [.mockConfigurationFieldPresence])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_namePresence_whenAMoveDropsAFieldOfAThreeTypeCycleWhoseTwoTypesKeepTheirOrder() async throws {
		let prefix = Self.mockDifferencePrefix
		// The move starts the search at the second type. The field from the third type to the first then appears, though those two keep their order.
		let names = try Self.typeNames(takingLetters: ["Z", "A", "Z"])
		let fixture = GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			Self.mockedType(names[0], instantiating: [("secondBuilder", "Instantiator<\(prefix)\(names[1])>")]),
			Self.mockedType(names[1], instantiating: [("thirdBuilder", "Instantiator<\(prefix)\(names[2])>")]),
			Self.mockedType(names[2], instantiating: [("firstBuilder", "Instantiator<\(prefix)\(names[0])>")]),
		])

		let differences = try await Self.differences(of: fixture, under: Self.moveOfTypeNames)

		#expect(Set(differences.map(\.aspect)) == [.mockConfigurationFieldPresence])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_namePresence_whenAMoveChangesOnlyWhereATypeOutsideACycleEntersIt() async throws {
		let prefix = Self.mockDifferencePrefix
		// The two types of the cycle keep their order; the move takes the type outside it from before them to between them.
		let names = try Self.typeNames(takingLetters: ["Z", "A", "Z"])
		let fixture = GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			Self.mockedType(names[0], instantiating: [("thirdBuilder", "Instantiator<\(prefix)\(names[2])>")]),
			Self.mockedType(names[1], instantiating: [("thirdBuilder", "Instantiator<\(prefix)\(names[2])>")]),
			Self.mockedType(names[2], instantiating: [("secondBuilder", "Instantiator<\(prefix)\(names[1])>")]),
		])

		let differences = try await Self.differences(of: fixture, under: Self.moveOfTypeNames)

		#expect(Set(differences.map(\.aspect)) == [.mockConfigurationFieldPresence])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_namePresence_whenAMoveChangesOnlyWhereATypeNoGeneratedCodeNamesEntersACycle() async throws {
		let prefix = Self.mockDifferencePrefix
		// The first type is neither mocked nor reached from a root, so the two outcomes hold no trace of it.
		let names = try Self.typeNames(takingLetters: ["Z", "A", "Z"])
		let fixture = GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			"@Instantiable\npublic final class \(prefix)\(names[0]): Instantiable {\n\tpublic init(thirdBuilder: Instantiator<\(prefix)\(names[2])>) {\n\t\tself.thirdBuilder = thirdBuilder\n\t}\n\t@Instantiated let thirdBuilder: Instantiator<\(prefix)\(names[2])>\n}\n",
			Self.mockedType(names[1], instantiating: [("thirdBuilder", "Instantiator<\(prefix)\(names[2])>")]),
			Self.mockedType(names[2], instantiating: [("secondBuilder", "Instantiator<\(prefix)\(names[1])>")]),
		])

		let differences = try await Self.differences(of: fixture, under: Self.moveOfTypeNames)

		#expect(Set(differences.map(\.aspect)) == [.mockConfigurationFieldPresence])
	}

	/// A lazy cycle whose first mocked type also instantiates two values of one type, and has two default-valued parameters.
	private static var lazyCycleWithTwoLeavesAndDefaultsFixture: GraphFuzzerFixture {
		let prefix = mockDifferencePrefix
		return GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			"@Instantiable(generateMock: true)\npublic final class \(prefix)T7: Instantiable {\n\tpublic init(t8Builder: Instantiator<\(prefix)T8>, t4: \(prefix)T3, t5: \(prefix)T3, theme: Int = 1, size: Int = 2) {\n\t\tself.t8Builder = t8Builder\n\t\tself.t4 = t4\n\t\tself.t5 = t5\n\t}\n\t@Instantiated let t8Builder: Instantiator<\(prefix)T8>\n\t@Instantiated let t4: \(prefix)T3\n\t@Instantiated let t5: \(prefix)T3\n}\n",
			mockedType("T8", instantiating: [("t7Builder", "Instantiator<\(prefix)T7>")]),
			plainType("T3"),
		])
	}

	/// The aspects of the difference in `T7`'s mock between the graph of `lazyCycleWithTwoLeavesAndDefaultsFixture` and its
	/// reversal of type names, with the reversal's mock edited by `edit`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func aspectsOfT7sMockWithDroppedReads(editedBy edit: (String?) -> String) async throws -> [GraphFuzzerOutcomeDifference.Aspect] {
		try await differences(of: lazyCycleWithTwoLeavesAndDefaultsFixture, under: reversalOfTypeNames, editingRenamedOutcome: { files in
			let fileName = Self.mockFileName(of: "T7")
			files[fileName] = edit(files[fileName])
		}).filter { $0.fileName == mockFileName(of: "T7") }.map(\.aspect)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_namePresence_whenEveryDiscardedReadIsThePathOfItsNode() async throws {
		#expect(try await Self.aspectsOfT7sMockWithDroppedReads { $0 ?? "" } == [.mockConfigurationFieldPresence])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenADiscardedOverrideReadsAnotherFieldPastADroppedField() async throws {
		let aspects = try await Self.aspectsOfT7sMockWithDroppedReads {
			Self.replacing("let t4 = if let safeDIBuilder = safeDIOverrides.t8Builder.t7Builder.t4 {", with: "let t4 = if let safeDIBuilder = safeDIOverrides.t8Builder.t7Builder.t5 {", in: $0)
		}

		#expect(aspects == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenADiscardedOverrideReadsAFieldNoStructHolds() async throws {
		let aspects = try await Self.aspectsOfT7sMockWithDroppedReads {
			Self.replacing("let t4 = if let safeDIBuilder = safeDIOverrides.t8Builder.t7Builder.t4 {", with: "let t4 = if let safeDIBuilder = safeDIOverrides.t8Builder.t7Builder.noSuchField {", in: $0)
		}

		#expect(aspects == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenADiscardedConstructionPassesOneDefaultTheFieldOfAnother() async throws {
		let path = "safeDIOverrides.t8Builder.t7Builder"
		let aspects = try await Self.aspectsOfT7sMockWithDroppedReads { code in
			Self.replacing("theme: \(path).theme, size: \(path).size", with: "theme: \(path).size, size: \(path).theme", in: Self.replacing("t5, \(path).theme, \(path).size)", with: "t5, \(path).size, \(path).theme)", in: code))
		}

		#expect(aspects == [.mockCode])
	}

	/// The aspects of the difference in `T8`'s mock between the graph of `lazyCycleOfErasedTypesFixture`, with the text
	/// `original` of its mock replaced, and its reversal of type names.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func aspectsOfT8sErasedMock(replacing original: String, with replacement: String) async throws -> [GraphFuzzerOutcomeDifference.Aspect] {
		try await differences(of: lazyCycleOfErasedTypesFixture, under: reversalOfTypeNames, editingOutcome: { files in
			let fileName = Self.mockFileName(of: "T8")
			files[fileName] = Self.replacing(original, with: replacement, in: files[fileName])
		}).filter { $0.fileName == mockFileName(of: "T8") }.map(\.aspect)
	}

	private static let erasedNodeOverride = "if let safeDIBuilder = safeDIOverrides.anyT7Builder.anyT8Builder.safeDIBuilder { "

	private static let erasedLeafOverride = "if let safeDIBuilder = safeDIOverrides.anyT7Builder.anyT8Builder.anyT4 { "

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenADiscardedOverrideOfAnErasedNodeDoesNotEraseItsBuilder() async throws {
		let prefix = Self.mockDifferencePrefix
		let aspects = try await Self.aspectsOfT8sErasedMock(replacing: "\(Self.erasedNodeOverride)\(prefix)AnyT8(safeDIBuilder(anyT7Builder, anyT4)) }", with: "\(Self.erasedNodeOverride)safeDIBuilder(anyT7Builder, anyT4) }")

		#expect(aspects == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenADiscardedOverrideOfAnErasedLeafErasesItsBuilder() async throws {
		let prefix = Self.mockDifferencePrefix
		let aspects = try await Self.aspectsOfT8sErasedMock(replacing: "\(Self.erasedLeafOverride)safeDIBuilder() }", with: "\(Self.erasedLeafOverride)\(prefix)AnyT4(safeDIBuilder()) }")

		#expect(aspects == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenADiscardedOverrideOfAnErasedLeafPassesItsBuilderTheConstruction() async throws {
		let prefix = Self.mockDifferencePrefix
		let aspects = try await Self.aspectsOfT8sErasedMock(replacing: "\(Self.erasedLeafOverride)safeDIBuilder() }", with: "\(Self.erasedLeafOverride)safeDIBuilder(\(prefix)T4()) }")

		#expect(aspects == [.mockCode])
	}

	/// A lazy cycle through `@Sendable` builders whose types each have default-valued parameters.
	private static var lazyCycleOfSendableBuildersWithDefaultsFixture: GraphFuzzerFixture {
		let prefix = mockDifferencePrefix
		return GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			"@Instantiable(generateMock: true)\npublic final class \(prefix)T7: Instantiable, Sendable {\n\tpublic init(t8Builder: SendableInstantiator<\(prefix)T8>, theme: Int = 1) {\n\t\tself.t8Builder = t8Builder\n\t}\n\t@Instantiated let t8Builder: SendableInstantiator<\(prefix)T8>\n}\n",
			"@Instantiable(generateMock: true)\npublic final class \(prefix)T8: Instantiable, Sendable {\n\tpublic init(t7Builder: SendableInstantiator<\(prefix)T7>, count: Int = 2, size: Int = 3) {\n\t\tself.t7Builder = t7Builder\n\t}\n\t@Instantiated let t7Builder: SendableInstantiator<\(prefix)T7>\n}\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_namePresence_whenADroppedConstructionPassesADefaultThroughAnExtractedLocal() async throws {
		let differences = try await Self.differences(of: Self.lazyCycleOfSendableBuildersWithDefaultsFixture, under: Self.reversalOfTypeNames)

		#expect(Set(differences.map(\.aspect)) == [.mockConfigurationFieldPresence])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_nameNeitherReason_whenAnExtractedLocalReadsTheFieldOfAnotherDefault() async throws {
		let differences = try await Self.differences(of: Self.lazyCycleOfSendableBuildersWithDefaultsFixture, under: Self.reversalOfTypeNames, editingOutcome: { files in
			let fileName = Self.mockFileName(of: "T8")
			files[fileName] = Self.replacing("count: __safeDI_t7Builder__overrides.t8Builder.count()", with: "count: __safeDI_t7Builder__overrides.t8Builder.size()", in: files[fileName])
		})

		#expect(differences.filter { $0.fileName == Self.mockFileName(of: "T8") }.map(\.aspect) == [.mockCode])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func differences_namePresence_whenTheBuilderFunctionsOfACycleAreRenamedApart() async throws {
		let prefix = Self.mockDifferencePrefix
		// Both types call the other `builder`, so a cycle-closing scope refers to a function a nested one would hide.
		let fixture = GraphFuzzerFixture(seed: 1_000_000_011, swiftFileContent: [
			Self.mockedType("T7", instantiating: [("builder", "Instantiator<\(prefix)T8>")]),
			Self.mockedType("T8", instantiating: [("builder", "Instantiator<\(prefix)T7>")]),
		])

		let differences = try await Self.differences(of: fixture, under: Self.reversalOfTypeNames)

		#expect(Set(differences.map(\.aspect)) == [.mockConfigurationFieldPresence])
	}

	@Test
	func summaryOfReport_saysTheSeedIsMisfiled_whenAnEntryListsADifferenceItsGraphDoesNotShow() async throws {
		let knownIssue = GraphFuzzerKnownIssue(reason: "Both reasons", signatures: [.renamedGraphDiffers(.mockParameterAndFieldOrder), .renamedGraphDiffers(.mockConfigurationFieldPresence)], seeds: [12])
		let reportLine = try #require(GraphFuzzerFinding.staleRenamedGraphDifference(knownIssue, .mockConfigurationFieldPresence).reportLine(seed: 12))
		let directory = TestTemporaryDirectory.root.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let report = directory.appendingPathComponent("report")
		let summary = directory.appendingPathComponent("summary")
		try "seed 12\nfinished 12\n\(reportLine)\ncompleted 1 graphs\n".write(to: report, atomically: true, encoding: .utf8)
		let script = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent(".github/scripts/summarize-graph-fuzzer-report.sh")
		let result = try await runProcess(
			URL(fileURLWithPath: "/bin/bash"),
			arguments: [script.path, report.path, summary.path, "12", "1"],
			// The job summary of a CI run of this suite is not this test's to write to.
			environment: ProcessInfo.processInfo.environment.filter { $0.key != "GITHUB_STEP_SUMMARY" },
		)

		let text = try String(contentsOf: summary, encoding: .utf8)
		#expect(result.exitCode == 1)
		#expect(text.contains("- **Seed 12** is listed under an entry that names more than its graph shows (Both reasons: the renamed graph does not show which configuration fields its generated mock has; list the seed under the entry that names exactly what it shows)."))
		#expect(!text.contains("no longer fails"))
	}

	@Test
	func findings_reportEachListedRenamedGraphDifference_whenTheGraphDoesNotShowIt() {
		let knownIssue = GraphFuzzerKnownIssue(reason: "Both reasons", signatures: [.renamedGraphDiffers(.mockParameterAndFieldOrder), .renamedGraphDiffers(.mockConfigurationFieldPresence)], seeds: [12])
		let order = GraphFuzzerFailure(seed: 12, kind: .renamedGraphDiffers, details: "Reversing its labels changes \(GraphFuzzerOutcomeDifference.Aspect.mockParameterAndFieldOrder.rawValue), in S12_T0+SafeDIMock.swift.\nThis graph:\n…", renamedGraphDifference: .mockParameterAndFieldOrder)

		let findings = GraphFuzzerFinding.findings(failure: order, laterFailures: [], knownIssue: knownIssue)

		#expect(findings == [.knownIssue(knownIssue, order), .staleRenamedGraphDifference(knownIssue, .mockConfigurationFieldPresence)])
		#expect(findings.last?.reportLine(seed: 12) == "misfiled 12 Both reasons: the renamed graph does not show which configuration fields its generated mock has; list the seed under the entry that names exactly what it shows")
	}

	@Test
	func findings_reportLaterValueDifference_whenFirstFailureIsRenamedDifferenceItsEntryLists() {
		// A renamed graph's difference that the entry lists masks no later failure the entry does not list.
		let knownIssue = GraphFuzzerKnownIssue(reason: "Builder order", signatures: [.renamedGraphDiffers(.dependencyTreeCode)], seeds: [12])
		let renamed = GraphFuzzerFailure(seed: 12, kind: .renamedGraphDiffers, details: "A", renamedGraphDifference: .dependencyTreeCode)
		let values = GraphFuzzerFailure(seed: 12, kind: .holeBuildsOtherValuesThanVisibleBuild, details: "B")

		#expect(GraphFuzzerFinding.findings(failure: renamed, laterFailures: [values], knownIssue: knownIssue) == [.failure(values)])
	}

	@Test
	func masksNoLaterFailure_isTrue_whenEntryListsRenamedDifferences() {
		let order = GraphFuzzerKnownIssue(reason: "Order", signatures: [.renamedGraphDiffers(.dependencyTreeCode)], seeds: [12])

		#expect(order.masksNoLaterFailure)
	}

	@Test
	func masksNoLaterFailure_isTrue_whenEntryListsRenamedDifferenceBesideRetention() {
		let orderAndLeak = GraphFuzzerKnownIssue(reason: "Order and leak", signatures: [.renamedGraphDiffers(.mockParameterAndFieldOrder), .seamRetainsWhatInlineFrees(containing: "_Leak alive")], seeds: [12])

		#expect(orderAndLeak.masksNoLaterFailure)
	}

	@Test
	func masksNoLaterFailure_isFalse_whenEntryListsCompilerErrorBesideRenamedDifference() {
		let compiler = GraphFuzzerKnownIssue(reason: "Compiler", signatures: [.renamedGraphDiffers(.dependencyTreeCode), .compilerError(containing: "redeclaration")], seeds: [12])

		#expect(!compiler.masksNoLaterFailure)
	}

	@Test
	func masksNoLaterFailure_isFalse_whenEntryListsHoleNamesChangingWithSecondPlace() {
		let names = GraphFuzzerKnownIssue(reason: "Names", signatures: [.holeNamesChangeWithSecondPlace(containing: "label")], seeds: [12])

		#expect(!names.masksNoLaterFailure)
	}

	@Test
	func findings_reportNoStaleDifference_whenTheGraphShowsEveryDifferenceItsEntryLists() {
		let knownIssue = GraphFuzzerKnownIssue(reason: "Both reasons", signatures: [.renamedGraphDiffers(.mockParameterAndFieldOrder), .renamedGraphDiffers(.mockConfigurationFieldPresence)], seeds: [12])
		let order = GraphFuzzerFailure(seed: 12, kind: .renamedGraphDiffers, details: "A", renamedGraphDifference: .mockParameterAndFieldOrder)
		let field = GraphFuzzerFailure(seed: 12, kind: .renamedGraphDiffers, details: "B", renamedGraphDifference: .mockConfigurationFieldPresence)

		#expect(GraphFuzzerFinding.findings(failure: order, laterFailures: [field], knownIssue: knownIssue) == [.knownIssue(knownIssue, order)])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func results_carryEveryRenamedGraphDifference_whenEachRenamingDiffersInAnotherFile() async throws {
		// One small type, so the compile this takes stays cheap, as in `compilationFailures_reportEachBrokenGraph…`.
		let seed: UInt64 = 1_000_000_009
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
		let fixture = GraphFuzzerFixture(seed: seed, swiftFileContent: [
			"@Instantiable\npublic final class \(prefix)Probe: Instantiable {\n\tpublic init() {}\n}\n",
		])
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["\(prefix)Probe+SafeDIMock.swift": "// mock\n", "SafeDIMockConfiguration.swift": "// configuration\n"], warnings: [])
		let otherMock = GraphFuzzerToolOutcome.accepted(generatedFiles: ["\(prefix)Probe+SafeDIMock.swift": "// other\n", "SafeDIMockConfiguration.swift": "// configuration\n"], warnings: [])
		let otherConfiguration = GraphFuzzerToolOutcome.accepted(generatedFiles: ["\(prefix)Probe+SafeDIMock.swift": "// mock\n", "SafeDIMockConfiguration.swift": "// other\n"], warnings: [])
		let toolRuns = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome, renamedOutcomes: [(GraphFuzzerRenaming.all[0], otherMock), (GraphFuzzerRenaming.all[1], otherConfiguration)])

		let result = try #require(try await GraphFuzzerOracle.results(of: [toolRuns]).first)

		#expect(result.failure?.renamedGraphDifference == .mockCode)
		#expect(result.laterFailures.map(\.renamedGraphDifference) == [.mockConfigurationCode])
	}

	@Test
	func knownIssue_matchesRenamedGraphDifference_onlyInTheAspectItNames() {
		let knownIssue = GraphFuzzerKnownIssue(reason: "An order", signatures: [.renamedGraphDiffers(.mockCode)], seeds: [12])
		// A failure's text holds the graph's generated code, which can say anything; only the aspect it reports counts.
		let configuration = GraphFuzzerFailure(seed: 12, kind: .renamedGraphDiffers, details: "Reversing its labels changes its generated mock configuration code, in SafeDIMockConfiguration.swift, not its generated mock code.\nThis graph:\n…", renamedGraphDifference: .mockConfigurationCode)
		let mock = GraphFuzzerFailure(seed: 12, kind: .renamedGraphDiffers, details: "Reversing its labels changes its generated mock code, in S12_T0+SafeDIMock.swift.\nThis graph:\n…", renamedGraphDifference: .mockCode)

		#expect(!knownIssue.matches(configuration))
		#expect(knownIssue.matches(mock))
	}

	@Test
	func findings_reportEachRenamedGraphDifferenceTheKnownIssueDoesNotList_whenTheFirstIsListed() {
		let knownIssue = GraphFuzzerKnownIssue(reason: "An order", signatures: [.renamedGraphDiffers(.mockCode)], seeds: [12])
		func failure(_ aspect: GraphFuzzerOutcomeDifference.Aspect, in file: String) -> GraphFuzzerFailure {
			GraphFuzzerFailure(seed: 12, kind: .renamedGraphDiffers, details: "Reversing its labels changes \(aspect.rawValue), in \(file).\nThis graph:\n…", renamedGraphDifference: aspect)
		}
		let listed = failure(.mockCode, in: "S12_T0+SafeDIMock.swift")
		let listedInAnotherFile = failure(.mockCode, in: "S12_T1+SafeDIMock.swift")
		let secondFile = failure(.dependencyTreeCode, in: "S12_Root0+SafeDI.swift")
		let warnings = failure(.warnings, in: "the tool's output")

		#expect(GraphFuzzerFinding.findings(failure: listed, laterFailures: [listedInAnotherFile, secondFile, warnings], knownIssue: knownIssue) == [.failure(secondFile), .failure(warnings)])
		#expect(GraphFuzzerFinding.findings(failure: listed, laterFailures: [listedInAnotherFile], knownIssue: knownIssue) == [.knownIssue(knownIssue, listed)])
	}

	@Test
	func findings_reportEachRenamedGraphDifference_whenNoKnownIssueListsTheSeed() {
		let mock = GraphFuzzerFailure(seed: 12, kind: .renamedGraphDiffers, details: "Reversing its labels changes its generated mock code, in S12_T0+SafeDIMock.swift.\nThis graph:\n…", renamedGraphDifference: .mockCode)
		let warnings = GraphFuzzerFailure(seed: 12, kind: .renamedGraphDiffers, details: "Reversing its labels changes its warnings.\nThis graph:\n…", renamedGraphDifference: .warnings)

		#expect(GraphFuzzerFinding.findings(failure: mock, laterFailures: [warnings], knownIssue: nil) == [.failure(mock), .failure(warnings)])
	}

	@Test
	func findings_reportRenamedGraphDifference_whenAKnownCompilerFailureComesFirst() {
		// What the tool generates under a renaming says nothing about what the compiler made of the graph, so a known
		// compiler failure documents no difference.
		let knownIssue = GraphFuzzerKnownIssue(reason: "A mock that does not compile", signatures: [.compilerError(containing: "invalid redeclaration")], seeds: [12])
		let compilation = GraphFuzzerFailure(seed: 12, kind: .generatedCodeDoesNotCompile, details: "error: invalid redeclaration of `a`")
		let renamed = GraphFuzzerFailure(seed: 12, kind: .renamedGraphDiffers, details: "Reversing its labels changes its warnings.\nThis graph:\n…", renamedGraphDifference: .warnings)

		#expect(GraphFuzzerFinding.findings(failure: compilation, laterFailures: [renamed], knownIssue: knownIssue) == [.failure(renamed)])
	}

	@Test
	func reportLine_namesTheDifference_whenRenamedGraphDiffers() {
		let failure = GraphFuzzerFailure(seed: 12, kind: .renamedGraphDiffers, details: "Reversing its labels changes its generated mock code, in S12_T0+SafeDIMock.swift.\nThis graph:\n…", renamedGraphDifference: .mockCode)

		#expect(GraphFuzzerFinding.failure(failure).reportLine(seed: 12) == "failure 12 the graph renamed to change an order gives other results: Reversing its labels changes its generated mock code, in S12_T0+SafeDIMock.swift")
	}

	@Test
	func toolOutcome_throwsHarnessError_whenHarnessWritesNoFileOfTheFixturesFirstName() async {
		// The fixture names its file `Elsewhere.swift`, while the harness names it after `Root`, its `@Instantiable` type, so
		// the fixture directory of the graph, which the tool rejects since nothing builds `Missing`, cannot be found: the
		// oracle reports that, and deletes nothing.
		let fixture = GraphFuzzerFixture(seed: 0, swiftFileContent: ["\(GraphFuzzerFixture.fileNameMarker)Elsewhere.swift\n\n@Instantiable(isRoot: true)\npublic final class Root: Instantiable {\n    public init(missing: Missing) {\n        self.missing = missing\n    }\n\n    @Instantiated let missing: Missing\n}"])
		let workingDirectory = FileManager.default.currentDirectoryPath

		let error = await #expect(throws: GraphFuzzerInfrastructureError.self) {
			try await GraphFuzzerOracle.toolOutcome(of: fixture)
		}
		#expect(error?.description == "The test harness wrote no fixture named Elsewhere.swift for seed 0: the fixture names its files apart from the names the harness gives them.")
		#expect(FileManager.default.fileExists(atPath: workingDirectory))
	}

	@Test
	func valuesInOrder_givesValuesInElementOrder_whenLaterElementsFinishFirst() async throws {
		// Each element waits longer the earlier it is, so the twenty finish in the reverse of their order.
		let values = try await GraphFuzzerOracle.valuesInOrder(of: Array(0..<20), concurrent: 20) { element in
			try await Task.sleep(for: .milliseconds(10 * (20 - element)))
			return "value \(element)"
		}

		#expect(values == (0..<20).map { "value \($0)" })
	}

	@Test
	func valuesInOrder_throwsTheFirstFailureInElementOrder_whenLaterElementsFailFirst() async {
		// Six of twenty elements fail, and each waits longer the earlier it is, so the first of them in order, 3, is the
		// last to fail. A loop that threw whichever failure finished first would name 17.
		let failing: Set = [3, 5, 8, 11, 14, 17]

		let error = await #expect(throws: ElementFailure.self) {
			try await GraphFuzzerOracle.valuesInOrder(of: Array(0..<20), concurrent: 20) { element in
				try await Task.sleep(for: .milliseconds(10 * (20 - element)))
				guard !failing.contains(element) else { throw ElementFailure(description: "element \(element) failed") }
				return element
			}
		}

		#expect(error?.description == "element 3 failed")
	}

	@Test
	func valuesInOrder_startsNoElementAfterAFailure_whenOneElementRunsAtATime() async {
		let started = StartedElements()

		await #expect(throws: ElementFailure.self) {
			try await GraphFuzzerOracle.valuesInOrder(of: Array(0..<20), concurrent: 1) { element in
				await started.append(element)
				guard element != 2 else { throw ElementFailure(description: "element 2 failed") }
				return element
			}
		}

		#expect(await started.elements == [0, 1, 2])
	}

	@Test
	func difference_isNil_whenUnreadTypeCommentMovesToAnotherFileOfItsModule() {
		let comment = "    // SafeDI counts `StaticString` as `public`: no module it reads declares it narrower. If `StaticString` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.\n"
		let commentAboveFirst = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzFeature/S5_T0+SafeDIMock.swift": "extension S5_T0 {\n\(comment)    public static func mock() {}\n}\n", "FuzzFeature/S5_T1+SafeDIMock.swift": "extension S5_T1 {\n    public static func mock() {}\n}\n"], warnings: [])
		let commentAboveSecond = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzFeature/S5_T0+SafeDIMock.swift": "extension S5_T0 {\n    public static func mock() {}\n}\n", "FuzzFeature/S5_T1+SafeDIMock.swift": "extension S5_T1 {\n\(comment)    public static func mock() {}\n}\n"], warnings: [])

		#expect(GraphFuzzerToolOutcome.difference(between: commentAboveFirst, and: commentAboveSecond) == nil)
	}

	@Test
	func difference_namesUnreadTypeComments_whenOnlyOneOutcomeCarriesOne() {
		let comment = "    // SafeDI counts `StaticString` as `public`: no module it reads declares it narrower. If `StaticString` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.\n"
		let withComment = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzFeature/S5_T0+SafeDIMock.swift": "extension S5_T0 {\n\(comment)    public static func mock() {}\n}\n"], warnings: [])
		let withoutComment = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzFeature/S5_T0+SafeDIMock.swift": "extension S5_T0 {\n    public static func mock() {}\n}\n"], warnings: [])

		#expect(GraphFuzzerToolOutcome.difference(between: withComment, and: withoutComment) == "the comments naming the types it counts as `public` because it reads no declaration of them")
	}

	@Test
	func difference_isNil_whenDiagnosticsSuggestTheSamePropertiesInAnotherOrder() {
		let diagnostics = GraphFuzzerToolOutcome.rejected(diagnostics: "/a/<fixture-directory>/S12_T1.swift:7:2: error: @Received property `t4: S12_T3` is not @Instantiated or @Forwarded in chain: S12_Root0 -> S12_T1. Did you mean one of `t3: S12_T3`, `t4: Instantiator<S12_T3>`, `t6: S12_T3`?")
		let reorderedSuggestions = GraphFuzzerToolOutcome.rejected(diagnostics: "/b/<fixture-directory>/S12_T1.swift:7:2: error: @Received property `t4: S12_T3` is not @Instantiated or @Forwarded in chain: S12_Root0 -> S12_T1. Did you mean one of `t6: S12_T3`, `t4: Instantiator<S12_T3>`, `t3: S12_T3`?")

		#expect(GraphFuzzerToolOutcome.difference(between: diagnostics, and: reorderedSuggestions) == nil)
	}

	@Test
	func difference_isNil_whenDiagnosticsListTheSameProvingDeclarationsInAnotherOrder() {
		// SafeDI lists the declarations that prove a seam parameter's access in source order, which a file-name
		// reversal reverses; the same declarations in another order are the same diagnostic, and a missing one is not.
		func diagnostics(provers: String) -> GraphFuzzerToolOutcome {
			.rejected(diagnostics: "/a/<fixture-directory>/S1_Seam.swift:1:1: error: SafeDI cannot generate the dependency tree of `S1_Seam`: … `S1_Key` is `package` as far as SafeDI can tell: every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (\(provers)). …")
		}

		#expect(GraphFuzzerToolOutcome.difference(between: diagnostics(provers: "`S1_Host.init(key:seam:)`, `S1_Vault.init(key:)`"), and: diagnostics(provers: "`S1_Vault.init(key:)`, `S1_Host.init(key:seam:)`")) == nil)
		#expect(GraphFuzzerToolOutcome.difference(between: diagnostics(provers: "`S1_Host.init(key:seam:)`, `S1_Vault.init(key:)`"), and: diagnostics(provers: "`S1_Vault.init(key:)`")) == "its diagnostics")
	}

	@Test
	func difference_isNil_whenDiagnosticsListTheSameFormsOneCycleParameterCannotCarryInAnotherOrder() {
		// SafeDI lists the forms of a label one cycle parameter cannot carry in the order of their types' names, which a
		// renaming that moves type names across wrapper names reorders (seam corpus seed 788); the same forms in another
		// order are the same diagnostic, and another form is not.
		func diagnostics(forms: String) -> GraphFuzzerToolOutcome {
			.rejected(diagnostics: "/a/<fixture-directory>/S1_Reader.swift:9:2: error: @Received property `tag: LazilyInstantiated<S1_Tag>?` is received in chain: S1_B -> S1_Reader. A dependency cycle builds `S1_B` again beneath `S1_C`, which declares `tag: LazilyInstantiated<S1_Tag>` with the same label, and SafeDI hands each `S1_B` one value of `tag`. `S1_B` and the types it builds receive `tag` as \(forms), which one value cannot carry together. Receive \(forms) under different labels to fix.")
		}

		#expect(GraphFuzzerToolOutcome.difference(between: diagnostics(forms: "`tag: LazilyInstantiated<S1_Tag>?` and `tag: S1_Tag?`"), and: diagnostics(forms: "`tag: S1_Tag?` and `tag: LazilyInstantiated<S1_Tag>?`")) == nil)
		#expect(GraphFuzzerToolOutcome.difference(between: diagnostics(forms: "`tag: Instantiator<S1_Tag>?`, `tag: LazilyInstantiated<S1_Tag>?`, and `tag: S1_Tag?`"), and: diagnostics(forms: "`tag: S1_Tag?`, `tag: Instantiator<S1_Tag>?`, and `tag: LazilyInstantiated<S1_Tag>?`")) == nil)
		#expect(GraphFuzzerToolOutcome.difference(between: diagnostics(forms: "`tag: LazilyInstantiated<S1_Tag>?` and `tag: S1_Tag?`"), and: diagnostics(forms: "`tag: LazilyInstantiated<S1_Tag>?` and `tag: S1_Tag`")) == "its diagnostics")
	}

	@Test
	func difference_isNil_whenDiagnosticsNameTheSameTypesDeclaringACapturedWrapperInAnotherOrder() {
		// SafeDI lists the types whose declarations of a wrapper a `@Sendable` builder function captures at one receive in
		// source order, which a file-name reversal reverses (base corpus seeds 58, 112 and 225); the same types in another
		// order are the same diagnostic, and another type is not.
		func diagnostics(types: String, receivesWrapper: Bool) -> GraphFuzzerToolOutcome {
			let receive = receivesWrapper ? ", and this property," : ""
			return .rejected(diagnostics: "/a/<fixture-directory>/S1_Settings.swift:7:2: error: @Received property `childBuilder: Instantiator<S1_Child>` cannot be received inside a `@Sendable` function in chain: S1_Root0 -> S1_Settings. SafeDI builds `settingsBuilder: SendableInstantiator<S1_Settings>` on `S1_Root0` in a `@Sendable` function, which cannot capture `childBuilder: Instantiator<S1_Child>` on `S1_Root0`, because `Instantiator<S1_Child>` is not `Sendable`. Declare `childBuilder` on \(types)\(receive) as `SendableInstantiator<S1_Child>` to fix. `SendableInstantiator<S1_Child>` builds `S1_Child` in a `@Sendable` function, so what the tree of `S1_Child` receives from outside that function must be `Sendable` too.\n/a/<fixture-directory>/S1_Root0.swift:7:2: note: `childBuilder: Instantiator<S1_Child>` is declared here")
		}

		#expect(GraphFuzzerToolOutcome.difference(between: diagnostics(types: "`S1_Root0`, `S1_Root1`, and `S1_Root2`", receivesWrapper: true), and: diagnostics(types: "`S1_Root2`, `S1_Root1`, and `S1_Root0`", receivesWrapper: true)) == nil)
		#expect(GraphFuzzerToolOutcome.difference(between: diagnostics(types: "`S1_Root0` and `S1_Root1`", receivesWrapper: false), and: diagnostics(types: "`S1_Root1` and `S1_Root0`", receivesWrapper: false)) == nil)
		#expect(GraphFuzzerToolOutcome.difference(between: diagnostics(types: "`S1_Root0` and `S1_Root1`", receivesWrapper: true), and: diagnostics(types: "`S1_Root0` and `S1_Root2`", receivesWrapper: true)) == "its diagnostics")
	}

	@Test
	func difference_isNil_whenDiagnosticsNameTheSamePlacesOfAFillFindingInAnotherOrder() {
		// SafeDI lists the places one fill finding holds for in the order of their types' names, then their labels, which a
		// renaming that moves type names across wrapper names reorders (seam corpus seed 566); the same places in another
		// order are the same diagnostic, and another place is not.
		func reenteringCallDiagnostics(places: String) -> GraphFuzzerToolOutcome {
			.rejected(diagnostics: "/a/<fixture-directory>/S566_HoleImpl.swift:14:2: error: `S566_HoleImpl` receives `holeLogger: S566_HoleLogger`, which `S566_HoleSeam`’s tree builds where it instantiates `S566_HoleSeam` again, but that call passes the builder `S566_HoleSeam` takes for \(places) on unchanged, so the caller that fills it cannot hand it those values. Declare `@Received let holeLogger: S566_HoleLogger` on `S566_HoleSeam`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `S566_HoleService` in module `FuzzFeature` or a module it lists among its SafeDI dependencies, so `S566_HoleSeam` fills the builder itself.\n/a/<fixture-directory>/S566_HoleLoop.swift:11:2: note: `S566_HoleLoop` declares `holeLogger: S566_HoleLogger` here.")
		}
		func scopeDiagnostics(places: String) -> GraphFuzzerToolOutcome {
			.rejected(diagnostics: "/a/<fixture-directory>/S1_Impl.swift:9:5: error: `S1_Impl` receives `theme: S1_Theme`, which `S1_Home` builds after `profile`, since `S1_Theme` receives `profile` only if available, so SafeDI does not hand it to the builders for \(places). Receive `profile` on `S1_Theme` some other way, or declare an @Instantiable type that fulfills `S1_Service` in module `FuzzFeature` or a module it lists among its SafeDI dependencies.")
		}
		let ownerPlace = "`S566_HoleOwner`’s `holeService: any S566_HoleService`"
		let ownerLazyPlace = "`S566_HoleOwner`’s `holeServiceLazy: LazilyInstantiated<any S566_HoleService>`"
		let nestPlace = "`S566_HoleNestImpl`’s `holeService: any S566_HoleService`"
		let firstSeamPlace = "`S1_Profile`’s `service: any S1_Service` (`service` of `serviceBuilder`) in `S1_SeamA`’s tree"
		let secondSeamPlace = "`S1_Account`’s `service: any S1_Service` (`service` of `serviceBuilder`) in `S1_SeamB`’s tree"

		#expect(GraphFuzzerToolOutcome.difference(between: reenteringCallDiagnostics(places: "\(nestPlace), \(ownerPlace), and \(ownerLazyPlace)"), and: reenteringCallDiagnostics(places: "\(ownerPlace), \(ownerLazyPlace), and \(nestPlace)")) == nil)
		#expect(GraphFuzzerToolOutcome.difference(between: reenteringCallDiagnostics(places: "\(nestPlace) and \(ownerPlace)"), and: reenteringCallDiagnostics(places: "\(ownerPlace) and \(nestPlace)")) == nil)
		#expect(GraphFuzzerToolOutcome.difference(between: scopeDiagnostics(places: "\(firstSeamPlace) and \(secondSeamPlace)"), and: scopeDiagnostics(places: "\(secondSeamPlace) and \(firstSeamPlace)")) == nil)
		#expect(GraphFuzzerToolOutcome.difference(between: reenteringCallDiagnostics(places: "\(nestPlace) and \(ownerPlace)"), and: reenteringCallDiagnostics(places: "\(ownerLazyPlace) and \(nestPlace)")) == "its diagnostics")
		#expect(GraphFuzzerToolOutcome.difference(between: reenteringCallDiagnostics(places: "\(nestPlace) and \(ownerPlace)"), and: reenteringCallDiagnostics(places: "\(nestPlace), \(ownerPlace), and \(ownerLazyPlace)")) == "its diagnostics")
		#expect(GraphFuzzerToolOutcome.difference(between: scopeDiagnostics(places: "\(firstSeamPlace) and \(secondSeamPlace)"), and: scopeDiagnostics(places: "\(secondSeamPlace.replacingOccurrences(of: "S1_SeamB", with: "S1_SeamA")) and \(firstSeamPlace)")) == "its diagnostics")
	}

	@Test
	func difference_isNil_whenDiagnosticsListTheSameSeamsAndPlacesOfAPassedUpPlaceFindingInAnotherOrder() {
		// Seam corpus seed 116's merged finding: the seams whose calls present its places, and the places, follow the order of
		// type names, which moving type names across wrapper names reverses. The same items in another order are the same
		// diagnostic; another called seam, a place under the other seam's tree, a remedy's other seam, or a fulfill remedy
		// dropped is not.
		let deepPlace = "`S116_HoleDeepImpl`’s `holeService: any S116_HoleService` (`holeService` of `s116_HoleServiceSendableBuilder`) in `S116_HoleSeam`’s tree"
		let stagePlace = "`S116_HoleStageOwner`’s `holeService: any S116_HoleService` (`holeService` of `s116_HoleServiceSendableBuilder`) in `S116_HoleStager`’s tree"
		let serviceRemedy = "declare an @Instantiable type that fulfills `S116_HoleService` in module `FuzzFeature` or a module it lists among its SafeDI dependencies, so `S116_HoleOuter` fills the builders itself"
		let gadgetRemedy = "declare an @Instantiable type that fulfills `S116_HoleGadget` in module `FuzzFeature` or a module it lists among its SafeDI dependencies, so `S116_HoleOuter` fills the builders itself"
		func diagnostics(calledSeams: String, places: String, remedySeams: String = "`S116_HoleSeam` and `S116_HoleStager`", remedies: String = "\(serviceRemedy) and \(gadgetRemedy)") -> GraphFuzzerToolOutcome {
			.rejected(diagnostics: "<fixture-directory>/shop/Sources/FuzzApp/S116_HoleImpl.swift:13:3: error: `S116_HoleNamespace.S116_HoleImpl` receives `holeLogger: S116_HoleLogger`, which `S116_HoleOuter` builds where it calls \(calledSeams), but `S116_HoleOuter` passes the builders for \(places) on from its own caller, which cannot hand them `S116_HoleOuter`’s values. Declare `@Received let holeLogger: S116_HoleLogger` on \(remedySeams), so SafeDI hands it to the builders, or \(remedies).\n<fixture-directory>/shop/Sources/FuzzFeature/S116_HoleOuter.swift:11:2: note: `S116_HoleOuter` declares `holeLogger: S116_HoleLogger` here.")
		}
		let original = diagnostics(calledSeams: "`S116_HoleSeam` and `S116_HoleStager`", places: "\(deepPlace) and \(stagePlace)")

		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(calledSeams: "`S116_HoleStager` and `S116_HoleSeam`", places: "\(stagePlace) and \(deepPlace)", remedySeams: "`S116_HoleStager` and `S116_HoleSeam`", remedies: "\(gadgetRemedy) and \(serviceRemedy)")) == nil)
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(calledSeams: "`S116_HoleStager` and `S116_HoleRelay`", places: "\(stagePlace) and \(deepPlace)")) == "its diagnostics")
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(calledSeams: "`S116_HoleSeam` and `S116_HoleStager`", places: "\(deepPlace) and \(stagePlace.replacingOccurrences(of: "in `S116_HoleStager`’s tree", with: "in `S116_HoleSeam`’s tree"))")) == "its diagnostics")
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(calledSeams: "`S116_HoleSeam` and `S116_HoleStager`", places: "\(deepPlace) and \(stagePlace)", remedySeams: "`S116_HoleSeam` and `S116_HoleRelay`")) == "its diagnostics")
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(calledSeams: "`S116_HoleSeam` and `S116_HoleStager`", places: "\(deepPlace) and \(stagePlace)", remedies: serviceRemedy)) == "its diagnostics")
	}

	@Test
	func difference_isNil_whenDiagnosticsListTheSameClausesOfAReenteringCallFindingInAnotherOrder() {
		// Seam corpus seed 331's shape: one clause per declaration and call, and the declaring types, in name order, and a note
		// per declaring type, in that order, which a renaming of the types or the files reverses. The same items and notes in
		// another order are the same diagnostic; another call, a place of another builder, a declaring type renamed in the
		// list, or a note dropped or changed is not.
		let alphaClause = "`MiddleAlpha` declares on the paths from the builders for `Profile`’s `router: any Router` (`router` of `routerBuilder`) and `Screen`’s `screenRouter: any Router` (`screenRouter` of `routerBuilder`) to the call by which `MiddleAlpha` instantiates `Flow` again (`flowBuilder`)"
		let reorderedAlphaClause = "`MiddleAlpha` declares on the paths from the builders for `Screen`’s `screenRouter: any Router` (`screenRouter` of `routerBuilder`) and `Profile`’s `router: any Router` (`router` of `routerBuilder`) to the call by which `MiddleAlpha` instantiates `Flow` again (`flowBuilder`)"
		let zedClause = "`MiddleZed` declares on the path from the builder for `Profile`’s `router: any Router` (`router` of `routerBuilder`) to the call by which `MiddleZed` instantiates `Flow` again (`flowBuilder`)"
		let alphaNote = "/a/<fixture-directory>/MiddleAlpha.swift:10:5: note: `MiddleAlpha` declares `logger: Logger` here."
		let zedNote = "/a/<fixture-directory>/MiddleZed.swift:10:5: note: `MiddleZed` declares `logger: Logger` here."
		func diagnostics(clauses: String, declaringTypes: String = "`MiddleAlpha`’s and `MiddleZed`’s", notes: [String] = [alphaNote, zedNote]) -> GraphFuzzerToolOutcome {
			.rejected(diagnostics: (["/a/<fixture-directory>/DefaultRouter.swift:10:5: error: `DefaultRouter` receives `logger: Logger`, which \(clauses), but those calls pass the builder on as module `App` fills it, which cannot hand it \(declaringTypes) values. Declare `@Received let logger: Logger` on `Flow`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Router` in module `Feature` or a module it lists among its SafeDI dependencies."] + notes).joined(separator: "\n"))
		}
		let original = diagnostics(clauses: "\(alphaClause) and \(zedClause)")

		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(clauses: "\(zedClause) and \(reorderedAlphaClause)", declaringTypes: "`MiddleZed`’s and `MiddleAlpha`’s", notes: [zedNote, alphaNote])) == nil)
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(clauses: "\(alphaClause) and \(zedClause.replacingOccurrences(of: "instantiates `Flow` again (`flowBuilder`)", with: "instantiates `Shell` again (`shellBuilder`)"))")) == "its diagnostics")
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(clauses: "\(alphaClause) and \(zedClause.replacingOccurrences(of: "of `routerBuilder`", with: "of `defaultRouter_RouterBuilder`"))")) == "its diagnostics")
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(clauses: "\(alphaClause) and \(zedClause)", declaringTypes: "`MiddleAlpha`’s and `MiddleOmega`’s")) == "its diagnostics")
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(clauses: "\(alphaClause) and \(zedClause)", notes: [zedNote])) == "its diagnostics")
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(clauses: "\(alphaClause) and \(zedClause)", notes: [alphaNote, zedNote.replacingOccurrences(of: "`logger: Logger`", with: "`logger: Logger?`")])) == "its diagnostics")
		// A clause whose call is of a seam that builds `Flow`, named as written, sorts as a clause too.
		let zedRelayClause = zedClause.replacingOccurrences(of: "instantiates `Flow` again (`flowBuilder`)", with: "instantiates `Relay` (`relayBuilder`), which instantiates `Flow` again")
		#expect(GraphFuzzerToolOutcome.difference(between: diagnostics(clauses: "\(alphaClause) and \(zedRelayClause)"), and: diagnostics(clauses: "\(zedRelayClause) and \(reorderedAlphaClause)", declaringTypes: "`MiddleZed`’s and `MiddleAlpha`’s", notes: [zedNote, alphaNote])) == nil)
		#expect(GraphFuzzerToolOutcome.difference(between: diagnostics(clauses: "\(alphaClause) and \(zedRelayClause)"), and: diagnostics(clauses: "\(alphaClause) and \(zedRelayClause.replacingOccurrences(of: "`Relay`", with: "`Hub`"))")) == "its diagnostics")
	}

	@Test
	func differences_reportNothing_whenFieldOfReenteringPlaceListsItsTypesSeamsAndCallsInAnotherOrder() {
		// A renaming reorders the lists of a fill's error about a value its seam, opened again, loses, which follow names. Another
		// type, seam or call in one list still differs.
		func outcome(_ first: String, _ second: String, call: String = "Builder") -> GraphFuzzerToolOutcome {
			.rejected(diagnostics: "/F/Impl.swift:3:2: error: `Impl` receives `id: Int?`, which the builder for `\(first)Owner`’s `service: any Service` and `\(second)Owner`’s `service: any Service` carries from `\(first)Screen` and `\(second)Screen`, and each of their fills instantiates `\(first)Seam` and `\(second)Seam` again (`\(first)\(call)` and `\(second)Builder`). Inline, `Impl` would read `\(first)Screen`’s or `\(second)Screen`’s `id` inside that `\(first)Seam` or `\(second)Seam`, but those calls pass the builder on as module `App` fills it, whose scope there does not carry `id`, so `Impl` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let id: Int?` on `\(first)Seam` and `\(second)Seam`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Service` in module `Feature`.")
		}

		#expect(GraphFuzzerToolOutcome.differences(between: outcome("A", "B"), and: outcome("B", "A")) == [])
		#expect(GraphFuzzerToolOutcome.difference(between: outcome("A", "B"), and: outcome("B", "C")) == "its diagnostics")
		#expect(GraphFuzzerToolOutcome.difference(between: outcome("A", "B"), and: outcome("B", "A", call: "Factory")) == "its diagnostics")
		// Calls of seams that build the seam built again, named as written.
		func relayOutcome(_ first: String, _ second: String) -> GraphFuzzerToolOutcome {
			.rejected(diagnostics: "/F/Impl.swift:3:2: error: `Impl` receives `id: Int?`, which the builder for `Owner`’s `service: any Service` carries from `Screen`, and that builder’s fill instantiates `\(first)Relay` and `\(second)Relay` (`\(first)Builder` and `\(second)Builder`), which instantiate `Seam` again. Inline, `Impl` would read `Screen`’s `id` inside that `Seam`, but those calls pass the builder on as module `App` fills it, whose scope there does not carry `id`, so `Impl` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let id: Int?` on `Seam`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Service` in module `Feature`.")
		}
		#expect(GraphFuzzerToolOutcome.differences(between: relayOutcome("A", "B"), and: relayOutcome("B", "A")) == [])
		#expect(GraphFuzzerToolOutcome.difference(between: relayOutcome("A", "B"), and: relayOutcome("B", "C")) == "its diagnostics")
	}

	@Test
	func differences_reportNothing_whenFieldOfReenteringPlaceListsRelaysBesideDirectCallInAnotherOrder() {
		// A fill that opens the seam again both directly and through two seams that build it lists the direct call first, then
		// the relays and their calls, which follow names. Another relay or call in that list still differs.
		func outcome(_ first: String, _ second: String) -> GraphFuzzerToolOutcome {
			.rejected(diagnostics: "/F/Impl.swift:3:2: error: `Impl` receives `id: Int?`, which the builder for `Owner`’s `service: any Service` carries from `Screen`, and that builder’s fill instantiates `Seam` again (`seamBuilder`) and `\(first)Relay` and `\(second)Relay` (`\(first)Builder` and `\(second)Builder`), which instantiate `Seam` again. Inline, `Impl` would read `Screen`’s `id` inside that `Seam`, but those calls pass the builder on as module `App` fills it, whose scope there does not carry `id`, so `Impl` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let id: Int?` on `Seam`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Service` in module `Feature`.")
		}
		#expect(GraphFuzzerToolOutcome.differences(between: outcome("A", "B"), and: outcome("B", "A")) == [])
		#expect(GraphFuzzerToolOutcome.difference(between: outcome("A", "B"), and: outcome("B", "C")) == "its diagnostics")
	}

	@Test
	func diagnosticEntries_sortsEachErrorsNotesWithTheirFixIts_whenNotesFollowAnError() {
		// Each note keeps the fix-it line after it, the lines before an error's first note stay with the error, and notes never
		// move to another error.
		let diagnostics = [
			"/a/B.swift:1:1: error: second",
			"/a/B.swift:1:1-1:2: fixit: of the second",
			"/a/Z.swift:2:1: note: z",
			"/a/A.swift:3:1: note: a",
			"/a/A.swift:3:1-3:2: fixit: of a",
			"/a/A.swift:1:1: error: first",
			"/a/Y.swift:4:1: note: y",
		].joined(separator: "\n")

		#expect(GraphFuzzerToolOutcome.diagnosticEntries(of: diagnostics) == [
			"/a/A.swift:1:1: error: first\n/a/Y.swift:4:1: note: y",
			"/a/B.swift:1:1: error: second\n/a/B.swift:1:1-1:2: fixit: of the second\n/a/A.swift:3:1: note: a\n/a/A.swift:3:1-3:2: fixit: of a\n/a/Z.swift:2:1: note: z",
		])
	}

	@Test
	func difference_reportsDiagnostics_whenDiagnosticsDifferInMoreThanTheOrderOfTheirSuggestions() {
		func diagnostics(chain: String, suggestions: String) -> GraphFuzzerToolOutcome {
			.rejected(diagnostics: "/a/<fixture-directory>/S12_T1.swift:7:2: error: @Received property `t4: S12_T3` is not @Instantiated or @Forwarded in chain: \(chain). Did you mean one of \(suggestions)?")
		}
		let original = diagnostics(chain: "S12_Root0 -> S12_T1", suggestions: "`t3: S12_T3`, `t6: S12_T3`")

		// Another suggestion, one more suggestion, and the same suggestions in another order in another message.
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(chain: "S12_Root0 -> S12_T1", suggestions: "`t3: S12_T3`, `t5: S12_T3`")) == "its diagnostics")
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(chain: "S12_Root0 -> S12_T1", suggestions: "`t3: S12_T3`, `t4: Instantiator<S12_T3>`, `t6: S12_T3`")) == "its diagnostics")
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(chain: "S12_Root1 -> S12_T1", suggestions: "`t6: S12_T3`, `t3: S12_T3`")) == "its diagnostics")
	}

	@Test
	func finding_isKnownIssue_whenRenamedGraphDiffersAsDocumented() {
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "A shape whose mock follows the order of names",
			signatures: [.renamedGraphDiffers(.mockCode)],
			seeds: [12],
		)
		let failure = GraphFuzzerFailure(
			seed: 12,
			kind: .renamedGraphDiffers,
			details: "Reversing its labels changes its generated mock code, in S12_T0+SafeDIMock.swift.\nThis graph:\n…",
			renamedGraphDifference: .mockCode,
		)
		let diagnosticsFailure = GraphFuzzerFailure(
			seed: 12,
			kind: .renamedGraphDiffers,
			details: "Reversing its labels changes its diagnostics.\nThis graph:\nchanges its generated mock code",
			renamedGraphDifference: .diagnostics,
		)

		#expect(GraphFuzzerFinding(failure: failure, knownIssue: knownIssue) == .knownIssue(knownIssue, failure))
		#expect(GraphFuzzerFinding(failure: diagnosticsFailure, knownIssue: knownIssue) == .failure(diagnosticsFailure))
	}

	// MARK: Multi-module partition

	@Test
	func partition_keepsLazyCycleInOneModule_whenInstantiatorsCloseIt() {
		// `Root0` instantiates `T1`, which instantiates `T2` through an instantiator, which instantiates `T1` through
		// one: a lazy cycle, whose types must share a module. `T3` refers to nothing and nothing refers to it.
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"]),
			Self.typeSource(named: "S12_T1", properties: ["@Instantiated let t2Builder: Instantiator<S12_T2>"]),
			Self.typeSource(named: "S12_T2", properties: ["@Instantiated let t1Builder: Instantiator<S12_T1>"]),
			Self.typeSource(named: "S12_T3", properties: []),
		])

		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 4)

		#expect(partition.modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [1, 2], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Beta", fileIndices: [0], referencedModuleNames: ["Alpha"], dependencies: ["Alpha"]),
			GraphFuzzerPartition.Module(name: "Gamma", fileIndices: [3], referencedModuleNames: [], dependencies: []),
		])
		#expect(partition.importedModuleNamesByFileIndex == [["Alpha"], [], [], []])
	}

	@Test
	func partitionDescription_listsEachModuleWithItsDependenciesAndFilesImports_whenModulesDependOnOneAnother() {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"]),
			Self.typeSource(named: "S12_T1", properties: ["@Instantiated let t2Builder: Instantiator<S12_T2>"]),
			Self.typeSource(named: "S12_T2", properties: ["@Instantiated let t1Builder: Instantiator<S12_T1>"]),
			Self.typeSource(named: "S12_T3", properties: []),
		])

		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 4)

		#expect(partition.description == """
		Alpha: S12_T1.swift, S12_T2.swift
		Beta (depends on Alpha): S12_Root0.swift importing Alpha
		Gamma: S12_T3.swift
		""")
	}

	@Test
	func partition_listsEveryModuleATreeReachesAsDependency_whenModulesFormChain() {
		// `Root0`'s tree reaches `T2` through `T1`, so `Root0`'s module must read `T2`'s `.safedi` as well as `T1`'s,
		// as a Bazel user must list it, while its file imports only `T1`'s module.
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"]),
			Self.typeSource(named: "S12_T1", properties: ["@Instantiated let t2: S12_T2"]),
			Self.typeSource(named: "S12_T2", properties: []),
		])

		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 3)

		#expect(partition.modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [2], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Beta", fileIndices: [1], referencedModuleNames: ["Alpha"], dependencies: ["Alpha"]),
			GraphFuzzerPartition.Module(name: "Gamma", fileIndices: [0], referencedModuleNames: ["Beta"], dependencies: ["Alpha", "Beta"]),
		])
		#expect(partition.importedModuleNamesByFileIndex == [["Beta"], ["Alpha"], []])
	}

	@Test
	func partition_dealsComponentsOutToFewerModules_whenModuleCountIsBelowComponentCount() {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"]),
			Self.typeSource(named: "S12_T1", properties: ["@Instantiated let t2: S12_T2"]),
			Self.typeSource(named: "S12_T2", properties: []),
		])

		// The three components, `T2`, `T1`, and `Root0`, are dealt out in that order: the first two to `Alpha`.
		#expect(GraphFuzzerPartition.partition(of: fixture, moduleCount: 2).modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [1, 2], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Beta", fileIndices: [0], referencedModuleNames: ["Alpha"], dependencies: ["Alpha"]),
		])
		#expect(GraphFuzzerPartition.partition(of: fixture, moduleCount: 1).modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [0, 1, 2], referencedModuleNames: [], dependencies: []),
		])
	}

	@Test
	func partition_refersToModuleDeclaringErasedType_whenFileNamesOnlyTheErasedType() {
		// `T1` receives `T2`'s erased type, declared beside `T2`, and nothing names `T2` itself.
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_T1", properties: ["@Received let anyT2: S12_AnyT2"]),
			Self.typeSource(named: "S12_T2", properties: [], declaresHelperTypes: true),
		])

		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 2)

		#expect(partition.modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [1], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Beta", fileIndices: [0], referencedModuleNames: ["Alpha"], dependencies: ["Alpha"]),
		])
	}

	@Test
	func partition_refersToModuleDeclaringProtocol_whenFileNamesOnlyTheProtocol() {
		// `T1` aliases `t2` as `T2`'s protocol, declared beside `T2`, and nothing names `T2` itself.
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_T1", properties: ["@Received(fulfilledByDependencyNamed: \"t2\", ofType: S12_T2Protocol.self) let t2Protocol: S12_T2Protocol"]),
			Self.typeSource(named: "S12_T2", properties: [], declaresHelperTypes: true),
		])

		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 2)

		#expect(partition.modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [1], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Beta", fileIndices: [0], referencedModuleNames: ["Alpha"], dependencies: ["Alpha"]),
		])
	}

	@Test
	func partition_movesHelperTypesIntoTheirOwnFile_whenRootFileDeclaresThem() {
		// The generator declares `Value` and `Unbuildable<n>` in `Root0`'s file. `T1` names `Value`, so left there, `T1`
		// and `Root0` would refer to each other and share a module; moved, the helper file lands first and the root's
		// module depends on `T1`'s.
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"])
				+ "\npublic final class S12_Value: Instantiable {}\n\npublic final class S12_Unbuildable0 {}\n",
			Self.typeSource(named: "S12_T1", properties: ["@Received let items: Instantiator<S12_Value>"]),
		])

		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 3)

		#expect(partition.fileNames == ["S12_Root0.swift", "S12_T1.swift", "S12_Helpers.swift"])
		#expect(partition.modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [2], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Beta", fileIndices: [1], referencedModuleNames: ["Alpha"], dependencies: ["Alpha"]),
			GraphFuzzerPartition.Module(name: "Gamma", fileIndices: [0], referencedModuleNames: ["Beta"], dependencies: ["Alpha", "Beta"]),
		])
		let modules = partition.moduleFixtures(of: fixture)
		#expect(modules.map(\.swiftFileContent) == [[], ["import Alpha\n\n" + fixture.swiftFileContent[1]], ["import Beta\n\n" + Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"])]])
		#expect(modules.map(\.swiftFileContentByFilePath) == [["S12_Helpers.swift": "public final class S12_Value: Instantiable {}\n\npublic final class S12_Unbuildable0 {}\n"], [:], [:]])
	}

	@Test
	func partition_putsHelperFileInFirstModule_whenOnlyATypeNoRootReachesNamesIt() {
		// Visited in file order, the helper file would be met from `T2`, after the roots' components; visited first, it
		// is the first component wherever it is named from.
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"])
				+ "\npublic final class S12_Value: Instantiable {}\n",
			Self.typeSource(named: "S12_T1", properties: []),
			Self.typeSource(named: "S12_T2", properties: ["@Received let items: Instantiator<S12_Value>"]),
		])

		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 4)

		#expect(partition.fileNames == ["S12_Root0.swift", "S12_T1.swift", "S12_T2.swift", "S12_Helpers.swift"])
		#expect(partition.modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [3], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Beta", fileIndices: [1], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Gamma", fileIndices: [0], referencedModuleNames: ["Beta"], dependencies: ["Beta"]),
			GraphFuzzerPartition.Module(name: "Delta", fileIndices: [2], referencedModuleNames: ["Alpha"], dependencies: ["Alpha"]),
		])
	}

	@Test
	func moduleFixtures_prependImportOfEachReferencedModule_whenFilesReferToOtherModules() {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1", "@Instantiated let t2: S12_T2"]),
			Self.typeSource(named: "S12_T1", properties: []),
			Self.typeSource(named: "S12_T2", properties: []),
		])
		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 3)

		let modules = partition.moduleFixtures(of: fixture)

		#expect(modules.map(\.name) == ["Alpha", "Beta", "Gamma"])
		#expect(modules.map(\.packageName) == ["Graph", "Graph", "Graph"])
		#expect(modules.map(\.dependencies) == [[], [], ["Alpha", "Beta"]])
		#expect(modules.map(\.swiftFileContent) == [
			[fixture.swiftFileContent[1]],
			[fixture.swiftFileContent[2]],
			["import Alpha\nimport Beta\n\n" + fixture.swiftFileContent[0]],
		])
		#expect(modules.map(\.swiftFileContentByFilePath) == [[:], [:], [:]])
	}

	@Test
	func moduleFixtures_keepEachFileInItsModuleUnderRenamedNames_whenRenamingReversesTypeAndFileNames() {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_T1", properties: ["@Instantiated let t2: S12_T2"]),
			Self.typeSource(named: "S12_T2", properties: []),
		])
		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 2)
		let renaming = GraphFuzzerRenaming(reversesTypeNames: true, reversesLabels: false, reversesFileNames: true)

		let modules = partition.moduleFixtures(of: fixture, renamedBy: renaming)

		// `T2`, in `Alpha`, becomes `T7`, and `T1`, in `Beta`, becomes `T8`; the files are named to reverse their order.
		#expect(modules.map(\.name) == ["Alpha", "Beta"])
		#expect(modules.map(\.swiftFileContent) == [[], []])
		#expect(modules[0].swiftFileContentByFilePath == ["F99_S12_T7.swift": Self.typeSource(named: "S12_T7", properties: [])])
		#expect(modules[1].swiftFileContentByFilePath == ["F98_S12_T8.swift": "import Alpha\n\n" + Self.typeSource(named: "S12_T8", properties: ["@Instantiated let t2: S12_T7"])])
	}

	@Test
	func moduleCount_variesWithTheGraph_acrossSmokeSeeds() {
		// Chosen from the graph's text, so that single-module graphs stay in the corpus beside the others.
		let moduleCounts = Set(Self.smokeSeeds.map { seed in
			GraphFuzzerPartition.partition(of: GraphFuzzerGenerator.fixture(forSeed: seed)).modules.count
		})

		#expect(moduleCounts.contains(1))
		#expect(moduleCounts.contains(2))
		#expect(moduleCounts.contains { $0 >= 3 })
		#expect(moduleCounts.allSatisfy { (1...GraphFuzzerPartition.moduleNames.count).contains($0) })
	}

	@Test
	func partition_matchesReferenceHash_forSmokeAndKnownIssueSeeds() {
		// The partition draws nothing from the seed, so a change to it changes neither the graphs nor the pins on
		// them; this pins the partition itself, so a change to it is deliberate. The long run pins it for the corpus.
		let seeds = Self.smokeSeeds + Self.knownIssues.flatMap(\.seeds)
		#expect(Self.partitionHash(forSeeds: seeds) == Self.smokeAndKnownIssuePartitionHash)
	}

	@Test
	func generatedModule_splitsCombinedFileIntoUnitsNamedAsThePluginNamesItsFiles_whenFileHoldsATreeMocksAndConfigurations() {
		var module = GraphFuzzerGeneratedModule(units: [:], importsByFileName: [:], warnings: [])

		GraphFuzzerGeneratedModule.parsingGeneratedFile("""
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if canImport(Alpha)
		import Alpha
		#endif
		#if canImport(Beta)
		import Beta
		#endif

		extension S12_Root0 {
		    public convenience init() {
		        let t1 = S12_T1()
		        self.init(t1: t1)
		    }
		}

		#if DEBUG
		extension S12_T1 {
		    static func mock(
		    ) -> S12_T1 {
		        S12_T1()
		    }
		}
		#endif

		#if DEBUG
		extension S12_T1 {
		    struct SafeDIMockConfiguration {
		    }
		}
		#endif

		#if DEBUG
		extension S12_T2 {
		    struct SafeDIMockConfiguration {
		    }
		}

		extension S12_T3 {
		    struct SafeDIMockConfiguration {
		    }
		}
		#endif

		""", named: "Gamma.swift", into: &module)

		#expect(module.importsByFileName == ["Gamma.swift": ["import Alpha", "import Beta"]])
		#expect(module.units == [
			"S12_Root0+SafeDI.swift": """
			extension S12_Root0 {
			    public convenience init() {
			        let t1 = S12_T1()
			        self.init(t1: t1)
			    }
			}
			""",
			"S12_T1+SafeDIMock.swift": """
			#if DEBUG
			extension S12_T1 {
			    static func mock(
			    ) -> S12_T1 {
			        S12_T1()
			    }
			}
			#endif
			""",
			"S12_T1+SafeDIMockConfiguration.swift": """
			#if DEBUG
			extension S12_T1 {
			    struct SafeDIMockConfiguration {
			    }
			}
			#endif
			""",
			"S12_T2+SafeDIMockConfiguration.swift": """
			#if DEBUG
			extension S12_T2 {
			    struct SafeDIMockConfiguration {
			    }
			}
			#endif
			""",
			"S12_T3+SafeDIMockConfiguration.swift": """
			#if DEBUG
			extension S12_T3 {
			    struct SafeDIMockConfiguration {
			    }
			}
			#endif
			""",
		])
	}

	@Test
	func generatedModule_unitesUnitsAndKeepsImportsPerFile_whenSeveralFilesAreParsedOneAfterAnother() {
		var module = GraphFuzzerGeneratedModule(units: [:], importsByFileName: [:], warnings: [])

		GraphFuzzerGeneratedModule.parsingGeneratedFile("#if canImport(Alpha)\nimport Alpha\n#endif\n\nextension S12_Root0 {\n}\n", named: "S12_Root0+SafeDI.swift", into: &module)
		GraphFuzzerGeneratedModule.parsingGeneratedFile("#if canImport(Alpha)\nimport Alpha\n#endif\n#if canImport(Beta)\nimport Beta\n#endif\n\n#if DEBUG\nextension S12_T1 {\n    static func mock() -> S12_T1 {\n    }\n}\n#endif\n", named: "S12_T1+SafeDIMock.swift", into: &module)
		GraphFuzzerGeneratedModule.parsingGeneratedFile("#if canImport(Alpha)\nimport Alpha\n#endif\n", named: "SafeDIMockConfiguration.swift", into: &module)

		#expect(module.importsByFileName == [
			"S12_Root0+SafeDI.swift": ["import Alpha"],
			"S12_T1+SafeDIMock.swift": ["import Alpha", "import Beta"],
			"SafeDIMockConfiguration.swift": ["import Alpha"],
		])
		#expect(module.units.keys.sorted() == ["S12_Root0+SafeDI.swift", "S12_T1+SafeDIMock.swift"])
	}

	@Test
	func multiModuleDifference_isNil_whenPluginReportsSkippedModulesDiagnosticsAtFirstConsumerThatGenerates() {
		let diagnostics = "/a/<fixture-directory>/Graph/Sources/Alpha/S12_T7.swift:1:1: error: Found multiple @Instantiable types or extensions that fulfill `S12_T7Protocol`."
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .rejected(diagnostics: diagnostics)),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .skipped),
			.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: [:]))),
			.init(moduleName: "Gamma", kind: .rejected(diagnostics: "/b/<fixture-directory>/Graph/Sources/Alpha/S12_T7.swift:1:1: error: Found multiple @Instantiable types or extensions that fulfill `S12_T7Protocol`.")),
		])

		// `Beta` does not depend on `Alpha`, so its generate never reads `Alpha`'s files; `Gamma`'s is the first that does.
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[], [], ["Alpha"]])) == nil)
	}

	@Test
	func multiModuleDifference_reportsVerdict_whenConsumerThatDependsOnSkippedModuleAcceptsIt() {
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .rejected(diagnostics: "/a/<fixture-directory>/Graph/Sources/Alpha/S12_T7.swift:1:1: error: Found multiple @Instantiable types or extensions that fulfill `S12_T7Protocol`.")),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .skipped),
			.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: [:]))),
		])

		// `Beta` depends on `Alpha`, so its generate read `Alpha`'s files and should have reported the defect.
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[], ["Alpha"]])) == "its verdict for module Alpha (.moduleInfo rejects it, while .swiftPackagePlugin plans no output for it and accepts module Beta, which depends on it)")
	}

	@Test
	func multiModuleDifference_isNil_whenNoModuleThePluginGeneratesDependsOnTheModuleItSkipsAndModuleInfoRejects() {
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": "extension S12_Root0 {\n}"]))),
			.init(moduleName: "Beta", kind: .rejected(diagnostics: "/a/<fixture-directory>/Graph/Sources/Beta/S12_T7.swift:1:1: error: Found multiple")),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": "extension S12_Root0 {\n}"]))),
			.init(moduleName: "Beta", kind: .skipped),
			.init(moduleName: "Gamma", kind: .accepted(Self.generatedModule(units: [:]))),
		])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[], [], ["Alpha"]])) == nil)
	}

	@Test
	func multiModuleDifference_namesFirstModuleAndUnitWhoseCodeDiffers_whenUnitsOfSeveralModulesDiffer() {
		let rootCode = "extension S12_Root0 {\n    public convenience init() {\n    }\n}"
		let mockCode = "#if DEBUG\nextension S12_T1 {\n    static func mock() -> S12_T1 {\n    }\n}\n#endif"
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_T1+SafeDIMock.swift": mockCode]))),
			.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": rootCode]))),
		])
		func pluginOutcome(mockCode: String, rootCode: String) -> GraphFuzzerMultiModuleOutcome {
			GraphFuzzerMultiModuleOutcome(verdicts: [
				.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_T1+SafeDIMock.swift": mockCode]))),
				.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": rootCode]))),
			])
		}
		let modules = Self.chainOfModules(dependencies: [[], ["Alpha"]])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome(mockCode: mockCode, rootCode: rootCode), modules: modules) == nil)
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome(mockCode: mockCode + "\n", rootCode: rootCode + "\n"), modules: modules) == "the generated mock code of module Alpha, in S12_T1+SafeDIMock.swift")
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome(mockCode: mockCode, rootCode: rootCode + "\n"), modules: modules) == "the generated dependency tree code of module Beta, in S12_Root0+SafeDI.swift")
	}

	@Test
	func multiModuleDifference_namesPluginFileWhoseImportsDiffer_whenOneOfTwoPluginFilesLacksAnImport() {
		// The combined file imports what the dependency trees and the mocks need together; without `#if`, every one of
		// the plugin's files must import the same, so a mock file lacking an import is not covered by a tree file having it.
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:]))),
			.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: [:], importsByFileName: ["Beta.swift": ["import Alpha"]]))),
		])
		func pluginOutcome(mockFileImports: [String]) -> GraphFuzzerMultiModuleOutcome {
			GraphFuzzerMultiModuleOutcome(verdicts: [
				.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:]))),
				.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: [:], importsByFileName: [
					"S12_Root0+SafeDI.swift": ["import Alpha"],
					"S12_T1+SafeDIMock.swift": mockFileImports,
				]))),
			])
		}
		let modules = Self.chainOfModules(dependencies: [[], ["Alpha"]])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome(mockFileImports: ["import Alpha"]), modules: modules) == nil)
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome(mockFileImports: []), modules: modules) == "the imports of module Beta's generated file S12_T1+SafeDIMock.swift ( under .swiftPackagePlugin, against import Alpha under .moduleInfo)")
	}

	@Test
	func multiModuleDifference_reportsModuleThePluginSkips_onlyWhenModuleInfoGeneratesCodeForIt() {
		let modules = Self.chainOfModules(dependencies: [[]])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [.init(moduleName: "Alpha", kind: .skipped)])

		#expect(GraphFuzzerMultiModuleOutcome.difference(
			betweenModuleInfo: GraphFuzzerMultiModuleOutcome(verdicts: [.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:])))]),
			andPlugin: pluginOutcome,
			modules: modules,
		) == nil)
		#expect(GraphFuzzerMultiModuleOutcome.difference(
			betweenModuleInfo: GraphFuzzerMultiModuleOutcome(verdicts: [.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_T1+SafeDIMock.swift": "#if DEBUG\nextension S12_T1 {\n}\n#endif"])))]),
			andPlugin: pluginOutcome,
			modules: modules,
		) == "the generated units of module Alpha (S12_T1+SafeDIMock.swift under .moduleInfo, while .swiftPackagePlugin plans no output for it)")
	}

	@Test
	func multiModuleDifference_reportsVerdict_whenOnlyOneIntegrationRejectsAModule() {
		let modules = Self.chainOfModules(dependencies: [[], ["Alpha"]])
		let accepted = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:]))),
			.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: [:]))),
		])
		let rejectedBeta = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:]))),
			.init(moduleName: "Beta", kind: .rejected(diagnostics: "error")),
		])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: accepted, andPlugin: rejectedBeta, modules: modules) == "its verdict for module Beta (.moduleInfo accepts it, .swiftPackagePlugin rejects it)")
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: rejectedBeta, andPlugin: accepted, modules: modules) == "its verdict for module Beta (.moduleInfo rejects it, .swiftPackagePlugin accepts it)")
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: rejectedBeta, andPlugin: rejectedBeta, modules: modules) == nil)
	}

	@Test
	func multiModuleDifference_namesUnitsOfBothIntegrations_whenOnlyThePluginGeneratesAUnit() {
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": "extension S12_Root0 {\n}"]))),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [
				"S12_Root0+SafeDI.swift": "extension S12_Root0 {\n}",
				"S12_T1+SafeDIMock.swift": "#if DEBUG\nextension S12_T1 {\n}\n#endif",
			]))),
		])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[]])) == "the generated units of module Alpha (S12_Root0+SafeDI.swift under .moduleInfo, S12_Root0+SafeDI.swift, S12_T1+SafeDIMock.swift under .swiftPackagePlugin)")
	}

	@Test
	func multiModuleDifference_reportsWarnings_whenOnlyTheWarningsDiffer() {
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:], warnings: ["<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:8:2: warning: one", "<fixture-directory>/Graph/Sources/Alpha/S12_T2.swift:8:2: warning: two"]))),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:], warnings: ["<fixture-directory>/Graph/Sources/Alpha/S12_T2.swift:8:2: warning: two", "<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:8:2: warning: one"]))),
		])
		let otherWarningsPluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:], warnings: ["<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:8:2: warning: one"]))),
		])
		let modules = Self.chainOfModules(dependencies: [[]])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: modules) == nil)
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: otherWarningsPluginOutcome, modules: modules) == "the warnings of module Alpha")
	}

	@Test
	func multiModuleDifference_reportsDiagnostics_whenBothIntegrationsRejectAModuleWithOtherDiagnostics() {
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .rejected(diagnostics: "/a/<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:7:2: error: first")),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .rejected(diagnostics: "/b/<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:7:2: error: second")),
		])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[]])) == "the diagnostics of module Alpha")
	}

	@Test
	func multiModuleDifference_reportsDiagnosticsNamingConsumer_whenConsumerReportsOtherDiagnosticsForSkippedModule() {
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .rejected(diagnostics: "/a/<fixture-directory>/Graph/Sources/Alpha/S12_T7.swift:1:1: error: Found multiple @Instantiable types or extensions that fulfill `S12_T7Protocol`.")),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .skipped),
			.init(moduleName: "Beta", kind: .skipped),
			.init(moduleName: "Gamma", kind: .rejected(diagnostics: "/b/<fixture-directory>/Graph/Sources/Gamma/S12_Root0.swift:8:2: error: another")),
		])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[], [], ["Alpha"]])) == "the diagnostics of module Alpha (which .swiftPackagePlugin reports in module Gamma)")
	}

	@Test
	func multiModuleDifference_isNil_whenPluginRejectsModuleNotDependingOnSkippedOneBeforeAnyConsumerGenerates() {
		// `Beta` does not depend on `Alpha`, and the module-info integration never ran it, so its rejection is not
		// compared, and `Gamma`, the consumer that would report `Alpha`'s defect, was never reached.
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .rejected(diagnostics: "/a/<fixture-directory>/Graph/Sources/Alpha/S12_T7.swift:1:1: error: Found multiple")),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .skipped),
			.init(moduleName: "Beta", kind: .rejected(diagnostics: "/b/<fixture-directory>/Graph/Sources/Beta/S12_Root0.swift:8:2: error: another")),
		])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[], [], ["Alpha"]])) == nil)
	}

	@Test
	func multiModuleDifference_comparesFirstConsumerThatGenerates_whenAnEarlierConsumerIsSkipped() {
		// `Beta` depends on `Alpha` but plans no output, so the plugin first reads `Alpha`'s files in `Gamma`'s generate.
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .rejected(diagnostics: "/a/<fixture-directory>/Graph/Sources/Alpha/S12_T7.swift:1:1: error: Found multiple @Instantiable types or extensions that fulfill `S12_T7Protocol`.")),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .skipped),
			.init(moduleName: "Beta", kind: .skipped),
			.init(moduleName: "Gamma", kind: .rejected(diagnostics: "/b/<fixture-directory>/Graph/Sources/Gamma/S12_Root0.swift:8:2: error: another")),
		])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[], ["Alpha"], ["Alpha", "Beta"]])) == "the diagnostics of module Alpha (which .swiftPackagePlugin reports in module Gamma)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func multiModuleProperty_agreesWithoutNormalizing_whenConsumerWritesDependencysRootWithoutCode() async throws {
		// `Root0` and `T1` share `Alpha`; `Root1`, in `Beta`, instantiates `T1`, so under the plugin `Beta`'s CSV holds
		// `Alpha`'s files and its `scan` plans a file for `Root0`, which `Beta` writes without code.
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"]),
			Self.typeSource(named: "S12_Root1", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"]),
			Self.typeSource(named: "S12_T1", properties: []),
		])
		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 2)
		#expect(partition.modules.map(\.fileIndices) == [[0, 2], [1]])

		let runs = try await GraphFuzzerMultiModuleProperty.runs(of: fixture, partition: partition)

		#expect(runs.failure == nil)
		#expect(Self.unitNamesByModuleName(of: runs.pluginOutcome) == ["Alpha": ["S12_Root0+SafeDI.swift"], "Beta": ["S12_Root1+SafeDI.swift"]])
		#expect(Self.unitNamesByModuleName(of: runs.moduleInfoOutcome) == ["Alpha": ["S12_Root0+SafeDI.swift"], "Beta": ["S12_Root1+SafeDI.swift"]])
	}

	@Test
	func reducingFixtureRootPaths_reducesEachSpellingOfTheFixtureRoot_whereverAPathAppears() {
		let unresolved = "/var/folders/1f/3dqdr7xs2yn_90rwj5xxhh780000gn/T/72FAAFF2-C685-4DE6-A860-FA097D2CFDB8/Graph/Sources/Alpha/S12_T1.swift"
		let resolved = "/private/var/folders/1f/3dqdr7xs2yn_90rwj5xxhh780000gn/T/72FAAFF2-C685-4DE6-A860-FA097D2CFDB8/Graph/Sources/Alpha/S12_T1.swift"
		let linux = "/tmp/72FAAFF2-C685-4DE6-A860-FA097D2CFDB8/Graph/Sources/Alpha/S12_T1.swift"

		#expect(GraphFuzzerMultiModuleProperty.reducingFixtureRootPaths(in: "\(unresolved):8:2: error: one") == "<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:8:2: error: one")
		#expect(GraphFuzzerMultiModuleProperty.reducingFixtureRootPaths(in: "\(resolved):8:2: error: one") == "<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:8:2: error: one")
		#expect(GraphFuzzerMultiModuleProperty.reducingFixtureRootPaths(in: "\(linux):8:2: error: one") == "<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:8:2: error: one")
		#expect(GraphFuzzerMultiModuleProperty.reducingFixtureRootPaths(in: "            #sourceLocation(file: \"\(resolved)\", line: 8)") == "            #sourceLocation(file: \"<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift\", line: 8)")
		#expect(GraphFuzzerMultiModuleProperty.reducingFixtureRootPaths(in: "chain: S12_Root0 -> S12_T1 at \(unresolved) and \(resolved)") == "chain: S12_Root0 -> S12_T1 at <fixture-directory>/Graph/Sources/Alpha/S12_T1.swift and <fixture-directory>/Graph/Sources/Alpha/S12_T1.swift")
		#expect(GraphFuzzerMultiModuleProperty.reducingFixtureRootPaths(in: "/Users/someone/Graph/Sources/Alpha/S12_T1.swift:8:2: error: one") == "/Users/someone/Graph/Sources/Alpha/S12_T1.swift:8:2: error: one")
	}

	@Test
	func finding_isKnownIssue_whenIntegrationsDifferAsDocumented() {
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "A shape whose mock differs between the integrations",
			signatures: [.integrationsDiffer(containing: "the generated mock code")],
			seeds: [12],
		)
		let failure = GraphFuzzerFailure(
			seed: 12,
			kind: .integrationsDiffer,
			details: "Split into modules, the graph differs between the .moduleInfo and .swiftPackagePlugin integrations in the generated mock code of module Alpha, in S12_T0+SafeDIMock.swift.\nModules:\n…",
		)
		let verdictFailure = GraphFuzzerFailure(
			seed: 12,
			kind: .integrationsDiffer,
			details: "Split into modules, the graph differs between the .moduleInfo and .swiftPackagePlugin integrations in its verdict for module Alpha.\nModules:\nthe generated mock code",
		)

		#expect(GraphFuzzerFinding(failure: failure, knownIssue: knownIssue) == .knownIssue(knownIssue, failure))
		#expect(GraphFuzzerFinding(failure: verdictFailure, knownIssue: knownIssue) == .failure(verdictFailure))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_generateTheSameCodeUnderBothMultiModuleIntegrations_whenSplitAcrossModules() async throws {
		for result in try await smokeResults.value {
			#expect(result.multiModuleRuns.count == GraphFuzzerOracle.multiModuleRenamings.count)
			for failure in result.multiModuleFailures {
				Issue.record(failure.issueComment(fixture: result.fixture))
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_includeAcceptedAndRejectedGraphsSplitIntoSeveralModules_whenRunThroughMultiModuleIntegrations() async throws {
		let runs = try await smokeResults.value.flatMap(\.multiModuleRuns).filter { $0.renaming == nil }

		// Some graphs are rejected with several modules, so that the diagnostics of a split graph are compared too.
		#expect(runs.contains { $0.isAccepted && $0.partition.modules.count > 1 })
		#expect(runs.contains { !$0.isAccepted && $0.partition.modules.count > 1 })
	}

	/// The source of a `final class` `@Instantiable` type, as the generator emits one, with its helper types when asked.
	private static func typeSource(named name: String, arguments: String? = nil, properties: [String], declaresHelperTypes: Bool = false) -> String {
		var lines = [arguments.map { "@Instantiable(\($0))" } ?? "@Instantiable", "public final class \(name): Instantiable {"]
		if properties.isEmpty {
			lines.append("\tpublic init() {}")
		} else {
			let parameters = properties.map { $0.components(separatedBy: " let ")[1] }
			lines.append("\tpublic init(\(parameters.joined(separator: ", "))) {")
			lines += parameters.map { "\t\tself.\($0.prefix { $0 != ":" }) = \($0.prefix { $0 != ":" })" }
			lines.append("\t}")
			lines.append("")
			lines += properties.map { "\t\($0)" }
		}
		lines.append("}")
		if declaresHelperTypes {
			let erasedName = name.replacingOccurrences(of: "_T", with: "_AnyT")
			lines += ["", "public protocol \(name)Protocol: AnyObject {}", "", "public final class \(erasedName) {", "\tpublic init(_ value: \(name)) {", "\t\tself.value = value", "\t}", "", "\tpublic let value: \(name)", "}"]
		}
		return lines.joined(separator: "\n") + "\n"
	}

	private static func generatedModule(units: [String: String], importsByFileName: [String: [String]] = [:], warnings: [String] = []) -> GraphFuzzerGeneratedModule {
		GraphFuzzerGeneratedModule(units: units, importsByFileName: importsByFileName, warnings: warnings)
	}

	/// The names of the units each module's generated code holds, for a module the integration generated.
	private static func unitNamesByModuleName(of outcome: GraphFuzzerMultiModuleOutcome) -> [String: [String]] {
		Dictionary(uniqueKeysWithValues: outcome.verdicts.compactMap { verdict in
			switch verdict.kind {
			case let .accepted(module):
				(verdict.moduleName, module.units.keys.sorted())
			case .skipped, .rejected:
				nil
			}
		})
	}

	/// Modules `Alpha`, `Beta`, … with the given dependencies, each a closure over the modules before it.
	private static func chainOfModules(dependencies: [[String]]) -> [GraphFuzzerPartition.Module] {
		dependencies.enumerated().map { index, dependencies in
			GraphFuzzerPartition.Module(name: GraphFuzzerPartition.moduleNames[index], fileIndices: [index], referencedModuleNames: dependencies, dependencies: dependencies)
		}
	}

	// MARK: Reproducibility

	@Test
	func randomNumberGenerator_producesSplitMix64ReferenceSequence_forSeedZero() {
		var random = GraphFuzzerRandomNumberGenerator(seed: 0)
		#expect([random.next(), random.next(), random.next()] == [0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4, 0x06C45D188009454F])
	}

	@Test
	func seedSetSum_addsUpAcrossShards_whicheverOrderSeedsAreAdded() {
		var whole = GraphFuzzerSeedSetSum()
		for seed in [UInt64(3), 1, 4, 1_000, 59] {
			whole.add(seed)
		}
		var firstShard = GraphFuzzerSeedSetSum()
		var secondShard = GraphFuzzerSeedSetSum()
		for seed in [UInt64(59), 1] {
			firstShard.add(seed)
		}
		for seed in [UInt64(1_000), 3, 4] {
			secondShard.add(seed)
		}

		#expect(firstShard.value &+ secondShard.value == whole.value)
		#expect(firstShard.value != whole.value)
	}

	@Test
	func fixture_matchesReferenceHash_forSmokeAndKnownIssueSeeds() {
		// Every platform must generate the same graph for a seed, or a seed reported by the long run would not
		// reproduce elsewhere. Changing the generator changes this hash and changes which graph every seed names, so
		// re-derive the smoke and known-issue seeds when it changes; the long run pins the rest of the corpus.
		let seeds = Self.smokeSeeds + Self.knownIssues.flatMap(\.seeds)
		#expect(Self.fixtureHash(forSeeds: seeds) == Self.smokeAndKnownIssueFixtureHash)
		let seamSeeds = Self.seamSmokeSeeds + Self.seamKnownIssues.flatMap(\.seeds)
		#expect(Self.fixtureHash(forSeeds: seamSeeds, features: [.generateDependencyTree]) == Self.seamSmokeAndKnownIssueFixtureHash)
		let publicMockSeeds = Self.publicMockSmokeSeeds + Self.publicMockKnownIssues.flatMap(\.seeds)
		#expect(Self.fixtureHash(forSeeds: publicMockSeeds, features: [.generateMockPublic]) == Self.publicMockSmokeAndKnownIssueFixtureHash)
	}

	// MARK: Long run

	@Test(.enabled(if: GraphFuzzerLongRunConfiguration.current != nil, "Set SAFEDI_GRAPH_FUZZER_ITERATIONS or SAFEDI_GRAPH_FUZZER_SEEDS to run"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func longRun_findsNoUnknownFailures_whenEnabledByEnvironment() async throws {
		let configuration = try #require(GraphFuzzerLongRunConfiguration.current)
		let report = GraphFuzzerReport(path: configuration.reportPath)
		func reportProblem(_ problem: String) {
			report.append("problem \(problem)")
			Issue.record(Comment(rawValue: problem))
		}
		guard compileVerificationIsEnabled else {
			reportProblem("The graph fuzzer checks generated code by compiling it. Unset SAFEDI_SKIP_COMPILE_CHECK.")
			return
		}
		guard let features = configuration.features else {
			reportProblem("SAFEDI_GRAPH_FUZZER_FEATURES must name generator features: \(GraphFuzzerGeneratorFeature.allCases.map(\.rawValue).joined(separator: ", ")).")
			return
		}
		guard configuration.iterations > 0 else {
			reportProblem(configuration.noSeedsProblem)
			return
		}
		let corpus = Self.corpus(for: features)
		let knownIssueListProblems = Self.knownIssueListProblems(corpus.knownIssues, corpusSeedCount: corpus.seedCount)
		guard knownIssueListProblems.isEmpty else {
			knownIssueListProblems.forEach(reportProblem)
			return
		}
		let knownIssuesBySeed = Dictionary(uniqueKeysWithValues: corpus.knownIssues.flatMap { knownIssue in
			knownIssue.seeds.map { ($0, knownIssue) }
		})

		// Pin the whole corpus the long run covers, which the ordinary suite's hash covers only a sample of, and the
		// partition of every graph of it across modules, and check that no graph uses a label beginning with
		// `__safeDI_`, which the generated builder functions use.
		var generatedCorpusHash = GraphFuzzerHash()
		// The partition is pinned for the base corpus, whose graphs declare no seam and no public mock: the graphs
		// `GraphFuzzerOracle.toolRuns(of:renamings:multiModuleRenamings:)` splits.
		let isPartitioned = corpus.features.isEmpty
		var partitionedCorpusHash = GraphFuzzerHash()
		var graphCountByModuleCount = [Int](repeating: 0, count: GraphFuzzerPartition.moduleNames.count + 1)
		// The graphs whose two integrations combine declarations in different orders: see `GraphFuzzerPartition.moduleNames`.
		var deltaDependsOnGammaCount = 0
		for seed in 0..<UInt64(corpus.seedCount) {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: corpus.features)
			generatedCorpusHash.combine(fixture.description)
			if isPartitioned {
				let partition = GraphFuzzerPartition.partition(of: fixture)
				partitionedCorpusHash.combine(partition.description)
				graphCountByModuleCount[partition.modules.count] += 1
				if partition.modules.last?.name == "Delta", partition.modules.last?.dependencies.contains("Gamma") == true {
					deltaDependsOnGammaCount += 1
				}
			}
			let reservedLabels = fixture.swiftFileContent.flatMap(GraphFuzzerSourceLine.lines(of:)).compactMap { line -> String? in
				guard case let .property(_, label, _) = line, label.hasPrefix("__safeDI_") else { return nil }
				return label
			}
			if !reservedLabels.isEmpty {
				reportProblem("Seed \(seed)'s graph uses \(reservedLabels), which begin with `__safeDI_`, the prefix of generated builder functions.")
			}
		}
		if generatedCorpusHash.value != corpus.fixtureHash {
			reportProblem("The generator's graphs for seeds 0..<\(corpus.seedCount) of the \(corpus.name) corpus changed (fixture hash \(Self.hexadecimal(generatedCorpusHash.value)), pinned \(Self.hexadecimal(corpus.fixtureHash))). Re-derive the known issues, smoke seeds, and pinned values.")
		}
		if isPartitioned {
			if partitionedCorpusHash.value != Self.corpusPartitionHash {
				reportProblem("The partition of the graphs for seeds 0..<\(corpus.seedCount) across modules changed (partition hash \(Self.hexadecimal(partitionedCorpusHash.value)), pinned \(Self.hexadecimal(Self.corpusPartitionHash))). Re-derive the known issues and the pinned partition hashes.")
			}
			report.append("partitions " + graphCountByModuleCount.indices.dropFirst().map { "\($0):\(graphCountByModuleCount[$0])" }.joined(separator: " ") + " delta-depends-on-gamma:\(deltaDependsOnGammaCount)")
		}

		var graphCount = 0
		var acceptedCount = 0
		var acceptedSeedsSum = GraphFuzzerSeedSetSum()
		var acceptedFeatureCounts = [GraphFuzzerFeature: Int]()
		var valueOracleInspectedCount = 0
		var valueOracleComparedCount = 0
		var retentionCounts = GraphFuzzerRetentionCounts()
		var levelFunctionCaptureCounts = GraphFuzzerLevelFunctionCaptureCounts()
		// The graphs of each gating draw that the oracles after acceptance judged, by the draw's name.
		var gatingDrawJudgedCounts = [String: Int]()
		var readTwinGraphCount = 0
		var cleanSubtreeSkipOffGraphCount = 0
		var builderSurfaceCounts = [String: Int]()
		var acceptedSpellingDrawFeatures = Set<GraphFuzzerSeamDrawFeature>()
		var omittedValueGraphCount = 0
		var publicMockOutputFeatureCounts = [GraphFuzzerPublicMockOutputFeature: Int]()
		// The accepted graphs whose seam's own internal mock takes a builder as a closure that takes nothing.
		var seamOwnMockBuilderGraphCount = 0
		var errorGraphCounts = [String: Int]()
		var acceptedDrawFeatureCounts = [GraphFuzzerSeamDrawFeature: Int]()
		var acceptedPublicMockDrawFeatureCounts = [GraphFuzzerPublicMockDrawFeature: Int]()
		var valueOracleCounts = GraphFuzzerValueOracleCounts()
		// The remedies the remedy oracle applied, and those that left an error at their site, by kind, and the sites of a
		// family it reads that it applied none to.
		var remedyCounts = [GraphFuzzerRemedyKind: (judged: Int, failed: Int)]()
		var unremediedSiteCount = 0
		var acceptedRemedyCount = 0
		var knownIssueCount = 0
		var failureCount = 0
		// Batches run concurrently, one per core, but their findings are recorded in the run's seed order, so the report and
		// the issues are the same on every run. A batch's seeds are all finished when its results arrive.
		let batchStarts = Array(stride(from: 0, to: configuration.iterations, by: Self.longRunBatchSize))
		let concurrentBatchCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
		// What each phase of the oracle cost, which the report's `cpu` line gives with the run's wall time and the CPU
		// time of the test process and of its child processes.
		let phaseAccount = GraphFuzzerPhaseAccount()
		let phaseContext = GraphFuzzerPhaseAccount.Context(account: phaseAccount, phase: nil)
		let startNanoseconds = DispatchTime.now().uptimeNanoseconds
		let startProcessCPUSeconds = GraphFuzzerPhaseAccount.processCPUSeconds()
		let startChildProcessCPUSeconds = GraphFuzzerPhaseAccount.childProcessCPUSeconds()
		do {
			try await withThrowingTaskGroup(of: (Int, [GraphFuzzerResult]).self) { group in
				var nextBatchIndex = 0
				func addNextBatch() {
					guard nextBatchIndex < batchStarts.count else { return }
					let batchIndex = nextBatchIndex
					let batchStart = batchStarts[batchIndex]
					let seeds = (batchStart..<min(batchStart + Self.longRunBatchSize, configuration.iterations))
						.map(configuration.seed(at:))
					nextBatchIndex += 1
					group.addTask { try await GraphFuzzerPhaseAccount.$current.withValue(phaseContext) {
						var results = try await GraphFuzzerOracle.results(forSeeds: seeds, features: corpus.features, isolatingValueGraphsOf: corpus.isolatedValueGraphSeeds, concurrentToolRuns: 1) { seed in
							report.append("seed \(seed)")
						}
						for index in results.indices where results[index].passesBesidesBuilderSurface
							&& results[index].fixture.seed % Self.crossProcessSampleInterval == 0
						{
							let fixture = results[index].fixture
							let crossProcessFailure = try await GraphFuzzerPhaseAccount.measuring(.crossProcess) {
								try await GraphFuzzerOracle.crossProcessFailure(of: fixture)
							}
							results[index] = GraphFuzzerResult(
								fixture: results[index].fixture,
								outcome: results[index].outcome,
								failure: crossProcessFailure ?? results[index].failure,
								laterFailures: crossProcessFailure == nil ? results[index].laterFailures : [results[index].failure].compactMap(\.self) + results[index].laterFailures,
								renamedGraphFailures: results[index].renamedGraphFailures,
								multiModuleRuns: results[index].multiModuleRuns,
								isInspectedByValueOracle: results[index].isInspectedByValueOracle,
								isComparedByValueOracle: results[index].isComparedByValueOracle,
								isComparedAcrossIntegrations: results[index].isComparedAcrossIntegrations,
								isComparedWithRecomputedSignatures: results[index].isComparedWithRecomputedSignatures,
								isComparedWithReadTwin: results[index].isComparedWithReadTwin,
								isComparedWithCleanSubtreeSkipOff: results[index].isComparedWithCleanSubtreeSkipOff,
								retentionCounts: results[index].retentionCounts,
								valueOracle: results[index].valueOracle,
								remedyRuns: results[index].remedyRuns,
								builderSurfaceFloorKinds: results[index].builderSurfaceFloorKinds,
								levelFunctionCaptures: results[index].levelFunctionCaptures,
							)
						}
						for result in results {
							report.append("finished \(result.fixture.seed)")
						}
						return (batchIndex, results)
					} }
				}
				for _ in 0..<concurrentBatchCount {
					addNextBatch()
				}
				var finishedBatches = [Int: [GraphFuzzerResult]]()
				var nextBatchToRecord = 0
				while let (batchIndex, results) = try await group.next() {
					finishedBatches[batchIndex] = results
					addNextBatch()
					while let results = finishedBatches.removeValue(forKey: nextBatchToRecord) {
						nextBatchToRecord += 1
						for result in results {
							let seed = result.fixture.seed
							graphCount += 1
							if result.isAccepted {
								acceptedCount += 1
								acceptedSeedsSum.add(seed)
								// Counted whether or not the graph fails, as the accepted-seed pins are, so fixing a
								// known issue changes no count.
								for feature in GraphFuzzerFeature.features(of: result.fixture, outcome: result.outcome) {
									acceptedFeatureCounts[feature, default: 0] += 1
								}
								if corpus.features.contains(.generateMockPublic), case let .accepted(generatedFiles, _) = result.outcome {
									for feature in GraphFuzzerPublicMockDraw.outputFeatures(of: result.fixture, generatedFiles: generatedFiles) {
										publicMockOutputFeatureCounts[feature, default: 0] += 1
									}
								}
								if corpus.features.contains(.generateDependencyTree), case let .accepted(generatedFiles, _) = result.outcome,
								   GraphFuzzerFeature.seamOutputFeatures(of: result.fixture, generatedFiles: generatedFiles).contains(.seamOwnMockBuilder)
								{
									seamOwnMockBuilderGraphCount += 1
								}
								if !corpus.drawFeaturesCountedWhenAccepted.isEmpty {
									for feature in GraphFuzzerFeature.seamDrawFeatures(of: result.fixture).intersection(corpus.drawFeaturesCountedWhenAccepted) {
										acceptedDrawFeatureCounts[feature, default: 0] += 1
									}
								}
								if !corpus.publicMockDrawFeaturesCountedWhenAccepted.isEmpty {
									for feature in GraphFuzzerPublicMockDraw.drawFeatures(of: result.fixture).intersection(corpus.publicMockDrawFeaturesCountedWhenAccepted) {
										acceptedPublicMockDrawFeatureCounts[feature, default: 0] += 1
									}
								}
								// As the seam smoke batch counts its shapes: a renamed graph that differs by the builder label sort its
								// entry lists still draws its spellings.
								if result.passes(butForRetentionDocumentedBy: knownIssuesBySeed[seed], butForBuilderOrderDocumentedBy: Self.seamBuilderOrderShape(listedBy: knownIssuesBySeed[seed])) {
									acceptedSpellingDrawFeatures.formUnion(GraphFuzzerFeature.seamDrawFeatures(of: result.fixture).intersection(corpus.spellingDrawFeatures))
								}
							}
							if result.isInspectedByValueOracle {
								valueOracleInspectedCount += 1
							}
							if case let .rejected(diagnostics) = result.outcome, diagnostics.split(separator: "\n").contains(where: GraphFuzzerOracle.isOmittedValueError) {
								omittedValueGraphCount += 1
							}
							// The graphs each error the corpus pins rejects: a public mock's own errors, or the errors of a cycle's
							// label in a seam's tree.
							if case let .rejected(diagnostics) = result.outcome {
								for marker in corpus.errorMarkers where diagnostics.contains(marker) {
									errorGraphCounts[marker, default: 0] += 1
								}
							}
							if result.isComparedByValueOracle {
								valueOracleComparedCount += 1
							}
							retentionCounts.add(result.retentionCounts)
							levelFunctionCaptureCounts.add(result.levelFunctionCaptureCounts)
							for draw in corpus.gatingDrawsJudged(by: result, knownIssue: knownIssuesBySeed[seed]) {
								gatingDrawJudgedCounts[draw, default: 0] += 1
							}
							for kind in result.builderSurfaceFloorKinds {
								builderSurfaceCounts[kind, default: 0] += 1
							}
							if result.isComparedWithReadTwin {
								readTwinGraphCount += 1
							}
							if result.isComparedWithCleanSubtreeSkipOff {
								cleanSubtreeSkipOffGraphCount += 1
							}
							if let valueOracle = result.valueOracle {
								valueOracleCounts.add(valueOracle, isCompared: result.isComparedByValueOracle)
							}
							for remedyRun in result.remedyRuns {
								remedyCounts[remedyRun.remedy.kind, default: (0, 0)].judged += 1
								if remedyRun.failureLine != nil {
									remedyCounts[remedyRun.remedy.kind, default: (0, 0)].failed += 1
								}
								if case .accepted = remedyRun.outcome {
									acceptedRemedyCount += 1
								}
							}
							if case let .rejected(diagnostics) = result.outcome {
								unremediedSiteCount += GraphFuzzerRemedies.unremediedSiteCount(of: result.fixture, diagnostics: diagnostics)
							}
							// Counted whether or not the graph also fails another way.
							for renamedGraphFailure in result.renamedGraphFailures {
								report.append("renamed \(seed) \(renamedGraphFailure.details.prefix { $0 != "\n" })")
							}
							for multiModuleFailure in result.multiModuleFailures {
								report.append("multimodule \(seed) \(multiModuleFailure.details.prefix { $0 != "\n" })")
							}
							for finding in GraphFuzzerFinding.findings(failure: result.failure, laterFailures: result.laterFailures, knownIssue: knownIssuesBySeed[seed], retentionIsJudged: result.isJudgedForRetention) {
								if let reportLine = finding.reportLine(seed: seed) {
									// A stale line carries the remedy, chosen by the stale issue's shape, for the summary.
									if case let .staleKnownIssue(knownIssue) = finding {
										report.append("\(reportLine); \(corpus.staleSeedRemedy(knownIssue, seed))")
									} else {
										report.append(reportLine)
									}
								}
								switch finding {
								case .knownIssue:
									knownIssueCount += 1
								case .failure:
									failureCount += 1
								case .passed, .staleKnownIssue, .staleRenamedGraphDifference, .staleBuilderSurfaceSignature, .staleLeakEntry:
									break
								}
								Self.record(finding, fixture: result.fixture)
							}
						}
					}
				}
			}
		} catch {
			reportProblem("The long run stopped after \(graphCount) graphs: \(error)")
			return
		}

		// The oracle accepts any error the tool reports, so pin which graphs the tool accepts: a change that makes
		// it reject valid graphs changes this. A shard of the corpus reports its part, which ci.yml's combine job
		// adds up, and a run of the whole corpus checks the pins itself; a run of listed seeds reports a `seeds` line.
		report.append("\(configuration.seedsReportFields) \(acceptedCount) \(Self.hexadecimal(acceptedSeedsSum.value)) \(corpus.name)")
		report.append("corpus \(corpus.seedCount) \(corpus.acceptedSeedCount) \(Self.hexadecimal(corpus.acceptedSeedsSum)) \(corpus.name)")
		// The accepted graphs that show each feature, with the pinned counts, which ci.yml's combine job adds up and
		// checks for a corpus that pins them.
		let featureCounts = GraphFuzzerFeature.allCases.map { "\($0.rawValue)=\(acceptedFeatureCounts[$0, default: 0])" }.joined(separator: ",")
		let featurePins = GraphFuzzerFeature.allCases.compactMap { feature in corpus.acceptedFeatureCounts[feature].map { "\(feature.rawValue)=\($0)" } }.joined(separator: ",")
		report.append("features \(corpus.name) \(featureCounts) \(featurePins)")
		// The value oracle's inspected graphs and the spellings drawn in accepted graphs, which ci.yml's combine job adds
		// up across shards: a draw that stops landing in accepted graphs, or an oracle that stops inspecting, fails it.
		report.append("inspected \(valueOracleInspectedCount) \(corpus.valueOracleInspectedGraphCount) \(corpus.name)")
		// The graphs the comparator compared, which a compilation failure (a known warning among them) keeps below the
		// inspected count: read from the report rather than derived.
		report.append("compared \(valueOracleComparedCount) \(corpus.name)")
		// What the retention oracle judged, with the corpus's pins, which ci.yml's combine job adds up: a change that judges
		// fewer graphs, or pairs fewer experiments, fails them.
		report.append("retention \(corpus.name) \(retentionCounts.reportField) \(corpus.retentionCounts.reportField)")
		// What the level function capture check judged, with the corpus's pins, which ci.yml's combine job adds up: a change
		// that judges fewer graphs, or stops reaching fill functions, fails them.
		report.append("level-captures \(corpus.name) \(levelFunctionCaptureCounts.reportField) \(corpus.levelFunctionCaptureCounts.reportField)")
		// The graphs of each gating draw that the oracles after acceptance judged, with the floor, which ci.yml's combine
		// job adds up: a draw gates nothing while fewer of its graphs are judged. The shapes each draw rolls are reported
		// too, against no floor: a shape the draw rolls in few graphs shows how thinly the oracles judge it.
		let gatingDraws = corpus.flooredGatingDrawNames.map { "\($0)=\(gatingDrawJudgedCounts[$0, default: 0])" }.joined(separator: ",")
		report.append("gating \(corpus.name) \(gatingDraws) \(Self.gatingDrawJudgedGraphFloor)")
		let gatingShapes = corpus.gatingDrawNames.filter { !corpus.flooredGatingDrawNames.contains($0) }.map { "\($0)=\(gatingDrawJudgedCounts[$0, default: 0])" }.joined(separator: ",")
		report.append("gating-shapes \(corpus.name) \(gatingShapes)")
		// The graphs the oracle compared with their read twin, with the pin, which ci.yml's combine job adds up: an oracle
		// that stops running the twins fails it.
		report.append("read-twins \(readTwinGraphCount) \(corpus.readTwinGraphCount) \(corpus.name)")
		// The graphs the oracle ran again with no skip of a clean subtree in the validation walk, against no pin: a run of the
		// whole corpus checks the floor below.
		report.append("clean-subtree-skips \(cleanSubtreeSkipOffGraphCount) \(corpus.name)")
		// The accepted graphs whose seam's own internal mock takes a builder as a closure that takes nothing, which ci.yml's
		// combine job adds up and checks against a floor of ten: the only count of that shape the corpus draws.
		if corpus.features.contains(.generateDependencyTree) {
			report.append("seam-mock-builders \(seamOwnMockBuilderGraphCount) \(corpus.name)")
		}
		// The graphs the builder surface judges, by kind, with the kinds whose floor the corpus must reach, which ci.yml's
		// combine job adds up and checks: a draw or an edit that stops landing in accepted graphs fails it.
		// Every corpus writes it, the base corpus, which has no holes, with no floored kind.
		let builderSurfaceCountsField = GraphFuzzerBuilderSurface.floorKinds.map { "\($0)=\(builderSurfaceCounts[$0, default: 0])" }.joined(separator: ",")
		report.append("builder-surface \(corpus.name) \(builderSurfaceCountsField) \(corpus.builderSurfaceFlooredKinds.joined(separator: ","))")
		// The graphs the tool rejects because a caller holds a value its tier omits, which ci.yml's combine job adds up.
		report.append("omitted-values \(omittedValueGraphCount) \(corpus.omittedValueGraphCount) \(corpus.name)")
		report.append("spellings \(corpus.name) \(corpus.spellingDrawFeatures.map(\.rawValue).sorted().joined(separator: ",")) \(acceptedSpellingDrawFeatures.map(\.rawValue).sorted().joined(separator: ","))")
		// The accepted graphs that show each draw the corpus counts there, with the pinned counts, and the graphs each error
		// the corpus pins rejects, with the pins, which ci.yml's combine job adds up and checks: a draw that stops landing
		// in accepted graphs, or a change that rejects more of them, names the shape.
		let drawFeatureCounts = (corpus.drawFeaturesCountedWhenAccepted.sorted().map { "\($0.rawValue)=\(acceptedDrawFeatureCounts[$0, default: 0])" }
			+ corpus.publicMockDrawFeaturesCountedWhenAccepted.sorted().map { "\($0.rawValue)=\(acceptedPublicMockDrawFeatureCounts[$0, default: 0])" }).joined(separator: ",")
		let drawFeaturePins = (corpus.acceptedDrawFeatureCounts.sorted { $0.key < $1.key }.map { "\($0.key.rawValue)=\($0.value)" }
			+ corpus.acceptedPublicMockDrawFeatureCounts.sorted { $0.key < $1.key }.map { "\($0.key.rawValue)=\($0.value)" }).joined(separator: ",")
		report.append("draws \(corpus.name) \(drawFeatureCounts) \(drawFeaturePins)")
		let errorCounts = corpus.errorMarkers.map { errorGraphCounts[$0, default: 0] }
		report.append("errors \(corpus.name) \(errorCounts.map(String.init).joined(separator: ",")) \(corpus.errorGraphCounts.map(String.init).joined(separator: ","))")
		// The output features of the accepted graphs, whether or not they fail, with each pinned minimum share as a
		// percentage of the corpus's accepted graphs, which ci.yml's combine job adds up and checks.
		if corpus.features.contains(.generateMockPublic) {
			let counts = GraphFuzzerPublicMockOutputFeature.allCases.map { "\($0.rawValue)=\(publicMockOutputFeatureCounts[$0, default: 0])" }.joined(separator: ",")
			let minimums = corpus.outputFeatureMinimumShares.sorted { $0.key < $1.key }.map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: ",")
			report.append("outputs \(corpus.name) \(counts) \(minimums)")
		}
		// What the base corpus's value oracle compared and skipped, with the pins, which ci.yml's combine job adds up.
		if let pinnedValueOracleCounts = corpus.valueOracleCounts {
			report.append("value-oracle \(corpus.name) \(valueOracleCounts.reportField) \(pinnedValueOracleCounts.reportField)")
		}
		// The remedy oracle's judgments by kind, as `judged/failed`, the sites it applied no remedy to, and the remedied graphs
		// the tool accepts, whose code the run compiles, which no pin checks: the remedy oracle's unit tests hold a
		// representative of each kind. It reads base and seam corpus graphs, in one module or split.
		if corpus.features.isEmpty || corpus.features == [.generateDependencyTree] {
			let counts = GraphFuzzerRemedyKind.allCases.map { "\($0.rawValue)=\(remedyCounts[$0]?.judged ?? 0)/\(remedyCounts[$0]?.failed ?? 0)" }.joined(separator: ",")
			report.append("remedies \(corpus.name) \(counts) unremedied=\(unremediedSiteCount) accepted=\(acceptedRemedyCount)")
		}
		// What the run cost: its wall seconds, the CPU seconds of the test process and of its child processes, and for each
		// phase the seconds batches spent in it, the CPU seconds of the processes it ran, and their number, which ci.yml's
		// combine job adds up per corpus.
		let wallSeconds = Double(DispatchTime.now().uptimeNanoseconds - startNanoseconds) / 1e9
		let processCPUSeconds = GraphFuzzerPhaseAccount.processCPUSeconds() - startProcessCPUSeconds
		let childProcessCPUSeconds = GraphFuzzerPhaseAccount.childProcessCPUSeconds() - startChildProcessCPUSeconds
		await report.append("cpu \(corpus.name) \(GraphFuzzerPhaseAccount.formatted(wallSeconds)) \(GraphFuzzerPhaseAccount.formatted(processCPUSeconds)) \(GraphFuzzerPhaseAccount.formatted(childProcessCPUSeconds)) \(phaseAccount.reportField)")
		// Every corpus that exists, so the combine job can tell a corpus whose shards left no report from none.
		report.append("corpora \(([Self.baseCorpus] + GraphFuzzerGeneratorFeature.allCases.map { Self.corpus(for: [$0]) }).map(\.name).joined(separator: " "))")
		if configuration.coversCorpus(ofSeedCount: corpus.seedCount),
		   acceptedCount != corpus.acceptedSeedCount || acceptedSeedsSum.value != corpus.acceptedSeedsSum
		{
			reportProblem("The tool accepted \(acceptedCount) of seeds 0..<\(corpus.seedCount) of the \(corpus.name) corpus (sum \(Self.hexadecimal(acceptedSeedsSum.value))), but \(corpus.acceptedSeedCount) are pinned (sum \(Self.hexadecimal(corpus.acceptedSeedsSum))). A tool change that rejects or accepts different graphs must update the pinned values deliberately.")
		}
		if configuration.coversCorpus(ofSeedCount: corpus.seedCount) {
			if !corpus.acceptedFeatureCounts.isEmpty {
				let mismatches = GraphFuzzerFeature.allCases.compactMap { feature -> String? in
					let count = acceptedFeatureCounts[feature, default: 0]
					guard let pinnedCount = corpus.acceptedFeatureCounts[feature] else {
						return "\(feature.rawValue) \(count) (no pin)"
					}
					return count == pinnedCount ? nil : "\(feature.rawValue) \(count) (pinned \(pinnedCount))"
				}
				if !mismatches.isEmpty {
					reportProblem("The accepted graphs of the \(corpus.name) corpus show these features in other numbers than pinned: \(mismatches.joined(separator: ", ")). A generator or tool change that draws or accepts other graphs must update the per-feature pins deliberately, with the hashes and the accepted-seed pins.")
				}
			}
			if valueOracleInspectedCount != corpus.valueOracleInspectedGraphCount {
				reportProblem("The value oracle inspected \(valueOracleInspectedCount) graphs of the \(corpus.name) corpus, but \(corpus.valueOracleInspectedGraphCount) are pinned.")
			}
			if let pinnedValueOracleCounts = corpus.valueOracleCounts, valueOracleCounts != pinnedValueOracleCounts {
				reportProblem("The value oracle compared and skipped, over the \(corpus.name) corpus, \(valueOracleCounts.reportField), but \(pinnedValueOracleCounts.reportField) is pinned (`corpusValueOracleCounts`).")
			}
			if cleanSubtreeSkipOffGraphCount < Self.cleanSubtreeSkipOffGraphFloor {
				reportProblem("The oracle ran \(cleanSubtreeSkipOffGraphCount) graphs of the \(corpus.name) corpus again with no skip of a clean subtree in the validation walk, fewer than \(Self.cleanSubtreeSkipOffGraphFloor): the oracle that compares the two runs judges too few graphs to stand in for unit tests.")
			}
			if readTwinGraphCount != corpus.readTwinGraphCount {
				reportProblem("The oracle compared \(readTwinGraphCount) graphs of the \(corpus.name) corpus with their read twin, but \(corpus.readTwinGraphCount) are pinned.")
			}
			if retentionCounts != corpus.retentionCounts {
				reportProblem("The retention oracle judged, over the \(corpus.name) corpus, \(retentionCounts.reportField), but \(corpus.retentionCounts.reportField) is pinned (`retentionCounts`).")
			}
			if levelFunctionCaptureCounts != corpus.levelFunctionCaptureCounts {
				reportProblem("The level function capture oracle judged, over the \(corpus.name) corpus, \(levelFunctionCaptureCounts.reportField), but \(corpus.levelFunctionCaptureCounts.reportField) is pinned (`levelFunctionCaptureCounts`).")
			}
			let thinGatingDraws = corpus.flooredGatingDrawNames.filter { gatingDrawJudgedCounts[$0, default: 0] < Self.gatingDrawJudgedGraphFloor }
			if !thinGatingDraws.isEmpty {
				reportProblem("The oracles judged fewer than \(Self.gatingDrawJudgedGraphFloor) graphs of the \(corpus.name) corpus that draw \(thinGatingDraws.map { "\($0) (\(gatingDrawJudgedCounts[$0, default: 0]))" }.joined(separator: ", ")): such a draw gates nothing.")
			}
			for kind in corpus.builderSurfaceFlooredKinds where builderSurfaceCounts[kind, default: 0] < Self.builderSurfaceFloor {
				reportProblem("The builder surface judged \(builderSurfaceCounts[kind, default: 0]) graphs of the \(corpus.name) corpus as \(kind), below its floor of \(Self.builderSurfaceFloor).")
			}
			if omittedValueGraphCount != corpus.omittedValueGraphCount {
				reportProblem("The tool rejected \(omittedValueGraphCount) graphs of the \(corpus.name) corpus because a caller holds a value its tier omits, but \(corpus.omittedValueGraphCount) are pinned.")
			}
			let missingSpellings = corpus.spellingDrawFeatures.subtracting(acceptedSpellingDrawFeatures)
			if !missingSpellings.isEmpty {
				reportProblem("No accepted graph of the \(corpus.name) corpus draws \(missingSpellings.map(\.rawValue).sorted().joined(separator: ", ")).")
			}
			if errorCounts != corpus.errorGraphCounts {
				reportProblem("The tool rejected \(errorCounts) graphs of the \(corpus.name) corpus with each error it pins (`errorMarkers`), but \(corpus.errorGraphCounts) are pinned.")
			}
			let drawMismatches = corpus.drawFeaturesCountedWhenAccepted.union(corpus.acceptedDrawFeatureCounts.keys).sorted().compactMap { feature -> String? in
				let count = acceptedDrawFeatureCounts[feature, default: 0]
				guard let pinnedCount = corpus.acceptedDrawFeatureCounts[feature] else {
					return "\(feature.rawValue) \(count) (no pin)"
				}
				return count == pinnedCount ? nil : "\(feature.rawValue) \(count) (pinned \(pinnedCount))"
			} + corpus.publicMockDrawFeaturesCountedWhenAccepted.union(corpus.acceptedPublicMockDrawFeatureCounts.keys).sorted().compactMap { feature -> String? in
				let count = acceptedPublicMockDrawFeatureCounts[feature, default: 0]
				guard let pinnedCount = corpus.acceptedPublicMockDrawFeatureCounts[feature] else {
					return "\(feature.rawValue) \(count) (no pin)"
				}
				return count == pinnedCount ? nil : "\(feature.rawValue) \(count) (pinned \(pinnedCount))"
			}
			if !drawMismatches.isEmpty {
				reportProblem("The accepted graphs of the \(corpus.name) corpus show these draws in other numbers than pinned (`acceptedDrawFeatureCounts`): \(drawMismatches.joined(separator: ", ")).")
			}
			for (feature, minimumShare) in corpus.outputFeatureMinimumShares.sorted(by: { $0.key < $1.key }) where publicMockOutputFeatureCounts[feature, default: 0] * 100 < minimumShare * acceptedCount {
				reportProblem("The generated code of \(publicMockOutputFeatureCounts[feature, default: 0]) of the \(acceptedCount) graphs of the \(corpus.name) corpus the tool accepts shows \(feature.rawValue), fewer than the pinned \(minimumShare) percent.")
			}
		}
		report.append("completed \(graphCount) graphs, \(acceptedCount) accepted, \(knownIssueCount) known issues, \(failureCount) unknown failures")
		#expect(graphCount == configuration.iterations)
	}

	// MARK: Seeds

	/// The ordinary suite's batch: seeds 12, 25, 30, 62, 99, 212, 267, 304, 582, 691, 705, 731, 930, 2314, 2420, 2611, and 3360, whose graphs
	/// the tool accepts, with the same results under every `GraphFuzzerRenaming`, and which between them exercise every feature
	/// (seed 2314's graph has a required erased rename of an optional alias, which a type its host instantiates receives only
	/// if available; seed 25's
	/// graph has a chain of aliases through an `onlyIfAvailable` alias; seed 731's has a chain through an
	/// `onlyIfAvailable` alias of a sibling's optional form; seed 2420's has such a chain through a child scope; the graphs of
	/// seeds 582 and 705 receive a constant of a type that is not `@Instantiable` beneath the type that instantiates it;
	/// the mocked owner of such a constant in seed 2611 receives a type that receives it as a `LazilyInstantiated`, and
	/// in seed 12 lazily instantiates it as one wrapper while the type it receives receives the other kind), and
	/// seeds 14, 40, 4224, and 4516, whose graphs it rejects (seed 4224's with the dependency cycle through a chain through a
	/// child scope, because the sibling's type receives the other sibling; seed 4516's because a declaration in the tree
	/// of a dependency a mock builds beside the mocked type hides a receive beneath it; seed 40's for an unfulfillable
	/// receive, which keeps the rejected share at the quarter, rounded down, that
	/// `smokeSeeds_includeAcceptedAndRejectedGraphs_whenRunThroughTool` requires). Seeds 99, 304 and 3360 complete what
	/// the base corpus's value oracle must show in passing graphs: a label declared at two depths of a root's tree above
	/// a receiver of it (99), an `onlyIfAvailable` alias of a dependency a mock promotes (304), and a promoted wrapper
	/// whose label the tree also receives by value, as the mocked type does (3360). Seeds 18, 59, 97, 133 and 161 complete the
	/// elements a forwarded tuple spells. Seeds 30, 97, 212 and 267 show the loops through received instantiators:
	/// `Sendable` instantiators that receive one another (97), a `Sendable` loop with a member whose builder function
	/// takes cycle parameters (30), the same member with wrappers that are not `Sendable` (267), and an instantiator
	/// received inside the tree it builds, with each kind of wrapper (212). Seeds 5889 and 6388, beyond the corpus, have
	/// a builder whose own type receives it beside a receive only if available that the order leaves `nil` because the
	/// builder it receives waits on the first through a value: its builder function must still wrap itself again, and
	/// without that the generated code does not compile. Seed 94's type receives that builder only if available, and gets it
	/// (`builderReceivedInsideItsTreeBesideBuilderLeftNil`). Seeds 4, 5, 7 and 70, which the tool rejects, keep the
	/// rejected share at that quarter. Seed 98, rejected too, draws a hand-written mock's parameter whose dependency an
	/// inactive `#if` clause declares (`addingGuardedMockParameterShapes`), so the batch applies that error's two remedies.
	/// Seeds 99, 378 and 466 draw a mock passed a label that a scope its tree builds declares again above an alias of it
	/// (`addingMockPassedLabelAboveAliasCycle`): the trackers of 378 and 466 receive the alias's owner, a cycle the mock
	/// reports (378's alias, spelled with the tracker's optional form, is the graph 2.2.0 accepted and generated a mock
	/// for that did not compile), and 99's does not, so the mock binds the alias to the scope's tracker. Seed 520 has a
	/// constant that closes a cycle an instantiator defers (`constantCycleCloser`), since 466's graph, which had one, is
	/// now rejected. Seed 327 draws screens that open one another, beneath which a screen receives only if available what a
	/// mock binds at its root (`addingReceiveThroughCycleWalkedEarlier`); without the walk's fix its mock passes the screen
	/// built again `nil`, leaving its binding of the override unread, which draws a warning.
	/// Seed 4002's type-key root shares a builder function that takes an optional lazily instantiated value and reads its
	/// instance as `lazyT3?.instance`, which the query suppliers oracle reads through the optional chaining.
	/// It is small because compiling generated code is what the fuzzer costs; ci.yml fuzzes the whole corpus on
	/// every pull request. Compiling the batch is one `swiftc` invocation when nothing fails, and comparing its values
	/// one compile and one link.
	static let smokeSeeds: [UInt64] = [4, 5, 12, 18, 25, 30, 40, 53, 59, 62, 70, 86, 94, 97, 98, 99, 133, 161, 212, 267, 304, 327, 378, 466, 520, 582, 691, 705, 731, 930, 2_314, 2_420, 2_611, 3_360, 4_002, 4_224, 4_516, 5_889, 6_388]

	static let smokeAndKnownIssueFixtureHash: UInt64 = 0x51EE14FE9314DE8A

	/// The remedies the remedy oracle applies in the smoke batch's rejected graphs. `SafeDIToolGraphFuzzerRemedyTests`
	/// holds a representative of every kind.
	static let smokeRemedyKinds: [GraphFuzzerRemedyKind] = [.decorateType, .defaultMockParameter, .instantiateOnRoot, .instantiateOnRootAndReceiveOnlyIfAvailable, .moveMockIntoClause, .receiveOptionallyIfAvailable, .receiveSuggestedProperty, .relabelHidingDeclaration, .removeReceive]

	/// The `GraphFuzzerPartition` of the smoke and known-issue seeds' graphs, as `partitionHash(forSeeds:)` hashes
	/// them; `corpusPartitionHash` pins the whole corpus's. The partition draws nothing from the seed, so changing it
	/// changes neither the graphs nor the pins on them: these pins make a change to the partition deliberate. They
	/// move with the generator and, this one, with the smoke and known-issue seeds too, as the fixture hashes do.
	static let smokeAndKnownIssuePartitionHash: UInt64 = 0x898FFC7AD499FAD

	/// The corpus, seeds `0..<corpusSeedCount`, which ci.yml fuzzes on every pull request and push to main and
	/// `SAFEDI_GRAPH_FUZZER_ITERATIONS=corpus` selects. `knownIssues` lists every one that fails.
	static let corpusSeedCount = 5_000

	static let corpusFixtureHash: UInt64 = 0x57AA068FA013D518

	static let corpusPartitionHash: UInt64 = 0x8E00AD97A6B19084

	/// How many of the corpus's graphs the tool accepts, and which ones, as a `GraphFuzzerSeedSetSum`, which
	/// shards of the corpus can add up.
	static let corpusAcceptedSeedCount = 2_679
	static let corpusAcceptedSeedsSum: UInt64 = 0xDD1ED42C6F079C76

	/// How many of the corpus's graphs the tool accepts show each `GraphFuzzerFeature`, read from their source as the
	/// smoke batch reads them, which shards of the corpus add up. Unit tests leave the siblings of a shape to the
	/// corpus, so a generator change that stops drawing a feature, or a tool change that stops accepting the graphs that
	/// draw it, changes these and must update them deliberately, with the hashes and the accepted-seed pins.
	static let corpusAcceptedFeatureCounts: [GraphFuzzerFeature: Int] = [
		.constantProperty: 2_623,
		.erasedConstantProperty: 450,
		.instantiatorProperty: 2_187,
		.sendableInstantiatorProperty: 917,
		.erasedInstantiatorProperty: 1_382,
		.sendableErasedInstantiatorProperty: 493,
		.lazilyInstantiatedProperty: 777,
		.sendableLazilyInstantiatedProperty: 191,
		.erasedLazilyInstantiatedProperty: 216,
		.forwardedLazilyInstantiatedProperty: 328,
		.receivedLazilyInstantiatedInstance: 277,
		.forwardedProperty: 1_686,
		.optionalForwardedProperty: 889,
		.requiredReceive: 2_522,
		.requiredOptionalReceive: 371,
		.onlyIfAvailableReceive: 2_287,
		.requiredAlias: 1_293,
		.onlyIfAvailableAlias: 1_033,
		.aliasOfOnlyIfAvailableAlias: 78,
		.aliasOfOptionalFormOfProperty: 83,
		.onlyIfAvailableAliasBeneathLabelAMockIsPassed: 104,
		.receiveThroughCycleWalkedEarlier: 142,
		.erasedAlias: 228,
		.erasedRenameOfOptionalDependency: 37,
		.forwardedTupleOptionalElement: 82,
		.forwardedTupleNestedTypeElement: 89,
		.forwardedTupleGenericElementSpelledWithAngleBrackets: 83,
		.forwardedTupleGenericElement: 80,
		.forwardedTupleArrayElement: 97,
		.forwardedTupleDictionaryElement: 88,
		.forwardedTupleClosureElement: 89,
		.forwardedTupleSendableClosureElement: 96,
		.forwardedTupleOptionalClosureElement: 87,
		.forwardedTupleExistentialElement: 94,
		.forwardedTupleOptionalExistentialElement: 87,
		.forwardedTupleTupleElement: 98,
		.forwardedTupleTypedThrowsClosureElement: 93,
		.forwardedTupleVariadicClosureElement: 77,
		.forwardedTupleConventionClosureElement: 91,
		.forwardedTupleIsolatedAnyClosureElement: 97,
		.forwardedTupleQualifiedGlobalActorClosureElement: 75,
		.forwardedTupleNonisolatedNonsendingClosureElement: 86,
		.forwardedTupleKeywordLabel: 173,
		.forwardedPropertiesTypealiasArgument: 156,
		.forwardedTupleBuilderReceivedByMockedType: 137,
		.multipleRoots: 2_039,
		.generateMock: 2_490,
		.lazyCycle: 1_420,
		.constantCycleCloser: 157,
		.builderReceivedInsideItsTree: 179,
		.sendableBuilderReceivedInsideItsTree: 68,
		.builderReceivedInsideItsTreeBesideBuilderLeftNil: 40,
		.buildersReceivingEachOther: 154,
		.sendableBuildersReceivingEachOther: 65,
		.receivedLoopMemberWithCycleParameters: 17,
		.sendableReceivedLoopMemberWithCycleParameters: 8,
		.sameLabelWithDifferentTypes: 1_316,
		.labelSpelledAsGeneratedName: 699,
		.dependencyMockCannotBuild: 1_579,
		.dependencyMockCannotBuildReceivedBeneathItsOwner: 267,
		.dependencyMockCannotBuildReceivedLazilyBesideItsMockedOwner: 68,
		.dependencyMockCannotBuildLazilyInstantiatedReceivedAsOtherKindBesideItsMockedOwner: 9,
		.sendableAndNonSendableWrappers: 579,
		.mockedTypeOnLazyCycle: 704,
		.typesReceivingEachOtherOnlyIfAvailable: 298,
		.labelReceivedAsInstanceAndAsInstantiator: 244,
		.sameLabelReceivedAsDifferentUnbuildableWrappers: 134,
		.receivedErasedInstantiator: 895,
		.forwardedErasedInstantiator: 171,
		.defaultValuedInstantiateParameter: 644,
		.nonSendableValuesInsideSendableBuilder: 152,
		.handWrittenMockUnderMockCondition: 723,
		.customMockNameBesideGeneratedMock: 894,
		.mockOnlyExtensionOfReceivedType: 1_095,
		.instantiableStruct: 544,
		.additionalMockToGenerate: 653,
		.generateDependencyTree: 0,
	]

	/// The graphs of seeds `0..<seedCount` drawn with `features`, and what is pinned about them. Each generator
	/// feature has a corpus of its own, so that turning a feature on changes no graph of the corpus drawn without it.
	struct Corpus {
		/// The name the long run's report lines carry, which ci.yml's combine job groups shards by.
		let name: String
		let features: Set<GraphFuzzerGeneratorFeature>
		let seedCount: Int
		let fixtureHash: UInt64
		let acceptedSeedCount: Int
		let acceptedSeedsSum: UInt64
		/// How many of the graphs the tool accepts show each `GraphFuzzerFeature`, read from their source as the smoke
		/// batch reads them, for a corpus that pins them; empty for a corpus that does not.
		var acceptedFeatureCounts = [GraphFuzzerFeature: Int]()
		let knownIssues: [GraphFuzzerKnownIssue]
		/// The name of the list `knownIssues` is read from, which a stale entry's message names.
		let knownIssuesName: String
		/// What to edit when a seed of `knownIssues` no longer fails in this corpus, by the shape it was listed under
		/// and the list that put the seed there.
		let staleSeedRemedy: @Sendable (GraphFuzzerKnownIssue, UInt64) -> String
		/// How many graphs the value oracle compares with their inline build: those the tool accepts with a seam and
		/// without it.
		let valueOracleInspectedGraphCount: Int
		/// The spellings each of which some graph the tool accepts must draw.
		let spellingDrawFeatures: Set<GraphFuzzerSeamDrawFeature>
		/// How many graphs the tool rejects with an error that a caller in another module holds a value the seam tier it
		/// calls omits, which the omitted-value oracle judges against the inline build.
		let omittedValueGraphCount: Int
		/// The least share, in percent of the graphs the tool accepts, of the graphs whose generated code shows each public
		/// mock output feature, for the features that have one.
		var outputFeatureMinimumShares = [GraphFuzzerPublicMockOutputFeature: Int]()
		/// Text that each of the errors whose rejections the corpus pins contains: a public mock's own errors
		/// (`GraphFuzzerOracle.publicMockOnlyErrorMarkers`), or the errors of a cycle's label in a seam's tree.
		var errorMarkers = [String]()
		/// How many graphs the tool rejects with each error of `errorMarkers`, in its order.
		var errorGraphCounts = [Int]()
		/// The draws whose graphs the tool accepts the corpus counts, so that a draw the tool always rejects fails a pin.
		var drawFeaturesCountedWhenAccepted = Set<GraphFuzzerSeamDrawFeature>()
		/// How many of the graphs the tool accepts show each draw of `drawFeaturesCountedWhenAccepted`, counted whether or
		/// not the graph fails, as the accepted-seed pins are.
		var acceptedDrawFeatureCounts = [GraphFuzzerSeamDrawFeature: Int]()
		/// The public mock draws whose graphs the tool accepts the corpus counts, as `drawFeaturesCountedWhenAccepted` does
		/// for the seam draws.
		var publicMockDrawFeaturesCountedWhenAccepted = Set<GraphFuzzerPublicMockDrawFeature>()
		/// How many of the graphs the tool accepts show each draw of `publicMockDrawFeaturesCountedWhenAccepted`.
		var acceptedPublicMockDrawFeatureCounts = [GraphFuzzerPublicMockDrawFeature: Int]()
		/// What the base corpus's value oracle compares and skips over the whole corpus, or `nil` for a corpus that has
		/// no such oracle.
		var valueOracleCounts: GraphFuzzerValueOracleCounts?
		/// How many graphs name a type no declaration SafeDI reads declares, which the oracle runs again as their read
		/// twin (`GraphFuzzerFixture.readTwin`) and compares with the graph: none for a corpus that draws no such type.
		var readTwinGraphCount = 0
		/// What the retention oracle judges over the whole corpus (`retention` in the report), pinned: graphs with a hole it
		/// judged, those of them that draw its own shape, those whose hand-written builder's probe it judged, and the
		/// experiments only one path ran.
		var retentionCounts = GraphFuzzerRetentionCounts()
		/// What the level function capture check judges over the whole corpus (`level-captures` in the report), pinned: the
		/// graphs with a level function, those of them with a member closure that names its parameter, those member
		/// closures, the conversion functions and the fill functions.
		var levelFunctionCaptureCounts = GraphFuzzerLevelFunctionCaptureCounts()
		/// The gating draws of the seam corpus (`isForwardedLabelAcrossSeamCallShape`, `isRetentionShape`), whose judged
		/// graphs must reach `gatingDrawJudgedGraphFloor`.
		var gatingSeamDrawFeatures = Set<GraphFuzzerSeamDrawFeature>()
		/// The gating draws of the public mock corpus (`isCountedWhenAccepted`), as `gatingSeamDrawFeatures`.
		var gatingPublicMockDrawFeatures = Set<GraphFuzzerPublicMockDrawFeature>()

		/// The names of the corpus's gating draws and the shapes they roll, sorted.
		var gatingDrawNames: [String] {
			gatingSeamDrawFeatures.sorted().map(\.rawValue) + gatingPublicMockDrawFeatures.sorted().map(\.rawValue)
		}

		/// The names of the corpus's gating draws, each on a stream of its own, whose judged graphs must reach
		/// `gatingDrawJudgedGraphFloor`: those of `gatingDrawNames` that no other begins, since a shape a draw rolls is
		/// named after the draw, and every shape of a place held in an instantiator, its rolls included
		/// (`GraphFuzzerSeamDrawFeature.isForwardingPlaceShape`), each of which an accepted count alone would not show judged.
		var flooredGatingDrawNames: [String] {
			let names = gatingDrawNames
			return names.filter { name in
				GraphFuzzerSeamDrawFeature(rawValue: name)?.isForwardingPlaceShape == true || !names.contains { $0 != name && name.hasPrefix($0) }
			}
		}

		/// The gating draws of `result`'s graph that the oracles after acceptance judged: the graph is accepted, a known
		/// issue listing it masks no later failure (`GraphFuzzerKnownIssue.masksNoLaterFailure`), and the retention oracle
		/// judged it, for a retention draw, or the value comparator compared it, for any other.
		func gatingDrawsJudged(by result: GraphFuzzerResult, knownIssue: GraphFuzzerKnownIssue?) -> [String] {
			guard result.isAccepted, knownIssue?.masksNoLaterFailure ?? true else { return [] }
			let seamDraws = gatingSeamDrawFeatures.isEmpty ? [] : GraphFuzzerFeature.seamDrawFeatures(of: result.fixture).intersection(gatingSeamDrawFeatures).filter { feature in
				feature.isRetentionShape ? result.isJudgedForRetention : result.isComparedByValueOracle
			}
			let publicMockDraws = gatingPublicMockDrawFeatures.isEmpty ? [] : GraphFuzzerPublicMockDraw.drawFeatures(of: result.fixture).intersection(gatingPublicMockDrawFeatures).filter { feature in
				feature.isRetentionShape ? result.isJudgedForRetention : result.isComparedByValueOracle
			}
			return seamDraws.map(\.rawValue) + publicMockDraws.map(\.rawValue)
		}

		/// The builder surface's kinds (`GraphFuzzerBuilderSurface.floorKinds`) whose judged graphs must reach
		/// `builderSurfaceFloor` over the corpus, which ci.yml's combine job adds up and checks: every kind the corpus draws,
		/// none for a corpus without holes. A kind the corpus never draws is left out: the seam corpus draws no edit of a
		/// place's wrapper, no second call of a public mock and no new builder of an existing filling type but its second
		/// erasure, and the public mock corpus no inner seam and no second erasure.
		var builderSurfaceFlooredKinds = [String]()
		/// The seeds whose value graphs' probes traverse more wrappers than `DifferentialValueLimits()` allows, each listed
		/// by name so that only its graphs get `DifferentialValueLimits.isolatedFuzzerGraph`'s budget.
		var seedsTraversingPastTheBatchBudget = Set<UInt64>()

		/// The seeds whose value graphs the value oracle compares each on its own, with
		/// `DifferentialValueLimits.isolatedFuzzerGraph`: those whose value-oracle fixture is known not to compile, and
		/// `seedsTraversingPastTheBatchBudget`.
		var isolatedValueGraphSeeds: Set<UInt64> {
			SafeDIToolGraphFuzzerTests.isolatedValueOracleSeeds(of: knownIssues).union(seedsTraversingPastTheBatchBudget)
		}
	}

	static let baseCorpus = Corpus(
		name: "base",
		features: [],
		seedCount: corpusSeedCount,
		fixtureHash: corpusFixtureHash,
		acceptedSeedCount: corpusAcceptedSeedCount,
		acceptedSeedsSum: corpusAcceptedSeedsSum,
		acceptedFeatureCounts: corpusAcceptedFeatureCounts,
		knownIssues: knownIssues,
		knownIssuesName: "knownIssues",
		staleSeedRemedy: { _, _ in "remove it from `knownIssuesBesideReportedIssueShapes`, or from `repeatedAncestorLazyCycleSeeds` or `receiveThroughCycleWalkedEarlierLazyCycleSeeds` for a reported issue’s shape, and from `seamCorpusSeedsOfOtherShapes` when it is listed there" },
		valueOracleInspectedGraphCount: corpusValueOracleInspectedGraphCount,
		spellingDrawFeatures: [],
		omittedValueGraphCount: 0,
		errorMarkers: [GraphFuzzerOracle.guardedMockParameterErrorMarker],
		errorGraphCounts: corpusErrorGraphCounts,
		valueOracleCounts: corpusValueOracleCounts,
		seedsTraversingPastTheBatchBudget: corpusSeedsTraversingPastTheBatchBudget,
	)

	/// How many of the corpus's graphs the tool rejects with the error of a hand-written mock's parameter whose
	/// dependency an inactive `#if` clause declares (`GraphFuzzerOracle.guardedMockParameterErrorMarker`): every graph
	/// that draws the shape (`addingGuardedMockParameterShapes`).
	static let corpusErrorGraphCounts = [66]

	/// How many of the corpus's graphs the base corpus's value oracle inspects: every graph the tool accepts.
	static let corpusValueOracleInspectedGraphCount = corpusAcceptedSeedCount

	/// What the base corpus's value oracle compares and skips over the whole corpus (`GraphFuzzerValueOracleCounts`).
	static let corpusValueOracleCounts = GraphFuzzerValueOracleCounts(
		rootPairCount: 6_109,
		rootPairsSum: GraphFuzzerSeedSetSum(value: 0x1BBA8A8003FE33F1),
		mirroredPairCount: 5_290,
		mirroredPairsSum: GraphFuzzerSeedSetSum(value: 0x10EC6065CFF8BC10),
		skipCounts: [
			.requiredParameter: 1_666,
			.twoFormsOfOneLabel: 182,
			.requiredOptionalReceiveOfNonOptionalDeclaration: 49,
			.requiredReceiveOfUncreatedAlias: 40,
		],
		shapeCounts: [
			.rootTreePropertyReceivedByTwoOrMoreTypes: 1_784,
			.rootTreeLabelDeclaredAtTwoDepthsAboveReceiver: 181,
			.promotedDependencyReceivedByTwoOrMoreTypes: 565,
			.onlyIfAvailableAliasOfPromotedDependency: 122,
			.requiredAliasOfPromotedDependency: 402,
			.promotedWrapperReceivedInAnotherForm: 66,
			.instanceOfPromotedWrapperPassedToMockedType: 4,
			.onlyIfAvailableReceiveInMockedTypesTreeLeftUnbuilt: 723,
		],
		drawnMocksMatchingOnlyAfterNormalizationCount: 945,
		mirroredPairsTakingSamplesCount: 972,
		forwardedPropertiesSampleCount: 2_727,
		overridePairCount: 8_022,
		overridePairsSum: GraphFuzzerSeedSetSum(value: 0xFD0772C0C776EA2B),
		overrideFieldKindCounts: [
			.builder: 4_921,
			.configuration: 3_101,
		],
		overrideCandidateKindCounts: [
			.constant: 6_185,
			.lazilyInstantiated: 530,
			.erased: 386,
			.sendableInstantiator: 921,
		],
		pinnedPlacePairCount: 105,
		nestedCyclePairCount: 92,
	)

	/// The seeds of `knownIssues` whose value-oracle fixture is known not to compile.
	static func isolatedValueOracleSeeds(of knownIssues: [GraphFuzzerKnownIssue]) -> Set<UInt64> {
		Set(knownIssues.filter { knownIssue in
			knownIssue.signatures.contains { signature in
				if case .valueOracleFixtureDoesNotCompile = signature {
					true
				} else {
					false
				}
			}
		}.flatMap(\.seeds))
	}

	/// The corpus drawn with the `generateDependencyTree` feature: seeds `0..<seamCorpusSeedCount`, each graph with
	/// one type a root reaches declared as a seam. Smaller than the base corpus while the feature settles.
	static let seamCorpus = Corpus(
		name: GraphFuzzerGeneratorFeature.generateDependencyTree.rawValue,
		features: [.generateDependencyTree],
		seedCount: seamCorpusSeedCount,
		fixtureHash: seamCorpusFixtureHash,
		acceptedSeedCount: seamCorpusAcceptedSeedCount,
		acceptedSeedsSum: seamCorpusAcceptedSeedsSum,
		knownIssues: seamKnownIssues,
		knownIssuesName: "seamKnownIssues",
		// A label-sorted seed leaves its own list; an inherited seed leaves `knownIssues` when the base corpus reports
		// it stale too, and is otherwise one the seam's draw changed.
		staleSeedRemedy: { knownIssue, seed in
			if knownIssue.reason == labelSortedPassThroughReason {
				"remove it from `labelSortedPassThroughSeeds`"
			} else if knownIssue.reason == labelSortedPassThroughAndMockParametersReason {
				"remove it from `labelSortedPassThroughSeedsWhoseMockParametersAlsoChange`"
			} else if seamCorpusSeedsAddedToInheritedShapes[knownIssue.reason]?.contains(seed) == true {
				"remove it from `seamCorpusSeedsAddedToInheritedShapes`"
			} else {
				"remove it from `knownIssuesBesideReportedIssueShapes` if the base corpus reports it stale too, else add it to `seamCorpusSeedsOfOtherShapes`"
			}
		},
		valueOracleInspectedGraphCount: seamCorpusValueOracleInspectedGraphCount,
		spellingDrawFeatures: Set(GraphFuzzerSpelling.allCases.map(\.drawFeature)),
		omittedValueGraphCount: seamCorpusOmittedValueGraphCount,
		errorMarkers: seamCorpusErrorMarkers,
		errorGraphCounts: seamCorpusErrorGraphCounts,
		drawFeaturesCountedWhenAccepted: Set(GraphFuzzerSeamDrawFeature.allCases.filter { $0.isAliasSpellingRollShape || $0.isCycleParameterShape || $0.isForwardedLabelAcrossSeamCallShape || $0.isRetentionShape || $0.isErasurePlaceShape || $0.isForwardingPlaceShape || $0.isPassedUpPlaceReadingPassingSeamsValueShape || $0.isFixedSeamCallDefectShape || $0.isOptionalPlaceShape || $0.isReadThroughViewShape || $0.isScreenPlaceShape || $0.isLazyRouteShape }),
		acceptedDrawFeatureCounts: seamCorpusAcceptedDrawFeatureCounts,
		readTwinGraphCount: seamCorpusReadTwinGraphCount,
		retentionCounts: seamCorpusRetentionCounts,
		levelFunctionCaptureCounts: seamCorpusLevelFunctionCaptureCounts,
		gatingSeamDrawFeatures: Set(GraphFuzzerSeamDrawFeature.allCases.filter { $0.isForwardedLabelAcrossSeamCallShape || $0.isRetentionShape || $0.isForwardingPlaceShape || $0.isPassedUpPlaceReadingPassingSeamsValueShape || $0.isFixedSeamCallDefectShape || $0.isOptionalPlaceShape }),
		builderSurfaceFlooredKinds: [
			"base-plain",
			"base-lazy",
			"base-forwarding",
			"base-sendable",
			"secondPlaceInAnotherType",
			"secondPlaceInInnerSeamOfAnotherModule",
			"holderMovedToInnerSeamOfAnotherModule",
			"placeBehindLazilyInstantiated",
			"placeOfNewBuilderInInnerSeamOfAnotherModule",
			"placeOfHoleTypeNamedAfterSendableLabel",
			"placeForwardingOtherValues",
			"placeForwardingOtherValuesRemedied",
			"placeForwardingOtherValuesInInnerSeamOfAnotherModule",
			"placeForwardingOtherValuesInInnerSeamOfAnotherModuleRemedied",
			"lazilyInstantiatedPlaceMovedBack",
			"secondErasureOfFillingType",
			"remedyKeepsDrawnBuilders",
			"instantiatorPlaceMovedToPlainPlace",
			"instantiatorChangedToErasedInstantiator",
			"sendableInstantiatorPlaceMovedToPlainPlace",
			"sendableInstantiatorChangedToSendableErasedInstantiator",
			"plainPlaceMovedToInstantiator",
			"erasedInstantiatorChangedToInstantiator",
			"plainPlaceMovedToSendableInstantiator",
			"sendableErasedInstantiatorChangedToSendableInstantiator",
			GraphFuzzerBuilderSurface.wrapperBuilderCallKind,
		],
		seedsTraversingPastTheBatchBudget: seamCorpusSeedsTraversingPastTheBatchBudget,
	)

	/// The fewest graphs of each gating draw (`Corpus.flooredGatingDrawNames`) that the oracles after acceptance judge
	/// (`Corpus.gatingDrawsJudged(by:knownIssue:)`), and the fewest graphs the retention oracle judges of each count
	/// `retentionCounts` pins but the unpaired experiments, that a corpus must hold for the check to gate: ten graphs per
	/// draw.
	static let gatingDrawJudgedGraphFloor = 10

	/// The fewest graphs of a corpus the oracle must run again with no skip of a clean subtree in the validation walk
	/// (`GraphFuzzerToolRuns.cleanSubtreeSkipFailure`) for that comparison to stand in for unit tests.
	static let cleanSubtreeSkipOffGraphFloor = 10

	/// What the retention oracle judges over the seam corpus (`Corpus.retentionCounts`). Pins: derived on CI.
	static let seamCorpusRetentionCounts = GraphFuzzerRetentionCounts(judged: 112, judgedDrawingRetentionShape: 108, judgedThroughHandWrittenBuilder: 69, unpairedExperiments: 0, judgedHoldingForwardingWrapper: ["ErasedInstantiator": 77, "SendableErasedInstantiator": 22, "Instantiator": 73, "SendableInstantiator": 21])

	/// What the level function capture check judges over the seam corpus (`Corpus.levelFunctionCaptureCounts`). Pins:
	/// derived on CI.
	static let seamCorpusLevelFunctionCaptureCounts = GraphFuzzerLevelFunctionCaptureCounts(judged: 246, judgedWithNamed: 211, named: 2_090, conversions: 0, fills: 422)

	/// What the level function capture check judges over the public mock corpus (`Corpus.levelFunctionCaptureCounts`).
	/// Pins: derived on CI.
	static let publicMockCorpusLevelFunctionCaptureCounts = GraphFuzzerLevelFunctionCaptureCounts(judged: 640, judgedWithNamed: 399, named: 1_075, conversions: 0, fills: 504)

	/// What the retention oracle judges over the public mock corpus (`Corpus.retentionCounts`). Pins: derived on CI.
	static let publicMockCorpusRetentionCounts = GraphFuzzerRetentionCounts(judged: 693, judgedDrawingRetentionShape: 131, judgedThroughHandWrittenBuilder: 92, unpairedExperiments: 0)

	/// The base corpus's seeds whose probes traverse more wrappers than a batch allows, compared on their own with
	/// `DifferentialValueLimits.isolatedFuzzerGraph`: seeds 512, 1136 and 1627, whose override probe records what one more
	/// call of `cycleWalkScreen7Builder` builds, which the describer unrolls through the eight screens of the cycle walk
	/// again from the record's own path.
	static let corpusSeedsTraversingPastTheBatchBudget: Set<UInt64> = [512, 1_136, 1_627]

	static let seamCorpusSeedCount = 2_000
	static let seamCorpusFixtureHash: UInt64 = 0x1313E68FFFFF5176
	static let seamCorpusAcceptedSeedCount = 609
	static let seamCorpusAcceptedSeedsSum: UInt64 = 0x38D97AC726E69107
	/// How many of the seam corpus's graphs the tool accepts with their seams and without them, which the value
	/// oracle compares.
	static let seamCorpusValueOracleInspectedGraphCount = 477
	/// How many of the seam corpus's graphs the tool rejects because a caller holds a value the tier it calls omits.
	static let seamCorpusOmittedValueGraphCount = 0
	/// The errors of a cycle's label in a seam's tree whose rejections the seam corpus pins, which
	/// `addingCycleParameterShapes` draws by design: a fill that reads a label a cycle declares again with no cycle
	/// parameter to carry it (`declarationBoundOnCycleReentry`), forms of a label one cycle parameter cannot carry
	/// (`unpassableCycleLabel`), a fill that requires what its scope carries only optionally (`fieldHeldOnlyOptionally`),
	/// and a plain wrapper captured inside a `Sendable` one (`nonSendableWrapperCaptures`). The third marker is the part of
	/// `fieldHeldOnlyOptionally`'s message both of its causes share: the seam's tree receiving the label only if available,
	/// and a builder function a lazy cycle closes on taking it as a parameter. The last two are a fill that builds its seam
	/// again and reads a value only the place it fills carries (`fieldOfReenteringPlace`), which `addingHoleShapes` draws in
	/// a screen: a read only if available, then a required read, counted apart.
	static let seamCorpusErrorMarkers = [
		"the same values at every level of that cycle",
		"which one value cannot carry together",
		"only as `",
		"cannot be received inside a `@Sendable` function in chain",
		"would get `nil` or another value.",
		"would get another value.",
	]
	/// How many of the seam corpus's graphs the tool rejects with each error of `seamCorpusErrorMarkers`, in its order.
	static let seamCorpusErrorGraphCounts = [17, 15, 7, 53, 35, 8]
	/// How many of the seam corpus's graphs the tool accepts show each of `addingCycleParameterShapes`' draws, so that a
	/// draw the tool rejects every time, or a change that rejects more of them, names the shape. Four draws the tool rejects
	/// by design are pinned at none: an instantiator declaration between beside by-value ones, which hides the reads beneath
	/// it, a fill's read of a label no cycle parameter carries (`declarationBoundOnCycleReentry`, among
	/// `seamCorpusErrorMarkers`), and a screen's fill that builds its seam again and reads, only if available or as
	/// required, a value only the place it fills carries (`fieldOfReenteringPlace`, the last two of `seamCorpusErrorMarkers`).
	static let seamCorpusAcceptedDrawFeatureCounts: [GraphFuzzerSeamDrawFeature: Int] = [
		.cycleParameterDeclaredAfterCloser: 26,
		.cycleParameterDeclaredAsAlias: 19,
		.cycleParameterDeclaredAsHidingInstantiator: 1,
		.cycleParameterDeclaredAsInstantiators: 30,
		.cycleParameterDeclaredBySeam: 93,
		.cycleParameterDeclaredLazily: 36,
		.cycleParameterDeferredFromCaller: 45,
		.cycleParameterDeferredNote: 45,
		.cycleParameterFillReadsLabel: 83,
		.cycleParameterFillReadsLabelNoParameterCarries: 0,
		.cycleParameterFillReadsNote: 51,
		.cycleParameterHoleAtOrBeneathDeclaration: 52,
		.cycleParameterHoleBetween: 57,
		.cycleParameterHoleOnClosedOnType: 52,
		.cycleParameterHoleOnReader: 14,
		.cycleParameterHoleOnSeam: 18,
		.cycleParameterMixedWrapperKinds: 6,
		.cycleParameterMocked: 32,
		.cycleParameterNestedCycle: 20,
		.cycleParameterNoteDeclaredAgain: 15,
		.cycleParameterNoteReceivedAfterLabel: 27,
		.cycleParameterOpenedByInstantiator: 63,
		.cycleParameterOpenedByValue: 20,
		.cycleParameterOpenedLazily: 58,
		.cycleParameterReaderBetween: 26,
		.cycleParameterReaderReceivesInstantiator: 24,
		.cycleParameterReaderReceivesOnlyIfAvailable: 32,
		.cycleParameterReaderReceivesWrapperOnlyIfAvailable: 3,
		.cycleParameterReaderRequiresValue: 48,
		.cycleParameterReaderRequiresWrapper: 5,
		.cycleParameterSeam: 141,
		.cycleParameterSendableWrappers: 34,
		.cycleParameterSideReceivesInstantiator: 9,
		.cycleParameterSideReceivesValue: 45,
		.cycleParameterSideReceivesWrapper: 5,
		.cycleParameterTwoLevelsDeep: 58,
		.cycleParameterUndeclaredAbove: 3,
		.cycleParameterWithoutReader: 15,
		.forwardedLabelAcrossSeamCall: 169,
		.forwardedLabelAcrossSeamCallCallerInsideSeam: 57,
		.forwardedLabelAcrossSeamCallFillReadsLabel: 76,
		.forwardedLabelAcrossSeamCallInnerOptional: 21,
		.forwardedLabelAcrossSeamCallOtherTypes: 48,
		.forwardedLabelAcrossSeamCallOuterDefers: 29,
		.forwardedLabelAcrossSeamCallPlaceBeneath: 50,
		.forwardedLabelAcrossSeamCallSameClassType: 38,
		.forwardedLabelAcrossSeamCallSameValueType: 33,
		.forwardedLabelAcrossSeamCallSendable: 46,
		.retentionLoopOfBuilders: 130,
		.retentionLoopOfBuildersBeneathSeam: 52,
		.retentionLoopOfBuildersFourMembers: 45,
		.retentionLoopOfBuildersSendable: 30,
		.retentionSeamValueBeforeBuilder: 185,
		.retentionSeamValueBeforeBuilderFillReadsValue: 33,
		.retentionSeamValueBeforeBuilderInnerSeam: 61,
		.retentionSeamValueBeforeBuilderLeafThroughInstantiator: 98,
		.retentionSeamValueBeforeBuilderSendable: 47,
		.holeErasureBeneathSeamInSendableFamily: 44,
		.holeErasureInsidePlainFill: 48,
		.holeErasureInsideSendableFill: 31,
		.holeForwardingPlace: 70,
		.holeForwardingPlaceLabeledPair: 59,
		.holeForwardingPlacePassedUp: 50,
		.holeForwardingPlaceSecondPlace: 63,
		.holeForwardingPlaceSecondPlaceSpelledOtherwise: 60,
		.holeInstantiatorPlace: 176,
		.holeInstantiatorPlaceBesideErased: 146,
		.holeInstantiatorPlaceBesidePlain: 152,
		.holeInstantiatorPlaceBesidePlainAcrossFamilies: 41,
		.holeLazyRoute: 97,
		.holeLazyRouteBeneathInstantiator: 33,
		.holeLazyRouteNestedSeamFillRequiresValue: 52,
		.holeLazyRouteReadOnlyIfAvailable: 51,
		.holeLazyRouteSecondFormPlace: 46,
		.holeLazyRouteSecondFormBeneathLevel: 27,
		.holeLazyRouteSendableWrapper: 20,
		.holeNothingForwardedPlace: 174,
		.holeNothingForwardedPlaceBesideInstantiator: 75,
		.holeNothingForwardedPlaceBesidePlain: 71,
		.holeNothingForwardedPlacePassedUp: 112,
		.retentionSeamValueBeforeBuilderForwardingPlace: 82,
		.carriedLevel: 124,
		.carriedLevelFillReadsForwarded: 41,
		.carriedLevelTwoRoutes: 83,
		.fillCallReadsOwnLevel: 165,
		.fillCallReadsOwnLevelInsideSendableFill: 44,
		.fillCallReadsOwnLevelSendableCall: 53,
		.fillCallReadsOwnLevelSendableRoute: 23,
		.fillCallReadsOwnLevelSharedLabel: 52,
		.holePassedUpPlaceReadsLazyValue: 37,
		.holePassedUpPlaceReadsOptionalField: 40,
		.holePassedUpPlaceReadsPassingSeamsValue: 39,
		.holePassedUpPlaceReadsValueTwoSeamsUp: 37,
		.passingUpCopies: 113,
		.passingUpCopiesFillReadsLabel: 50,
		.passingUpCopiesSeamsBindLabel: 27,
		.reenteredFill: 148,
		.reenteredFillCallBeneathFilledType: 41,
		.reenteredFillCallThroughSeamPassingPlaceUp: 61,
		.holeScreenPlace: 86,
		.holeScreenValueBuiltBySeam: 27,
		.holeScreenValueLostOnReentry: 0,
		.holeScreenValueReadWithoutReentry: 40,
		.holeScreenValueReceivedBySeam: 19,
		.holeScreenValueRequiredLostOnReentry: 0,
		.reenteredFillCallThroughSeamPassingPlaceUpByTypeOfAnotherModule: 13,
		.nestedCycleHole: 57,
		.nestedCycleHoleLabelDeclaredAfterCloser: 30,
		.nestedCycleHoleLabelReceivedBySeamPassingPlaceUp: 21,
		.nestedCycleHoleLabelReceivedByTypeBuiltAgain: 36,
		.nestedCycleHolePlaceOnScreen: 28,
		.nestedCycleHolePlacePassedUp: 21,
		.nestedCycleHoleThirdCycle: 17,
		.wrapperMix: 88,
		.wrapperMixValueAndSendableWrapper: 78,
		.wrapperMixWrapperReadInSendableFunction: 42,
		.placesOfOneCase: 133,
		.placesOfOneCaseHandFillsOtherValues: 111,
		.placesOfOneCaseFillReadsOnlyIfAvailable: 36,
		.reenteredFillCallThroughSeamPassingPlaceUpInSendableFill: 13,
		.reenteredFillReadsPlaceFieldDeclaredInFill: 40,
		.reenteredFillReadsPlaceFieldRemedied: 74,
		.reenteredFillEnclosingFillHoldsPlace: 57,
		.reenteredFillReadsValueAbove: 65,
		.reenteredFillReadsValueOfOneRouteRemedied: 67,
		.reenteredFillReentersEnclosingFill: 49,
		.carriedLevelFillReadsDeferredValue: 75,
		.carriedLevelFillReadsDeferredValueRootDeclares: 36,
		.carriedLevelFillReadsDeferredValueOnTopsRouteToo: 18,
		.carriedLevelFillReadsDeferredValueFromTwoSeams: 42,
		.carriedLevelFillReadsSendableWrapper: 14,
		.carriedLevelFillReadsSendableWrapperAlone: 14,
		.reenteredFillSendableCall: 13,
		.seamDependencyChainReadThroughView: 11,
		.seamDependencyReadThroughView: 77,
		.spelledAliasNamingProtocolWithoutAny: 23,
		.spelledAliasOnlyReceiveOfMockedChild: 13,
		.carrierDrawCoincidingLabel: 75,
		.carrierDrawCoincidingLabelOnSeamToo: 28,
		.carrierDrawKeySplitFamilies: 35,
		.carrierDrawLoopLevelReadByFill: 84,
		.carrierDrawLoopLevelReadByFillThreeMembers: 38,
		.optionalPlace: 149,
		.optionalPlaceFilled: 93,
		.optionalPlaceUnfilled: 56,
		.optionalPlaceOnSeam: 47,
		.optionalPlaceThroughInstantiator: 39,
		.optionalPlacePassedUp: 53,
		.optionalPlaceBesideRequiredPlace: 35,
		.optionalPlaceReceivedRequired: 59,
		.optionalPlaceSeamMocked: 14,
		.carrierDrawMixedInnerSeamFillAndPassUp: 60,
		.carrierDrawMixedInnerSeamFillAndPassUpThroughInstantiator: 29,
		.carrierDrawUnequalSiblings: 68,
		.carrierDrawUnequalSiblingsBeneathChild: 45,
		.carrierDrawWrappedBesidePlain: 81,
		.carrierDrawWrappedBesidePlainErased: 45,
		.carrierDrawWrappedBesidePlainLazy: 36,
		.nestedFillHole: 123,
		.nestedFillHoleBeneathInstantiator: 49,
		.nestedFillHoleInnerPlaceBeneathInstantiator: 44,
		.seamRing: 59,
		.seamRingOfSendableInstantiators: 15,
		.seamRingWithoutRootValues: 27,
		.seamRingRooted: 29,
	]
	/// How many of the seam corpus's graphs name a type no declaration SafeDI reads declares, which the oracle compares
	/// with their read twin.
	static let seamCorpusReadTwinGraphCount = 288
	/// The seam corpus's seeds whose probes traverse more wrappers than a batch allows, compared on their own with
	/// `DifferentialValueLimits.isolatedFuzzerGraph`: seed 391, whose `S391_Root0()` traverses 130,726 through a chain of
	/// hole draws that re-enter one another (`HoleInner2`, `HoleDeep`, `HoleLoop`, `HoleSeam`), on its builds with the
	/// hole, visible and inline alike; and seed 883, whose `S883_Root0()` spends a batch's traversals through `HoleBoth`,
	/// `HolePing` and `HoleInner2` re-entering `HoleSeam`, with types shared under its hole, on both of its builds alike; and
	/// seed 945, whose `S945_HoleOtherRoot()` spends a batch's traversals through `HoleOuter`, `HoleRelay` and `HoleImpl`
	/// re-entering `HoleSeam`, whose place inside a plain fill `HoleNestScreen` holds, on both of its builds alike; and seed
	/// 1311, whose `S1311_Root0()` spends even a graph's own traversals through `HoleRelay`, `HoleLoop`, `HolePing` and
	/// `HoleDeep` re-entering `HoleSeam`, on both of its builds alike, as `seamKnownIssues` lists; the smoke batch's
	/// seeds 277 and 1890, below the corpus's size (`seamSmokeSeedsTraversingPastTheBatchBudget`); and seeds 4429 and
	/// 5059, past the corpus's size, which a run of the seam draw beyond the corpus spent a batch's traversals on through
	/// holes that re-enter `HoleSeam`, as seed 391 does, and which a graph's own traversals describe; and seeds 5043 and
	/// 5609, past the corpus's size too, which spend even a graph's own traversals through holes that re-enter `HoleSeam`,
	/// as seed 1311 does, in the comparator's probe alone: `generate` takes no longer on them than on another graph.
	static let seamCorpusSeedsTraversingPastTheBatchBudget: Set<UInt64> = [277, 391, 883, 945, 1_311, 1_890, 4_429, 5_043, 5_059, 5_609]

	/// The seam smoke batch's seeds whose probes traverse more wrappers than a batch allows, compared on their own as
	/// `seamCorpusSeedsTraversingPastTheBatchBudget`'s are: seed 1890, whose `S1890_HoleOtherRoot()` spends a batch's
	/// traversals through `HoleOuterS`, `HoleRelay` and `HoleDeep` re-entering `HoleSeam`; and seed 277, whose hole re-enters
	/// `HoleSeam` through a seam passing its place up, plain and `@Sendable`, beside the instantiator place.
	static let seamSmokeSeedsTraversingPastTheBatchBudget: Set<UInt64> = [277, 1_890]

	/// The ordinary suite's batch of the seam corpus: graphs the tool accepts whose generated code, between them, shows
	/// every `GraphFuzzerSeamOutputFeature` – both kinds of pass-through, a call reading `.instance`, an `@escaping`
	/// closure parameter, an `@escaping @Sendable` one, an optional closure, the comment naming a type SafeDI reads no
	/// declaration of (seed 16), and a seam's own mock taking a builder that takes nothing (seed 934) – graphs split across
	/// modules, with a caller in another package, a caller in the seam's package without a package and a seam's module
	/// without one (seeds 31, 84, 180 and 215 between them), some
	/// also accepted inline, so the batch compiles every module, compares a split graph's values and compares one across the
	/// two integrations;
	/// graphs with a hole whose code, between them, shows every `GraphFuzzerHoleOutputFeature` – a passed-up builder whose
	/// fill re-enters the inner seam, a `@Sendable` builder whose fill re-enters its seam, a fill passed to a seam that passes
	/// its site up, also `@Sendable` (seeds 277 and 1890 between them) – and that draw, between them, every roll of
	/// `addingHoleShapes` with an accepted variant (with seeds 68, 227, 605 and 1890), the nested builders' draws among them
	/// – a second hole type (seed 215), a wrapper of the hole beside its by-value place (seeds 78 and 605), a cycle of two
	/// seams with a `@Sendable` edge (seed 93), and an inner seam reached by a plain and a `@Sendable` route, passed up with
	/// both enums, an inner `@Sendable` place on a `@Sendable` route and a place inside a `@Sendable` fill (seed 273), a place
	/// inside a plain fill on two routes of the inner seam's enum, two types deep, read through the inner seam's levels
	/// (seed 594, and seed 151 on two routes), on two calls (seed 1010) and read by its fulfiller (seed 1450), and a hole
	/// under a later member of a loop of received instantiators, declared by the seam (seed 347) or beneath it (seed 215),
	/// under every member through a shared leaf (seed 164), read from the member's level (seed 309), of three members (seed
	/// 1020) and with a member also built by value (seeds 309 and 347) – of which the name-stability oracle compares one
	/// without its second place; a split graph that
	/// declares a type in a flag's clause in the seam's module (`recordedInFlagClause`), which the two integrations agree
	/// on once the plugin flow's assertions about that module's block are excused (seed 84); and a graph it rejects, which
	/// `seamSmokeSeeds_exerciseSeamFeature_inGraphsTheToolAccepts` checks; and declarations moved beneath the seam's module
	/// (seed 153) and a chain of seams through the three modules beneath it (seed 347), which a caller computes from the
	/// seam's module's view (`GraphFuzzerSeamDependencyDraw`); and seams naming a type declared in a block that guards
	/// mock-only declarations, whose other clauses declare it at the same level (seed 277), wider (seed 151) or narrower
	/// (seed 1837), or which has none while another file declares it where `DEBUG` is inactive (seed 881), each compiled
	/// as a release build too; and `addingCycleParameterShapes`' cycle, its hole between the cycle's ends filled by a fill
	/// that reads the label the cycle declares again (seed 227), its hole on the seam (seed
	/// 705), the label aliased and both kinds of wrapper (seed 1010), instantiator declarations in a nested cycle (seed 24),
	/// and opened by value inside `Sendable` wrappers (seed 277). The union of the batches the hole rolls and the seam tests'
	/// draws were each pinned with, less the seeds whose renamed graph shows a known issue's shape: a tangle of cycles, which
	/// the tool now accepts, giving the seam a second hole type whose builders the move across wrapper names reorders
	/// (`seamBuilderOrderReason`), or a lazy cycle's configuration field (`lazyCycleConfigurationFieldReason`); seed 850 stands in for seed 93, whose forwarding place became a second
	/// hole type, for a hole read only if available. Seeds 227, 277, 309, 1020 and 1890, whose seams later draws gave a
	/// second hole type that the move reorders, stay for the shapes above: they are listed under `seamBuilderOrderReason`, a
	/// sanctioned order, which `seamSmokeSeeds_exerciseSeamFeature_inGraphsTheToolAccepts` counts as passing
	/// (`seamBuilderOrderShape(listedBy:)`). Seeds 0, 304 and 1010 are now rejected – both builds reject a
	/// re-entered fill's unremedied read of a value one route holds, and passing-up copies hide a label – so seeds 93, 273,
	/// 468, 743, 892 and 1986 show, accepted, the rolls they showed: a cycle of two seams with a `@Sendable` edge (seed 93),
	/// a diamond with a `@Sendable` seam, and seed 304's inner seam on a plain and a `@Sendable` route (seed 273),
	/// `HoleOwner` aliasing the field (seeds 468 and 1986), a fulfiller's
	/// `package` initializer in another package (seed 743), two calls of the plain fill (seed 892) and mixed wrapper kinds
	/// in the cycle (seed 1986); seeds 151, 309, 594 and 969 draw places inside a plain fill that spell their hole type
	/// with and without `any`, seed 969 with no known issue, and seeds 68 and 84 the remedied read of a value one route
	/// holds. Seeds 2006 and 3575 are a fill that builds its seam again and reads a value only the place it fills,
	/// inside an inner seam's screen, carries, which the tool rejects (`fieldOfReenteringPlace`). Seeds 1815 and 4668
	/// fill a hole whose fill receives a parameter of the seam in a form the parameter does not provide, which the tool
	/// rejects as it rejects the seam whose own tree receives both forms. Pinned by `seamSmokeAndKnownIssueFixtureHash`.
	static let seamSmokeSeeds: [UInt64] = [0, 1, 16, 24, 31, 68, 78, 84, 92, 93, 151, 153, 164, 180, 215, 227, 273, 277, 304, 309, 347, 468, 594, 605, 705, 743, 850, 881, 892, 934, 969, 1_010, 1_020, 1_450, 1_815, 1_837, 1_890, 1_986, 2_006, 3_575, 4_668]

	static let seamSmokeAndKnownIssueFixtureHash: UInt64 = 0x89196AB0BDCA7106

	/// How many of the seam corpus's graphs each shape of `addingSeam` lands in, exactly, as the corpus run observed,
	/// so a draw that stops landing, or a change in a shape's share, fails
	/// `seamCorpus_drawsEachShapeInThePinnedNumberOfGraphs_whenFixturesAreGeneratedWithoutTheTool`.
	static let seamCorpusDrawFeatureCounts: [GraphFuzzerSeamDrawFeature: Int] = [
		.collidingFormsBeneathSeam: 136,
		.innerSeam: 1_262,
		.instanceHeldByCaller: 771,
		.instanceReceiveBeneathSeam: 1_146,
		.otherKindWrapperReceiveBeneathSeam: 63,
		.renameAboveSeam: 41,
		.renameOnSeamOrChild: 799,
		.requiredWrapperProvidingByValueForm: 361,
		.spelledAliasFulfillingProperty: 385,
		.spelledAliasNamingProtocolWithoutAny: 65,
		.spelledAliasOnlyReceiveOfMockedChild: 37,
		.spelledArray: 125,
		.spelledClosure: 131,
		.spelledClosureTakingExistential: 118,
		.spelledClosureWithParameterAndReturn: 133,
		.spelledExistential: 111,
		.spelledNestedType: 104,
		.spelledOnlyIfAvailablePassThrough: 205,
		.spelledOptionalClosure: 90,
		.spelledOptionalSendableClosure: 124,
		.spelledOwnForwarded: 476,
		.spelledOwnReceived: 377,
		.spelledRequiredPassThrough: 389,
		.spelledResult: 115,
		.spelledSendableClosure: 122,
		.spelledTupleWithClosure: 132,
		.spelledTypealias: 148,
		.synthesizedChild: 715,
		.synthesizedHeldProvider: 680,
		.synthesizedLazyProvider: 967,
		.synthesizedSharedProvider: 1_788,
		.uncreatedAliasDeclarationAbove: 170,
		.uncreatedAliasFulfillingPropertyPruned: 131,
		.uncreatedAliasLabelHeldByCaller: 241,
		.uncreatedAliasLabelParameter: 237,
		.uncreatedAliasOtherTypeBeside: 99,
		.uncreatedAliasReader: 95,
		.uncreatedAliasSamePropertyBeside: 89,
		.uncreatedAliasWrapperBeside: 164,
		.spelledOptionalFormOnSibling: 423,
		.spelledTreeMocked: 492,
		.uncreatedAliasFulfillingPropertyHeldByCaller: 351,
		.uncreatedAliasRequiredReader: 0,
		.uncreatedAliasLabelKeepingAliasReader: 76,
		.uncreatedAliasReaderInsideWrapper: 33,
		.uncreatedAliasReaderInsideNestedSeam: 35,
		.uncreatedAliasDeeperReader: 91,
		.uncreatedAliasOnSeamItself: 66,
		.uncreatedAliasFulfillingPropertyBeingBuilt: 92,
		.uncreatedAliasFulfillingPropertyGeneratedLater: 76,
		.uncreatedAliasRequiredOptionalParameter: 74,
		.uncreatedAliasExactFormAlias: 193,
		.uncreatedAliasAcceptedTwin: 325,
		.wrapperReceiveBeneathSeam: 1_158,
		.seamTypeNarrowerThanPublic: 457,
		.receiverNarrowerThanType: 590,
		.receiverTypeNarrowerThanItsInitializer: 151,
		.ownInitializerNarrowerWithNoPassThrough: 130,
		.ownInitializerNarrowerWithOnlyOptionalNarrowerPassThroughs: 163,
		.ownInitializerNarrowerThanTwoParameterLevels: 102,
		.requiredParameterNarrowerThanSeamType: 106,
		.ownOnlyIfAvailableParameter: 222,
		.ownOnlyIfAvailableParameterNarrowerThanSeam: 79,
		.providedValueHeldByCaller: 164,
		.providedValueHeldByNoCaller: 59,
		.unprovenAliasType: 50,
		.unprovenAliasTypeOnlyIfAvailable: 53,
		.aliasOfNarrowerInstantiableType: 49,
		.aliasFulfillingTypeAlsoReceived: 42,
		.namespaceExtensionUnspelled: 119,
		.namespaceExtensionSpelled: 75,
		.publicNamespace: 53,
		.namespaceInMarkerFreeFile: 100,
		.namespaceTypeOnlyThroughExistential: 103,
		.instantiableExtensionOfNarrowerType: 123,
		.qualifiedAllowlistMention: 40,
		.mockCappedByItsExtension: 111,
		.mockCapRaisedByUnreachedMention: 63,
		.mockInInstantiableExtension: 62,
		.typeInExtensionOfSeam: 81,
		.typeInExtensionOfNarrowerRecordedType: 71,
		.valueDeclaredAfterSeam: 138,
		.moduleSplit: 935,
		.otherPackageCaller: 430,
		.samePackageCallerRunWithoutPackageName: 116,
		.seamModuleRunWithoutPackageName: 124,
		.seamDependency: 749,
		.seamDependencyChain: 103,
		.seamDependencyReadThroughView: 400,
		.seamDependencyChainReadThroughView: 60,
		.hole: 647,
		.holeOwnedBySeam: 159,
		.holeProtocolInMarkerFreeFile: 314,
		.holeProtocolPackage: 121,
		.holeBeneathConstant: 118,
		.holeBeneathInstantiator: 177,
		.holeBeneathSendableInstantiator: 68,
		.holeBeneathLazilyInstantiated: 104,
		.holeBeneathSendableLazilyInstantiated: 21,
		.holeOwnerReachedAtTwoSites: 102,
		.holeReadsField: 328,
		.holeReadsCallerValue: 280,
		.holePassedUp: 425,
		.holeReentersSeam: 80,
		.holeReentersSeamBeneathRedeclaredLabel: 13,
		.holeReentersInnerSeamOfPassedUpBuilder: 31,
		.holeSeamReentersItself: 38,
		.holeSeamReentersItselfBeneathBoundLabel: 2,
		.holeCrossPackage: 180,
		.holeCrossPackageFulfillerInitializerPackage: 29,
		.holeCrossPackageFulfillerBuildsPackageInitializerOfSeamsPackage: 22,
		.holeNarrowerField: 37,
		.holeLevelOfSevenValues: 49,
		.holeLevelOfEightValues: 71,
		.holeLevelOfNineValues: 75,
		.holeLevelOfTwelveValues: 69,
		.holeLevelWithPackageValueOnPublicSeam: 52,
		.holeLevelOfPackageValuesOnPackageSeam: 43,
		.holeAliasOrOnlyIfAvailable: 118,
		.holeReadOnlyIfAvailable: 64,
		.holeOwnerAliasesField: 48,
		.holeOwnerLabeledAsKeyword: 205,
		.holeSendablePlaceLabeledAsKeyword: 42,
		.holeMocks: 99,
		.holeImplInNamespace: 95,
		.holeSeamModuleWithoutPackageName: 74,
		.holeReentryThroughPassingSeam: 36,
		.holeReentryThroughPassingSeamBeneathBoundLabel: 14,
		.holeReentryThroughSendablePassingSeam: 15,
		.holeSecondHole: 197,
		.holeSecondHoleBeneathRedeclaredLabel: 3,
		.holeSendableDiamond: 45,
		.holeNestedSameLabelFill: 42,
		.holeSecondHoleType: 68,
		.holeSecondHoleTypeCollidingStem: 98,
		.holeFillReadsForwardedValueOutsideSendableFunction: 10,
		.holeFillReadsDeclaredValueOutsideSendableFunction: 25,
		.holeForwardingPlace: 237,
		.holeInnerSeamPlainAndSendableRoutes: 60,
		.holeInnerSeamWithBothEnums: 31,
		.holeTwoSeamCycleWithSendableEdge: 49,
		.holeInnerSendablePlaceOnSendableRoute: 54,
		.holeLazyWrapperBesideByValuePlace: 117,
		.holeSendableLazyWrapperBesideByValuePlace: 48,
		.holePlaceInsideSendableFill: 178,
		.holeSharedTypes: 172,
		.holeSharedTypesThroughModel: 84,
		.holeTangleOfCycles: 154,
		.holeTangleReadsInstantiator: 75,
		.holeTangleTReadsMark: 136,
		.holeTangleTBuiltByValue: 82,
		.holeLazyRoute: 334,
		.holeLazyRouteSendableWrapper: 91,
		.holeLazyRouteReadOnlyIfAvailable: 152,
		.holeLazyRouteBeneathInstantiator: 137,
		.holeLazyRouteNestedSeamFillRequiresValue: 162,
		.holeLazyRouteSecondFormPlace: 167,
		.holeLazyRouteSecondFormBeneathLevel: 89,
		.holePlaceInsidePlainFill: 234,
		.holePlaceInsidePlainFillOnTwoInnerRoutes: 117,
		.holePlaceInsidePlainFillReadsInnerLevel: 120,
		.holePlaceInsidePlainFillTwoTypesDeep: 94,
		.holePlaceInsidePlainFillTwoCalls: 66,
		.holePlaceInsidePlainFillFulfillerReadsInnerLevel: 55,
		.holePlacesInsideFillSpellTypeWithAndWithoutAny: 136,
		.holeUnderLaterLoopMember: 84,
		.holeUnderEveryLoopMember: 60,
		.holeLoopOfThreeMembers: 26,
		.holeLoopPlaceThroughSharedLeaf: 28,
		.holeLoopBeneathSeam: 28,
		.holeLoopMemberLevelReadByFill: 29,
		.holeLoopMemberAlsoBuiltByValue: 27,
		.holeErasureInsidePlainFill: 180,
		.holeErasureInsideSendableFill: 163,
		.holeErasureBeneathSeamInSendableFamily: 216,
		.uncreatedAliasLabelLazilyInstantiatedBeside: 52,
		.uncreatedAliasLabelReceivedBeside: 33,
		.uncreatedAliasLabelOnMid: 7,
		.uncreatedAliasSeamRequiresLabel: 16,
		.uncreatedAliasSeamReceivesLabelAsAnotherType: 17,
		.uncreatedAliasLabelAliasesOtherParameter: 22,
		.uncreatedAliasLabelDeclaredAfterDetail: 66,
		.uncreatedAliasLabelDeclaredBesideAndAbove: 48,
		.uncreatedAliasClientReceivesWrapper: 34,
		.uncreatedAliasReaderOfAliasOfAlias: 25,
		.uncreatedAliasRequiredLabelKeepingAliasReader: 29,
		.uncreatedAliasReaderRedeclaresAlias: 23,
		.uncreatedAliasLabelGeneratedAfterDetail: 104,
		.uncreatedAliasSeamReceivesFulfillingPropertyOnlyIfAvailable: 89,
		.uncreatedAliasFulfillingPropertyRequiredBeside: 70,
		.uncreatedAliasAcrossModules: 223,
		.spelledAcrossModules: 357,
		.unreadParameterType: 288,
		.unreadParameterTypeThroughTypealias: 35,
		.recordedInsideConditionalBlock: 49,
		.recordedInFlagClause: 95,
		.unreadBoundaryInPackageExtension: 45,
		.unreadBoundaryInExtensionOfNestedType: 48,
		.unreadBoundaryInternalTypealias: 52,
		.unreadAcrossModules: 112,
		.mockOnlyBlockTypeElseSameLevel: 44,
		.mockOnlyBlockTypeElseWider: 61,
		.mockOnlyBlockTypeElseNarrower: 50,
		.mockOnlyBlockTypeRedeclaredWhereMockConditionIsInactive: 57,
		.mockOnlyBlockAcrossModules: 56,
		.formsAcrossModules: 282,
		.formsSeam: 986,
		.formsByValueReceive: 548,
		.formsWrapperReceive: 685,
		.formsOptionalWrapperReceive: 210,
		.formsSeamOwnReceive: 105,
		.formsDetailInSendableBuilder: 66,
		.formsCallerHoldsInstance: 115,
		.formsCallerHoldsWrapper: 478,
		.formsCallerForwardsOptionalForm: 133,
		.formsCallerHoldsNearerOptionalInstance: 42,
		.formsInstanceTreeBuildsSeam: 54,
		.formsInstanceTreeReceivesSeamOnlyIfAvailable: 91,
		.formsCallerHoldsNothing: 73,
		.formsUserDeclaredAfterSeam: 343,
		.foundationQualifiedAllowlistMention: 40,
		.mockOnlyFakeMentionsReceivedType: 118,
		.lazilyInstantiatedProvider: 47,
		.hostReceivesValuesOnlyIfAvailable: 114,
		.seamReachedThroughHolder: 201,
		.samePackageHostIsSeam: 327,
		.otherPackageHostIsSeam: 86,
		.cycleParameterSeam: 660,
		.cycleParameterOpenedByInstantiator: 291,
		.cycleParameterOpenedLazily: 273,
		.cycleParameterOpenedByValue: 96,
		.cycleParameterSendableWrappers: 180,
		.cycleParameterMixedWrapperKinds: 50,
		.cycleParameterTwoLevelsDeep: 264,
		.cycleParameterNestedCycle: 82,
		.cycleParameterDeclaredLazily: 208,
		.cycleParameterDeclaredAsInstantiators: 112,
		.cycleParameterDeclaredAsHidingInstantiator: 15,
		.cycleParameterDeclaredAsAlias: 81,
		.cycleParameterDeclaredAfterCloser: 130,
		.cycleParameterReaderRequiresValue: 203,
		.cycleParameterReaderReceivesOnlyIfAvailable: 169,
		.cycleParameterReaderRequiresWrapper: 29,
		.cycleParameterReaderReceivesWrapperOnlyIfAvailable: 28,
		.cycleParameterReaderReceivesInstantiator: 85,
		.cycleParameterWithoutReader: 84,
		.cycleParameterReaderBetween: 108,
		.cycleParameterSideReceivesValue: 164,
		.cycleParameterSideReceivesWrapper: 60,
		.cycleParameterSideReceivesInstantiator: 39,
		.cycleParameterDeclaredBySeam: 401,
		.cycleParameterDeferredFromCaller: 231,
		.cycleParameterUndeclaredAbove: 28,
		.cycleParameterHoleOnSeam: 104,
		.cycleParameterHoleOnClosedOnType: 244,
		.cycleParameterHoleBetween: 252,
		.cycleParameterHoleAtOrBeneathDeclaration: 218,
		.cycleParameterHoleOnReader: 60,
		.cycleParameterFillReadsLabel: 436,
		.cycleParameterFillReadsLabelNoParameterCarries: 5,
		.cycleParameterDeferredNote: 199,
		.cycleParameterNoteReceivedAfterLabel: 100,
		.cycleParameterNoteDeclaredAgain: 56,
		.cycleParameterFillReadsNote: 207,
		.cycleParameterMocked: 147,
		.forwardedLabelAcrossSeamCall: 797,
		.forwardedLabelAcrossSeamCallCallerInsideSeam: 260,
		.forwardedLabelAcrossSeamCallFillReadsLabel: 340,
		.forwardedLabelAcrossSeamCallInnerOptional: 111,
		.forwardedLabelAcrossSeamCallOtherTypes: 233,
		.forwardedLabelAcrossSeamCallOuterDefers: 120,
		.forwardedLabelAcrossSeamCallPlaceBeneath: 243,
		.forwardedLabelAcrossSeamCallSameClassType: 160,
		.forwardedLabelAcrossSeamCallSameValueType: 173,
		.forwardedLabelAcrossSeamCallSendable: 220,
		.retentionLoopOfBuilders: 539,
		.retentionLoopOfBuildersBeneathSeam: 227,
		.retentionLoopOfBuildersFourMembers: 202,
		.retentionLoopOfBuildersSendable: 142,
		.retentionSeamValueBeforeBuilder: 779,
		.retentionSeamValueBeforeBuilderFillReadsValue: 143,
		.retentionSeamValueBeforeBuilderInnerSeam: 270,
		.retentionSeamValueBeforeBuilderLeafThroughInstantiator: 395,
		.retentionSeamValueBeforeBuilderSendable: 208,
		.holeForwardingPlaceLabeledPair: 182,
		.holeForwardingPlaceSecondPlace: 210,
		.holeForwardingPlaceSecondPlaceSpelledOtherwise: 201,
		.holeForwardingPlacePassedUp: 176,
		.holeInstantiatorPlace: 615,
		.holeInstantiatorPlaceBesideErased: 514,
		.holeInstantiatorPlaceBesidePlain: 547,
		.holeInstantiatorPlaceBesidePlainAcrossFamilies: 207,
		.holeNothingForwardedPlace: 617,
		.holeNothingForwardedPlaceBesidePlain: 258,
		.holeNothingForwardedPlaceBesideInstantiator: 288,
		.holeNothingForwardedPlacePassedUp: 408,
		.retentionSeamValueBeforeBuilderForwardingPlace: 326,
		.fillCallReadsOwnLevel: 715,
		.fillCallReadsOwnLevelSharedLabel: 246,
		.fillCallReadsOwnLevelSendableRoute: 120,
		.fillCallReadsOwnLevelInsideSendableFill: 192,
		.fillCallReadsOwnLevelSendableCall: 199,
		.carriedLevel: 614,
		.carriedLevelTwoRoutes: 432,
		.carriedLevelFillReadsForwarded: 203,
		.carriedLevelFillReadsDeferredValue: 382,
		.carriedLevelFillReadsDeferredValueRootDeclares: 184,
		.carriedLevelFillReadsDeferredValueOnTopsRouteToo: 88,
		.carriedLevelFillReadsDeferredValueFromTwoSeams: 238,
		.carriedLevelFillReadsSendableWrapper: 78,
		.carriedLevelFillReadsSendableWrapperAlone: 75,
		.carriedLevelFillReadsOptionalSendableWrapper: 48,
		.carriedLevelFillReadsOptionalSendableWrapperOuterReceives: 16,
		.passingUpCopies: 507,
		.passingUpCopiesFillReadsLabel: 260,
		.passingUpCopiesSeamsBindLabel: 126,
		.passingUpCopiesHideLabel: 37,
		.reenteredFill: 705,
		.reenteredFillReadsValueAbove: 272,
		.reenteredFillReadsValueOfOneRoute: 37,
		.reenteredFillReadsValueOfOneRouteBoundAboveCall: 31,
		.reenteredFillReadsValueOfOneRouteRemedied: 246,
		.reenteredFillReadsPlaceField: 24,
		.reenteredFillReadsPlaceFieldBoundAboveCall: 20,
		.reenteredFillRequiresPlaceField: 22,
		.reenteredFillReadsPlaceFieldRemedied: 284,
		.reenteredFillReadsPlaceFieldDeclaredInFill: 162,
		.reenteredFillReadsLabelPassingUpSeamBinds: 11,
		.reenteredFillEnclosingFillHoldsPlace: 246,
		.reenteredFillReentersEnclosingFill: 224,
		.reenteredFillCallBeneathFilledType: 217,
		.reenteredFillSendableCall: 69,
		.reenteredFillCallThroughSeamPassingPlaceUp: 253,
		.holePassedUpPlaceReadsPassingSeamsValue: 143,
		.holePassedUpPlaceReadsValueTwoSeamsUp: 153,
		.holePassedUpPlaceReadsLazyValue: 153,
		.holePassedUpPlaceReadsOptionalField: 152,
		.holeScreenPlace: 300,
		.holeScreenValueLostOnReentry: 10,
		.holeScreenValueRequiredLostOnReentry: 2,
		.holeScreenValueReceivedBySeam: 68,
		.holeScreenValueBuiltBySeam: 104,
		.holeScreenValueReadWithoutReentry: 116,
		.reenteredFillCallThroughSeamPassingPlaceUpInSendableFill: 64,
		.reenteredFillCallThroughSeamPassingPlaceUpByTypeOfAnotherModule: 62,
		.nestedCycleHole: 263,
		.nestedCycleHoleLabelDeclaredAfterCloser: 132,
		.nestedCycleHoleLabelNoFunctionTakes: 16,
		.nestedCycleHoleLabelReceivedBySeamPassingPlaceUp: 94,
		.nestedCycleHoleLabelReceivedByTypeBuiltAgain: 153,
		.nestedCycleHolePlaceOnScreen: 126,
		.nestedCycleHolePlacePassedUp: 98,
		.nestedCycleHoleThirdCycle: 90,
		.wrapperMix: 378,
		.wrapperMixValueAndSendableWrapper: 372,
		.wrapperMixSendableWrapperBesidePlainMemo: 40,
		.wrapperMixWrapperDeclaredAboveCall: 13,
		.wrapperMixWrapperReadInSendableFunction: 249,
		.placesOfOneCase: 556,
		.placesOfOneCaseHandFillsOtherValues: 447,
		.placesOfOneCaseFillReadsOnlyIfAvailable: 165,
		.placesOfOneCaseFillClosesCycleAtTwoDepths: 21,
		.placesOfOneCaseFillCapturesWrapperOfEveryPlace: 43,
		.placesOfOneCaseValueBoundAfterOnePlace: 11,
		.nestedFillHole: 567,
		.nestedFillHoleBeneathInstantiator: 186,
		.nestedFillHoleInnerPlaceBeneathInstantiator: 207,
		.nestedFillHoleUnfilled: 19,
		.seamRing: 238,
		.seamRingOfSendableInstantiators: 71,
		.seamRingWithoutRootValues: 101,
		.seamRingRooted: 135,
		.carrierDrawUnequalSiblings: 299,
		.carrierDrawUnequalSiblingsBeneathChild: 153,
		.carrierDrawCoincidingLabel: 332,
		.carrierDrawCoincidingLabelOnSeamToo: 115,
		.carrierDrawKeySplitFamilies: 256,
		.carrierDrawWrappedBesidePlain: 330,
		.carrierDrawWrappedBesidePlainLazy: 169,
		.carrierDrawWrappedBesidePlainErased: 161,
		.carrierDrawMixedInnerSeamFillAndPassUp: 284,
		.carrierDrawMixedInnerSeamFillAndPassUpThroughInstantiator: 124,
		.carrierDrawLoopLevelReadByFill: 340,
		.carrierDrawLoopLevelReadByFillThreeMembers: 144,
		.optionalPlace: 660,
		.optionalPlaceFilled: 404,
		.optionalPlaceUnfilled: 256,
		.optionalPlaceOnSeam: 175,
		.optionalPlaceThroughInstantiator: 179,
		.optionalPlacePassedUp: 247,
		.optionalPlaceBesideRequiredPlace: 154,
		.optionalPlaceReceivedRequired: 295,
		.optionalPlaceSeamMocked: 74,
	]

	/// Seeds in `0..<seamCorpusSeedCount` whose graphs fail today. The 1 000-seed run of this corpus found that each
	/// shape of `knownIssues` fails the same seeds here, below the corpus's size, but those the seam's own draw
	/// changes (`seamCorpusSeedsOfOtherShapes`), and fails some the base corpus does not list under it
	/// (`seamCorpusSeedsAddedToInheritedShapes`): the inherited shapes are listed from `knownIssues` with those
	/// adjustments, a shape left with no seed dropped, so that a fix there is a fix here, and the long run reports a
	/// seed that diverges as stale or new. The seam's own shape follows them. Each seed is listed once.
	static let seamKnownIssuesBesideBuilderSurface: [GraphFuzzerKnownIssue] = knownIssuesBesideReportedIssueShapes.compactMap { knownIssue in
		// The base corpus's value oracle runs in no other corpus.
		guard !knownIssue.isBaseCorpusValueOracleShape else { return nil }
		let seeds = (knownIssue.seeds.filter { $0 < UInt64(seamCorpusSeedCount) && !seamCorpusSeedsOfOtherShapes.contains($0) }
			+ (seamCorpusSeedsAddedToInheritedShapes[knownIssue.reason] ?? [])).sorted()
		return seeds.isEmpty ? nil : GraphFuzzerKnownIssue(reason: knownIssue.reason, signatures: knownIssue.signatures, seeds: seeds)
	} + [
		GraphFuzzerKnownIssue(
			reason: labelSortedPassThroughReason,
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder)],
			seeds: labelSortedPassThroughSeeds,
		),
		GraphFuzzerKnownIssue(
			reason: labelSortedPassThroughAndMockParametersReason,
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder), .renamedGraphDiffers(.mockParameterAndFieldOrder)],
			seeds: labelSortedPassThroughSeedsWhoseMockParametersAlsoChange,
		),
		// The nested builders' design orders a seam's builders by label, so by their hole types' names, which the move
		// across wrapper names reorders where two hole types take other letters, such as the two erasures of
		// `HoleGadgetImpl`, labeled by the types they return.
		GraphFuzzerKnownIssue(
			reason: seamBuilderOrderReason,
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder)],
			seeds: [
				15, 38, 69, 93, 94, 98, 121, 151, 164, 227, 273, 277, 283, 298, 309, 341, 347, 348, 407, 478, 481,
				494, 500, 527, 556, 562, 564, 594, 605, 618, 663, 669, 670, 699, 701, 710, 752, 769, 787, 838, 850, 876,
				883, 892, 905, 930, 931, 976, 1_020, 1_048, 1_050, 1_094, 1_096, 1_142, 1_156, 1_269, 1_317, 1_320,
				1_336, 1_340, 1_355, 1_393, 1_454, 1_463, 1_471, 1_475, 1_511, 1_528, 1_536, 1_541, 1_569, 1_581, 1_599,
				1_605, 1_610, 1_637, 1_657, 1_661, 1_668, 1_674, 1_678, 1_720, 1_763, 1_773, 1_788, 1_790, 1_794, 1_813,
				1_849, 1_850, 1_860, 1_890, 1_914, 1_954,
			],
		),
		// The chains of hole draws that re-enter one another of seeds 391 and 1311 hold more wrappers than a graph compared on
		// its own may traverse (`DifferentialValueLimits.isolatedFuzzerGraph`), so the comparator describes none of their
		// values beneath the point where their traversals run out; seed 967's hold more than a graph compared in the batch
		// may traverse, and run out at the batch's bound.
		GraphFuzzerKnownIssue(
			reason: "\(seamTraversalLimitReason); and \(seamBuilderOrderReason)",
			signatures: [
				.valueComparatorCouldNotDescribeGraph(containing: "spent its 200000 traversals"),
				.valueComparatorCouldNotDescribeGraph(containing: "spent its 10000 traversals"),
				.renamedGraphDiffers(.dependencyTreeListOrder),
			],
			seeds: [391, 967, 1_311],
		),
		// The forwarding place's hole type is a second hole type beside `HoleService`, so its builders reorder too; and the
		// erasures of `HoleGadgetImpl` in graphs whose mock shows the inherited shape of a mock's API, which the base corpus
		// lists 311, 338, 595, 836 and 948 under.
		GraphFuzzerKnownIssue(
			reason: "\(seamBuilderOrderReason); and \(lazyCycleConfigurationFieldReason)",
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder), .renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [
				163, 383, 484, 567, 595, 742, 749, 751, 836, 886, 940, 948, 1_065, 1_145, 1_149, 1_232, 1_352, 1_464,
				1_524, 1_804, 1_888,
			],
		),
		GraphFuzzerKnownIssue(
			reason: "\(seamBuilderOrderReason); and \(mockParameterAndFieldOrderReason)",
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder), .renamedGraphDiffers(.mockParameterAndFieldOrder)],
			seeds: [146, 281, 300, 548, 1_163, 1_300, 1_301, 1_535, 1_561, 1_563],
		),
		// Seams with two or more pass-throughs whose builders the move across wrapper names reorders too.
		GraphFuzzerKnownIssue(
			reason: "\(labelSortedPassThroughReason); and \(seamBuilderOrderReason)",
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder)],
			seeds: [330, 809, 950, 1_055],
		),
		// The same, in a graph whose integrations also emit other compile-time assertions, as the base corpus's graph of the
		// seed did before `addingMockPassedLabelAboveAliasCycle` drew a cycle into it.
		GraphFuzzerKnownIssue(
			reason: "\(labelSortedPassThroughReason); and \(seamBuilderOrderReason); and \(compileTimeAssertionsDifferBetweenIntegrationsReason)",
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder), .integrationsDiffer(containing: "<compile-time assertions>")],
			seeds: [1_278],
		),
		GraphFuzzerKnownIssue(
			reason: "\(labelSortedPassThroughReason); and \(lazyCycleConfigurationFieldReason)",
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder), .renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [1_154, 1_567],
		),
		// A seam's own internal mock takes a builder for each hole its tree cannot fill, sorted among its parameters by
		// label, so the move across wrapper names that reorders the seam's builders reorders the mock's too.
		GraphFuzzerKnownIssue(
			reason: "\(seamBuilderOrderReason); and \(seamMockBuilderOrderReason)",
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder), .renamedGraphDiffers(.mockCode)],
			seeds: [83, 108, 326, 362, 365, 797, 858, 929],
		),
		GraphFuzzerKnownIssue(
			reason: "\(seamBuilderOrderReason); and \(seamMockBuilderOrderReason); and \(lazyCycleConfigurationFieldReason)",
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder), .renamedGraphDiffers(.mockCode), .renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [19, 1_139],
		),
		GraphFuzzerKnownIssue(
			reason: "\(seamBuilderOrderReason); and \(mockParameterAndFieldOrderAndLazyCycleConfigurationFieldReason)",
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder), .renamedGraphDiffers(.mockParameterAndFieldOrder), .renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [21],
		),
		// Seed 848's seam's own mock and its configuration change with its builders' order, and its other mocks' parameters
		// with their labels, so it shows four shapes at once.
		GraphFuzzerKnownIssue(
			reason: "\(seamBuilderOrderReason); and \(seamMockBuilderOrderReason); and \(mockParameterAndFieldOrderAndLazyCycleConfigurationFieldReason)",
			signatures: [.renamedGraphDiffers(.dependencyTreeListOrder), .renamedGraphDiffers(.mockCode), .renamedGraphDiffers(.mockParameterAndFieldOrder), .renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [848],
		),
		// The base corpus lists seed 1959 under the mock's parameter order alone; the seam's draw also gives its lazy cycle a
		// configuration field that a renaming drops.
		GraphFuzzerKnownIssue(
			reason: mockParameterAndFieldOrderAndLazyCycleConfigurationFieldReason,
			signatures: [.renamedGraphDiffers(.mockParameterAndFieldOrder), .renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [1_959],
		),
		// The remedy oracle's shapes that only a seam's tree shows.
		GraphFuzzerKnownIssue(
			reason: remedySeamProvidingWrapperUndeclaredReason,
			signatures: [
				.remedyLeavesErrorAtSite(.declareProvidingFormOnSeam, containing: "` is not @Instantiated or @Forwarded in chain: "),
				.remedyLeavesErrorAtSite(.declareProvidingFormOnSeam, containing: "Dependency cycle: "),
			],
			seeds: [
				63, 107, 184, 260, 580, 685, 686, 715, 731, 871, 898, 911, 939, 957, 1_051, 1_123, 1_177, 1_200, 1_374,
				1_415, 1_504, 1_538, 1_752, 1_760, 1_955,
			],
		),
		// The remedy oracle's seam fill shapes whose advice names a wrapper that a `@Sendable` function cannot capture.
		GraphFuzzerKnownIssue(
			reason: remedySeamFillInstantiatedOutsideNotSendableReason,
			signatures: [.remedyLeavesErrorAtSite(.instantiateOutsideSeam, containing: "cannot be received inside a `@Sendable` function")],
			seeds: [1_401],
		),
		GraphFuzzerKnownIssue(
			reason: remedySeamFillBuilderPassedOnReason,
			signatures: [
				.remedyLeavesErrorAtSite(.instantiateOutsideSeam, containing: "would get another value"),
				.remedyLeavesErrorAtSite(.receiveOnSeam, containing: "on from its own caller, which cannot hand"),
			],
			seeds: [614],
		),
		GraphFuzzerKnownIssue(
			reason: remedyRelabelLeavesSeamLabelInTwoFormsReason,
			signatures: [.remedyLeavesErrorAtSite(.relabelHidingDeclaration, containing: "the same way in every type of the tree")],
			seeds: [1_935],
		),
		GraphFuzzerKnownIssue(
			reason: remedySeamFillCycleReceiveNotSendableReason,
			signatures: [.remedyLeavesErrorAtSite(.receiveOnTypeTheCycleBuilds, containing: "cannot be received inside a `@Sendable` function")],
			seeds: [1_916],
		),
	]

	/// `seamKnownIssuesBesideBuilderSurface` with each part of the builder surface added for its seeds.
	static let seamKnownIssues = addingBuilderSurfaceShapes(seeds: seamBuilderSurfaceSeeds, to: seamKnownIssuesBesideBuilderSurface)

	/// `seamKnownIssues` and `seamSmokeKnownIssuesBeyondTheCorpus`, with the smoke seeds beyond the seam corpus that fail
	/// the builder surface, which the corpus's list, bounded by its size, cannot hold.
	static let seamSmokeKnownIssues = addingBuilderSurfaceShapes(
		seeds: BuilderSurfaceSeeds(
			base: [],
			labels: [],
			sameSupply: [],
			sameSupplyReason: seamMockTakesHoleValueReason,
			sameSupplyBuilderKindFlips: [],
			remedyBuilderKindFlips: [],
			addedSupply: [],
			forwardingOtherValues: [],
			callingMocks: [],
		),
		to: seamKnownIssues + seamSmokeKnownIssuesBeyondTheCorpus,
	)

	/// The fewest graphs of a corpus the builder surface must judge for each kind it floors (`Corpus.builderSurfaceFlooredKinds`):
	/// below ten, a draw no longer stands in for unit tests of its shape.
	static let builderSurfaceFloor = 10

	/// The seeds of a corpus that fail each part of the builder surface, each part's list apart: the base check, the label
	/// check, same supply (i), added supply (ii), places forwarding other values (iii) and calling mocks (iv).
	struct BuilderSurfaceSeeds {
		let base: [UInt64]
		let labels: [UInt64]
		let sameSupply: [UInt64]
		/// Why `sameSupply`'s graphs fail, which differs by corpus: the shape each corpus's same-supply edits show.
		let sameSupplyReason: String
		/// Seeds whose same-supply call stops compiling because the edit flips a builder's kind.
		let sameSupplyBuilderKindFlips: [UInt64]
		/// Why `sameSupplyBuilderKindFlips`' graphs fail, which differs by corpus: a seam's builder that flips between a struct
		/// and a closure over its enum (`sameSupplyBuilderKindFlipReason`), or a public mock's that flips between one that
		/// takes nothing and one handed the scope (`publicMockBuilderFormFlipReason`).
		var sameSupplyBuilderKindFlipsReason = sameSupplyBuilderKindFlipReason
		/// Seeds whose part (iii) remedy flips a builder's kind, so the remedy takes other builders, `remedyBuilderKindFlipReason`.
		let remedyBuilderKindFlips: [UInt64]
		let addedSupply: [UInt64]
		let forwardingOtherValues: [UInt64]
		let callingMocks: [UInt64]
	}

	/// `issues` with each part of the builder surface's shape added for its seeds (`GraphFuzzerKnownIssue.adding`).
	private static func addingBuilderSurfaceShapes(seeds: BuilderSurfaceSeeds, to issues: [GraphFuzzerKnownIssue]) -> [GraphFuzzerKnownIssue] {
		var issues = GraphFuzzerKnownIssue.adding(.builderSurface(.builderSurfaceNamesGeneratedType), reason: builderSurfaceReason, seeds: seeds.base, to: issues)
		issues = GraphFuzzerKnownIssue.adding(.builderSurface(.builderLabelBreaksContract), reason: labelReason, seeds: seeds.labels, to: issues)
		issues = GraphFuzzerKnownIssue.adding(.builderSurface(.sameSupplyCallStopsCompiling), reason: seeds.sameSupplyReason, seeds: seeds.sameSupply, to: issues)
		issues = GraphFuzzerKnownIssue.adding(.builderSurface(.sameSupplyCallStopsCompiling), reason: seeds.sameSupplyBuilderKindFlipsReason, seeds: seeds.sameSupplyBuilderKindFlips, to: issues)
		issues = GraphFuzzerKnownIssue.adding(.builderSurface(.remedyAddsBuilder), reason: remedyBuilderKindFlipReason, seeds: seeds.remedyBuilderKindFlips, to: issues)
		issues = GraphFuzzerKnownIssue.adding(.builderSurface(.addedBuilderChangesExistingBuilder), reason: addedSupplyReason, seeds: seeds.addedSupply, to: issues)
		issues = GraphFuzzerKnownIssue.adding(.builderSurface(.placesForwardingOtherValuesAccepted), reason: forwardingOtherValuesReason, seeds: seeds.forwardingOtherValues, to: issues)
		return GraphFuzzerKnownIssue.adding(.builderSurface(.callingMockChangesBuilder), reason: callingMocksReason, seeds: seeds.callingMocks, to: issues)
	}

	/// Why a graph with a hole fails the builder surface on main (`GraphFuzzerToolRuns.builderSurfaceFailure`).
	static let builderSurfaceReason = "A seam's readable initializer and a mock hand each hole's builder a generated scope enum, so a builder a person writes names generated code; the planned builder structs replace it with builders that take only what their place forwards"

	private static let labelReason = "A builder of a hole is labeled `<fillingType>Builder` until a second returned type of its filling type appears, and a calling mock names builders apart after each called type, where contract rule 8 labels each builder by its filling type, returned type and family alone"

	/// The seam corpus's same-supply shape, which stays for 2.x: an internal mock keeps 2.2.0's flat parameters, so
	/// `HoleOwner`'s internal `mock()` takes `holeService: any S98_HoleService` (seed 98) where the seam takes a builder,
	/// and a builder added later comes with a default beside the flat parameter ("A seam's own internal mock" in
	/// `public-mock-builders.md`).
	private static let seamMockTakesHoleValueReason = "An internal mock of a type that is not a seam, such as `HoleOwner`'s, takes the value of a place its module cannot build, or the wrapper the place spells, as a flat parameter where the seam takes one builder per filling type, returned type and family, so moving the place behind `LazilyInstantiated` or into an inner seam, or giving a second place the same label, changes the parameter's type, its label or its order (Intended: an internal mock keeps the flat parameters 2.2.0 gave it for 2.x, and a builder added later comes with a default beside the flat parameter)"

	/// The public mock corpus's same-supply shape, which stays for 2.x: an internal mock keeps 2.2.0's flat parameters, so
	/// an internal calling mock takes `hole: S128_Hole` (seed 128), and a builder added later comes with a default beside
	/// the flat parameter. Seeds 230 and 539 show its other form: a type a mock builds with its hand-written mock
	/// (`customMockName`) takes the hole's value as that mock's parameter, which stays a flat parameter, as a hand-written
	/// mock's parameters are its API. Seeds 79 and 658 show a third: the calling mock builds a promoted `HoleHost` from the
	/// hole's flat value and passes it to the called public mock (`S79_T6.__safeDI_mock(…, holeHostBuilder:)`).
	private static let callingMockTakesHoleValueReason = "An internal calling mock passes the called public mock's hole up as a flat parameter, the hole's value or the wrapper its place spells, where its twin takes one builder per filling type, returned type and family, or a type built with its hand-written mock takes that value or wrapper as the hand-written mock's parameter, so changing the place's wrapper changes the parameter's type or its label (Intended: an internal mock keeps the flat parameters 2.2.0 gave it for 2.x, and a builder added later comes with a default beside the flat parameter; a hand-written mock's parameters are its API)"

	/// Transitional: owned by the change that gives every public mock builder one form, which empties these seeds. The
	/// edit moves a place behind `LazilyInstantiated` or into an instantiator that forwards a value, which keeps the
	/// builder handed the scope, where the drawn graph's builder takes nothing, or the reverse, so the call written for one
	/// does not compile against the other: every problem these seeds add names such a builder parameter.
	private static let publicMockBuilderFormFlipReason = "A transitional builder-form flip: a public mock's builder takes nothing only while none of its places is lazily instantiated, built in a `@Sendable` function, forwards a value or reaches another scope, so an edit that moves a place behind `LazilyInstantiated` or into an instantiator that forwards a value flips the builder to one handed the scope, and a call written for the drawn graph stops compiling, until every public mock builder takes one form"

	/// Transitional: owned by the change that hands every seam builder structs, which empties these seeds.
	private static let sameSupplyBuilderKindFlipReason = "A transitional builder-kind flip: a seam takes builder structs only while its builders reach no place that forwards a value and hold no scope of another seam, so an edit that adds a place opening another seam's scope (an `.inner` case) flips a builder from a struct to a closure over a scope enum, and a call of the readable initializer stops compiling, until every seam takes builder structs"

	/// Transitional: owned by the change that hands every seam builder structs, which empties these seeds.
	private static let remedyBuilderKindFlipReason = "A transitional builder-kind flip: a seam takes builder structs only while its builders reach no place that forwards a value and hold no scope of another seam, so the remedy of places that forward other values, whose places forward the same values, flips a builder between a struct and a closure over a scope enum, keeping its label, until every seam takes builder structs"

	private static let addedSupplyReason = "A builder takes `<fillingType>_<ReturnedType>Builder` only once a second returned type of its filling type appears, so adding a place of a new builder of an existing filling type renames the existing builder"

	private static let forwardingOtherValuesReason = "Places of one builder that forward other values are merged into one builder rather than rejected, so the builder cannot take only what each place forwards"

	private static let callingMocksReason = "An internal mock that passes up the places of two calls of public mocks of one hole type names their builders apart after each called type, so adding the second call adds a builder and renames the first's, where the second call's places are places of the first's builder"

	/// The seam corpus's graphs that fail each part of the builder surface today, observed from a run of the tool over
	/// the corpus (`GraphFuzzerBuilderSurface`), each part's seeds apart: the base check (every graph with a hole the tool
	/// accepts), the label check, same supply (i), added supply (ii), places forwarding other values (iii) and calling
	/// mocks (iv). The planned builder structs empty them, each slice the seeds it fixes, but for same supply's, a shape
	/// that stays for 2.x (`seamMockTakesHoleValueReason`).
	static let seamBuilderSurfaceSeeds = BuilderSurfaceSeeds(
		base: [],
		labels: [],
		sameSupply: [98, 151, 273, 300, 990, 1_020, 1_050, 1_094, 1_159, 1_210, 1_331, 1_524],
		sameSupplyReason: seamMockTakesHoleValueReason,
		sameSupplyBuilderKindFlips: [],
		remedyBuilderKindFlips: [],
		addedSupply: [],
		forwardingOtherValues: [],
		callingMocks: [],
	)

	/// `seamSmokeKnownIssues` by seed, which the smoke batch consults.
	static let seamSmokeKnownIssuesBySeed = Dictionary(uniqueKeysWithValues: seamSmokeKnownIssues.flatMap { knownIssue in knownIssue.seeds.map { ($0, knownIssue) } })

	/// The known issues of the smoke batch's seeds beyond the seam corpus, which no corpus run reaches: the in-seam leak,
	/// until its fix, and the order of a seam's builders by label. In order of their seeds.
	static let seamSmokeKnownIssuesBeyondTheCorpus: [GraphFuzzerKnownIssue] = []

	private static let inSeamLeakReason = "A seam's builder functions capture the values of each level on the way to a place, so holding a builder keeps them alive where the inline build frees them, until the in-seam leak fix"

	/// What the in-seam leak keeps alive in the seam corpus's graphs and the smoke batch's, each type after its graph's
	/// prefix with what is held and both counts, as the corpus runs observed: `addingRetentionShapes`' generated fill, and
	/// the hole draws' tangle, ring, nest and cycle.
	private static let inSeamLeakSignatures: [GraphFuzzerKnownIssue.Signature] = [
		"_ChainBase alive holding holeSeam.Protocol once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainBase alive holding holeSeam.Self once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainBase alive holding holeSeam.Type once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainBase alive holding holeSeam.default once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainBase alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainBase alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainBase alive holding holeSeam.holeOwnerBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainBase alive holding holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainBase alive holding holeSeam.init once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainBase alive holding holeTop.holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainBase alive holding holeTop.holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLeaf alive holding holeSeam.Protocol once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLeaf alive holding holeSeam.Self once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLeaf alive holding holeSeam.Type once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLeaf alive holding holeSeam.default once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLeaf alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLeaf alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLeaf alive holding holeSeam.holeOwnerBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLeaf alive holding holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLeaf alive holding holeSeam.init once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLeaf alive holding holeTop.holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLeaf alive holding holeTop.holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLink alive holding holeSeam.Protocol once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLink alive holding holeSeam.Self once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLink alive holding holeSeam.Type once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLink alive holding holeSeam.default once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLink alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLink alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLink alive holding holeSeam.holeOwnerBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLink alive holding holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLink alive holding holeSeam.init once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLink alive holding holeTop.holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ChainLink alive holding holeTop.holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_Cycle4Reader alive holding cycleSeam.cycle1A.cycle2BBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_CycleTag alive holding cycleSeam.cycle1A.cycle2BBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_CycleTag> alive holding cycleSeam.cycle1A once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_ForwardedUser alive holding forwardedHome.forwardedOuter.forwardedInnerBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeBoth.holeSeamPlain.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeBoth.holeSeamPlain.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeBothTop.holeBoth.holeSeamPlain.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeBothTop.holeBoth.holeSeamPlain.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeBothTop.holeBoth.holeSeamPlain.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeOuter.holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeOuter.holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeOuter.holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeOuter.holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeOuter.holeSeam.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeSeam.holeRingAValue.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeSeam.holeTangleTValue.holeTangleService.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeTop.holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeTop.holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeTop.holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleAnalytics alive holding holeTop.holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleDeep> alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleDeep> alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleDeep> alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleDeep> alive holding holeTop.holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleErasureImpl alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleErasureImpl alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleErasureImpl alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeOuter.holeSeam.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeOuter.holeSeam.holeServiceLater once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeOuter.holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeOuter.holeSeam.holeTicketBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeOuter.holeSeam.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeOuter.holeSeam.holeTicketHolder.holeTicketOther once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeSeam.holeRingAValue.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetImpl alive holding holeSeam.holeTicketBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleGadgetOwner alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetOwner alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetOwner alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetOwner alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetOwner alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetOwner alive holding holeOuter.holeSeam.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetOwner alive holding holeOuter.holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetOwner alive holding holeOuter.holeSeam.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetOwner alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetOwner alive holding holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetOwner alive holding holeSeam.holeRingAValue.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetOwner alive holding holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleGadgetOwner alive holding holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeBoth.holeSeamPlain.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeBoth.holeSeamPlain.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeOuter.holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeOuter.holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeOuter.holeSeam.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeOuter.holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeOuter.holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeOuter.holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeSeam.holeNestBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeSeam.holeRingABuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeSeam.holeRingBBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeSeam.holeTangleC once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeSeam.holeTangleT once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeTop.holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeTop.holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHanded> alive holding holeTop.holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeBoth.holeSeamPlain.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeBoth.holeSeamPlain.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeOuter.holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeOuter.holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeOuter.holeSeam.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeOuter.holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeOuter.holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeOuter.holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeTop.holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeTop.holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder alive holding holeTop.holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder> alive holding holeBoth.holeSeamPlain.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder> alive holding holeBoth.holeSeamPlain.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder> alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder> alive holding holeOuter.holeSeam.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder> alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder> alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder> alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder> alive holding holeTop.holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder> alive holding holeTop.holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedHolder> alive holding holeTop.holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeOuter.holeSeam.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeOuter.holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeOuter.holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleHandedImpl alive holding holeTop.holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeBoth.holeSeamPlain.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeBoth.holeSeamPlain.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeBoth.holeSeamPlain.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeRingABuilder once the probe's value is released: 3 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeRingBBuilder once the probe's value is released: 3 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeSecondOwner.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeOuter.holeSeam.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 4 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeNestBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeNestBuilder once the probe's value is released: 3 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeRingABuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeRingABuilder once the probe's value is released: 3 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeRingAValue.holeRingBBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeRingBBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeRingBBuilder once the probe's value is released: 3 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeRingFlow.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeRingFlow.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeTangleC once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeTangleT once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeTangleTValue.holeTangleService.holeTangleC once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleImpl alive holding holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLaterService> alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLaterService> alive holding holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLaterService> alive holding holeOuter.holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLaterService> alive holding holeOuter.holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLaterService> alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLaterService> alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeBothTop.holeBoth.holeSeamPlain.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeBothTop.holeBoth.holeSeamPlain.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeBothTop.holeBoth.holeSeamPlain.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeOuter.holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeOuter.holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeOuter.holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeOuter.holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeOuter.holeSeam.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeSeam.holeRingFlow.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeSeam.holeRingFlow.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeSeam.holeTangleTValue.holeTangleService.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleLogger alive holding holeTop.holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleModel alive holding holeOuter.holeSeam.holeRingABuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleModel alive holding holeOuter.holeSeam.holeRingBBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleModel alive holding holeSeam.holeNestBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleModel alive holding holeSeam.holeRingABuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleModel alive holding holeSeam.holeRingBBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleNamespace.S556_HoleImpl alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleNest alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleNest> alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleNest> alive holding holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleNest> alive holding holeSeam.holeRingAValue.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleNest> alive holding holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleNestImpl alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleNestImpl alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleNestImpl alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleNestScreen> alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleNestWidget alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleNestWidget alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeSeam.holeNestBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeSeam.holeRingABuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeSeam.holeRingAValue.holeRingBBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeSeam.holeRingBBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeSeam.holeTangleC once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeSeam.holeTangleT once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeSeam.holeTangleTValue.holeTangleService.holeTangleC once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleOwner alive holding holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeBothTop.holeBoth.holeSeamPlain.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeBothTop.holeBoth.holeSeamPlain.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeBothTop.holeBoth.holeSeamPlain.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeOuter.holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeOuter.holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeOuter.holeSeam.holeSecondOwner.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeOuter.holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeOuter.holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeOuter.holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeOuter.holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeOuter.holeSeam.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeSeam.holeRingFlow.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeSeam.holeRingFlow.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeSeam.holeTangleTValue.holeTangleService.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeTop.holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeTop.holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeTop.holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleOwner> alive holding holeTop.holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HolePing> alive holding holeBothTop.holeBoth.holeSeamPlain.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HolePing> alive holding holeBothTop.holeBoth.holeSeamPlain.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HolePing> alive holding holeBothTop.holeBoth.holeSeamPlain.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HolePing> alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HolePing> alive holding holeOuter.holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HolePing> alive holding holeOuter.holeSeam.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HolePing> alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HolePing> alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HolePing> alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HolePing> alive holding holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleScreenA alive holding holeOuter.holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleScreenA alive holding holeOuter.holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleScreenA alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleScreenA alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleScreenA alive holding holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleScreenA alive holding holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleScreenB alive holding holeOuter.holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleScreenB alive holding holeOuter.holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleScreenB alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleScreenB alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleScreenB alive holding holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleScreenB alive holding holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleService> alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleService> alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleService> alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleService> alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleService> alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleService> alive holding holeSeam.holeNestBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleService> alive holding holeSeam.holeRingABuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleService> alive holding holeSeam.holeRingAValue.holeRingBBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleService> alive holding holeSeam.holeRingBBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleService> alive holding holeSeam.holeRingFlow.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleService> alive holding holeSeam.holeRingFlow.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleService> alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleService> alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleService> alive holding holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeOuter.holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeOuter.holeSeam.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeSeam.holeRingFlow.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeSeam.holeRingFlow.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeSeam.holeTangleTValue.holeTangleService.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeTop.holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleSettings alive holding holeTop.holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleShared alive holding holeOuter.holeSeam.holeRingABuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleShared alive holding holeOuter.holeSeam.holeRingBBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleShared alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleShared alive holding holeSeam.holeNestBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleShared alive holding holeSeam.holeRingABuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleShared alive holding holeSeam.holeRingBBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleStager> alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleStager> alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleStager> alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleC> alive holding holeOuter.holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleC> alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleC> alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleC> alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleC> alive holding holeSeam.holeTangleTValue.holeTangleService.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleReader alive holding holeOuter.holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleReader alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleReader alive holding holeSeam.holeTangleTValue.holeTangleService.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleT> alive holding holeOuter.holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleT> alive holding holeOuter.holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleT> alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleT> alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleT> alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleT> alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTangleT> alive holding holeSeam.holeTangleTValue.holeTangleService.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeBoth.holeSeamPlain.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeBoth.holeSeamPlain.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeBoth.holeSeamPlain.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeBothTop.holeBoth.holeSeamPlain.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeOuter.holeSeam.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeOuter.holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeOuter.holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeOuter.holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeTop.holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketHolder alive holding holeTop.holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeBoth.holeSeamPlain.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeBoth.holeSeamPlain.holeHandedErased once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeBoth.holeSeamPlain.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeBoth.holeSeamPlain.holeHandedHolder.holeHandedBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeBoth.holeSeamPlain.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeBoth.holeSeamPlain.holeServiceLater once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeBothTop.holeBoth.holeSeamPlain.holeHandedHolder.holeHandedBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeBothTop.holeBoth.holeSeamPlain.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeServiceLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeServiceLater once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeTangleC once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeTangleT once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeOuter.holeSeam.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeSeam.holeNestBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeSeam.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeSeam.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeSeam.holeRingFlow.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeSeam.holeRingFlow.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeTop.holeOuter.holeSeam.holeHandedErased once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTicketService> alive holding holeTop.holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 2 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeOuter.holeSeam.holeHandedErased once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeOuter.holeSeam.holeHandedLater once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeOuter.holeSeam.holeLaterBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeOuter.holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeOuter.holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeOuter.holeSeam.holeTicketHolder.holeTicketOther once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeSeam.holeNest.holeNestScreenBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeSeam.holeRingFlow.holeRingABuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeSeam.holeRingFlow.holeRingBBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeSeam.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeSeam.holeTangleT once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeSeam.holeTangleTValue.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeSeam.holeTangleTValue.holeTangleService.holeTangleC once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeSeam.holeTicketBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeTop.holeOuter.holeSeam.holeHandedHolder.holeHandedBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_HoleTrackerImpl alive holding holeTop.holeOuter.holeSeam.holeNestBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		"_RetainNavigator alive holding retainHome.retainDetailBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
	].map { .seamRetainsWhatInlineFrees(containing: $0) }

	/// The shape of the builder label sort alone, `seamBuilderOrderReason` with the one signature its entries list, when
	/// `knownIssue` lists that reason among those it joins, or `nil`. The order is sanctioned (CLAUDE.md, "What may follow
	/// names"), so the seam smoke batch counts a graph whose renamed graph differs by it as exercising its shapes; no other
	/// reason a known issue lists is handed to `GraphFuzzerResult.passes(butForRetentionDocumentedBy:butForBuilderOrderDocumentedBy:)`.
	static func seamBuilderOrderShape(listedBy knownIssue: GraphFuzzerKnownIssue?) -> GraphFuzzerKnownIssue? {
		guard let knownIssue, knownIssue.reason.components(separatedBy: "; and ").contains(seamBuilderOrderReason) else { return nil }
		return GraphFuzzerKnownIssue(reason: seamBuilderOrderReason, signatures: [.renamedGraphDiffers(.dependencyTreeListOrder)], seeds: knownIssue.seeds)
	}

	private static let seamTraversalLimitReason = "A graph whose probes traverse more wrappers than a graph compared on its own may traverse, so the comparator describes none of its values beneath the point where its traversals run out (Intended: an oracle limit, not a SafeDI defect; raising the comparator's traversal bound for one graph would lengthen every graph's comparison)"

	/// The remedy oracle's finding in the label-forms and alias draws of seams split across modules: an error at a receive
	/// no declaration fulfills suggests every form of the label the chain declares, the first of which a closer declaration
	/// of the label with another type hides (seed 1034: `FormsHost` declares `formsUser: FormsUser?` above `FormsSummary`,
	/// whose `formsUser: LazilyInstantiated<FormsUser>` the error offers `formsUser: FormsUser` first).
	private static let seamMockBuilderOrderReason = "A seam's own mock takes a builder for each hole its tree cannot fill, labeled after the hole type's name and sorted among its parameters by label, so moving type names across wrapper names reorders the mock's parameters"

	private static let seamBuilderOrderReason = "A seam's builders are ordered by label, which its hole type's names spell, so moving type names across wrapper names reorders the builders of a seam with two hole types, its generated initializers and the calls of them (Intended: CLAUDE.md's \"What may follow names\" allows a label sort of equivalent parameters, so the rename oracle's reordering here is expected, not a defect)"

	private static let labelSortedPassThroughReason = "A seam's pass-through parameters are sorted by label, so reversing the labels reorders its generated initializer and the calls of it (Intended: CLAUDE.md's \"What may follow names\" allows a label sort of equivalent parameters, so the rename oracle's reordering here is expected, not a defect)"

	private static let labelSortedPassThroughAndMockParametersReason = "\(labelSortedPassThroughReason), and a mock's parameters and fields are sorted by label, so reversing the labels reorders them too"

	/// Seeds of `knownIssues` that the seam corpus's run observed failing with the seam's own shape, or not failing
	/// at all, since the seam's draw changed their graphs, or the base corpus's mock vocabulary draw, which the seam
	/// corpus does not draw, changed them there (154, 527, 657); the inherited lists leave them out. Observed, not
	/// derived: a seed here that a run finds failing its inherited shape again is a new failure, and goes back. Seeds
	/// 281, 300, 383, 548, 567, 595, 742, 749, 751, 836, 886, 940, 948, 1139, 1145, 1149, 1163, 1300, 1301, 1352, 1464,
	/// 1524, 1561, 1563 and 1804 fail it beside the builder order, 51, 772, 1567, 1742 and 1816 beside the label-sorted
	/// pass-throughs, 21 and 848 beside both a builder order and the lazy cycle's configuration field, and 1959 beside
	/// that field, and are listed with them; 107, 1051 and 1504 fail the remedy oracle's seam shape instead; 593, 617
	/// and the other seeds from 1000 no longer fail it. The remedy oracle's `@Sendable` builder shape fails 167 in the
	/// base corpus only. Seed 1329 failed the remedy oracle's seam fill shape that forwards a value into a lazy wrapper's type
	/// instead, which the fill error's advice to declare that wrapper as an instantiator fixed. The hole draw's value outside a `@Sendable` function lands
	/// in 338, 1042, 1072 and 1492, which the tool rejects, 338 and 1072 with that draw's error: 338 failed its inherited
	/// shape before the draw, and 1042, 1072 and 1492 failed theirs no longer.
	private static let seamCorpusSeedsOfOtherShapes: Set<UInt64> = [
		7, 14, 21, 27, 35, 45, 51, 107, 114, 116, 157, 167, 204, 264, 265, 272, 281, 300, 309, 323, 338, 342, 364,
		371, 381, 383, 431, 434, 455, 461, 476, 508, 525, 527, 545, 548, 567, 577, 593, 595, 617, 624, 628, 632, 634,
		657, 695, 714, 728, 735, 742, 749, 751, 768, 772, 774, 786, 801, 808, 836, 840, 847, 848, 886, 903, 912, 940,
		948, 953, 993, 1_024, 1_029, 1_035, 1_042, 1_044, 1_051, 1_061, 1_072, 1_073, 1_081, 1_084, 1_092, 1_139, 1_145, 1_147,
		1_149, 1_163, 1_300, 1_301, 1_322, 1_329, 1_335, 1_352, 1_362, 1_366, 1_369, 1_372, 1_432, 1_433, 1_434, 1_436,
		1_447, 1_464, 1_483, 1_492, 1_504, 1_521, 1_524, 1_525, 1_531, 1_559, 1_561, 1_563, 1_567, 1_572, 1_580, 1_602,
		1_633, 1_646, 1_659, 1_664, 1_724, 1_742, 1_758, 1_784, 1_804, 1_805, 1_816, 1_832, 1_857, 1_864, 1_867, 1_896,
		1_898, 1_935, 1_959, 1_970,
	]

	/// Seeds that `knownIssues` does not list under an inherited shape, whose graphs the seam's draw changes so that
	/// they fail it, by the shape's reason. Observed, not derived, as `seamCorpusSeedsOfOtherShapes` is.
	private static let seamCorpusSeedsAddedToInheritedShapes: [String: [UInt64]] = [
		lazyCycleConfigurationFieldReason: [135, 1_049, 1_215, 1_289, 1_293],
	]

	/// Seeds whose seam has two or more pass-throughs. They are sorted by label – kept by ruling: a parameter order
	/// that follows label order is how mocks and initializers already work – so the oracle's label reversal
	/// reorders them, which is expected, not a defect, as the mock's label-sorted parameters are in `knownIssues`.
	private static let labelSortedPassThroughSeeds: [UInt64] = [604, 816, 928, 1_159]

	/// Seeds of the same shape whose generated mock also lists label-sorted parameters, so that it changes too.
	private static let labelSortedPassThroughSeedsWhoseMockParametersAlsoChange: [UInt64] = [51, 371, 381, 1_742, 1_816]

	/// The corpus drawn with `features`: the base corpus when there are none, and a feature's corpus for that
	/// feature. Every feature has a corpus, so the two are the only ones.
	static func corpus(for features: Set<GraphFuzzerGeneratorFeature>) -> Corpus {
		if features.contains(.generateMockPublic) {
			publicMockCorpus
		} else if features.contains(.generateDependencyTree) {
			seamCorpus
		} else {
			baseCorpus
		}
	}

	/// The corpus drawn with the `generateMockPublic` feature: seeds `0..<publicMockCorpusSeedCount`, each a graph of its
	/// own (`GraphFuzzerPublicMockDraw`) with types declared `generateMock: .public` and the consumers that reach them.
	static let publicMockCorpus = Corpus(
		name: GraphFuzzerGeneratorFeature.generateMockPublic.rawValue,
		features: [.generateMockPublic],
		seedCount: publicMockCorpusSeedCount,
		fixtureHash: publicMockCorpusFixtureHash,
		acceptedSeedCount: publicMockCorpusAcceptedSeedCount,
		acceptedSeedsSum: publicMockCorpusAcceptedSeedsSum,
		knownIssues: publicMockKnownIssues,
		knownIssuesName: "publicMockKnownIssues",
		staleSeedRemedy: { _, _ in "remove it from `publicMockKnownIssues`" },
		valueOracleInspectedGraphCount: publicMockCorpusValueOracleInspectedGraphCount,
		spellingDrawFeatures: [],
		omittedValueGraphCount: publicMockCorpusOmittedValueGraphCount,
		outputFeatureMinimumShares: publicMockCorpusOutputFeatureMinimumShares,
		errorMarkers: GraphFuzzerOracle.publicMockOnlyErrorMarkers + [GraphFuzzerOracle.publicMockStaleValueErrorMarker, GraphFuzzerOracle.publicMockSendableFunctionCarryErrorMarker],
		errorGraphCounts: publicMockCorpusErrorGraphCounts,
		publicMockDrawFeaturesCountedWhenAccepted: Set(GraphFuzzerPublicMockDrawFeature.allCases.filter(\.isCountedWhenAccepted)),
		acceptedPublicMockDrawFeatureCounts: publicMockCorpusAcceptedDrawFeatureCounts,
		readTwinGraphCount: publicMockCorpusReadTwinGraphCount,
		retentionCounts: publicMockCorpusRetentionCounts,
		levelFunctionCaptureCounts: publicMockCorpusLevelFunctionCaptureCounts,
		gatingPublicMockDrawFeatures: Set(GraphFuzzerPublicMockDrawFeature.allCases.filter(\.isCountedWhenAccepted)),
		builderSurfaceFlooredKinds: [
			"base-plain",
			"base-lazy",
			"base-forwarding",
			"base-sendable",
			"placeBehindLazilyInstantiated",
			"instantiatorPlaceMovedToPlainPlace",
			"plainPlaceMovedToInstantiator",
			"instantiatorChangedToErasedInstantiator",
			"erasedInstantiatorChangedToInstantiator",
			"sendableInstantiatorPlaceMovedToPlainPlace",
			"plainPlaceMovedToSendableInstantiator",
			"sendableInstantiatorChangedToSendableErasedInstantiator",
			"sendableErasedInstantiatorChangedToSendableInstantiator",
			"placeOfNewBuilderOfExistingFillingType",
			"placeForwardingOtherValues",
			"placeForwardingOtherValuesRemedied",
			"lazilyInstantiatedPlaceMovedBack",
			"secondCallOfPublicMock",
			"remedyKeepsDrawnBuilders",
		],
	)

	/// How many of the public mock corpus's accepted graphs show each gating draw (`isCountedWhenAccepted`), counted
	/// whether or not the graph fails: at least ten each (`acceptedDrawFeatureCounts_holdAtLeastTenGraphs_forEachGatingDraw`). Pins:
	/// derived on CI.
	static let publicMockCorpusAcceptedDrawFeatureCounts: [GraphFuzzerPublicMockDrawFeature: Int] = [
		.placeInsidePublicMockFill: 316,
		.placeInsidePublicMockFillFilledByConsumer: 228,
		.placeInsidePublicMockFillHoldsLoopOfBuilders: 109,
		.placeInsidePublicMockFillOnForwardingRoute: 128,
		.placeInsidePublicMockFillPassedUp: 88,
		.placeInsidePublicMockFillReadsForwardedValue: 63,
		.placeInsidePublicMockFillReadsOuterValue: 70,
		.retentionPublicMockValueBeforeBuilder: 131,
		.retentionPublicMockValueBeforeBuilderFillReadsValue: 39,
		.retentionPublicMockValueBeforeBuilderLeafThroughInstantiator: 65,
		.selfBuildingPublicMock: 344,
		.selfBuildingPublicMockFillReadsToken: 77,
		.selfBuildingPublicMockPassedUp: 78,
		.selfBuildingPublicMockPlaceBeneath: 115,
		.selfBuildingPublicMockReceivesBuilder: 177,
		.selfBuildingPublicMockThroughSendableInstantiator: 29,
		.selfBuildingPublicMockThroughStep: 91,
		.sharedConstructionPublicMock: 244,
		.sharedConstructionPublicMockBeneathCycleEdge: 56,
		.sharedConstructionPublicMockBesideDeclaringModulesOwn: 55,
		.sharedConstructionPublicMockErased: 104,
		.sharedConstructionPublicMockExtensionBased: 99,
		.sharedConstructionPublicMockInDeclaringModule: 68,
		.keywordLabeledPublicMock: 238,
		.keywordLabeledPublicMockBesideInternalConfiguration: 107,
		.sharedConstructionPublicMockOneHolder: 47,
		.sharedConstructionPublicMockWithoutMockFirst: 96,
		.holeHandWrittenMockBuiltInPublicMock: 87,
		.holeMockIsolatedToMainActor: 77,
		.overrideClosureCall: 311,
		.overrideClosureCallCanHand: 184,
		.overrideClosureCallFillReadsCalledMocksOtherPlace: 39,
		.overrideClosureCallFillReadsCalledMocksParameter: 39,
		.overrideClosureCallFillReadsConsumersValue: 28,
		.overrideClosureCallFillReadsValueCalledMockRenames: 38,
		.overrideClosureCallInternalCallerPassesPlaceUp: 72,
		.overrideClosureCallPlaceIsErasedInstantiator: 90,
		.overrideClosureCallPublicCallerPassesPlaceUp: 67,
		.carrierBeforeSibling: 127,
		.carrierBeforeSiblingBetweenSiblings: 52,
		.carrierBeforeSiblingThroughSameModuleSeam: 64,
		.carrierBeforeSiblingBeneathConfiguredChild: 59,
		.wrapperReadByValuePublicMock: 235,
		.wrapperReadByValuePublicMockMockedTypeReadsValue: 73,
		.wrapperReadByValuePublicMockMockedTypeReadsValueOnlyIfAvailable: 66,
		.wrapperReadByValuePublicMockReaderThroughInstantiator: 119,
		.wrapperReadByValuePublicMockSendably: 43,
		.wrapperReadByValuePublicMockTreeReadsValue: 96,
		.ownOptionalDefaultOnNonisolatedTypeThatBuilds: 503,
		.promotedHolePublicMock: 87,
		.promotedHolePublicMockLazily: 75,
		.promotedHolePublicMockPassedUp: 17,
		.promotedHolePublicMockPublicConsumer: 40,
		.promotedHolePublicMockSendableLazily: 12,
		.optionalPlacePublicMock: 165,
		.optionalPlacePublicMockOnLeaf: 73,
		.optionalPlacePublicMockSendably: 27,
		.optionalPlacePublicMockReceived: 84,
		.optionalPlacePublicMockPassedUp: 67,
		.optionalPlacePublicMockPublicConsumer: 45,
		.outerFulfillerPublicMockCall: 112,
		.unbuildableValuePublicMockCall: 174,
		.unbuildableValuePublicMockCallPublicTier: 174,
		.carrierBeforeSiblingBeneathInternallyConfiguredChild: 26,
		.valueFormsBesidePublicMockCall: 257,
		.valueFormsBesidePublicMockCallBeneathCycleEdge: 49,
		.valueFormsBesidePublicMockCallCalledTakesOptional: 88,
		.valueFormsBesidePublicMockCallCalledTreeReceivesValue: 90,
		.valueFormsBesidePublicMockCallConsumerReceivesValue: 106,
		.valueFormsBesidePublicMockCallEmptyPublicMock: 108,
		.valueFormsBesidePublicMockCallLabelOfAnotherType: 98,
		.valueFormsBesidePublicMockCallPublicConsumer: 86,
		.valueFormsBesidePublicMockCallPublicOptionalWrapperBesideOtherType: 42,
		.valueFormsBesidePublicMockCallRenamed: 63,
		.valueFormsBesidePublicMockCallTwoWrapperForms: 19,
		.valueFormsBesidePublicMockCallUnbuildableValue: 119,
	]

	/// The least share of the public mock corpus's accepted graphs, whether or not they fail, whose generated code shows
	/// each output feature, in percent: the floor of the share the corpus run observed, for each feature the generated code
	/// shows today. The commits that make another feature show pin it in turn.
	static let publicMockCorpusOutputFeatureMinimumShares: [GraphFuzzerPublicMockOutputFeature: Int] = [
		.allNonPublicConfiguration: 41,
		.configurationStruct: 34,
		.constructionFunction: 84,
		.consumerCall: 82,
		.consumerCallsTieredMockWithoutBuilderStruct: 43,
		.consumerErasedCall: 19,
		.consumerErasedInline: 3,
		.consumerFillReentersPublicMock: 2,
		.consumerFillsHole: 3,
		.consumerInline: 37,
		.consumerPassesHoleBuilderUp: 14,
		.consumerPassesLevelFunctionsStruct: 64,
		.consumerSendableFactory: 17,
		.defaultRewritten: 88,
		.forwardedProvider: 3,
		.generatedOnlyMockFunction: 88,
		.generatedOnlyMockFunctionBesideConstructionFunction: 7,
		.holeBuilder: 39,
		.holeLoopBuilder: 11,
		.holeLoopBuilderOfBuilderStruct: 9,
		.isolatedConstruction: 3,
		.isolatedGeneratedOnlyMockFunction: 9,
		.moduleConfiguration: 84,
		.publicMockTakesWrapper: 80,
		.publicTier: 100,
		.secondTier: 60,
		.sendableHoleBuilder: 2,
		.thirdTier: 0,
		.unreadTypeComment: 27,
	]

	static let publicMockCorpusSeedCount = 1_000
	static let publicMockCorpusFixtureHash: UInt64 = 0xBBFB2E79AE7331A2
	static let publicMockCorpusAcceptedSeedCount = 854
	static let publicMockCorpusAcceptedSeedsSum: UInt64 = 0xA0030516C7DF62F
	/// How many of the public mock corpus's graphs the tool accepts as drawn and as their known-right path, which the
	/// value oracle compares.
	static let publicMockCorpusValueOracleInspectedGraphCount = 854
	/// How many of the public mock corpus's graphs the tool rejects because a caller provides a value the tier of the public
	/// mock it calls omits (`leafTierOmitsProvidedValue`), which the long run counts as it counts the seam's: the graphs of
	/// `GraphFuzzerPublicMockDrawFeature.unbuildableValuePublicMockCallTierOmits`, a value of a type whose spelling SafeDI
	/// cannot read that the consumer's `mock()` is passed because it cannot build it. No holder of `Dock` is one, since SafeDI
	/// reads `Dock`'s declaration inside a platform-conditioned block. Pins: derived on CI.
	static let publicMockCorpusOmittedValueGraphCount = 6
	/// How many of the public mock corpus's graphs name a type no declaration SafeDI reads declares, which the oracle
	/// compares with their read twin.
	static let publicMockCorpusReadTwinGraphCount = 260
	/// How many of the public mock corpus's graphs the tool rejects with each of a public mock's own errors, in the order
	/// of `GraphFuzzerOracle.publicMockOnlyErrorMarkers`: the public tier or a hole bound apart from its label (the graphs of
	/// `holeLabelReceivedByPromotedSibling`), a narrower enclosing type, a leaf tier (the graphs
	/// of `unbuildableValuePublicMockCallTierOmits`) and a nested leaf tier omitting a provided value, the mock condition, the
	/// by-name check, and the view that cannot call;
	/// then the fill that reads a value the loop around `T6`'s hole declares again
	/// (`GraphFuzzerOracle.publicMockStaleValueErrorMarker`), which rejects seeds 50, 85, 450, 555, 609, 688 and 967; and the
	/// fill, in a module that calls `T6`'s public mock, that reads the `holeContext` `T6` declares outside the `@Sendable`
	/// function above its hole (`GraphFuzzerOracle.publicMockSendableFunctionCarryErrorMarker`), which rejects seed 157.
	static let publicMockCorpusErrorGraphCounts = [
		49, 0, 6, 0, 37, 0, 0, 7, 1,
	]

	/// The ordinary suite's batch of the public mock corpus: graphs the tool accepts – a consumer in the same package
	/// calling a public mock with the `analytics` wrapper it holds, which the mock takes as that wrapper, of a `@MainActor`
	/// type whose public tier passes its own provider-defaulted parameter on (seed 0); a consumer in the same package only
	/// (seed 43); a `Sendable` wrapper above the leaf, a construction function isolated as the initializer
	/// it calls, and a leaf reached through an `ErasedInstantiator` (seed 46); both consumer modules, a differing mock
	/// condition and a configuration whose members are all narrower than `public` (seed 142); two leaves that each build
	/// the `session` their caller cannot name, M8.9b's, a leaf reached through an erased constant, and a hole's builder
	/// passed up (seed 151); a consumer in another package filling a hole whose fill builds the `.public` type again
	/// through an `Instantiator`, a fully lazy cycle (seed 197); a `@Sendable` builder for a hole beneath a `Sendable` wrapper
	/// (seed 59; seed 211, which showed it first, now draws `T6Twin` and is a known issue); a consumer in another package only and a differing mock condition (seed 253); a configuration's
	/// module-level forwarder of a default's provider, and a hole's builder passed up into a `@Sendable` builder function
	/// (seed 551); a third tier (seed 215); the comment naming a type SafeDI reads no declaration of (seed 10) – a graph the
	/// public tier rejects (seed 7), a graph whose configurations a renaming only reorders (seed 23), and a graph
	/// whose fill reads the `holeContext` the loop around `T6`'s hole declares again, which the mock rejects as a seam does
	/// and, without that check, fills with `T6`'s at every level (seed 555), and a graph whose fill reads `T6`'s
	/// `holeContext` under that loop, which the loop does not declare again (seed 836); declarations moved
	/// beneath the declaring module (seed 98) and a chain of public mocks through the three modules beneath it (seed 208),
	/// which a consumer computes from the declaring module's view (`GraphFuzzerSeamDependencyDraw`); and a type built with
	/// its hand-written mock inside another public mock of its module, whose extensions declare the function only generated
	/// code calls beside the construction function of that name (seed 37); and a graph that puts a place beneath a
	/// dependency the public mock promotes, which did not compile before a public mock kept such a place: `SelfPart`
	/// receiving `SelfNode`'s `SendableInstantiator` beside the place, whose construction function forwarded a flat
	/// `@autoclosure` parameter (seed 189, the adopter's own shape). Between them its passing graphs show every output feature `publicMockCorpusOutputFeatureMinimumShares` pins,
	/// which `publicMockSmokeSeeds_exercisePublicMockFeature_inGraphsTheToolAccepts` checks. Beyond the corpus, seeds
	/// 1339, 1649, 2687 and 2840 build a type whose public mock names `customMockName` erased to a concrete existential in
	/// another module's public mock, whose shared construction function returned the eraser and did not compile
	/// (`SafeDIToolPublicMockCustomMockConstructionTests`); no corpus graph showed it, and they pass with no known issue
	/// once every public mock builder takes a builder struct. Seeds 10, 551 and 836 also draw a type the public mocks of one module build two
	/// ways (`drawSharedConstructionPublicMock`), 836 with the hand-written mock only beneath a cycle edge, whose generated
	/// code did not compile before each construction had a function of its own
	/// (`SafeDIToolPublicMockSharedConstructionTests`); seed 555 draws it in the graph the tool rejects.
	/// Pinned by `publicMockSmokeAndKnownIssueFixtureHash`.
	static let publicMockSmokeSeeds: [UInt64] = [0, 7, 10, 23, 37, 43, 46, 59, 98, 142, 151, 189, 197, 208, 215, 253, 551, 555, 836, 1_339, 1_649, 2_687, 2_840]

	static let publicMockSmokeAndKnownIssueFixtureHash: UInt64 = 0x69CB45E5EEDAF5F7

	/// Seeds in `0..<publicMockCorpusSeedCount` whose graphs fail today, by shape. Every seed is the feature's own: the
	/// draw shares no graph with the base corpus.
	static let publicMockKnownIssuesBesideBuilderSurface: [GraphFuzzerKnownIssue] = [
		GraphFuzzerKnownIssue(
			reason: publicMockParametersSortedByLabelReason,
			signatures: [.renamedGraphDiffers(.mockParameterAndFieldOrder)],
			seeds: [103, 106, 167, 251, 351, 514, 528, 562, 771, 836, 947],
		),
		// The base corpus's shape, in a consumer that builds a `.public` type's tree inline with a fill that closes a lazy
		// cycle through it, in the gating draw of the shape #702 fixed, a `.public` type that builds itself again through
		// `SelfStep`, whose two names the move across wrapper names now and then puts on either side of `Instantiator`, and in
		// the stale-value draw's loop around `T6`'s hole (`HoleHost` and `HoleLoop`), and in the shared-construction draw's
		// cycle through `ShareService` and `ShareTicker`.
		GraphFuzzerKnownIssue(
			reason: lazyCycleConfigurationFieldReason,
			signatures: [.renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [
				3, 99, 104, 112, 194, 213, 265, 289, 301, 302, 542, 561, 566, 572, 574, 583, 598, 612, 616, 649, 653,
				677, 697, 825, 832, 833, 884, 907, 909, 944, 946,
			],
		),
		// A shape the corpus first compiled once SafeDI proved a type's access from its plain declaration (2026-11-03):
		// before, a consumer held a holder the public tier omitted, which the tool rejected; now `Dock`'s own declaration
		// proves the holder `public`, or, `package`, leaves a consumer in another package holding none.
		GraphFuzzerKnownIssue(
			reason: "Two public mocks a consumer in another package calls each build their own instance of a dependency it cannot name (M8.9b), first built in a leaf's child, which the stated divergence's exemption does not derive (Intended: an oracle limit on a divergence the public mock contract states; one seed)",
			signatures: [.publicMockBuildsOtherValuesThanKnownRight(containing: "t1 > t4 > session")],
			seeds: [95],
		),
		// The nested builders' design, as a seam orders its builders: a mock's parameters are sorted by label, and a builder's
		// label begins with its hole type's name, which the move across wrapper names moves among the other labels.
		GraphFuzzerKnownIssue(
			reason: publicMockBuilderOrderReason,
			signatures: [.renamedGraphDiffers(.mockCode)],
			seeds: [176, 455, 685],
		),
		// As above, with the optional builder of a hole type a calling mock's calls fill, which is listed among the flat
		// parameters by label as a required builder is; and a lazy cycle's configuration field.
		GraphFuzzerKnownIssue(
			reason: "\(publicMockBuilderOrderReason); and \(lazyCycleConfigurationFieldReason)",
			signatures: [.renamedGraphDiffers(.mockCode), .renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [897],
		),
		// The design's output stability: an internal consumer that passes up the places of two public mocks of one hole
		// type names the builders it takes for them apart, after each called type, so `T6Twin`'s call renames `T6`'s.
		GraphFuzzerKnownIssue(
			reason: passedUpBuildersNamedApartReason,
			signatures: [.holeNamesChangeWithSecondPlace(containing: "`t6Twin`")],
			seeds: [406],
		),
		GraphFuzzerKnownIssue(
			reason: "\(passedUpBuildersNamedApartReason); and \(publicMockBuilderOrderReason)",
			signatures: [.holeNamesChangeWithSecondPlace(containing: "`t6Twin`"), .renamedGraphDiffers(.mockCode)],
			seeds: [19, 299, 456, 510],
		),
		// The root-level stream's label in two forms (`holeRootReceivesLabelInTwoForms`), in `T6`'s mock and in a consumer's
		// call of it: a public mock's required parameters keep their places in the comparison, which sorts only the
		// optional ones (`GraphFuzzerMockDifference`).
		GraphFuzzerKnownIssue(
			reason: publicMockFormsNamedApartOrderReason,
			signatures: [.renamedGraphDiffers(.mockCode)],
			seeds: [18, 22, 156, 242, 326, 327, 474, 629, 731, 821, 881, 983],
		),
		// The root-level stream's label in two forms in a graph with a lazy cycle whose back-edge the move across wrapper
		// names moves: `SelfStep`'s, or the stale-value draw's loop around `T6`'s hole (`HoleHost` and `HoleLoop`).
		GraphFuzzerKnownIssue(
			reason: "\(lazyCycleConfigurationFieldReason); and \(publicMockFormsNamedApartOrderReason)",
			signatures: [.renamedGraphDiffers(.mockConfigurationFieldPresence), .renamedGraphDiffers(.mockCode)],
			seeds: [47, 221, 381, 452, 880, 886],
		),
		GraphFuzzerKnownIssue(
			reason: "\(publicMockParametersSortedByLabelReason); and \(lazyCycleConfigurationFieldReason)",
			signatures: [.renamedGraphDiffers(.mockParameterAndFieldOrder), .renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [12, 65, 407],
		),
		GraphFuzzerKnownIssue(
			reason: "\(passedUpBuildersNamedApartReason); and \(lazyCycleConfigurationFieldReason)",
			signatures: [.holeNamesChangeWithSecondPlace(containing: "`t6Twin`"), .renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [211, 307],
		),
		GraphFuzzerKnownIssue(
			reason: "\(passedUpBuildersNamedApartReason); and \(publicMockBuilderOrderReason); and \(lazyCycleConfigurationFieldReason)",
			signatures: [.holeNamesChangeWithSecondPlace(containing: "`t6Twin`"), .renamedGraphDiffers(.mockCode), .renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [597],
		),
		// Where `mockConditionalCompilation: nil` puts a mock in its type's dependency tree file, a change to it changes that file too.
		GraphFuzzerKnownIssue(
			reason: "\(publicMockFormsNamedApartOrderReason); and \(lazyCycleConfigurationFieldReason)",
			signatures: [.renamedGraphDiffers(.dependencyTreeCode), .renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [137],
		),
		GraphFuzzerKnownIssue(
			reason: "\(publicMockFormsNamedApartOrderReason); and a public mock's parameters are sorted by label (`Property.precedesInMockOrder`), so reversing the labels reorders a `.public` consumer's `mock()`; and \(lazyCycleConfigurationFieldReason); and \(calledPublicMockArgumentOrderReason)",
			signatures: [.renamedGraphDiffers(.dependencyTreeCode), .renamedGraphDiffers(.mockConfigurationFieldPresence), .renamedGraphDiffers(.mockCode)],
			seeds: [708],
		),
		GraphFuzzerKnownIssue(
			reason: "\(publicMockParametersSortedByLabelReason); and \(calledPublicMockArgumentOrderReason)",
			signatures: [.renamedGraphDiffers(.mockCode)],
			seeds: [433],
		),
		// The lazy cycle around `T6`'s hole that the stale-value draw adds (`HoleHost` and `HoleLoop`), whose back-edge's override the move across wrapper names moves, in `T6`'s mock in its dependency tree file.
		GraphFuzzerKnownIssue(
			reason: "\(lazyCycleConfigurationFieldReason), in a mock that `mockConditionalCompilation: nil` puts in its type's dependency tree file",
			signatures: [.renamedGraphDiffers(.mockConfigurationFieldPresence), .renamedGraphDiffers(.dependencyTreeCode)],
			seeds: [281, 863],
		),
		GraphFuzzerKnownIssue(
			reason: "\(passedUpBuildersNamedApartReason); and \(lazyCycleConfigurationFieldReason), in a mock that `mockConditionalCompilation: nil` puts in its type's dependency tree file",
			signatures: [.holeNamesChangeWithSecondPlace(containing: "`t6Twin`"), .renamedGraphDiffers(.mockConfigurationFieldPresence), .renamedGraphDiffers(.dependencyTreeCode)],
			seeds: [658],
		),
	]

	/// `publicMockKnownIssuesBesideBuilderSurface` with each part of the builder surface added for its seeds.
	static let publicMockKnownIssues = addingBuilderSurfaceShapes(seeds: publicMockBuilderSurfaceSeeds, to: publicMockKnownIssuesBesideBuilderSurface)

	/// The public mock corpus's graphs that fail each part of the builder surface today, observed from a run of the tool over
	/// the corpus (`GraphFuzzerBuilderSurface`), each part's seeds apart: the base check (every graph with a hole the tool
	/// accepts), the label check, same supply (i), added supply (ii), places forwarding other values (iii) and calling
	/// mocks (iv). The planned builder structs empty them, each slice the seeds it fixes, but for same supply's, a shape
	/// that stays for 2.x (`callingMockTakesHoleValueReason`).
	static let publicMockBuilderSurfaceSeeds = BuilderSurfaceSeeds(
		base: [],
		labels: [],
		sameSupply: [
			79, 122, 128, 136, 145, 230, 266, 332, 352, 411, 420, 427, 539, 580, 658, 681, 740, 786, 814, 823, 827, 853,
		],
		sameSupplyReason: callingMockTakesHoleValueReason,
		sameSupplyBuilderKindFlips: [406, 463],
		sameSupplyBuilderKindFlipsReason: publicMockBuilderFormFlipReason,
		remedyBuilderKindFlips: [],
		addedSupply: [],
		forwardingOtherValues: [],
		callingMocks: [230, 406],
	)

	/// `publicMockKnownIssues`, with the smoke seeds beyond the public mock corpus that fail the builder surface or show a
	/// public mock's leak, which the corpus's list, bounded by its size, cannot hold: none today.
	static let publicMockSmokeKnownIssues = addingBuilderSurfaceShapes(
		seeds: BuilderSurfaceSeeds(
			base: [],
			labels: [],
			sameSupply: [],
			sameSupplyReason: callingMockTakesHoleValueReason,
			sameSupplyBuilderKindFlips: [],
			remedyBuilderKindFlips: [],
			addedSupply: [],
			forwardingOtherValues: [],
			callingMocks: [],
		),
		to: publicMockKnownIssues,
	)

	private static let publicMockParametersSortedByLabelReason = "A public mock's parameters are sorted by label (decision 27), so reversing the labels reorders a `.public` consumer's `mock()` and the parameters it surfaces from its leaves (Intended: CLAUDE.md's \"What may follow names\" allows a label sort of equivalent parameters, so the rename oracle's reordering here is expected, not a defect)"

	private static let calledPublicMockArgumentOrderReason = "a `__safeDI_mock` call's arguments are a label-sorted list the comparator doesn't yet move, so where a consumer calls another module's public mock to honor its builders, the same reorderings read as a change of the mock's code, and the guard enum names that hash the called mock's signature change with it (Intended: an oracle limit; a later pull request teaches the comparator and deletes this)"

	private static let publicMockBuilderOrderReason = "A mock's parameters are sorted by label, and a builder's label begins with its hole type's name, so moving type names across wrapper names moves a consumer's builder among its other parameters (Intended: CLAUDE.md's \"What may follow names\" allows a label sort of equivalent parameters, so the rename oracle's reordering here is expected, not a defect)"

	private static let publicMockFormsNamedApartOrderReason = "A mock names the forms of a label its tree receives in two apart, after their types, and orders them by `Property.precedesInMockOrder` (label, kind, then type), so moving type names across wrapper names reorders a public mock's required parameters (Intended: CLAUDE.md's \"What may follow names\" allows a label sort of equivalent parameters, so the rename oracle's reordering here is expected, not a defect)"

	private static let passedUpBuildersNamedApartReason = "An internal consumer that passes up the places of two public mocks of one hole type names the builders it takes for them apart after each called type, so adding the second call renames the first's builder (Intended: CLAUDE.md's \"What may follow names\" allows a label sort of equivalent parameters, so the rename oracle's reordering here is expected, not a defect)"

	/// How many of the public mock corpus's graphs each shape of `GraphFuzzerPublicMockDraw` lands in, exactly, so a draw
	/// that stops landing, or a change in a shape's share, fails
	/// `publicMockCorpus_drawsEachShapeInThePinnedNumberOfGraphs_whenFixturesAreGeneratedWithoutTheTool`.
	static let publicMockCorpusDrawFeatureCounts: [GraphFuzzerPublicMockDrawFeature: Int] = [
		.allNonPublicConfiguration: 307,
		.allowlistedParameterType: 138,
		.bothConsumerModules: 393,
		.childDefaultNamingOwnStaticMember: 452,
		.closureDefault: 225,
		.consumerHoldsLazilyInstantiatedWrapper: 266,
		.consumerHoldsOmittedValue: 188,
		.consumerInstantiatesLeaf: 671,
		.consumerReachesHoleTypeThroughTwoPublicMocks: 57,
		.consumerReachesHoleTypeUnderTwoLabels: 87,
		.consumerReachesHoleTypeWithFill: 155,
		.consumerReachesHoleTypeWithoutFill: 166,
		.consumerReceivesLazilyInstantiatedWrapper: 133,
		.consumerReceivesLeaf: 537,
		.customMockName: 369,
		.declaringModuleConfigurationFile: 30,
		.erasedConstantLeaf: 119,
		.erasedInstantiatorLeaf: 116,
		.extensionBasedInstantiable: 212,
		.fakeExtensionPackage: 165,
		.fakeMockDefaultedParameter: 344,
		.fakeMockDependencyBoundParameter: 221,
		.fakeTypeInternal: 344,
		.holderlessOmittedValue: 57,
		.holeBeneathInstantiator: 35,
		.holeBeneathLazilyInstantiated: 47,
		.holeBeneathSendableWrapper: 12,
		.holeCallerInOtherPackage: 278,
		.holeCallerInSamePackage: 120,
		.holeDeclaredAsErasedConstant: 77,
		.holeDeclaredAsErasedInstantiator: 73,
		.holeDeclaredAsExistential: 86,
		.holeDeclaredAsInstantiator: 34,
		.holeFakeAlone: 7,
		.holeFakeBesideFill: 12,
		.holeHandWrittenMockBuiltInPublicMock: 113,
		.holeHandWrittenMockTakesNoOverrides: 29,
		.holeHostReceivedByValue: 17,
		.holeHostReceivedThroughInstantiator: 38,
		.holeHostReceivedThroughSendableInstantiator: 21,
		.holeFillClosesLazyCycle: 15,
		.holeFillReadsContextBoundOutsideSendableFunction: 1,
		.holeFillReceivesField: 56,
		.holeFillReceivesNonField: 40,
		.holeFillReceivesFormBoundAgain: 25,
		.holeFillReceivesRootLevelValue: 38,
		.holeFillReceivesRootLevelWrapper: 15,
		.holeForwardsValue: 43,
		.holeInsideLoop: 131,
		.holeLoopDeclaresContextAgain: 74,
		.holeMockIsolatedToMainActor: 93,
		.holeOnPublicMockType: 228,
		.holeRootLevelHoldsValues: 111,
		.holeRootLevelHoldsWrapper: 91,
		.holeRootReceivesLabelInTwoForms: 92,
		.holeScopeHoldsPackageValue: 103,
		.holeScopeHoldsPublicValue: 225,
		.placeInsidePublicMockFill: 355,
		.placeInsidePublicMockFillFilledByConsumer: 261,
		.placeInsidePublicMockFillHoldsLoopOfBuilders: 125,
		.placeInsidePublicMockFillOnForwardingRoute: 148,
		.placeInsidePublicMockFillPassedUp: 94,
		.placeInsidePublicMockFillReadsForwardedValue: 70,
		.placeInsidePublicMockFillReadsOuterValue: 76,
		.selfBuildingPublicMock: 383,
		.selfBuildingPublicMockFillReadsToken: 84,
		.selfBuildingPublicMockPassedUp: 82,
		.selfBuildingPublicMockPlaceBeneath: 127,
		.selfBuildingPublicMockReceivesBuilder: 200,
		.selfBuildingPublicMockThroughSendableInstantiator: 35,
		.selfBuildingPublicMockThroughStep: 103,
		.retentionPublicMockValueBeforeBuilder: 144,
		.retentionPublicMockValueBeforeBuilderFillReadsValue: 41,
		.retentionPublicMockValueBeforeBuilderLeafThroughInstantiator: 70,
		.sharedConstructionPublicMock: 270,
		.sharedConstructionPublicMockBeneathCycleEdge: 60,
		.sharedConstructionPublicMockBesideDeclaringModulesOwn: 61,
		.sharedConstructionPublicMockErased: 113,
		.sharedConstructionPublicMockExtensionBased: 112,
		.sharedConstructionPublicMockInDeclaringModule: 73,
		.sharedConstructionPublicMockOneHolder: 49,
		.sharedConstructionPublicMockWithoutMockFirst: 108,
		.keywordLabeledPublicMock: 264,
		.keywordLabeledPublicMockBesideInternalConfiguration: 119,
		.overrideClosureCall: 358,
		.overrideClosureCallCanHand: 211,
		.overrideClosureCallFillReadsCalledMocksOtherPlace: 48,
		.overrideClosureCallFillReadsCalledMocksParameter: 45,
		.overrideClosureCallFillReadsConsumersValue: 34,
		.overrideClosureCallFillReadsValueCalledMockRenames: 41,
		.overrideClosureCallInternalCallerPassesPlaceUp: 82,
		.overrideClosureCallPublicCallerPassesPlaceUp: 81,
		.overrideClosureCallPlaceIsErasedInstantiator: 98,
		.promotedHolePublicMock: 96,
		.promotedHolePublicMockLazily: 83,
		.promotedHolePublicMockSendableLazily: 13,
		.promotedHolePublicMockPassedUp: 18,
		.promotedHolePublicMockPublicConsumer: 40,
		.optionalPlacePublicMock: 178,
		.optionalPlacePublicMockOnLeaf: 81,
		.optionalPlacePublicMockSendably: 30,
		.optionalPlacePublicMockReceived: 94,
		.optionalPlacePublicMockPassedUp: 70,
		.optionalPlacePublicMockPublicConsumer: 48,
		.unbuildableValuePublicMockCall: 198,
		.unbuildableValuePublicMockCallPublicTier: 191,
		.unbuildableValuePublicMockCallTierOmits: 7,
		.outerFulfillerPublicMockCall: 135,
		.holeLabelReceivedByPromotedSibling: 8,
		.holeLabelReceivedByPromotedSiblingHeldInInstantiator: 2,
		.holeLabelReceivedByPromotedSiblingHeldInLazilyInstantiated: 3,
		.holeLabelReceivedByPromotedSiblingEqualsGeneratedName: 2,
		.carrierBeforeSibling: 143,
		.carrierBeforeSiblingBetweenSiblings: 55,
		.carrierBeforeSiblingThroughSameModuleSeam: 76,
		.carrierBeforeSiblingBeneathConfiguredChild: 65,
		.carrierBeforeSiblingBeneathInternallyConfiguredChild: 29,
		.wrapperReadByValuePublicMock: 257,
		.wrapperReadByValuePublicMockMockedTypeReadsValue: 78,
		.wrapperReadByValuePublicMockMockedTypeReadsValueOnlyIfAvailable: 77,
		.wrapperReadByValuePublicMockReaderThroughInstantiator: 129,
		.wrapperReadByValuePublicMockSendably: 49,
		.wrapperReadByValuePublicMockTreeReadsValue: 102,
		.valueFormsBesidePublicMockCall: 324,
		.valueFormsBesidePublicMockCallUnbuildableValue: 158,
		.valueFormsBesidePublicMockCallPublicConsumer: 108,
		.valueFormsBesidePublicMockCallBeneathCycleEdge: 61,
		.valueFormsBesidePublicMockCallCalledTakesOptional: 103,
		.valueFormsBesidePublicMockCallTwoWrapperForms: 29,
		.valueFormsBesidePublicMockCallRenamed: 79,
		.valueFormsBesidePublicMockCallConsumerReceivesValue: 149,
		.valueFormsBesidePublicMockCallEmptyPublicMock: 136,
		.valueFormsBesidePublicMockCallLabelOfAnotherType: 150,
		.valueFormsBesidePublicMockCallCalledTreeReceivesValue: 135,
		.valueFormsBesidePublicMockCallPublicOptionalWrapperBesideOtherType: 53,
		.instantiableParameterType: 235,
		.internalInitializer: 520,
		.lazilyInstantiatedOmittedValueProvider: 58,
		.lazilyReceivedLabelWithOnlyIfAvailableByValueReceive: 227,
		.mainActorChildInitializerSpellsIsolation: 66,
		.mainActorChildIsolatedInitializer: 141,
		.mainActorChildNonisolatedInitializer: 40,
		.mockConditionDiffers: 103,
		.namespaceExtensionPackage: 93,
		.namespaceInMarkerFreeFile: 101,
		.dockPackage: 163,
		.dockInsidePlatformBlock: 172,
		.unreadParameterType: 260,
		.namespaceExtensionPublic: 44,
		.namespaceExtensionUnspelled: 78,
		.narrowerTreeType: 878,
		.nonOptionalDefault: 694,
		.omittedValueProviderAfterLeaf: 101,
		.omittedValueProviderAndLeafReceiveEachOther: 51,
		.omittedValueProviderBeforeLeaf: 100,
		.omittedValueProviderUnderSendableBuilder: 36,
		.onePublicMockType: 369,
		.optionalDefaultOfPackageType: 282,
		.optionalDefaultOfPublicType: 267,
		.optionalDefaultOfUnprovenType: 325,
		.otherPackageConsumerModuleOnly: 301,
		.ownOptionalDefaultOnNonisolatedTypeThatBuilds: 592,
		.seamDependency: 35,
		.seamDependencyChain: 32,
		.packageInitializer: 797,
		.plainTypeOnlyDefaultArgumentsName: 325,
		.plainTypeOnlyPackageInitializersTake: 214,
		.plainTypePublicInitializerTakes: 200,
		.protocolSlotFilledByFake: 686,
		.publicConsumer: 331,
		.publicConsumerLeavesLeafLabelUnprovided: 104,
		.qualifiedAllowlistedParameterType: 93,
		.requiredParameterNarrowerThanPublic: 43,
		.samePackageConsumerModuleOnly: 306,
		.sendableErasedInstantiatorLeaf: 15,
		.sendableWrapperAboveLeaf: 225,
		.spelledChildDefault: 147,
		.spelledClosure: 84,
		.spelledConsumerPasses: 109,
		.spelledExistential: 129,
		.spelledForwarded: 157,
		.spelledGeneric: 145,
		.spelledNested: 128,
		.spelledNonOptionalDefault: 150,
		.spelledOnlyIfAvailableReceive: 159,
		.spelledOptionalClosure: 136,
		.spelledOptionalDefault: 169,
		.spelledPlain: 118,
		.spelledRequiredReceive: 213,
		.spelledSendableClosure: 123,
		.spelledTuple: 120,
		.spelledTypealias: 127,
		.threePublicMockTypes: 332,
		.twoLeavesReceiveUnnameableDependency: 43,
		.twoPublicMockTypes: 299,
		.typeInExtensionOfInstantiable: 219,
	]

	/// Seed 2760, whose mock of `S2760_T2` the tool rejected until a mock passed `nil` to a receive only if available that
	/// another receive's form pins (#718): `S2760_T2` instantiates `t3: LazilyInstantiated<S2760_Unbuildable1>`, which its
	/// mock takes as a parameter, and builds `S2760_T1` through a `SendableErasedInstantiator`, and `S2760_T1` receives `t3`
	/// by value, so the mock reads the lazy value inside the `@Sendable` function, which does not compile.
	private static let mockParameterAndFieldOrderReason = "A mock's parameters and fields are sorted by label, so a renaming that reorders labels reorders them (Intended: CLAUDE.md's \"What may follow names\" allows a label sort of equivalent parameters, so the rename oracle's reordering here is expected, not a defect)"

	private static let lazyCycleConfigurationFieldReason = "Which back-edge of a lazy cycle loses its override follows the order of type names, so one field of a configuration struct, with the reads of it, is present under one naming and absent under another"

	private static let mockParameterAndFieldOrderAndLazyCycleConfigurationFieldReason = "\(mockParameterAndFieldOrderReason), and which back-edge of a lazy cycle loses its override follows the order of type names, so one field of a configuration struct is present under one naming and absent under another"

	// The remedy oracle's shapes: advice an error states that does not fix it. Each names its minimal graph, a test in
	// `SafeDIToolGraphFuzzerRemedyTests` that expects the advice to work as a known issue.
	static let remedyCapturedInSendableBuilderReason = "An error at a receive inside a `@Sendable` builder advises receiving, or declaring, a property that is not `Sendable`, or relabeling the declaration that hides one, which then cannot be received there (remedyRuns_leaveNoErrorAtTheReceive_whenTheSuggestedOnlyIfAvailableReceiveIsInsideASendableBuilder: Root builds `t1Builder: SendableInstantiator<T1>` and `t2Builder: Instantiator<T2>`, and T1 requires `t2Builder: Instantiator<T2>?`, which the error says to receive only if available)"

	static let remedyHiddenByCloserDeclarationReason = "An error advises receiving a property only if available, or a suggested property, beneath a type whose mock is generated and that declares the label with another type, so the mock rejects the receive as hidden (remedyRuns_leaveNoErrorAtTheReceive_whenAMockedTypeBetweenDeclaresItsLabelWithAnotherType: T3, mocked, declares `t4: T1` and builds T5, which Root builds too and which requires `t4: T0?`, and the error says to declare `t4: T0` on Root and receive it only if available)"

	static let remedySuggestionClosesCycleReason = "An error suggests receiving a property whose receive closes a dependency cycle (remedyRuns_leaveNoErrorAtTheReceive_whenTheSuggestedPropertyIsOfTheMockedReceiversOwnType: T1, mocked, requires `t0: T1` beneath T2, which forwards `t0: T1?` and builds T1, and the error suggests `t0: T1?`, which the mock of T1 receives while building T1)"

	static let remedySuggestionsAlternateReason = "Each error reports one path to a receiver, so receiving the property one path suggests leaves an error on another path, which suggests the first label again (remedyRuns_leaveNoErrorAtTheReceive_whenTwoPathsToTheReceiverDeclareTheReceivedTypeUnderOtherLabels: T1 declares `t4: T4` and T2 declares `lazyT4: T4`, and each builds T3, which requires `t4: T4`)"

	static let remedyDeclarationClosesCycleThroughRootReason = "An error advises declaring a property on a root whose own properties the declared type's tree receives and that require the declaration, so the declaration closes a dependency cycle there (remedyRuns_leaveNoErrorAtTheReceive_whenTheDeclaredTypesTreeReceivesARootPropertyThatRequiresTheDeclaration: Root builds `t2: T2`, which requires `t0Builder: Instantiator<T0>`, and T0 receives `t2`)"

	static let compileTimeAssertionsDifferBetweenIntegrationsReason = "The two multi-module integrations emit other compile-time assertions for a module whose declarations sit inside `#if` blocks, in a build that reports its conditions (the graphs `addingGuardedMockParameterShapes` draws, the first the fuzzer runs with conditions): a module that generates nothing else gets its assertions from the module-info flow and no generate run from the SwiftPM plugin flow (seed 4880: Alpha holds `Guarded` alone, and only the module-info flow emits `#if !(!FUZZ_GUARD)` `#error`), and a condition two blocks of one declaration test is asserted twice by the plugin flow and once by the module-info flow (seed 2915: `FUZZ_OTHER`). Left as it is: the flows differ in assertions only, never in code that does not compile or in a value; the first loses a check only in a module that generates nothing depending on it, and the second states one check twice. Revisit if an adopter reports a condition SwiftPM missed"

	static let remedyHidingDeclarationMasksMockTreeReceiveReason = "In a mock whose tree a cycle builds again, the error for a receive that a declaration of its label hides names a declaration that a type above the receive also receives, so relabeling it leaves that type’s receive of the label, which the mock’s tree then reports as hiding the receive (\"Receive … under different labels\"), an error the first one masked (remedyRuns_relabelTheHidingDeclarationAndLeaveNoErrorAtTheReceive_whenAMockWhoseTreeACycleBuildsAgainReceivesTheLabelInTheHidingForm: S1_T1, which generates a mock, declares `t3: S1_T4` and builds S1_T2 through an instantiator, which generates a mock, receives `t3: S1_T4` and builds S1_T0, which receives `t3: S1_T3` and builds S1_T1 again; once S1_T1’s declaration is relabeled, both mocks report S1_T0’s receive hidden by S1_T2’s). The advice fixes the error it states; the error it uncovers is another one, which a root reports only once its first is gone"
	static let remedySeamFillInstantiatedOutsideNotSendableReason = "A fill's error for a value inside a `@Sendable` function advises instantiating it outside the seam as declared, a wrapper that is not `Sendable`, which the fill, inside that function, cannot capture from the builder's caller (a neighbour of adopter shape W8; seed 1401; remedyRuns_leaveNoErrorAtTheReceive_whenTheValueInstantiatedOutsideTheSeamIsALazyWrapperTheSendableFillCannotCapture: S1_Outer declares `logger: LazilyInstantiated<S1_Logger>` and calls S1_Inner, which builds the place in a `SendableInstantiator`, and the error says to instantiate `logger` outside S1_Outer). Its fix names the `Sendable` wrapper in the advice, `SendableLazilyInstantiated<S1_Logger>`"
	static let remedySeamFillCycleReceiveNotSendableReason = "A fill's error for a value a cycle in the seam's tree declares again advises receiving it on the type the cycle builds again, which a `@Sendable` function builds, as the wrapper the cycle declares, which is not `Sendable`, so that type cannot receive it there (seed 1916; remedyRuns_leaveNoErrorAtTheReceive_whenTheTypeTheCycleBuildsAgainIsInsideASendableFunctionAndTheValueIsNotSendable: S1_Home declares `cache: Instantiator<S1_Cache>` and builds S1_Screen in a `SendableInstantiator`, S1_Screen builds S1_Step in another, and S1_Step declares `cache` again and builds S1_Screen again, and the error says to declare `@Received(onlyIfAvailable: true) let cache: Instantiator<S1_Cache>?` on S1_Screen). Its fix names the `Sendable` wrapper in the advice, `SendableInstantiator<S1_Cache>`"
	static let remedySeamFillBuilderPassedOnReason = "A fill's error for a value a type receives beneath a builder that a type in the seam's tree passes on from its own caller advises receiving the value on the seam, or instantiating it outside the seam, which leaves that builder passed on, so the error stays (\"passes the builder … on from its own caller\", or, where the builder is `@Sendable`, \"would get another value\"; seed 614: `S614_HoleRelay` passes the builder for `S614_HoleStageOwner`’s `holeService` on from its own caller, and the error at `S614_HoleImpl` says to declare `@Received let holeLogger: S614_HoleLogger` on `S614_HoleSeam`)"
	static let remedyRelabelLeavesSeamLabelInTwoFormsReason = "An error at a receive that a declaration of its label hides advises relabeling the hiding declaration, which leaves a seam's tree receiving the label in two forms, which a seam rejects (\"Receive `t0Builder` the same way in every type of the tree\"; seed 1935: relabeling `t0Builder: SendableInstantiator<S1935_T0>` on `S1935_T2` leaves `S1935_T1` receiving `t0Builder: Instantiator<S1935_T0>?` and `S1935_T4` receiving `t0Builder: Instantiator<S1935_T0>`)"
	static let remedySeamProvidingWrapperUndeclaredReason = "A seam's error for one label its tree receives in two forms advises declaring on the seam the wrapper that provides the others, which no type that builds the seam declares, so the seam's receive is then unfulfilled, or a dependency cycle through the wrapper's type (seed 871: `FormsUser` -> `FormsScreen` -> `FormsUser`; remedyRuns_leaveNoErrorAtTheSeam_whenTheProvidingFormIsAWrapperTheSeamsCallerDoesNotDeclare: Root declares `user: S1_User` and builds S1_Seam, which receives `user: LazilyInstantiated<S1_User>?` only if available and builds S1_Child, which requires `user: S1_User`, and the error says to declare `@Received let user: LazilyInstantiated<S1_User>` on S1_Seam). Plan row I8 owns the fix"
	static let valueOracleSendableTreeReceivingInstantiatorReason = "A value-oracle fixture limit: a root's mock accepts a `SendableInstantiator` tree that receives a non-`Sendable` `Instantiator` from outside, which production rejects under any host, so the fixture that calls the mock beside production is rejected (Intended: an oracle limit, not a SafeDI defect; seed 2764: `S2764_Root1` builds `t3Builder: SendableInstantiator<S2764_T1>`, and `S2764_T1` receives `t2Builder: Instantiator<S2764_T2>`, which cannot be received inside a `@Sendable` function)"
	static let remedySendableWrapperNamesOneDeclarationReason = "An error at a receive inside a `@Sendable` function advises declaring the captured property as its `Sendable` wrapper on the one root its chain starts at, and at the receive, where another root declares the property, or another type receives it, as the wrapper that is not `Sendable`: the receive is then unfulfilled beneath the other root, or hidden beneath the other receiver (remedyRuns_leaveNoErrorAtTheReceive_whenAnotherRootDeclaresThePropertyTheSendableBuilderCannotCapture: Root0 builds T1 through `SendableInstantiator<T1>` and Root1 as a constant, each declares `t2Builder: Instantiator<T2>`, and T1 receives it). Naming every declaration whose `@Sendable` chain reaches the receive leaves out, in the base corpus's seeds 1436 and 4829, a root that reaches it on a chain that is not `@Sendable`, or the mock of a type that receives it"

	/// Seeds in `0..<corpusSeedCount` whose graphs fail today, grouped by shape. Every fix first adds a graph of
	/// its shape, reduced, as a hand-written regression test; removing the seeds is the last step of the fix.
	static let knownIssues = addingReportedIssueShapes(to: knownIssuesBesideReportedIssueShapes)

	/// Why a graph that draws `GraphFuzzerGenerator.addingRepeatedAncestorShapes`'s roll changes under a renaming: the
	/// roll's `RepeatScreen` and `RepeatFlow` are a two-type lazy cycle, which shows `lazyCycleConfigurationFieldReason`.
	static let repeatedAncestorLazyCycleReason = "#720's roll closes a two-type lazy cycle, `RepeatScreen` building `RepeatFlow`, which builds `RepeatScreen` through an instantiator, and which back-edge of a lazy cycle loses its override follows the order of type names, so one field of a configuration struct, with the reads of it, is present under one naming and absent under another"

	/// The seeds of the base corpus whose graphs draw the roll of #720's shape and whose lazy cycle loses another field
	/// of its configuration under a renaming, but for those already listed under that shape, copied from a run of the
	/// rolls' seeds.
	static let repeatedAncestorLazyCycleSeeds: [UInt64] = [
		16, 24, 249, 279, 355, 579, 609, 850, 1_014, 1_093, 1_121, 1_175, 1_391, 1_513, 1_538, 1_572, 1_661, 1_677,
		1_759, 2_096, 2_147, 2_298, 2_330, 2_620, 2_634, 2_645, 2_665, 2_901, 3_049, 3_080, 3_393, 3_452, 3_909, 3_964,
		4_123,
	]

	/// Why a graph that draws `GraphFuzzerGenerator.addingReceiveThroughCycleWalkedEarlier`'s screens changes under a
	/// renaming: the screens open one another through instantiators, lazy cycles, which show `lazyCycleConfigurationFieldReason`.
	static let receiveThroughCycleWalkedEarlierLazyCycleReason = "The screens of the roll of a receive through a cycle walked earlier open one another through instantiators, and which back-edge of a lazy cycle loses its override follows the order of type names, so one field of a configuration struct, with the reads of it, is present under one naming and absent under another"

	/// The seeds of the base corpus whose graphs draw the screens of `addingReceiveThroughCycleWalkedEarlier` and whose lazy
	/// cycles lose another field of their configuration under a renaming, copied from a run of the roll's seeds.
	static let receiveThroughCycleWalkedEarlierLazyCycleSeeds: [UInt64] = [
		95, 121, 243, 259, 346, 413, 490, 497, 507, 512, 528, 653, 724, 744, 939, 966, 1_005, 1_043, 1_073, 1_293, 1_295,
		1_533, 1_547, 1_570, 1_585, 1_617, 1_627, 1_648, 1_827, 1_860, 2_034, 2_067, 2_093, 2_153, 2_176, 2_371, 2_394,
		2_452, 2_496, 2_564, 2_616, 2_679, 2_727, 2_729, 2_839, 2_860, 2_890, 2_931, 2_967, 2_985, 3_035, 3_040, 3_079,
		3_284, 3_484, 3_502, 3_524, 3_580, 3_714, 3_718, 3_815, 3_924, 3_956, 4_033, 4_051, 4_088, 4_219, 4_273, 4_277,
		4_297, 4_322, 4_439, 4_623, 4_695,
	]

	/// `issues` with the shapes of the reported issues the base corpus's rolls draw, each combined with a seed's other
	/// shapes in an entry of its own, since a seed is listed once. Only the base corpus draws these rolls, so the seam
	/// corpus inherits `knownIssuesBesideReportedIssueShapes`.
	private static func addingReportedIssueShapes(to issues: [GraphFuzzerKnownIssue]) -> [GraphFuzzerKnownIssue] {
		GraphFuzzerKnownIssue.adding(
			.renamedGraphDiffers(.mockConfigurationFieldPresence),
			reason: receiveThroughCycleWalkedEarlierLazyCycleReason,
			seeds: receiveThroughCycleWalkedEarlierLazyCycleSeeds,
			to: GraphFuzzerKnownIssue.adding(.renamedGraphDiffers(.mockConfigurationFieldPresence), reason: repeatedAncestorLazyCycleReason, seeds: repeatedAncestorLazyCycleSeeds, to: issues),
		)
	}

	/// `knownIssues` but for the shapes of the reported issues only the base corpus draws (`addingReportedIssueShapes`).
	static let knownIssuesBesideReportedIssueShapes: [GraphFuzzerKnownIssue] = [
		GraphFuzzerKnownIssue(
			reason: mockParameterAndFieldOrderReason,
			signatures: [.renamedGraphDiffers(.mockParameterAndFieldOrder)],
			seeds: [
				6, 7, 14, 27, 36, 45, 51, 55, 64, 157, 188, 209, 272, 281, 300, 342, 371, 380, 381, 434, 455, 476, 541,
				548, 577, 593, 624, 634, 657, 695, 774, 801, 808, 840, 848, 903, 1_024, 1_042, 1_073, 1_081, 1_140,
				1_163, 1_185, 1_216, 1_217, 1_300, 1_301, 1_335, 1_369, 1_432, 1_434, 1_442, 1_483, 1_521, 1_563, 1_572,
				1_646, 1_659, 1_664, 1_675, 1_742, 1_795, 1_805, 1_816, 1_817, 1_853, 1_867, 1_959, 2_051, 2_057, 2_083,
				2_149, 2_296, 2_337, 2_484, 2_532, 2_594, 2_626, 2_707, 2_790, 2_791, 2_836, 2_841, 2_863, 2_916, 2_935,
				2_949, 3_013, 3_040, 3_160, 3_352, 3_470, 3_491, 3_513, 3_527, 3_534, 3_537, 3_547, 3_589, 3_600, 3_613,
				3_623, 3_661, 3_674, 3_704, 3_822, 3_843, 3_908, 3_922, 3_940, 3_943, 3_987, 3_994, 4_015, 4_025, 4_090,
				4_103, 4_191, 4_192, 4_278, 4_430, 4_541, 4_607, 4_613, 4_634, 4_664, 4_712, 4_729, 4_834, 4_857, 4_865,
				4_891, 4_947, 4_955, 4_983,
			],
		),
		GraphFuzzerKnownIssue(
			reason: lazyCycleConfigurationFieldReason,
			signatures: [.renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [
				3, 35, 107, 114, 116, 131, 168, 204, 223, 241, 264, 265, 311, 323, 338, 364, 383, 390, 431, 448, 450,
				473, 508, 515, 525, 527, 545, 567, 595, 617, 628, 630, 644, 680, 714, 728, 732, 735, 742, 749, 751, 768,
				785, 786, 836, 847, 886, 912, 940, 948, 953, 975, 987, 991, 993, 1_004, 1_029, 1_044, 1_051, 1_061,
				1_064, 1_072, 1_075, 1_084, 1_092, 1_139, 1_145, 1_147, 1_149, 1_172, 1_236, 1_244, 1_322, 1_329, 1_352,
				1_362, 1_372, 1_433, 1_441, 1_447, 1_453, 1_464, 1_492, 1_504, 1_524, 1_531, 1_559, 1_567, 1_580, 1_602,
				1_633, 1_708, 1_758, 1_781, 1_784, 1_804, 1_857, 1_896, 1_926, 1_938, 1_972, 2_009, 2_013, 2_017, 2_084,
				2_123, 2_152, 2_165, 2_234, 2_249, 2_270, 2_277, 2_282, 2_287, 2_316, 2_325, 2_335, 2_348, 2_389, 2_403,
				2_430, 2_432, 2_437, 2_444, 2_456, 2_529, 2_555, 2_577, 2_630, 2_633, 2_637, 2_669, 2_682, 2_732, 2_808,
				2_835, 2_845, 2_874, 2_914, 2_972, 3_004, 3_064, 3_074, 3_075, 3_091, 3_134, 3_180, 3_183, 3_196, 3_215,
				3_221, 3_232, 3_241, 3_250, 3_252, 3_298, 3_306, 3_329, 3_344, 3_345, 3_359, 3_361, 3_430, 3_504, 3_506,
				3_522, 3_526, 3_533, 3_541, 3_567, 3_577, 3_579, 3_582, 3_584, 3_588, 3_594, 3_596, 3_602, 3_648, 3_699,
				3_707, 3_715, 3_723, 3_741, 3_750, 3_775, 3_776, 3_805, 3_820, 3_823, 3_826, 3_832, 3_850, 3_858, 3_879,
				3_885, 3_894, 3_915, 4_044, 4_068, 4_102, 4_107, 4_110, 4_117, 4_122, 4_125, 4_156, 4_177, 4_206, 4_213,
				4_215, 4_217, 4_227, 4_254, 4_260, 4_266, 4_281, 4_304, 4_344, 4_358, 4_371, 4_396, 4_404, 4_420, 4_428,
				4_515, 4_534, 4_545, 4_549, 4_567, 4_603, 4_619, 4_637, 4_640, 4_642, 4_666, 4_684, 4_699, 4_707, 4_716,
				4_717, 4_775, 4_776, 4_781, 4_783, 4_786, 4_795, 4_859, 4_904, 4_918, 4_921, 4_922, 4_944, 4_963, 4_964,
				4_996,
			],
		),
		// A graph that shows both reasons, under one renaming or across them, is documented only by the shape that names both.
		GraphFuzzerKnownIssue(
			reason: mockParameterAndFieldOrderAndLazyCycleConfigurationFieldReason,
			signatures: [.renamedGraphDiffers(.mockParameterAndFieldOrder), .renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [
				21, 77, 461, 632, 772, 869, 1_035, 1_366, 1_496, 1_525, 1_970, 2_211, 2_518, 2_553, 2_667, 2_704, 2_741,
				2_902, 2_974, 3_023, 3_225, 3_439, 3_609, 4_496,
			],
		),
		GraphFuzzerKnownIssue(
			reason: "Intended: a root's mock rejects a tree that repeats a label along a branch, a receive, only if available, of a label a closer declaration holds with another type, which production accepts for the same tree",
			signatures: [.valueOracleFixtureRejected(containing: "is hidden in chain")],
			seeds: [
				47, 207, 451, 471, 598, 685, 939, 1_028, 1_116, 1_323, 1_374, 1_499, 1_614, 1_687, 1_793, 2_147, 2_775,
				3_089, 3_208, 3_698, 3_813, 4_079, 4_311, 4_388, 4_790,
			],
		),
		// A known rejection masks no later failure, so a graph that also changes under a renaming documents both.
		GraphFuzzerKnownIssue(
			reason: "Intended: a root's mock rejects a tree that repeats a label along a branch, a receive, only if available, of a label a closer declaration holds with another type, which production accepts for the same tree, in a graph whose mock's parameters and fields also reorder under a renaming",
			signatures: [.valueOracleFixtureRejected(containing: "is hidden in chain"), .renamedGraphDiffers(.mockParameterAndFieldOrder)],
			seeds: [309, 1_561, 1_864, 3_132, 3_141, 3_692],
		),
		GraphFuzzerKnownIssue(
			reason: "Intended: a root's mock rejects a tree that repeats a label along a branch, a receive, only if available, of a label a closer declaration holds with another type, which production accepts for the same tree, in a graph whose lazy cycle also drops another configuration field under a renaming",
			signatures: [.valueOracleFixtureRejected(containing: "is hidden in chain"), .renamedGraphDiffers(.mockConfigurationFieldPresence)],
			seeds: [2_201, 3_247],
		),
		GraphFuzzerKnownIssue(
			reason: remedyCapturedInSendableBuilderReason,
			signatures: [
				.remedyLeavesErrorAtSite(.instantiateOnRoot, containing: "cannot be received inside a `@Sendable` function"),
				.remedyLeavesErrorAtSite(.instantiateOnRootAndReceiveOnlyIfAvailable, containing: "cannot be received inside a `@Sendable` function"),
				.remedyLeavesErrorAtSite(.receiveOnlyIfAvailable, containing: "cannot be received inside a `@Sendable` function"),
				.remedyLeavesErrorAtSite(.receiveOptionallyIfAvailable, containing: "cannot be received inside a `@Sendable` function"),
				.remedyLeavesErrorAtSite(.receiveSuggestedProperty, containing: "cannot be received inside a `@Sendable` function"),
				.remedyLeavesErrorAtSite(.relabelHidingDeclaration, containing: "cannot be received inside a `@Sendable` function"),
			],
			seeds: [
				167, 456, 1_724, 1_935, 2_715, 3_145, 3_240, 4_345,
			],
		),
		GraphFuzzerKnownIssue(
			reason: remedyHiddenByCloserDeclarationReason,
			signatures: [
				.remedyLeavesErrorAtSite(.instantiateOnRootAndReceiveOnlyIfAvailable, containing: "is hidden in chain"),
				.remedyLeavesErrorAtSite(.receiveOnlyIfAvailable, containing: "is hidden in chain"),
				.remedyLeavesErrorAtSite(.receiveOptionallyIfAvailable, containing: "is hidden in chain"),
				.remedyLeavesErrorAtSite(.receiveSuggestedProperty, containing: "is hidden in chain"),
			],
			seeds: [
				492, 1_832, 2_322, 2_500, 2_663, 2_982, 3_529, 3_778, 3_799, 4_142, 4_441, 4_940,
			],
		),
		GraphFuzzerKnownIssue(
			reason: remedyHidingDeclarationMasksMockTreeReceiveReason,
			signatures: [.remedyLeavesErrorAtSite(.relabelHidingDeclaration, containing: "is hidden in chain")],
			seeds: [1_898],
		),
		GraphFuzzerKnownIssue(
			reason: remedySuggestionClosesCycleReason,
			signatures: [.remedyLeavesErrorAtSite(.receiveSuggestedProperty, containing: "Dependency cycle: ")],
			seeds: [1_132, 2_059, 2_560, 3_995, 4_333],
		),
		GraphFuzzerKnownIssue(
			reason: remedySuggestionsAlternateReason,
			signatures: [.remedyLeavesErrorAtSite(.receiveSuggestedProperty, containing: "Did you mean `")],
			seeds: [495, 2_272],
		),
		GraphFuzzerKnownIssue(
			reason: remedyDeclarationClosesCycleThroughRootReason,
			signatures: [.remedyLeavesErrorAtSite(.instantiateOnRoot, containing: "Dependency cycle: ")],
			seeds: [4_864],
		),
		GraphFuzzerKnownIssue(
			reason: remedySendableWrapperNamesOneDeclarationReason,
			signatures: [
				.remedyLeavesErrorAtSite(.declareAsSendableWrapper, containing: "` is not @Instantiated or @Forwarded in chain: "),
				.remedyLeavesErrorAtSite(.declareAsSendableWrapper, containing: "is hidden in chain"),
			],
			seeds: [1_436, 4_829],
		),
		GraphFuzzerKnownIssue(
			reason: valueOracleSendableTreeReceivingInstantiatorReason,
			signatures: [.valueOracleFixtureRejected(containing: "cannot be received inside a `@Sendable` function")],
			seeds: [2_764, 3_405],
		),
		GraphFuzzerKnownIssue(
			reason: compileTimeAssertionsDifferBetweenIntegrationsReason,
			signatures: [.integrationsDiffer(containing: "<compile-time assertions>")],
			seeds: [2_787, 4_622, 4_839],
		),
	]

	/// Known issues for the tests of `GraphFuzzerFinding`, which must not depend on what `knownIssues` lists today.
	private static let valueOracleRejectionKnownIssue = GraphFuzzerKnownIssue(
		reason: "A root's mock rejects a receive of a hidden label",
		signatures: [.valueOracleFixtureRejected(containing: "is hidden in chain")],
		seeds: [47],
	)
	private static let hiddenInChainError = "/F/S47_T1.swift:7:2: error: @Received property `t1: S47_T3?` is hidden in chain: S47_Root0 -> S47_T0 -> S47_T1. `S47_T0` declares `t1: S47_T1` with the same label, so the types below `S47_T0` receive `t1: S47_T1` instead. Give `t1: S47_T1` on `S47_T0` a different label to fix."

	/// The failure of a value-oracle fixture the tool rejects with `errorLines`, each followed by a note, as the tool
	/// reports a hidden label.
	private static func valueOracleRejection(errorLines: [String]) -> GraphFuzzerFailure {
		let diagnostics = errorLines.map { "\($0)\n/F/S47_T0.swift:8:2: note: `t1: S47_T1` is declared here" }
		return GraphFuzzerFailure(
			seed: 47,
			kind: .valueOracleFixtureRejected,
			details: (diagnostics + ["The value-oracle fixture:", "…"]).joined(separator: "\n"),
			rejectionErrorLines: errorLines,
		)
	}

	/// A known issue that documents a difference of `comparison` whose description contains `documentedDifference`'s
	/// last line, and no other.
	private static func valueDivergenceKnownIssue(of comparison: ValueComparisonUnderTest) -> GraphFuzzerKnownIssue {
		GraphFuzzerKnownIssue(
			reason: "A documented divergence",
			signatures: [comparison.signature(containing: "known right: aliasAuth: nil")],
			seeds: [430],
		)
	}

	private static let documentedDifference = "probe `Root()` at <1> Root > aliasSeam > aliasDetail > aliasAuth:\n  feature:     aliasAuth: <2> Value (seen, first at <1> Root > aliasSource)\n  known right: aliasAuth: nil"
	private static let undocumentedDifference = "probe `Root()` at <1> Root > aliasSeam > aliasRight > aliasToken:\n  feature:     aliasToken: nil\n  known right: aliasToken: <3> Value"

	/// The runs of the first seam smoke graph the tool accepts with its seam and without it whose root passes a value
	/// for a tier parameter received only if available, with its seam build's files and warnings.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func valueProbeRuns() async throws -> (runs: GraphFuzzerToolRuns, seamFiles: [String: String], warnings: [String]) {
		for seed in seamSmokeSeeds {
			let runs = try await GraphFuzzerOracle.toolRuns(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree]), renamings: [])
			guard case let .accepted(seamFiles, warnings) = runs.firstOutcome, case .accepted = runs.inlineOutcome, passingNil(forAnOnlyIfAvailableParameterIn: seamFiles, of: runs.fixture) != nil else { continue }
			return (runs, seamFiles, warnings)
		}
		throw GraphFuzzerTestError.noSmokeGraphPassesValueForOnlyIfAvailableParameter
	}

	/// Seed 1637's runs, with the files of its seam build perturbed so that the one site of `CycleB`'s hole hands the fill
	/// the `cycle6Tag` the function's reader holds – the level above's – instead of its own `CycleB`'s, and that build's
	/// warnings. The perturbed build constructs other values than both the visible build and the inline build.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func cycleFillReadingLevelAboveRuns() async throws -> (runs: GraphFuzzerToolRuns, perturbedFiles: [String: String], warnings: [String]) {
		let seed: UInt64 = 1_637
		let runs = try await GraphFuzzerOracle.toolRuns(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree]), renamings: [])
		guard case let .accepted(files, warnings) = runs.firstOutcome, case .accepted = runs.visibleOutcome, case .accepted = runs.inlineOutcome else {
			throw GraphFuzzerTestError.cycleSeedIsNoLongerAcceptedEveryWay
		}
		let seamFileName = try #require(files.keys.first { $0.hasSuffix("/S\(seed)_CycleSeam+SafeDI.swift") })
		let seamFile = try #require(files[seamFileName])
		// The type key declares `CycleB`'s function once at the seam's root, so the level above's `cycle6Tag`, which
		// `CycleA`'s function binds and its reader holds, is not in scope at the site. The edit hands it in: the function
		// takes it as one more parameter, `CycleA`'s function passes its own `cycle6Tag`, and the site, which calls its
		// carrier's member with the level's values positionally, `cycle6Tag` first, reads it in place of `CycleB`'s.
		let edits = [
			(
				"func __safeDI_cycle2BBuilder(__safeDI_s\(seed)_CycleServiceBuilder_cycle2BBuilder: __safeDI_S\(seed)_CycleServiceCarrier_S\(seed)_CycleB<any S\(seed)_CycleService>)",
				"func __safeDI_cycle2BBuilder(__safeDI_s\(seed)_CycleServiceBuilder_cycle2BBuilder: __safeDI_S\(seed)_CycleServiceCarrier_S\(seed)_CycleB<any S\(seed)_CycleService>, levelAboveCycle6Tag: S\(seed)_CycleTag)",
			),
			(
				"__safeDI_cycle2BBuilder(__safeDI_s\(seed)_CycleServiceBuilder_cycle2BBuilder: __safeDI_s\(seed)_CycleServiceBuilder_cycle2BBuilder)",
				"__safeDI_cycle2BBuilder(__safeDI_s\(seed)_CycleServiceBuilder_cycle2BBuilder: __safeDI_s\(seed)_CycleServiceBuilder_cycle2BBuilder, levelAboveCycle6Tag: cycle6Tag)",
			),
			(".cycle0Service(cycle6Tag, ", ".cycle0Service(levelAboveCycle6Tag, "),
		]
		var perturbedFile = seamFile
		for (text, replacement) in edits {
			try #require(perturbedFile.components(separatedBy: text).count == 2, "Seed \(seed)’s seam no longer holds `\(text)` once")
			perturbedFile = perturbedFile.replacingOccurrences(of: text, with: replacement)
		}
		var perturbedFiles = files
		perturbedFiles[seamFileName] = perturbedFile
		return (runs, perturbedFiles, warnings)
	}

	/// `seamFiles` with the first call, in a root's file, of a seam tier's parameter received only if available
	/// (`GraphFuzzerSeamParameterKinds`) passing `nil` instead of the value it passed, with the parameter's label; or
	/// `nil` when no root's call passes a value for such a parameter.
	private static func passingNil(forAnOnlyIfAvailableParameterIn seamFiles: [String: String], of fixture: GraphFuzzerFixture) -> (files: [String: String], label: String)? {
		let parameterKinds = GraphFuzzerSeamParameterKinds(fixture: fixture)
		for (_, contents) in seamFiles.sorted(by: { $0.key < $1.key }) where contents.contains("public enum __safeDI_") {
			for initializer in GraphFuzzerOracle.seamInitializerParameters(inGeneratedFile: contents) {
				for parameter in initializer.parameters {
					let label = parameter.prefix { $0 != ":" }.trimmingCharacters(in: .whitespaces)
					guard parameterKinds.isOnlyIfAvailable(label: label, ofSeam: initializer.seamTypeName) else { continue }
					for (rootFileName, rootContents) in seamFiles.sorted(by: { $0.key < $1.key }) where rootFileName.hasPrefix("\(fixture.typeNamePrefix)Root") {
						// The arguments of the first call of the seam: up to the parenthesis that closes it.
						guard let callRange = rootContents.range(of: "\(initializer.seamTypeName)(") else { continue }
						var depth = 1
						var callEnd = callRange.upperBound
						while depth > 0, callEnd < rootContents.endIndex {
							switch rootContents[callEnd] {
							case "(": depth += 1
							case ")": depth -= 1
							default: break
							}
							callEnd = rootContents.index(after: callEnd)
						}
						guard let argument = rootContents[callRange.upperBound..<callEnd].range(of: "\(label): \(label)") else { continue }
						var files = seamFiles
						files[rootFileName] = rootContents.replacingCharacters(in: argument, with: "\(label): nil")
						return (files, label)
					}
				}
			}
		}
		return nil
	}

	private static let compilerErrorKnownIssue = GraphFuzzerKnownIssue(
		reason: "A shape whose generated code redeclares a label",
		signatures: [.compilerError(containing: "invalid redeclaration")],
		seeds: [84],
	)
	private static let compilerWarningKnownIssue = GraphFuzzerKnownIssue(
		reason: "A shape whose generated code binds a value it never reads",
		signatures: [.compilerWarning(containing: "was never used")],
		seeds: [84],
	)
	private static let compilerCrashKnownIssue = GraphFuzzerKnownIssue(
		reason: "A shape whose generated mock crashes the compiler, or captures a closure before declaring it",
		signatures: [.compilerError(containing: "before it is declared"), .compilerCrashInGeneratedMock],
		seeds: [705],
	)

	private static let longRunBatchSize = 20

	/// Every this many seeds, the long run also runs the `SafeDITool` executable in two processes and compares them.
	private static let crossProcessSampleInterval: UInt64 = 50

	/// What is wrong with `knownIssues`: a seed listed twice, a shape's seeds out of order, or a seed the long
	/// run's corpus does not cover.
	static func knownIssueListProblems(_ knownIssues: [GraphFuzzerKnownIssue] = knownIssues, corpusSeedCount: Int = corpusSeedCount) -> [String] {
		var problems = [String]()
		var seenSeeds = Set<UInt64>()
		for knownIssue in knownIssues {
			if knownIssue.seeds.isEmpty || knownIssue.signatures.isEmpty {
				problems.append("The known issue \"\(knownIssue.reason)\" lists no seeds or no signatures.")
			}
			if knownIssue.seeds != knownIssue.seeds.sorted() {
				problems.append("The seeds of \"\(knownIssue.reason)\" are not in increasing order.")
			}
			for seed in knownIssue.seeds {
				if !seenSeeds.insert(seed).inserted {
					problems.append("Seed \(seed) is listed as a known issue more than once.")
				}
				if seed >= UInt64(corpusSeedCount) {
					problems.append("Seed \(seed) is a known issue outside the corpus, seeds 0..<\(corpusSeedCount).")
				}
			}
		}
		return problems
	}

	static func fixtureHash(forSeeds seeds: [UInt64], features: Set<GraphFuzzerGeneratorFeature> = []) -> UInt64 {
		var hash = GraphFuzzerHash()
		for seed in seeds {
			hash.combine(GraphFuzzerGenerator.fixture(forSeed: seed, features: features).description)
		}
		return hash.value
	}

	static func partitionHash(forSeeds seeds: [UInt64]) -> UInt64 {
		var hash = GraphFuzzerHash()
		for seed in seeds {
			hash.combine(GraphFuzzerPartition.partition(of: GraphFuzzerGenerator.fixture(forSeed: seed)).description)
		}
		return hash.value
	}

	private static func hexadecimal(_ value: UInt64) -> String {
		"0x" + String(value, radix: 16, uppercase: true)
	}

	/// Records `finding` as an issue: as a known issue when it is one, and as a known issue that was not recorded,
	/// which fails the test, when the seed no longer fails.
	private static func record(_ finding: GraphFuzzerFinding, fixture: GraphFuzzerFixture) {
		switch finding {
		case .passed:
			break
		case let .knownIssue(knownIssue, failure):
			withKnownIssue("Seed \(fixture.seed): \(knownIssue.reason)") {
				Issue.record(failure.issueComment(fixture: fixture))
			}
		case let .staleKnownIssue(knownIssue):
			withKnownIssue("Seed \(fixture.seed) no longer fails, so \(Self.corpus(for: GraphFuzzerGeneratorFeature.features(drawnIn: fixture)).staleSeedRemedy(knownIssue, fixture.seed)): \(knownIssue.reason)") {}
		case let .staleRenamedGraphDifference(knownIssue, aspect):
			Issue.record("Seed \(fixture.seed) sits on \"\(knownIssue.reason)\", which lists \(aspect.rawValue), but its renamed graphs do not show it: list the seed under the entry that names exactly what it shows.")
		case let .staleBuilderSurfaceSignature(knownIssue, kind):
			Issue.record("Seed \(fixture.seed) sits on \"\(knownIssue.reason)\", which lists \(kind.rawValue), but the graph does not show it: list the seed under the entry that names exactly what it shows.")
		case let .staleLeakEntry(knownIssue):
			Issue.record("Seed \(fixture.seed) sits on \"\(knownIssue.reason)\", which lists a leak the graph no longer shows: remove the seed from the leak's entry.")
		case let .failure(failure):
			Issue.record(failure.issueComment(fixture: fixture))
		}
	}
}

/// The smoke batch's results, computed once per process and shared by the tests that check them.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) private let smokeResults = SharedTestWork {
	try await GraphFuzzerOracle.results(forSeeds: SafeDIToolGraphFuzzerTests.smokeSeeds, isolatingValueGraphsOf: SafeDIToolGraphFuzzerTests.baseCorpus.isolatedValueGraphSeeds)
}

/// The seam smoke batch's results, drawn with the `generateDependencyTree` feature, computed once per process.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) private let seamSmokeResults = SharedTestWork {
	try await GraphFuzzerOracle.results(forSeeds: SafeDIToolGraphFuzzerTests.seamSmokeSeeds, features: [.generateDependencyTree], isolatingValueGraphsOf: SafeDIToolGraphFuzzerTests.seamSmokeSeedsTraversingPastTheBatchBudget)
}

extension GraphFuzzerToolRuns {
	/// These runs, with one more generated file in both outcomes when the tool accepted the graph.
	func addingGeneratedFile(named fileName: String, contents: String) -> GraphFuzzerToolRuns {
		func adding(to outcome: GraphFuzzerToolOutcome) -> GraphFuzzerToolOutcome {
			switch outcome {
			case let .accepted(generatedFiles, warnings):
				.accepted(generatedFiles: generatedFiles.merging([fileName: contents]) { $1 }, warnings: warnings)
			case .rejected:
				outcome
			}
		}
		return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: adding(to: firstOutcome), secondOutcome: adding(to: secondOutcome))
	}
}

/// The long run's settings, read from the environment.
struct GraphFuzzerLongRunConfiguration {
	let iterations: Int
	let startingSeed: UInt64
	/// The seeds `SAFEDI_GRAPH_FUZZER_SEEDS` lists, in the order it lists them, which the run then covers in place of
	/// the `iterations` consecutive seeds from `startingSeed`; `iterations` is their count and `startingSeed` the first.
	let listedSeeds: [UInt64]?
	/// Whether `SAFEDI_GRAPH_FUZZER_SEEDS` is set, whatever it holds.
	let namesSeedList: Bool
	/// The generator features the run's graphs are drawn with, which select the corpus and its pins, or `nil` when
	/// `SAFEDI_GRAPH_FUZZER_FEATURES` names a feature that does not exist, which the run reports.
	let features: Set<GraphFuzzerGeneratorFeature>?
	/// A file the run appends its progress to, which `graph-fuzzer.yml` reads: `seed <n>` before the tool first
	/// runs each graph; `failure <seed> <kind>`, with a renamed graph's difference after the kind, `known <seed> <reason>`,
	/// `stale <seed> <reason>`, or `misfiled <seed> <reason>` for each finding; `renamed <seed> <summary>` and `multimodule <seed> <summary>` for each renamed or partitioned run
	/// that gives other results, whether or not the graph fails another way; `problem <text>` for anything wrong
	/// with the run itself; `partitions …` with how many base corpus graphs are split into each number of modules and
	/// how many have a `Delta` depending on `Gamma`, whose two integrations combine declarations in different orders;
	/// `cpu …` with what each `GraphFuzzerPhase` cost (`GraphFuzzerPhaseAccount`); and `completed …` at the end.
	let reportPath: String?

	/// The process's settings: `configuration(inEnvironment:)` of its environment.
	static var current: GraphFuzzerLongRunConfiguration? {
		configuration(inEnvironment: ProcessInfo.processInfo.environment)
	}

	/// `nil` unless `SAFEDI_GRAPH_FUZZER_ITERATIONS` or `SAFEDI_GRAPH_FUZZER_SEEDS` is set. `SAFEDI_GRAPH_FUZZER_ITERATIONS`
	/// is a count of seeds, or `corpus` for the seed count
	/// of the corpus `SAFEDI_GRAPH_FUZZER_FEATURES` selects – a comma-separated list of `GraphFuzzerGeneratorFeature`
	/// names, or unset for the corpus drawn without features. Anything else becomes zero, which the run reports.
	/// `SAFEDI_GRAPH_FUZZER_SHARD`, when set to `<index>/<count>`, runs only that shard of those seeds
	/// (`shard(_:of:startingSeed:iterations:)`), as `graph-fuzzer.yml`'s jobs do; any other value also becomes zero.
	/// `SAFEDI_GRAPH_FUZZER_SEEDS` is a comma-separated list of distinct seeds, such as `98,311,383`, which one process
	/// then runs in place of a process per seed. It replaces the count, the starting seed and the shard, so a list
	/// set beside any of them, an empty list, and a list that repeats a seed or holds anything but seeds also become
	/// zero. A listed run checks no corpus pin, whatever it lists (`coversCorpus(ofSeedCount:)`), and writes a `seeds`
	/// line where a range writes its `shard` line.
	static func configuration(inEnvironment environment: [String: String]) -> GraphFuzzerLongRunConfiguration? {
		let seedList = environment["SAFEDI_GRAPH_FUZZER_SEEDS"]
		guard environment["SAFEDI_GRAPH_FUZZER_ITERATIONS"] != nil || seedList != nil else { return nil }
		let iterations = environment["SAFEDI_GRAPH_FUZZER_ITERATIONS"] ?? ""
		let featureNames = (environment["SAFEDI_GRAPH_FUZZER_FEATURES"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
		let features = featureNames.compactMap(GraphFuzzerGeneratorFeature.init(rawValue:))
		let validFeatures: Set<GraphFuzzerGeneratorFeature>? = features.count == featureNames.count ? Set(features) : nil
		let requestedIterations = iterations == "corpus" ? validFeatures.map { SafeDIToolGraphFuzzerTests.corpus(for: $0).seedCount } ?? 0 : Int(iterations) ?? 0
		let requestedStartingSeed = environment["SAFEDI_GRAPH_FUZZER_STARTING_SEED"].flatMap { UInt64($0) } ?? 0
		let seeds: (startingSeed: UInt64, iterations: Int)
		var listedSeeds: [UInt64]?
		if let seedList {
			let listed = seedList.split(separator: ",", omittingEmptySubsequences: false).map { UInt64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
			let namesNoOtherSeeds = ["SAFEDI_GRAPH_FUZZER_ITERATIONS", "SAFEDI_GRAPH_FUZZER_STARTING_SEED", "SAFEDI_GRAPH_FUZZER_SHARD"].allSatisfy { environment[$0] == nil }
			let valid = listed.compactMap(\.self)
			if namesNoOtherSeeds, valid.count == listed.count, Set(valid).count == valid.count, let first = valid.first {
				seeds = (first, valid.count)
				listedSeeds = valid
			} else {
				seeds = (requestedStartingSeed, 0)
			}
		} else if let shardDescription = environment["SAFEDI_GRAPH_FUZZER_SHARD"] {
			let parts = shardDescription.split(separator: "/", omittingEmptySubsequences: false).map { Int($0) }
			if parts.count == 2, let index = parts[0], let count = parts[1], let shard = shard(index, of: count, startingSeed: requestedStartingSeed, iterations: requestedIterations) {
				seeds = shard
			} else {
				seeds = (requestedStartingSeed, 0)
			}
		} else {
			seeds = (requestedStartingSeed, requestedIterations)
		}
		return GraphFuzzerLongRunConfiguration(
			iterations: seeds.iterations,
			startingSeed: seeds.startingSeed,
			listedSeeds: listedSeeds,
			namesSeedList: seedList != nil,
			features: validFeatures,
			reportPath: environment["SAFEDI_GRAPH_FUZZER_REPORT"],
		)
	}

	/// The run's seed at `offset`, which is in `0..<iterations`.
	func seed(at offset: Int) -> UInt64 {
		if let listedSeeds {
			listedSeeds[offset]
		} else {
			startingSeed &+ UInt64(offset)
		}
	}

	/// Whether the run is of the whole corpus of `seedCount` seeds, whose pins it then checks: consecutive seeds from
	/// zero. Listed seeds never are, in whatever order and number, so that a list's order does not decide it.
	func coversCorpus(ofSeedCount seedCount: Int) -> Bool {
		listedSeeds == nil && startingSeed == 0 && iterations == seedCount
	}

	/// What the run reports when its settings name no seed.
	var noSeedsProblem: String {
		if namesSeedList {
			"SAFEDI_GRAPH_FUZZER_SEEDS must be a comma-separated list of distinct seeds, set without SAFEDI_GRAPH_FUZZER_ITERATIONS, SAFEDI_GRAPH_FUZZER_STARTING_SEED or SAFEDI_GRAPH_FUZZER_SHARD."
		} else {
			"SAFEDI_GRAPH_FUZZER_ITERATIONS must be a positive integer or `corpus`, and SAFEDI_GRAPH_FUZZER_SHARD, when set, `<index>/<count>` naming a shard with at least one seed."
		}
	}

	/// What the report's line of accepted graphs begins with: `shard <starting seed> <count>` for consecutive seeds,
	/// which `ci.yml`'s combine job adds up, or `seeds <seed>,<seed>…` for listed ones, which belong to no shard.
	var seedsReportFields: String {
		if let listedSeeds {
			"seeds \(listedSeeds.map(String.init).joined(separator: ","))"
		} else {
			"shard \(startingSeed) \(iterations)"
		}
	}

	/// The seeds of shard `index` of `count` consecutive shards of the `iterations` seeds from `startingSeed`, the earlier
	/// shards one seed longer when `count` does not divide `iterations`; `nil` unless `index` is in `0..<count`.
	static func shard(_ index: Int, of count: Int, startingSeed: UInt64, iterations: Int) -> (startingSeed: UInt64, iterations: Int)? {
		guard count > 0, (0..<count).contains(index) else { return nil }
		let shortShardLength = iterations / count
		let longShardCount = iterations % count
		let offset = index * shortShardLength + min(index, longShardCount)
		return (startingSeed &+ UInt64(offset), shortShardLength + (index < longShardCount ? 1 : 0))
	}
}

/// An append-only progress log. Each line is written as it happens, so the log survives a crash of the process.
/// Batches run concurrently, so appends are serialized.
final class GraphFuzzerReport: Sendable {
	init(path: String?) {
		self.path = path
	}

	let path: String?

	func append(_ line: String) {
		guard let path else { return }
		lock.withLock {
			if !FileManager.default.fileExists(atPath: path) {
				FileManager.default.createFile(atPath: path, contents: nil)
			}
			guard let fileHandle = FileHandle(forWritingAtPath: path) else { return }
			defer { try? fileHandle.close() }
			_ = try? fileHandle.seekToEnd()
			try? fileHandle.write(contentsOf: Data((line + "\n").utf8))
		}
	}

	private let lock = NSLock()
}

/// A comparison of a seam graph's values whose known issues are documented difference by difference
/// (`GraphFuzzerKnownIssue.matches(_:)`), for the tests that hold for each.
enum ValueComparisonUnderTest: CaseIterable {
	/// The seam build against the inline build (`seamBuildsOtherValuesThanInline`).
	case seamAgainstInline
	/// The build that fills a hole against its visible build (`holeBuildsOtherValuesThanVisibleBuild`).
	case holeAgainstVisibleBuild

	/// The kind of the failure the comparison reports.
	var failureKind: GraphFuzzerFailure.Kind {
		switch self {
		case .seamAgainstInline: .seamBuildsOtherValuesThanInline
		case .holeAgainstVisibleBuild: .holeBuildsOtherValuesThanVisibleBuild
		}
	}

	/// The other comparison, which a graph with a hole runs beside this one.
	var other: ValueComparisonUnderTest {
		switch self {
		case .seamAgainstInline: .holeAgainstVisibleBuild
		case .holeAgainstVisibleBuild: .seamAgainstInline
		}
	}

	/// The signature that documents a difference of this comparison whose description contains `text`.
	func signature(containing text: String) -> GraphFuzzerKnownIssue.Signature {
		switch self {
		case .seamAgainstInline: .seamBuildsOtherValuesThanInline(containing: text)
		case .holeAgainstVisibleBuild: .holeBuildsOtherValuesThanVisibleBuild(containing: text)
		}
	}
}

private enum GraphFuzzerTestError: Error {
	case noSmokeGraphPassesValueForOnlyIfAvailableParameter
	/// Seed 1637 is no longer accepted with its hole, as its visible build and inline.
	case cycleSeedIsNoLongerAcceptedEveryWay
}

/// Extensions a generated configuration file might hold, for the tests of how a renamed graph's files are compared.
private enum PublicConfiguration {
	static let firstStruct = "/// Configuration for how `S12_T0` is constructed within the public mock trees of this module.\npublic struct S12_T0Configuration {\n}"
	static let firstExtension = "extension S12_T0 {\n    static func make() {}\n}"
	static let first = "\(firstStruct)\n\n\(firstExtension)"
	static let secondStruct = "/// Configuration for how `S12_T1` is constructed within the public mock trees of this module.\npublic struct S12_T1Configuration {\n}"
	static let secondExtension = "extension S12_T1 {\n    static func make() {}\n}"
}

private enum GeneratedExtension {
	static let first = "extension S12_T0 {\n    static let a = 1\n}\n"
	static let changedFirst = "extension S12_T0 {\n    static let a = 2\n}\n"
	static let second = "extension S12_T1 {\n    static let b = 1\n}\n"
	static let third = "extension S12_T2 {\n    static let c = 1\n}\n"
	static let fourth = "extension S12_T3 {\n    static let d = 1\n}\n"
}

/// What a `valuesInOrder` test's element throws.
private struct ElementFailure: Error, CustomStringConvertible {
	let description: String
}

/// The elements a `valuesInOrder` test's closure was called with, in the order of the calls.
private actor StartedElements {
	private(set) var elements = [Int]()

	func append(_ element: Int) {
		elements.append(element)
	}
}
