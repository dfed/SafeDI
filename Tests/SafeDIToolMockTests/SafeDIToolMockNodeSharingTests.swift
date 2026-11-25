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

/// A mock's alike places share one plan node (`MockLowering.SharedRecordKey`), and the type key reads the first place's
/// record for all of them, so the key must read every field of each record type it compares: a field it missed would
/// let two places that differ in it share one body.
struct SafeDIToolMockNodeSharingTests {
	@Test
	func sharedRecordKey_readsEveryFieldOfBuiltPlaceRecord_whenComparingPlaces() throws {
		let type = TypeDescription.simple(name: "Screen", generics: [])
		var record = BuiltPlaceRecord(
			property: Property(label: "screen", typeDescription: type),
			isErased: false,
			concreteType: type,
			isExtension: false,
			target: .initializer(type),
			arguments: [],
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: "__safeDI_screen",
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: true,
			children: [],
			node: PlanNode(),
		)
		record.passedArguments = []
		let shape = try #require(MockLowering.BuiltRecordShape(record, passedArgumentValues: false))
		let sharingFields = try #require(record.sharingFields)
		// The node is what the key decides, and the box's fields are read through its accessors.
		let recordFields = Self.fieldNames(of: record).subtracting(["node", "sharingFields"]).union(Self.fieldNames(of: sharingFields))
		#expect(recordFields == Self.fieldNames(of: shape))
	}

	@Test
	func sharedRecordKey_readsEveryFieldOfEachRecordItCompares_whenComparingPlaces() {
		let type = TypeDescription.simple(name: "Screen", generics: [])
		let property = Property(label: "screen", typeDescription: type)
		let closer = ClosingPlaceRecord(property: property, isErased: false, isExtension: false, closedOnFunctionName: "__safeDI_screen", forwardedProperties: [], cycleArguments: [])
		#expect(Self.fieldNames(of: closer) == Self.fieldNames(of: MockLowering.ClosingShape(closer)))
		let alias = AliasPlaceRecord(property: property, fulfillingProperty: nil, text: "")
		#expect(Self.fieldNames(of: alias) == Self.fieldNames(of: MockLowering.AliasShape(alias)))
		let alternative = ConstructionAlternative(closure: .passedArgument("screen"), bindingName: nil, requiresAbsent: [], use: .calledWithNoArguments, resultWrapper: nil)
		#expect(Self.fieldNames(of: alternative) == Self.fieldNames(of: MockLowering.AlternativeShape(alternative)))
		let argument = PassedArgument(parameterName: "screen", type: type, value: .passedArgument("screen"), staysOutsideSendableFunctions: false)
		#expect(Self.fieldNames(of: argument) == Self.fieldNames(of: MockLowering.PassedArgumentShape(argument, value: true)))
	}

	private static func fieldNames(of value: Any) -> Set<String> {
		Set(Mirror(reflecting: value).children.compactMap(\.label))
	}
}
