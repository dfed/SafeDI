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
@testable import SafeDICore

/// The type key lays out a root's cycles from the per-type plan: each variant's body once, every reference to a cyclic
/// member a call of its variant's function. No walk builds the plan yet, so each test builds the root's places and the
/// variants as the plan would.
struct TypeKeyBodyCycleVariantTests {
	@Test
	func statements_declaresOneFunctionPerVariantCapturingWhatEveryCallPasses_whenTheRootEntersTheCycleFromBothMembers() throws {
		let statements = try #require(TypeKeyBody.statements(
			ofRootBody: [
				Self.alias("p", "P"),
				Self.alias("q", "Q"),
				Self.call("aBuilder", building: "A", variant: 0, reading: ["p", "q"]),
				Self.call("bBuilder", building: "B", variant: 1, reading: ["p", "q"]),
			],
			variants: [
				Self.variant("aBuilder", building: "A", reading: ["p", "q"], children: [
					Self.call("bBuilder", building: "B", variant: 1, reading: ["p", "q"]),
					Self.inline("k", "K", reading: "q", "Q"),
				]),
				Self.variant("bBuilder", building: "B", reading: ["p", "q"], children: [
					Self.call("aBuilder", building: "A", variant: 0, reading: ["p", "q"]),
					Self.inline("m", "M", reading: "p", "P"),
				]),
			],
		))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let p = P()
		        let q = Q()
		        func __safeDI_aBuilder() -> A {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            let k = K(q: q)
		            return A(bBuilder: bBuilder, k: k)
		        }
		        func __safeDI_bBuilder() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            let m = M(p: p)
		            return B(aBuilder: aBuilder, m: m)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		""")
	}

	@Test
	func statements_passesAParameter_whenCallsOfAVariantResolveItsReadToDifferentDeclarations() throws {
		let statements = try #require(TypeKeyBody.statements(
			ofRootBody: [
				Self.alias("x", "X"),
				Self.call("aBuilder", building: "A", variant: 0, reading: []),
				Self.call("bBuilder", building: "B", variant: 1, reading: ["x"]),
			],
			variants: [
				Self.variant("aBuilder", building: "A", reading: [], children: [
					Self.alias("x", "X"),
					Self.call("bBuilder", building: "B", variant: 1, reading: ["x"]),
				]),
				Self.variant("bBuilder", building: "B", reading: ["x"], children: [
					Self.call("aBuilder", building: "A", variant: 0, reading: []),
					Self.inline("k", "K", reading: "x", "X"),
				]),
			],
		))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let x = X()
		        func __safeDI_aBuilder() -> A {
		            let x = X()
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(x: x)
		            }
		            return A(x: x, bBuilder: bBuilder)
		        }
		        func __safeDI_bBuilder(x: X) -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            let k = K(x: x)
		            return B(aBuilder: aBuilder, k: k)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        let bBuilder = Instantiator<B> {
		            __safeDI_bBuilder(x: x)
		        }
		""")
	}

	@Test
	func statements_passesAParameter_whenACallOfAnotherVariantPassesOnWhatAVariantDeclaresItself() throws {
		// The root passes `A` its own `x`, which `A` passes on to `B`, which passes it back; `C` passes `B` an `x` of its own,
		// so `B`'s and so `A`'s calls do not all pass the root's `x`, though `A`'s first-reached calls do.
		let statements = try #require(TypeKeyBody.statements(
			ofRootBody: [
				Self.alias("x", "X"),
				Self.call("aBuilder", building: "A", variant: 0, reading: ["x"]),
				Self.call("cBuilder", building: "C", variant: 2, reading: []),
			],
			variants: [
				Self.variant("aBuilder", building: "A", reading: ["x"], children: [
					Self.call("bBuilder", building: "B", variant: 1, reading: ["x"]),
					Self.inline("k", "K", reading: "x", "X"),
				]),
				Self.variant("bBuilder", building: "B", reading: ["x"], children: [
					Self.call("aBuilder", building: "A", variant: 0, reading: ["x"]),
				]),
				Self.variant("cBuilder", building: "C", reading: [], children: [
					Self.alias("x", "X"),
					Self.call("bBuilder", building: "B", variant: 1, reading: ["x"]),
				]),
			],
		))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let x = X()
		        func __safeDI_aBuilder(x: X) -> A {
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(x: x)
		            }
		            let k = K(x: x)
		            return A(bBuilder: bBuilder, k: k)
		        }
		        func __safeDI_bBuilder(x: X) -> B {
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(x: x)
		            }
		            return B(aBuilder: aBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(x: x)
		        }
		        func __safeDI_cBuilder() -> C {
		            let x = X()
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(x: x)
		            }
		            return C(x: x, bBuilder: bBuilder)
		        }
		        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		""")
	}

	@Test
	func statements_keepsThePathKeysBody_whenAVariantReadsALabelItTakesNoCycleParameterOf() {
		#expect(TypeKeyBody.statements(
			ofRootBody: [
				Self.alias("q", "Q"),
				Self.call("aBuilder", building: "A", variant: 0, reading: []),
			],
			variants: [
				Self.variant("aBuilder", building: "A", reading: [], children: [
					Self.call("aBuilder", building: "A", variant: 0, reading: []),
					Self.inline("k", "K", reading: "q", "Q"),
				]),
			],
		) == nil)
	}

	@Test
	func statements_namesVariantsApart_whenTwoVariantsBuildPropertiesOfOneLabel() throws {
		let statements = try #require(TypeKeyBody.statements(
			ofRootBody: [
				Self.alias("p", "P"),
				Self.alias("q", "Q"),
				Self.call("aBuilder", building: "A", variant: 0, reading: ["p", "q"]),
			],
			variants: [
				Self.variant("aBuilder", building: "A", reading: ["p", "q"], children: [
					Self.call("aBuilder", building: "A", variant: 1, reading: ["p"]),
					Self.inline("k", "K", reading: "q", "Q"),
				]),
				Self.variant("aBuilder", building: "A", reading: ["p"], children: [
					Self.inline("m", "M", reading: "p", "P"),
				]),
			],
		))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let p = P()
		        let q = Q()
		        func __safeDI_aBuilder_() -> A {
		            let m = M(p: p)
		            return A(m: m)
		        }
		        func __safeDI_aBuilder() -> A {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder_)
		            let k = K(q: q)
		            return A(aBuilder: aBuilder, k: k)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		""")
	}

	@Test
	func statements_keepsThePathKeysBody_whenACallTargetsAVariantThePlanDoesNotHold() {
		#expect(TypeKeyBody.statements(
			ofRootBody: [Self.call("aBuilder", building: "A", variant: 1, reading: [])],
			variants: [
				Self.variant("aBuilder", building: "A", reading: [], children: [Self.call("aBuilder", building: "A", variant: 0, reading: [])]),
			],
		) == nil)
	}

	@Test
	func statements_takesNoParameter_whenEveryCallAnswersNothingOrADeclarationStillBeingBuilt() throws {
		let statements = try #require(TypeKeyBody.statements(
			ofRootBody: [
				Self.call("aBuilder", building: "A", variant: 1, reading: []),
				Self.call("bBuilder", building: "B", variant: 0, reading: ["x"], answers: [.none]),
			],
			variants: [
				Self.variant("bBuilder", building: "B", reading: ["x"], answers: [.none], children: [
					Self.inline("k", "K", reading: "x", "X?", passingNil: true),
				]),
				Self.variant("aBuilder", building: "A", reading: [], children: [
					Self.alias("x", "X", typeDescription: .optional(.simple(name: "X"))),
					Self.call("bBuilder", building: "B", variant: 0, reading: ["x"], answers: [.declared(Property(label: "x", typeDescription: .optional(.simple(name: "X"))), isBeingBuilt: true)]),
				]),
			],
		))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        func __safeDI_bBuilder() -> B {
		            let k = K(x: nil)
		            return B(k: k)
		        }
		        func __safeDI_aBuilder() -> A {
		            let x = X()
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            return A(x: x, bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		""")
	}

	@Test
	func statements_typesTheParameterAsItsAnswer_whenOnlyARenameOnlyIfAvailableReadsIt() throws {
		let statements = try #require(TypeKeyBody.statements(
			ofRootBody: [
				Self.alias("x", "X"),
				Self.call("aBuilder", building: "A", variant: 0, reading: ["x"]),
			],
			variants: [
				Self.variant("aBuilder", building: "A", reading: ["x"], children: [
					Self.renameOnlyIfAvailable("anyX", "AnyX", of: "x", "X"),
					Self.call("bBuilder", building: "B", variant: 1, reading: []),
				]),
				Self.variant("bBuilder", building: "B", reading: [], children: [
					Self.alias("x", "X"),
					Self.call("aBuilder", building: "A", variant: 0, reading: ["x"]),
				]),
			],
		))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let x = X()
		        func __safeDI_aBuilder(x: X) -> A {
		            let anyX: AnyX? = (x as X?).map { AnyX($0) }
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            return A(anyX: anyX, bBuilder: bBuilder)
		        }
		        func __safeDI_bBuilder() -> B {
		            let x = X()
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(x: x)
		            }
		            return B(x: x, aBuilder: aBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(x: x)
		        }
		""")
	}

	// MARK: Places as the per-type plan records them

	/// `let <label> = <type>()`, written as text that reads nothing, declaring `typeDescription` where given.
	@Test
	func statementsOfPlan_callsEachBodyAtItsCallPlace_whenThePlanGivesCallsByPath() throws {
		let plan = FakePlan(
			rootStatements: [Self.alias("p", "P"), Self.alias("q", "Q"), Self.leaf("aBuilder", building: "A"), Self.leaf("bBuilder", building: "B")],
			records: [
				1: Self.variant("aBuilder", building: "A", reading: ["p", "q"], children: [Self.leaf("bBuilder", building: "B"), Self.inline("k", "K", reading: "q", "Q")]).record,
				2: Self.variant("bBuilder", building: "B", reading: ["p", "q"], children: [Self.leaf("aBuilder", building: "A"), Self.inline("m", "M", reading: "p", "P")]).record,
			],
			childIndices: [0: [[]: [0, 1, 2, 3]], 1: [[]: [0, 1]], 2: [[]: [0, 1]]],
			calls: [
				0: [Self.variantCall("aBuilder", building: "A", at: [2], calling: 1, reading: ["p", "q"]), Self.variantCall("bBuilder", building: "B", at: [3], calling: 2, reading: ["p", "q"])],
				1: [Self.variantCall("bBuilder", building: "B", at: [0], calling: 2, reading: ["p", "q"])],
				2: [Self.variantCall("aBuilder", building: "A", at: [0], calling: 1, reading: ["p", "q"])],
			],
			labels: [1: ["p", "q"], 2: ["p", "q"]],
		)
		let statements = try TypeKeyBody.statements(ofPlan: plan)
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let p = P()
		        let q = Q()
		        func __safeDI_aBuilder() -> A {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            let k = K(q: q)
		            return A(bBuilder: bBuilder, k: k)
		        }
		        func __safeDI_bBuilder() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            let m = M(p: p)
		            return B(aBuilder: aBuilder, m: m)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		""")
	}

	@Test
	func statementsOfPlan_findsCallPlaceByIndexIntoPropertiesToGenerate_whenTheGeneratorBuildsChildrenOutOfThatOrder() throws {
		// The root builds its children in the order `x`, then `aBuilder`, which are its second and first properties: the
		// call's path names `aBuilder` by its index into `propertiesToGenerate`, never by where it is built.
		let plan = FakePlan(
			rootStatements: [Self.alias("x", "X"), Self.leaf("aBuilder", building: "A")],
			records: [1: Self.variant("aBuilder", building: "A", reading: ["x"], children: [Self.inline("k", "K", reading: "x", "X")]).record],
			childIndices: [0: [[]: [1, 0]], 1: [[]: [0]]],
			calls: [0: [Self.variantCall("aBuilder", building: "A", at: [0], calling: 1, reading: ["x"])]],
			labels: [1: ["x"]],
		)
		let statements = try TypeKeyBody.statements(ofPlan: plan)
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let x = X()
		        func __safeDI_aBuilder() -> A {
		            let k = K(x: x)
		            return A(k: k)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		""")
	}

	@Test
	func statementsOfPlan_callsABodyBeneathABuiltChild_whenTheCallPlaceIsDeeperThanTheBodysRoot() throws {
		let plan = FakePlan(
			rootStatements: [Self.alias("x", "X"), Self.leaf("aBuilder", building: "A")],
			records: [1: Self.variant("aBuilder", building: "A", reading: ["x"], children: [
				Self.built("b", "B", children: [Self.leaf("aBuilder", building: "A")]),
			]).record],
			childIndices: [0: [[]: [0, 1]], 1: [[]: [0], [0]: [0]]],
			calls: [
				0: [Self.variantCall("aBuilder", building: "A", at: [1], calling: 1, reading: ["x"])],
				1: [Self.variantCall("aBuilder", building: "A", at: [0, 0], calling: 1, reading: ["x"])],
			],
			labels: [1: ["x"]],
		)
		let statements = try TypeKeyBody.statements(ofPlan: plan)
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let x = X()
		        func __safeDI_aBuilder() -> A {
		            let b: B = __safeDI_b()
		            return A(b: b)
		        }
		        func __safeDI_b() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            return B(aBuilder: aBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		""")
	}

	@Test
	func statementsOfPlan_keepsTheCallPlacesIndentation_whenTheGeneratorIndentsIt() throws {
		let plan = FakePlan(
			rootStatements: [.indented(Self.leaf("aBuilder", building: "A"), by: "")],
			records: [1: Self.variant("aBuilder", building: "A", reading: [], children: []).record],
			childIndices: [0: [[]: [0]], 1: [[]: []]],
			calls: [0: [Self.variantCall("aBuilder", building: "A", at: [0], calling: 1, reading: [])]],
			labels: [1: []],
		)
		let statements = try TypeKeyBody.statements(ofPlan: plan)
		#expect(GeneratedCode.lines(statements).spelled() == """
		        func __safeDI_aBuilder() -> A {
		            A()
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		""")
	}

	@Test
	func statementsOfPlan_keepsThePathKeysBody_whenACallsPathNamesNoPlace() {
		let plan = FakePlan(
			rootStatements: [Self.leaf("aBuilder", building: "A")],
			records: [1: Self.variant("aBuilder", building: "A", reading: [], children: []).record],
			childIndices: [0: [[]: [0]], 1: [[]: []]],
			calls: [0: [Self.variantCall("aBuilder", building: "A", at: [1], calling: 1, reading: [])]],
			labels: [1: []],
		)
		#expect(throws: TypeKeyRefusal.callNamesNoPlace(body: 0, path: [1])) {
			try TypeKeyBody.statements(ofPlan: plan)
		}
	}

	@Test
	func statementsOfPlan_keepsThePathKeysBody_whenACallIsOfTheRootsOwnBody() {
		let plan = FakePlan(
			rootStatements: [Self.leaf("aBuilder", building: "A")],
			records: [:],
			childIndices: [0: [[]: [0]]],
			calls: [0: [Self.variantCall("aBuilder", building: "A", at: [0], calling: 0, reading: [])]],
			labels: [:],
		)
		#expect(throws: TypeKeyRefusal.callOfBodyOutsidePlan(body: 0, calledBody: 0)) {
			try TypeKeyBody.statements(ofPlan: plan)
		}
	}

	@Test
	func statementsOfPlan_keepsThePathKeysBody_whenTwoCallsShareAPath() {
		let plan = FakePlan(
			rootStatements: [Self.leaf("aBuilder", building: "A")],
			records: [1: Self.variant("aBuilder", building: "A", reading: [], children: []).record],
			childIndices: [0: [[]: [0]], 1: [[]: []]],
			calls: [0: [Self.variantCall("aBuilder", building: "A", at: [0], calling: 1, reading: []), Self.variantCall("aBuilder", building: "A", at: [0], calling: 1, reading: [])]],
			labels: [1: []],
		)
		#expect(throws: TypeKeyRefusal.twoCallsAtOnePlace(body: 0, path: [0])) {
			try TypeKeyBody.statements(ofPlan: plan)
		}
	}

	@Test
	func statementsOfPlan_keepsThePathKeysBody_whenABodysGeneratorBuildsNoPlace() {
		let plan = FakePlan(
			rootStatements: [Self.leaf("aBuilder", building: "A")],
			records: [:],
			childIndices: [0: [[]: [0]]],
			calls: [0: [Self.variantCall("aBuilder", building: "A", at: [0], calling: 1, reading: [])]],
			labels: [1: []],
			bodyCount: 2,
		)
		#expect(throws: TypeKeyRefusal.bodyBuildsNoPlace(body: 1)) {
			try TypeKeyBody.statements(ofPlan: plan)
		}
	}

	@Test
	func statementsOfPlan_keepsThePathKeysBody_whenAGeneratorHasMoreChildrenThanPlaces() {
		let plan = FakePlan(
			rootStatements: [Self.alias("x", "X")],
			records: [:],
			childIndices: [0: [[]: [0, 1]]],
			calls: [:],
			labels: [:],
		)
		#expect(throws: TypeKeyRefusal.childrenOutnumberPlaces(body: 0, path: [])) {
			try TypeKeyBody.statements(ofPlan: plan)
		}
	}

	@Test
	func statementsOfPlan_keepsThePathKeysBody_whenAGeneratorHasFewerChildrenThanPlaces() {
		let plan = FakePlan(
			rootStatements: [Self.alias("x", "X"), Self.alias("y", "Y")],
			records: [:],
			childIndices: [0: [[]: [0]]],
			calls: [:],
			labels: [:],
		)
		#expect(throws: TypeKeyRefusal.placesOutnumberChildren(body: 0, path: [])) {
			try TypeKeyBody.statements(ofPlan: plan)
		}
	}

	@Test
	func statementsOfPlan_keepsThePathKeysBody_whenACallPlaceIsARename() {
		let plan = FakePlan(
			rootStatements: [Self.alias("aBuilder", "A")],
			records: [1: Self.variant("aBuilder", building: "A", reading: [], children: []).record],
			childIndices: [0: [[]: [0]], 1: [[]: []]],
			calls: [0: [Self.variantCall("aBuilder", building: "A", at: [0], calling: 1, reading: [])]],
			labels: [1: []],
		)
		#expect(throws: TypeKeyRefusal.callAtRename(body: 0, path: [0])) {
			try TypeKeyBody.statements(ofPlan: plan)
		}
	}

	@Test
	func statementsOfPlan_keepsThePathKeysBody_whenACallAnswersOtherLabelsThanItsBodyTakes() {
		let plan = FakePlan(
			rootStatements: [Self.alias("x", "X"), Self.leaf("aBuilder", building: "A")],
			records: [1: Self.variant("aBuilder", building: "A", reading: ["x"], children: []).record],
			childIndices: [0: [[]: [0, 1]], 1: [[]: []]],
			calls: [0: [Self.variantCall("aBuilder", building: "A", at: [1], calling: 1, reading: [])]],
			labels: [1: ["x"]],
		)
		#expect(throws: TypeKeyRefusal.answersDifferFromLabels(body: 0, path: [1])) {
			try TypeKeyBody.statements(ofPlan: plan)
		}
	}

	@Test
	func statementsOfPlan_keepsThePathKeysBody_whenABodyHoldsAStatementThatIsNoPlace() {
		let plan = FakePlan(
			rootStatements: [.text("// A comment.")],
			records: [:],
			childIndices: [0: [[]: []]],
			calls: [:],
			labels: [:],
		)
		#expect(throws: TypeKeyRefusal.statementIsNoPlace(body: 0, path: [])) {
			try TypeKeyBody.statements(ofPlan: plan)
		}
	}

	@Test
	func statementsOfPlan_keepsWhatAClosingPlaceSaysOfItsWrapper_whenTheGeneratorWritesTheCallPlaceAsOne() throws {
		let plan = FakePlan(
			rootStatements: [Self.call("aBuilder", building: "A", variant: 7, reading: [])],
			records: [1: Self.variant("aBuilder", building: "A", reading: [], children: []).record],
			childIndices: [0: [[]: [0]], 1: [[]: []]],
			calls: [0: [Self.variantCall("aBuilder", building: "A", at: [0], calling: 1, reading: [])]],
			labels: [1: []],
		)
		let statements = try TypeKeyBody.statements(ofPlan: plan)
		#expect(GeneratedCode.lines(statements).spelled() == """
		        func __safeDI_aBuilder() -> A {
		            A()
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		""")
	}

	@Test
	func statementsOfPlan_throwsVariantReadsLabelItTakesNoParameterOf_whenAVariantReadsALabelItTakesNoParameterOf() {
		let plan = FakePlan(
			rootStatements: [Self.alias("q", "Q"), Self.leaf("aBuilder", building: "A")],
			records: [1: Self.variant("aBuilder", building: "A", reading: [], children: [Self.leaf("aBuilder", building: "A"), Self.inline("k", "K", reading: "q", "Q")]).record],
			childIndices: [0: [[]: [0, 1]], 1: [[]: [0, 1]]],
			calls: [
				0: [Self.variantCall("aBuilder", building: "A", at: [1], calling: 1, reading: [])],
				1: [Self.variantCall("aBuilder", building: "A", at: [0], calling: 1, reading: [])],
			],
			labels: [1: []],
		)
		#expect(throws: TypeKeyRefusal.variantReadsLabelItTakesNoParameterOf) {
			try TypeKeyBody.statements(ofPlan: plan)
		}
	}

	@Test
	func statementsOfPlan_handsEachCallsPassedArguments_whenTheCalledBodyDeclaresThem() throws {
		let cfg = TypeDescription.simple(name: "Cfg")
		var record = Self.variant("aBuilder", building: "A", reading: [], children: []).record
		record.passedArguments = [PassedArgument(parameterName: "cfg", type: cfg, value: .emptyInitialization(cfg), staysOutsideSendableFunctions: false)]
		var call = Self.variantCall("aBuilder", building: "A", at: [0], calling: 1, reading: [])
		call.passedArguments = [PassedArgument(parameterName: "cfg", type: cfg, value: .emptyInitialization(cfg), staysOutsideSendableFunctions: false)]
		let plan = FakePlan(
			rootStatements: [Self.leaf("aBuilder", building: "A")],
			records: [1: record],
			childIndices: [0: [[]: [0]], 1: [[]: []]],
			calls: [0: [call]],
			labels: [1: []],
		)
		let statements = try TypeKeyBody.statements(ofPlan: plan)
		#expect(GeneratedCode.lines(statements).spelled() == """
		        func __safeDI_aBuilder(cfg: Cfg) -> A {
		            A()
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(cfg: Cfg())
		        }
		""")
	}

	@Test
	func statementsOfPlan_keepsThePathKeysBody_whenACallPassesArgumentsItsBodyDoesNotDeclare() {
		var call = Self.variantCall("aBuilder", building: "A", at: [0], calling: 1, reading: [])
		call.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Cfg"), value: .emptyInitialization(.simple(name: "Cfg")), staysOutsideSendableFunctions: false)]
		let plan = FakePlan(
			rootStatements: [Self.leaf("aBuilder", building: "A")],
			records: [1: Self.variant("aBuilder", building: "A", reading: [], children: []).record],
			childIndices: [0: [[]: [0]], 1: [[]: []]],
			calls: [0: [call]],
			labels: [1: []],
		)
		#expect(throws: TypeKeyRefusal.passedArgumentsDifferFromParameters(body: 0, path: [0])) {
			try TypeKeyBody.statements(ofPlan: plan)
		}
	}

	/// A call place of the plan for `label`, an `Instantiator` of `type`, as a body's generator builds it: a place with no
	/// children, which the plan's calls name by path.
	private static func leaf(_ label: String, building type: String) -> GeneratedCode {
		built(label, "Instantiator<\(type)>", typeDescription: .simple(name: "Instantiator", generics: [.simple(name: type)]), children: [])
	}

	/// `let <label>: <type> = __safeDI_<label>()`, built in its own function holding `children`.
	private static func built(_ label: String, _ type: String, typeDescription: TypeDescription? = nil, children: [GeneratedCode]) -> GeneratedCode {
		let childReads = children.compactMap { child -> PlaceRead? in
			guard case let .place(plan) = child.node, case let .built(built) = plan.record else { return nil }
			return PlaceRead(argumentLabel: built.property.label, label: built.property.label, property: built.property, source: .binding(label: built.property.label))
		}
		let record = BuiltPlaceRecord(
			property: Property(label: label, typeDescription: typeDescription ?? .simple(name: type)),
			isErased: false,
			concreteType: .simple(name: type),
			isExtension: false,
			target: .initializer(.simple(name: type)),
			arguments: childReads,
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: "__safeDI_\(label)",
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: !children.isEmpty,
			children: children,
			node: PlanNode(),
		)
		return .place(PlacePlan(code: .text("let \(label) = __safeDI_\(label)()"), record: .built(record)))
	}

	/// The plan's call at `path` of the body `body`, whose function builds `type` for `label`, an `Instantiator`,
	/// answering every label of `reading` with the declaration of its label.
	private static func variantCall(_ label: String, building type: String, at path: [Int], calling body: Int, reading: [String]) -> VariantCall {
		VariantCall(path: path, property: Property(label: label, typeDescription: .simple(name: "Instantiator", generics: [.simple(name: type)])), calledBody: body, arguments: declarations(of: reading))
	}

	/// A plan written out: each body's record, its generators' child indices by path, its calls and its labels, each body
	/// answering its labels with the declarations of their uppercased types.
	private struct FakePlan: TypeKeyVariantPlan {
		let rootStatements: [GeneratedCode]
		let records: [Int: BuiltPlaceRecord]
		let childIndices: [Int: [[Int]: [Int]]]
		let calls: [Int: [VariantCall]]
		let labels: [Int: [String]]
		var bodyCount: Int

		init(rootStatements: [GeneratedCode], records: [Int: BuiltPlaceRecord], childIndices: [Int: [[Int]: [Int]]], calls: [Int: [VariantCall]], labels: [Int: [String]], bodyCount: Int? = nil) {
			self.rootStatements = rootStatements
			self.records = records
			self.childIndices = childIndices
			self.calls = calls
			self.labels = labels
			self.bodyCount = bodyCount ?? records.count + 1
		}

		func record(ofBody body: Int) -> BuiltPlaceRecord? {
			records[body]
		}

		func childIndices(ofPlaceAt path: [Int], inBody body: Int) -> [Int] {
			childIndices[body]?[path] ?? []
		}

		func calls(of body: Int) -> [VariantCall] {
			calls[body] ?? []
		}

		func labels(of body: Int) -> [String] {
			labels[body] ?? []
		}

		func answers(of body: Int) -> [Answer] {
			declarations(of: labels(of: body))
		}

		func isInSendableFamily(_: Int) -> Bool {
			false
		}
	}

	private static func alias(_ label: String, _ type: String, typeDescription: TypeDescription? = nil) -> GeneratedCode {
		let record = AliasPlaceRecord(property: Property(label: label, typeDescription: typeDescription ?? .simple(name: type)), fulfillingProperty: nil, text: "let \(label) = \(type)()", reads: [])
		return .place(PlacePlan(code: .text(record.text), record: .alias(record)))
	}

	/// A call place of the variant at index `variant`, whose function builds `type` for `label`, an `Instantiator`, answering
	/// every label of `reading` with the declaration of its label where it is made, or with each of `answers` where given.
	private static func call(_ label: String, building type: String, variant: Int, reading: [String], answers: [Answer]? = nil) -> GeneratedCode {
		let record = ClosingPlaceRecord(
			callingVariant: variant,
			property: Property(label: label, typeDescription: .simple(name: "Instantiator", generics: [.simple(name: type)])),
			isErased: false,
			isExtension: false,
			forwardedProperties: [],
			labels: reading,
			answers: answers ?? declarations(of: reading),
			arguments: answers ?? declarations(of: reading),
		)
		return .place(PlacePlan(code: .text("let \(label) = Instantiator<\(type)>(__safeDI_\(label))"), record: .closer(record)))
	}

	/// Answers that name, for each label, a declaration of the label's type, its uppercased label.
	private static func declarations(of labels: [String]) -> [Answer] {
		labels.map { .declared(Property(label: $0, typeDescription: .simple(name: $0.uppercased())), isBeingBuilt: false) }
	}

	/// `let <label> = <type>(<read>: <read>)`, built in place, or passing `nil` for the read where `passingNil`.
	private static func inline(_ label: String, _ type: String, reading readLabel: String, _ readType: String, passingNil: Bool = false) -> GeneratedCode {
		let record = BuiltPlaceRecord(
			property: Property(label: label, typeDescription: .simple(name: type)),
			isErased: false,
			concreteType: .simple(name: type),
			isExtension: false,
			target: .initializer(.simple(name: type)),
			arguments: [read(readLabel, readType, passingNil: passingNil)],
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: "__safeDI_\(label)",
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: false,
			children: [],
			node: PlanNode(),
		)
		return .place(PlacePlan(code: .text("let \(label) = \(type)(\(readLabel): \(passingNil ? "nil" : readLabel))"), record: .built(record)))
	}

	/// `let <label>: <type>? = (<fulfilling> as <fulfillingType>?).map { <type>($0) }`, a rename of `fulfilling` only if
	/// available, erased to `type`.
	private static func renameOnlyIfAvailable(_ label: String, _ type: String, of fulfilling: String, _ fulfillingType: String) -> GeneratedCode {
		let record = AliasPlaceRecord(
			property: Property(label: label, typeDescription: .optional(.simple(name: type))),
			fulfillingProperty: Property(label: fulfilling, typeDescription: .simple(name: fulfillingType)),
			text: "let \(label): \(type)? = (\(fulfilling) as \(fulfillingType)?).map { \(type)($0) }",
			readsOnlyIfAvailable: true,
		)
		return .place(PlacePlan(code: .text(record.text), record: .alias(record)))
	}

	/// The variant whose function builds `type` for `label`, an `Instantiator`, whose body answers every label of
	/// `reading` with a declaration of the label's type, or with each of `answers` where given, with `children` its body,
	/// each of which its construction reads.
	private static func variant(_ label: String, building type: String, reading: [String], answers: [Answer]? = nil, children: [GeneratedCode]) -> CycleVariantRecord {
		let childReads = children.compactMap { child -> PlaceRead? in
			guard case let .place(plan) = child.node, let record = plan.record else { return nil }
			let property = switch record {
			case let .built(built):
				built.property
			case let .closer(closer):
				closer.property
			case let .alias(alias):
				alias.property
			}
			return PlaceRead(argumentLabel: property.label, label: property.label, property: property, source: .binding(label: property.label))
		}
		return CycleVariantRecord(record: BuiltPlaceRecord(
			property: Property(label: label, typeDescription: .simple(name: "Instantiator", generics: [.simple(name: type)])),
			isErased: false,
			concreteType: .simple(name: type),
			isExtension: false,
			target: .initializer(.simple(name: type)),
			arguments: childReads,
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: "__safeDI_\(label)",
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: true,
			children: children,
			node: PlanNode(),
		), isInSendableFamily: false, labels: reading, answers: answers ?? declarations(of: reading))
	}

	/// A read of the declaration of `label`, of `type`, which a trailing `?` makes optional, or `nil` where `passingNil`.
	private static func read(_ label: String, _ type: String, passingNil: Bool = false) -> PlaceRead {
		let typeDescription: TypeDescription = type.hasSuffix("?") ? .optional(.simple(name: String(type.dropLast()))) : .simple(name: type)
		return PlaceRead(argumentLabel: label, label: label, property: Property(label: label, typeDescription: typeDescription), source: passingNil ? .nil : .binding(label: label))
	}
}
