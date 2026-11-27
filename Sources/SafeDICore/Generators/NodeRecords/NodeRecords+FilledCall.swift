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

/// The records of a root's seam call that fills places of the seam it calls (step 3, row 6 of
/// `lanes/node-records-fills/step3-interface.md`), made from the world alone: each fill's function, the call's dispatchers,
/// what the call passes each builder it fills, what the root dispatcher hands of the caller's scope, and the call's names.
/// Each fill is laid out once per case, whatever the paths that reach it. The engine spells the call in place from these.
struct FilledCallRecords: Sendable {
	/// One fill of the call: its facts, its function's record, and the names the call gives it.
	struct Fill: Sendable {
		let facts: FillFacts
		let signature: FillSignature
		let functionName: String
		let scopeParameterName: String
	}

	/// The call's node.
	let call: DeclarationID
	/// The call's fills that generate code, one per case, in the order of the call's fill arguments.
	let fills: [Fill]
	/// The call's dispatchers, in the order it declares them, each `@Sendable` as the call decides.
	let dispatchers: [DispatcherRecord]
	/// Each dispatcher's function, by key.
	let dispatcherNames: [String: String]
	let decisions: FillEmissionDecisions
	let fields: FilledCallFields
	/// What the call passes each builder it fills, in the order of the called seam's builders.
	let closureArguments: [ClosureArgumentEntry]
	let builtClosures: [BuiltClosure]

	/// The records of `call`, a node of `world` that calls a seam and fills a place of it, whose variant is `variant`.
	/// - Parameter reservedNames: The names enclosing the call, which no function of the call takes: none for a root's call.
	/// - Throws: The refusal of a call node records leave to the tree (`FillFacts.refusal(ofCall:in:routeCount:)`), and of
	///   one whose inner scope levels they do not make.
	static func of(call: DeclarationID, variant: VariantID, in world: TypeFactsGraph, reservedNames: [String]) throws(NodeRecordRefusal) -> FilledCallRecords {
		let allFacts: [FillFacts]
		switch FillFacts.of(call: call, in: world) {
		case let .facts(facts):
			allFacts = facts
		case let .refused(refusal):
			throw refusal
		}
		let innerScopes = try FillInnerScopes.of(call: call, in: world, seamTree: nil)
		// What the root dispatcher hands each parameter of the caller's scope a fill takes: the first fill that reads it bound.
		var callerArguments = [Property: ArgumentSource]()
		let callerSources = FillCallerSources(world: world)
		for facts in allFacts {
			let declarations = callerSources.declarations(facts: facts, call: call, variant: variant)
			let sources = callerSources.of(facts: facts, call: call, variant: variant)
			for (read, (declared, (parameter, source))) in zip(facts.callerReads, zip(declarations, zip(facts.parametersTakenOfCallerReads, sources))) {
				// A form of the label the fill's tree receives only if available that the caller's declaration does not provide is
				// unavailable to it; a label every form of which is unavailable is passed `nil`, unless another fill finds it.
				let isAvailable = source != .nil && receivedForms(ofLabel: read.label, beneath: facts.declaration, in: world).contains { form in
					// An optional declaration stands for the value it may hold, as a forwarded optional does.
					!form.isOnlyIfAvailable || declared.map { CycleParameter.forms(providedBy: $0).union(CycleParameter.forms(providedBy: $0.asUnwrappedProperty)).contains(form.property.asUnwrappedProperty) } ?? false
				}
				if isAvailable {
					callerArguments[parameter] = source
				} else if callerArguments[parameter] == nil {
					callerArguments[parameter] = .nil
				}
			}
		}
		let fillParameters = allFacts.map { (fillKey: $0.key, parameters: $0.memberParameters) }
		// The names are claimed from the dispatchers' stems, which do not depend on names; the dispatchers are then made again
		// naming each other and their fills as the call does.
		let unnamedLevels = FillDispatchers.of(call: call, in: world, fillParameters: fillParameters, innerScopes: innerScopes)
		let names = FillNames(
			reserving: reservedNames,
			fills: allFacts.map { FillNames.Fill(caseKey: ScopeGenerator.fillCaseKey(of: $0.hole), functionNameStem: $0.functionNameStem, labelsReadOrDeclared: $0.labelsReadOrDeclared) },
			dispatchers: unnamedLevels.dispatchers.map { FillNames.Dispatcher(key: $0.key, functionNameStem: $0.dispatcher.functionNameStem) },
		)
		let levels = FillDispatchers.of(call: call, in: world, fillParameters: fillParameters, innerScopes: innerScopes, names: names)
		let decisions = FillEmissionDecisions.of(
			fills: allFacts.map { facts in
				FillEmissionDecisions.Fill(
					key: facts.key,
					hole: facts.hole,
					carrierUse: facts.carrierUse,
					takesPayloadFields: facts.takesPayloadFields,
					labelsReadOrDeclared: Set(facts.labelsReadOrDeclared),
					boundLabels: Set(facts.boundLabels),
					parameters: facts.memberParameters,
					// No fill of an accepted root call reads its inner scopes (`FillFacts.readsInnerScopes`).
					innerScopeParameters: [],
					declaresFunction: facts.declaresFunction,
					readLabels: Set(facts.readLabels),
				)
			},
			dispatchers: levels.dispatchers,
			callerArguments: callerArguments,
			callerMemoArguments: [:],
		)
		var fills = [Fill]()
		var seenCaseKeys = Set<String>()
		for facts in allFacts {
			let caseKey = ScopeGenerator.fillCaseKey(of: facts.hole)
			guard seenCaseKeys.insert(caseKey).inserted,
			      let functionName = names.functionName(ofFill: caseKey),
			      let scopeParameterName = names.scopeParameterName(ofFill: caseKey)
			else { continue }
			fills.append(Fill(facts: facts, signature: signature(of: facts, isSendable: decisions.sendableKeys.contains(facts.key)), functionName: functionName, scopeParameterName: scopeParameterName))
		}
		let dispatchers = levels.dispatchers.map { DispatcherRecord(dispatcher: $0.dispatcher, parameters: $0.parameters, isSendable: decisions.sendableKeys.contains($0.key)) }
		let dispatcherByKey = Dictionary(dispatchers.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
		var closureArguments = [ClosureArgumentEntry]()
		var builtClosures = [BuiltClosure]()
		for closure in levels.builtClosures {
			closureArguments.append(ClosureArgumentEntry(label: closure.label, value: .built(BuiltClosureID(builtClosures.count))))
			builtClosures.append(BuiltClosure(
				rootDispatcherKey: closure.rootDispatcherKey,
				dispatchers: closure.dispatcherKeys.compactMap { dispatcherByKey[$0] },
				fillChildIndices: closure.fillKeys.compactMap { key in fills.firstIndex { $0.facts.key == key } },
				carriedStructs: closure.carriedStructs,
			))
		}
		return FilledCallRecords(
			call: call,
			fills: fills,
			dispatchers: dispatchers,
			dispatcherNames: Dictionary(names.dispatchers.map { ($0.key, $0.functionName) }, uniquingKeysWith: { first, _ in first }),
			decisions: decisions,
			fields: FilledCallFields(callerArguments: callerArguments, callerMemoArguments: [:], labelsHiddenByReenteringCalls: []),
			closureArguments: closureArguments,
			builtClosures: builtClosures,
		)
	}

	/// The forms of `label` the tree beneath `fill` receives from above it, each with whether it is received only if available.
	private static func receivedForms(ofLabel label: String, beneath fill: DeclarationID, in world: TypeFactsGraph) -> [(property: Property, isOnlyIfAvailable: Bool)] {
		var forms = [(property: Property, isOnlyIfAvailable: Bool)]()
		var pending = [fill]
		var visited: Set = [fill]
		while let declaration = pending.popLast() {
			for dependency in world.scope(of: declaration).instantiable.dependencies {
				switch dependency.source {
				case let .received(onlyIfAvailable):
					if dependency.property.label == label {
						forms.append((dependency.property, onlyIfAvailable))
					}
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					if fulfillingProperty.label == label {
						forms.append((fulfillingProperty, onlyIfAvailable))
					}
				case .instantiated, .forwarded:
					break
				}
			}
			for child in world.edges(from: declaration) where visited.insert(child).inserted {
				pending.append(child)
			}
		}
		return forms
	}

	/// The record of the function of the fill `facts` are of: how it takes and binds its case's values, as the tree writes it
	/// (`ScopeGenerator.generateFillCode`).
	private static func signature(of facts: FillFacts, isSendable: Bool) -> FillSignature {
		let hole = facts.hole
		let form: FillSignature.Form
		var bound = [FillSignature.BoundValue]()
		if facts.takesPayloadFields {
			// No fill of a root's call reads its inner scopes (`FillFacts.readsInnerScopes`).
			form = .wrapperBuilder(parameters: facts.memberParameters, innerScopeLabels: [])
		} else {
			let valuesType = hole.valuesType(qualifiedBy: hole.scopeSeamType)
			// A seam's carrier hands the fill the case's values as arguments.
			let takesValuesAsArguments = if case let .nested(_, enumType, _)? = valuesType {
				ReservedName.seamCarrier(ofEnum: enumType) != nil
			} else {
				false
			}
			form = if let carrierUse = facts.carrierUse, takesValuesAsArguments {
				.carrierUse(carrierUse)
			} else if takesValuesAsArguments {
				.caseArguments
			} else {
				.caseValues(valuesType: valuesType)
			}
			if valuesType != nil {
				let boundLabels = Set(facts.bound)
				for (index, field) in (hole.enumPlace?.values ?? hole.fields).enumerated() where boundLabels.contains(field.property.label) {
					bound.append(FillSignature.BoundValue(index: index, field: field, bindsMemo: facts.memoBoundLabels.contains(field.property.label)))
				}
			}
		}
		return FillSignature(
			hole: hole,
			functionNameStem: facts.functionNameStem,
			isSendable: isSendable,
			form: form,
			bound: bound,
			parameters: form.takesCaseValues ? facts.parametersTaken : [],
			labelsReadOrDeclared: Set(facts.labelsReadOrDeclared),
			returnsBoundValue: facts.returnsBoundValue,
		)
	}

	/// Each function of the call node records spell without the fills' bodies, by the name the call gives it, as lines with no
	/// indentation: each fill's function up to its tree, and each dispatcher whose cases hold no fill in place.
	/// - Parameter typesDeclaredEscaping: The types a node's tree declares `@escaping` (`ScopeGenerator.typesDeclaredEscaping`).
	func spelledFunctions(typesDeclaredEscaping: (DeclarationID) -> Set<TypeDescription>) -> [String: [String]] {
		var spelled = [String: [String]]()
		for fill in fills {
			spelled[fill.functionName] = fill.signature.spelledSignature(functionName: fill.functionName, scopeParameterName: fill.scopeParameterName, indent: "", typesDeclaredEscaping: typesDeclaredEscaping(fill.facts.declaration))
		}
		var fillParametersByKey = [String: [SeamSignature.Hole.Field]]()
		for fill in fills {
			fillParametersByKey[fill.facts.key] = fill.facts.memberParameters
		}
		let fillsTakingPayloadFields = Set(fills.filter(\.facts.takesPayloadFields).map(\.facts.key))
		for dispatcher in dispatchers where !dispatcher.dispatcher.cases.contains(where: { $0.target.map { decisions.inlinedFillKeys.contains($0.key) } ?? false }) {
			guard let name = dispatcherNames[dispatcher.key] else { continue }
			spelled[name] = GeneratedCodeText.lines(of: fields.declaration(
				of: dispatcher,
				among: dispatchers,
				asRootFunction: decisions.rootFunctionDispatcherKeys.contains(dispatcher.key),
				indent: "",
				inlinedFills: [:],
				fillParametersByKey: fillParametersByKey,
				typesDeclaredEscaping: typesDeclaredEscaping(call),
				fillsTakingPayloadFields: fillsTakingPayloadFields,
			))
		}
		return spelled
	}
}

extension FillSignature.Form {
	/// Whether a fill of the form takes its case's values, then what it takes after them (`FillSignature.parameters`).
	fileprivate var takesCaseValues: Bool {
		switch self {
		case .caseValues, .caseArguments, .carrierUse:
			true
		case .wrapperBuilder, .payloadFields:
			false
		}
	}
}

/// The functions node records spell of a production root's filled seam calls (`FilledCallRecords`), each as lines with no
/// indentation, beside which a test holds the tree's (`FillSignatureObservation`, `DispatcherRecordObservation`), and what
/// each call passes the builders it fills, beside its text's (`SeamCallRecordObservation.written`).
public struct FilledCallRecordsObservation: Sendable {
	public let root: String
	/// Each function, by the name the call gives it.
	public let functions: [String: [String]]
	/// Each closure argument, as `label: value`.
	public let closureArguments: [String]

	/// Called with each production root's filled calls, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: (@Sendable (FilledCallRecordsObservation) -> Void)?

	/// Hands the observer, where one is set, the records of `world`'s filled calls that node records accept.
	static func observe(root: String, world: TypeFactsGraph) {
		guard let observer else { return }
		var functions = [String: [String]]()
		var closureArguments = [String]()
		// The types a node's tree declares `@escaping`, as the tree's generator of the node unions them over its children.
		func typesDeclaredEscaping(_ declaration: DeclarationID) -> Set<TypeDescription> {
			var escaping = Set<TypeDescription>()
			var pending = [declaration]
			var visited: Set = [declaration]
			while let next = pending.popLast() {
				let scope = world.scope(of: next)
				escaping.formUnion(scope.instantiable.typesDeclaredEscapingByItsDeclaration)
				escaping.formUnion(scope.publicMockCall?.typesDeclaredEscaping ?? [])
				escaping.formUnion(scope.seamCall?.typesDeclaredEscaping ?? [])
				for child in world.edges(from: next) where visited.insert(child).inserted {
					pending.append(child)
				}
			}
			return escaping
		}
		let holdsBuilderLoop = NodeRecords.refusals(in: world, declaredTypeNames: nil).contains(.builderLoop)
		for declaration in 0..<Int32(world.declarationCount) where world.construction(of: declaration) == .seamCall {
			// A call refused for nothing but that its record is not assembled yet.
			guard Set(NodeRecords.kindAndRefusals(of: declaration, in: world).refusals) == [.fill],
			      let variant = (0..<Int32(world.variantCount)).first(where: { world.declaration(of: $0) == declaration })
			else { continue }
			let records: FilledCallRecords
			do {
				records = try FilledCallRecords.of(call: declaration, variant: variant, in: world, reservedNames: [])
			} catch {
				continue
			}
			functions.merge(records.spelledFunctions(typesDeclaredEscaping: typesDeclaredEscaping), uniquingKeysWith: { first, _ in first })
			// The tree writes no record of a call in a world with a loop of builders, whose members' functions rebind what the
			// call reads (`ScopeGenerator.observeFilledCall`).
			for (argument, closure) in zip(records.closureArguments, records.builtClosures) where !holdsBuilderLoop {
				closureArguments.append("\(argument.label): \(closure.spelled(dispatcherName: records.dispatcherNames[closure.rootDispatcherKey] ?? "", structNames: []))")
			}
		}
		observer(FilledCallRecordsObservation(root: root, functions: functions, closureArguments: closureArguments))
	}
}
