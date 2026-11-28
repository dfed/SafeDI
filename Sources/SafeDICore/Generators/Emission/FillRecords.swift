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
	/// What the call hands the root dispatcher, in its order: the struct the case of the caller's own enum for the call
	/// returns, for each struct of a level the fills take.
	let carriedStructs: [CarriedStructRead]

	/// A struct a call hands its root dispatcher: under the label the fills take it by, read of the binding the caller's tree
	/// makes of the struct's type for the call's case, never by the name the binding is allocated.
	struct CarriedStructRead: Hashable, Sendable {
		let upName: String
		let structType: TypeDescription
	}

	/// The argument, calling the root dispatcher as `dispatcherName` and handing it each carried struct bound under the name
	/// at its position in `structNames`.
	func spelled(dispatcherName: String, structNames: [String]) -> String {
		"\(dispatcherName)(\(zip(carriedStructs, structNames).map { "\($0.upName.spelledAsArgumentLabel): \($1)" }.joined(separator: ", ")))"
	}
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
/// The fill's place is a built place among the call's children whose record holds this signature. A deliberate gap: the
/// record spells a fill that binds its fields itself, never one that calls a shared body (`sharedFillBodyFunction`), whose
/// fields are its body's arguments, so `FillSignatureObservation` observes only the first; the record learns the shared
/// form before records lay out a fill that calls one.
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
		/// binding none; of those, each struct of the fill's own level, `innerScopeLabels`, as the function the inner seam's
		/// member returns for the place.
		case wrapperBuilder(parameters: [SeamSignature.Hole.Field], innerScopeLabels: Set<String>)
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

	/// The fill's function's first line, named `functionName`, then each line binding a value of its case, indented by
	/// `indent`: what precedes the fill's tree.
	func spelledSignature(functionName: String, indent: String, typesDeclaredEscaping: Set<TypeDescription>) -> [String] {
		// The parameter is named apart from what the tree reads by name, which it would hide.
		var scopeParameterName = "scope"
		while labelsReadOrDeclared.contains(scopeParameterName) {
			scopeParameterName += "_"
		}
		let prefix = ScopeGenerator.localFunctionPrefix(isSendable: isSendable)
		let caseValues = hole.enumPlace?.values ?? hole.fields
		var parameterList: [String]
		var returnType = hole.builtType
		var bindings = [String]()
		switch form {
		case let .wrapperBuilder(parameters, innerScopeLabels):
			parameterList = parameters.map { field in
				let type = if innerScopeLabels.contains(field.property.label) {
					TypeDescription.attributed(
						DependencyTreeGenerator.erasedBuilderType(
							forwarding: hole.forwardedType?.strippingEscaping ?? .void(.tuple),
							returning: field.property.typeDescription,
							isSendable: hole.enumPlace?.isBuiltBySendableBuilder ?? false,
						),
						specifiers: [],
						attributes: ["escaping"],
					)
				} else {
					field.boundTypeAsFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)
				}
				return "\(field.property.label.spelledAsArgumentLabel): \(type.asSource)"
			}
			returnType = .nested(name: Dependency.wrapperBuilderTypeName, parentType: hole.property.typeDescription.unwrapped, generics: [])
		case let .payloadFields(parameters):
			parameterList = parameters.map { "\($0.property.label.spelledAsArgumentLabel): \($0.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
		case let .caseValues(valuesType):
			parameterList = valuesType.map { ["_ \(scopeParameterName): \($0.asSource)"] } ?? []
			bindings = bound.map { "\(indent)let \($0.field.property.label) = \(scopeParameterName).\($0.field.memberName(bindingMemo: $0.bindsMemo))" }
		case .caseArguments:
			parameterList = caseValues.map { "_ \(SeamHoles.argumentName(of: $0, inPayloadNamed: scopeParameterName)): \(($0.memoType ?? $0.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)).asSource)" }
			bindings = bound.map { "\(indent)let \($0.field.property.label) = \(SeamHoles.argumentRead(of: $0.field, inPayloadNamed: scopeParameterName, bindingMemo: $0.bindsMemo))" }
		case let .carrierUse(use):
			parameterList = zip(use.parameterNames(of: caseValues, inPayloadNamed: scopeParameterName), use.parameterTypes(of: caseValues, qualifiedBy: hole.scopeSeamType, typesDeclaredEscaping: typesDeclaredEscaping)).map { "_ \($0): \($1.asSource)" }
			bindings = bound.map { "\(indent)let \($0.field.property.label) = \(use.read(ofFieldAt: $0.index, of: caseValues, inPayloadNamed: scopeParameterName, bindingMemo: $0.bindsMemo))" }
		}
		parameterList += parameters.map { "\($0.property.label.spelledAsArgumentLabel): \($0.boundTypeAsFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
		return ["\(prefix)func \(functionName)(\(parameterList.joined(separator: ", "))) -> \(returnType.asSource) {"] + bindings
	}
}

/// A fill's function as the tree writes it up to its tree, beside the same lines spelled from the fill's record alone.
public struct FillSignatureObservation: Sendable {
	public let written: [String]
	public let spelledFromRecord: [String]

	/// Called with each fill as its function is written, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable (FillSignatureObservation) -> Void>?
}

/// What a call that fills a builder hands its dispatchers of the caller's scope, shared by every builder it fills.
struct FilledCallFields: Sendable {
	/// What the root dispatcher hands each parameter a target takes of a value of the caller's scope, read of the caller's
	/// nearest declaration (`ScopeGenerator.FillCallerReads`).
	let callerArguments: [Property: ArgumentSource]
	/// What the root dispatcher hands each `SendableLazilyInstantiated` memo a target takes.
	let callerMemoArguments: [Property: ArgumentSource]
	/// The deferred labels a fill that re-enters the call cannot read from outside it.
	let labelsHiddenByReenteringCalls: Set<String>

	/// The declaration of `record`, one of the call's `dispatchers`, indented by `indent`: as a root function, which
	/// hands on no caller's declaration and takes its attribute where the root declares it, or in the call's body.
	/// - Parameters:
	///   - inlinedFills: The fills the dispatchers hold the bodies of, by key.
	///   - fillParametersByKey: What each fill takes beside its case's values, by key.
	func declaration(
		of record: DispatcherRecord,
		among dispatchers: [DispatcherRecord],
		asRootFunction: Bool,
		indent: String,
		inlinedFills: [String: ScopeGenerator.FillDispatcher.InlinedFill],
		fillParametersByKey: [String: [SeamSignature.Hole.Field]],
		typesDeclaredEscaping: Set<TypeDescription>,
		fillsTakingPayloadFields: Set<String>,
	) -> String {
		var parametersByKey = fillParametersByKey
		for dispatcher in dispatchers where parametersByKey[dispatcher.key] == nil {
			parametersByKey[dispatcher.key] = dispatcher.parameters
		}
		return record.dispatcher.declarationAndCaptures(
			isSendable: asRootFunction ? false : record.isSendable,
			indent: indent,
			inlinedFills: inlinedFills,
			parametersByKey: parametersByKey,
			callerArgumentByParameter: asRootFunction ? [:] : callerArguments.mapValues(\.spelled),
			callerMemoArgumentByMemo: asRootFunction ? [:] : callerMemoArguments.mapValues(\.spelled),
			typesDeclaredEscaping: typesDeclaredEscaping,
			fillsTakingPayloadFields: fillsTakingPayloadFields,
			labelsHiddenByReenteringCalls: labelsHiddenByReenteringCalls,
		).text
	}
}

/// A dispatcher's declaration as the tree writes it, beside the declaration spelled from the call's records alone.
public struct DispatcherRecordObservation: Sendable {
	public let text: String
	public let spelledFromRecord: String

	/// Called with each dispatcher as its declaration is written, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable (DispatcherRecordObservation) -> Void>?
}
