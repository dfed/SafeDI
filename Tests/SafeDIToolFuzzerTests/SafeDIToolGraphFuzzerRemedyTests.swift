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

	// MARK: Known issues

	// The minimal graph of each shape `SafeDIToolGraphFuzzerTests.knownIssues` records under `remedyLeavesErrorAtSite`:
	// advice that does not fix its error. Each expects the advice to work, as a known issue, so fixing the diagnostic fails
	// the test until its known issue goes.

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
