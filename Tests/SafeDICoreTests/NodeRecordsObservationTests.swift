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

/// The comparison every test makes of node records' root body with the tree's (`NodeRecordsObservation.differences`):
/// node records match the tree at every place of every test, so each way they can differ is shown here, on bodies made
/// by hand.
struct NodeRecordsObservationTests {
	@Test
	func differences_areNone_whenEachPlaceRecordsTheSameFields() {
		let comparison = NodeRecordsObservation.differences(between: [Self.place(Self.record("a", children: [Self.place(Self.record("b"))]))], and: [Self.place(Self.record("a", children: [Self.place(Self.record("b"))]))])
		#expect(comparison.differences == [])
		#expect(comparison.treePlaceCount == 2)
	}

	@Test
	func differences_nameTheCounts_whenTheTreeBuildsAnotherNumberOfStatements() {
		let comparison = NodeRecordsObservation.differences(between: [Self.place(Self.record("a")), Self.place(Self.record("b"))], and: [Self.place(Self.record("a"))])
		#expect(comparison.differences == ["root: the tree builds 2 statements, node records 1"])
	}

	@Test
	func differences_nameTheStatement_whenNodeRecordsMakeOneThatIsNoBuiltPlace() {
		let comparison = NodeRecordsObservation.differences(between: [Self.place(Self.record("a"))], and: [.text("let a = A()")])
		#expect(comparison.differences == ["root: node records made a statement that is no built place"])
	}

	@Test
	func differences_nameThePlace_whenTheTreeWritesTextThere() {
		let comparison = NodeRecordsObservation.differences(between: [.indented(.text("let a = A()"), by: "    ")], and: [Self.place(Self.record("a"))])
		#expect(comparison.differences == ["root.a: the tree writes no built place’s record"])
	}

	@Test
	func differences_nameTheIndentation_whenThePlacesAreIndentedApart() {
		let comparison = NodeRecordsObservation.differences(between: [.indented(.place(PlacePlan(code: .empty, record: .built(Self.record("a")))), by: "        ")], and: [Self.place(Self.record("a"))])
		#expect(comparison.differences == ["root.a: indented 8 in the tree, 4 by node records"])
	}

	@Test
	func differences_nameTheFieldAndItsPath_whenAChildsRecordDiffers() {
		let comparison = NodeRecordsObservation.differences(between: [Self.place(Self.record("a", children: [Self.place(Self.record("b", hasFunction: true))]))], and: [Self.place(Self.record("a", children: [Self.place(Self.record("b"))]))])
		#expect(comparison.differences == ["root.a.b: hasFunction is true in the tree, false by node records"])
	}

	@Test
	func differences_nameTheKinds_whenTheTreeClosesACycleWhereNodeRecordsBuildThePlace() {
		let comparison = NodeRecordsObservation.differences(between: [Self.closingPlace(Self.closingRecord("a"))], and: [Self.place(Self.record("a"))])
		#expect(comparison.differences == ["root.a: the tree closes a cycle where node records build the place"])
	}

	@Test
	func differences_nameTheField_whenTheClosingPlacesDiffer() {
		let comparison = NodeRecordsObservation.differences(between: [Self.closingPlace(Self.closingRecord("a", closedOnFunctionName: "__safeDI_a_"))], and: [Self.closingPlace(Self.closingRecord("a"))])
		#expect(comparison.differences == ["root.a: closedOnFunctionName is __safeDI_a_ in the tree, __safeDI_a by node records"])
		#expect(comparison.treePlaceCount == 1)
	}

	@Test
	func differences_nameThePlace_whenTheTreeWritesAnAliasWhereNodeRecordsBuildThePlace() {
		let alias = AliasPlaceRecord(property: Property(label: "a", typeDescription: .simple(name: "A")), fulfillingProperty: Property(label: "b", typeDescription: .simple(name: "A")), text: "let a = b")
		let comparison = NodeRecordsObservation.differences(between: [.indented(.place(PlacePlan(code: .empty, record: .alias(alias))), by: "    ")], and: [Self.place(Self.record("a"))])
		#expect(comparison.differences == ["root.a: the tree writes no built place’s record"])
	}

	/// `record` as a place that closes a cycle, indented as a child of a builder function is.
	private static func closingPlace(_ record: ClosingPlaceRecord) -> GeneratedCode {
		.indented(.place(PlacePlan(code: .empty, record: .closer(record))), by: "    ")
	}

	/// A place that closes a cycle on the function that builds `<label>: <Label>`.
	private static func closingRecord(_ label: String, closedOnFunctionName: String? = nil) -> ClosingPlaceRecord {
		ClosingPlaceRecord(
			property: Property(label: label, typeDescription: .simple(name: label.uppercased())),
			isErased: false,
			isExtension: false,
			closedOnFunctionName: closedOnFunctionName ?? "__safeDI_\(label)",
			forwardedProperties: [],
			cycleArguments: [],
		)
	}

	/// `record` as a place, indented as a child of a builder function is.
	private static func place(_ record: BuiltPlaceRecord) -> GeneratedCode {
		.indented(.place(PlacePlan(code: .empty, record: .built(record))), by: "    ")
	}

	/// A place that builds `<label>: <Label>`, with `children`.
	private static func record(_ label: String, hasFunction: Bool = false, children: [GeneratedCode] = []) -> BuiltPlaceRecord {
		let type = TypeDescription.simple(name: label.uppercased())
		return BuiltPlaceRecord(
			property: Property(label: label, typeDescription: type),
			isErased: false,
			concreteType: type,
			isExtension: false,
			target: .initializer(type),
			arguments: [],
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: "__safeDI_\(label)",
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: hasFunction,
			children: children,
			node: PlanNode(),
		)
	}
}
