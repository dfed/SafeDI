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

/// A world's loops of builders (`MadeAgainEdges`): each member makes again, at the top of its body, the members its tree
/// receives, a call of each from that top which is an edge of the reads closure and of the variants, never of the build
/// order or of a cycle.
struct SafeDIToolTypeFactsLoopTests: ~Copyable {
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
	mutating func generate_makesEachMemberAgainAtTheOthersTop_whenTwoSiblingBuildersReceiveEachOther() async throws {
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let aBuilder: Instantiator<A>"]),
		])
		let a = try node(declaring: "A as aBuilder: Instantiator<A>", in: report)
		let b = try node(declaring: "B as bBuilder: Instantiator<B>", in: report)

		#expect(report.nodes[a].madeAgain == [b], "\(report.world)")
		#expect(report.nodes[b].madeAgain == [a], "\(report.world)")
		// What a writer reads for each member's own argument: the label it rebinds, whose argument is the rebinding.
		#expect(report.nodes[a].madeAgainLabels == ["bBuilder"] && report.nodes[b].madeAgainLabels == ["aBuilder"], "\(report.world)")
		#expect(!report.nodes[a].isOnCycle && !report.nodes[b].isOnCycle, "\(report.world)")
		#expect(report.variantCountsByNode[a] == 1 && report.variantCountsByNode[b] == 1, "\(report.world)")
		expectMadeAgainCallsNameTheParentsCalls(in: report)
		// Each member's receive of the other reads the rebinding at its top, so each reads only the label it is built as,
		// and the member made again is handed its label made again.
		#expect(report.nodes[a].readsFromAbove == ["value(aBuilder)"] && report.nodes[b].readsFromAbove == ["value(bBuilder)"], "\(report.world)")
		let callOfB = try #require(report.variantMadeAgainCallSources[variant(of: a, in: report)].first)
		#expect(callOfB == ["bound madeAgain"], "\(report.world)")
		// A made-again call is a call: each member is called by its parent and made again by the other.
		#expect(try !report.variantIsCalledOnce[variant(of: a, in: report)] && !report.variantIsCalledOnce[variant(of: b, in: report)], "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRingOffEveryCycleAndSettlesItsReads_whenThreeBuildersReceiveEachNext() async throws {
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received let aBuilder: Instantiator<A>"]),
		])
		let members = try ["A as aBuilder: Instantiator<A>", "B as bBuilder: Instantiator<B>", "C as cBuilder: Instantiator<C>"].map { try node(declaring: $0, in: report) }

		#expect(members.map { report.nodes[$0].madeAgain } == [[members[1]], [members[2]], [members[0]]], "\(report.world)")
		#expect(members.allSatisfy { !report.nodes[$0].isOnCycle }, "\(report.world)")
		// Each member's receive reads its rebinding, and what the member it makes again reads but for that rebinding is
		// the label it is built as, which the next member rebinds: each member reads only its own label.
		#expect(members.map { report.nodes[$0].readsFromAbove } == [["value(aBuilder)"], ["value(bBuilder)"], ["value(cBuilder)"]], "\(report.world)")
		#expect(members.allSatisfy { report.variantCountsByNode[$0] == 1 }, "\(report.world)")
		expectMadeAgainCallsNameTheParentsCalls(in: report)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_answersOwnLabelMadeAgainBeneathMember_whenMembersTreeReceivesItsOwnBuilder() async throws {
		// A loop of one: `S1`, beneath `S0`, receives `s0Builder`. `S0` rebinds its own wrapper, so `S1` reads it made
		// again at `S0`, never being built.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let s0Builder: Instantiator<S0>"]),
			seamFixtureType(named: "S0", isFinalClass: true, declarations: ["@Instantiated let s1: S1"]),
			seamFixtureType(named: "S1", isFinalClass: true, declarations: ["@Received let s0Builder: Instantiator<S0>"]),
		])
		let s0 = try node(declaring: "S0 as s0Builder: Instantiator<S0>", in: report)
		let s1 = try node(declaring: "S1 as s1: S1", in: report)

		#expect(report.nodes[s0].madeAgain == [s0], "\(report.world)")
		#expect(!report.nodes[s0].isOnCycle, "\(report.world)")
		#expect(report.variantCountsByNode[s0] == 1, "\(report.world)")
		expectMadeAgainCallsNameTheParentsCalls(in: report)
		let callOfS1 = try #require(report.variantCallSources[variant(of: s0, in: report)].first)
		// `S1` reads `s0Builder`, then its own label, which `S0` declares.
		#expect(report.nodes[s1].readsFromAbove == ["value(s0Builder)", "value(s1)"], "\(report.world)")
		#expect(callOfS1.first == "bound madeAgain", "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesItsOwnRebindingForItsOwnLabel_whenMemberReceivesItsOwnBuilder() async throws {
		// A loop of one whose member's own type receives its label: that receive and the read of the label it is built as
		// are one read, which still reaches above, answered by the root's declaration being built, while the argument a
		// writer passes is the rebinding at the member's top, which `madeAgainLabels` names.
		let (report, output) = try await rootReportAndOutput(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let aBuilder: Instantiator<A>"]),
		])
		let a = try node(declaring: "A as aBuilder: Instantiator<A>", in: report)

		#expect(report.nodes[a].madeAgain == [a] && report.nodes[a].madeAgainLabels == ["aBuilder"], "\(report.world)")
		#expect(report.nodes[a].readsFromAbove == ["value(aBuilder)"], "\(report.world)")
		#expect(report.variantCountsByNode[a] == 1, "\(report.world)")
		expectMadeAgainCallsNameTheParentsCalls(in: report)
		#expect(output.generatedFiles?["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public convenience init() {
		        func __safeDI_aBuilder() -> A {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            return A(aBuilder: aBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        self.init(aBuilder: aBuilder)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesSendableMembersAgain_whenTwoSendableBuildersReceiveEachOther() async throws {
		// A loop of `SendableInstantiator` members, in production and in the mock: each made-again call keys as the
		// root's call of the member, family included. A loop that mixes a plain member with a `Sendable` one is rejected
		// in both directions (`SafeDIToolReceivedBuilderCycleTests`), since a ring that steps from one to the other steps
		// back too, so this is every family a loop can hold beside the plain one.
		let types = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: SendableInstantiator<A>", "@Instantiated let bBuilder: SendableInstantiator<B>"])
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let bBuilder: SendableInstantiator<B>"], conformances: ", Sendable"),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let aBuilder: SendableInstantiator<A>"], conformances: ", Sendable"),
		]
		for forMockGeneration in [false, true] {
			let report = try await rootReportAndOutput(of: types, forMockGeneration: forMockGeneration).report
			let a = try node(declaring: "A as aBuilder: SendableInstantiator<A>", in: report)
			let b = try node(declaring: "B as bBuilder: SendableInstantiator<B>", in: report)

			#expect(report.nodes[a].madeAgain == [b] && report.nodes[b].madeAgain == [a], "\(report.world)")
			expectMadeAgainCallsNameTheParentsCalls(in: report)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysMemberPerParent_whenTwoParentsAnswerWhatTheMemberItMakesAgainReadsApart() async throws {
		// `First` and `Second` each declare the loop `A`, `B`, and spell the router `B` receives apart, which keys a
		// variant per spelling. `A` reads no router itself; it makes `B` again at its top, so it reads what `B` reads
		// there, and has a variant per parent.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			"public protocol Routing {}",
			seamFixtureType(named: "LiveRouter", isFinalClass: true, declarations: [], conformances: ", Routing"),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated(fulfilledByType: \"LiveRouter\") let router: any Routing", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated(fulfilledByType: \"LiveRouter\") let router: Routing", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let aBuilder: Instantiator<A>", "@Received let router: any Routing"]),
		])
		let a = try node(declaring: "A as aBuilder: Instantiator<A>", in: report)

		#expect(report.nodes[a].readsFromAbove.contains("value(router)"), "\(report.world)")
		#expect(report.variantCountsByNode[a] == 2, "\(report.world)")
		expectMadeAgainCallsNameTheParentsCalls(in: report)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesAgainWhatEachMemberRebinds_whenARingRunsThroughAMembersTree() async throws {
		// `A` receives `bBuilder`, `B`'s child `E` receives `dBuilder`, and `D` receives `aBuilder`: the ring runs through a
		// member's tree, and each member makes again what its function rebinds.
		let (report, output) = try await rootReportAndOutput(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let dBuilder: Instantiator<D>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let e: E"]),
			seamFixtureType(named: "E", isFinalClass: true, declarations: ["@Received let dBuilder: Instantiator<D>"]),
			seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Received let aBuilder: Instantiator<A>"]),
		])
		let members = try ["A as aBuilder: Instantiator<A>", "B as bBuilder: Instantiator<B>", "D as dBuilder: Instantiator<D>"].map { try node(declaring: $0, in: report) }

		#expect(members.map { report.nodes[$0].madeAgain } == [[members[1]], [members[2]], [members[0]]], "\(report.world)")
		expectMadeAgainCallsNameTheParentsCalls(in: report)
		// Today's code: each member's function rebinds what the report says it makes again.
		#expect(output.generatedFiles?["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public convenience init() {
		        func __safeDI_aBuilder() -> A {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            return A(bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        func __safeDI_bBuilder() -> B {
		            let dBuilder = Instantiator<D>(__safeDI_dBuilder)
		            let e = E(dBuilder: dBuilder)
		            return B(e: e)
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        func __safeDI_dBuilder() -> D {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            return D(aBuilder: aBuilder)
		        }
		        let dBuilder = Instantiator<D>(__safeDI_dBuilder)
		        self.init(aBuilder: aBuilder, bBuilder: bBuilder, dBuilder: dBuilder)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesNothingAgainOfALabel_whenTheMemberDeclaresIt() async throws {
		// `A` declares its own `bBuilder`, which hides the root's from `A`'s tree, so `A` makes no `B` again. Its `B`
		// receives `aBuilder`, the `A` being built, which `A` makes again itself.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let aBuilder: Instantiator<A>"]),
		])
		let a = try node(declaring: "A as aBuilder: Instantiator<A>", in: report)
		let b = try node(declaring: "B as bBuilder: Instantiator<B>", in: report)

		#expect(report.nodes[a].madeAgain == [a], "\(report.world)")
		#expect(report.nodes[b].madeAgain.isEmpty, "\(report.world)")
		expectMadeAgainCallsNameTheParentsCalls(in: report)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_listsMemberSharedApart_whenAnotherParentBuildsItOffTheLoop() async throws {
		// The root's `A` and `B` are a loop. `Other` builds `A` as the same property without `B`, so `A` receives the
		// root's `bBuilder` there and makes nothing again: one node, two made-again sets.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let other: Other"]),
			seamFixtureType(named: "Other", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let aBuilder: Instantiator<A>"]),
		])
		let a = try node(declaring: "A as aBuilder: Instantiator<A>", in: report)

		#expect(report.loopMembersSharedApart == [a], "\(report.world)")
		#expect(report.nodes[a].madeAgain.isEmpty, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsVariantsPerNodeFixed_whenRingGrows() async throws {
		// A ring of n members, each receiving the next. Each member reads only the label it is built as, so the ring's keys
		// total n, with one variant per node, however long the ring.
		for memberCount in [4, 8, 16] {
			var rootDeclarations = [String]()
			var types = [String]()
			for member in 0..<memberCount {
				rootDeclarations.append("@Instantiated let m\(member)Builder: Instantiator<M\(member)>")
				types.append(seamFixtureType(named: "M\(member)", isFinalClass: true, declarations: ["@Received let m\((member + 1) % memberCount)Builder: Instantiator<M\((member + 1) % memberCount)>"]))
			}
			types.append(seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: rootDeclarations))
			let report = try await rootReport(of: types, skipCompileVerification: true)

			#expect(report.nodes.dropFirst().allSatisfy { $0.madeAgain.count == 1 && !$0.isOnCycle && $0.readsFromAbove.count == 1 }, "\(memberCount): \(report.world)")
			#expect(report.variantCountsByNode.allSatisfy { $0 == 1 }, "\(memberCount): \(report.world)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_answersOptionalReadMadeAgain_whenLoopMemberReceivesLaterSiblingsBuilderOnlyIfAvailable() async throws {
		// `A` receives `bBuilder` only if available and `B` receives `aBuilder`. The root binds `bBuilder` after `aBuilder`,
		// but `A`'s function begins by making `bBuilder` again, so `A`'s construction reads that: the read stays inside
		// `A`, where nothing the root binds later can answer it nil.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let bBuilder: Instantiator<B>?"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let aBuilder: Instantiator<A>"]),
		])
		let a = try node(declaring: "A as aBuilder: Instantiator<A>", in: report)
		let b = try node(declaring: "B as bBuilder: Instantiator<B>", in: report)

		#expect(report.nodes[a].madeAgain == [b] && report.nodes[b].madeAgain == [a], "\(report.world)")
		#expect(report.variantCountsByNode[a] == 1 && report.variantCountsByNode[b] == 1, "\(report.world)")
		#expect(report.nodes[a].readsFromAbove == ["value(aBuilder)"], "\(report.world)")
		#expect(try report.variantMadeAgainCallSources[variant(of: a, in: report)] == [["bound madeAgain"]], "\(report.world)")
		expectMadeAgainCallsNameTheParentsCalls(in: report)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_answersOptionalReadMadeAgain_whenTypeReceivesInstantiatorThatBuildsItOnlyIfAvailable() async throws {
		// A loop of one: `Editor` receives `editorBuilder`, the `Instantiator` being built around it, only if available.
		// `Editor`'s function begins by making `editorBuilder` again, so its construction reads that. Its reads of its own
		// label reach above, answered by the root's declaration being built, which keys as the rebinding does (rule 2),
		// never as nil.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let editorBuilder: Instantiator<Editor>"]),
			seamFixtureType(named: "Editor", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let editorBuilder: Instantiator<Editor>?"]),
		])
		let editor = try node(declaring: "Editor as editorBuilder: Instantiator<Editor>", in: report)

		#expect(report.nodes[editor].madeAgain == [editor], "\(report.world)")
		#expect(report.variantCountsByNode[editor] == 1, "\(report.world)")
		#expect(report.nodes[editor].readsFromAbove == ["value(editorBuilder)", "optionalValue(editorBuilder)", "optional(editorBuilder)"], "\(report.world)")
		#expect(report.variantCallSources[0] == [["bound beingBuilt", "bound beingBuilt", "bound beingBuilt"]], "\(report.world)")
		#expect(try report.variantMadeAgainCallSources[variant(of: editor, in: report)] == [["bound madeAgain", "bound madeAgain", "bound madeAgain"]], "\(report.world)")
		expectMadeAgainCallsNameTheParentsCalls(in: report)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysEachInnerMemberOnce_whenSiblingBuilderIsReceivedInsideLazyCycleOfEarlierSibling() async throws {
		// `A` and `B` instantiate one another lazily; `A` receives `qBuilder` and `Q` receives `bBuilder`, so `bBuilder` and
		// `qBuilder` make each other again.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let qBuilder: Instantiator<Q>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let innerBBuilder: Instantiator<B>", "@Received let qBuilder: Instantiator<Q>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let innerABuilder: Instantiator<A>"]),
			seamFixtureType(named: "Q", isFinalClass: true, declarations: ["@Received let bBuilder: Instantiator<B>"]),
		])
		let innerA = try node(declaring: "A as innerABuilder: Instantiator<A>", in: report)
		let innerB = try node(declaring: "B as innerBBuilder: Instantiator<B>", in: report)

		// Each inner member is placed beneath every path into the lazy cycle, and every call of it keys alike.
		#expect(report.places.count(where: { $0.node == innerA }) == 3 && report.places.count(where: { $0.node == innerB }) == 3, "\(report.world)")
		#expect(report.variantCountsByNode[innerA] == 1 && report.variantCountsByNode[innerB] == 1, "\(report.world)")
		expectMadeAgainCallsNameTheParentsCalls(in: report)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private func rootReport(of types: [String], skipCompileVerification: Bool = false) async throws -> TypeFactsReport {
		try await rootReportAndOutput(of: types, skipCompileVerification: skipCompileVerification).report
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private func rootReportAndOutput(of types: [String], skipCompileVerification: Bool = false, forMockGeneration: Bool = false) async throws -> (report: TypeFactsReport, output: TestOutput) {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		let output = try await ConstructionMemoOracle.$observer.withValue(TaskLocalFunction { _, _, report in continuation.yield(report) }) {
			var filesToDelete = [URL]()
			defer {
				for file in filesToDelete {
					try? FileManager.default.removeItem(at: file)
				}
			}
			return try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, skipCompileVerification: skipCompileVerification)
		}
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == "Root" && report.forMockGeneration == forMockGeneration {
			reports.append(report)
		}
		return try (#require(reports.last), output)
	}

	private func node(declaring declaration: String, in report: TypeFactsReport) throws -> Int {
		try #require(report.places.first(where: { $0.declaration == declaration })?.node, "\(report.world)")
	}

	/// The first variant of `node`.
	private func variant(of node: Int, in report: TypeFactsReport) throws -> Int {
		try #require(report.variantNodes.firstIndex(of: node), "\(report.world)")
	}

	/// Oracle B of the loop rule, as check 32 runs it on every tree: each made-again call names the variant its caller's
	/// parent calls for the member, at the parent's edge to it.
	private func expectMadeAgainCallsNameTheParentsCalls(in report: TypeFactsReport) {
		let result = TypeFactsChecks.findings(of: report)
		#expect(result.comparedByCheck[32, default: 0] == report.variantMadeAgainCalls.joined().count, "\(report.world)")
		#expect(result.findingsByCheck[32] == nil, "\(result.findingsByCheck[32] ?? []): \(report.world)")
	}
}
