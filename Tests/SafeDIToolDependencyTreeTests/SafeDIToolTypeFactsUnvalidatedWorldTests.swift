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

/// The world of per-type facts of the roots one validation call walks, built before the walk
/// (`TypeFactsGraph.init(roots:intern:)`): what a fold over it would judge of each shape the walk rejects, and of the
/// shapes beside them it accepts. Nothing in the world is an error, so each test reads the world of a graph whether or
/// not `generate` then throws, and a test of a rejected graph also pins the error, so that the fixture stays one the
/// walk rejects for that reason.
///
/// A receive's line (`TypeFactsRootsReport.receives`) names each answer some route hands the node for the receive's
/// read: `none` where nothing above declares the label, the forms the nearest declaration binds otherwise, and
/// `being built` where that declaration is the property a type on the way down is being built as. After each answer
/// come `provided` where it holds a property the receive accepts, and the route the world keeps as its witness, which
/// in each rejected graph here is the chain the walk's error names.
struct SafeDIToolTypeFactsUnvalidatedWorldTests {
	// MARK: Rejections

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_answersNone_whenNothingDeclaresRequiredReceive() async throws {
		let observation = await observe([
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])

		#expect(try observation.firstWorld.receives == [
			"Child as child: Child: required value(x) accepts [x: X] = none (not provided) along world > frame 0 of Root > Root > Child as child: Child",
		])
		let error = try #require(observation.error as? SafeDIToolTestError)
		#expect("\(error.underlyingError)" == """
		\(error.fixtures["Child.swift"]):7:5: error: @Received property `x: X` is not @Instantiated or @Forwarded in chain: Root -> Child. Declare `@Instantiated let x: X` on `Root` or on another type in the chain to fix.
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_answersNearestDeclarationsForms_whenNearerDeclarationOfAnotherTypeHidesReceive() async throws {
		let observation = await observe([
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let parent: Parent"]),
			seamFixtureType(named: "Parent", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		])

		#expect(try observation.firstWorld.receives == [
			"Child as child: Child: required value(x) accepts [x: X] = value x: Y, x: Y? (not provided) along world > frame 0 of Root > Root > Parent as parent: Parent > Child as child: Child",
		])
		let error = try #require(observation.error as? SafeDIToolTestError)
		#expect("\(error.underlyingError)" == """
		\(error.fixtures["Child.swift"]):7:5: error: @Received property `x: X` is hidden in chain: Root -> Parent -> Child. `Parent` declares `x: Y` with the same label, so the types below `Parent` receive `x: Y` instead. Give `x: Y` on `Parent` a different label to fix.
		\(error.fixtures["Parent.swift"]):8:5: note: `x: Y` is declared here
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_answersBeingBuilt_whenReceivedValueIsBuiltAboveItsReceiver() async throws {
		let observation = await observe([
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let a: A"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let a: A"]),
		])

		#expect(try observation.firstWorld.receives == [
			"B as b: B: required value(a) accepts [a: A] = value a: A, a: A? being built (provided) along world > frame 0 of Root > Root > A as a: A > B as b: B",
		])
		let error = try #require(observation.error as? SafeDIToolTestError)
		#expect("\(error.underlyingError)" == """
		\(error.fixtures["B.swift"]):7:5: error: Dependency cycle: `A` -> `B` -> `A`. `B` receives `a: A`, which is still being built when `B` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
		\(error.fixtures["A.swift"]):1:1: note: `A` is part of the cycle
		\(error.fixtures["B.swift"]):1:1: note: `B` is part of the cycle
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_marksNodesOnCycle_whenValuesInstantiateEachOther() async throws {
		let observation = await observe([
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let a: A"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let a: A"]),
		])

		#expect(try observation.firstWorld.nodes.filter(\.isOnCycle).map(\.description) == [
			"A as a: A",
			"B as b: B",
		])
		#expect(try observation.firstWorld.receives == [])
		let error = try #require(observation.error as? SafeDIToolTestError)
		#expect("\(error.underlyingError)" == """
		\(error.fixtures["B.swift"]):7:5: error: Dependency cycle: `A` -> `B` -> `A`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `a: A`, `b: B` to an instantiator.
		\(error.fixtures["A.swift"]):1:1: note: `A` is part of the cycle
		\(error.fixtures["B.swift"]):1:1: note: `B` is part of the cycle
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_keepsEachRootsAnswer_whenTwoRootsBindOneLabelInTwoTypesAboveOneRequiredReceive() async throws {
		// `Child` is one node both roots reach, so its read has two answers: `RootA`'s `x: X`, and `RootB`'s `x: Y`, which
		// the walk rejects along the same route the world keeps as that answer's witness.
		let observation = await observe([
			seamFixtureType(named: "RootA", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let child: Child"]),
			seamFixtureType(named: "RootB", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		])

		let world = try observation.firstWorld
		#expect(world.nodes.map(\.description) == [
			"world",
			"frame 0 of RootA",
			"RootA",
			"X as x: X",
			"Child as child: Child",
			"frame 1 of RootB",
			"RootB",
			"Y as x: Y",
		])
		#expect(world.receives == [
			"Child as child: Child: required value(x) accepts [x: X] = value x: X, x: X? (provided) along world > frame 0 of RootA > RootA > Child as child: Child; value x: Y, x: Y? (not provided) along world > frame 1 of RootB > RootB > Child as child: Child",
		])
		let error = try #require(observation.error as? SafeDIToolTestError)
		#expect("\(error.underlyingError)" == """
		\(error.fixtures["Child.swift"]):7:5: error: @Received property `x: X` is not @Instantiated or @Forwarded in chain: RootB -> Child. Did you mean `x: Y`?
		\(error.fixtures["Child.swift"]):7:22-7:23: fixit: Y
		""")
	}

	// MARK: Accepted graphs

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_keepsEachRootsAnswer_whenTwoRootsBindOneLabelInTwoTypesAboveOneReceiveOnlyIfAvailable() async throws {
		let observation = await observe([
			seamFixtureType(named: "RootA", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let child: Child"]),
			seamFixtureType(named: "RootB", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		])

		let world = try observation.firstWorld
		#expect(observation.error == nil)
		#expect(world.rootVariants.map { world.nodes[world.variantNodes[$0]].description } == ["RootA", "RootB"])
		#expect(world.receives == [
			"Child as child: Child: only if available optionalValue(x) accepts [x: X?, x: X] = optionalValue x: X, x: X? (provided) along world > frame 0 of RootA > RootA > Child as child: Child; optionalValue x: Y, x: Y? (not provided) along world > frame 1 of RootB > RootB > Child as child: Child",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_holdsOnlyItsRootsAnswer_whenOneOfTwoRootsThatBindOneLabelReachesNode() async throws {
		// One root's answers never reach another root's nodes: only `RootA` builds `OnlyA`, so `RootB`'s `x: Y` is no
		// answer of its read, though it is one of `Child`'s, which both roots build.
		let observation = await observe([
			seamFixtureType(named: "RootA", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let onlyA: OnlyA", "@Instantiated let child: Child"]),
			seamFixtureType(named: "RootB", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let child: Child"]),
			seamFixtureType(named: "OnlyA", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		])

		let world = try observation.firstWorld
		#expect(observation.error == nil)
		#expect(world.receives == [
			"OnlyA as onlyA: OnlyA: only if available optionalValue(x) accepts [x: X?, x: X] = optionalValue x: X, x: X? (provided) along world > frame 0 of RootA > RootA > OnlyA as onlyA: OnlyA",
			"Child as child: Child: only if available optionalValue(x) accepts [x: X?, x: X] = optionalValue x: X, x: X? (provided) along world > frame 0 of RootA > RootA > Child as child: Child; optionalValue x: Y, x: Y? (not provided) along world > frame 1 of RootB > RootB > Child as child: Child",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_givesEachMockRootsFrameWhatItsMockBinds_whenTwoMockRootsReceiveOneLabelInTwoTypes() async throws {
		let observation = await observe([
			mockFixtureType(named: "A", declarations: ["@Received let x: X", "@Instantiated let shared: Shared"]),
			mockFixtureType(named: "B", declarations: ["@Received let x: Y", "@Instantiated let shared: Shared"]),
			seamFixtureType(named: "Shared", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		])

		let world = try observation.firstWorld
		#expect(observation.error == nil)
		#expect(world.nodes.map(\.description) == [
			"world",
			"frame 0 of A",
			"A",
			"Shared as shared: Shared",
			"frame 1 of B",
			"B",
		])
		#expect(world.receives == [
			"A: required value(x) accepts [x: X] = value x: X, x: X? (provided) along world > frame 0 of A > A",
			"Shared as shared: Shared: only if available optionalValue(x) accepts [x: X?, x: X] = optionalValue x: X, x: X? (provided) along world > frame 0 of A > A > Shared as shared: Shared; optionalValue x: X?, x: Y (provided) along world > frame 1 of B > B > Shared as shared: Shared",
			"B: required value(x) accepts [x: Y] = value x: X?, x: Y (provided) along world > frame 1 of B > B",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_givesSeamsFrameWhatItsTreeReceivesFromOutside_whenSeamsChildRequiresValueSeamDoesNotDeclare() async throws {
		let observation = await observe([
			seamFixtureType(named: "First", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let one: One"]),
			seamFixtureType(named: "One", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])

		let world = try observation.firstWorld
		#expect(observation.error == nil)
		#expect(world.nodes.map(\.description) == [
			"world",
			"frame 0 of First",
			"First",
			"One as one: One",
		])
		#expect(world.receives == [
			"One as one: One: required value(x) accepts [x: X] = value x: X (provided) along world > frame 0 of First > First > One as one: One",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_givesSeamsFrameEachLabelsOwnForms_whenSeamsChildRequiresTwoValuesSeamDoesNotDeclare() async throws {
		let observation = await observe([
			seamFixtureType(named: "First", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let one: One"]),
			seamFixtureType(named: "One", isFinalClass: true, declarations: ["@Received let x: X", "@Received let y: Y"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		])

		let receives = try observation.firstWorld.receives
		#expect(observation.error == nil)
		#expect(receives == [
			"One as one: One: required value(x) accepts [x: X] = value x: X (provided) along world > frame 0 of First > First > One as one: One",
			"One as one: One: required value(y) accepts [y: Y] = value y: Y (provided) along world > frame 0 of First > First > One as one: One",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_answersBeingBuilt_whenInstantiatorIsReceivedInsideTheTreeItBuilds() async throws {
		let observation = await observe([
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let aBuilder: Instantiator<A>"]),
		])

		let receives = try observation.firstWorld.receives
		#expect(observation.error == nil)
		#expect(receives == [
			"B as b: B: required value(aBuilder) accepts [aBuilder: Instantiator<A>] = value aBuilder: Instantiator<A>, aBuilder: Instantiator<A>? being built (provided) along world > frame 0 of Root > Root > A as aBuilder: Instantiator<A> > B as b: B",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_keepsBothFormsWithTheLapsRoute_whenLapIsBuiltAgainBeneathAnotherFormOfItsReceive() async throws {
		let observation = await observe([
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B", "@Received let x: X"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])

		let world = try observation.firstWorld
		#expect(observation.error == nil)
		#expect(world.receives == [
			"A as aBuilder: Instantiator<A>: required value(x) accepts [x: X] = value x: X, x: X? (provided) along world > frame 0 of Root > Root > A as aBuilder: Instantiator<A>; value x: LazilyInstantiated<X>, x: LazilyInstantiated<X>?, x: X, x: X? (provided) along world > frame 0 of Root > Root > A as aBuilder: Instantiator<A> > B as b: B > A as aBuilder: Instantiator<A>",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_answersNone_whenNothingDeclaresReceiveOnlyIfAvailable() async throws {
		let observation = await observe([
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])

		let receives = try observation.firstWorld.receives
		#expect(observation.error == nil)
		#expect(receives == [
			"Child as child: Child: only if available optionalValue(x) accepts [x: X?, x: X] = none (not provided) along world > frame 0 of Root > Root > Child as child: Child",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_acceptsRenamedPropertysForms_whenReceivesRenameRequiredAndOnlyIfAvailable() async throws {
		let observation = await observe([
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: [
				"@Received(fulfilledByDependencyNamed: \"x\", ofType: X.self) let renamed: X",
				"@Received(fulfilledByDependencyNamed: \"y\", ofType: Y.self, onlyIfAvailable: true) let other: Y?",
			]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		])

		let receives = try observation.firstWorld.receives
		#expect(observation.error == nil)
		#expect(receives == [
			"Child as child: Child: required value(x) through renamed: X accepts [x: X] = value x: X, x: X? (provided) along world > frame 0 of Root > Root > Child as child: Child",
			"Child as child: Child: only if available optionalValue(y) through other: Y? accepts [y: Y, y: Y?] = none (not provided) along world > frame 0 of Root > Root > Child as child: Child",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_isNil_whenValidationCallHasNoRoot() async {
		let observation = await observe([
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])

		#expect(observation.error == nil)
		#expect(!observation.worlds.isEmpty)
		#expect(observation.worlds.allSatisfy { $0 == nil })
	}

	// MARK: Interning order

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_spellsTheSameFacts_whenRunInternsInAnotherOrder() async throws {
		// IDs follow the order a run interns in, so what the world says by name is the same in every order: the reversed
		// order and six permutations, over a graph of nine labels read in two channels.
		let types = Self.alternatingRow(layerCount: 4)
		let expected = try await nameBasedFacts(of: observe(types).firstWorld)

		let orders = [ConstructionInternerOrder.reversed] + (1...6).map { ConstructionInternerOrder.permuted(seed: $0) }
		for order in orders {
			let facts = try await nameBasedFacts(of: observe(types, order: order).firstWorld)
			#expect(facts == expected, "\(order)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_reportsTheSameFindings_whenRunDeclaresInAnotherOrder() async throws {
		// Inside an answer set the answers are in the order of their IDs, which follow the order a run interns in. What
		// validation reports must not: the answers each receive is given with the route that witnesses each, and the
		// error of a graph the walk rejects, here one whose four required receives are each unfulfilled along half of
		// sixteen routes. The reversed order and six permutations.
		let types = Self.alternatingRow(layerCount: 4, readerRequiresTokens: true)
		let expected = await observe(types)
		let expectedFindings = try expected.firstWorld.receives
		let expectedError = try Self.textWithoutDirectories(of: #require(expected.error))

		let orders = [ConstructionInternerOrder.reversed] + (1...6).map { ConstructionInternerOrder.permuted(seed: $0) }
		for order in orders {
			let observation = await observe(types, order: order)
			#expect(try observation.firstWorld.receives == expectedFindings, "\(order)")
			#expect(observation.error.map(Self.textWithoutDirectories) == expectedError, "\(order)")
		}
	}

	// MARK: Growth

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_holdsAnswersInProportionToItsReads_whenAlternatingParentsDeclareTokenOnOneSide() async throws {
		// rows.py's alternating row: every route gives the reader another vector of answers, 2 to the layers of them, and
		// each of its reads has two answers, the token and `none`. Sizes 4 and 8 only: at 16 layers the generator, which
		// builds the reader once per vector after validation, does not finish in a quarter of an hour.
		let small = try await growth(of: observe(Self.alternatingRow(layerCount: 4)).firstWorld)
		let medium = try await growth(of: observe(Self.alternatingRow(layerCount: 8)).firstWorld)

		#expect(small == "variants beyond one per node [] nodes 16 edges 22 reads 85 answers 117 largest set 2 steps 246")
		#expect(medium == "variants beyond one per node [] nodes 28 edges 42 reads 297 answers 425 largest set 2 steps 970")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_holdsAnswersInProportionToItsReads_whenReaderReceivesEveryLayersBuilderStillBeingBuiltOnHalfTheRoutes() async throws {
		let small = try await growth(of: observe(Self.beingBuiltRow(layerCount: 4)).firstWorld)
		let medium = try await growth(of: observe(Self.beingBuiltRow(layerCount: 8)).firstWorld)

		#expect(small == "variants beyond one per node [] nodes 12 edges 18 reads 29 answers 45 largest set 2 steps 80")
		#expect(medium == "variants beyond one per node [] nodes 20 edges 34 reads 89 answers 153 largest set 2 steps 288")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_holdsAnswersInProportionToItsReads_whenHubsLeafReceivesEveryMembersLabelOnlyIfAvailable() async throws {
		let small = try await growth(of: observe(Self.hubMembersRow(memberCount: 4)).firstWorld)
		let medium = try await growth(of: observe(Self.hubMembersRow(memberCount: 8)).firstWorld)
		let large = try await growth(of: observe(Self.hubMembersRow(memberCount: 16)).firstWorld)

		#expect(small == "variants beyond one per node [] nodes 13 edges 16 reads 58 answers 98 largest set 2 steps 227")
		#expect(medium == "variants beyond one per node [] nodes 21 edges 28 reads 178 answers 322 largest set 2 steps 835")
		#expect(large == "variants beyond one per node [] nodes 37 edges 52 reads 610 answers 1154 largest set 2 steps 3203")
	}

	// MARK: Agreement with the validated world

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_holdsEachRootsGraphAsItsValidatedWorldDoes_whenGraphIsAccepted() async throws {
		for types in [
			Self.alternatingRow(layerCount: 4),
			Self.beingBuiltRow(layerCount: 4),
			Self.hubMembersRow(memberCount: 4),
			[
				seamFixtureType(named: "RootA", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let child: Child"]),
				seamFixtureType(named: "RootB", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let child: Child"]),
				seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
				seamFixtureType(named: "X", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
			],
		] {
			let observation = await observe(types)
			let world = try observation.firstWorld
			#expect(observation.error == nil)
			#expect(!world.rootVariants.isEmpty)
			for (rootIndex, rootVariant) in world.rootVariants.enumerated() {
				let rootDescription = world.nodes[world.variantNodes[rootVariant]].description
				let report = try #require(observation.reports.last { $0.root == rootDescription && !$0.forMockGeneration })
				#expect(TypeFactsChecks.disagreements(ofRootAt: rootIndex, in: world, with: report) == [], "\(rootDescription)")
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func disagreements_namesEachDifference_whenWorldAndReportAreOfTwoGraphs() async throws {
		let world = try await observe([
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let childBuilder: Instantiator<Child>"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		]).firstWorld
		let observation = await observe([
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let childBuilder: Instantiator<Child>"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])
		let report = try #require(observation.reports.last { $0.root == "Root" && !$0.forMockGeneration })

		#expect(TypeFactsChecks.disagreements(ofRootAt: 0, in: world, with: report) == [
			"nodes: 2, not 3",
			"node 0 Root edges: [1], not [1, 2]",
			"node 0 Root reads from above: [\"optionalValue(x)\", \"optional(x)\"], not []",
			"node 1 X as x: X description: Child as childBuilder: Instantiator<Child>, not X as x: X",
			"node 1 X as x: X kind: instantiator, not constant",
			"node 1 X as x: X cycle key: childBuilder: Instantiator<Child> for Child, not x: X for X",
			"node 1 X as x: X reads from above: [\"value(childBuilder)\", \"optionalValue(x)\", \"optional(x)\"], not [\"value(x)\"]",
		])
		#expect(TypeFactsChecks.disagreements(ofRootAt: 1, in: world, with: report) == ["the world has no root 1"])
	}

	// MARK: Generation-side columns

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_holdsNoGenerationSideFact_whenWorldIsBuiltBeforeValidation() async throws {
		// A graph whose validated worlds hold edge facts, bindings, parents and property facts: a hub of instantiators
		// that close cycles, and a leaf that receives a label of each member.
		let world = try await observe(Self.hubMembersRow(memberCount: 4)).firstWorld

		#expect(world.generationSideElementCount == 0)
	}

	// MARK: Storage

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func unvalidatedWorld_internsOnlyFormsNoDeclarationSpells_whenWorldIsBuiltBeforeTheWalk() async throws {
		// What the world's build adds to the run's interner, and the 32-bit elements of its columns, for the hub row at
		// two sizes: the memory a validation over the world costs beyond the records it reads.
		let small = try await observe(Self.hubMembersRow(memberCount: 4)).firstWorld
		let large = try await observe(Self.hubMembersRow(memberCount: 8)).firstWorld

		#expect(small.internedForWorldCount == 12)
		#expect(small.columnElementCount == 1_194)
		#expect(large.internedForWorldCount == 20)
		#expect(large.columnElementCount == 3_234)
	}

	// MARK: Private

	/// What one `generate` showed its observers.
	private struct Observation {
		/// The world of each validation call, in the order `generate` made them, `nil` for a call with no root.
		let worlds: [TypeFactsRootsReport?]
		/// The validated world of each tree the run built.
		let reports: [TypeFactsReport]
		/// The error `generate` threw, if any.
		let error: (any Error)?

		/// The world of the first validation call that had a root.
		var firstWorld: TypeFactsRootsReport {
			get throws {
				try #require(worlds.compactMap(\.self).first)
			}
		}
	}

	/// An error's text with each file path cut to its file name: every run writes its fixtures to a directory of its own.
	private static func textWithoutDirectories(of error: any Error) -> String {
		String(describing: error).replacingOccurrences(of: #"/[^\s:]*/"#, with: "", options: .regularExpression)
	}

	private static func alternatingRow(layerCount: Int, readerRequiresTokens: Bool = false) -> [String] {
		var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let left0Builder: Instantiator<Left0>", "@Instantiated let right0Builder: Instantiator<Right0>"])]
		types.append(seamFixtureType(named: "Reader", isFinalClass: true, declarations: (0..<layerCount).map {
			readerRequiresTokens ? "@Received let token\($0): Token\($0)" : "@Received(onlyIfAvailable: true) let token\($0): Token\($0)?"
		}))
		for layer in 0..<layerCount {
			let next = layer == layerCount - 1
				? ["@Instantiated let reader: Reader"]
				: ["@Instantiated let left\(layer + 1)Builder: Instantiator<Left\(layer + 1)>", "@Instantiated let right\(layer + 1)Builder: Instantiator<Right\(layer + 1)>"]
			types.append(seamFixtureType(named: "Token\(layer)", isFinalClass: true, declarations: []))
			types.append(seamFixtureType(named: "Left\(layer)", isFinalClass: true, declarations: ["@Instantiated let token\(layer): Token\(layer)"] + next))
			types.append(seamFixtureType(named: "Right\(layer)", isFinalClass: true, declarations: next))
		}
		return types
	}

	private static func beingBuiltRow(layerCount: Int) -> [String] {
		var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let left0Builder: Instantiator<Left0>", "@Instantiated let right0Builder: Instantiator<Right0>"])]
		types.append(seamFixtureType(named: "Reader", isFinalClass: true, declarations: (0..<layerCount).map { "@Received let left\($0)Builder: Instantiator<Left\($0)>" }))
		for layer in 0..<layerCount {
			let next = layer == layerCount - 1
				? ["@Instantiated let reader: Reader"]
				: ["@Instantiated let left\(layer + 1)Builder: Instantiator<Left\(layer + 1)>", "@Instantiated let right\(layer + 1)Builder: Instantiator<Right\(layer + 1)>"]
			types.append(seamFixtureType(named: "Left\(layer)", isFinalClass: true, declarations: next))
			types.append(seamFixtureType(named: "Right\(layer)", isFinalClass: true, declarations: next))
		}
		return types
	}

	private static func hubMembersRow(memberCount: Int) -> [String] {
		var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let hubBuilder: Instantiator<Hub>"])]
		types.append(seamFixtureType(named: "Hub", isFinalClass: true, declarations: ["@Instantiated let leaf: Leaf"] + (0..<memberCount).map { "@Instantiated let member\($0)Builder: Instantiator<Member\($0)>" }))
		types.append(seamFixtureType(named: "Leaf", isFinalClass: true, declarations: (0..<memberCount).map { "@Received(onlyIfAvailable: true) let label\($0): Label\($0)?" }))
		for member in 0..<memberCount {
			types.append(seamFixtureType(named: "Label\(member)", isFinalClass: true, declarations: []))
			types.append(seamFixtureType(named: "Member\(member)", isFinalClass: true, declarations: ["@Instantiated let label\(member): Label\(member)", "@Instantiated let hubBuilder: Instantiator<Hub>"]))
		}
		return types
	}

	private func mockFixtureType(named name: String, declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations).replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n")
	}

	/// What a row's world holds and what its answer sets cost, as one line: the nodes with more than one variant, then
	/// the reads from above, the answers of their sets, the answers of the largest set, and the times the fold took an
	/// answer to an edge.
	private func growth(of world: TypeFactsRootsReport) -> String {
		"variants beyond one per node \(variantCounts(in: world)) nodes \(world.nodes.count) edges \(world.edgeCount) reads \(world.readCount) answers \(world.answerCount) largest set \(world.largestAnswerSetCount) steps \(world.answerStepCount)"
	}

	/// A line per node with more than one variant, `<node>: <count>`, in node order.
	private func variantCounts(in world: TypeFactsRootsReport) -> [String] {
		zip(world.nodes, world.variantCountsByNode).filter { $0.1 != 1 }.map { "\($0.0.description): \($0.1)" }
	}

	/// Everything `world` says by name or by position in the graph, which no interning order changes.
	private func nameBasedFacts(of world: TypeFactsRootsReport) -> [String] {
		var facts = world.nodes.map { "\($0.description) \($0.kind) \($0.construction) \($0.cycleKey) \($0.edges) \($0.isOnCycle) \($0.readsFromAbove) \($0.firstRoute)" }
		facts.append("roots \(world.rootVariants) nodes \(world.variantNodes) calls \(world.variantCalls) counts \(world.variantCountsByNode)")
		facts.append("elements \(world.columnElementCount) interned \(world.internedForWorldCount)")
		facts += world.receives
		return facts
	}

	/// What `generate` over `types` showed: the world of each validation call, the validated world of each tree, and the
	/// error it threw, if any.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private func observe(_ types: [String], order: ConstructionInternerOrder? = nil) async -> Observation {
		let (worldStream, worldContinuation) = AsyncStream.makeStream(of: TypeFactsRootsReport?.self)
		let (reportStream, reportContinuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		var thrownError: (any Error)?
		do {
			_ = try await ConstructionInternerOrder.applying(order) {
				try await ValidationWalkObservation.$observer.withValue({ observation in
					if case let .unvalidatedWorld(world) = observation {
						worldContinuation.yield(world)
					}
				}) {
					try await ConstructionMemoOracle.$observer.withValue({ _, _, report in reportContinuation.yield(report) }) {
						var filesToDelete = [URL]()
						defer {
							for file in filesToDelete {
								try? FileManager.default.removeItem(at: file)
							}
						}
						return try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, skipCompileVerification: true)
					}
				}
			}
		} catch {
			thrownError = error
		}
		worldContinuation.finish()
		reportContinuation.finish()
		var worlds = [TypeFactsRootsReport?]()
		for await world in worldStream {
			worlds.append(world)
		}
		var reports = [TypeFactsReport]()
		for await report in reportStream {
			reports.append(report)
		}
		return Observation(worlds: worlds, reports: reports, error: thrownError)
	}
}
