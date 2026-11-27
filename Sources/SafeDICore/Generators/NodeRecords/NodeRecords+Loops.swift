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
	/// Whether `declaration` is a member of a loop of builders that makes members again at its top, `nil` where it makes
	/// none. A member is otherwise a node of stage 1 (`checkBuiltByInitializer(_:in:)`).
	static func loopMemberKind(of declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) -> NodeRecordKind? {
		// A member two parents' loops make different members again makes none: a function per parent, which a record that
		// is a function of the node cannot be.
		guard !world.loopMembersSharedApart.contains(declaration) else { throw .builderLoopSharedApart }
		guard !world.madeAgain(from: declaration).isEmpty else { return nil }
		try checkBuiltByInitializer(declaration, in: world)
		return .builtInLoop
	}

	/// The places `declaration`'s builder function begins with, before every child: a wrapper made again of each member of
	/// its loop it rebinds, in the order it rebinds them, each a call of that member's builder function
	/// (`ClosingPlaceRecord.rebindsLoopMember`). Every member is a node of stage 1, so each has one variant, which is the one
	/// the parent's body calls (oracle B, check 32 of the per-type facts' checks).
	static func loopRebindings(of declaration: DeclarationID, in world: some NodeRecordSources) -> [GeneratedCode] {
		world.madeAgain(from: declaration).compactMap { member in
			guard let property = world.property(of: member) else { return nil }
			let instantiable = world.scope(of: member).instantiable
			return .indented(.place(PlacePlan(code: .empty, record: .closer(ClosingPlaceRecord(
				property: property,
				isErased: false,
				isExtension: instantiable.declarationType.isExtension,
				closedOnFunctionName: ScopeGenerator.functionName(toBuildPropertyNamed: property.label),
				forwardedProperties: instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted(),
				cycleArguments: [],
				rebindsLoopMember: true,
			)))), by: ScopeGenerator.standardIndent)
		}
	}
}
