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

// The records of what a seam call passes for a builder it fills, and of each fill: what the engine spells and hoists by
// record identity, with no text and no allocated name (`lanes/node-records-fills/field-map.md`). A call's record
// (`BuiltPlaceRecord`, with the call's guard and closure arguments) refers to a `BuiltClosure` by a `BuiltClosureID`, its
// index in the record's built closures, and to each fill by the index of the fill's place among its children.

/// What a call passes a builder it fills (`ClosureArgument.built`): the dispatcher the argument calls, every dispatcher that one's enums reach, and
/// the fills their cases reach.
struct BuiltClosure: Sendable {
	/// The key of the dispatcher the argument calls (`DispatcherRecord.key`).
	let rootDispatcherKey: String
	/// Every dispatcher the root dispatcher's enums reach, the root's among them, in the order the call declares them.
	let dispatchers: [DispatcherRecord]
	/// The fills the dispatchers' cases reach, by the index of each fill's place among the call's children.
	let fillChildIndices: [Int]
}

/// A function of a call that switches over one level of the called seam's enums and hands each case to a fill or to the
/// dispatcher of the next level.
struct DispatcherRecord: Sendable {
	/// The level the dispatcher switches over, its enum, what it returns and its cases (`ScopeGenerator.FillDispatcher`), each
	/// case's target named by a request, never by an allocated name.
	let dispatcher: ScopeGenerator.FillDispatcher
	/// What the dispatcher takes, labeled and typed as the fields it passes on (`FillDispatcher.dispatcherParameters`).
	let parameters: [SeamSignature.Hole.Field]
	/// Whether the dispatcher is a `@Sendable` function.
	let isSendable: Bool
	/// The level, as a key the call's other records name it by.
	var key: String {
		dispatcher.key
	}
}

/// The function of a fill: the place it fills, built in its body, and how the function takes and binds the case's values.
/// The fill's place is a built place among the call's children whose record holds this signature.
struct FillSignature: Sendable {
	/// How the fill takes the values of its case (`lanes/node-records-fills/fill-body-record.md`).
	enum Form: Sendable {
		/// One payload struct of `valuesType`, whose members the bound values read; `nil` where the place is not nested by
		/// type, which takes no parameter.
		case caseValues(valuesType: TypeDescription?)
		/// A carrier's level whose fill has no carrier use: one positional parameter per case value, read or not.
		case caseArguments
		/// A carrier's level taken as the carrier's member takes it: the struct of the run the values end, then each value
		/// after it.
		case carrierUse(SeamCarrierValues.Use)
		/// The fill returns the builder the place's wrapper keeps, and takes each field a level function's member hands it,
		/// binding none.
		case wrapperBuilder(parameters: [SeamSignature.Hole.Field])
		/// The fill takes each field of its payload by itself, binding none: an override closure's or a level function
		/// member's call.
		case payloadFields(parameters: [SeamSignature.Hole.Field])
	}

	/// A value of the case the fill binds before its tree.
	struct BoundValue: Sendable {
		/// Its position among the case's values.
		let index: Int
		let field: SeamSignature.Hole.Field
		/// Whether the binding is of a deferred parameter's memo (`Field.bindsMemo`).
		let bindsMemo: Bool
	}

	/// The hole the fill fills.
	let hole: SeamSignature.Hole
	/// The stem the fill's function is named from (`ScopeGenerator.fillFunctionName(of:)`); the allocator names it.
	let functionNameStem: String
	let isSendable: Bool
	let form: Form
	/// The case values the fill binds first, in case-value order (forms `caseValues`, `caseArguments`, `carrierUse`).
	let bound: [BoundValue]
	/// What the fill takes after its case's values (`ScopeGenerator.fillParameterFields`): bound labels the payload does
	/// not carry, each in the form the root dispatcher hands, then the inner scope parameters.
	let parameters: [SeamSignature.Hole.Field]
	/// Each label the fill's tree reads and each name it declares, which the parameter that takes the case's values is
	/// named apart from, and which decide whether the fill can be written inline in its dispatcher's case.
	let labelsReadOrDeclared: Set<String>
	/// Whether the fill returns the value its body binds (a constant), rather than the wrapper's builder.
	let returnsBoundValue: Bool
}
