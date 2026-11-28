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

import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The check that holds each place graph a module info file holds to the graph its run computed
/// (`StoredPlaceGraphChecks`), which every run of the multi-module harness makes.
struct SafeDIToolStoredPlaceGraphChecksTests {
	@Test
	func firstDifference_namesWhereTwoValuesDiffer_andCountsSourcePositionsAsAbsent() {
		struct Pair {
			let label: String
			let location: Dependency.DeclarationLocation?
			let members: Set<Int>
			let others: [String]
		}
		let location = Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1)
		let read = Pair(label: "first", location: nil, members: [1, 2, 3], others: ["a"])
		#expect(StoredPlaceGraphChecks.firstDifference(between: read, and: Pair(label: "first", location: location, members: [3, 2, 1], others: ["a"]), at: "pair") == nil)
		#expect(StoredPlaceGraphChecks.firstDifference(between: read, and: Pair(label: "second", location: location, members: [1, 2, 3], others: ["a"]), at: "pair") == "pair.label is read as `first`, and was computed as `second`")
		#expect(StoredPlaceGraphChecks.firstDifference(between: read, and: Pair(label: "first", location: nil, members: [1, 2, 4], others: ["a"]), at: "pair") == "pair.members.2 is read as `3`, and was computed as `4`")
		#expect(StoredPlaceGraphChecks.firstDifference(between: read, and: Pair(label: "first", location: nil, members: [1, 2, 3], others: ["a", "b"]), at: "pair") == "pair.others is read with 1 members, and was computed with 2")
		#expect(StoredPlaceGraphChecks.firstDifference(between: String?.some("a") as Any, and: String?.none as Any, at: "value") == "value is read as `a`, and was computed as absent")
		#expect(StoredPlaceGraphChecks.firstDifference(between: String?.none as Any, and: String?.some("a") as Any, at: "value") == "value is read as absent, and was computed as `a`")
		#expect(StoredPlaceGraphChecks.firstDifference(between: 1, and: "1", at: "value") == "value is read as a `Int`, and was computed as a `String`")
		#expect(StoredPlaceGraphChecks.firstDifference(between: Result<Int, Never>.success(1), and: Int?.some(1) as Any, at: "value") != nil)
	}

	@Test
	func expectGraphsReadBackAsComputed_recordsIssue_whenFileHoldsAnotherGraphOrNone() {
		let ownerCase = SeamSignature.Places.Case(ownerLevel: 0, isBuiltInSendableFunction: false, siteOpensSendableFunction: false, passedUp: nil)
		let computed = SeamSignature.Places(levels: [], cases: [ownerCase])
		// The same graph records nothing.
		StoredPlaceGraphChecks.expectGraphsReadBackAsComputed([.init(subject: "`Seam`", computed: computed, read: computed)], byRunOfModuleNamed: "Feature", sourceLocation: #_sourceLocation)
		withKnownIssue {
			StoredPlaceGraphChecks.expectGraphsReadBackAsComputed([.init(subject: "`Seam`", computed: computed, read: SeamSignature.Places(levels: [], cases: []))], byRunOfModuleNamed: "Feature", sourceLocation: #_sourceLocation)
		} matching: { issue in
			issue.description.contains("A place graph the run of module `Feature` wrote reads back as another graph than the one it computed: the places of `Seam`.cases is read with 0 members, and was computed with 1")
		}
		withKnownIssue {
			StoredPlaceGraphChecks.expectGraphsReadBackAsComputed([.init(subject: "`Seam`", computed: computed, read: nil)], byRunOfModuleNamed: "Feature", sourceLocation: #_sourceLocation)
		} matching: { issue in
			issue.description.contains("the places of `Seam` is read as absent, and was computed as")
		}
		withKnownIssue {
			let sendableCase = SeamSignature.Places.Case(ownerLevel: 0, isBuiltInSendableFunction: true, siteOpensSendableFunction: false, passedUp: nil)
			StoredPlaceGraphChecks.expectGraphsReadBackAsComputed([.init(subject: "`Seam`", computed: computed, read: SeamSignature.Places(levels: [], cases: [sendableCase]))], byRunOfModuleNamed: "Feature", sourceLocation: #_sourceLocation)
		} matching: { issue in
			issue.description.contains("the places of `Seam`.cases.0.isBuiltInSendableFunction is read as `true`, and was computed as `false`")
		}
	}

	@Test
	func expectGraphsReadBackAsComputed_recordsIssue_whenFileHoldsAnotherGraphOfSeamOrOtherSeams() throws {
		func signature(of seam: String, cases: [SeamSignature.Places.Case]) -> StoredSeamSignature {
			let seamType = TypeDescription.simple(name: seam)
			return StoredSeamSignature(seamType: seamType, signature: SeamSignature(seamType: seamType, parameters: [], tiers: [.public], places: SeamSignature.Places(levels: [], cases: cases)))
		}
		let plainCase = SeamSignature.Places.Case(ownerLevel: 0, isBuiltInSendableFunction: false, siteOpensSendableFunction: false, passedUp: nil, namingRoute: [0])
		let sendableCase = SeamSignature.Places.Case(ownerLevel: 0, isBuiltInSendableFunction: true, siteOpensSendableFunction: false, passedUp: nil, namingRoute: [0])
		// A seam whose generated signature is its own initializer's stores none, and has no graph on either side.
		let written = [signature(of: "Host", cases: [plainCase]), signature(of: "Panel", cases: [plainCase, sendableCase]), StoredSeamSignature(seamType: .simple(name: "Plain"), signature: nil)]
		let file = try ModuleInfoFile(moduleInfoData: ModuleInfoFile(
			moduleName: "Feature",
			packageName: nil,
			dependencyModuleNames: [],
			imports: [],
			mockImports: [],
			instantiables: [],
			configurations: [],
			filesWithUnexpectedNodes: nil,
			conditionalCompilationDecisions: [],
			instantiableTypeNamesInAnyClause: [],
			plainTypeDeclarations: [],
			seamSignatures: written,
			view: .empty,
		).moduleInfoData)
		// The signatures the file was written from record nothing.
		StoredPlaceGraphChecks.expectGraphsReadBackAsComputed(ofSeamSignatures: written, in: file, writtenByRunOfModuleNamed: "Feature", sourceLocation: #_sourceLocation)
		withKnownIssue {
			let computed = [written[0], signature(of: "Panel", cases: [plainCase, plainCase]), written[2]]
			StoredPlaceGraphChecks.expectGraphsReadBackAsComputed(ofSeamSignatures: computed, in: file, writtenByRunOfModuleNamed: "Feature", sourceLocation: #_sourceLocation)
		} matching: { issue in
			issue.description.contains("A place graph the run of module `Feature` wrote reads back as another graph than the one it computed: the places of seam `Panel`.cases.1.isBuiltInSendableFunction is read as `true`, and was computed as `false`")
		}
		withKnownIssue {
			StoredPlaceGraphChecks.expectGraphsReadBackAsComputed(ofSeamSignatures: written + [signature(of: "Sheet", cases: [plainCase])], in: file, writtenByRunOfModuleNamed: "Feature", sourceLocation: #_sourceLocation)
		} matching: { issue in
			issue.description.contains("the places of seam `Sheet` is read as absent, and was computed as")
		}
		withKnownIssue {
			StoredPlaceGraphChecks.expectGraphsReadBackAsComputed(ofSeamSignatures: [written[1], written[2]], in: file, writtenByRunOfModuleNamed: "Feature", sourceLocation: #_sourceLocation)
		} matching: { issue in
			issue.description.contains("the places of seam `Host` is read as") && issue.description.contains("and was computed as absent")
		}
	}

	@Test
	func expectGraphsReadBackAsComputed_recordsIssue_whenFileHoldsAnotherGraphOfPublicMockOrMockTheRunDidNotCompute() throws {
		func plan(of mockedType: String, cases: [SeamSignature.Places.Case]) -> StoredPublicMockPlan {
			StoredPublicMockPlan(
				mockedType: .simple(name: mockedType),
				parameters: [],
				noTierParameters: [],
				tiers: [.public],
				guardTypeName: "\(mockedType)Guard",
				holes: [],
				builders: [],
				scopeEnums: [],
				places: SeamSignature.Places(levels: [], cases: cases),
				caseIndexByHole: [0, -1],
				receivers: [],
				typesDeclaredEscaping: [],
			)
		}
		let plainCase = SeamSignature.Places.Case(ownerLevel: 0, isBuiltInSendableFunction: false, siteOpensSendableFunction: false, passedUp: nil, namingRoute: [0])
		let sendableCase = SeamSignature.Places.Case(ownerLevel: 0, isBuiltInSendableFunction: true, siteOpensSendableFunction: false, passedUp: nil, namingRoute: [0])
		let written = [plan(of: "Host", cases: [plainCase]), plan(of: "Panel", cases: [plainCase, sendableCase])]
		let file = try ModuleInfoFile(moduleInfoData: ModuleInfoFile(
			moduleName: "Feature",
			packageName: nil,
			dependencyModuleNames: [],
			imports: [],
			mockImports: [],
			instantiables: [],
			configurations: [],
			filesWithUnexpectedNodes: nil,
			conditionalCompilationDecisions: [],
			instantiableTypeNamesInAnyClause: [],
			plainTypeDeclarations: [],
			seamSignatures: ModuleSeamSignatures([]),
			publicMockPlans: ModulePublicMockPlans(written, compilesGeneratedMocks: false),
			view: .empty,
		).moduleInfoData)
		// The plans the file was written from record nothing, and neither does a plan the run computed that the file
		// leaves out.
		StoredPlaceGraphChecks.expectGraphsReadBackAsComputed(ofPublicMockPlans: written + [plan(of: "Sheet", cases: [plainCase])], in: file, writtenByRunOfModuleNamed: "Feature", sourceLocation: #_sourceLocation)
		withKnownIssue {
			StoredPlaceGraphChecks.expectGraphsReadBackAsComputed(ofPublicMockPlans: [written[0], plan(of: "Panel", cases: [plainCase, plainCase])], in: file, writtenByRunOfModuleNamed: "Feature", sourceLocation: #_sourceLocation)
		} matching: { issue in
			issue.description.contains("A place graph the run of module `Feature` wrote reads back as another graph than the one it computed: the places of the public mock of `Panel`.cases.1.isBuiltInSendableFunction is read as `true`, and was computed as `false`")
		}
		withKnownIssue {
			StoredPlaceGraphChecks.expectGraphsReadBackAsComputed(ofPublicMockPlans: [written[1]], in: file, writtenByRunOfModuleNamed: "Feature", sourceLocation: #_sourceLocation)
		} matching: { issue in
			issue.description.contains("the places of the public mock of `Host` is read as") && issue.description.contains("and was computed as absent")
		}
	}
}
