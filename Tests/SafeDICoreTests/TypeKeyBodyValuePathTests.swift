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
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody(constructionValue: .call(
			"member",
			of: .rootDeclaration("builder"),
			arguments: [Self.idRead],
			argumentsWrapper: .simple(name: "Values"),
		))))
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
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody(constructionValue: .member("value", of: .passedArgument("missing")))) == nil)
	}

	private static let idRead = PlaceRead(
		argumentLabel: "id",
		label: "id",
		property: Property(label: "id", typeDescription: .simple(name: "Int")),
		source: .binding(label: "id"),
	)

	/// `let id = 1`, then a place that builds `b: B` in a function of its own, whose construction is `value`.
	private static func rootBody(constructionValue value: ValuePath) -> [GeneratedCode] {
		let id = AliasPlaceRecord(property: Property(label: "id", typeDescription: .simple(name: "Int")), fulfillingProperty: nil, text: "let id = 1")
		var built = BuiltPlaceRecord(
			property: Property(label: "b", typeDescription: .simple(name: "B")),
			isErased: false,
			concreteType: .simple(name: "B"),
			isExtension: false,
			target: .initializer(.simple(name: "B")),
			arguments: [],
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: "__safeDI_b",
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: true,
			children: [],
			node: PlanNode(),
		)
		built.constructionValue = ConstructionValue(value: value, resultWrapper: nil)
		return [
			.place(PlacePlan(code: .text("let id = 1"), record: .alias(id))),
			.place(PlacePlan(code: .text("let b = B()"), record: .built(built))),
		]
	}
}
