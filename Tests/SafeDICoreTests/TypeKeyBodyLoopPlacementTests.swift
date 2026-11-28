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

/// The type key declares each member of a loop of builders right before the statement that builds it, as the path key
/// declares a loop it writes once (`declaresLoopMembersAsThePathKeyDoes`), only where that keeps Swift's capture rule.
/// The tree orders what a loop's members receive before the loop, so no generated root binds a capture between two
/// members' statements: each test builds the root's places as a walk would.
struct TypeKeyBodyLoopPlacementTests {
	@Test
	func statements_declaresEachMemberBeforeItsStatement_whenWhatTheLaterMemberCapturesIsBoundBeforeBoth() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody(bindsXBetweenMembers: false), laysOutEveryLoop: true, declaresLoopMembersAsThePathKeyDoes: true))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let x = 1
		        func __safeDI_aBuilder() -> A {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            return A(bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        func __safeDI_bBuilder() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            return B(aBuilder: aBuilder, x: x)
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		""")
	}

	@Test
	func statements_keepsThePathKeysBody_whenTheRootBindsWhatALaterMemberCapturesBetweenTwoMembers() {
		// `A`'s statement uses `A`'s function, which calls `B`'s, which captures `x`: declared before `x`, that use is
		// Swift's "closure captures 'x' before it is declared".
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody(bindsXBetweenMembers: true), laysOutEveryLoop: true, declaresLoopMembersAsThePathKeyDoes: true) == nil)
	}

	@Test
	func statements_nestsEachCycleFunctionInTheBodyThatBuildsIt_whenTheCycleHoldsALoopRebinding() throws {
		// `cBuilder`'s function closes the cycle on `aBuilder`'s and makes itself again, so the three functions are one
		// component of calls that the root's body enters once: the path key nests each in the body that builds it.
		let statements = try #require(TypeKeyBody.statements(ofRootBody: [Self.cycle()], laysOutEveryLoop: true, declaresLoopMembersAsThePathKeyDoes: true))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        func __safeDI_aBuilder() -> A {
		            func __safeDI_bBuilder() -> B {
		                func __safeDI_cBuilder() -> C {
		                    let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		                    let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		                    return C(cBuilder: cBuilder, aBuilder: aBuilder)
		                }
		                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		                return B(cBuilder: cBuilder)
		            }
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            return A(bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		""")
	}

	// MARK: Private

	/// The root's `aBuilder: Instantiator<A>`, whose `A` builds `bBuilder`, whose `B` builds `cBuilder`, whose `C` makes
	/// `cBuilder` again, as a member of a loop of builders, and closes the cycle on `aBuilder`, as a walk builds them.
	private static func cycle() -> GeneratedCode {
		let c = built("c", children: [closer("c", rebindsLoopMember: true), closer("a", rebindsLoopMember: false)], reads: ["c", "a"])
		let b = built("b", children: [c], reads: ["c"])
		return built("a", children: [b], reads: ["b"])
	}

	/// The place `<label>Builder: Instantiator<Label>`, whose function holds `children` and builds its type with
	/// `<read>Builder` for each of `reads`.
	private static func built(_ label: String, children: [GeneratedCode], reads: [String]) -> GeneratedCode {
		let type = TypeDescription.simple(name: label.uppercased())
		let record = BuiltPlaceRecord(
			property: builderProperty(label),
			isErased: false,
			concreteType: type,
			isExtension: false,
			target: .initializer(type),
			arguments: reads.map { read("\($0)Builder", type: builderProperty($0).typeDescription) },
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: "__safeDI_\(label)Builder",
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: true,
			children: children.map { .indented($0, by: "    ") },
			node: PlanNode(),
		)
		return .place(PlacePlan(code: .text("let \(label)Builder = Instantiator<\(label.uppercased())>(__safeDI_\(label)Builder)"), record: .built(record)))
	}

	/// A call of `<label>Builder`'s function, which closes a cycle on it or makes a member of a loop again.
	private static func closer(_ label: String, rebindsLoopMember: Bool) -> GeneratedCode {
		.place(PlacePlan(code: .empty, record: .closer(ClosingPlaceRecord(
			property: builderProperty(label),
			isErased: false,
			isExtension: false,
			closedOnFunctionName: "__safeDI_\(label)Builder",
			forwardedProperties: [],
			cycleArguments: [],
			rebindsLoopMember: rebindsLoopMember,
		))))
	}

	/// The root's `aBuilder: Instantiator<A>` and `bBuilder: Instantiator<B>`, a loop whose members each make the other
	/// again, and `let x = 1`, which `B` receives: first, or between the two members where `bindsXBetweenMembers`.
	private static func rootBody(bindsXBetweenMembers: Bool) -> [GeneratedCode] {
		let x = AliasPlaceRecord(property: Property(label: "x", typeDescription: .simple(name: "Int")), fulfillingProperty: nil, text: "let x = 1", reads: [])
		let xPlace = GeneratedCode.place(PlacePlan(code: .text("let x = 1"), record: .alias(x)))
		let a = member("a", receiving: "b", reads: [])
		let b = member("b", receiving: "a", reads: [read("x", type: .simple(name: "Int"))])
		return bindsXBetweenMembers ? [a, xPlace, b] : [xPlace, a, b]
	}

	/// The place `<label>Builder: Instantiator<Label>`, whose function makes `<other>Builder` again and builds its type
	/// with it and `reads`.
	private static func member(_ label: String, receiving other: String, reads: [PlaceRead]) -> GeneratedCode {
		let otherProperty = builderProperty(other)
		let rebinding = ClosingPlaceRecord(
			property: otherProperty,
			isErased: false,
			isExtension: false,
			closedOnFunctionName: "__safeDI_\(other)Builder",
			forwardedProperties: [],
			cycleArguments: [],
			rebindsLoopMember: true,
		)
		let type = TypeDescription.simple(name: label.uppercased())
		let built = BuiltPlaceRecord(
			property: builderProperty(label),
			isErased: false,
			concreteType: type,
			isExtension: false,
			target: .initializer(type),
			arguments: [read("\(other)Builder", type: otherProperty.typeDescription)] + reads,
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: "__safeDI_\(label)Builder",
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: true,
			children: [.indented(.place(PlacePlan(code: .empty, record: .closer(rebinding))), by: "    ")],
			node: PlanNode(),
		)
		return .place(PlacePlan(code: .text("let \(label)Builder = Instantiator<\(label.uppercased())>(__safeDI_\(label)Builder)"), record: .built(built)))
	}

	private static func builderProperty(_ label: String) -> Property {
		Property(label: "\(label)Builder", typeDescription: .simple(name: "Instantiator", generics: [.simple(name: label.uppercased())]))
	}

	private static func read(_ label: String, type: TypeDescription) -> PlaceRead {
		PlaceRead(argumentLabel: label, label: label, property: Property(label: label, typeDescription: type), source: .binding(label: label))
	}
}
