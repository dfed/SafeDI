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
	/// The refusals of `declaration` as a member of a loop of builders, whatever kind claims it: a member two parents'
	/// loops make different members of again, which would need a function per parent where a record is a function of the
	/// node; a member whose loop step 0 finds that makes nothing again, which the stand-in for its loops does not see; a
	/// mock world's member, whose rebindings hand the mock's configurations, which these records do not yet; and a
	/// `@Sendable` member that captures a member's wrapper that is not `Sendable`, which the tree reports.
	static func loopRefusals(of declaration: DeclarationID, in world: some NodeRecordSources) -> [NodeRecordRefusal] {
		guard !world.loopMembersSharedApart.contains(declaration) else { return [.builderLoopSharedApart] }
		let isUnseenMember = zip(world.edges(from: declaration), world.edgeFacts(from: declaration)).contains { child, edge in
			edge.loop >= 0 && world.madeAgain(from: child).isEmpty && !world.loopMembersSharedApart.contains(child)
		}
		let madeAgain = world.madeAgain(from: declaration)
		let isMockMember = world.isMockWorld && !madeAgain.isEmpty
		// A rebinding names the member's function, so it captures that member's wrapper: a `@Sendable` member that makes a
		// member again that is not `Sendable` captures it, the error the tree reports (`nonSendableWrapperCaptures`).
		let capturesWrapper = world.property(of: declaration)?.propertyType.isSendable == true && madeAgain.contains { member in
			world.property(of: member)?.propertyType.isSendable == false
		}
		return (isUnseenMember || isMockMember ? [.builderLoop] : []) + (capturesWrapper ? [.sendableFunctionCapturesWrapper] : [])
	}

	/// The places `declaration`'s builder function begins with, before every child: a wrapper made again of each member of
	/// its loop it rebinds, in the order it rebinds them, each a call of that member's builder function
	/// (`ClosingPlaceRecord.rebindsLoopMember`). A production world has one variant per node (`nodeHasSeveralVariants`), which is the one
	/// the parent's body calls (oracle B, check 32 of the per-type facts' checks).
	static func loopRebindings(of declaration: DeclarationID, in world: some NodeRecordSources) -> [GeneratedCode] {
		world.madeAgain(from: declaration).compactMap { member in
			guard let property = world.property(of: member) else { return nil }
			let instantiable = world.scope(of: member).instantiable
			return .indented(.place(PlacePlan(code: .empty, record: .closer(ClosingPlaceRecord(
				property: property,
				isErased: world.isErased(member),
				isExtension: instantiable.declarationType.isExtension,
				closedOnFunctionName: ScopeGenerator.functionName(toBuildPropertyNamed: property.label),
				forwardedProperties: instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted(),
				cycleArguments: [],
				rebindsLoopMember: true,
			)))), by: ScopeGenerator.standardIndent)
		}
	}
}
