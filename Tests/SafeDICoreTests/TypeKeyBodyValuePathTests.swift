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

	private static let idRead = PlaceRead(
		argumentLabel: "id",
		label: "id",
		property: Property(label: "id", typeDescription: .simple(name: "Int")),
		source: .binding(label: "id"),
	)

	/// `let id = 1`, then a place that builds `b: B` with `arguments` in a function of its own, whose body builds `children`, as `configure` records it.
	private static func rootBody(arguments: [PlaceRead] = [], children: [GeneratedCode] = [], _ configure: (inout BuiltPlaceRecord) -> Void) -> [GeneratedCode] {
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
			isSendable: false,
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
}
