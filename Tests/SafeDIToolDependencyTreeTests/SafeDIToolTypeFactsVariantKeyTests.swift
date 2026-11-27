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

/// The two parameter rules of a world's variant key (`TypeFactsGraph.optionalParameterKey`): a difference a body's
/// parameter carries keys alike, so a type built under parents that differ only in it has one body.
struct SafeDIToolTypeFactsVariantKeyTests: ~Copyable {
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
	mutating func generate_keysOneVariant_whenReceiveOnlyIfAvailableIsAnsweredUnderOneParentAndNilUnderTheOther() async throws {
		// Rule 1: `Child` reads `x` only if available; `First` declares it and `Second` does not, so one place is handed
		// the value and the other `nil`, which an optional parameter carries.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let child: Child"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])

		#expect(report.places.count(where: { $0.declaration == "Child as child: Child" }) == 2, "\(report.world)")
		#expect(variantCount(ofNodeDeclaring: "Child as child: Child", in: report) == 1, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysVariantPerParameterType_whenReceiveOnlyIfAvailableIsAnsweredByValueUnderOneParentAndLazilyUnderTheOther() async throws {
		// Rule 1 keeps whether a lazy wrapper answers: `First` declares `x` by value and `Second` lazily, so the place under
		// `Second` reads the wrapper's instance where it reads `x`, and its body takes the wrapper, not the value.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let child: Child"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])

		#expect(variantCount(ofNodeDeclaring: "Child as child: Child", in: report) == 2, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysVariantPerParameterType_whenReceiveOnlyIfAvailableIsAnsweredLazilyUnderOneParentAndNilUnderTheOther() async throws {
		// `nil` keys apart from a lazy wrapper's answer until rule 3's second stage, which lets a `nil` wrapper parameter
		// stand for it: this count is the one that stage changes.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let child: Child"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])

		#expect(variantCount(ofNodeDeclaring: "Child as child: Child", in: report) == 2, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysVariantPerSpelling_whenParentsSpellTheReceivedTypeApart() async throws {
		// One parent spells the router `any Routing` and the other `Routing`, which name one type: today's code has a
		// function per spelling, each typed as its parent spells it, so the key keeps the declared spelling. Answers by ID
		// must keep this count, or the merge is a change of generated code (SafeDIToolTypeKeyViewTests' twin of this shape).
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			"public protocol Routing {}",
			seamFixtureType(named: "LiveRouter", isFinalClass: true, declarations: [], conformances: ", Routing"),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated(fulfilledByType: \"LiveRouter\") let router: any Routing", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated(fulfilledByType: \"LiveRouter\") let router: Routing", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
			seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Received let router: any Routing"]),
		])

		#expect(variantCount(ofNodeDeclaring: "Detail as detailBuilder: Instantiator<Detail>", in: report) == 2, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsVariantsPerNodeFixed_whenAlternatingParentsDeclareTokenOnOneSideAndEveryLayerDoublesThePaths() async throws {
		// rows.py's alternating row: layer i's left parent declares `token<i>` and its right one does not, both open both
		// parents of the next layer, and a reader beneath every parent receives each token only if available. Rule 1
		// keys every answer alike, so the paths double at each layer while the variants stay one per node.
		for layerCount in [4, 8] {
			var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let left0Builder: Instantiator<Left0>", "@Instantiated let right0Builder: Instantiator<Right0>"])]
			types.append(seamFixtureType(named: "Reader", isFinalClass: true, declarations: (0..<layerCount).map { "@Received(onlyIfAvailable: true) let token\($0): Token\($0)?" }))
			for layer in 0..<layerCount {
				let next = layer == layerCount - 1
					? ["@Instantiated let reader: Reader"]
					: ["@Instantiated let left\(layer + 1)Builder: Instantiator<Left\(layer + 1)>", "@Instantiated let right\(layer + 1)Builder: Instantiator<Right\(layer + 1)>"]
				types.append(seamFixtureType(named: "Token\(layer)", isFinalClass: true, declarations: []))
				types.append(seamFixtureType(named: "Left\(layer)", isFinalClass: true, declarations: ["@Instantiated let token\(layer): Token\(layer)"] + next))
				types.append(seamFixtureType(named: "Right\(layer)", isFinalClass: true, declarations: next))
			}
			let report = try await rootReport(of: types, skipCompileVerification: true)

			#expect(report.places.count(where: { $0.declaration == "Reader as reader: Reader" }) == 1 << layerCount, "\(layerCount)")
			#expect(report.variantCountsByNode.allSatisfy { $0 == 1 }, "\(layerCount): \(report.world)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsVariantsPerNodeFixed_whenReaderReceivesEveryLayersBuilderStillBeingBuiltOnHalfThePaths() async throws {
		// rows.py's being-built row: each layer's two parents both open both builders of the next, and the reader receives
		// every layer's left builder, which is still being built on each path through `Left<i>` and built on the others.
		// Rule 2 keys a wrapper alike either way.
		for layerCount in [4, 8] {
			var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let left0Builder: Instantiator<Left0>", "@Instantiated let right0Builder: Instantiator<Right0>"])]
			types.append(seamFixtureType(named: "Reader", isFinalClass: true, declarations: (0..<layerCount).map { "@Received let left\($0)Builder: Instantiator<Left\($0)>" }))
			for layer in 0..<layerCount {
				let next = layer == layerCount - 1
					? ["@Instantiated let reader: Reader"]
					: ["@Instantiated let left\(layer + 1)Builder: Instantiator<Left\(layer + 1)>", "@Instantiated let right\(layer + 1)Builder: Instantiator<Right\(layer + 1)>"]
				types.append(seamFixtureType(named: "Left\(layer)", isFinalClass: true, declarations: next))
				types.append(seamFixtureType(named: "Right\(layer)", isFinalClass: true, declarations: next))
			}
			let report = try await rootReport(of: types, skipCompileVerification: true)

			#expect(report.places.count(where: { $0.declaration == "Reader as reader: Reader" }) == 1 << layerCount, "\(layerCount)")
			#expect(report.variantCountsByNode.allSatisfy { $0 == 1 }, "\(layerCount): \(report.world)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsVariantsPerNodeFixed_whenHubsLeafReceivesEveryMembersLabelOnlyIfAvailable() async throws {
		// rows.py's hub-members row: a hub opens each member, each member declares its own label and opens the hub again,
		// and the hub's leaf receives every member's label only if available. Rule 1 keys every answer alike, so the hub
		// has one variant however many members reach it. (The lazy row waits on rule 3.)
		for memberCount in [4, 8] {
			var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let hubBuilder: Instantiator<Hub>"])]
			types.append(seamFixtureType(named: "Hub", isFinalClass: true, declarations: ["@Instantiated let leaf: Leaf"] + (0..<memberCount).map { "@Instantiated let member\($0)Builder: Instantiator<Member\($0)>" }))
			types.append(seamFixtureType(named: "Leaf", isFinalClass: true, declarations: (0..<memberCount).map { "@Received(onlyIfAvailable: true) let label\($0): Label\($0)?" }))
			for member in 0..<memberCount {
				types.append(seamFixtureType(named: "Label\(member)", isFinalClass: true, declarations: []))
				types.append(seamFixtureType(named: "Member\(member)", isFinalClass: true, declarations: ["@Instantiated let label\(member): Label\(member)", "@Instantiated let hubBuilder: Instantiator<Hub>"]))
			}
			let report = try await rootReport(of: types, skipCompileVerification: true)

			#expect(report.variantCountsByNode.allSatisfy { $0 == 1 }, "\(memberCount): \(report.world)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysOneVariant_whenReceivedWrapperIsBeingBuiltUnderOneParentOnly() async throws {
		// Rule 2: `Child` receives `firstBuilder`, which is still being built where `First` builds `Child` and is not
		// where `Second` does; the wrapper is passed and made again at the call, so the difference keys alike.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let firstBuilder: Instantiator<First>", "@Instantiated let second: Second"]),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let child: Child"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received let firstBuilder: Instantiator<First>"]),
		])

		#expect(report.places.count(where: { $0.declaration == "Child as child: Child" }) >= 2, "\(report.world)")
		#expect(variantCount(ofNodeDeclaring: "Child as child: Child", in: report) == 1, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_answersBeingBuilt_whenConstantChildsOwnLabelIsReadBeneathIt() async throws {
		// `First` builds `home` by value, and `Leaf` beneath it receives `home` only if available, so the answer `First`
		// binds at its edge to `home` is the declaration being built, whose key text is the answer's own.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First"]),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let home: Home"]),
			seamFixtureType(named: "Home", isFinalClass: true, declarations: ["@Instantiated let leaf: Leaf"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let home: Home?"]),
		])

		#expect(report.world.contains("bound beingBuilt"), "\(report.world)")
		#expect(!report.world.contains("bound declared"), "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_answersNone_whenParentBindsReadLabelAfterTheCall() async throws {
		// `Second` receives `first`, so `Root` builds `first` before `second`, and `Leaf` beneath `first` receives `second`
		// only if available: at the edge to `first` nothing of `Root` answers `second` yet, and `Leaf` is handed nil, as the
		// generated code passes it.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let leaf: Leaf"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Received let first: First"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let second: Second?"]),
		])

		// `Second` receives `first`, so `Root` builds `first` first: its call answers `second`'s two reads none.
		#expect(report.world.contains("v0 d0 plain keys [] calls [1, 2] sources [[\"bound beingBuilt\", \"none\", \"none\"], [\"bound declared\", \"bound beingBuilt\"]]"), "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysOneVariant_whenValueTwinAndLazyTwinOfOneLabelAreBeingBuilt() async throws {
		// Rule 3, case 2: `Leaf` receives `home` only if available beneath the `home` being built, by value under `First`
		// and lazily under `Second`; either way it is `nil` and 2.4.0 builds one function for the identity, so one body.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let home: Home"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let home: LazilyInstantiated<Home>"]),
			seamFixtureType(named: "Home", isFinalClass: true, declarations: ["@Instantiated let leaf: Leaf"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let home: Home?"]),
		])

		#expect(report.places.count(where: { $0.declaration == "Leaf as leaf: Leaf" }) == 2, "\(report.world)")
		#expect(variantCount(ofNodeDeclaring: "Leaf as leaf: Leaf", in: report) == 1, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysOneVariant_whenReceiveOnlyIfAvailableIsUnansweredUnderOneParentAndBeingBuiltUnderTheOther() async throws {
		// `A` receives `theme` only if available: `Root` declares none, and the cycle `Theme` closes on `aBuilder` reads the
		// `theme` `Mid` is still building. Both pass `nil`, and 2.4.0 builds one function of `A`, so one body.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let theme: Theme?", "@Instantiated let midBuilder: Instantiator<Mid>"]),
			seamFixtureType(named: "Mid", isFinalClass: true, declarations: ["@Instantiated let theme: Theme"]),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
		])

		#expect(report.places.count(where: { $0.declaration == "A as aBuilder: Instantiator<A>" }) == 2, "\(report.world)")
		#expect(variantCount(ofNodeDeclaring: "A as aBuilder: Instantiator<A>", in: report) == 1, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysOneVariant_whenReceiveOnlyIfAvailableIsUnansweredUnderOneParentAndALazyWrapperBeingBuiltUnderTheOther() async throws {
		// As above, with `Mid` building `theme` lazily and `A` receiving the wrapper: both calls still pass `nil`.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let theme: LazilyInstantiated<Theme>?", "@Instantiated let midBuilder: Instantiator<Mid>"]),
			seamFixtureType(named: "Mid", isFinalClass: true, declarations: ["@Instantiated let theme: LazilyInstantiated<Theme>"]),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
		])

		#expect(report.places.count(where: { $0.declaration == "A as aBuilder: Instantiator<A>" }) == 2, "\(report.world)")
		#expect(variantCount(ofNodeDeclaring: "A as aBuilder: Instantiator<A>", in: report) == 1, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysVariantPerOtherRead_whenTwinsBeingBuiltReadAnotherLabelInOtherForms() async throws {
		// Rule 3, case 2 drops only the being-built answer's form: `Leaf` also requires `theme`, which `First` declares by
		// value and `Second` lazily, so the two bodies stay apart by `theme` alone.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let home: Home"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let theme: LazilyInstantiated<Theme>", "@Instantiated let home: LazilyInstantiated<Home>"]),
			seamFixtureType(named: "Home", isFinalClass: true, declarations: ["@Instantiated let leaf: Leaf"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let home: Home?", "@Received let theme: Theme"]),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
		])

		#expect(variantCount(ofNodeDeclaring: "Leaf as leaf: Leaf", in: report) == 2, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_answersBoundButNotProvided_whenNearestDeclarationOfLabelIsAnotherType() async throws {
		// `Entry0` binds `mark: OtherMark` before it builds `ring0Builder`, whose `Ring0` receives `mark: Mark?` only if
		// available: the answer at the edge is bound, but provides no form the subtree reads, so the call passes `nil`, as
		// the generated `Ring0(ring1Builder: ring1Builder, mark: nil)` does. A farther `mark: Mark` above `Entry0` would be
		// rejected as hidden in the chain, so nothing farther is handed.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let entry0: Entry0"]),
			seamFixtureType(named: "Entry0", isFinalClass: true, declarations: ["@Instantiated let mark: OtherMark", "@Instantiated let ring0Builder: Instantiator<Ring0>"]),
			seamFixtureType(named: "Ring0", isFinalClass: true, declarations: ["@Instantiated let ring1Builder: Instantiator<Ring1>", "@Received(onlyIfAvailable: true) let mark: Mark?"]),
			seamFixtureType(named: "Ring1", isFinalClass: true, declarations: ["@Instantiated let ring0Builder: Instantiator<Ring0>"]),
			seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
			seamFixtureType(named: "OtherMark", isFinalClass: true, declarations: []),
		])

		// The call of `Ring0` answers its two reads of `mark` (only if available, and optional) by `mark: OtherMark`.
		#expect(report.world.contains("[\"bound beingBuilt\", \"bound declared not provided\", \"bound declared not provided\"]"), "\(report.world)")
		#expect(report.world.components(separatedBy: "not provided").count == 3, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_ordersParametersAsBodyFirstReceives_whenAnEarlierSiblingReadsALaterLabelFirst() async throws {
		// `Early` reads `alpha` before the world reaches `Ring0`, so the world's reads order `alpha` first (and read
		// `ring0Builder`, the label of the cycle `Ring1` closes, which is no parameter), while
		// `Ring0`'s body receives `zeta` itself before its `leaf` receives `alpha`: the generated functions are
		// `__safeDI_ring0Builder(zeta: Zeta?, alpha: Alpha?)` and `__safeDI_ring1Builder(zeta: Zeta?, alpha: Alpha?)`.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let entry0: Entry0"]),
			seamFixtureType(named: "Entry0", isFinalClass: true, declarations: ["@Instantiated let alpha: Alpha", "@Instantiated let zeta: Zeta", "@Instantiated let early: Early", "@Instantiated let ring0Builder: Instantiator<Ring0>"]),
			seamFixtureType(named: "Early", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let alpha: Alpha?"]),
			seamFixtureType(named: "Ring0", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let zeta: Zeta?", "@Instantiated let leaf: Leaf", "@Instantiated let ring1Builder: Instantiator<Ring1>"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let alpha: Alpha?"]),
			seamFixtureType(named: "Ring1", isFinalClass: true, declarations: ["@Instantiated let ring0Builder: Instantiator<Ring0>"]),
			seamFixtureType(named: "Alpha", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Zeta", isFinalClass: true, declarations: []),
		])
		let graph = report.graph
		func labelTexts(_ labels: some Sequence<WorldLabelID>) -> [String] {
			labels.map { graph.labelTexts[Int($0)] }
		}
		let ring0 = try #require(report.nodes.firstIndex { $0.description.hasPrefix("Ring0 ") })
		let ring1 = try #require(report.nodes.firstIndex { $0.description.hasPrefix("Ring1 ") })

		#expect(labelTexts(graph.labels(of: Int32(ring0))) == ["alpha", "ring0Builder", "zeta"])
		#expect(labelTexts(graph.parameterOrder(of: Int32(ring0))) == ["zeta", "alpha"])
		#expect(labelTexts(graph.parameterOrder(of: Int32(ring1))) == ["zeta", "alpha"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_ordersParametersAsBodyFirstReceives_whenTheBodyReceivesALabelThroughARename() async throws {
		// As above, with `Ring0` receiving `zeta` through a rename: the rename receives `zeta` itself, before its `leaf`
		// receives `alpha`, so `zeta` still comes first.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let entry0: Entry0"]),
			seamFixtureType(named: "Entry0", isFinalClass: true, declarations: ["@Instantiated let alpha: Alpha", "@Instantiated let zeta: Zeta", "@Instantiated let early: Early", "@Instantiated let ring0Builder: Instantiator<Ring0>"]),
			seamFixtureType(named: "Early", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let alpha: Alpha?"]),
			seamFixtureType(named: "Ring0", isFinalClass: true, declarations: ["@Received(fulfilledByDependencyNamed: \"zeta\", ofType: Zeta.self) let renamedZeta: Zeta", "@Instantiated let leaf: Leaf", "@Instantiated let ring1Builder: Instantiator<Ring1>"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let alpha: Alpha?"]),
			seamFixtureType(named: "Ring1", isFinalClass: true, declarations: ["@Instantiated let ring0Builder: Instantiator<Ring0>"]),
			seamFixtureType(named: "Alpha", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Zeta", isFinalClass: true, declarations: []),
		])
		let graph = report.graph
		func labelTexts(_ labels: some Sequence<WorldLabelID>) -> [String] {
			labels.map { graph.labelTexts[Int($0)] }
		}
		let ring0 = try #require(report.nodes.firstIndex { $0.description.hasPrefix("Ring0 ") })
		let ring1 = try #require(report.nodes.firstIndex { $0.description.hasPrefix("Ring1 ") })

		#expect(labelTexts(graph.labels(of: Int32(ring0))) == ["zeta", "alpha", "ring0Builder"])
		#expect(labelTexts(graph.parameterOrder(of: Int32(ring0))) == ["zeta", "alpha"])
		#expect(labelTexts(graph.parameterOrder(of: Int32(ring1))) == ["zeta", "alpha"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysOneVariant_whenReceiveOfAWrapperOnlyIfAvailableIsPassedTheWrapperAtOnePlaceAndNilAtAnother() async throws {
		// `Logger` receives `analytics: LazilyInstantiated<Analytics>?`: beneath the `analytics` being built it is passed `nil`,
		// beneath `Screen` the wrapper, which is the form the receive declares. Both pass through one optional parameter, as
		// 2.4.x writes one `__safeDI_loggerBuilder(analytics:)` for both, so rule 1 keys them alike.
		let (tree, report) = try await generatedTreeAndReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let analytics: LazilyInstantiated<Analytics>", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: ["@Instantiated let loggerBuilder: Instantiator<Logger>"]),
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Instantiated let loggerBuilder: Instantiator<Logger>"]),
			seamFixtureType(named: "Logger", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let analytics: LazilyInstantiated<Analytics>?", "@Instantiated let loggerBuilder: Instantiator<Logger>"]),
		])

		#expect(tree == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_loggerBuilder(analytics: LazilyInstantiated<Analytics>?) -> Logger {
		            let loggerBuilder = Instantiator<Logger> {
		                __safeDI_loggerBuilder(analytics: analytics)
		            }
		            return Logger(analytics: analytics, loggerBuilder: loggerBuilder)
		        }
		        func __safeDI_analytics() -> Analytics {
		            let loggerBuilder = Instantiator<Logger> {
		                __safeDI_loggerBuilder(analytics: nil)
		            }
		            return Analytics(loggerBuilder: loggerBuilder)
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        func __safeDI_screen() -> Screen {
		            let loggerBuilder = Instantiator<Logger> {
		                __safeDI_loggerBuilder(analytics: analytics)
		            }
		            return Screen(loggerBuilder: loggerBuilder)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(analytics: analytics, screen: screen)
		    }
		}
		"""])
		#expect(variantCount(ofNodeDeclaring: "Logger as loggerBuilder: Instantiator<Logger>", in: report) == 1, "\(report.world)")
		#expect(TypeFactsChecks.findings(of: report).findingsByCheck[10, default: []].isEmpty, "\(TypeFactsChecks.findings(of: report).findingsByCheck[10, default: []])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysOneVariant_whenAnotherTypeOutsideTheSubtreeReceivesTheLabelInTheOtherForm() async throws {
		// `Logger` as in `generate_keysOneVariant_whenReceiveOfAWrapperOnlyIfAvailableIsPassedTheWrapperAtOnePlaceAndNilAtAnother`,
		// with `Other` beside `Screen` receiving `analytics: Analytics?`: the form a wrapper keys by is the one `Logger`'s
		// subtree reads, so a type that only shares the label's name changes nothing.
		let (_, report) = try await generatedTreeAndReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let analytics: LazilyInstantiated<Analytics>", "@Instantiated let screen: Screen", "@Instantiated let other: Other"]),
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: ["@Instantiated let loggerBuilder: Instantiator<Logger>"]),
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Instantiated let loggerBuilder: Instantiator<Logger>"]),
			seamFixtureType(named: "Other", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let analytics: Analytics?"]),
			seamFixtureType(named: "Logger", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let analytics: LazilyInstantiated<Analytics>?", "@Instantiated let loggerBuilder: Instantiator<Logger>"]),
		])

		#expect(variantCount(ofNodeDeclaring: "Logger as loggerBuilder: Instantiator<Logger>", in: report) == 1, "\(report.world)")
		#expect(TypeFactsChecks.findings(of: report).findingsByCheck[10, default: []].isEmpty, "\(TypeFactsChecks.findings(of: report).findingsByCheck[10, default: []])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysNilWithTheValue_whenReceiveOfTheValueIsAnsweredByTheValueAWrapperAndNothing() async throws {
		// `Leaf` receives `theme: Theme?`: `First` passes its value and `Third` nothing, both through `theme: Theme?`; `Second`'s
		// wrapper is a parameter of another type, whose instance `Leaf` reads. 2.4.x writes the same two functions.
		let (tree, report) = try await generatedTreeAndReport(of: Self.leafFixture(places: [("First", "Theme"), ("Second", "LazilyInstantiated<Theme>"), ("Third", nil)]))

		#expect(tree == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_leafBuilder(theme: Theme?) -> Leaf {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: theme)
		            }
		            return Leaf(theme: theme, leafBuilder: leafBuilder)
		        }
		        func __safeDI_first() -> First {
		            let theme = Theme()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: theme)
		            }
		            return First(theme: theme, leafBuilder: leafBuilder)
		        }
		        let first: First = __safeDI_first()
		        func __safeDI_theme() -> Theme {
		            Theme()
		        }
		        func __safeDI_leafBuilder_(theme: LazilyInstantiated<Theme>) -> Leaf {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder_(theme: theme)
		            }
		            return Leaf(theme: theme.instance, leafBuilder: leafBuilder)
		        }
		        func __safeDI_second() -> Second {
		            let theme = LazilyInstantiated<Theme>(__safeDI_theme)
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder_(theme: theme)
		            }
		            return Second(theme: theme, leafBuilder: leafBuilder)
		        }
		        let second: Second = __safeDI_second()
		        func __safeDI_third() -> Third {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: nil)
		            }
		            return Third(leafBuilder: leafBuilder)
		        }
		        let third: Third = __safeDI_third()
		        self.init(first: first, second: second, third: third)
		    }
		}
		"""])
		#expect(variantCount(ofNodeDeclaring: "Leaf as leafBuilder: Instantiator<Leaf>", in: report) == 2, "\(report.world)")
		#expect(TypeFactsChecks.findings(of: report).findingsByCheck[10, default: []].isEmpty, "\(TypeFactsChecks.findings(of: report).findingsByCheck[10, default: []])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysNilWithTheValue_whenThePlaceThatPassesNilIsDeclaredFirst() async throws {
		// The places of `generate_keysNilWithTheValue_whenReceiveOfTheValueIsAnsweredByTheValueAWrapperAndNothing`, declared
		// in the other order. Rule 1 keys `nil` by the form the receive declares, wherever its place is, so the variants are
		// those of the first order. 2.4.x chose by declaration order: it passes `nil` to the function of the first place that
		// passes anything, here `Second`'s wrapper, made optional (`__safeDI_leafBuilder(theme: LazilyInstantiated<Theme>?)`).
		let (tree, report) = try await generatedTreeAndReport(of: Self.leafFixture(places: [("Third", nil), ("Second", "LazilyInstantiated<Theme>"), ("First", "Theme")]))

		#expect(tree == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_leafBuilder(theme: LazilyInstantiated<Theme>?) -> Leaf {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: theme)
		            }
		            return Leaf(theme: theme?.instance, leafBuilder: leafBuilder)
		        }
		        func __safeDI_third() -> Third {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: nil)
		            }
		            return Third(leafBuilder: leafBuilder)
		        }
		        let third: Third = __safeDI_third()
		        func __safeDI_theme() -> Theme {
		            Theme()
		        }
		        func __safeDI_second() -> Second {
		            let theme = LazilyInstantiated<Theme>(__safeDI_theme)
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: theme)
		            }
		            return Second(theme: theme, leafBuilder: leafBuilder)
		        }
		        let second: Second = __safeDI_second()
		        func __safeDI_leafBuilder_(theme: Theme?) -> Leaf {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder_(theme: theme)
		            }
		            return Leaf(theme: theme, leafBuilder: leafBuilder)
		        }
		        func __safeDI_first() -> First {
		            let theme = Theme()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder_(theme: theme)
		            }
		            return First(theme: theme, leafBuilder: leafBuilder)
		        }
		        let first: First = __safeDI_first()
		        self.init(third: third, second: second, first: first)
		    }
		}
		"""])
		#expect(variantCount(ofNodeDeclaring: "Leaf as leafBuilder: Instantiator<Leaf>", in: report) == 2, "\(report.world)")
		#expect(TypeFactsChecks.findings(of: report).findingsByCheck[10, default: []].isEmpty, "\(TypeFactsChecks.findings(of: report).findingsByCheck[10, default: []])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysNilApartFromTheWrapper_whenOnlyAWrapperAndNothingAnswerAReceiveOfTheValue() async throws {
		// `Leaf` receives `theme: Theme?`, which `Second`'s wrapper answers and nothing answers beneath `Third`. Rule 1 keys
		// `nil` by the form the receive declares, apart from the wrapper: two variants. 2.4.x writes one function, taking the
		// wrapper as optional, because its first place in declaration order passes the wrapper.
		let (tree, report) = try await generatedTreeAndReport(of: Self.leafFixture(places: [("Second", "LazilyInstantiated<Theme>"), ("Third", nil)]))

		#expect(tree == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_theme() -> Theme {
		            Theme()
		        }
		        func __safeDI_leafBuilder(theme: LazilyInstantiated<Theme>?) -> Leaf {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: theme)
		            }
		            return Leaf(theme: theme?.instance, leafBuilder: leafBuilder)
		        }
		        func __safeDI_second() -> Second {
		            let theme = LazilyInstantiated<Theme>(__safeDI_theme)
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: theme)
		            }
		            return Second(theme: theme, leafBuilder: leafBuilder)
		        }
		        let second: Second = __safeDI_second()
		        func __safeDI_third() -> Third {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: nil)
		            }
		            return Third(leafBuilder: leafBuilder)
		        }
		        let third: Third = __safeDI_third()
		        self.init(second: second, third: third)
		    }
		}
		"""])
		#expect(variantCount(ofNodeDeclaring: "Leaf as leafBuilder: Instantiator<Leaf>", in: report) == 2, "\(report.world)")
		#expect(TypeFactsChecks.findings(of: report).findingsByCheck[10, default: []].isEmpty, "\(TypeFactsChecks.findings(of: report).findingsByCheck[10, default: []])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysEachWrapperApartAndNilWithTheValue_whenTwoWrappersAndNothingAnswerAReceiveOfTheValueInEitherOrder() async throws {
		// `Leaf` receives `theme: Theme?`, answered by a `SendableLazilyInstantiated` beneath `First`, a `LazilyInstantiated`
		// beneath `Second`, and nothing beneath `Third`: three variants in either order of the two wrappers. 2.4.x writes two
		// functions, passing `nil` to the function of whichever wrapper's place it declares first, made optional.
		let sendableFirst = try await generatedTreeAndReport(of: Self.leafFixture(places: [("First", "SendableLazilyInstantiated<Theme>"), ("Second", "LazilyInstantiated<Theme>"), ("Third", nil)], themeIsSendable: true))
		let lazyFirst = try await generatedTreeAndReport(of: Self.leafFixture(places: [("Second", "LazilyInstantiated<Theme>"), ("First", "SendableLazilyInstantiated<Theme>"), ("Third", nil)], themeIsSendable: true))

		#expect(sendableFirst.tree == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_theme() -> Theme {
		            Theme()
		        }
		        func __safeDI_leafBuilder(theme: SendableLazilyInstantiated<Theme>?) -> Leaf {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: theme)
		            }
		            return Leaf(theme: theme?.instance, leafBuilder: leafBuilder)
		        }
		        func __safeDI_first() -> First {
		            let theme = SendableLazilyInstantiated<Theme>(__safeDI_theme)
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: theme)
		            }
		            return First(theme: theme, leafBuilder: leafBuilder)
		        }
		        let first: First = __safeDI_first()
		        func __safeDI_theme_() -> Theme {
		            Theme()
		        }
		        func __safeDI_leafBuilder_(theme: LazilyInstantiated<Theme>) -> Leaf {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder_(theme: theme)
		            }
		            return Leaf(theme: theme.instance, leafBuilder: leafBuilder)
		        }
		        func __safeDI_second() -> Second {
		            let theme = LazilyInstantiated<Theme>(__safeDI_theme_)
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder_(theme: theme)
		            }
		            return Second(theme: theme, leafBuilder: leafBuilder)
		        }
		        let second: Second = __safeDI_second()
		        func __safeDI_third() -> Third {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: nil)
		            }
		            return Third(leafBuilder: leafBuilder)
		        }
		        let third: Third = __safeDI_third()
		        self.init(first: first, second: second, third: third)
		    }
		}
		"""])
		#expect(lazyFirst.tree == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_theme() -> Theme {
		            Theme()
		        }
		        func __safeDI_leafBuilder(theme: LazilyInstantiated<Theme>?) -> Leaf {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: theme)
		            }
		            return Leaf(theme: theme?.instance, leafBuilder: leafBuilder)
		        }
		        func __safeDI_second() -> Second {
		            let theme = LazilyInstantiated<Theme>(__safeDI_theme)
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: theme)
		            }
		            return Second(theme: theme, leafBuilder: leafBuilder)
		        }
		        let second: Second = __safeDI_second()
		        @Sendable nonisolated func __safeDI_theme_() -> Theme {
		            Theme()
		        }
		        func __safeDI_leafBuilder_(theme: SendableLazilyInstantiated<Theme>) -> Leaf {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder_(theme: theme)
		            }
		            return Leaf(theme: theme.instance, leafBuilder: leafBuilder)
		        }
		        func __safeDI_first() -> First {
		            let theme = SendableLazilyInstantiated<Theme>(__safeDI_theme_)
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder_(theme: theme)
		            }
		            return First(theme: theme, leafBuilder: leafBuilder)
		        }
		        let first: First = __safeDI_first()
		        func __safeDI_third() -> Third {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: nil)
		            }
		            return Third(leafBuilder: leafBuilder)
		        }
		        let third: Third = __safeDI_third()
		        self.init(second: second, first: first, third: third)
		    }
		}
		"""])
		#expect(variantCount(ofNodeDeclaring: "Leaf as leafBuilder: Instantiator<Leaf>", in: sendableFirst.report) == 3, "\(sendableFirst.report.world)")
		#expect(variantCount(ofNodeDeclaring: "Leaf as leafBuilder: Instantiator<Leaf>", in: lazyFirst.report) == 3, "\(lazyFirst.report.world)")
		#expect(TypeFactsChecks.findings(of: sendableFirst.report).findingsByCheck[10, default: []].isEmpty)
		#expect(TypeFactsChecks.findings(of: lazyFirst.report).findingsByCheck[10, default: []].isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysOneParameterPerForm_whenOneBodyReceivesTheLabelOnlyIfAvailableInBothFormsInEitherOrder() async throws {
		// `Leaf` receives `theme` in one form and its `Sub` in the other, so the wrapper is not the form every receive declares:
		// it keys apart from the value and `nil`, two variants in either order, as 2.4.x writes two functions, each with one
		// parameter, handing `nil` to the wrapper's receive beneath the value.
		let leafReadsValue = try await generatedTreeAndReport(of: Self.leafFixture(places: [("First", "Theme"), ("Second", "LazilyInstantiated<Theme>"), ("Third", nil)], subTheme: "LazilyInstantiated<Theme>?"))
		let leafReadsWrapper = try await generatedTreeAndReport(of: Self.leafFixture(places: [("First", "Theme"), ("Second", "LazilyInstantiated<Theme>"), ("Third", nil)], leafTheme: "LazilyInstantiated<Theme>?", subTheme: "Theme?"))

		#expect(leafReadsValue.tree == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_leafBuilder(theme: Theme?) -> Leaf {
		            let sub = Sub(theme: nil)
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: theme)
		            }
		            return Leaf(theme: theme, sub: sub, leafBuilder: leafBuilder)
		        }
		        func __safeDI_first() -> First {
		            let theme = Theme()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: theme)
		            }
		            return First(theme: theme, leafBuilder: leafBuilder)
		        }
		        let first: First = __safeDI_first()
		        func __safeDI_theme() -> Theme {
		            Theme()
		        }
		        func __safeDI_leafBuilder_(theme: LazilyInstantiated<Theme>) -> Leaf {
		            let sub = Sub(theme: theme)
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder_(theme: theme)
		            }
		            return Leaf(theme: theme.instance, sub: sub, leafBuilder: leafBuilder)
		        }
		        func __safeDI_second() -> Second {
		            let theme = LazilyInstantiated<Theme>(__safeDI_theme)
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder_(theme: theme)
		            }
		            return Second(theme: theme, leafBuilder: leafBuilder)
		        }
		        let second: Second = __safeDI_second()
		        func __safeDI_third() -> Third {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: nil)
		            }
		            return Third(leafBuilder: leafBuilder)
		        }
		        let third: Third = __safeDI_third()
		        self.init(first: first, second: second, third: third)
		    }
		}
		"""])
		#expect(leafReadsWrapper.tree == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_leafBuilder(theme: Theme?) -> Leaf {
		            let sub = Sub(theme: theme)
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: theme)
		            }
		            return Leaf(theme: nil, sub: sub, leafBuilder: leafBuilder)
		        }
		        func __safeDI_first() -> First {
		            let theme = Theme()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: theme)
		            }
		            return First(theme: theme, leafBuilder: leafBuilder)
		        }
		        let first: First = __safeDI_first()
		        func __safeDI_theme() -> Theme {
		            Theme()
		        }
		        func __safeDI_leafBuilder_(theme: LazilyInstantiated<Theme>) -> Leaf {
		            let sub = Sub(theme: theme.instance)
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder_(theme: theme)
		            }
		            return Leaf(theme: theme, sub: sub, leafBuilder: leafBuilder)
		        }
		        func __safeDI_second() -> Second {
		            let theme = LazilyInstantiated<Theme>(__safeDI_theme)
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder_(theme: theme)
		            }
		            return Second(theme: theme, leafBuilder: leafBuilder)
		        }
		        let second: Second = __safeDI_second()
		        func __safeDI_third() -> Third {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(theme: nil)
		            }
		            return Third(leafBuilder: leafBuilder)
		        }
		        let third: Third = __safeDI_third()
		        self.init(first: first, second: second, third: third)
		    }
		}
		"""])
		#expect(variantCount(ofNodeDeclaring: "Leaf as leafBuilder: Instantiator<Leaf>", in: leafReadsValue.report) == 2, "\(leafReadsValue.report.world)")
		#expect(variantCount(ofNodeDeclaring: "Leaf as leafBuilder: Instantiator<Leaf>", in: leafReadsWrapper.report) == 2, "\(leafReadsWrapper.report.world)")
		#expect(TypeFactsChecks.findings(of: leafReadsValue.report).findingsByCheck[10, default: []].isEmpty)
		#expect(TypeFactsChecks.findings(of: leafReadsWrapper.report).findingsByCheck[10, default: []].isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysAliasPerForm_whenRenameIsAnsweredByAValueUnderOneParentAndALazyWrapperUnderAnother() async throws {
		// `Reader` renames `x`, which `LazyParent` declares lazily (the alias reads `x.instance`) and `ValueParent` by value
		// (`x`): one variant of the alias for both would write one of them wrong, so the alias reads its fulfilling label
		// and keys by the answer's form. Check 10 compares the forms the parents' places hand the alias.
		let (_, report) = try await generatedTreeAndReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let lazyParent: LazyParent", "@Instantiated let valueParent: ValueParent"]),
			seamFixtureType(named: "LazyParent", isFinalClass: true, declarations: ["@Instantiated let readerBuilder: Instantiator<Reader>", "@Instantiated let x: LazilyInstantiated<X>"]),
			seamFixtureType(named: "ValueParent", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let holder: Holder"]),
			seamFixtureType(named: "Holder", isFinalClass: true, declarations: ["@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: [#"@Received(fulfilledByDependencyNamed: "x", ofType: X.self) let renamed: X"#]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])
		let alias = try #require(report.nodes.firstIndex { $0.isLeaf && $0.description.hasSuffix("as renamed: X") }, "\(report.world)")

		#expect(report.variantCountsByNode[alias] == 2, "\(report.world)")
		#expect(TypeFactsChecks.findings(of: report).findingsByCheck[10, default: []].isEmpty, "\(TypeFactsChecks.findings(of: report).findingsByCheck[10, default: []])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysOneVariant_whenProductionBuildsTypeInPlainFunctionAndInSendableFunction() async throws {
		// `leaf` is one node with two parents, one built in a plain `Instantiator`'s function and one in a
		// `SendableInstantiator`'s `@Sendable` function: production's body is one, `@Sendable` a mark folded over its calls,
		// so the family keys no production variant.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let plainBuilder: Instantiator<Plain>", "@Instantiated let sharedBuilder: SendableInstantiator<Shared>"]),
			seamFixtureType(named: "Plain", isFinalClass: true, declarations: ["@Instantiated let leaf: Leaf"]),
			seamFixtureType(named: "Shared", isFinalClass: true, declarations: ["@Instantiated let leaf: Leaf"], conformances: ", Sendable"),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: [], conformances: ", Sendable"),
		])

		#expect(report.places.count(where: { $0.declaration == "Leaf as leaf: Leaf" }) == 2, "\(report.world)")
		#expect(variantCount(ofNodeDeclaring: "Leaf as leaf: Leaf", in: report) == 1, "\(report.world)")
		#expect(Set(report.variantFamilies) == ["plain"], "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_marksSharedVariantBuiltInsideSendableFunction_whenProductionBuildsTypeInPlainFunctionAndInSendableFunction() async throws {
		// `leaf`'s one body is called from `Plain`'s plain body and from `Shared`'s, inside `sharedBuilder`'s `@Sendable`
		// function: the mark folded over its calls makes its function `@Sendable`.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let plainBuilder: Instantiator<Plain>", "@Instantiated let sharedBuilder: SendableInstantiator<Shared>"]),
			seamFixtureType(named: "Plain", isFinalClass: true, declarations: ["@Instantiated let leaf: Leaf"]),
			seamFixtureType(named: "Shared", isFinalClass: true, declarations: ["@Instantiated let leaf: Leaf"], conformances: ", Sendable"),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: [], conformances: ", Sendable"),
		])

		#expect(marksByDeclaration(in: report) == [
			"Root": [false],
			"Plain as plainBuilder: Instantiator<Plain>": [false],
			"Shared as sharedBuilder: SendableInstantiator<Shared>": [true],
			"Leaf as leaf: Leaf": [true],
		], "\(report.world)")
		// Each place the old tree builds says the same.
		#expect(TypeFactsChecks.findings(of: report).findingsByCheck[34] == nil, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_marksVariantMadeBeforeItsCallerBuiltInsideSendableFunction_whenCycleClosesFromInsideSendableFunction() async throws {
		// `C`'s body is made first, called from `bBuilder`'s plain body, and called again by `otherBBuilder`'s, inside its
		// `@Sendable` function, where the cycle closes on `C`: the fold marks `C` when that call is met, after `C` was
		// visited, as 2.4.x makes `C`'s function `@Sendable` for the call that closes on it from inside one, and hands the
		// mark on to `d`, built in `C`'s body.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let otherBBuilder: SendableInstantiator<B>", "@Instantiated let d: D"]),
			seamFixtureType(named: "D", isFinalClass: true, declarations: []),
		])

		#expect(marksByDeclaration(in: report) == [
			"Root": [false],
			"A as aBuilder: Instantiator<A>": [false],
			"B as bBuilder: Instantiator<B>": [false],
			"C as cBuilder: Instantiator<C>": [true],
			"B as otherBBuilder: SendableInstantiator<B>": [true],
			"D as d: D": [true],
		], "\(report.world)")
		// Each place the old tree builds says the same.
		#expect(TypeFactsChecks.findings(of: report).findingsByCheck[34] == nil, "\(report.world)")
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

	/// `Leaf` receives `theme` only if available, as `leafTheme`, and builds itself again through `leafBuilder`, so 2.4.x
	/// writes it as a function; each of `places`, in `Root`'s declaration order, declares the `theme` it names, if any, then
	/// builds `leafBuilder`. A `subTheme` gives `Leaf` a `Sub` that receives `theme` only if available in that form.
	private static func leafFixture(places: [(name: String, theme: String?)], leafTheme: String = "Theme?", subTheme: String? = nil, themeIsSendable: Bool = false) -> [String] {
		var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: places.map { "@Instantiated let \($0.name.prefix(1).lowercased() + $0.name.dropFirst()): \($0.name)" })]
		for place in places {
			types.append(seamFixtureType(named: place.name, isFinalClass: true, declarations: (place.theme.map { ["@Instantiated let theme: \($0)"] } ?? []) + ["@Instantiated let leafBuilder: Instantiator<Leaf>"]))
		}
		types.append(seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let theme: \(leafTheme)"] + (subTheme == nil ? [] : ["@Instantiated let sub: Sub"]) + ["@Instantiated let leafBuilder: Instantiator<Leaf>"]))
		if let subTheme {
			types.append(seamFixtureType(named: "Sub", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let theme: \(subTheme)"]))
		}
		types.append(seamFixtureType(named: "Theme", isFinalClass: true, declarations: [], conformances: themeIsSendable ? ", Sendable" : ""))
		return types
	}

	/// The root's generated tree and the type facts report of `Root`'s production tree.
	private func generatedTreeAndReport(of types: [String]) async throws -> (tree: [String: String], report: TypeFactsReport) {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		let output = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
			try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == "Root" && !report.forMockGeneration {
			reports.append(report)
		}
		return (output.dependencyTreeFiles, try #require(reports.last))
	}

	/// Each node's description, with the mark of each of its variants in variant order.
	private func marksByDeclaration(in report: TypeFactsReport) -> [String: [Bool]] {
		var marks = [String: [Bool]]()
		for (variant, node) in report.variantNodes.enumerated() {
			marks[report.nodes[node].description, default: []].append(report.variantBuildsInSendableFunction[variant])
		}
		return marks
	}

	private func variantCount(ofNodeDeclaring declaration: String, in report: TypeFactsReport) -> Int? {
		guard let node = report.places.first(where: { $0.declaration == declaration })?.node else {
			return nil
		}
		return report.variantCountsByNode[node]
	}
}
