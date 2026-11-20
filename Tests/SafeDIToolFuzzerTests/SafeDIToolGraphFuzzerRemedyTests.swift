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
@testable import SafeDIToolTestSupport

/// The base corpus's remedy oracle: each remedy a rejected graph's error states, applied to the graph's declarations,
/// must leave no error where the error was. One representative graph per remedy, each written as the fuzzer writes a
/// graph. See "Remedy oracle" in `.claude/rules/fuzzer-remedy-oracle.md`.
struct SafeDIToolGraphFuzzerRemedyTests {
	// MARK: Remedies

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_declareReceivedPropertyOnRootAndLeaveNoErrorAtTheReceive_whenNoTypeInTheChainInstantiatesIt() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1) {
					self.t1 = t1
				}

				@Instantiated let t1: S1_T1
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Received let t2: S1_T2
			}
			""",
			Self.leaf("S1_T2"),
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.instantiateOnRoot])
		#expect(runs.first?.remedy.fixture.swiftFileContent.first == """
		@Instantiable(isRoot: true)
		public final class S1_Root0: Instantiable {
			public init(t1: S1_T1, t2: S1_T2) {
				self.t1 = t1
				self.t2 = t2
			}

			@Instantiated let t1: S1_T1
			@Instantiated let t2: S1_T2
		}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_receiveOnlyIfAvailableAndLeaveNoErrorAtTheReceive_whenOnlyTheNonOptionalFormIsInTheChain() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1, t2: S1_T2) {
					self.t1 = t1
					self.t2 = t2
				}

				@Instantiated let t1: S1_T1
				@Instantiated let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2?) {
					self.t2 = t2
				}

				@Received let t2: S1_T2?
			}
			""",
			Self.leaf("S1_T2"),
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.receiveOnlyIfAvailable])
		#expect(runs.first?.remedy.fixture.swiftFileContent[1] == """
		@Instantiable
		public final class S1_T1: Instantiable {
			public init(t2: S1_T2?) {
				self.t2 = t2
			}

			@Received(onlyIfAvailable: true) let t2: S1_T2?
		}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_receiveEachSuggestedPropertyAndLeaveNoErrorAtTheReceive_whenTheChainHoldsTwoPropertiesOfTheReceivedType() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1, t2: S1_T2, t3: S1_T2) {
					self.t1 = t1
					self.t2 = t2
					self.t3 = t3
				}

				@Instantiated let t1: S1_T1
				@Instantiated let t2: S1_T2
				@Instantiated let t3: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t4: S1_T2, title: String = "") {
					self.t4 = t4
				}

				@Received let t4: S1_T2
			}
			""",
			Self.leaf("S1_T2"),
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.receiveSuggestedProperty, .receiveSuggestedProperty])
		#expect(runs.map { $0.remedy.fixture.swiftFileContent[1] } == ["t2", "t3"].map { label in
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(\(label): S1_T2, title: String = "") {
					self.\(label) = \(label)
				}

				@Received let \(label): S1_T2
			}
			"""
		})
		#expect(runs.map(\.errorsAtSite) == [[], []])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_makeTheClosingDependencyAnInstantiatorAndLeaveNoErrorAtIt_whenAConstantCycleHasNoInstantiator() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1) {
					self.t1 = t1
				}

				@Instantiated let t1: S1_T1
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Instantiated let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(t1: S1_T1) {
					self.t1 = t1
				}

				@Instantiated let t1: S1_T1
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.instantiateAsInstantiator])
		#expect(runs.first?.remedy.fixture.swiftFileContent[2] == """
		@Instantiable
		public final class S1_T2: Instantiable {
			public init(t1: Instantiator<S1_T1>) {
				self.t1 = t1
			}

			@Instantiated let t1: Instantiator<S1_T1>
		}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_removeTheReceiveOrReceiveItOptionallyAndLeaveNoErrorAtIt_whenAReceiveClosesACycle() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1) {
					self.t1 = t1
				}

				@Instantiated let t1: S1_T1
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Instantiated let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(t1: S1_T1) {
					self.t1 = t1
				}

				@Received let t1: S1_T1
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.removeReceive, .receiveOptionallyIfAvailable])
		#expect(runs.map { $0.remedy.fixture.swiftFileContent[2] } == [
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init() {}
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(t1: S1_T1?) {
					self.t1 = t1
				}

				@Received(onlyIfAvailable: true) let t1: S1_T1?
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[], []])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_declareReceivedPropertyOnRootAndReceiveItOnlyIfAvailableAndLeaveNoErrorAtTheReceive_whenNoTypeInTheChainInstantiatesARequiredOptionalReceive() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1) {
					self.t1 = t1
				}

				@Instantiated let t1: S1_T1
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2?) {
					self.t2 = t2
				}

				@Received let t2: S1_T2?
			}
			""",
			Self.leaf("S1_T2"),
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.instantiateOnRootAndReceiveOnlyIfAvailable])
		#expect(runs.first.map { Array($0.remedy.fixture.swiftFileContent.prefix(2)) } == [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1, t2: S1_T2) {
					self.t1 = t1
					self.t2 = t2
				}

				@Instantiated let t1: S1_T1
				@Instantiated let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2?) {
					self.t2 = t2
				}

				@Received(onlyIfAvailable: true) let t2: S1_T2?
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_removeTheReceiveOrReceiveItOptionallyAndLeaveNoErrorAtIt_whenDeclaringTheReceivedPropertyWouldCloseACycle() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Instantiated let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Instantiated let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(t1: S1_T1) {
					self.t1 = t1
				}

				@Received let t1: S1_T1
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.removeReceive, .receiveOptionallyIfAvailable])
		#expect(runs.map { $0.remedy.fixture.swiftFileContent[2] } == [
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init() {}
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(t1: S1_T1?) {
					self.t1 = t1
				}

				@Received(onlyIfAvailable: true) let t1: S1_T1?
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[], []])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_declareTheProvidingFormOnTheSeamAndLeaveNoErrorAtTheSeam_whenItsTreeReceivesALabelOptionallyAndAsItsNonOptionalForm() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.seamFormsGraph(seamAttribute: "@Received(onlyIfAvailable: true)", seamType: "S1_User?"))

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.declareProvidingFormOnSeam])
		#expect(runs.first?.remedy.fixture.swiftFileContent[1] == """
		@Instantiable(generateDependencyTree: true)
		public final class S1_Seam: Instantiable {
			public init(user: S1_User, child: S1_Child) {
				self.user = user
				self.child = child
			}

			@Received let user: S1_User
			@Instantiated let child: S1_Child
		}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_applyNoRemedyAtTheSeam_whenItsTreeRequiresAnOptionalFormOfTheLabel() async throws {
		// A required receive of an optional is not a shape an adopter writes, so its pair is not judged.
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(hostBuilder: Instantiator<S1_Host>) {
					self.hostBuilder = hostBuilder
				}

				@Instantiated let hostBuilder: Instantiator<S1_Host>
			}
			""",
			"""
			@Instantiable
			public final class S1_Host: Instantiable {
				public init(user: LazilyInstantiated<S1_User>?, seam: S1_Seam) {
					self.user = user
					self.seam = seam
				}

				@Forwarded let user: LazilyInstantiated<S1_User>?
				@Instantiated let seam: S1_Seam
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class S1_Seam: Instantiable {
				public init(user: S1_User?, child: S1_Child) {
					self.user = user
					self.child = child
				}

				@Received(onlyIfAvailable: true) let user: S1_User?
				@Instantiated let child: S1_Child
			}
			""",
			"""
			@Instantiable
			public final class S1_Child: Instantiable {
				public init(user: LazilyInstantiated<S1_User>?) {
					self.user = user
				}

				@Received let user: LazilyInstantiated<S1_User>?
			}
			""",
			Self.leaf("S1_User"),
		])

		let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
		let runs = try await GraphFuzzerOracle.remedyRuns(of: fixture, outcome: outcome)

		#expect(runs.isEmpty)
		guard case let .rejected(diagnostics) = outcome else {
			Issue.record("The tool accepts the graph:\n\(outcome.description)")
			return
		}
		// The site is read, and counted as one the oracle leaves.
		#expect(GraphFuzzerRemedies.unremediedSiteCount(of: fixture, diagnostics: diagnostics) == 1)
	}

	// MARK: Known issues

	// The minimal graph of each shape `SafeDIToolGraphFuzzerTests.knownIssues` records under `remedyLeavesErrorAtSite`:
	// advice that does not fix its error. Each expects the advice to work, as a known issue, so fixing the diagnostic fails
	// the test until its known issue goes.

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_relabelTheHidingDeclarationAndLeaveNoErrorAtTheReceive_whenACloserTypeDeclaresTheReceivedLabelWithAnotherType() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1, t2: S1_T2) {
					self.t1 = t1
					self.t2 = t2
				}

				@Instantiated let t1: S1_T1
				@Instantiated let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T4, t3: S1_T3) {
					self.t2 = t2
					self.t3 = t3
				}

				@Instantiated let t2: S1_T4
				@Instantiated let t3: S1_T3
			}
			""",
			Self.leaf("S1_T2"),
			"""
			@Instantiable
			public final class S1_T3: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Received let t2: S1_T2
			}
			""",
			Self.leaf("S1_T4"),
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.relabelHidingDeclaration])
		#expect(runs.first?.remedy.fixture.swiftFileContent[1] == """
		@Instantiable
		public final class S1_T1: Instantiable {
			public init(t2Relabeled: S1_T4, t3: S1_T3) {
				self.t2Relabeled = t2Relabeled
				self.t3 = t3
			}

			@Instantiated let t2Relabeled: S1_T4
			@Instantiated let t3: S1_T3
		}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_applyNoRemedyAtTheReceive_whenTheHiddenReceiveIsARequiredOptional() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(hostBuilder: Instantiator<S1_Host>) {
					self.hostBuilder = hostBuilder
				}

				@Instantiated let hostBuilder: Instantiator<S1_Host>
			}
			""",
			"""
			@Instantiable
			public final class S1_Host: Instantiable {
				public init(t2: S1_T2?, t1: S1_T1) {
					self.t2 = t2
					self.t1 = t1
				}

				@Forwarded let t2: S1_T2?
				@Instantiated let t1: S1_T1
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T4, t3: S1_T3) {
					self.t2 = t2
					self.t3 = t3
				}

				@Instantiated let t2: S1_T4
				@Instantiated let t3: S1_T3
			}
			""",
			Self.leaf("S1_T2"),
			"""
			@Instantiable
			public final class S1_T3: Instantiable {
				public init(t2: S1_T2?) {
					self.t2 = t2
				}

				@Received let t2: S1_T2?
			}
			""",
			Self.leaf("S1_T4"),
		])
		let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
		guard case let .rejected(diagnostics) = outcome else {
			Issue.record("The tool accepts the graph:\n\(outcome.description)")
			return
		}

		let runs = try await GraphFuzzerOracle.remedyRuns(of: fixture, outcome: outcome)

		#expect(runs.isEmpty)
		#expect(GraphFuzzerRemedies.unremediedSiteCount(of: fixture, diagnostics: diagnostics) == 1)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_leaveNoErrorAtTheReceive_whenTwoTypesAlongTheChainDeclareTheReceivedLabelWithOtherTypes() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1, t3: S1_T3) {
					self.t1 = t1
					self.t3 = t3
				}

				@Instantiated let t1: S1_T1
				@Instantiated let t3: S1_T3
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t3: S1_T4, t2: S1_T2) {
					self.t3 = t3
					self.t2 = t2
				}

				@Instantiated let t3: S1_T4
				@Instantiated let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(t3: S1_T5, t0: S1_T0) {
					self.t3 = t3
					self.t0 = t0
				}

				@Instantiated let t3: S1_T5
				@Instantiated let t0: S1_T0
			}
			""",
			"""
			@Instantiable
			public final class S1_T0: Instantiable {
				public init(t3: S1_T3) {
					self.t3 = t3
				}

				@Received let t3: S1_T3
			}
			""",
			Self.leaf("S1_T3"),
			Self.leaf("S1_T4"),
			Self.leaf("S1_T5"),
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.relabelHidingDeclaration])
		withKnownIssue("\(SafeDIToolGraphFuzzerTests.remedyHiddenByEachDeclarationAlongTheChainReason)") {
			#expect(runs.map(\.errorsAtSite) == [[]])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_declareReceivedPropertyOnRootInItsOwnModuleAndLeaveNoErrorAtTheReceive_whenTheReceiverIsInAnotherModule() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1) {
					self.t1 = t1
				}

				@Instantiated let t1: S1_T1
			}
			""",
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Received let t2: S1_T2
			}
			""",
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_T2: Instantiable {
				public init() {}
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.instantiateOnRoot])
		#expect(runs.first?.remedy.fixture.swiftFileContent == [
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1, t2: S1_T2) {
					self.t1 = t1
					self.t2 = t2
				}

				@Instantiated let t1: S1_T1
				@Instantiated let t2: S1_T2
			}
			""",
		] + fixture.swiftFileContent.dropFirst())
		#expect(runs.first?.remedy.fixture.modules?.map(\.name) == fixture.modules?.map(\.name))
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_defaultTheMockParameterOrMoveTheMockIntoTheClauseAndLeaveNoErrorAtTheDependency_whenAMockTakesADependencyOfAnInactiveClause() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(guardedHost: S1_GuardedHost) {
					self.guardedHost = guardedHost
				}

				@Instantiated let guardedHost: S1_GuardedHost
			}
			""",
			"""
			@Instantiable(generateMock: true)
			public final class S1_GuardedHost: Instantiable {
				public init(guarded: S1_Guarded) {
					self.guarded = guarded
				}

				@Instantiated let guarded: S1_Guarded
			}
			""",
			"""
			@Instantiable
			public final class S1_Guarded: Instantiable {
				#if FUZZ_OTHER
				public init() {}
				#elseif FUZZ_GUARD
				public init(guardedValue: S1_GuardedValue) {
					self.guardedValue = guardedValue
				}

				@Instantiated let guardedValue: S1_GuardedValue
				#else
				public init() {}
				#endif

				#if DEBUG
				public static func mock(guardedValue: S1_GuardedValue) -> S1_Guarded {
					#if FUZZ_OTHER
					S1_Guarded()
					#elseif FUZZ_GUARD
					S1_Guarded(guardedValue: guardedValue)
					#else
					S1_Guarded()
					#endif
				}
				#endif
			}
			""",
			Self.leaf("S1_GuardedValue"),
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.defaultMockParameter, .moveMockIntoClause])
		#expect(runs.first?.remedy.fixture.swiftFileContent[2] == """
		@Instantiable
		public final class S1_Guarded: Instantiable {
			#if FUZZ_OTHER
			public init() {}
			#elseif FUZZ_GUARD
			public init(guardedValue: S1_GuardedValue) {
				self.guardedValue = guardedValue
			}

			@Instantiated let guardedValue: S1_GuardedValue
			#else
			public init() {}
			#endif

			#if DEBUG
			public static func mock(guardedValue: S1_GuardedValue = S1_GuardedValue()) -> S1_Guarded {
				#if FUZZ_OTHER
				S1_Guarded()
				#elseif FUZZ_GUARD
				S1_Guarded(guardedValue: guardedValue)
				#else
				S1_Guarded()
				#endif
			}
			#endif
		}
		""")
		#expect(runs.last?.remedy.fixture.swiftFileContent[2] == """
		@Instantiable
		public final class S1_Guarded: Instantiable {
			#if FUZZ_OTHER
			public init() {}
			#elseif FUZZ_GUARD
			public init(guardedValue: S1_GuardedValue) {
				self.guardedValue = guardedValue
			}

			@Instantiated let guardedValue: S1_GuardedValue

			#if DEBUG
			public static func mock(guardedValue: S1_GuardedValue) -> S1_Guarded {
				#if FUZZ_OTHER
				S1_Guarded()
				#elseif FUZZ_GUARD
				S1_Guarded(guardedValue: guardedValue)
				#else
				S1_Guarded()
				#endif
			}
			#endif
			#else
			public init() {}
			#endif
		}
		""")
		#expect(runs.map(\.errorsAtSite) == [[], []])
		#expect(runs.map {
			if case .accepted = $0.outcome {
				true
			} else {
				false
			}
		} == [true, true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_defaultTheMockParameterOnlyAndLeaveNoErrorAtTheDependency_whenTheInactiveClauseHoldsTheDependencyInANestedBlock() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(guarded: S1_Guarded) {
					self.guarded = guarded
				}

				@Instantiated let guarded: S1_Guarded
			}
			""",
			"""
			@Instantiable(generateMock: true, customMockName: "customMock")
			public final class S1_Guarded: Instantiable {
				#if FUZZ_GUARD
				#if FUZZ_INNER
				public init(guardedValue: S1_GuardedValue) {
					self.guardedValue = guardedValue
				}

				@Received let guardedValue: S1_GuardedValue
				#else
				public init() {}
				#endif
				#else
				public init() {}
				#endif

				#if DEBUG
				public static func customMock(guardedValue: S1_GuardedValue) -> S1_Guarded {
					#if FUZZ_GUARD
					#if FUZZ_INNER
					S1_Guarded(guardedValue: guardedValue)
					#else
					S1_Guarded()
					#endif
					#else
					S1_Guarded()
					#endif
				}
				#endif
			}
			""",
			Self.leaf("S1_GuardedValue"),
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.defaultMockParameter])
		#expect(runs.first?.remedy.fixture.swiftFileContent[1] == """
		@Instantiable(generateMock: true, customMockName: "customMock")
		public final class S1_Guarded: Instantiable {
			#if FUZZ_GUARD
			#if FUZZ_INNER
			public init(guardedValue: S1_GuardedValue) {
				self.guardedValue = guardedValue
			}

			@Received let guardedValue: S1_GuardedValue
			#else
			public init() {}
			#endif
			#else
			public init() {}
			#endif

			#if DEBUG
			public static func customMock(guardedValue: S1_GuardedValue = S1_GuardedValue()) -> S1_Guarded {
				#if FUZZ_GUARD
				#if FUZZ_INNER
				S1_Guarded(guardedValue: guardedValue)
				#else
				S1_Guarded()
				#endif
				#else
				S1_Guarded()
				#endif
			}
			#endif
		}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
		#expect(runs.map {
			if case .accepted = $0.outcome {
				true
			} else {
				false
			}
		} == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_keepEachFulfillerInTurnAndLeaveNoErrorAtItsDeclaration_whenTwoDeclarationsFulfillOneType() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t7: S1_T7, t8: S1_T8) {
					self.t7 = t7
					self.t8 = t8
				}

				@Instantiated let t7: S1_T7
				@Instantiated let t8: S1_T8
			}
			""",
			"""
			@Instantiable(fulfillingAdditionalTypes: [S1_T7Protocol.self])
			public final class S1_T7: Instantiable, S1_T7Protocol {
				public init() {}
			}

			public protocol S1_T7Protocol: AnyObject {}

			public final class S1_AnyT7 {
				public init(_ value: S1_T7) {
					self.value = value
				}

				public let value: S1_T7
			}
			""",
			"""
			@Instantiable(fulfillingAdditionalTypes: [S1_T7Protocol.self])
			public final class S1_T8: Instantiable, S1_T8Protocol, S1_T7Protocol {
				public init() {}
			}

			public protocol S1_T8Protocol: AnyObject {}

			public final class S1_AnyT8 {
				public init(_ value: S1_T8) {
					self.value = value
				}

				public let value: S1_T8
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.keepOneFulfiller, .keepOneFulfiller])
		#expect(runs.map(\.remedy.site.typeName) == ["S1_T7", "S1_T8"])
		#expect(runs.first?.remedy.fixture.swiftFileContent.dropFirst() == [
			"""
			@Instantiable(fulfillingAdditionalTypes: [S1_T7Protocol.self])
			public final class S1_T7: Instantiable, S1_T7Protocol {
				public init() {}
			}

			public protocol S1_T7Protocol: AnyObject {}

			public final class S1_AnyT7 {
				public init(_ value: S1_T7) {
					self.value = value
				}

				public let value: S1_T7
			}
			""",
			"""
			@Instantiable
			public final class S1_T8: Instantiable, S1_T8Protocol, S1_T7Protocol {
				public init() {}
			}

			public protocol S1_T8Protocol: AnyObject {}

			public final class S1_AnyT8 {
				public init(_ value: S1_T8) {
					self.value = value
				}

				public let value: S1_T8
			}
			""",
		])
		#expect(runs.last?.remedy.fixture.swiftFileContent.dropFirst() == [
			"""
			@Instantiable
			public final class S1_T7: Instantiable, S1_T7Protocol {
				public init() {}
			}

			public protocol S1_T7Protocol: AnyObject {}

			public final class S1_AnyT7 {
				public init(_ value: S1_T7) {
					self.value = value
				}

				public let value: S1_T7
			}
			""",
			"""
			@Instantiable(fulfillingAdditionalTypes: [S1_T7Protocol.self])
			public final class S1_T8: Instantiable, S1_T8Protocol, S1_T7Protocol {
				public init() {}
			}

			public protocol S1_T8Protocol: AnyObject {}

			public final class S1_AnyT8 {
				public init(_ value: S1_T8) {
					self.value = value
				}

				public let value: S1_T8
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[], []])
		#expect(runs.map {
			if case .accepted = $0.outcome {
				true
			} else {
				false
			}
		} == [true, true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_decorateTheTypeAndLeaveNoErrorAtTheProperty_whenNoDeclarationFulfillsAnInstantiatedType() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(missing0: S1_Missing0) {
					self.missing0 = missing0
				}

				@Instantiated let missing0: S1_Missing0
			}

			public final class S1_Missing0 {}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.decorateType])
		#expect(runs.first?.remedy.fixture.swiftFileContent == [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(missing0: S1_Missing0) {
					self.missing0 = missing0
				}

				@Instantiated let missing0: S1_Missing0
			}

			@Instantiable
			public final class S1_Missing0: Instantiable {
				public init() {}
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
		#expect(runs.map {
			if case .accepted = $0.outcome {
				true
			} else {
				false
			}
		} == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_declareTheBuilderAndItsReceiveAsTheSendableWrapperAndLeaveNoErrorAtTheReceive_whenASendableBuilderFunctionCapturesABuilderThatIsNotSendable() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1Builder: SendableInstantiator<S1_T1>, t2Builder: Instantiator<S1_T2>) {
					self.t1Builder = t1Builder
					self.t2Builder = t2Builder
				}

				@Instantiated let t1Builder: SendableInstantiator<S1_T1>
				@Instantiated let t2Builder: Instantiator<S1_T2>
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2Builder: Instantiator<S1_T2>) {
					self.t2Builder = t2Builder
				}

				@Received let t2Builder: Instantiator<S1_T2>
			}
			""",
			Self.leaf("S1_T2"),
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.declareAsSendableWrapper])
		#expect(runs.first?.remedy.fixture.swiftFileContent.dropLast() == [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1Builder: SendableInstantiator<S1_T1>, t2Builder: SendableInstantiator<S1_T2>) {
					self.t1Builder = t1Builder
					self.t2Builder = t2Builder
				}

				@Instantiated let t1Builder: SendableInstantiator<S1_T1>
				@Instantiated let t2Builder: SendableInstantiator<S1_T2>
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2Builder: SendableInstantiator<S1_T2>) {
					self.t2Builder = t2Builder
				}

				@Received let t2Builder: SendableInstantiator<S1_T2>
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
		#expect(runs.map {
			if case .accepted = $0.outcome {
				true
			} else {
				false
			}
		} == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_declareOnlyTheLazyPropertyAsTheSendableWrapperAndLeaveNoErrorAtTheReceive_whenASendableBuilderFunctionCapturesItsInstance() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1Builder: SendableInstantiator<S1_T1>, t2: LazilyInstantiated<S1_T2>) {
					self.t1Builder = t1Builder
					self.t2 = t2
				}

				@Instantiated let t1Builder: SendableInstantiator<S1_T1>
				@Instantiated let t2: LazilyInstantiated<S1_T2>
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Received let t2: S1_T2
			}
			""",
			Self.leaf("S1_T2"),
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.declareAsSendableWrapper])
		#expect(runs.first?.remedy.fixture.swiftFileContent.dropLast() == [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1Builder: SendableInstantiator<S1_T1>, t2: SendableLazilyInstantiated<S1_T2>) {
					self.t1Builder = t1Builder
					self.t2 = t2
				}

				@Instantiated let t1Builder: SendableInstantiator<S1_T1>
				@Instantiated let t2: SendableLazilyInstantiated<S1_T2>
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Received let t2: S1_T2
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
		#expect(runs.map {
			if case .accepted = $0.outcome {
				true
			} else {
				false
			}
		} == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_forwardTheReceiveAndLeaveNoErrorAtIt_whenAnInstantiatorBuildsTheReceiverOfATypeOnlyAnInstantiatorBuilds() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1Builder: Instantiator<S1_T1>) {
					self.t1Builder = t1Builder
				}

				@Instantiated let t1Builder: Instantiator<S1_T1>
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Received let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(seed: Int) {
					self.seed = seed
				}

				@Forwarded let seed: Int
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.forwardReceive])
		#expect(runs.first?.remedy.fixture.swiftFileContent == [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1Builder: Instantiator<S1_T1>) {
					self.t1Builder = t1Builder
				}

				@Instantiated let t1Builder: Instantiator<S1_T1>
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Forwarded let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(seed: Int) {
					self.seed = seed
				}

				@Forwarded let seed: Int
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
		#expect(runs.map {
			if case .accepted = $0.outcome {
				true
			} else {
				false
			}
		} == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_forwardTheReceiveAndDeclareTheReceiverAsTheInstantiatorTheNextErrorStates_whenAConstantBuildsTheReceiver() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1) {
					self.t1 = t1
				}

				@Instantiated let t1: S1_T1
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Received let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(seed: Int) {
					self.seed = seed
				}

				@Forwarded let seed: Int
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.forwardReceive])
		#expect(runs.first?.remedy.fixture.swiftFileContent == [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: Instantiator<S1_T1>) {
					self.t1 = t1
				}

				@Instantiated let t1: Instantiator<S1_T1>
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Forwarded let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(seed: Int) {
					self.seed = seed
				}

				@Forwarded let seed: Int
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
		#expect(runs.map {
			if case .accepted = $0.outcome {
				true
			} else {
				false
			}
		} == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_forwardTheReceiveAndDeclareTheErasedInstantiatorTheNextErrorStates_whenAnErasedInstantiatorThatTakesNothingBuildsTheReceiver() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1Builder: ErasedInstantiator<(), S1_AnyT1>) {
					self.t1Builder = t1Builder
				}

				@Instantiated(fulfilledByType: "S1_T1", erasedToConcreteExistential: true) let t1Builder: ErasedInstantiator<(), S1_AnyT1>
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Received let t2: S1_T2
			}

			public final class S1_AnyT1 {
				public init(_ value: S1_T1) {
					self.value = value
				}

				public let value: S1_T1
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(seed: Int) {
					self.seed = seed
				}

				@Forwarded let seed: Int
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.forwardReceive])
		#expect(runs.first?.remedy.fixture.swiftFileContent == [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1Builder: ErasedInstantiator<S1_T2, S1_AnyT1>) {
					self.t1Builder = t1Builder
				}

				@Instantiated(fulfilledByType: "S1_T1", erasedToConcreteExistential: true) let t1Builder: ErasedInstantiator<S1_T2, S1_AnyT1>
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Forwarded let t2: S1_T2
			}

			public final class S1_AnyT1 {
				public init(_ value: S1_T1) {
					self.value = value
				}

				public let value: S1_T1
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(seed: Int) {
					self.seed = seed
				}

				@Forwarded let seed: Int
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
		#expect(runs.map {
			if case .accepted = $0.outcome {
				true
			} else {
				false
			}
		} == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_declareEveryPropertyOfTheLabelAsTheSendableWrapperAndLeaveNoErrorAtTheReceive_whenAMocksTreeReceivesTheBuilderFromOutsideIt() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t0: S1_T0) {
					self.t0 = t0
				}

				@Instantiated let t0: S1_T0
			}
			""",
			"""
			@Instantiable
			public final class S1_T0: Instantiable, @unchecked Sendable {
				public init() {}
			}
			""",
			"""
			@Instantiable(generateMock: true)
			public final class S1_T1: Instantiable, @unchecked Sendable {
				public init(t2Builder: SendableInstantiator<S1_T2>, t0Builder: Instantiator<S1_T0>) {
					self.t2Builder = t2Builder
					self.t0Builder = t0Builder
				}

				@Instantiated let t2Builder: SendableInstantiator<S1_T2>
				@Received let t0Builder: Instantiator<S1_T0>
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable, @unchecked Sendable {
				public init(t0Builder: Instantiator<S1_T0>) {
					self.t0Builder = t0Builder
				}

				@Received let t0Builder: Instantiator<S1_T0>
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.declareAsSendableWrapper])
		#expect(runs.first?.remedy.fixture.swiftFileContent == [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t0: S1_T0) {
					self.t0 = t0
				}

				@Instantiated let t0: S1_T0
			}
			""",
			"""
			@Instantiable
			public final class S1_T0: Instantiable, @unchecked Sendable {
				public init() {}
			}
			""",
			"""
			@Instantiable(generateMock: true)
			public final class S1_T1: Instantiable, @unchecked Sendable {
				public init(t2Builder: SendableInstantiator<S1_T2>, t0Builder: SendableInstantiator<S1_T0>) {
					self.t2Builder = t2Builder
					self.t0Builder = t0Builder
				}

				@Instantiated let t2Builder: SendableInstantiator<S1_T2>
				@Received let t0Builder: SendableInstantiator<S1_T0>
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable, @unchecked Sendable {
				public init(t0Builder: SendableInstantiator<S1_T0>) {
					self.t0Builder = t0Builder
				}

				@Received let t0Builder: SendableInstantiator<S1_T0>
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
		#expect(runs.map {
			if case .accepted = $0.outcome {
				true
			} else {
				false
			}
		} == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_forwardTheReceiveAndLeaveNoErrorAtIt_whenNoDeclarationFulfillsTheReceivedType() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1Builder: Instantiator<S1_T1>) {
					self.t1Builder = t1Builder
				}

				@Instantiated let t1Builder: Instantiator<S1_T1>
			}

			public final class S1_Unbuildable0 {}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_Unbuildable0) {
					self.t2 = t2
				}

				@Received let t2: S1_Unbuildable0
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.forwardReceive])
		#expect(runs.first?.remedy.fixture.swiftFileContent == [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1Builder: Instantiator<S1_T1>) {
					self.t1Builder = t1Builder
				}

				@Instantiated let t1Builder: Instantiator<S1_T1>
			}

			public final class S1_Unbuildable0 {}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_Unbuildable0) {
					self.t2 = t2
				}

				@Forwarded let t2: S1_Unbuildable0
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
		#expect(runs.map {
			if case .accepted = $0.outcome {
				true
			} else {
				false
			}
		} == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_decorateTheTypeKeepingItsSendableConformance_whenTheTypeNoDeclarationFulfillsIsSendable() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(missing0: S1_Missing0) {
					self.missing0 = missing0
				}

				@Instantiated let missing0: S1_Missing0
			}

			public final class S1_Missing0: Sendable {}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.decorateType])
		#expect(runs.first?.remedy.fixture.swiftFileContent == [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(missing0: S1_Missing0) {
					self.missing0 = missing0
				}

				@Instantiated let missing0: S1_Missing0
			}

			@Instantiable
			public final class S1_Missing0: Instantiable, Sendable {
				public init() {}
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
		#expect(runs.map {
			if case .accepted = $0.outcome {
				true
			} else {
				false
			}
		} == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_leaveNoErrorAtTheReceive_whenAnotherRootDeclaresThePropertyTheSendableBuilderCannotCapture() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1Builder: SendableInstantiator<S1_T1>, t2Builder: Instantiator<S1_T2>) {
					self.t1Builder = t1Builder
					self.t2Builder = t2Builder
				}

				@Instantiated let t1Builder: SendableInstantiator<S1_T1>
				@Instantiated let t2Builder: Instantiator<S1_T2>
			}
			""",
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root1: Instantiable {
				public init(t1: S1_T1, t2Builder: Instantiator<S1_T2>) {
					self.t1 = t1
					self.t2Builder = t2Builder
				}

				@Instantiated let t1: S1_T1
				@Instantiated let t2Builder: Instantiator<S1_T2>
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable, @unchecked Sendable {
				public init(t2Builder: Instantiator<S1_T2>) {
					self.t2Builder = t2Builder
				}

				@Received let t2Builder: Instantiator<S1_T2>
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable, @unchecked Sendable {
				public init() {}
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.declareAsSendableWrapper])
		withKnownIssue("\(SafeDIToolGraphFuzzerTests.remedySendableWrapperNamesOneDeclarationReason)") {
			#expect(runs.map(\.errorsAtSite) == [[]])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_leaveNoErrorAtTheReceive_whenTheSuggestedOnlyIfAvailableReceiveIsInsideASendableBuilder() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1Builder: SendableInstantiator<S1_T1>, t2Builder: Instantiator<S1_T2>) {
					self.t1Builder = t1Builder
					self.t2Builder = t2Builder
				}

				@Instantiated let t1Builder: SendableInstantiator<S1_T1>
				@Instantiated let t2Builder: Instantiator<S1_T2>
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2Builder: Instantiator<S1_T2>?) {
					self.t2Builder = t2Builder
				}

				@Received let t2Builder: Instantiator<S1_T2>?
			}
			""",
			Self.leaf("S1_T2"),
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.receiveOnlyIfAvailable])
		withKnownIssue("\(SafeDIToolGraphFuzzerTests.remedyCapturedInSendableBuilderReason)") {
			#expect(runs.map(\.errorsAtSite) == [[]])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_leaveNoErrorAtTheReceive_whenAMockedTypeBetweenDeclaresItsLabelWithAnotherType() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t5: S1_T5) {
					self.t5 = t5
				}

				@Instantiated let t5: S1_T5
			}
			""",
			Self.leaf("S1_T0"),
			Self.leaf("S1_T1"),
			"""
			@Instantiable(generateMock: true)
			public final class S1_T3: Instantiable {
				public init(t4: S1_T1, t5: S1_T5) {
					self.t4 = t4
					self.t5 = t5
				}

				@Instantiated let t4: S1_T1
				@Instantiated let t5: S1_T5
			}
			""",
			"""
			@Instantiable
			public final class S1_T5: Instantiable {
				public init(t4: S1_T0?) {
					self.t4 = t4
				}

				@Received let t4: S1_T0?
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.instantiateOnRootAndReceiveOnlyIfAvailable])
		withKnownIssue("\(SafeDIToolGraphFuzzerTests.remedyHiddenByCloserDeclarationReason)") {
			#expect(runs.map(\.errorsAtSite) == [[]])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_leaveNoErrorAtTheReceive_whenTheSuggestedPropertyIsOfTheMockedReceiversOwnType() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t2Builder: Instantiator<S1_T2>) {
					self.t2Builder = t2Builder
				}

				@Instantiated let t2Builder: Instantiator<S1_T2>
			}
			""",
			"""
			@Instantiable(generateMock: true)
			public final class S1_T1: Instantiable {
				public init(t0: S1_T1) {
					self.t0 = t0
				}

				@Received let t0: S1_T1
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(t0: S1_T1?, t1: S1_T1) {
					self.t0 = t0
					self.t1 = t1
				}

				@Forwarded let t0: S1_T1?
				@Instantiated let t1: S1_T1
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.receiveSuggestedProperty])
		withKnownIssue("\(SafeDIToolGraphFuzzerTests.remedySuggestionClosesCycleReason)") {
			#expect(runs.map(\.errorsAtSite) == [[]])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_leaveNoErrorAtTheReceive_whenTwoPathsToTheReceiverDeclareTheReceivedTypeUnderOtherLabels() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1, t2: S1_T2) {
					self.t1 = t1
					self.t2 = t2
				}

				@Instantiated let t1: S1_T1
				@Instantiated let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t4: S1_T4, t3: S1_T3) {
					self.t4 = t4
					self.t3 = t3
				}

				@Instantiated let t4: S1_T4
				@Instantiated let t3: S1_T3
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(lazyT4: S1_T4, t3: S1_T3) {
					self.lazyT4 = lazyT4
					self.t3 = t3
				}

				@Instantiated let lazyT4: S1_T4
				@Instantiated let t3: S1_T3
			}
			""",
			"""
			@Instantiable
			public final class S1_T3: Instantiable {
				public init(t4: S1_T4) {
					self.t4 = t4
				}

				@Received let t4: S1_T4
			}
			""",
			Self.leaf("S1_T4"),
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.receiveSuggestedProperty])
		withKnownIssue("\(SafeDIToolGraphFuzzerTests.remedySuggestionsAlternateReason)") {
			#expect(runs.map(\.errorsAtSite) == [[]])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_leaveNoErrorAtTheReceive_whenTheDeclaredTypesTreeReceivesARootPropertyThatRequiresTheDeclaration() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Instantiated let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T0: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Received let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(t0Builder: Instantiator<S1_T0>) {
					self.t0Builder = t0Builder
				}

				@Received let t0Builder: Instantiator<S1_T0>
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.instantiateOnRoot])
		withKnownIssue("\(SafeDIToolGraphFuzzerTests.remedyDeclarationClosesCycleThroughRootReason)") {
			#expect(runs.map(\.errorsAtSite) == [[]])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_leaveNoErrorAtTheSeam_whenTheProvidingFormIsAWrapperTheSeamsCallerDoesNotDeclare() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.seamFormsGraph(seamAttribute: "@Received(onlyIfAvailable: true)", seamType: "LazilyInstantiated<S1_User>?"))

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.declareProvidingFormOnSeam])
		withKnownIssue("\(SafeDIToolGraphFuzzerTests.remedySeamProvidingWrapperUndeclaredReason)") {
			#expect(runs.map(\.errorsAtSite) == [[]])
		}
	}

	// MARK: Verdict

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyFailure_reportsEachRemedy_whenTheRemediedGraphKeepsAnErrorAtTheSite() throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1) {
					self.t1 = t1
				}

				@Instantiated let t1: S1_T1
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Received let t2: S1_T2
			}
			""",
			Self.leaf("S1_T2"),
		])
		let error = "@Received property `t2: S1_T2` is not @Instantiated or @Forwarded in chain: S1_Root0 -> S1_T1. Declare `@Instantiated let t2: S1_T2` on `S1_Root0` or on another type in the chain to fix."
		let remedy = try #require(GraphFuzzerRemedies.remedies(of: fixture, diagnostics: "/x/<fixture-directory>/S1_T1.swift:7:2: error: \(error)").first)
		// The remedied graph's receive is on the same line, which a remedy on another file leaves where it was.
		let keptError = "/x/<fixture-directory>/S1_T1.swift:7:2: error: @Received property `t2: S1_T2` is still unfulfilled."
		let otherError = "/x/<fixture-directory>/S1_Root0.swift:7:2: error: Another error at another declaration."
		let runs = GraphFuzzerToolRuns(
			fixture: fixture,
			firstOutcome: .rejected(diagnostics: "/x/<fixture-directory>/S1_T1.swift:7:2: error: \(error)"),
			secondOutcome: .rejected(diagnostics: "/x/<fixture-directory>/S1_T1.swift:7:2: error: \(error)"),
			remedyRuns: [
				GraphFuzzerRemedyRun(remedy: remedy, outcome: .rejected(diagnostics: "\(otherError)\n\(keptError)")),
				GraphFuzzerRemedyRun(remedy: remedy, outcome: .rejected(diagnostics: otherError)),
			],
		)

		let failure = try #require(runs.remedyFailure)

		#expect(failure.kind == .remedyLeavesErrorAtSite)
		#expect(failure.remedyFailures == ["The instantiate-on-root remedy, which declares `@Instantiated let t2: S1_T2` on `S1_Root0`, leaves at `S1_T1.t2` in S1_T1.swift: @Received property `t2: S1_T2` is still unfulfilled."])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func knownIssue_matchesRemedyFailure_onlyWhenEveryRemedyThatLeavesAnErrorMatchesASignatureOfItsKindAndError() {
		let knownIssue = GraphFuzzerKnownIssue(reason: "A remedy that leaves its error", signatures: [.remedyLeavesErrorAtSite(.instantiateOnRoot, containing: "is hidden in chain")], seeds: [1])
		let documented = "The instantiate-on-root remedy, which declares `@Instantiated let t2: S1_T2` on `S1_Root0`, leaves at `S1_T1.t2` in S1_T1.swift: @Received property `t2: S1_T2` is hidden in chain: S1_Root0 -> S1_T1."
		let otherKind = "The remove-receive remedy, which removes `S1_T2.t1` in S1_T2.swift, leaves at `S1_T2.t1` in S1_T2.swift: @Received property `t3: S1_T3` is hidden in chain: S1_Root0 -> S1_T2."
		let otherError = "The instantiate-on-root remedy, which declares `@Instantiated let t3: S1_T3` on `S1_Root0`, leaves at `S1_T1.t3` in S1_T1.swift: Dependency cycle: `S1_T3` -> `S1_T1` -> `S1_T3`."
		func failure(_ remedyFailures: [String]) -> GraphFuzzerFailure {
			GraphFuzzerFailure(seed: 1, kind: .remedyLeavesErrorAtSite, details: remedyFailures.joined(separator: "\n"), remedyFailures: remedyFailures)
		}

		#expect(knownIssue.matches(failure([documented])))
		#expect(!knownIssue.matches(failure([documented, otherKind])))
		#expect(!knownIssue.matches(failure([documented, otherError])))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedies_areNone_whenTheErrorsAtASiteStateOtherRemedies() {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [Self.leaf("S1_Root0"), """
		@Instantiable
		public final class S1_T1: Instantiable {
			public init(t2: S1_T2) {
				self.t2 = t2
			}

			@Received let t2: S1_T2
		}
		"""])
		let declare = "/x/<fixture-directory>/S1_T1.swift:7:2: error: @Received property `t2: S1_T2` is not @Instantiated or @Forwarded in chain: S1_Root0 -> S1_T1. Declare `@Instantiated let t2: S1_T2` on `S1_Root0` or on another type in the chain to fix."
		let suggest = "/x/<fixture-directory>/S1_T1.swift:7:2: error: @Received property `t2: S1_T2` is not @Instantiated or @Forwarded in chain: S1_T3 -> S1_T1. Did you mean `t3: S1_T2`?"

		#expect(GraphFuzzerRemedies.remedies(of: fixture, diagnostics: "\(declare)\n\(suggest)").isEmpty)
		#expect(GraphFuzzerRemedies.unremediedSiteCount(of: fixture, diagnostics: "\(declare)\n\(suggest)") == 1)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func errorsAtSite_listTheErrorForwardingIntroducedAtTheReceiversBuilder_whenTheFollowingRunsLeaveIt() throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t1: S1_T1) {
					self.t1 = t1
				}

				@Instantiated let t1: S1_T1
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2) {
					self.t2 = t2
				}

				@Received let t2: S1_T2
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable {
				public init(seed: Int) {
					self.seed = seed
				}

				@Forwarded let seed: Int
			}
			""",
		])
		let original = "/x/<fixture-directory>/S1_T1.swift:7:2: error: @Received property `t2: S1_T2` is not @Instantiated or @Forwarded in chain: S1_Root0 -> S1_T1. `S1_T2` has @Forwarded properties, so SafeDI builds it only through an `Instantiator`, never as an @Instantiated constant. Declare `@Forwarded let t2: S1_T2` on a type below `S1_Root0` in the chain, and pass the value to the `Instantiator` that builds that type, to fix."
		let remedy = try #require(GraphFuzzerRemedies.remedies(of: fixture, diagnostics: original).first)
		let introduced = "`t1: S1_T1` on `S1_Root0` cannot build `S1_T1`, which has @Forwarded properties that only an instantiator is passed. Declare it as `Instantiator<S1_T1>`."
		// An error about a builder of another type is not the remedy’s to answer for.
		let unrelated = "`t3: S1_T3` on `S1_Root0` cannot build `S1_T3`, which has @Forwarded properties that only an instantiator is passed. Declare it as `Instantiator<S1_T3>`."
		let outcome = GraphFuzzerToolOutcome.rejected(diagnostics: "/x/<fixture-directory>/S1_Root0.swift:7:2: error: \(introduced)\n/x/<fixture-directory>/S1_Root0.swift:7:2: error: \(unrelated)")

		let introducedErrors = GraphFuzzerRemedies.errorsIntroducedByForwarding(remedy, outcome: outcome, originalDiagnostics: original)
		let run = GraphFuzzerRemedyRun(remedy: remedy, outcome: outcome, introducedErrors: introducedErrors)

		#expect(remedy.kind == .forwardReceive)
		#expect(run.errorsAtSite == [introduced])
		#expect(run.failureLine == "The forward-receive remedy, which receives `t2` with `@Forwarded`, leaves at `S1_T1.t2` in S1_T1.swift: \(introduced)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unremediedSiteCount_countsAnErrorOfAFamilyTheOracleReads_whenItIsAtALineThatIsNoPropertyOfAFinalClass() {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(missing0: S1_Missing0) {
					self.missing0 = missing0
				}

				@Instantiated let missing0: S1_Missing0
			}

			public final class S1_Missing0 {}
			""",
		])
		// The error is at the type's attribute, where the oracle reads no site for its family.
		let unplaced = "/x/<fixture-directory>/S1_Root0.swift:1:1: error: No @Instantiable type or extension fulfills `S1_Missing0`, which @Instantiated property `missing0: S1_Missing0` instantiates. Decorate `S1_Missing0`, or an extension of it, with @Instantiable to fix."
		let otherFamily = "/x/<fixture-directory>/S1_Root0.swift:1:1: error: Another error at no property."

		#expect(GraphFuzzerRemedies.remedies(of: fixture, diagnostics: "\(unplaced)\n\(otherFamily)").isEmpty)
		#expect(GraphFuzzerRemedies.unremediedSiteCount(of: fixture, diagnostics: "\(unplaced)\n\(otherFamily)") == 1)
	}

	// MARK: Helpers

	/// A type that declares no property, as the fuzzer writes one.
	private static func leaf(_ name: String) -> String {
		"""
		@Instantiable
		public final class \(name): Instantiable {
			public init() {}
		}
		"""
	}

	/// A root that declares `user: S1_User` and builds a seam, which receives `user: seamType` with `seamAttribute` and
	/// builds a child that requires `user: S1_User`: one label in two forms of one type in the seam's tree.
	private static func seamFormsGraph(seamAttribute: String, seamType: String) -> [String] {
		[
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(user: S1_User, seam: S1_Seam) {
					self.user = user
					self.seam = seam
				}

				@Instantiated let user: S1_User
				@Instantiated let seam: S1_Seam
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class S1_Seam: Instantiable {
				public init(user: \(seamType), child: S1_Child) {
					self.user = user
					self.child = child
				}

				\(seamAttribute) let user: \(seamType)
				@Instantiated let child: S1_Child
			}
			""",
			"""
			@Instantiable
			public final class S1_Child: Instantiable {
				public init(user: S1_User) {
					self.user = user
				}

				@Received let user: S1_User
			}
			""",
			leaf("S1_User"),
		]
	}

	/// The remedy runs of `fixture`, which the tool must reject, and the sites of a family the oracle reads that get none.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func remedyRunsAndUnremediedSiteCount(of fixture: GraphFuzzerFixture) async throws -> ([GraphFuzzerRemedyRun], Int) {
		let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
		guard case let .rejected(diagnostics) = outcome else {
			Issue.record("The tool accepts the graph:\n\(outcome.description)")
			return ([], 0)
		}
		let runs = try await GraphFuzzerOracle.remedyRuns(of: fixture, outcome: outcome)
		return (runs, GraphFuzzerRemedies.unremediedSiteCount(of: fixture, diagnostics: diagnostics))
	}

	/// The remedy runs of `fixture`, which the tool must reject.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func remedyRuns(of fixture: GraphFuzzerFixture) async throws -> [GraphFuzzerRemedyRun] {
		let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
		guard case .rejected = outcome else {
			Issue.record("The tool accepts the graph:\n\(outcome.description)")
			return []
		}
		return try await GraphFuzzerOracle.remedyRuns(of: fixture, outcome: outcome)
	}
}
