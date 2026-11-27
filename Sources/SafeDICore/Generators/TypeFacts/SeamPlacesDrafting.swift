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

// The drafts a seam's place graph (`SeamSignature.Places`) is assembled from, read off the seam's facts world alone: one
// level per (variant, edge) on a route to a hole or to a call that presents places, a site per hole edge, and a case per
// owner level and family. Nothing here reads the seam's generator tree.

/// A level: the body of one variant before one of its edges.
struct SeamPlacesLevelID: Hashable, Sendable {
	/// The edge of the seam root's variant before which its parameters are bound and nothing else is.
	static let seamRootTop: Int32 = -1

	let variant: VariantID
	/// The edge's index in `edgeFacts(from: declaration(of: variant))`, or `seamRootTop`.
	let edge: Int32
}

/// The fill an edge passes, where the edge is a fill's: the hole of the called signature it fills.
struct SeamPlacesFillDraft: Equatable, Sendable {
	/// The world's ID of the seam or public mock called.
	let calledType: Int32
	let isPublicMock: Bool
	/// The hole's position among the called signature's holes.
	let holeIndex: Int32
}

/// The body of one variant before one of its edges, with what a place beneath reads of it.
struct SeamPlacesLevelDraft: Equatable, Sendable {
	let id: SeamPlacesLevelID
	/// Every level whose edge calls this level's variant, in facts order: the levels a route can come down from. Empty
	/// for the seam's root.
	let parents: [SeamPlacesLevelID]
	/// How many of the variant's bindings (`TypeFactsGraph.worldBindings(of:)`) are bound before the edge. Later bindings
	/// hide farther declarations of their label but hold no value there.
	let bindingsBefore: Int32
	/// The edge's position in the order the body builds its children, and the loop of builders it is a member of (-1).
	let nextPosition: Int32
	let nextLoop: Int32
	/// The function the edge opens around its child.
	let opens: TypeFactsFunctionOpened
	/// For a fill's edge, what it fills.
	let fill: SeamPlacesFillDraft?
	/// For a call that closes a cycle, the level of the build it closes on.
	let closesOn: SeamPlacesLevelID?
}

/// A field of a site: a declaration a hole's owner level can see, by the level and binding that declare it.
struct SeamPlacesFieldDraft: Equatable, Sendable {
	let label: WorldLabelID
	let declaredAt: SeamPlacesLevelID
	/// The binding's index in `worldBindings(of: declaration(of: declaredAt.variant))`.
	let binding: Int32
}

/// A hole edge beneath its owner level.
struct SeamPlacesSiteDraft: Equatable, Sendable {
	/// The level before the hole's edge.
	let owner: SeamPlacesLevelID
	/// The hole's leaf.
	let hole: DeclarationID
	/// What the hole's struct carries, in the order its builder names them.
	let fields: [SeamPlacesFieldDraft]
}

/// The places of one owner level in one family: one `.place(sites:)` case.
struct SeamPlacesCaseDraft: Equatable, Sendable {
	let owner: SeamPlacesLevelID
	let isBuiltInSendableFunction: Bool
	let siteOpensSendableFunction: Bool
	/// Empty for a case passed up from a called seam.
	let sites: [SeamPlacesSiteDraft]
	/// For a case passed up from a called seam, that seam's case: a reference, never a copy of its levels.
	let passedUp: SeamSignature.Places.CalledCase?
	/// The first case, in facts order, that presents the same places.
	let firstCasePresentingSamePlaces: Int?
}
