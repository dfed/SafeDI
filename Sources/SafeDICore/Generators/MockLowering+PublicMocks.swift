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

/// Stage D1's lowering of lane C's family: public mock roots, the sites of their holes, the payloads and members bound before
/// a node, the fills of their calls, and the calls of other modules' public mocks.
extension MockLowering.Walk {
	/// The node of `generator`, a site of a hole or a fill, whose statements are appended to `lines`, or the first rule it
	/// meets.
	mutating func placeOrFillNode(
		of _: ScopeGenerator,
		inScope _: Set<Property>,
		path _: String,
		indent _: String,
		lines _: inout [String],
	) async -> MockLowering.Lowering<MockLowering.TreeNode> {
		.unsupported(.publicMock)
	}

	/// The node of `generator`, a call of another module's public mock, whose statements are appended to `lines`, or the
	/// first rule it meets.
	mutating func publicMockCallNode(
		of _: ScopeGenerator,
		inScope _: Set<Property>,
		path _: String,
		indent _: String,
		lines _: inout [String],
	) async -> MockLowering.Lowering<MockLowering.TreeNode> {
		.unsupported(.publicMock)
	}
}

extension MockLowering {
	/// A node of a mock's tree that calls another module's public mock, which builds the node's whole tree.
	struct PublicMockCallNode {
		let property: Property
		/// The type whose public mock the node calls.
		let calledType: TypeDescription
		let call: PublicMockCall

		/// The member of the calling mock's overrides that configures the call: the called mock's own `SafeDIOverrides`.
		var overridesField: OverridesField {
			OverridesField(
				name: property.label,
				typeSource: "\(calledType.asSource).\(ReservedName.mockOverridesTypeName)",
				defaultValue: ".init()",
			)
		}

		/// The statements that name the called mock's guard and bind the node, whose overrides are at `nodePath`.
		func bindingLines(path nodePath: String, indent: String) -> [String] {
			[
				"\(indent)\(call.guardLine(for: calledType))",
				"\(indent)let \(property.label) = \(calledType.asSource).\(call.functionName)(\(ReservedName.mockOverridesParameterName): \(nodePath))",
			]
		}
	}
}
