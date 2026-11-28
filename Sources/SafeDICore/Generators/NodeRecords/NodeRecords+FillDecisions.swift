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

/// What a root's seam call decides of its fills and dispatchers before any is spelled (step 3, row 4 of
/// `lanes/node-records-fills/step3-interface.md`): which are `@Sendable`, which fills a dispatcher's case holds in place of
/// calling the fill's function, which dispatchers capture the caller's declarations, and which the root may declare once
/// for every call. Each is keyed by fill or dispatcher key, never by a name. Made from the fills' facts and the call's
/// dispatchers, as the tree decides them in `ScopeGenerator.statements(of:leadingMemberWhitespace:)`; only for a call no
/// fill encloses, whose fills refer to no fill by name, as every call a root makes is.
struct FillEmissionDecisions: Sendable, Equatable {
	/// The fills and dispatchers whose function is `@Sendable`.
	let sendableKeys: Set<String>
	/// The fills a dispatcher's case holds in place of calling the fill's function.
	let inlinedFillKeys: Set<String>
	/// The dispatchers the root may declare once for every call: those that capture nothing of the call.
	let rootFunctionDispatcherKeys: Set<String>
	/// The dispatchers that hand a target a declaration of the caller's scope, which the root function's text would not.
	let capturingDispatcherKeys: Set<String>

	/// What the decisions read of one fill of the call.
	struct Fill: Sendable {
		/// The fill's key (`Scope.Fill.key`).
		let key: String
		/// The hole the fill fills.
		let hole: SeamSignature.Hole
		/// How a member of the seam's carrier takes the case's values, where it does (`SeamCarrierValues.Use`).
		let carrierUse: SeamCarrierValues.Use?
		/// Whether the fill takes each field of its payload by itself: one that returns its wrapper's builder.
		let takesPayloadFields: Bool
		/// Each label the fill's tree reads and each name it declares, which its scope parameter is named apart from
		/// (`FillSignature.labelsReadOrDeclared`).
		let labelsReadOrDeclared: Set<String>
		/// The labels of the case values the fill binds before its tree.
		let boundLabels: Set<String>
		/// What the fill takes after its case's values (`FillSignature.parameters`).
		let parameters: [SeamSignature.Hole.Field]
		/// The structs of levels the fill takes on a carried route (`FillCallerReads.innerScopeParameters`).
		let innerScopeParameters: [SeamSignature.Hole.Field]
		/// Whether the fill's body declares a function: the builder function of the property it fills.
		let declaresFunction: Bool
		/// The labels the fill's tree reads from outside the fill.
		let readLabels: Set<String>
	}

	/// The decisions of a call whose fills are `fills`, whose dispatchers are `dispatchers` (each with what it takes,
	/// `DispatcherRecord.parameters`; its `isSendable` is not read), and whose root dispatcher hands its targets
	/// `callerArguments` and `callerMemoArguments` of the caller's scope (`FilledCallFields`).
	static func of(
		fills: [Fill],
		dispatchers: [DispatcherRecord],
		callerArguments: [Property: ArgumentSource],
		callerMemoArguments: [Property: ArgumentSource],
	) -> FillEmissionDecisions {
		// The fills and dispatchers that are `@Sendable`: each a `@Sendable`-family argument of the call reaches – a fill of a
		// `@Sendable` builder, a dispatcher of a `@Sendable` family – and each such a dispatcher's case leads to. No fill of a
		// root's call refers to another by name, so nothing else decides one `@Sendable`. A call built inside a `@Sendable`
		// function marks the functions it spells there (`FilledCallRecords`), as the tree marks a root function a
		// `@Sendable` function reaches, which decides nothing: a fill held in place stays a closure of its dispatcher.
		let sendableKeys = Set(fills.filter(\.hole.isSendable).map(\.key)).union(keysReached(from: dispatchers.filter(\.dispatcher.isSendableFamily), among: dispatchers))
		var parametersByKey = [String: [SeamSignature.Hole.Field]]()
		for fill in fills {
			parametersByKey[fill.key] = fill.parameters
		}
		for dispatcher in dispatchers {
			parametersByKey[dispatcher.key] = parametersByKey[dispatcher.key] ?? dispatcher.parameters
		}
		let inlinedFills = inlinedFills(of: fills, dispatchers: dispatchers, sendableKeys: sendableKeys)
		// A fill held in place that reads a value neither its case nor its parameters hand it reads the caller's
		// declaration, which the dispatcher holding it captures.
		let inlinedFillKeysCapturingNothing = Set(inlinedFills.filter { fill in
			fill.readLabels.isSubset(of: fill.boundLabels.union(fill.parameters.map(\.property.label)))
		}.map(\.key))
		let inlinedFillKeys = Set(inlinedFills.map(\.key))
		let fillsTakingPayloadFields = Set(fills.filter(\.takesPayloadFields).map(\.key))
		let capturingKeys = callerArguments.isEmpty && callerMemoArguments.isEmpty ? [] : Set(dispatchers.filter { dispatcher in
			handsCallersDeclaration(
				dispatcher,
				parametersByKey: parametersByKey,
				inlinedFillKeys: inlinedFillKeys,
				fillsTakingPayloadFields: fillsTakingPayloadFields,
				callerArguments: callerArguments,
				callerMemoArguments: callerMemoArguments,
			)
		}.map(\.key))
		return FillEmissionDecisions(
			sendableKeys: sendableKeys,
			inlinedFillKeys: inlinedFillKeys,
			rootFunctionDispatcherKeys: rootFunctionDispatcherKeys(of: dispatchers, inlinedFillKeys: inlinedFillKeysCapturingNothing, capturingKeys: capturingKeys),
			capturingDispatcherKeys: capturingKeys,
		)
	}

	/// The keys of `starts` and of each fill or dispatcher their cases lead to, among `dispatchers`.
	static func keysReached(from starts: [DispatcherRecord], among dispatchers: [DispatcherRecord]) -> Set<String> {
		var keys = Set<String>()
		var dispatchersToVisit = starts
		let dispatcherByKey = Dictionary(dispatchers.map { ($0.key, $0) }) { first, _ in first }
		keys.formUnion(dispatchersToVisit.map(\.key))
		while let dispatcher = dispatchersToVisit.popLast() {
			for target in dispatcher.dispatcher.cases.compactMap(\.target) where keys.insert(target.key).inserted {
				if let targetDispatcher = dispatcherByKey[target.key] {
					dispatchersToVisit.append(targetDispatcher)
				}
			}
		}
		return keys
	}

	/// The fills a dispatcher's case holds in place of calling the fill's function, in the order of `fills`: each one case
	/// of one dispatcher calls, where the dispatcher takes no `passUp`, the fill takes no struct of a carried level, the fill
	/// and its dispatcher are alike `@Sendable` or not, the fill's function takes the case's values under the name the case
	/// binds them, and a builder struct's member, inside which no function is declared, holds no body that declares one.
	private static func inlinedFills(of fills: [Fill], dispatchers: [DispatcherRecord], sendableKeys: Set<String>) -> [Fill] {
		var caseCountByTargetKey = [String: Int]()
		var dispatcherByTargetKey = [String: ScopeGenerator.FillDispatcher]()
		for dispatcher in dispatchers {
			for target in dispatcher.dispatcher.cases.compactMap(\.target) {
				caseCountByTargetKey[target.key, default: 0] += 1
				dispatcherByTargetKey[target.key] = dispatcher.dispatcher
			}
		}
		return fills.filter { fill in
			guard caseCountByTargetKey[fill.key] == 1, let dispatcher = dispatcherByTargetKey[fill.key] else { return false }
			return !dispatcher.takesPassUp
				&& (dispatcher.carriedInnerScopes.isEmpty || fill.innerScopeParameters.isEmpty)
				&& sendableKeys.contains(fill.key) == sendableKeys.contains(dispatcher.key)
				&& takesCaseValuesUnderTheCasesName(fill)
				&& !(fill.declaresFunction && dispatcher.returnsBuilderStruct)
		}
	}

	/// Whether `fill`'s function takes its case's values under the name a dispatcher's case binds them, `scope`, so that the
	/// case can hold its body: a fill handed no payload does; one whose scope parameter is named apart from what its tree
	/// reads, or that takes its payload's fields by themselves, does not, unless the seam's carrier hands it no value.
	private static func takesCaseValuesUnderTheCasesName(_ fill: Fill) -> Bool {
		guard let valuesType = fill.hole.valuesType(qualifiedBy: nil) else { return true }
		var scopeParameterName = "scope"
		while fill.labelsReadOrDeclared.contains(scopeParameterName) {
			scopeParameterName += "_"
		}
		guard case let .nested(_, enumType, _) = valuesType, ReservedName.seamCarrier(ofEnum: enumType) != nil else {
			// A payload struct, taken as `_ scope: ` by a fill that binds its fields.
			return !fill.takesPayloadFields && scopeParameterName == "scope"
		}
		// A carrier's values, each taken under a name made of the payload's.
		let caseValues = fill.hole.enumPlace?.values ?? fill.hole.fields
		func firstParameterName(inPayloadNamed payloadName: String) -> String? {
			(fill.carrierUse?.parameterNames(of: caseValues, inPayloadNamed: payloadName) ?? caseValues.map { SeamHoles.argumentName(of: $0, inPayloadNamed: payloadName) }).first
		}
		guard let expectedName = firstParameterName(inPayloadNamed: "scope") else { return true }
		return !fill.takesPayloadFields && firstParameterName(inPayloadNamed: scopeParameterName) == expectedName
	}

	/// Whether `dispatcher`'s declaration hands a target a declaration of the caller's scope (`callerArguments`, or a memo of
	/// `callerMemoArguments`), where the declaration written without them hands the value's label: the root dispatcher's,
	/// which takes no value of its own, as `FillDispatcher.declaration` decides each argument it hands a target that is no
	/// fill held in place.
	private static func handsCallersDeclaration(
		_ record: DispatcherRecord,
		parametersByKey: [String: [SeamSignature.Hole.Field]],
		inlinedFillKeys: Set<String>,
		fillsTakingPayloadFields: Set<String>,
		callerArguments: [Property: ArgumentSource],
		callerMemoArguments: [Property: ArgumentSource],
	) -> Bool {
		let dispatcher = record.dispatcher
		// A level that takes the values of outer types hands its own parameters, under their names.
		func handsCallersDeclaration(of parameter: SeamSignature.Hole.Field) -> Bool {
			guard !dispatcher.takesValuesOfOuterTypes, let argument = callerArguments[parameter.property] else { return false }
			return argument.spelled != parameter.property.label
		}
		let carriedNames = Set(dispatcher.carriedInnerScopes.map(\.name))
		for dispatcherCase in dispatcher.cases {
			guard let target = dispatcherCase.target, !inlinedFillKeys.contains(target.key) else { continue }
			let isFill = !target.key.hasPrefix("dispatcher ")
			let readsOwnPayload = fillsTakingPayloadFields.contains(target.key) || !isFill
			for parameter in parametersByKey[target.key] ?? [] {
				let label = parameter.property.label
				if carriedNames.contains(label) {
					continue
				} else if readsOwnPayload, dispatcherCase.carriedLabels.contains(label), dispatcherCase.handsOn(parameter), dispatcherCase.values?.contains(where: { $0.property.label == label }) == true {
					// The case's own payload hands it. No call re-enters a root's call, so no label is hidden from it.
					continue
				} else if let ownParameter = ScopeGenerator.FillDispatcher.parameter(handing: parameter, among: record.parameters) {
					if handsCallersDeclaration(of: ownParameter) {
						return true
					}
				} else if parameter.bindsMemo, parameter.deferral == .deferred(isSendable: true), callerMemoArguments[parameter.memoProperty] != nil {
					return true
				} else if handsCallersDeclaration(of: parameter) {
					return true
				}
			}
		}
		return false
	}

	/// The dispatchers that capture nothing of the call, so the root may declare them once for every call: each that takes
	/// no `passUp`, carries no level's struct, and hands no target the caller's declaration, and whose every case leads to a
	/// fill held in place that reads nothing of the caller, or to such a dispatcher. Found as a fixed point, since a
	/// dispatcher's cases lead to others.
	private static func rootFunctionDispatcherKeys(of dispatchers: [DispatcherRecord], inlinedFillKeys: Set<String>, capturingKeys: Set<String>) -> Set<String> {
		var keys = Set(dispatchers.filter { !$0.dispatcher.takesPassUp && $0.dispatcher.carriedInnerScopes.isEmpty && !capturingKeys.contains($0.key) }.map(\.key))
		var changed = true
		while changed {
			changed = false
			for dispatcher in dispatchers where keys.contains(dispatcher.key) {
				let capturesNothing = dispatcher.dispatcher.cases.allSatisfy { dispatcherCase in
					guard let target = dispatcherCase.target else { return false }
					return target.reusedCarriedInnerScopes.isEmpty && (inlinedFillKeys.contains(target.key) || keys.contains(target.key))
				}
				if !capturesNothing {
					keys.remove(dispatcher.key)
					changed = true
				}
			}
		}
		return keys
	}
}

/// A seam call's decisions as the tree made them, beside the decisions made from the same call's fills and dispatchers
/// (`FillEmissionDecisions`), each described as text.
public struct FillEmissionDecisionsObservation: Sendable {
	public let tree: String
	public let fromRecords: String

	/// Called with each call a root's decisions are made for, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: (@Sendable (FillEmissionDecisionsObservation) -> Void)?
}

extension FillEmissionDecisions: CustomStringConvertible {
	var description: String {
		[
			("sendable", sendableKeys),
			("inlined", inlinedFillKeys),
			("root functions", rootFunctionDispatcherKeys),
			("capturing", capturingDispatcherKeys),
		].map { "\($0): \($1.sorted().joined(separator: ", "))" }.joined(separator: "\n")
	}
}
