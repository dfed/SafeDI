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
	/// The claim of `declaration` in a mock root's world where it is a rename: of kind `mockRename`, as production's
	/// `renameClaim(of:in:)` claims it, since a mock reads no override of a rename. `nil` for any other node.
	static func mockRenameClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		renameClaim(of: declaration, in: world).map { NodeRecordClaim(kind: .mockRename, discharges: $0.discharges, refusals: $0.refusals) }
	}

	/// What a node of a mock root's world whose type declares a rename discharges of stage 1's refusals, and what it
	/// holds instead: the rename is a node of its own (`mockRenameClaim(of:in:)`), so the node discharges `renameOrHole`,
	/// which it still holds where its scope declares an instantiated dependency it does not build, as production's
	/// `receivesOnlyIfAvailableClaim(of:in:)` holds it. Empty for a node that declares no rename.
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
		return ([.renameOrHole], scope.instantiatedDependenciesNotGenerated.isEmpty ? [] : [.renameOrHole])
	}

	/// The record of `declaration`'s place in `variant`, a rename of a mock root's world: production's record, but that an
	/// erased rename only if available maps over its fulfilling value wherever it is bound, as the mock's walk binds it,
	/// whether or not the declaration it reads is optional. A rename reads no override.
	static func mockRenameRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		answers: OnlyIfAvailableAnswers,
	) throws(NodeRecordRefusal) -> AliasPlaceRecord {
		try renameRecord(of: declaration, variant: variant, in: world, answers: answers, mapsWhereBoundOnlyIfAvailable: true)
	}
}
