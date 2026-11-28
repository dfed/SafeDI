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

extension NodeRecords {
	/// The names the mock root's level binds, read from its world: `renamesAbove`, what `mock()`'s signature names apart,
	/// with each node of the level the level names apart (`MockLowering.rootLevelBindingNames(of:besideNamesTaken:)`) in
	/// the order the root builds them, as the walk names the level when it reaches it.
	static func mockRootLevelNames(
		in world: some NodeRecordSources,
		besideNamesTaken namesTaken: MockLowering.RootLevelNamesTaken,
		renamesAbove: [String: [TypeDescription: String]],
	) -> MockLowering.RootLevelNames {
		let edges = world.edges(from: 0)
		let edgeFacts = world.edgeFacts(from: 0)
		let edgeIndices = edges.indices.sorted { (edgeFacts[$0].buildPosition, $0) < (edgeFacts[$1].buildPosition, $1) }
		// A dependency promoted to the root again, from a tree that receives it, is an edge to a declaration the root
		// already lists: the walk builds it once, under the first.
		var listedChildren = Set<DeclarationID>()
		let nodes = edgeIndices.map { edgeIndex -> MockLowering.LevelNode in
			let child = edges[edgeIndex]
			guard !edgeFacts[edgeIndex].isFill, listedChildren.insert(child).inserted, let property = world.property(of: child) else { return .other }
			// No node of the level is a hole: only a public mock's tree is built with holes
			// (`createMockTypeDescriptionToScopeMapping(publicMockCalls:buildsHoles:)`), and a public mock's root is lowered
			// without node records (`lowerPublicMockRoot(of:publicMockContext:context:)`).
			if case .alias = world.kind(of: child) {
				return .alias(property)
			} else {
				return .property(property, isUnavailableDependency: world.scope(of: child).isUnavailableDependency)
			}
		}
		var names = MockLowering.RootLevelNames(namesApart: renamesAbove, propertyNodeBindingNames: [], aliasBindingNamesApart: [])
		for (node, bindingName) in zip(nodes, MockLowering.rootLevelBindingNames(of: nodes, besideNamesTaken: namesTaken)) {
			switch (node, bindingName) {
			case let (.property(property, _), bindingName?):
				names.propertyNodeBindingNames.insert(bindingName)
				if bindingName != property.label {
					names.namesApart[property.label, default: [:]][property.typeDescription] = bindingName
				}
			case let (.alias(property), bindingName?) where bindingName != property.label:
				names.namesApart[property.label, default: [:]][property.typeDescription] = bindingName
				names.aliasBindingNamesApart.insert(bindingName)
			case (.property, nil), (.alias, _), (.other, _):
				// An alias that keeps its label and a node that binds no property name nothing apart.
				break
			}
		}
		return names
	}
}
