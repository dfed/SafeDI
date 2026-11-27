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
	func differences_areNone_whenAHolesPlacesWriteTheSameText() {
		let hole = GeneratedCode.sequence([Self.textPlace("binding"), Self.textPlace("site")])
		let comparison = NodeRecordsObservation.differences(between: [Self.place(Self.record("a", children: [.indented(hole, by: "    ")]))], and: [Self.place(Self.record("a", children: [.indented(hole, by: "    ")]))])
		#expect(comparison.differences == [])
		#expect(comparison.treePlaceCount == 2)
	}

	@Test
	func differences_nameTheCounts_whenTheTreeWritesNoPlaceAsTextWhereNodeRecordsWriteAHole() {
		let comparison = NodeRecordsObservation.differences(between: [Self.place(Self.record("site"))], and: [.indented(Self.textPlace("site"), by: "        ")])
		#expect(comparison.differences == [
			"root.site: indented 4 in the tree, 8 by node records",
			"root.site: the tree writes 0 places as text, node records 1",
		])
	}

	@Test
	func differences_nameTheField_whenAHolesPlaceWritesOtherText() {
		let comparison = NodeRecordsObservation.differences(between: [Self.textPlace("site", text: "let site = a")], and: [Self.textPlace("site", text: "let site = b")])
		#expect(comparison.differences == [
			"root.site: text is let site = a in the tree, let site = b by node records",
			"root.site: recordText is let site = a in the tree, let site = b by node records",
		])
	}

	@Test
	func differences_nameThePlaceAfter_whenAPayloadBoundBeforeItDiffers() {
		let comparison = NodeRecordsObservation.differences(
			between: [.sequence([Self.textPlace("payload", text: "let payload = a"), .place(PlacePlan(code: .empty, record: .built(Self.record("b"))))])],
			and: [.sequence([Self.textPlace("payload", text: "let payload = c"), .place(PlacePlan(code: .empty, record: .built(Self.record("b"))))])],
		)
		#expect(comparison.differences == [
			"root: before a place, text is let payload = a in the tree, let payload = c by node records",
			"root: before a place, recordText is let payload = a in the tree, let payload = c by node records",
		])
	}

	/// A place written as `text`, with a rename's record that binds `label` and reads nothing, as a hole's site and the
	/// payloads before it are.
	private static func textPlace(_ label: String, text: String? = nil) -> GeneratedCode {
		let text = text ?? "let \(label) = \(label)Value"
		return .place(PlacePlan(code: .text(text), record: .alias(AliasPlaceRecord(property: Property(label: label, typeDescription: .simple(name: "T")), fulfillingProperty: nil, text: text, reads: []))))
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
