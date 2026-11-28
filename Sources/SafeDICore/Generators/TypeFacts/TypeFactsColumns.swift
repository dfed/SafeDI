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

// The columns the table side builds beside the frozen interface's (`TypeFactsWorld.swift`): what names properties, labels
// and types by the world's own IDs, until the run's snapshot can look them up.

/// One binding a declaration makes, by the world's IDs (`TypeFactsBinding` names the run's, which the graph cannot look
/// up yet), in the order its scope binds them: the forwarded properties, then each child as it is built. A seam's own
/// parameters are no binding yet: the graph's reads take them from above its root, as its caller hands them, so
/// `isSeamParameter` is set by no binding yet. Trivially copyable.
struct TypeFactsWorldBinding: Hashable, Sendable {
	let label: Int32
	/// The world's ID of the property bound.
	let property: Int32
	/// The world's ID of the type that declares the binding.
	let declaringType: Int32
	/// The index of the declaration's location in `TypeFactsGraph.declarationLocations`, or -1 for none.
	let declarationLocation: Int32
	/// The type whose builder function takes the binding as a parameter, or -1: the graph binds no cycle parameter, since
	/// every reference to a member of a cycle is a call, never a binding.
	let parameterTakingType: Int32
	/// The world's ID of the declaring type's module, or -1 where SafeDI knows none.
	let declaringModule: Int32
	let isReceivedOnlyIfAvailable: Bool
	let isSeamParameter: Bool
	let isCycleParameter: Bool
	/// Whether the binding is a loop member's wrapper its scope's builder functions make again.
	let isReboundByBuilderFunction: Bool
	let isForwarded: Bool
}

/// The fill an edge passes: the hole it fills in the called graph, and its fill path. Trivially copyable.
struct TypeFactsFill: Hashable, Sendable {
	/// The edge's position among the graph's edges.
	let edge: Int32
	/// The world's ID of the seam or public mock called.
	let calledType: Int32
	let isPublicMock: Bool
	/// The hole's position among the called signature's holes.
	let holeIndex: Int32
	/// The world's ID of the type that declares the hole's property.
	let filledHoleOwnerType: Int32
	/// The run of `TypeFactsGraph.fillPathEntries` the fill is built beneath, root first.
	let stackStart: Int32
	let stackCount: Int32
	/// Whether the seam the fill is passed to takes it `@Sendable`: one input of `buildsInSendableFunction`.
	let holeIsSendable: Bool
	/// Whether the fill builds its tree in a `@Sendable` function of its own, the tree's mark
	/// (`ScopeGenerator.buildsInSendableFunction(ofFill:)`): where the seam takes it `@Sendable`, a `@Sendable`-family
	/// dispatcher of its call reaches it, or a `@Sendable` function inside the call's fills refers to it, found by one fold
	/// up the call nesting (`TypeFactsFillSendability`). Exact where `sendabilityRefusal` is empty.
	let buildsInSendableFunction: Bool
	/// Why `buildsInSendableFunction` can differ from the tree's mark (`TypeFactsFillSendability.Columns.fillRefusal`).
	let sendabilityRefusal: TypeFactsSendabilityRefusal
	/// The fill's key (`ScopeGenerator.fillKey(of:)`), which names its place, by its position in
	/// `TypeFactsGraph.fillKeyTexts`.
	let key: Int32
	/// The run of `TypeFactsGraph.fillHandedMemos` the fill takes: the memo it takes of each label some route hands it a
	/// memo of, as the tree's fill takes it (`ScopeGenerator.FillDispatcher.memosHanded(toFills:ofPublicMockCall:labelsReadOnlyAsPlaceField:readingSendableWrapper:among:)`,
	/// the `SendableLazilyInstantiated` its tree reads beside the value applied), by label. Empty for nearly every fill.
	let handedMemoStart: Int32
	let handedMemoCount: Int32
}

/// The memo a fill takes of one label some route hands it a memo of (`ScopeGenerator.FillDispatcher.HandedMemo`): the
/// label's and the memo's property's IDs, and the memo's deferral, which says whether it serves a
/// `SendableLazilyInstantiated`.
struct TypeFactsHandedMemo: Hashable, Sendable {
	let label: Int32
	let property: Int32
	let deferral: SeamSignature.Parameter.Deferral
}

/// One entry of a fill's path: the property built and the concrete type built for it, by the world's IDs.
struct TypeFactsFillPathEntry: Hashable, Sendable {
	let property: Int32
	let concreteType: Int32
}

/// A world's dense IDs of one kind of value, in the order the graph's build first gives each.
struct TypeFactsInterner<Value: Hashable & Sendable>: Sendable {
	mutating func id(of value: Value) -> Int32 {
		if let id = idByValue[value] {
			return id
		}
		let id = Int32(values.count)
		idByValue[value] = id
		values.append(value)
		return id
	}

	func existingID(of value: Value) -> Int32? {
		idByValue[value]
	}

	private(set) var values = [Value]()
	private var idByValue = [Value: Int32]()
}
