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

/// The per-place comparison of node records with the tree's records (`NodeRecordsObservation.differences`), on the
/// statements a loop member's function begins with. Every test of the pipeline compares the two and finds them alike, so
/// these build the bodies by hand to show that each way they can differ is reported.
struct NodeRecordsObservationTests {
	@Test
	func differences_namesEachFieldAndIndentation_whenRebindingsCallOtherFunctions() {
		let tree = [rebinding(of: "aBuilder", callingFunctionNamed: "__safeDI_aBuilder", indentedBy: "    ")]
		let nodeRecords = [rebinding(of: "aBuilder", callingFunctionNamed: "__safeDI_bBuilder", indentedBy: "        ")]

		let comparison = NodeRecordsObservation.differences(between: tree, and: nodeRecords)

		#expect(comparison.differences == [
			"root.aBuilder made again: indented 4 in the tree, 8 by node records",
			"root.aBuilder made again: closedOnFunctionName is __safeDI_aBuilder in the tree, __safeDI_bBuilder by node records",
		])
		#expect(comparison.treePlaceCount == 1)
	}

	@Test
	func differences_reportsMissingCloser_whenTreeWritesTextWhereNodeRecordsRebind() {
		let comparison = NodeRecordsObservation.differences(
			between: [.text("let aBuilder = Instantiator<A>(__safeDI_aBuilder)")],
			and: [rebinding(of: "aBuilder", callingFunctionNamed: "__safeDI_aBuilder", indentedBy: "    ")],
		)

		#expect(comparison.differences == ["root.aBuilder made again: the tree writes no closing place’s record"])
	}

	@Test
	func differences_reportsStatementThatIsNoPlace_whenNodeRecordsWriteText() {
		let comparison = NodeRecordsObservation.differences(between: [.text("let a = A()")], and: [.text("let a = A()")])

		#expect(comparison.differences == ["root: node records made a statement that is no place"])
	}

	@Test
	func differences_reportsRename_whenNodeRecordsMakeOne() {
		let property = Property(label: "renamed", typeDescription: .simple(name: "A"))
		let rename = GeneratedCode.place(PlacePlan(code: .empty, record: .alias(AliasPlaceRecord(property: property, fulfillingProperty: nil, text: "let renamed: A? = nil"))))

		let comparison = NodeRecordsObservation.differences(between: [rename], and: [rename])

		#expect(comparison.differences == ["root: node records made a rename, which no stage makes"])
	}

	@Test
	func differences_namesFieldAndIndentation_whenBuiltPlacesDiffer() {
		let comparison = NodeRecordsObservation.differences(
			between: [built(functionNamed: "__safeDI_aBuilder", indentedBy: "    ")],
			and: [built(functionNamed: "__safeDI_aBuilder_2", indentedBy: "        ")],
		)

		#expect(comparison.differences == [
			"root.aBuilder: indented 4 in the tree, 8 by node records",
			"root.aBuilder: functionName is __safeDI_aBuilder in the tree, __safeDI_aBuilder_2 by node records",
		])
	}

	@Test
	func differences_reportsMissingBuiltPlace_whenTreeWritesTextWhereNodeRecordsBuild() {
		let comparison = NodeRecordsObservation.differences(between: [.text("let a = A()")], and: [built(functionNamed: "__safeDI_aBuilder", indentedBy: "    ")])

		#expect(comparison.differences == ["root.aBuilder: the tree writes no built place’s record"])
	}

	private func built(functionNamed functionName: String, indentedBy indentation: String) -> GeneratedCode {
		let type = TypeDescription.simple(name: "A")
		return .indented(.place(PlacePlan(code: .empty, record: .built(BuiltPlaceRecord(
			property: Property(label: "aBuilder", typeDescription: .simple(name: "Instantiator", generics: [type])),
			isErased: false,
			concreteType: type,
			isExtension: false,
			target: .initializer(type),
			arguments: [],
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: functionName,
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: true,
			children: [],
			node: PlanNode(),
		)))), by: indentation)
	}

	private func rebinding(of label: String, callingFunctionNamed functionName: String, indentedBy indentation: String) -> GeneratedCode {
		.indented(.place(PlacePlan(code: .empty, record: .closer(ClosingPlaceRecord(
			property: Property(label: label, typeDescription: .simple(name: "Instantiator", generics: [.simple(name: "A")])),
			isErased: false,
			isExtension: false,
			closedOnFunctionName: functionName,
			forwardedProperties: [],
			cycleArguments: [],
			rebindsLoopMember: true,
		)))), by: indentation)
	}
}
