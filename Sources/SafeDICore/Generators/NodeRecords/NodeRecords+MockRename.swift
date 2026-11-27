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
	/// What a node of a mock root's world whose type declares a rename discharges of stage 1's refusals, and what it
	/// holds instead: the rename is a node of its own, production's (`renameClaim(of:in:)`), so the node discharges
	/// `renameOrHole`, and holds nothing in its place: an instantiated dependency its scope does not build is
	/// `uncoveredDependency` (`mockUncoveredDependencyDischarges(of:in:)`). Empty for a node that declares no rename.
	static func mockRenameDischargesAndRefusals(of declaration: DeclarationID, in world: some NodeRecordSources) -> (discharges: Set<NodeRecordRefusal>, refusals: [NodeRecordRefusal]) {
		let scope = world.scope(of: declaration)
		var declaresRename = false
		for propertyToGenerate in scope.propertiesToGenerate {
			switch propertyToGenerate {
			case .aliased:
				declaresRename = true
			case .hole, .instantiated:
				// A mock world holds no hole: only the public mocks' scope map builds holes
				// (`createMockTypeDescriptionToScopeMapping(publicMockCalls:buildsHoles:)`), only a public mock's root is built
				// from it (`MockScopes.forMockRoot(_:)`), and a public mock's root is lowered without node records
				// (`ScopeGenerator.lowerMockRoot(context:worldRoot:)`, since a module that declares one always has the
				// public mock context).
				break
			}
		}
		guard declaresRename else { return ([], []) }
		return ([.renameOrHole], [])
	}
}
