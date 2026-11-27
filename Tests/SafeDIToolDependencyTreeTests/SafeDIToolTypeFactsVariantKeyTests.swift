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
	mutating func generate_answersBoundButNotProvided_whenMockRootForwardsAnotherTypeUnderALabelItsTreeReceives() async throws {
		// A mock root's forwarded properties hide nothing its tree receives, so `Screen`'s `gizmo: Gizmo` is named only by the
		// mock root's bindings, no declaration of the tree. The `Settings` the mock builds receives `gizmo:
		// Instantiator<Widget>`, which the mock takes apart: the bound `gizmo` provides no form it reads.
		let report = try await rootReport(of: [
			"""
			@Instantiable(generateMock: .public)
			public final class Screen: Instantiable {
			    public init(gizmo: Gizmo, settingsBuilder: Instantiator<Settings>, gadget: Gadget) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Forwarded public let gizmo: Gizmo
			    @Received public let settingsBuilder: Instantiator<Settings>
			    @Instantiated public let gadget: Gadget
			}
			@Instantiable
			public final class Settings: Instantiable {
			    public init(gizmo: Instantiator<Widget>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Received public let gizmo: Instantiator<Widget>
			}
			public final class Gizmo: Instantiable { public init() {} }
			public final class Widget: Instantiable { public init() {} }
			public final class Gadget: Instantiable { public init() {} }
			""",
		], root: "Screen", forMockGeneration: true)

		// The mock root's call of `Settings` answers `settingsBuilder` as being built and `gizmo` by the forwarded `gizmo`.
		#expect(report.world.contains("calls [1, 2] sources [[], [\"bound beingBuilt\", \"bound declared not provided\"]]"), "\(report.world)")
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

	// MARK: Private

	private var filesToDelete: [URL]

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private func rootReport(of types: [String], root: String = "Root", forMockGeneration: Bool = false, skipCompileVerification: Bool = false) async throws -> TypeFactsReport {
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
		for await report in stream where report.root == root && report.forMockGeneration == forMockGeneration {
			reports.append(report)
		}
		return try #require(reports.last)
	}

	private func variantCount(ofNodeDeclaring declaration: String, in report: TypeFactsReport) -> Int? {
		guard let node = report.places.first(where: { $0.declaration == declaration })?.node else {
			return nil
		}
		return report.variantCountsByNode[node]
	}
}
