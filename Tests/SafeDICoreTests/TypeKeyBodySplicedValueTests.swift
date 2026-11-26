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

/// The type key lays out a place whose argument is a spliced value (`ValuePath.spliced`): text, values and the functions an
/// earlier statement of the place's own body declares. No walk records one yet, so each test builds the root's places as a
/// walk would.
struct TypeKeyBodySplicedValueTests {
	@Test
	func statements_spellsEachSegment_whenAnArgumentIsSplicedFromAReadAndAFunctionItsBodyDeclares() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody(children: [Self.fillDeclaration]) { built in
			built.argumentValues = [0: Self.splicedBuilder]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b() -> B {
		            func __safeDI_fill() -> Builder { Builder() }
		            return B(builder: id.map { .init($0) } ?? __safeDI_fill())
		        }
		        let b: B = __safeDI_b()
		""")
	}

	@Test
	func statements_keepsThePathKeysBody_whenASplicedFunctionIsDeclaredOutsideThePlacesOwnBody() {
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody(rootStatements: [Self.fillDeclaration]) { built in
			built.argumentValues = [0: Self.splicedBuilder]
		}) == nil)
	}

	@Test
	func statements_keepsThePathKeysBody_whenAChildPlaceReadsAFunctionItsParentsBodyDeclares() {
		var child = Self.builtRecord(label: "c", typeName: "C")
		child.argumentValues = [0: Self.splicedBuilder]
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody(arguments: [Self.cRead], children: [Self.fillDeclaration, .place(PlacePlan(code: .text("let c = C()"), record: .built(child)))]) { _ in }) == nil)
	}

	@Test
	func statements_keepsThePathKeysBody_whenAFunctionIsDeclaredOnlyUnderAnotherName() {
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody(children: [Self.fillDeclaration]) { built in
			built.argumentValues = [0: .spliced([.declaredFunction("__safeDI_other"), .text("()")])]
		}) == nil)
	}

	@Test
	func statements_keepsThePathKeysBody_whenASplicedValueReadsADeclarationOfAnotherType() {
		let mistypedIdRead = PlaceRead(argumentLabel: "id", label: "id", property: Property(label: "id", typeDescription: .simple(name: "String")), source: .binding(label: "id"))
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody(children: [Self.fillDeclaration]) { built in
			built.argumentValues = [0: .spliced([.value(.read(mistypedIdRead)), .text(" ?? "), .declaredFunction("__safeDI_fill"), .text("()")])]
		}) == nil)
	}

	@Test
	func statements_keepsThePathKeysBody_whenASplicedValueReadsAPassedArgumentItsFunctionDoesNotTake() {
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody(children: [Self.fillDeclaration]) { built in
			built.argumentValues = [0: .spliced([.value(.passedArgument("missing")), .text(" ?? "), .declaredFunction("__safeDI_fill"), .text("()")])]
		}) == nil)
	}

	@Test
	func statements_keepsThePathKeysBody_whenASendableFunctionReadsASplicedValueThatStaysOutsideSendableFunctions() {
		#expect(TypeKeyBody.statements(ofRootBody: Self.rootBody(children: [Self.fillDeclaration], isSendable: true) { built in
			built.argumentValues = [0: Self.splicedBuilder(idStaysOutsideSendableFunctions: true)]
		}) == nil)
	}

	@Test
	func statements_laysOutASplicedValueThatStaysOutsideSendableFunctions_whenNoFunctionReadingItIsSendable() throws {
		#expect(try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody(children: [Self.fillDeclaration]) { built in
			built.argumentValues = [0: Self.splicedBuilder(idStaysOutsideSendableFunctions: true)]
		})).isEmpty == false)
	}

	@Test
	func statements_keepsEachPlacesOwnFunction_whenTwoPlacesSpliceTheirOwnBodysFunctions() throws {
		let first = Self.fillDeclaration
		let second = Self.declaration(ofFunction: "__safeDI_otherFill")
		var c = Self.builtRecord(label: "c", typeName: "C", children: [first])
		c.argumentValues = [0: Self.splicedBuilder]
		var d = Self.builtRecord(label: "d", typeName: "C", children: [second])
		d.argumentValues = [0: .spliced([.value(.read(Self.idRead)), .text(".map { .init($0) } ?? "), .declaredFunction("__safeDI_otherFill"), .text("()")])]
		let statements = try #require(TypeKeyBody.statements(ofRootBody: [
			.place(PlacePlan(code: .text("let id = 1"), record: .alias(AliasPlaceRecord(property: Property(label: "id", typeDescription: .simple(name: "Int")), fulfillingProperty: nil, text: "let id = 1", reads: [])))),
			.place(PlacePlan(code: .text("let c = C()"), record: .built(c))),
			.place(PlacePlan(code: .text("let d = C()"), record: .built(d))),
		]))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_c() -> C {
		            func __safeDI_fill() -> Builder { Builder() }
		            return C(builder: id.map { .init($0) } ?? __safeDI_fill())
		        }
		        let c: C = __safeDI_c()
		        func __safeDI_d() -> C {
		            func __safeDI_otherFill() -> Builder { Builder() }
		            return C(builder: id.map { .init($0) } ?? __safeDI_otherFill())
		        }
		        let d: C = __safeDI_d()
		""")
	}

	@Test
	func statements_spellsTheCallOfASplicedValue_whenAnArgumentCallsAMemberOfIt() throws {
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody(children: [Self.fillDeclaration]) { built in
			built.argumentValues = [0: .call("make", of: .spliced([.declaredFunction("__safeDI_fill"), .text("()")]), arguments: [Self.idRead], argumentsWrapper: nil)]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b() -> B {
		            func __safeDI_fill() -> Builder { Builder() }
		            return B(builder: __safeDI_fill().make(id: id))
		        }
		        let b: B = __safeDI_b()
		""")
	}

	@Test
	func statements_handsTheClosedOnFunctionASplicedValue_whenACloserHandsOne() throws {
		var closer = ClosingPlaceRecord(
			property: Property(label: "bBuilder", typeDescription: .simple(name: "Instantiator", generics: [.simple(name: "B")])),
			isErased: false,
			isExtension: false,
			closedOnFunctionName: "__safeDI_b",
			forwardedProperties: [],
			cycleArguments: [],
		)
		let argument = PassedArgument(parameterName: "cfg", type: .simple(name: "Builder"), value: .spliced([.text("Builder()")]), staysOutsideSendableFunctions: false)
		closer.passedArguments = [argument]
		let statements = try #require(TypeKeyBody.statements(ofRootBody: Self.rootBody(
			arguments: [PlaceRead(argumentLabel: "bBuilder", label: "bBuilder", property: closer.property, source: .binding(label: "bBuilder"))],
			children: [.place(PlacePlan(code: .text("let bBuilder = Instantiator<B> { __safeDI_b(cfg: Builder()) }"), record: .closer(closer)))],
		) { built in
			built.passedArguments = [argument]
		}))
		#expect(GeneratedCode.lines(statements).spelled() == """
		        let id = 1
		        func __safeDI_b(cfg: Builder) -> B {
		            let bBuilder = Instantiator<B> {
		                __safeDI_b(cfg: Builder())
		            }
		            return B(builder: nil, bBuilder: bBuilder)
		        }
		        let b: B = __safeDI_b(cfg: Builder())
		""")
	}

	private static let idRead = PlaceRead(
		argumentLabel: "id",
		label: "id",
		property: Property(label: "id", typeDescription: .simple(name: "Int")),
		source: .binding(label: "id"),
	)

	private static let cRead = PlaceRead(
		argumentLabel: "c",
		label: "c",
		property: Property(label: "c", typeDescription: .simple(name: "C")),
		source: .binding(label: "c"),
	)

	/// The argument a place's construction passes its builder, read at `builder`, which the spliced value replaces.
	private static let builderRead = PlaceRead(
		argumentLabel: "builder",
		label: "builder",
		property: Property(label: "builder", typeDescription: .simple(name: "Builder")),
		source: .binding(label: "builder"),
	)

	/// `id.map { .init($0) } ?? __safeDI_fill()`.
	private static let splicedBuilder = splicedBuilder(idStaysOutsideSendableFunctions: false)

	private static func splicedBuilder(idStaysOutsideSendableFunctions: Bool) -> ValuePath {
		var read = idRead
		read.staysOutsideSendableFunctions = idStaysOutsideSendableFunctions
		return .spliced([.value(.read(read)), .text(".map { .init($0) } ?? "), .declaredFunction("__safeDI_fill"), .text("()")])
	}

	/// A place written as text that declares `__safeDI_fill`.
	private static let fillDeclaration = declaration(ofFunction: "__safeDI_fill")

	/// A place written as text that declares the function `name` and reads nothing.
	private static func declaration(ofFunction name: String) -> GeneratedCode {
		let text = "func \(name)() -> Builder { Builder() }"
		var record = AliasPlaceRecord(property: Property(label: name, typeDescription: .simple(name: "Builder")), fulfillingProperty: nil, text: text, reads: [])
		record.declaredFunctionNames = [name]
		return .place(PlacePlan(code: .text(text), record: .alias(record)))
	}

	/// A place `<label>: <typeName>` in a function of its own that passes a builder, whose body builds `children`.
	private static func builtRecord(label: String, typeName: String, children: [GeneratedCode] = []) -> BuiltPlaceRecord {
		BuiltPlaceRecord(
			property: Property(label: label, typeDescription: .simple(name: typeName)),
			isErased: false,
			concreteType: .simple(name: typeName),
			isExtension: false,
			target: .initializer(.simple(name: typeName)),
			arguments: [builderRead],
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

	/// `let id = 1`, then `rootStatements`, then a place `b: B` that passes a builder, in a function of its own, `@Sendable`
	/// where `isSendable`, whose body builds `children`, as `configure` records it.
	private static func rootBody(arguments: [PlaceRead] = [], rootStatements: [GeneratedCode] = [], children: [GeneratedCode] = [], isSendable: Bool = false, _ configure: (inout BuiltPlaceRecord) -> Void) -> [GeneratedCode] {
		let id = AliasPlaceRecord(property: Property(label: "id", typeDescription: .simple(name: "Int")), fulfillingProperty: nil, text: "let id = 1", reads: [])
		var built = BuiltPlaceRecord(
			property: Property(label: "b", typeDescription: .simple(name: "B")),
			isErased: false,
			concreteType: .simple(name: "B"),
			isExtension: false,
			target: .initializer(.simple(name: "B")),
			arguments: [builderRead] + arguments,
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
		return [.place(PlacePlan(code: .text("let id = 1"), record: .alias(id)))]
			+ rootStatements
			+ [.place(PlacePlan(code: .text("let b = B()"), record: .built(built)))]
	}
}
