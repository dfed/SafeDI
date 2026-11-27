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

/// The type key lays out a place whose construction is a value it reads: a call of a member of a root declaration,
/// handed a read of the body. No walk records one yet, so each test builds the root's places as a walk would.
struct TypeKeyBodyValuePathTests {
	@Test
	func statements_beginsThePlacesFunctionWithItsEnteredPlaceLines_whenItsRecordCarriesAnEnteredPlace() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.callFields = CallFields(leadingStatement: .enteredPlace(EnteredPlace(slot: "b", nearestOfTypeSlot: nil)), closureArguments: [])
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b() -> B {
		            let __safeDI_place = __safeDI_entered.b ?? .init(safeDIOverrides, above: __safeDI_entered)
		            let safeDIOverrides = __safeDI_place.configuration
		            let __safeDI_entered = __safeDI_place.enteredAbove.entering(b: __safeDI_place)
		            return B()
		        }
		        let b: B = __safeDI_b()
		""")
	}

	@Test
	func statements_entersANewPlaceWithTheNearestConfigurationOfItsType_whenItsEnteredPlaceNamesANearestOfTypeSlot() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.callFields = CallFields(leadingStatement: .enteredPlace(EnteredPlace(slot: "b", nearestOfTypeSlot: "nearestB")), closureArguments: [])
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b() -> B {
		            let __safeDI_place = __safeDI_entered.b ?? .init(__safeDI_entered.nearestB?.configuration ?? safeDIOverrides, above: __safeDI_entered)
		            let safeDIOverrides = __safeDI_place.configuration
		            let __safeDI_entered = __safeDI_place.enteredAbove.entering(b: __safeDI_place)
		            return B()
		        }
		        let b: B = __safeDI_b()
		""")
	}

	@Test
	func statements_beginsThePlacesFunctionByEnteringOnlyTheNearestPlaceOfItsType_whenItsEnteredPlaceHasNoSlot() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.callFields = CallFields(leadingStatement: .enteredPlace(EnteredPlace(slot: nil, nearestOfTypeSlot: "nearestB")), closureArguments: [])
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b() -> B {
		            let __safeDI_entered = __safeDI_entered.entering(nearestB: .init(safeDIOverrides, above: __safeDI_entered))
		            return B()
		        }
		        let b: B = __safeDI_b()
		""")
	}

	@Test
	func statements_spellsMemberCallWithWrappedReads_whenConstructionIsACallOfAValue() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.constructionValue = ConstructionValue(value: .call("member", of: .rootDeclaration("builder"), arguments: [Self.idRead], argumentsWrapper: .simple(name: "Values")), resultWrapper: nil)
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b() -> B {
		            builder.member(Values(id: id))
		        }
		        let b: B = __safeDI_b()
		""")
	}

	@Test
	func statements_keepsThePathKeysBody_whenAValueReadsAPassedArgumentItsFunctionDoesNotTake() {
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.constructionValue = ConstructionValue(value: .member("value", of: .passedArgument("missing")), resultWrapper: nil)
		}) == nil)
	}

	@Test
	func statements_callsAnArgumentValueOnceWhereEachBranchPassesIt_whenTheArgumentIsACallOfAPassedArgumentsMember() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody(arguments: [PlaceRead(argumentLabel: "label", label: "label", property: Property(label: "label", typeDescription: .simple(name: "String")), source: .binding(label: "label"))]) { built in
			built.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Cfg"), value: .member("b", of: .rootDeclaration("overrides")), staysOutsideSendableFunctions: false)]
			built.argumentValues = [0: .call("label", of: .passedArgument("cfg"), arguments: [], argumentsWrapper: nil)]
			built.alternatives = [ConstructionAlternative(closure: .member("builder", of: .passedArgument("cfg")), bindingName: "builder", requiresAbsent: [], use: .calledWithConstructionArguments, resultWrapper: nil)]
		}))
		let spelled = GeneratedCode.lines(statements).spelled()
		#expect(spelled == """
		        let id = 1
		        func __safeDI_b(cfg: Cfg) -> B {
		            if let builder = cfg.builder { builder(cfg.label()) } else { B(label: cfg.label()) }
		        }
		        let b: B = __safeDI_b(cfg: overrides.b)
		""")
		// One call in each branch of the `if`, so the default runs once, where the construction passes it.
		#expect(spelled.components(separatedBy: "cfg.label()").count - 1 == 2)
	}

	@Test
	func statements_keepsThePathKeysBody_whenAnArgumentValueIsAtAPositionWithNoArgument() {
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.argumentValues = [0: .member("label", of: .rootDeclaration("overrides"))]
		}) == nil)
	}

	@Test
	func statements_passesANewValue_whenACallHandsAPassedArgumentAValueThatReadsNoDeclaration() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Cfg"), value: .emptyInitialization(.simple(name: "Cfg")), staysOutsideSendableFunctions: false)]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b(cfg: Cfg) -> B {
		            B()
		        }
		        let b: B = __safeDI_b(cfg: Cfg())
		""")
	}

	@Test
	func statements_passesANewValue_whenACloserHandsThePassedArgumentOfTheFunctionItClosesOn() throws {
		let configuration = PassedArgument(parameterName: "cfg", type: .simple(name: "Cfg"), value: .emptyInitialization(.simple(name: "Cfg")), staysOutsideSendableFunctions: false)
		var closer = ClosingPlaceRecord(
			property: Property(label: "bBuilder", typeDescription: .simple(name: "Instantiator", generics: [.simple(name: "B")])),
			isErased: false,
			isExtension: false,
			closedOnFunctionName: "__safeDI_b",
			forwardedProperties: [],
			cycleArguments: [],
		)
		closer.passedArguments = [configuration]
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody(
			arguments: [PlaceRead(argumentLabel: "bBuilder", label: "bBuilder", property: closer.property, source: .binding(label: "bBuilder"))],
			children: [.place(PlacePlan(code: .text("let bBuilder = Instantiator<B> { __safeDI_b(cfg: Cfg()) }"), record: .closer(closer)))],
		) { built in
			built.passedArguments = [configuration]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b(cfg: Cfg) -> B {
		            let bBuilder = Instantiator<B> {
		                __safeDI_b(cfg: Cfg())
		            }
		            return B(bBuilder: bBuilder)
		        }
		        let b: B = __safeDI_b(cfg: Cfg())
		""")
	}

	@Test
	func statements_constructsByTheAlternativeAlone_whenItHasNoCondition() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.alternatives = [ConstructionAlternative(closure: .member("make", of: .rootDeclaration("overrides")), bindingName: nil, requiresAbsent: [], use: .wrapped(in: .simple(name: "Wrapper")), resultWrapper: nil)]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b() -> B {
		            Wrapper(overrides.make)
		        }
		        let b: B = __safeDI_b()
		""")
	}

	@Test
	func statements_bindsTheClosureByItsOwnName_whenTheBindingNameIsThePassedArgument() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.passedArguments = [PassedArgument(parameterName: "make", type: .optional(.simple(name: "Make")), value: .member("make", of: .rootDeclaration("overrides")), staysOutsideSendableFunctions: false)]
			built.alternatives = [ConstructionAlternative(closure: .passedArgument("make"), bindingName: "make", requiresAbsent: [], use: .calledWithNoArguments, resultWrapper: nil)]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b(make: Make?) -> B {
		            if let make { make() } else { B() }
		        }
		        let b: B = __safeDI_b(make: overrides.make)
		""")
	}

	@Test
	func statements_requiresEachAbsentValueNil_whenAnAlternativeRequiresAValueAbsent() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.alternatives = [ConstructionAlternative(closure: .member("make", of: .rootDeclaration("overrides")), bindingName: "make", requiresAbsent: [.optionalMember("other", of: .rootDeclaration("overrides"))], use: .calledWithNoArguments, resultWrapper: nil)]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b() -> B {
		            if let make = overrides.make, overrides?.other == nil { make() } else { B() }
		        }
		        let b: B = __safeDI_b()
		""")
	}

	@Test
	func statements_wrapsTheAlternativesResult_whenTheAlternativeHasAResultWrapper() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.alternatives = [ConstructionAlternative(closure: .member("make", of: .rootDeclaration("overrides")), bindingName: "make", requiresAbsent: [], use: .calledWithNoArguments, resultWrapper: .simple(name: "Box"))]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b() -> B {
		            if let make = overrides.make { Box(make()) } else { B() }
		        }
		        let b: B = __safeDI_b()
		""")
	}

	@Test
	func statements_triesAlternativesInOrder_whenThePlaceHasTwo() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.alternatives = [
				ConstructionAlternative(closure: .member("first", of: .rootDeclaration("overrides")), bindingName: "first", requiresAbsent: [], use: .calledWithNoArguments, resultWrapper: nil),
				ConstructionAlternative(closure: .member("second", of: .rootDeclaration("overrides")), bindingName: "second", requiresAbsent: [], use: .calledWithNoArguments, resultWrapper: nil),
			]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b() -> B {
		            if let first = overrides.first { first() } else if let second = overrides.second { second() } else { B() }
		        }
		        let b: B = __safeDI_b()
		""")
	}

	@Test
	func statements_wrapsTheConstructionValue_whenTheValueHasAResultWrapper() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.constructionValue = ConstructionValue(value: .read(Self.idRead), resultWrapper: .simple(name: "Box"))
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b() -> B {
		            Box(id)
		        }
		        let b: B = __safeDI_b()
		""")
	}

	@Test
	func statements_passesWhatTheCallReads_whenACallHandsAPassedArgumentARead() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Int"), value: .read(Self.idRead), staysOutsideSendableFunctions: false)]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b(cfg: Int) -> B {
		            B()
		        }
		        let b: B = __safeDI_b(cfg: id)
		""")
	}

	@Test
	func statements_declaresAPassedClosureEscaping_whenAPassedArgumentIsAClosure() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.passedArguments = [PassedArgument(parameterName: "make", type: .closure(arguments: [], isAsync: false, doesThrow: false, returnType: .simple(name: "B")), value: .member("make", of: .rootDeclaration("overrides")), staysOutsideSendableFunctions: false)]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b(make: @escaping () -> B) -> B {
		            B()
		        }
		        let b: B = __safeDI_b(make: overrides.make)
		""")
	}

	@Test
	func statements_spellsAnArgumentValueInPlace_whenAnInlinePlaceReplacesAnArgument() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.inlineBody { inline in
			inline.argumentValues = [0: .member("label", of: .rootDeclaration("overrides"))]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        let b = B(id: overrides.label)
		""")
	}

	@Test
	func statements_constructsAnInlinePlaceByItsAlternative_whenTheAlternativesClosureExists() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.inlineBody { inline in
			inline.alternatives = [ConstructionAlternative(closure: .member("make", of: .rootDeclaration("overrides")), bindingName: "make", requiresAbsent: [], use: .calledWithConstructionArguments, resultWrapper: nil)]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        let b = if let make = overrides.make { make(id) } else { B(id: id) }
		""")
	}

	@Test
	func statements_keepsThePathKeysBody_whenAnInlinePlacesArgumentValueIsAtAPositionWithNoArgument() {
		#expect(TypeKeyBody.statements(ofRootBody: Self.inlineBody { inline in
			inline.argumentValues = [1: .member("label", of: .rootDeclaration("overrides"))]
		}) == nil)
	}

	@Test
	func statements_handsTheClosedOnFunctionARead_whenACloserHandsAPassedArgumentARead() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.closerBody(handing: PassedArgument(parameterName: "cfg", type: .simple(name: "Int"), value: .read(Self.idRead), staysOutsideSendableFunctions: false))))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b(cfg: Int) -> B {
		            let bBuilder = Instantiator<B> {
		                __safeDI_b(cfg: id)
		            }
		            return B(bBuilder: bBuilder)
		        }
		        let b: B = __safeDI_b(cfg: Int())
		""")
	}

	@Test
	func statements_handsTheClosedOnFunctionItsOwnArgument_whenACloserHandsThePassedArgumentOnward() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.closerBody(handing: PassedArgument(parameterName: "cfg", type: .simple(name: "Cfg"), value: .passedArgument("cfg"), staysOutsideSendableFunctions: false))))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b(cfg: Cfg) -> B {
		            let bBuilder = Instantiator<B> {
		                __safeDI_b(cfg: cfg)
		            }
		            return B(bBuilder: bBuilder)
		        }
		        let b: B = __safeDI_b(cfg: Cfg())
		""")
	}

	@Test
	func statements_keepsThePathKeysBody_whenACloserHandsAPassedArgumentAMember() {
		#expect(TypeKeyBody.statements(ofRootBody: Self.closerBody(handing: PassedArgument(parameterName: "cfg", type: .simple(name: "Cfg"), value: .member("cfg", of: .rootDeclaration("overrides")), staysOutsideSendableFunctions: false))) == nil)
	}

	@Test
	func statements_handsANestedCallWhatItsPassedArgumentReads_whenAPlaceInsideAFunctionTakesAPassedArgument() throws {
		let c = Self.builtRecord(label: "c", typeName: "C", hasFunction: true) { c in
			c.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Int"), value: .read(Self.idRead), staysOutsideSendableFunctions: false)]
		}
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody(
			arguments: [Self.cRead],
			children: [.place(PlacePlan(code: .text("let c = C()"), record: .built(c)))],
		) { _ in }))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_c(cfg: Int) -> C {
		            C()
		        }
		        func __safeDI_b() -> B {
		            let c: C = __safeDI_c(cfg: id)
		            return B(c: c)
		        }
		        let b: B = __safeDI_b()
		""")
	}

	@Test
	func statements_laysOutASendableFunction_whenNothingItsBodyReadsOrHandsOnStaysOutsideSendableFunctions() throws {
		let c = Self.builtRecord(label: "c", typeName: "C", hasFunction: true) { c in
			c.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Int"), value: .read(Self.idRead), staysOutsideSendableFunctions: false)]
		}
		let d = Self.builtRecord(label: "d", typeName: "D", hasFunction: false) { d in
			d.argumentValues = [0: .read(Self.idRead)]
		}
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody(
			arguments: [Self.cRead],
			children: [
				.place(PlacePlan(code: .text("let c = C()"), record: .built(c))),
				.place(PlacePlan(code: .text("let d = D(id: id)"), record: .built(d))),
				.place(PlacePlan(code: .text("let e = 2"), record: .alias(AliasPlaceRecord(property: Property(label: "e", typeDescription: .simple(name: "Int")), fulfillingProperty: nil, text: "let e = 2", reads: [])))),
			],
			isSendable: true,
		) { _ in }))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        @Sendable nonisolated func __safeDI_c(cfg: Int) -> C {
		            C()
		        }
		        @Sendable nonisolated func __safeDI_b() -> B {
		            let c: C = __safeDI_c(cfg: id)
		            let d = D(id: id)
		            let e = 2
		            return B(c: c)
		        }
		        let b: B = __safeDI_b()
		""")
	}

	@Test
	func statements_keepsThePathKeysBody_whenASendableFunctionHandsOnAPassedArgumentThatStaysOutsideSendableFunctions() {
		let c = Self.builtRecord(label: "c", typeName: "C", hasFunction: true) { c in
			c.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Cfg"), value: .member("cfg", of: .rootDeclaration("overrides")), staysOutsideSendableFunctions: true)]
		}
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody(
			arguments: [Self.cRead],
			children: [.place(PlacePlan(code: .text("let c = C()"), record: .built(c)))],
			isSendable: true,
		) { _ in }) == nil)
	}

	@Test
	func statements_keepsThePathKeysBody_whenASendableFunctionsCloserReadsAValueThatStaysOutsideSendableFunctions() {
		var read = Self.idRead
		read.staysOutsideSendableFunctions = true
		#expect(TypeKeyBody.statements(ofRootBody: Self.closerBody(handing: PassedArgument(parameterName: "cfg", type: .simple(name: "Int"), value: .read(read), staysOutsideSendableFunctions: false), isSendable: true)) == nil)
	}

	private static let cRead = PlaceRead(
		argumentLabel: "c",
		label: "c",
		property: Property(label: "c", typeDescription: .simple(name: "C")),
		source: .binding(label: "c"),
	)

	/// A place `<label>: <typeName>` constructed with `id`, in a function of its own where `hasFunction`, as `configure` records it.
	private static func builtRecord(label: String, typeName: String, hasFunction: Bool, _ configure: (inout BuiltPlaceRecord) -> Void) -> BuiltPlaceRecord {
		var record = BuiltPlaceRecord(
			property: Property(label: label, typeDescription: .simple(name: typeName)),
			isErased: false,
			concreteType: .simple(name: typeName),
			isExtension: false,
			target: .initializer(.simple(name: typeName)),
			arguments: hasFunction ? [] : [idRead],
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: "__safeDI_\(label)",
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: hasFunction,
			children: [],
			node: PlanNode(),
		)
		configure(&record)
		return record
	}

	/// A read of `id` whose type is not `id`'s declaration's, nor its lazy wrapper's instance, so no code reads it.
	private static let mistypedIdRead = PlaceRead(
		argumentLabel: "id",
		label: "id",
		property: Property(label: "id", typeDescription: .simple(name: "String")),
		source: .binding(label: "id"),
	)

	@Test(arguments: [
		ValuePath.read(mistypedIdRead),
		.member("value", of: .read(mistypedIdRead)),
		.call("make", of: .read(mistypedIdRead), arguments: [], argumentsWrapper: nil),
		.call("make", of: .rootDeclaration("overrides"), arguments: [mistypedIdRead], argumentsWrapper: nil),
	])
	func statements_keepsThePathKeysBody_whenAConstructionValueReadsADeclarationOfAnotherType(value: ValuePath) {
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.constructionValue = ConstructionValue(value: value, resultWrapper: nil)
		}) == nil)
	}

	@Test
	func statements_keepsThePathKeysBody_whenAnAlternativesClosureReadsADeclarationOfAnotherType() {
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.alternatives = [ConstructionAlternative(closure: .read(Self.mistypedIdRead), bindingName: "make", requiresAbsent: [], use: .calledWithNoArguments, resultWrapper: nil)]
		}) == nil)
	}

	@Test
	func statements_keepsThePathKeysBody_whenAnAbsentValueReadsADeclarationOfAnotherType() {
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.alternatives = [ConstructionAlternative(closure: .member("make", of: .rootDeclaration("overrides")), bindingName: "make", requiresAbsent: [.read(Self.mistypedIdRead)], use: .calledWithNoArguments, resultWrapper: nil)]
		}) == nil)
	}

	@Test
	func statements_keepsThePathKeysBody_whenAnArgumentValueReadsADeclarationOfAnotherType() {
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody(arguments: [Self.idRead]) { built in
			built.argumentValues = [0: .read(Self.mistypedIdRead)]
		}) == nil)
	}

	@Test
	func statements_keepsThePathKeysBody_whenACallHandsAPassedArgumentAReadOfADeclarationOfAnotherType() {
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "String"), value: .read(Self.mistypedIdRead), staysOutsideSendableFunctions: false)]
		}) == nil)
	}

	@Test
	func statements_keepsThePathKeysBody_whenASendableFunctionTakesAPassedArgumentThatStaysOutsideSendableFunctions() {
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody(isSendable: true) { built in
			built.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Cfg"), value: .member("cfg", of: .rootDeclaration("overrides")), staysOutsideSendableFunctions: true)]
		}) == nil)
	}

	private static let idRead = PlaceRead(
		argumentLabel: "id",
		label: "id",
		property: Property(label: "id", typeDescription: .simple(name: "Int")),
		source: .binding(label: "id"),
	)

	/// `let id = 1`, then a place that builds `b: B` with `arguments` in a function of its own, `@Sendable` where `isSendable`, whose body builds `children`, as `configure` records it.
	private static func rootBody(arguments: [PlaceRead] = [], children: [GeneratedCode] = [], isSendable: Bool = false, _ configure: (inout BuiltPlaceRecord) -> Void) -> [GeneratedCode] {
		let id = AliasPlaceRecord(property: Property(label: "id", typeDescription: .simple(name: "Int")), fulfillingProperty: nil, text: "let id = 1", reads: [])
		var built = BuiltPlaceRecord(
			property: Property(label: "b", typeDescription: .simple(name: "B")),
			isErased: false,
			concreteType: .simple(name: "B"),
			isExtension: false,
			target: .initializer(.simple(name: "B")),
			arguments: arguments,
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: "__safeDI_b",
			isSendable: isSendable,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: true,
			children: children,
			node: PlanNode(),
		)
		configure(&built)
		return [
			.place(PlacePlan(code: .text("let id = 1"), record: .alias(id))),
			.place(PlacePlan(code: .text("let b = B()"), record: .built(built))),
		]
	}

	/// `let id = 1`, then a place built inline as `b: B(id: id)`, as `configure` records it.
	private static func inlineBody(_ configure: (inout BuiltPlaceRecord) -> Void) -> [GeneratedCode] {
		let id = AliasPlaceRecord(property: Property(label: "id", typeDescription: .simple(name: "Int")), fulfillingProperty: nil, text: "let id = 1", reads: [])
		var inline = BuiltPlaceRecord(
			property: Property(label: "b", typeDescription: .simple(name: "B")),
			isErased: false,
			concreteType: .simple(name: "B"),
			isExtension: false,
			target: .initializer(.simple(name: "B")),
			arguments: [idRead],
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: "__safeDI_b",
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: false,
			children: [],
			node: PlanNode(),
		)
		configure(&inline)
		return [
			.place(PlacePlan(code: .text("let id = 1"), record: .alias(id))),
			.place(PlacePlan(code: .text("let b = B(id: id)"), record: .built(inline))),
		]
	}

	/// The root of `rootBody`, whose place `b`, `@Sendable` where `isSendable`, takes `argument` and builds a closer `bBuilder` that closes on its function,
	/// handing it `argument`.
	private static func closerBody(handing argument: PassedArgument, isSendable: Bool = false) -> [GeneratedCode] {
		var closer = ClosingPlaceRecord(
			property: Property(label: "bBuilder", typeDescription: .simple(name: "Instantiator", generics: [.simple(name: "B")])),
			isErased: false,
			isExtension: false,
			closedOnFunctionName: "__safeDI_b",
			forwardedProperties: [],
			cycleArguments: [],
		)
		closer.passedArguments = [argument]
		return rootBody(
			arguments: [PlaceRead(argumentLabel: "bBuilder", label: "bBuilder", property: closer.property, source: .binding(label: "bBuilder"))],
			children: [.place(PlacePlan(code: .text("let bBuilder = Instantiator<B> { __safeDI_b(cfg: cfg) }"), record: .closer(closer)))],
			isSendable: isSendable,
		) { built in
			built.passedArguments = [PassedArgument(parameterName: "cfg", type: argument.type, value: .emptyInitialization(argument.type), staysOutsideSendableFunctions: false)]
		}
	}
}
