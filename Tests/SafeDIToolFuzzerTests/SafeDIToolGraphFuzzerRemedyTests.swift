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
	func remedyRuns_relabelEachHidingDeclarationAndLeaveNoErrorAtTheReceive_whenTwoTypesAlongTheChainDeclareTheReceivedLabelWithOtherTypes() async throws {
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
		#expect(runs.map(\.remedy.description) == ["gives `t3: S1_T5` on `S1_T2` and `t3: S1_T4` on `S1_T1` the label `t3Relabeled`"])
		#expect(runs.first?.remedy.fixture.swiftFileContent[1] == """
		@Instantiable
		public final class S1_T1: Instantiable {
			public init(t3Relabeled: S1_T4, t2: S1_T2) {
				self.t3Relabeled = t3Relabeled
				self.t2 = t2
			}

			@Instantiated let t3Relabeled: S1_T4
			@Instantiated let t2: S1_T2
		}
		""")
		#expect(runs.first?.remedy.fixture.swiftFileContent[2] == """
		@Instantiable
		public final class S1_T2: Instantiable {
			public init(t3Relabeled: S1_T5, t0: S1_T0) {
				self.t3Relabeled = t3Relabeled
				self.t0 = t0
			}

			@Instantiated let t3Relabeled: S1_T5
			@Instantiated let t0: S1_T0
		}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_relabelEveryDeclarationAnyChainNamesAndLeaveNoErrorAtTheReceive_whenTwoPathsToTheReceiveNameDifferentHidingDeclarations() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t3: S1_T3, t1: S1_T1, secondT2: S1_T2) {
					self.t3 = t3
					self.t1 = t1
					self.secondT2 = secondT2
				}

				@Instantiated let t3: S1_T3
				@Instantiated let t1: S1_T1
				@Instantiated let secondT2: S1_T2
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
		let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
		guard case let .rejected(diagnostics) = outcome else {
			Issue.record("The tool accepts the graph:\n\(outcome.description)")
			return
		}

		let runs = try await GraphFuzzerOracle.remedyRuns(of: fixture, outcome: outcome)

		#expect(GraphFuzzerRemedies.errors(at: GraphFuzzerRemedy.Site(fileName: "S1_T0.swift", typeName: "S1_T0", label: "t3"), in: outcome, of: fixture) == [
			"@Received property `t3: S1_T3` is hidden in chain: S1_Root0 -> S1_T1 -> S1_T2 -> S1_T0. `S1_T2` declares `t3: S1_T5` with the same label, so the types below `S1_T2` receive `t3: S1_T5` instead, and above `S1_T2`, `S1_T1` declares `t3: S1_T4` with the same label too. Give `t3: S1_T5` on `S1_T2` and `t3: S1_T4` on `S1_T1` each a different label to fix.",
			"@Received property `t3: S1_T3` is hidden in chain: S1_Root0 -> S1_T2 -> S1_T0. `S1_T2` declares `t3: S1_T5` with the same label, so the types below `S1_T2` receive `t3: S1_T5` instead. Give `t3: S1_T5` on `S1_T2` a different label to fix.",
		])
		#expect(runs.map(\.remedy.kind) == [.relabelHidingDeclaration])
		#expect(runs.map(\.remedy.description) == ["gives `t3: S1_T5` on `S1_T2` and `t3: S1_T4` on `S1_T1` the label `t3Relabeled`"])
		#expect(runs.first?.remedy.fixture.swiftFileContent[1] == """
		@Instantiable
		public final class S1_T1: Instantiable {
			public init(t3Relabeled: S1_T4, t2: S1_T2) {
				self.t3Relabeled = t3Relabeled
				self.t2 = t2
			}

			@Instantiated let t3Relabeled: S1_T4
			@Instantiated let t2: S1_T2
		}
		""")
		#expect(runs.first?.remedy.fixture.swiftFileContent[2] == """
		@Instantiable
		public final class S1_T2: Instantiable {
			public init(t3Relabeled: S1_T5, t0: S1_T0) {
				self.t3Relabeled = t3Relabeled
				self.t0 = t0
			}

			@Instantiated let t3Relabeled: S1_T5
			@Instantiated let t0: S1_T0
		}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
		#expect(GraphFuzzerRemedies.unremediedSiteCount(of: fixture, diagnostics: diagnostics) == 0)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_relabelEveryDeclarationAnyChainNamesAndLeaveNoErrorAtTheReceive_whenALapOfACycleNamesAnotherHidingDeclaration() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(t3: S1_T3, t1: S1_T1) {
					self.t3 = t3
					self.t1 = t1
				}

				@Instantiated let t3: S1_T3
				@Instantiated let t1: S1_T1
			}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2, t4Builder: Instantiator<S1_T4>) {
					self.t2 = t2
					self.t4Builder = t4Builder
				}

				@Instantiated let t2: S1_T2
				@Instantiated let t4Builder: Instantiator<S1_T4>
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
			public final class S1_T4: Instantiable {
				public init(t3: S1_T6, t1Builder: Instantiator<S1_T1>) {
					self.t3 = t3
					self.t1Builder = t1Builder
				}

				@Instantiated let t3: S1_T6
				@Instantiated let t1Builder: Instantiator<S1_T1>
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
			Self.leaf("S1_T5"),
			Self.leaf("S1_T6"),
		])
		let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
		guard case let .rejected(diagnostics) = outcome else {
			Issue.record("The tool accepts the graph:\n\(outcome.description)")
			return
		}

		let runs = try await GraphFuzzerOracle.remedyRuns(of: fixture, outcome: outcome)

		#expect(runs.map(\.remedy.kind) == [.relabelHidingDeclaration])
		#expect(runs.map(\.remedy.description) == ["gives `t3: S1_T5` on `S1_T2` and `t3: S1_T6` on `S1_T4` the label `t3Relabeled`"])
		#expect(runs.map(\.errorsAtSite) == [[]])
		#expect(GraphFuzzerRemedies.unremediedSiteCount(of: fixture, diagnostics: diagnostics) == 0)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_relabelTheHidingDeclarationAndLeaveNoErrorAtTheReceive_whenAMockWhoseTreeACycleBuildsAgainReceivesTheLabelInTheHidingForm() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(generateMock: true)
			public final class S1_T1: Instantiable {
				public init(t3: S1_T4, t2Builder: Instantiator<S1_T2>) {
					self.t3 = t3
					self.t2Builder = t2Builder
				}

				@Instantiated let t3: S1_T4
				@Instantiated let t2Builder: Instantiator<S1_T2>
			}
			""",
			"""
			@Instantiable(generateMock: true)
			public final class S1_T2: Instantiable {
				public init(t3: S1_T4, t0Builder: Instantiator<S1_T0>) {
					self.t3 = t3
					self.t0Builder = t0Builder
				}

				@Received let t3: S1_T4
				@Instantiated let t0Builder: Instantiator<S1_T0>
			}
			""",
			"""
			@Instantiable
			public final class S1_T0: Instantiable {
				public init(t3: S1_T3, t1Builder: Instantiator<S1_T1>) {
					self.t3 = t3
					self.t1Builder = t1Builder
				}

				@Received let t3: S1_T3
				@Instantiated let t1Builder: Instantiator<S1_T1>
			}
			""",
			Self.leaf("S1_T3"),
			Self.leaf("S1_T4"),
		])
		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.relabelHidingDeclaration])
		#expect(runs.map(\.remedy.description) == ["gives `t3: S1_T4` on `S1_T1` the label `t3Relabeled`"])
		withKnownIssue("\(SafeDIToolGraphFuzzerTests.remedyHidingDeclarationMasksMockTreeReceiveReason)") {
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

		withKnownIssue("\(SafeDIToolGraphFuzzerTests.remedyUnlocatedErrorHasNoSiteReason)") {
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
		#expect(runs.map(\.errorsAtSite) == [[]])
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
		#expect(runs.map(\.errorsAtSite) == [[]])
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

		#expect(runs.map(\.remedy.kind) == [.removeReceive, .receiveOptionallyIfAvailable])
		#expect(runs.map(\.errorsAtSite) == [[], []])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_leaveNoErrorAtTheSeam_whenTheProvidingFormIsAWrapperTheSeamsCallerDoesNotDeclare() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.seamFormsGraph(seamAttribute: "@Received(onlyIfAvailable: true)", seamType: "LazilyInstantiated<S1_User>?"))

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.declareProvidingFormOnSeam])
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	// MARK: Seam fills

	// The errors of a fill that reads a value its builder is not handed. Each remedy edits declarations besides the fill's
	// receive, so its verdict also counts an error it introduces at a type it edits or whose declaration it moves. The
	// shapes an adopter reported are each a graph here, and a graph whose advice does not work is a known issue.

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_declareTheReadValueOnTheInnerSeamAndLeaveNoErrorAtTheReceive_whenTheSeamThatPassesTheBuilderUpDeclaresIt() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.passedUpBuilderGraph(receiveAttribute: "@Received", receivedType: "S1_Logger"))

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.receiveOnSeam])
		#expect(runs.first?.remedy.fixture.swiftFileContent[1] == """
		// module: FuzzFeature

		@Instantiable(generateDependencyTree: true)
		public final class S1_Inner: Instantiable {
			public init(service: any S1_Service, logger: S1_Logger) {
				self.service = service
				self.logger = logger
			}

			@Instantiated let service: any S1_Service
			@Received let logger: S1_Logger
		}

		public protocol S1_Service {}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_declareTheReadValueOnlyIfAvailableOnTheInnerSeamAndLeaveNoErrorAtTheReceive_whenTheFillReceivesTheValueTheSeamThatPassesTheBuilderUpDeclaresOnlyIfAvailable() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.passedUpBuilderGraph(receiveAttribute: "@Received(onlyIfAvailable: true)", receivedType: "S1_Logger?"))

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.receiveOnSeam])
		#expect(runs.first?.remedy.fixture.swiftFileContent[1] == """
		// module: FuzzFeature

		@Instantiable(generateDependencyTree: true)
		public final class S1_Inner: Instantiable {
			public init(service: any S1_Service, logger: S1_Logger?) {
				self.service = service
				self.logger = logger
			}

			@Instantiated let service: any S1_Service
			@Received(onlyIfAvailable: true) let logger: S1_Logger?
		}

		public protocol S1_Service {}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_declareTheReadValueOnlyIfAvailableOnTheSeamAndLeaveNoErrorAtTheReceive_whenTheSeamsTreeBuildsTheSeamAgainBeneathTheValueTheFillReadsOnlyIfAvailable() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Home: Instantiable {
				public init(service: any S1_Service, stepBuilder: Instantiator<S1_Step>) {
					self.service = service
					self.stepBuilder = stepBuilder
				}

				@Instantiated let service: any S1_Service
				@Instantiated let stepBuilder: Instantiator<S1_Step>
			}

			public protocol S1_Service {}
			""",
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_Step: Instantiable {
				public init(cache: S1_Cache, homeBuilder: Instantiator<S1_Home>) {
					self.cache = cache
					self.homeBuilder = homeBuilder
				}

				@Instantiated let cache: S1_Cache
				@Instantiated let homeBuilder: Instantiator<S1_Home>
			}
			""",
			Self.leaf("S1_Cache", module: "FuzzFeature"),
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(home: S1_Home) {
					self.home = home
				}

				@Instantiated let home: S1_Home
			}
			""",
			"""
			// module: FuzzApp, fills a hole
			import FuzzFeature

			@Instantiable(fulfillingAdditionalTypes: [S1_Service.self])
			public final class S1_Impl: Instantiable, S1_Service {
				public init(cache: S1_Cache?) {
					self.cache = cache
				}

				@Received(onlyIfAvailable: true) let cache: S1_Cache?
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.receiveOnSeam])
		#expect(runs.first?.remedy.fixture.swiftFileContent[0] == """
		// module: FuzzFeature

		@Instantiable(generateDependencyTree: true)
		public final class S1_Home: Instantiable {
			public init(service: any S1_Service, stepBuilder: Instantiator<S1_Step>, cache: S1_Cache?) {
				self.service = service
				self.stepBuilder = stepBuilder
				self.cache = cache
			}

			@Instantiated let service: any S1_Service
			@Instantiated let stepBuilder: Instantiator<S1_Step>
			@Received(onlyIfAvailable: true) let cache: S1_Cache?
		}

		public protocol S1_Service {}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_receiveTheValueOnlyIfAvailableOnTheSeamAndTheFillAndLeaveNoErrorAtTheReceive_whenTheFillsCallOfTheSeamIsBeneathADeclarationOfIt() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Seam: Instantiable {
				public init(ownerBuilder: Instantiator<S1_Owner>) {
					self.ownerBuilder = ownerBuilder
				}

				@Instantiated let ownerBuilder: Instantiator<S1_Owner>
			}

			public protocol S1_Service {}
			""",
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_Owner: Instantiable {
				public init(service: any S1_Service) {
					self.service = service
				}

				@Instantiated let service: any S1_Service
			}
			""",
			Self.leaf("S1_Logger", module: "FuzzFeature"),
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(logger: S1_Logger, seam: S1_Seam) {
					self.logger = logger
					self.seam = seam
				}

				@Instantiated let logger: S1_Logger
				@Instantiated let seam: S1_Seam
			}
			""",
			"""
			// module: FuzzApp, fills a hole
			import FuzzFeature

			@Instantiable(fulfillingAdditionalTypes: [S1_Service.self])
			public final class S1_Impl: Instantiable, S1_Service {
				public init(logger: S1_Logger, middle: S1_Middle) {
					self.logger = logger
					self.middle = middle
				}

				@Received let logger: S1_Logger
				@Instantiated let middle: S1_Middle
			}
			""",
			"""
			// module: FuzzApp, fills a hole
			import FuzzFeature

			@Instantiable
			public final class S1_Middle: Instantiable {
				public init(logger: S1_Logger, seamBuilder: Instantiator<S1_Seam>) {
					self.logger = logger
					self.seamBuilder = seamBuilder
				}

				@Instantiated let logger: S1_Logger
				@Instantiated let seamBuilder: Instantiator<S1_Seam>
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		// The error's first remedy, a required receive with the label declared on every route to the seam, states a
		// condition the oracle does not meet, so only the second is applied.
		#expect(runs.map(\.remedy.kind) == [.receiveOnlyIfAvailableOnSeamAndReader])
		#expect(runs.first.map { [$0.remedy.fixture.swiftFileContent[0], $0.remedy.fixture.swiftFileContent[4]] } == [
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Seam: Instantiable {
				public init(ownerBuilder: Instantiator<S1_Owner>, logger: S1_Logger?) {
					self.ownerBuilder = ownerBuilder
					self.logger = logger
				}

				@Instantiated let ownerBuilder: Instantiator<S1_Owner>
				@Received(onlyIfAvailable: true) let logger: S1_Logger?
			}

			public protocol S1_Service {}
			""",
			"""
			// module: FuzzApp, fills a hole
			import FuzzFeature

			@Instantiable(fulfillingAdditionalTypes: [S1_Service.self])
			public final class S1_Impl: Instantiable, S1_Service {
				public init(logger: S1_Logger?, middle: S1_Middle) {
					self.logger = logger
					self.middle = middle
				}

				@Received(onlyIfAvailable: true) let logger: S1_Logger?
				@Instantiated let middle: S1_Middle
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_forwardTheValueIntoTheSendableFunctionAndLeaveNoErrorAtTheReceive_whenASendableInstantiatorBuildsThePlace() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.stationGraph(placeWrapper: "SendableInstantiator", userReceivesId: nil))

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.forwardIntoSendableFunction])
		#expect(runs.first?.remedy.fixture.swiftFileContent[2] == """
		// module: FuzzFeature

		@Instantiable
		public final class S1_Owner: Instantiable, Sendable {
			public init(service: any S1_Service, id: Int) {
				self.service = service
				self.id = id
			}

			@Instantiated let service: any S1_Service
			@Forwarded let id: Int
		}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_forwardTheValueIntoTheSendableFunctionAndDeclareTheWrapperAsAnInstantiatorAndLeaveNoErrorAtTheReceive_whenASendableLazyWrapperBuildsThePlace() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.stationGraph(placeWrapper: "SendableLazilyInstantiated", userReceivesId: nil))

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.description) == ["declares `@Forwarded let id: Int` on `S1_Owner`, and `owner` on `S1_Mid` as `SendableInstantiator<S1_Owner>`"])
		#expect(runs.first.map { [$0.remedy.fixture.swiftFileContent[1], $0.remedy.fixture.swiftFileContent[2]] } == [
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_Mid: Instantiable, Sendable {
				public init(id: Int, owner: SendableInstantiator<S1_Owner>) {
					self.id = id
					self.owner = owner
				}

				@Forwarded let id: Int
				@Instantiated let owner: SendableInstantiator<S1_Owner>
			}
			""",
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_Owner: Instantiable, Sendable {
				public init(service: any S1_Service, id: Int) {
					self.service = service
					self.id = id
				}

				@Instantiated let service: any S1_Service
				@Forwarded let id: Int
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_forwardTheDeclaredValueIntoTheSendableFunctionAndLeaveNoErrorAtTheReceive_whenATypeOutsideTheSendableFunctionDeclaresIt() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.stationGraph(placeWrapper: "SendableInstantiator", userReceivesId: false))

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.forwardIntoSendableFunction])
		#expect(runs.first?.remedy.fixture.swiftFileContent[2] == """
		// module: FuzzFeature

		@Instantiable
		public final class S1_Owner: Instantiable, Sendable {
			public init(service: any S1_Service, user: S1_User) {
				self.service = service
				self.user = user
			}

			@Instantiated let service: any S1_Service
			@Forwarded let user: S1_User
		}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_forwardTheDeclaredValueIntoTheSendableFunctionAndLeaveNoErrorAtTheReceive_whenAnOuterSeamBuildsTheSeam() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.stationGraph(placeWrapper: "SendableInstantiator", userReceivesId: false, rootBuildsOuterSeam: true))

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.description) == ["declares `@Forwarded let user: S1_User` on `S1_Owner`"])
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_forwardTheDeclaredValueIntoTheSendableFunctionAndLeaveNoErrorAtTheReceive_whenTheDeclaredValueReceivesAValueForwardedOutsideTheFunction() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.stationGraph(placeWrapper: "SendableInstantiator", userReceivesId: true))

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.description) == ["declares `@Forwarded let user: S1_User` on `S1_Owner`"])
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_instantiateTheValueOutsideTheSeamAndLeaveNoErrorAtTheReceive_whenTheSeamDeclaresItOutsideTheSendableFunction() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.stationGraph(placeWrapper: "SendableInstantiator", userReceivesId: false, seamDeclaresUser: true))

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.instantiateOutsideSeam])
		#expect(runs.first.map { [$0.remedy.fixture.swiftFileContent[0], $0.remedy.fixture.swiftFileContent[4]] } == [
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Home: Instantiable, Sendable {
				public init(user: S1_User, midBuilder: Instantiator<S1_Mid>) {
					self.user = user
					self.midBuilder = midBuilder
				}

				@Received let user: S1_User
				@Instantiated let midBuilder: Instantiator<S1_Mid>
			}

			public protocol S1_Service: Sendable {}
			""",
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable, Sendable {
				public init(home: S1_Home, user: S1_User) {
					self.home = home
					self.user = user
				}

				@Instantiated let home: S1_Home
				@Instantiated let user: S1_User
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_instantiateTheValueOnTheCallerOfTheSeamThatPassesTheBuilderUpAndLeaveNoErrorAtTheReceive_whenAnOuterSeamBuildsTheSeamThatDeclaresIt() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.stationGraph(placeWrapper: "SendableInstantiator", userReceivesId: false, seamDeclaresUser: true, rootBuildsOuterSeam: true))

		let runs = try await Self.remedyRuns(of: fixture)

		// `S1_Outer` builds `S1_Home` and passes its builder up, so the builder's caller is the root, which declares the value.
		#expect(runs.map(\.remedy.description) == ["declares `@Instantiated let user: S1_User` on `S1_Root0`, and `@Received let user: S1_User` on `S1_Home` in place of `S1_Home`’s declaration"])
		#expect(runs.first.map { [$0.remedy.fixture.swiftFileContent[0], $0.remedy.fixture.swiftFileContent[5]] } == [
			fixture.swiftFileContent[0],
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable, Sendable {
				public init(outer: S1_Outer, user: S1_User) {
					self.outer = outer
					self.user = user
				}

				@Instantiated let outer: S1_Outer
				@Instantiated let user: S1_User
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_leaveNoErrorAtTheReceive_whenTheValueInstantiatedOutsideTheSeamIsALazyWrapperTheSendableFillCannotCapture() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Outer: Instantiable {
				public init(logger: LazilyInstantiated<S1_Logger>, inner: S1_Inner) {
					self.logger = logger
					self.inner = inner
				}

				@Instantiated let logger: LazilyInstantiated<S1_Logger>
				@Instantiated let inner: S1_Inner
			}
			""",
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Inner: Instantiable, Sendable {
				public init(ownerBuilder: SendableInstantiator<S1_Owner>) {
					self.ownerBuilder = ownerBuilder
				}

				@Instantiated let ownerBuilder: SendableInstantiator<S1_Owner>
			}

			public protocol S1_Service: Sendable {}
			""",
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_Owner: Instantiable, Sendable {
				public init(service: any S1_Service) {
					self.service = service
				}

				@Instantiated let service: any S1_Service
			}
			""",
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_Logger: Instantiable, Sendable {
				public init() {}
			}
			""",
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(outer: S1_Outer) {
					self.outer = outer
				}

				@Instantiated let outer: S1_Outer
			}
			""",
			"""
			// module: FuzzApp, fills a hole
			import FuzzFeature

			@Instantiable(fulfillingAdditionalTypes: [S1_Service.self])
			public final class S1_Impl: Instantiable, Sendable, S1_Service {
				public init(logger: S1_Logger?) {
					self.logger = logger
				}

				@Received(onlyIfAvailable: true) let logger: S1_Logger?
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.description) == ["declares `@Instantiated let logger: LazilyInstantiated<S1_Logger>` on `S1_Root0`, and `@Received let logger: LazilyInstantiated<S1_Logger>` on `S1_Outer` in place of `S1_Outer`’s declaration"])
		withKnownIssue("\(SafeDIToolGraphFuzzerTests.remedySeamFillInstantiatedOutsideNotSendableReason)") {
			#expect(runs.map(\.errorsAtSite) == [[]])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_instantiateTheInstantiatorAboveTheSeamAndLeaveNoErrorAtTheReceive_whenTheSeamsTreeBuildsItAfterTheBuilder() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Seam: Instantiable {
				public init(serviceBuilder: ErasedInstantiator<(), any S1_Service>, gadgetBuilder: ErasedInstantiator<(), any S1_Gadget>) {
					self.serviceBuilder = serviceBuilder
					self.gadgetBuilder = gadgetBuilder
				}

				@Instantiated(fulfilledByType: "S1_Impl") let serviceBuilder: ErasedInstantiator<(), any S1_Service>
				@Instantiated(fulfilledByType: "S1_GadgetImpl") let gadgetBuilder: ErasedInstantiator<(), any S1_Gadget>
			}

			public protocol S1_Service {}

			public protocol S1_Gadget {}
			""",
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(seam: S1_Seam) {
					self.seam = seam
				}

				@Instantiated let seam: S1_Seam
			}
			""",
			"""
			// module: FuzzApp, fills a hole
			import FuzzFeature

			@Instantiable(fulfillingAdditionalTypes: [S1_Gadget.self])
			public final class S1_GadgetImpl: Instantiable, S1_Gadget {
				public init() {}
			}
			""",
			"""
			// module: FuzzApp, fills a hole
			import FuzzFeature

			@Instantiable(fulfillingAdditionalTypes: [S1_Service.self])
			public final class S1_Impl: Instantiable, S1_Service {
				public init(gadgetBuilder: ErasedInstantiator<(), any S1_Gadget>) {
					self.gadgetBuilder = gadgetBuilder
				}

				@Received let gadgetBuilder: ErasedInstantiator<(), any S1_Gadget>
			}
			""",
		])

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.instantiateOutsideSeam])
		#expect(runs.first.map { [$0.remedy.fixture.swiftFileContent[0], $0.remedy.fixture.swiftFileContent[1]] } == [
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Seam: Instantiable {
				public init(serviceBuilder: ErasedInstantiator<(), any S1_Service>, gadgetBuilder: ErasedInstantiator<(), any S1_Gadget>) {
					self.serviceBuilder = serviceBuilder
					self.gadgetBuilder = gadgetBuilder
				}

				@Instantiated(fulfilledByType: "S1_Impl") let serviceBuilder: ErasedInstantiator<(), any S1_Service>
				@Received let gadgetBuilder: ErasedInstantiator<(), any S1_Gadget>
			}

			public protocol S1_Service {}

			public protocol S1_Gadget {}
			""",
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(seam: S1_Seam, gadgetBuilder: ErasedInstantiator<(), any S1_Gadget>) {
					self.seam = seam
					self.gadgetBuilder = gadgetBuilder
				}

				@Instantiated let seam: S1_Seam
				@Instantiated(fulfilledByType: "S1_GadgetImpl") let gadgetBuilder: ErasedInstantiator<(), any S1_Gadget>
			}
			""",
		])
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unremediedSiteCount_countsASeamFillsError_whenItAdvisesDeclaringTheInstantiatorBesideTheOneThatLeadsToThePlaceOnANewTypeOfTheFillsModule() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_SignedIn: Instantiable {
				public init(user: S1_User, aBuilder: ErasedInstantiator<(), any S1_AScreen>, bBuilder: ErasedInstantiator<(), any S1_BScreen>) {
					self.user = user
					self.aBuilder = aBuilder
					self.bBuilder = bBuilder
				}

				@Forwarded let user: S1_User
				@Instantiated(fulfilledByType: "S1_A") let aBuilder: ErasedInstantiator<(), any S1_AScreen>
				@Instantiated(fulfilledByType: "S1_B") let bBuilder: ErasedInstantiator<(), any S1_BScreen>
			}

			public protocol S1_AScreen {}

			public protocol S1_BScreen {}
			""",
			"""
			// module: FuzzFeature

			@Instantiable(fulfillingAdditionalTypes: [S1_AScreen.self])
			public final class S1_A: Instantiable, S1_AScreen {
				public init(user: S1_User, bBuilder: ErasedInstantiator<(), any S1_BScreen>) {
					self.user = user
					self.bBuilder = bBuilder
				}

				@Received let user: S1_User
				@Received let bBuilder: ErasedInstantiator<(), any S1_BScreen>
			}
			""",
			Self.leaf("S1_User", module: "FuzzFeature"),
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(signedInBuilder: Instantiator<S1_SignedIn>) {
					self.signedInBuilder = signedInBuilder
				}

				@Instantiated let signedInBuilder: Instantiator<S1_SignedIn>
			}
			""",
			"""
			// module: FuzzApp, fills a hole
			import FuzzFeature

			@Instantiable(fulfillingAdditionalTypes: [S1_BScreen.self])
			public final class S1_B: Instantiable, S1_BScreen {
				public init(aBuilder: ErasedInstantiator<(), any S1_AScreen>) {
					self.aBuilder = aBuilder
				}

				@Received let aBuilder: ErasedInstantiator<(), any S1_AScreen>
			}
			""",
		])

		let (runs, unremediedSiteCount) = try await Self.remedyRunsAndUnremediedSiteCount(of: fixture)

		// The error advises declaring `aBuilder` and `bBuilder` on one type of `FuzzApp` that `S1_SignedIn` builds through a
		// protocol in their place: a type and a protocol the graph does not declare, which the oracle does not write.
		#expect(runs.isEmpty)
		#expect(unremediedSiteCount == 1)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_receiveTheValueOnTheTypeTheCycleBuildsAgainAndLeaveNoErrorAtTheReceive_whenTheRootDeclaresTheLabelToo() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.cycleRedeclarationGraph(rootDeclaresCache: true))

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.receiveOnTypeTheCycleBuilds])
		#expect(runs.first?.remedy.fixture.swiftFileContent[2] == """
		// module: FuzzFeature

		@Instantiable
		public final class S1_Step: Instantiable {
			public init(service: any S1_Service, screenBuilder: Instantiator<S1_Screen>, cache: S1_Cache) {
				self.service = service
				self.screenBuilder = screenBuilder
				self.cache = cache
			}

			@Instantiated let service: any S1_Service
			@Instantiated let screenBuilder: Instantiator<S1_Screen>
			@Received let cache: S1_Cache
		}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_receiveTheValueOnTheTypeTheCycleBuildsAgainAndLeaveNoErrorAtTheReceive_whenOnlyTheDeclarationTheCycleRepeatsDeclaresTheLabel() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.cycleRedeclarationGraph(rootDeclaresCache: false))

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.description) == ["declares `@Received let cache: S1_Cache` on `S1_Step`"])
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_receiveTheValueOnlyIfAvailableOnTheTypeTheCycleBuildsAgainAndLeaveNoErrorAtTheReceive_whenTheSeamDeclaresTheLabelOutsideTheSendableFunctionThatBuildsTheCycle() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.sendableCycleRedeclarationGraph())

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.kind) == [.receiveOnTypeTheCycleBuilds])
		#expect(runs.first?.remedy.fixture.swiftFileContent[1] == """
		// module: FuzzFeature

		@Instantiable
		public final class S1_Screen: Instantiable, Sendable {
			public init(service: any S1_Service, stepBuilder: SendableInstantiator<S1_Step>, cache: S1_Cache?) {
				self.service = service
				self.stepBuilder = stepBuilder
				self.cache = cache
			}

			@Instantiated let service: any S1_Service
			@Instantiated let stepBuilder: SendableInstantiator<S1_Step>
			@Received(onlyIfAvailable: true) let cache: S1_Cache?
		}
		""")
		#expect(runs.map(\.errorsAtSite) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyRuns_leaveNoErrorAtTheReceive_whenTheTypeTheCycleBuildsAgainIsInsideASendableFunctionAndTheValueIsNotSendable() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: Self.sendableCycleRedeclarationGraph(cacheType: "Instantiator<S1_Cache>"))

		let runs = try await Self.remedyRuns(of: fixture)

		#expect(runs.map(\.remedy.description) == ["declares `@Received(onlyIfAvailable: true) let cache: Instantiator<S1_Cache>?` on `S1_Screen`"])
		withKnownIssue("\(SafeDIToolGraphFuzzerTests.remedySeamFillCycleReceiveNotSendableReason)") {
			#expect(runs.map(\.errorsAtSite) == [[]])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unremediedSiteCount_countsASeamFillsError_whenItStatesOnlyTheRemedyThatFulfillsTheHoleInTheSeamsModule() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Seam: Instantiable {
				public init(gadget: any S1_Gadget, service: any S1_Service) {
					self.gadget = gadget
					self.service = service
				}

				@Instantiated let gadget: any S1_Gadget
				@Instantiated let service: any S1_Service
			}

			public protocol S1_Gadget {}

			public protocol S1_Service {}
			""",
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(seam: S1_Seam) {
					self.seam = seam
				}

				@Instantiated let seam: S1_Seam
			}
			""",
			"""
			// module: FuzzApp, fills a hole
			import FuzzFeature

			@Instantiable(fulfillingAdditionalTypes: [S1_Gadget.self])
			public final class S1_GadgetImpl: Instantiable, S1_Gadget {
				public init(service: any S1_Service) {
					self.service = service
				}

				@Received let service: any S1_Service
			}
			""",
			"""
			// module: FuzzApp, fills a hole
			import FuzzFeature

			@Instantiable(fulfillingAdditionalTypes: [S1_Service.self])
			public final class S1_ServiceImpl: Instantiable, S1_Service {
				public init() {}
			}
			""",
		])

		let (runs, unremediedSiteCount) = try await Self.remedyRunsAndUnremediedSiteCount(of: fixture)

		#expect(runs.isEmpty)
		#expect(unremediedSiteCount == 1)
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

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles a remedied graph only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func results_reportTheRemedyKind_whenTheToolAcceptsTheRemediedGraphAndItsGeneratedCodeDoesNotCompile() async throws {
		// The tool accepts the forwarded receive, and the generated code calls `S1_T1`'s initializer, which the fixture
		// marks unavailable, so the remedied graph does not compile without depending on a defect of SafeDI.
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
				@available(*, unavailable)
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
		let runs = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: [], multiModuleRenamings: [])
		#expect(runs.remedyRuns.map(\.remedy.kind) == [.forwardReceive])

		let failure = try #require(try await GraphFuzzerOracle.results(of: [runs]).first?.failure)

		#expect(failure.kind == .generatedCodeDoesNotCompile)
		#expect(failure.details.hasPrefix("The forward-receive remedy, which receives `t2` with `@Forwarded`, is accepted at `S1_T1.t2` in S1_T1.swift, and the remedied graph's generated code does not compile"))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func edit_removesParameterFromHandWrittenMock_whenRemedyRemovesPropertyTheMockTakes() throws {
		var files = try #require(GraphFuzzerRemedies.Files(Self.typeWithHandWrittenMock))

		#expect(files.edit(typeNamed: "S1_T1") { properties in properties.filter { $0.label != "t0" } })
		#expect(files.contents == [
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t2: S1_T2, flag: Bool = true) {
					self.t2 = t2
				}

				@Received let t2: S1_T2

				#if DEBUG
				public static func mock(t2: S1_T2, flag: Bool = true) -> S1_T1 {
					S1_T1(t2: t2, flag: flag)
				}
				#endif
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func edit_retypesParameterOfHandWrittenMock_whenRemedyRetypesPropertyTheMockTakes() throws {
		var files = try #require(GraphFuzzerRemedies.Files(Self.typeWithHandWrittenMock))

		#expect(files.edit(typeNamed: "S1_T1") { properties in
			properties.map { $0.label == "t2" ? GraphFuzzerRemedyProperty(attribute: "@Received", label: "t2", type: "SendableInstantiator<S1_T2>") : $0 }
		})
		#expect(files.contents == [
			"""
			@Instantiable
			public final class S1_T1: Instantiable {
				public init(t0: S1_T0, t2: SendableInstantiator<S1_T2>, flag: Bool = true) {
					self.t0 = t0
					self.t2 = t2
				}

				@Received let t0: S1_T0
				@Received let t2: SendableInstantiator<S1_T2>

				#if DEBUG
				public static func mock(t0: S1_T0, t2: SendableInstantiator<S1_T2>, flag: Bool = true) -> S1_T1 {
					S1_T1(t0: t0, t2: t2, flag: flag)
				}
				#endif
			}
			""",
		])
	}

	@Test
	func declaredType_takesSendableForm_whenAdviceNamesBothFormsAndDeclaringTypeConformsToSendable() {
		#expect(GraphFuzzerRemedies.declaredType(
			advisedBy: "`t5` on `S1_T4` cannot build `S1_T5`, which has @Forwarded properties that only an instantiator is passed. Declare it as `Instantiator<S1_T5>`, or as `SendableInstantiator<S1_T5>` if `S1_T4` is Sendable.",
			declaringTypeConformsToSendable: true,
		) == "SendableInstantiator<S1_T5>")
	}

	@Test
	func declaredType_takesPlainForm_whenAdviceNamesBothFormsAndDeclaringTypeDoesNotConformToSendable() {
		#expect(GraphFuzzerRemedies.declaredType(
			advisedBy: "`t5` on `S1_T4` cannot build `S1_T5`, which has @Forwarded properties that only an instantiator is passed. Declare it as `Instantiator<S1_T5>`, or as `SendableInstantiator<S1_T5>` if `S1_T4` is Sendable.",
			declaringTypeConformsToSendable: false,
		) == "Instantiator<S1_T5>")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func conformsToSendable_readsUncheckedSendable_whenTypeListsItAmongItsConformances() throws {
		let files = try #require(GraphFuzzerRemedies.Files(GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable
			public final class S1_T1: Instantiable, S1_T1Protocol, @unchecked Sendable {
				public init() {}
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable, S1_T2Protocol {
				public init() {}
			}
			""",
		])))

		#expect(files.conformsToSendable(typeNamed: "S1_T1"))
		#expect(!files.conformsToSendable(typeNamed: "S1_T2"))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func conformsToSendable_readsProtocolThatRefinesSendable_whenTypeConformsOnlyThroughItsProtocol() throws {
		let files = try #require(GraphFuzzerRemedies.Files(GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init() {}
			}

			public protocol S1_T1Protocol: AnyObject, Sendable {}
			public protocol S1_T2Protocol: S1_T1Protocol {}
			public protocol S1_T3Protocol: AnyObject {}
			""",
			"""
			@Instantiable
			public final class S1_T1: Instantiable, S1_T1Protocol {
				public init() {}
			}
			""",
			"""
			@Instantiable
			public final class S1_T2: Instantiable, S1_T2Protocol {
				public init() {}
			}
			""",
			"""
			@Instantiable
			public final class S1_T3: Instantiable, S1_T3Protocol {
				public init() {}
			}
			""",
		])))

		#expect(files.conformsToSendable(typeNamed: "S1_T1"))
		#expect(files.conformsToSendable(typeNamed: "S1_T2"))
		#expect(!files.conformsToSendable(typeNamed: "S1_T3"))
	}

	/// A type with a hand-written mock that takes its initializer's parameters and passes each on, as the base corpus's
	/// mock vocabulary draws one.
	private static let typeWithHandWrittenMock = GraphFuzzerFixture(seed: 1, swiftFileContent: [
		"""
		@Instantiable
		public final class S1_T1: Instantiable {
			public init(t0: S1_T0, t2: S1_T2, flag: Bool = true) {
				self.t0 = t0
				self.t2 = t2
			}

			@Received let t0: S1_T0
			@Received let t2: S1_T2

			#if DEBUG
			public static func mock(t0: S1_T0, t2: S1_T2, flag: Bool = true) -> S1_T1 {
				S1_T1(t0: t0, t2: t2, flag: flag)
			}
			#endif
		}
		""",
	])

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

	/// A type of `module` that declares no property, as the fuzzer writes one.
	private static func leaf(_ name: String, module: String) -> String {
		"// module: \(module)\n\n" + leaf(name)
	}

	/// A seam of `FuzzFeature`, `S1_Outer`, that declares `logger: S1_Logger` and then calls `S1_Inner`, a seam whose hole
	/// `S1_Impl` fills in `FuzzApp`, receiving `logger: receivedType` with `receiveAttribute`: `S1_Outer` passes the builder up
	/// to the root, which cannot hand it `S1_Outer`'s `logger`.
	private static func passedUpBuilderGraph(receiveAttribute: String, receivedType: String) -> [String] {
		[
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Outer: Instantiable {
				public init(logger: S1_Logger, inner: S1_Inner) {
					self.logger = logger
					self.inner = inner
				}

				@Instantiated let logger: S1_Logger
				@Instantiated let inner: S1_Inner
			}
			""",
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Inner: Instantiable {
				public init(service: any S1_Service) {
					self.service = service
				}

				@Instantiated let service: any S1_Service
			}

			public protocol S1_Service {}
			""",
			leaf("S1_Logger", module: "FuzzFeature"),
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(outer: S1_Outer) {
					self.outer = outer
				}

				@Instantiated let outer: S1_Outer
			}
			""",
			"""
			// module: FuzzApp, fills a hole
			import FuzzFeature

			@Instantiable(fulfillingAdditionalTypes: [S1_Service.self])
			public final class S1_Impl: Instantiable, S1_Service {
				public init(logger: \(receivedType)) {
					self.logger = logger
				}

				\(receiveAttribute) let logger: \(receivedType)
			}
			""",
		]
	}

	/// A seam of `FuzzFeature`, `S1_Home`, that builds `S1_Mid` through an instantiator, which forwards `id: Int` and builds
	/// `S1_Owner`, the owner of a place of `S1_Service`, in a `@Sendable` function, with `placeWrapper`. `S1_Impl` fills the
	/// place in `FuzzApp`, reading `id` where `userReceivesId` is `nil`, and otherwise `user: S1_User`, which `S1_Mid`
	/// instantiates beside the place, and which receives `id` where `userReceivesId` is `true`: a value bound outside the
	/// function that builds the place, which hands its fill only what it binds. Where `seamDeclaresUser` is `true`, `S1_Home`
	/// instantiates `user` in place of `S1_Mid`.
	///
	/// Where `rootBuildsOuterSeam` is `true`, the root builds `S1_Outer`, a seam of `FuzzFeature` that builds `S1_Home` and
	/// passes its builder up, in place of building `S1_Home` itself.
	private static func stationGraph(placeWrapper: String, userReceivesId: Bool?, seamDeclaresUser: Bool = false, rootBuildsOuterSeam: Bool = false) -> [String] {
		var midProperties = [(attribute: "@Forwarded", label: "id", type: "Int")]
		var homeProperties = [(label: "midBuilder", type: "Instantiator<S1_Mid>")]
		let implProperty = if userReceivesId == nil {
			(attribute: "@Received", label: "id", type: "Int")
		} else {
			(attribute: "@Received", label: "user", type: "S1_User")
		}
		if seamDeclaresUser {
			homeProperties.insert((label: "user", type: "S1_User"), at: 0)
		} else if userReceivesId != nil {
			midProperties.append((attribute: "@Instantiated", label: "user", type: "S1_User"))
		}
		midProperties.append((attribute: "@Instantiated", label: "owner", type: "\(placeWrapper)<S1_Owner>"))
		let rootProperty = rootBuildsOuterSeam ? (label: "outer", type: "S1_Outer") : (label: "home", type: "S1_Home")
		var files = rootBuildsOuterSeam ? [
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Outer: Instantiable, Sendable {
				public init(home: S1_Home) {
					self.home = home
				}

				@Instantiated let home: S1_Home
			}
			""",
		] : []
		files += [
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Home: Instantiable, Sendable {
				public init(\(homeProperties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
			\(homeProperties.map { "\t\tself.\($0.label) = \($0.label)" }.joined(separator: "\n"))
				}

			\(homeProperties.map { "\t@Instantiated let \($0.label): \($0.type)" }.joined(separator: "\n"))
			}

			public protocol S1_Service: Sendable {}
			""",
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_Mid: Instantiable, Sendable {
				public init(\(midProperties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
			\(midProperties.map { "\t\tself.\($0.label) = \($0.label)" }.joined(separator: "\n"))
				}

			\(midProperties.map { "\t\($0.attribute) let \($0.label): \($0.type)" }.joined(separator: "\n"))
			}
			""",
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_Owner: Instantiable, Sendable {
				public init(service: any S1_Service) {
					self.service = service
				}

				@Instantiated let service: any S1_Service
			}
			""",
		]
		if let userReceivesId {
			files.append(userReceivesId
				? """
				// module: FuzzFeature

				@Instantiable
				public final class S1_User: Instantiable, Sendable {
					public init(id: Int) {
						self.id = id
					}

					@Received let id: Int
				}
				"""
				: """
				// module: FuzzFeature

				@Instantiable
				public final class S1_User: Instantiable, Sendable {
					public init() {}
				}
				""")
		}
		files += [
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable, Sendable {
				public init(\(rootProperty.label): \(rootProperty.type)) {
					self.\(rootProperty.label) = \(rootProperty.label)
				}

				@Instantiated let \(rootProperty.label): \(rootProperty.type)
			}
			""",
			"""
			// module: FuzzApp, fills a hole
			import FuzzFeature

			@Instantiable(fulfillingAdditionalTypes: [S1_Service.self])
			public final class S1_Impl: Instantiable, Sendable, S1_Service {
				public init(\(implProperty.label): \(implProperty.type)) {
					self.\(implProperty.label) = \(implProperty.label)
				}

				\(implProperty.attribute) let \(implProperty.label): \(implProperty.type)
			}
			""",
		]
		return files
	}

	/// A seam of `FuzzFeature`, `S1_Home`, whose `S1_Screen` declares `cache: S1_Cache` and builds `S1_Step`, the owner of a
	/// place of `S1_Service`, which builds `S1_Screen` again: a cycle that declares `cache` again at every level, while the
	/// fill, `S1_Impl` in `FuzzApp`, reads `cache` from a scope that holds the same values at every level. The root declares
	/// `cache` too where `rootDeclaresCache` is `true`.
	private static func cycleRedeclarationGraph(rootDeclaresCache: Bool) -> [String] {
		let rootProperties = rootDeclaresCache ? [(label: "cache", type: "S1_Cache"), (label: "home", type: "S1_Home")] : [(label: "home", type: "S1_Home")]
		return [
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Home: Instantiable {
				public init(screen: S1_Screen) {
					self.screen = screen
				}

				@Instantiated let screen: S1_Screen
			}

			public protocol S1_Service {}
			""",
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_Screen: Instantiable {
				public init(cache: S1_Cache, stepBuilder: Instantiator<S1_Step>) {
					self.cache = cache
					self.stepBuilder = stepBuilder
				}

				@Instantiated let cache: S1_Cache
				@Instantiated let stepBuilder: Instantiator<S1_Step>
			}
			""",
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_Step: Instantiable {
				public init(service: any S1_Service, screenBuilder: Instantiator<S1_Screen>) {
					self.service = service
					self.screenBuilder = screenBuilder
				}

				@Instantiated let service: any S1_Service
				@Instantiated let screenBuilder: Instantiator<S1_Screen>
			}
			""",
			leaf("S1_Cache", module: "FuzzFeature"),
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable {
				public init(\(rootProperties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
			\(rootProperties.map { "\t\tself.\($0.label) = \($0.label)" }.joined(separator: "\n"))
				}

			\(rootProperties.map { "\t@Instantiated let \($0.label): \($0.type)" }.joined(separator: "\n"))
			}
			""",
			"""
			// module: FuzzApp, fills a hole
			import FuzzFeature

			@Instantiable(fulfillingAdditionalTypes: [S1_Service.self])
			public final class S1_Impl: Instantiable, S1_Service {
				public init(cache: S1_Cache) {
					self.cache = cache
				}

				@Received let cache: S1_Cache
			}
			""",
		]
	}

	/// Seed 1916's cycle, made minimal: a seam of `FuzzFeature`, `S1_Home`, declares `cache: cacheType` and builds
	/// `S1_Screen`, the owner of a place of `S1_Service`, in a `SendableInstantiator`; `S1_Screen` builds `S1_Step` in another,
	/// which declares `cache` again and builds `S1_Screen` again. The fill, `S1_Impl` in `FuzzApp`, receives `cache` only if
	/// available, from a scope that holds the same values at every level of the cycle, and `S1_Home`'s `cache` is outside the
	/// `@Sendable` function that builds `S1_Screen`.
	private static func sendableCycleRedeclarationGraph(cacheType: String = "S1_Cache") -> [String] {
		[
			"""
			// module: FuzzFeature

			@Instantiable(generateDependencyTree: true)
			public final class S1_Home: Instantiable, Sendable {
				public init(cache: \(cacheType), screenBuilder: SendableInstantiator<S1_Screen>) {
					self.cache = cache
					self.screenBuilder = screenBuilder
				}

				@Instantiated let cache: \(cacheType)
				@Instantiated let screenBuilder: SendableInstantiator<S1_Screen>
			}

			public protocol S1_Service: Sendable {}
			""",
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_Screen: Instantiable, Sendable {
				public init(service: any S1_Service, stepBuilder: SendableInstantiator<S1_Step>) {
					self.service = service
					self.stepBuilder = stepBuilder
				}

				@Instantiated let service: any S1_Service
				@Instantiated let stepBuilder: SendableInstantiator<S1_Step>
			}
			""",
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_Step: Instantiable, Sendable {
				public init(cache: \(cacheType), screenBuilder: SendableInstantiator<S1_Screen>) {
					self.cache = cache
					self.screenBuilder = screenBuilder
				}

				@Instantiated let cache: \(cacheType)
				@Instantiated let screenBuilder: SendableInstantiator<S1_Screen>
			}
			""",
			"""
			// module: FuzzFeature

			@Instantiable
			public final class S1_Cache: Instantiable, Sendable {
				public init() {}
			}
			""",
			"""
			// module: FuzzApp
			import FuzzFeature

			@Instantiable(isRoot: true)
			public final class S1_Root0: Instantiable, Sendable {
				public init(home: S1_Home) {
					self.home = home
				}

				@Instantiated let home: S1_Home
			}
			""",
			"""
			// module: FuzzApp, fills a hole
			import FuzzFeature

			@Instantiable(fulfillingAdditionalTypes: [S1_Service.self])
			public final class S1_Impl: Instantiable, Sendable, S1_Service {
				public init(cache: \(cacheType)?) {
					self.cache = cache
				}

				@Received(onlyIfAvailable: true) let cache: \(cacheType)?
			}
			""",
		]
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
