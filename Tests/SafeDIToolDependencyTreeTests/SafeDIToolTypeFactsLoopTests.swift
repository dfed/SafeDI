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
		#expect(!report.nodes[a].isOnCycle && !report.nodes[b].isOnCycle, "\(report.world)")
		#expect(report.variantCountsByNode[a] == 1 && report.variantCountsByNode[b] == 1, "\(report.world)")
		expectMadeAgainCallsNameTheParentsCalls(in: report)
		// The member made again reads its own label, answered made again at its caller's top, and the other label, the
		// caller's own, passed through.
		let callOfB = try #require(report.variantMadeAgainCallSources[variant(of: a, in: report)].first)
		#expect(callOfB == ["passedThrough", "bound madeAgain"], "\(report.world)")
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
		// Each member makes the next again, which makes the one after again: what the ring reads reaches each member.
		#expect(members.allSatisfy { Set(report.nodes[$0].readsFromAbove).isSuperset(of: ["value(aBuilder)", "value(bBuilder)", "value(cBuilder)"]) }, "\(report.world)")
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
		// A ring of n members, each receiving the next. Each member makes the next again from its top, which makes the one
		// after again, so each member reads every label of the ring: n reads per member, n² keys in all, and one variant
		// per node however long the ring.
		for memberCount in [4, 8, 16] {
			var rootDeclarations = [String]()
			var types = [String]()
			for member in 0..<memberCount {
				rootDeclarations.append("@Instantiated let m\(member)Builder: Instantiator<M\(member)>")
				types.append(seamFixtureType(named: "M\(member)", isFinalClass: true, declarations: ["@Received let m\((member + 1) % memberCount)Builder: Instantiator<M\((member + 1) % memberCount)>"]))
			}
			types.append(seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: rootDeclarations))
			let report = try await rootReport(of: types, skipCompileVerification: true)

			#expect(report.nodes.dropFirst().allSatisfy { $0.madeAgain.count == 1 && !$0.isOnCycle && $0.readsFromAbove.count == memberCount }, "\(memberCount): \(report.world)")
			#expect(report.variantCountsByNode.allSatisfy { $0 == 1 }, "\(memberCount): \(report.world)")
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private func rootReport(of types: [String], skipCompileVerification: Bool = false) async throws -> TypeFactsReport {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		_ = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
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
		for await report in stream where report.root == "Root" && !report.forMockGeneration {
			reports.append(report)
		}
		return try #require(reports.last)
	}

	private func node(declaring declaration: String, in report: TypeFactsReport) throws -> Int {
		try #require(report.places.first(where: { $0.declaration == declaration })?.node, "\(report.world)")
	}

	/// The first variant of `node`.
	private func variant(of node: Int, in report: TypeFactsReport) throws -> Int {
		try #require(report.variantNodes.firstIndex(of: node), "\(report.world)")
	}

	/// Oracle B of the loop rule: each made-again call names the variant its caller's parent calls for the member, at the
	/// parent's edge to it. Every variant here is called from its parent, so the parent's variant is the one that calls the
	/// caller's.
	private func expectMadeAgainCallsNameTheParentsCalls(in report: TypeFactsReport) {
		for (caller, calls) in report.variantMadeAgainCalls.enumerated() {
			let callerNode = report.variantNodes[caller]
			for (index, callee) in calls.enumerated() {
				let member = report.nodes[callerNode].madeAgain[index]
				let parents = report.variantCalls.indices.filter { report.variantCalls[$0].contains(caller) }
				for parent in parents {
					let edges = report.nodes[report.variantNodes[parent]].edges
					guard let edge = edges.firstIndex(of: member) else { continue }
					#expect(report.variantCalls[parent][edge] == callee, "v\(caller) makes again v\(callee), where its parent v\(parent) calls v\(report.variantCalls[parent][edge]): \(report.world)")
				}
				#expect(!parents.isEmpty, "v\(caller) has no parent: \(report.world)")
			}
		}
	}
}
