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

/// Stage D1's lowering of the names a public mock takes its promoted nodes' values under.
extension MockLowering {
	/// The names of the parameters a public mock takes for `promotedNodes`, each a property its root's level promotes and
	/// the name the node is bound under, where a name differs from the binding's, as the mock's plan names them
	/// (`ScopeGenerator.publicMockPlan`): a promoted `LazilyInstantiated` is taken under its label, unless a parameter named
	/// in `leadingParameterNames` or another promoted node takes that name, and then under its binding's name.
	static func publicMockPromotedParameterNames(
		of promotedNodes: [(property: Property, bindingName: String)],
		besideParametersNamed leadingParameterNames: Set<String>,
	) -> [Property: String] {
		func preferredName(of property: Property, boundAs bindingName: String) -> String {
			property.propertyType.isLazilyInstantiated ? property.label : bindingName
		}
		var countByPreferredName = [String: Int]()
		for (property, bindingName) in promotedNodes {
			countByPreferredName[preferredName(of: property, boundAs: bindingName), default: 0] += 1
		}
		var names = [Property: String]()
		for (property, bindingName) in promotedNodes {
			let name = preferredName(of: property, boundAs: bindingName)
			guard name != bindingName, !leadingParameterNames.contains(name), countByPreferredName[name, default: 0] == 1 else { continue }
			names[property] = name
		}
		return names
	}
}
