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
	func statements_handsTheClosedOnFunctionAMember_whenACloserHandsAPassedArgumentAMember() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.closerBody(handing: PassedArgument(parameterName: "cfg", type: .simple(name: "Cfg"), value: .member("cfg", of: .rootDeclaration("overrides")), staysOutsideSendableFunctions: false))))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b(cfg: Cfg) -> B {
		            let bBuilder = Instantiator<B> {
		                __safeDI_b(cfg: overrides.cfg)
		            }
		            return B(bBuilder: bBuilder)
		        }
		        let b: B = __safeDI_b(cfg: Cfg())
		""")
	}

	@Test
	func statements_sharesOneFunctionPerType_whenACloserAndABuiltCallHandTheSameSplicedValue() throws {
		// `b` builds `c`, which closes on `b`; `c` at the root builds `b`, which closes on it. Each call of a type's function,
		// built or closing, hands the nearest configuration of the type first, else its parent's field.
		func arguments(ofCallTo type: String, from parent: String) -> [PassedArgument] {
			let lower = type.lowercased()
			return [
				PassedArgument(parameterName: "cfg", type: .simple(name: "\(type)Cfg"), value: .spliced([.value(.passedArgument("\(lower)Nearest")), .text(" ?? "), .value(.member(lower, of: .passedArgument("cfg")))]), staysOutsideSendableFunctions: false),
				PassedArgument(parameterName: "\(parent.lowercased())Nearest", type: .optional(.simple(name: "\(parent)Cfg")), value: .passedArgument("cfg"), staysOutsideSendableFunctions: false),
			]
		}
		func rootArguments(ofCallTo type: String, other: String) -> [PassedArgument] {
			[
				PassedArgument(parameterName: "cfg", type: .simple(name: "\(type)Cfg"), value: .member(type.lowercased(), of: .rootDeclaration("overrides")), staysOutsideSendableFunctions: false),
				PassedArgument(parameterName: "\(other.lowercased())Nearest", type: .optional(.simple(name: "\(other)Cfg")), value: .spliced([.text("nil")]), staysOutsideSendableFunctions: false),
			]
		}
		func read(_ type: String) -> PlaceRead {
			let label = type.lowercased()
			return PlaceRead(argumentLabel: label, label: label, property: Property(label: label, typeDescription: .simple(name: type)), source: .binding(label: label))
		}
		func closer(on type: String, from parent: String) -> GeneratedCode {
			var closer = ClosingPlaceRecord(
				property: Property(label: type.lowercased(), typeDescription: .simple(name: type)),
				isErased: false,
				isExtension: false,
				closedOnFunctionName: "__safeDI_\(type.lowercased())",
				forwardedProperties: [],
				cycleArguments: [],
			)
			closer.passedArguments = arguments(ofCallTo: type, from: parent)
			return .place(PlacePlan(code: .text(""), record: .closer(closer)))
		}
		func built(_ type: String, passedArguments: [PassedArgument], child: String, childCode: GeneratedCode) -> GeneratedCode {
			var record = BuiltPlaceRecord(
				property: Property(label: type.lowercased(), typeDescription: .simple(name: type)),
				isErased: false,
				concreteType: .simple(name: type),
				isExtension: false,
				target: .initializer(.simple(name: type)),
				arguments: [read(child)],
				forwardedProperties: [],
				cycleParameters: [],
				callCycleArguments: [],
				functionName: "__safeDI_\(type.lowercased())",
				isSendable: false,
				typesDeclaredEscaping: [],
				lineEnd: "",
				hasFunction: true,
				children: [childCode],
				node: PlanNode(),
			)
			record.passedArguments = passedArguments
			return .place(PlacePlan(code: .text(""), record: .built(record)))
		}
		let statements = try #require(TypeKeyBody.statements(ofRootBody: [
			built("B", passedArguments: rootArguments(ofCallTo: "B", other: "C"), child: "C", childCode: built("C", passedArguments: arguments(ofCallTo: "C", from: "B"), child: "B", childCode: closer(on: "B", from: "C"))),
			built("C", passedArguments: rootArguments(ofCallTo: "C", other: "B"), child: "B", childCode: built("B", passedArguments: arguments(ofCallTo: "B", from: "C"), child: "C", childCode: closer(on: "C", from: "B"))),
		], outerDeclarations: [Property(label: "overrides", typeDescription: .simple(name: "Overrides"))]))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        func __safeDI_b(cfg: BCfg, cNearest: CCfg?) -> B {
		            let c: C = __safeDI_c(cfg: cNearest ?? cfg.c, bNearest: cfg)
		            return B(c: c)
		        }
		        func __safeDI_c(cfg: CCfg, bNearest: BCfg?) -> C {
		            let b: B = __safeDI_b(cfg: bNearest ?? cfg.b, cNearest: cfg)
		            return C(b: b)
		        }
		        let b: B = __safeDI_b(cfg: overrides.b, cNearest: nil)
		        let c: C = __safeDI_c(cfg: overrides.c, bNearest: nil)
		""")
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

	@Test
	func statements_erasesInsideTheFunction_whenAnErasedPlacesFunctionReturnsTheErasedType() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody(boundAs: .simple(name: "AnyB"), isErased: true) { built in
			built.functionReturnType = .simple(name: "AnyB")
			built.alternatives = [ConstructionAlternative(closure: .member("make", of: .rootDeclaration("overrides")), bindingName: "make", requiresAbsent: [], use: .calledWithNoArguments, resultWrapper: .simple(name: "AnyB"))]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b() -> AnyB {
		            if let make = overrides.make { AnyB(make()) } else { AnyB(B()) }
		        }
		        let b: AnyB = __safeDI_b()
		""")
	}

	@Test
	func statements_returnsThePropertysType_whenAPlacesFunctionReturnsTheProtocolItsTypeFulfills() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody(boundAs: .simple(name: "BProtocol")) { built in
			built.functionReturnType = .simple(name: "BProtocol")
			built.alternatives = [ConstructionAlternative(closure: .member("make", of: .rootDeclaration("overrides")), bindingName: "make", requiresAbsent: [], use: .calledWithNoArguments, resultWrapper: nil)]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b() -> BProtocol {
		            if let make = overrides.make { make() } else { B() }
		        }
		        let b: BProtocol = __safeDI_b()
		""")
	}

	// MARK: Two places alike but for one part of a key

	@Test
	func statements_declaresOneFunctionForBothPlaces_whenTwoPlacesOfATypeAreAlike() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.twoHolders(
			first: Self.placeOfC { _ in },
			second: Self.placeOfC { _ in },
		)))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_c(cfg: Cfg, alt: Cfg) -> C {
		            if let builder = cfg.builder { builder() } else { C(id: id, other: id) }
		        }
		        func __safeDI_b() -> B {
		            let c: C = __safeDI_c(cfg: overrides.cfg, alt: overrides.alt)
		            return B(c: c)
		        }
		        let b: B = __safeDI_b()
		        func __safeDI_e() -> E {
		            let c: C = __safeDI_c(cfg: overrides.cfg, alt: overrides.alt)
		            return E(c: c)
		        }
		        let e: E = __safeDI_e()
		""")
	}

	/// Each part of a structural key keeps two places apart that differ in it alone: left out of the key, the two would
	/// share the first place's function, and the second would be built as the first is. The subject is how many
	/// functions the type gets, so the test counts them; the test above spells the body the two share when alike.
	@Test(arguments: KeyPart.allCases)
	func statements_declaresAFunctionForEachPlace_whenTwoPlacesOfATypeDifferOnlyInOnePartOfTheirKey(part: KeyPart) throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.twoHolders(
			first: Self.placeOfC { part.configure(&$0, isSecond: false) },
			second: Self.placeOfC { part.configure(&$0, isSecond: true) },
		)))
		let functionsOfC = GeneratedCode.lines(statements).spelled().components(separatedBy: "\n").filter { $0.contains("func __safeDI_c") }
		#expect(functionsOfC.count == 2)
	}

	/// A part of a structural key, as the difference between two places of `C` that are otherwise alike (`placeOfC`).
	enum KeyPart: String, CaseIterable, Sendable {
		// A place's construction key (`BuiltPlaceRecord.constructionShape`).
		case alternativeClosure
		case alternativeBindingName
		case alternativeAbsentValues
		case alternativeUse
		case alternativeResultWrapper
		case argumentValue
		case argumentValuePosition
		case constructionValue
		case constructionValueWrapper
		// A value path's key (`ValuePath.shape`) and a read's (`PlaceRead.shape`).
		case memberName
		case memberOfOptional
		case callArgumentsWrapper
		case callArguments
		case newValuesType
		case passedArgumentName
		case rootDeclarationName
		case readOfNil
		case readsArgumentLabel
		// A passed argument's key (`PassedArgument.shape`).
		case passedArgumentType
		case passedArgumentParameterName

		func configure(_ c: inout BuiltPlaceRecord, isSecond: Bool) {
			let cfg = ValuePath.passedArgument("cfg")
			func alternative(closure: ValuePath = .member("builder", of: .passedArgument("cfg")), bindingName: String? = "builder", requiresAbsent: [ValuePath] = [], use: ConstructionAlternative.Use = .calledWithNoArguments, resultWrapper: TypeDescription? = nil) -> ConstructionAlternative {
				ConstructionAlternative(closure: closure, bindingName: bindingName, requiresAbsent: requiresAbsent, use: use, resultWrapper: resultWrapper)
			}
			func make(of value: ValuePath, arguments: [PlaceRead] = [TypeKeyBodyValuePathTests.idRead], argumentsWrapper: TypeDescription? = nil) -> ConstructionValue {
				ConstructionValue(value: .call("make", of: value, arguments: arguments, argumentsWrapper: argumentsWrapper), resultWrapper: nil)
			}
			func passed(_ name: String, type: String = "Cfg") -> PassedArgument {
				PassedArgument(parameterName: name, type: .simple(name: type), value: .member(name, of: .rootDeclaration("overrides")), staysOutsideSendableFunctions: false)
			}
			switch self {
			case .alternativeClosure:
				c.alternatives = [alternative(closure: .member(isSecond ? "otherBuilder" : "builder", of: cfg))]
			case .alternativeBindingName:
				c.alternatives = [alternative(bindingName: isSecond ? "made" : "builder")]
			case .alternativeAbsentValues:
				c.alternatives = [alternative(requiresAbsent: isSecond ? [.member("skipped", of: cfg)] : [])]
			case .alternativeUse:
				c.alternatives = [alternative(use: isSecond ? .calledWithConstructionArguments : .calledWithNoArguments)]
			case .alternativeResultWrapper:
				c.alternatives = [alternative(resultWrapper: isSecond ? .simple(name: "Box") : nil)]
			case .argumentValue:
				c.argumentValues = [0: isSecond ? .member("value", of: .rootDeclaration("overrides")) : .member("value", of: cfg)]
			case .argumentValuePosition:
				c.argumentValues = [isSecond ? 1 : 0: .member("value", of: cfg)]
			case .constructionValue:
				c.constructionValue = isSecond ? ConstructionValue(value: .emptyInitialization(.simple(name: "C")), resultWrapper: nil) : make(of: .member("maker", of: cfg))
			case .constructionValueWrapper:
				c.constructionValue = ConstructionValue(value: .member("made", of: cfg), resultWrapper: isSecond ? .simple(name: "Box") : nil)
			case .memberName:
				c.constructionValue = make(of: .member(isSecond ? "factory" : "maker", of: cfg))
			case .memberOfOptional:
				c.constructionValue = make(of: isSecond ? .optionalMember("maker", of: cfg) : .member("maker", of: cfg))
			case .callArgumentsWrapper:
				c.constructionValue = make(of: .member("maker", of: cfg), argumentsWrapper: isSecond ? .simple(name: "Values") : nil)
			case .callArguments:
				c.constructionValue = make(of: .member("maker", of: cfg), arguments: isSecond ? [] : [TypeKeyBodyValuePathTests.idRead])
			case .newValuesType:
				c.constructionValue = make(of: .emptyInitialization(.simple(name: isSecond ? "OtherMaker" : "Maker")))
			case .passedArgumentName:
				c.constructionValue = make(of: .member("maker", of: .passedArgument(isSecond ? "alt" : "cfg")))
			case .rootDeclarationName:
				c.constructionValue = make(of: .member("maker", of: .rootDeclaration(isSecond ? "defaults" : "overrides")))
			case .readOfNil:
				c.constructionValue = make(of: .member("maker", of: cfg), arguments: [PlaceRead(argumentLabel: "id", label: "id", property: TypeKeyBodyValuePathTests.idRead.property, source: isSecond ? .nil : .binding(label: "id"))])
			case .readsArgumentLabel:
				c.constructionValue = make(of: .member("maker", of: cfg), arguments: [PlaceRead(argumentLabel: isSecond ? "identifier" : "id", label: "id", property: TypeKeyBodyValuePathTests.idRead.property, source: .binding(label: "id"))])
			case .passedArgumentType:
				c.passedArguments = [passed("cfg"), passed("alt", type: isSecond ? "OtherCfg" : "Cfg")]
			case .passedArgumentParameterName:
				c.passedArguments = [passed("cfg"), passed(isSecond ? "other" : "alt")]
			}
		}
	}

	/// Each part of a passed argument's key (`PassedArgument.shape`) keeps apart two callers of a type whose calls differ
	/// in it alone: left out of the key, the two would share the first caller's function, and with it the first call.
	@Test(arguments: PassedArgumentKeyPart.allCases)
	func statements_declaresAFunctionForEachCaller_whenTwoCallersOfATypeDifferOnlyInOnePartOfAnArgumentTheyPass(part: PassedArgumentKeyPart) throws {
		func caller(_ label: String, _ typeName: String, argument: PlaceRead, building child: BuiltPlaceRecord, functionName: String) -> BuiltPlaceRecord {
			BuiltPlaceRecord(
				property: Property(label: label, typeDescription: .simple(name: typeName)),
				isErased: false,
				concreteType: .simple(name: typeName),
				isExtension: false,
				target: .initializer(.simple(name: typeName)),
				arguments: [argument],
				forwardedProperties: [],
				cycleParameters: [],
				callCycleArguments: [],
				functionName: functionName,
				isSendable: false,
				typesDeclaredEscaping: [],
				lineEnd: "",
				hasFunction: true,
				children: [.place(PlacePlan(code: .text("let \(child.property.label) = \(child.concreteType.asSource)()"), record: .built(child)))],
				node: PlanNode(),
			)
		}
		func callerOfC(isSecond: Bool) -> BuiltPlaceRecord {
			caller("b", "B", argument: Self.cRead, building: Self.placeOfC { c in
				c.alternatives = []
				c.passedArguments = [part.argument(isSecond: isSecond)]
			}, functionName: "__safeDI_b")
		}
		let bRead = PlaceRead(argumentLabel: "b", label: "b", property: Property(label: "b", typeDescription: .simple(name: "B")), source: .binding(label: "b"))
		let statements = try #require(TypeKeyBody.statements(ofRootBody: [
			.place(PlacePlan(code: .text("let id = 1"), record: .alias(AliasPlaceRecord(property: Property(label: "id", typeDescription: .simple(name: "Int")), fulfillingProperty: nil, text: "let id = 1", reads: [])))),
			.place(PlacePlan(code: .text("let b = B()"), record: .built(callerOfC(isSecond: false)))),
			.place(PlacePlan(code: .text("let e = E()"), record: .built(caller("e", "E", argument: bRead, building: callerOfC(isSecond: true), functionName: "__safeDI_e")))),
		]))
		let functionsOfB = GeneratedCode.lines(statements).spelled().components(separatedBy: "\n").filter { $0.contains("func __safeDI_b") }
		#expect(functionsOfB.count == 2)
	}

	/// A part of a passed argument's key, as the difference between the arguments two calls pass.
	enum PassedArgumentKeyPart: String, CaseIterable, Sendable {
		// Its parameter's name and type are not in the key: two calls of one function hand the same parameters, and calls
		// of two functions already differ in the function.
		case value
		case staysOutsideSendableFunctions

		func argument(isSecond: Bool) -> PassedArgument {
			PassedArgument(
				parameterName: "cfg",
				type: .simple(name: "Cfg"),
				value: .member(self == .value && isSecond ? "other" : "cfg", of: .rootDeclaration("overrides")),
				staysOutsideSendableFunctions: self == .staysOutsideSendableFunctions && isSecond,
			)
		}
	}

	/// A place `c: C(id: id, other: id)` in a function of its own that takes `cfg` and `alt`, each a member of the root's
	/// `overrides`, and tries `cfg.builder` before its construction, as `configure` records it otherwise.
	private static func placeOfC(_ configure: (inout BuiltPlaceRecord) -> Void) -> BuiltPlaceRecord {
		var record = BuiltPlaceRecord(
			property: Property(label: "c", typeDescription: .simple(name: "C")),
			isErased: false,
			concreteType: .simple(name: "C"),
			isExtension: false,
			target: .initializer(.simple(name: "C")),
			arguments: [idRead, PlaceRead(argumentLabel: "other", label: "id", property: idRead.property, source: .binding(label: "id"))],
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: "__safeDI_c",
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: true,
			children: [],
			node: PlanNode(),
		)
		record.passedArguments = ["cfg", "alt"].map { PassedArgument(parameterName: $0, type: .simple(name: "Cfg"), value: .member($0, of: .rootDeclaration("overrides")), staysOutsideSendableFunctions: false) }
		record.alternatives = [ConstructionAlternative(closure: .member("builder", of: .passedArgument("cfg")), bindingName: "builder", requiresAbsent: [], use: .calledWithNoArguments, resultWrapper: nil)]
		configure(&record)
		return record
	}

	/// `let id = 1`, then `b: B(c: c)` and `e: E(c: c)`, each in a function of its own whose body builds its own `c`: `first` in `b`'s, `second` in `e`'s.
	private static func twoHolders(first: BuiltPlaceRecord, second: BuiltPlaceRecord) -> [GeneratedCode] {
		func holder(_ label: String, _ typeName: String, building c: BuiltPlaceRecord) -> GeneratedCode {
			.place(PlacePlan(code: .text("let \(label) = \(typeName)()"), record: .built(BuiltPlaceRecord(
				property: Property(label: label, typeDescription: .simple(name: typeName)),
				isErased: false,
				concreteType: .simple(name: typeName),
				isExtension: false,
				target: .initializer(.simple(name: typeName)),
				arguments: [cRead],
				forwardedProperties: [],
				cycleParameters: [],
				callCycleArguments: [],
				functionName: "__safeDI_\(label)",
				isSendable: false,
				typesDeclaredEscaping: [],
				lineEnd: "",
				hasFunction: true,
				children: [.place(PlacePlan(code: .text("let c = C()"), record: .built(c)))],
				node: PlanNode(),
			))))
		}
		return [
			.place(PlacePlan(code: .text("let id = 1"), record: .alias(AliasPlaceRecord(property: Property(label: "id", typeDescription: .simple(name: "Int")), fulfillingProperty: nil, text: "let id = 1", reads: [])))),
			holder("b", "B", building: first),
			holder("e", "E", building: second),
		]
	}

	// MARK: A read that resolves to another declaration at each of two places

	/// Each kind of read a place makes reaches its function's parameters: where `id` is one declaration at one place of
	/// `C` and another at the other, the one function both share takes `id`, and each call hands its own. A read left
	/// out of what the place reports would be read from the root inside the function, and `b`'s `c` built from `1`.
	@Test(arguments: ReadSite.allCases)
	func statements_handsEachPlaceTheDeclarationItReads_whenTwoPlacesOfATypeReadALabelDeclaredApart(site: ReadSite) throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: [
			Self.aliasOfID("let id = 1"),
			Self.place(Self.function("b", "B", arguments: [Self.cRead], children: [Self.aliasOfID("let id = 2"), Self.place(Self.function("c", "C", site.configure))])),
			Self.place(Self.function("e", "E", arguments: [Self.cRead], children: [Self.place(Self.function("c", "C", site.configure))])),
		]))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_c(\(site.parameters)) -> C {
		            \(site.construction)
		        }
		        func __safeDI_b() -> B {
		            let id = 2
		            let c: C = __safeDI_c(\(site.arguments))
		            return B(c: c)
		        }
		        let b: B = __safeDI_b()
		        func __safeDI_e() -> E {
		            let c: C = __safeDI_c(\(site.arguments))
		            return E(c: c)
		        }
		        let e: E = __safeDI_e()
		""")
	}

	/// Where in its construction a place of `C` reads `id`.
	enum ReadSite: String, CaseIterable, Sendable {
		case alternativesClosure
		case valueThatMustBeAbsent
		case passedArgument

		func configure(_ c: inout BuiltPlaceRecord) {
			let cfg = PassedArgument(parameterName: "cfg", type: .simple(name: "Cfg"), value: .member("cfg", of: .rootDeclaration("overrides")), staysOutsideSendableFunctions: false)
			switch self {
			case .alternativesClosure:
				c.passedArguments = [cfg]
				c.alternatives = [ConstructionAlternative(closure: .call("make", of: .member("maker", of: .passedArgument("cfg")), arguments: [TypeKeyBodyValuePathTests.idRead], argumentsWrapper: nil), bindingName: "made", requiresAbsent: [], use: .calledWithNoArguments, resultWrapper: nil)]
			case .valueThatMustBeAbsent:
				c.passedArguments = [cfg]
				c.alternatives = [ConstructionAlternative(closure: .member("builder", of: .passedArgument("cfg")), bindingName: "builder", requiresAbsent: [.call("skip", of: .passedArgument("cfg"), arguments: [TypeKeyBodyValuePathTests.idRead], argumentsWrapper: nil)], use: .calledWithNoArguments, resultWrapper: nil)]
			case .passedArgument:
				c.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Int"), value: .read(TypeKeyBodyValuePathTests.idRead), staysOutsideSendableFunctions: false)]
			}
		}

		/// What the function of `C` takes, how it constructs, and what each call hands it: the argument-decided parts
		/// of the one body the test spells.
		var parameters: String {
			switch self {
			case .alternativesClosure, .valueThatMustBeAbsent: "id: Int, cfg: Cfg"
			case .passedArgument: "cfg: Int"
			}
		}

		var construction: String {
			switch self {
			case .alternativesClosure: "if let made = cfg.maker.make(id: id) { made() } else { C() }"
			case .valueThatMustBeAbsent: "if let builder = cfg.builder, cfg.skip(id: id) == nil { builder() } else { C() }"
			case .passedArgument: "C()"
			}
		}

		var arguments: String {
			switch self {
			case .alternativesClosure, .valueThatMustBeAbsent: "id: id, cfg: overrides.cfg"
			case .passedArgument: "cfg: id"
			}
		}
	}

	@Test
	func statements_handsEachCallerTheDeclarationItsCallReads_whenTwoCallersOfATypePassALabelDeclaredApart() throws {
		func callerOfC() -> BuiltPlaceRecord {
			Self.function("b", "B", arguments: [Self.cRead], children: [Self.place(Self.function("c", "C", ReadSite.passedArgument.configure))])
		}
		let bRead = PlaceRead(argumentLabel: "b", label: "b", property: Property(label: "b", typeDescription: .simple(name: "B")), source: .binding(label: "b"))
		let statements = try #require(TypeKeyBody.statements(ofRootBody: [
			Self.aliasOfID("let id = 1"),
			Self.place(callerOfC()),
			Self.place(Self.function("e", "E", arguments: [bRead], children: [Self.aliasOfID("let id = 2"), Self.place(callerOfC())])),
		]))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b(id: Int) -> B {
		            let c: C = __safeDI_c(cfg: id)
		            return B(c: c)
		        }
		        func __safeDI_c(cfg: Int) -> C {
		            C()
		        }
		        let b: B = __safeDI_b(id: id)
		        func __safeDI_e() -> E {
		            let id = 2
		            let b: B = __safeDI_b(id: id)
		            return E(b: b)
		        }
		        let e: E = __safeDI_e()
		""")
	}

	@Test
	func statements_handsEachPlaceTheDeclarationItsClosingCallReads_whenTwoPlacesOfATypeCloseOnTheirFunctionPassingALabelDeclaredApart() throws {
		func cWithCloser() -> BuiltPlaceRecord {
			var closer = ClosingPlaceRecord(property: Property(label: "cBuilder", typeDescription: .simple(name: "Instantiator", generics: [.simple(name: "C")])), isErased: false, isExtension: false, closedOnFunctionName: "__safeDI_c", forwardedProperties: [], cycleArguments: [])
			closer.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Int"), value: .read(Self.idRead), staysOutsideSendableFunctions: false)]
			return Self.function("c", "C", arguments: [PlaceRead(argumentLabel: "cBuilder", label: "cBuilder", property: closer.property, source: .binding(label: "cBuilder"))], children: [.place(PlacePlan(code: .text("let cBuilder = Instantiator<C> { __safeDI_c(cfg: id) }"), record: .closer(closer)))]) { c in
				c.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Int"), value: .emptyInitialization(.simple(name: "Int")), staysOutsideSendableFunctions: false)]
			}
		}
		let statements = try #require(TypeKeyBody.statements(ofRootBody: [
			Self.aliasOfID("let id = 1"),
			Self.place(Self.function("b", "B", arguments: [Self.cRead], children: [Self.aliasOfID("let id = 2"), Self.place(cWithCloser())])),
			Self.place(Self.function("e", "E", arguments: [Self.cRead], children: [Self.place(cWithCloser())])),
		]))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_c(id: Int, cfg: Int) -> C {
		            let cBuilder = Instantiator<C> {
		                __safeDI_c(id: id, cfg: id)
		            }
		            return C(cBuilder: cBuilder)
		        }
		        func __safeDI_b() -> B {
		            let id = 2
		            let c: C = __safeDI_c(id: id, cfg: Int())
		            return B(c: c)
		        }
		        let b: B = __safeDI_b()
		        func __safeDI_e() -> E {
		            let c: C = __safeDI_c(id: id, cfg: Int())
		            return E(c: c)
		        }
		        let e: E = __safeDI_e()
		""")
	}

	// MARK: What a `@Sendable` function reads or hands on

	@Test
	func statements_keepsThePathKeysBody_whenASendableFunctionBuildsAPlaceInlineFromAValueThatStaysOutsideSendableFunctions() {
		var read = Self.idRead
		read.staysOutsideSendableFunctions = true
		let d = BuiltPlaceRecord(
			property: Property(label: "d", typeDescription: .simple(name: "D")),
			isErased: false,
			concreteType: .simple(name: "D"),
			isExtension: false,
			target: .initializer(.simple(name: "D")),
			arguments: [read],
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: "__safeDI_d",
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: false,
			children: [],
			node: PlanNode(),
		)
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody(
			children: [.place(PlacePlan(code: .text("let d = D(id: id)"), record: .built(d)))],
			isSendable: true,
		) { _ in }) == nil)
	}

	@Test
	func statements_keepsThePathKeysBody_whenASendableFunctionHandsOnAValueThatStaysOutsideSendableFunctionsBoundBeforeTheCall() {
		let c = Self.builtRecord(label: "c", typeName: "C", hasFunction: true) { c in
			c.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Cfg"), value: .member("cfg", of: .rootDeclaration("overrides")), staysOutsideSendableFunctions: true, bindsBeforeCall: true)]
		}
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody(
			arguments: [Self.cRead],
			children: [.place(PlacePlan(code: .text("let c = C()"), record: .built(c)))],
			isSendable: true,
		) { _ in }) == nil)
	}

	@Test
	func statements_keepsThePathKeysBody_whenASendableFunctionHandsOnAReadOfAValueThatStaysOutsideSendableFunctions() {
		var read = Self.idRead
		read.staysOutsideSendableFunctions = true
		let c = Self.builtRecord(label: "c", typeName: "C", hasFunction: true) { c in
			c.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Int"), value: .read(read), staysOutsideSendableFunctions: false)]
		}
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody(
			arguments: [Self.cRead],
			children: [.place(PlacePlan(code: .text("let c = C()"), record: .built(c)))],
			isSendable: true,
		) { _ in }) == nil)
	}

	private static func aliasOfID(_ text: String) -> GeneratedCode {
		.place(PlacePlan(code: .text(text), record: .alias(AliasPlaceRecord(property: Property(label: "id", typeDescription: .simple(name: "Int")), fulfillingProperty: nil, text: text, reads: []))))
	}

	private static func place(_ record: BuiltPlaceRecord) -> GeneratedCode {
		.place(PlacePlan(code: .text("let \(record.property.label) = \(record.concreteType.asSource)()"), record: .built(record)))
	}

	/// A place `<label>: <typeName>` constructed with `arguments` in a function of its own whose body builds `children`, as `configure` records it.
	private static func function(_ label: String, _ typeName: String, arguments: [PlaceRead] = [], children: [GeneratedCode] = [], _ configure: (inout BuiltPlaceRecord) -> Void = { _ in }) -> BuiltPlaceRecord {
		var record = BuiltPlaceRecord(
			property: Property(label: label, typeDescription: .simple(name: typeName)),
			isErased: false,
			concreteType: .simple(name: typeName),
			isExtension: false,
			target: .initializer(.simple(name: typeName)),
			arguments: arguments,
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
		)
		configure(&record)
		return record
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

	@Test
	func statements_bindsAPassedArgumentToALocalBeforeTheCall_whenTheArgumentBindsBeforeTheCall() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody { built in
			built.passedArguments = [PassedArgument(parameterName: "make", type: .optional(.simple(name: "Make")), value: .member("make", of: .rootDeclaration("overrides")), staysOutsideSendableFunctions: false, bindsBeforeCall: true)]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b(make: Make?) -> B {
		            B()
		        }
		        let __safeDI_b__make: Make? = overrides.make
		        let b: B = __safeDI_b(make: __safeDI_b__make)
		""")
	}

	@Test
	func statements_laysOutASendableFunction_whenItTakesAPassedArgumentThatStaysOutsideSendableFunctionsBoundBeforeTheCall() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody(isSendable: true) { built in
			built.passedArguments = [PassedArgument(parameterName: "make", type: .optional(.simple(name: "Make")), value: .member("make", of: .rootDeclaration("overrides")), staysOutsideSendableFunctions: true, bindsBeforeCall: true)]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        @Sendable nonisolated func __safeDI_b(make: Make?) -> B {
		            B()
		        }
		        let __safeDI_b__make: Make? = overrides.make
		        let b: B = __safeDI_b(make: __safeDI_b__make)
		""")
	}

	@Test
	func statements_keepsEachPlacesOwnFunction_whenTwoPlacesDifferOnlyInWhetherACallBindsItsArgumentBeforeTheCall() throws {
		func c(bindsBeforeCall: Bool) -> GeneratedCode {
			.place(PlacePlan(code: .text("let c = C()"), record: .built(Self.builtRecord(label: "c", typeName: "C", hasFunction: true) { c in
				c.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Int"), value: .read(Self.idRead), staysOutsideSendableFunctions: false, bindsBeforeCall: bindsBeforeCall)]
			})))
		}
		let statements = try #require(TypeKeyBody.statements(ofRootBody: [
			Self.idDeclaration,
			.place(PlacePlan(code: .text("let b = B()"), record: .built(Self.bRecord(arguments: [Self.cRead], children: [c(bindsBeforeCall: false)])))),
			.place(PlacePlan(code: .text("let d = B()"), record: .built(Self.bRecord(label: "d", arguments: [Self.cRead], children: [c(bindsBeforeCall: true)])))),
		]))
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
		        func __safeDI_d() -> B {
		            let __safeDI_c__cfg: Int = id
		            let c: C = __safeDI_c(cfg: __safeDI_c__cfg)
		            return B(c: c)
		        }
		        let d: B = __safeDI_d()
		""")
	}

	@Test
	func statements_keepsEachPlacesOwnFunction_whenTwoPlacesDifferOnlyInWhetherACloserBindsItsArgumentBeforeTheCall() throws {
		// Each place takes `cfg` and builds a closer on its own function, which hands that function what `id` reads.
		func place(_ label: String, closerBindsBeforeCall: Bool) -> GeneratedCode {
			var closer = ClosingPlaceRecord(
				property: Property(label: "bBuilder", typeDescription: .simple(name: "Instantiator", generics: [.simple(name: "B")])),
				isErased: false,
				isExtension: false,
				closedOnFunctionName: "__safeDI_\(label)",
				forwardedProperties: [],
				cycleArguments: [],
			)
			closer.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Int"), value: .read(Self.idRead), staysOutsideSendableFunctions: false, bindsBeforeCall: closerBindsBeforeCall)]
			var built = Self.bRecord(
				label: label,
				arguments: [PlaceRead(argumentLabel: "bBuilder", label: "bBuilder", property: closer.property, source: .binding(label: "bBuilder"))],
				children: [.place(PlacePlan(code: .text(""), record: .closer(closer)))],
			)
			built.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Int"), value: .emptyInitialization(.simple(name: "Int")), staysOutsideSendableFunctions: false)]
			return .place(PlacePlan(code: .text("let \(label) = B()"), record: .built(built)))
		}
		let statements = try #require(TypeKeyBody.statements(ofRootBody: [
			Self.idDeclaration,
			place("b", closerBindsBeforeCall: false),
			place("d", closerBindsBeforeCall: true),
		]))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b(cfg: Int) -> B {
		            let bBuilder = Instantiator<B> {
		                __safeDI_b(cfg: id)
		            }
		            return B(bBuilder: bBuilder)
		        }
		        let b: B = __safeDI_b(cfg: Int())
		        func __safeDI_d(cfg: Int) -> B {
		            let __safeDI_d__cfg: Int = id
		            let bBuilder = Instantiator<B> {
		                __safeDI_d(cfg: __safeDI_d__cfg)
		            }
		            return B(bBuilder: bBuilder)
		        }
		        let d: B = __safeDI_d(cfg: Int())
		""")
	}

	@Test
	func statements_passesNilOnlyWhereTheStatementReadsNil_whenAnotherStatementOfTheBodyReadsADeclarationAtTheSamePosition() throws {
		// `e` reads `id`; `f` is passed `nil` for a form of `id` its declaration, before both, does not provide, at the same
		// position among its arguments.
		func inline(_ label: String, typeName: String, reading read: PlaceRead) -> GeneratedCode {
			.place(PlacePlan(code: .text(""), record: .built(BuiltPlaceRecord(
				property: Property(label: label, typeDescription: .simple(name: typeName)),
				isErased: false,
				concreteType: .simple(name: typeName),
				isExtension: false,
				target: .initializer(.simple(name: typeName)),
				arguments: [read],
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
			))))
		}
		let nilRead = PlaceRead(argumentLabel: "id", label: "id", property: Property(label: "id", typeDescription: .optional(.simple(name: "String"))), source: .nil)
		let statements = try #require(TypeKeyBody.statements(ofRootBody: [
			Self.idDeclaration,
			inline("e", typeName: "E", reading: Self.idRead),
			inline("f", typeName: "F", reading: nilRead),
		]))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        let e = E(id: id)
		        let f = F(id: nil)
		""")
	}

	@Test
	func statements_readsAnotherBindingOfATextPlaceAtItsOwnType_whenAPlaceInsideAFunctionCapturesIt() throws {
		let d = Self.builtRecord(label: "d", typeName: "D", hasFunction: false) { d in
			d.argumentValues = [0: .read(Self.idRead)]
		}
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.textPlaceBindingIDBesidePair + [
			.place(PlacePlan(code: .text("let b = B()"), record: .built(Self.bRecord(children: [.place(PlacePlan(code: .text("let d = D(id: id)"), record: .built(d)))])))),
		]))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let pair = Pair()
		        let id = 1
		        func __safeDI_b() -> B {
		            let d = D(id: id)
		            return B()
		        }
		        let b: B = __safeDI_b()
		""")
	}

	@Test
	func statements_passesAnotherBindingOfATextPlaceAtItsOwnType_whenANestedCallsPassedArgumentReadsIt() throws {
		let c = Self.builtRecord(label: "c", typeName: "C", hasFunction: true) { c in
			c.passedArguments = [PassedArgument(parameterName: "cfg", type: .simple(name: "Int"), value: .read(Self.idRead), staysOutsideSendableFunctions: false)]
		}
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.textPlaceBindingIDBesidePair + [
			.place(PlacePlan(code: .text("let b = B()"), record: .built(Self.bRecord(arguments: [Self.cRead], children: [.place(PlacePlan(code: .text("let c = C()"), record: .built(c)))])))),
		]))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let pair = Pair()
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

	/// A place written as text that binds `pair: Pair` and, besides it, `id: Int`.
	private static let textPlaceBindingIDBesidePair: [GeneratedCode] = [
		.place(PlacePlan(code: .text("let pair = Pair()\nlet id = 1"), record: .alias(AliasPlaceRecord(
			property: Property(label: "pair", typeDescription: .simple(name: "Pair")),
			fulfillingProperty: nil,
			text: "let pair = Pair()\nlet id = 1",
			reads: [],
			otherBindings: [Property(label: "id", typeDescription: .simple(name: "Int"))],
		)))),
	]

	/// A place that builds `<label>: B` in a function of its own, taking `arguments`, whose body builds `children`.
	private static func bRecord(label: String = "b", arguments: [PlaceRead] = [], children: [GeneratedCode]) -> BuiltPlaceRecord {
		BuiltPlaceRecord(
			property: Property(label: label, typeDescription: .simple(name: "B")),
			isErased: false,
			concreteType: .simple(name: "B"),
			isExtension: false,
			target: .initializer(.simple(name: "B")),
			arguments: arguments,
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
		)
	}

	/// A place written as text that binds `id: Int`.
	private static let idDeclaration = GeneratedCode.place(PlacePlan(code: .text("let id = 1"), record: .alias(AliasPlaceRecord(property: Property(label: "id", typeDescription: .simple(name: "Int")), fulfillingProperty: nil, text: "let id = 1", reads: []))))

	static let idRead = PlaceRead(
		argumentLabel: "id",
		label: "id",
		property: Property(label: "id", typeDescription: .simple(name: "Int")),
		source: .binding(label: "id"),
	)

	/// `let id = 1`, then a place that builds a `B` bound as `b: <propertyType>`, erased to it where `isErased`, with `arguments` in a function of its own, `@Sendable` where `isSendable`, whose body builds `children`, as `configure` records it.
	private static func rootBody(arguments: [PlaceRead] = [], children: [GeneratedCode] = [], isSendable: Bool = false, boundAs propertyType: TypeDescription = .simple(name: "B"), isErased: Bool = false, _ configure: (inout BuiltPlaceRecord) -> Void) -> [GeneratedCode] {
		let id = AliasPlaceRecord(property: Property(label: "id", typeDescription: .simple(name: "Int")), fulfillingProperty: nil, text: "let id = 1", reads: [])
		var built = BuiltPlaceRecord(
			property: Property(label: "b", typeDescription: propertyType),
			isErased: isErased,
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
