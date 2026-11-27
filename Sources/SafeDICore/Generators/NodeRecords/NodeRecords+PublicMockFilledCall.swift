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

extension LevelFunctionRecordsObservation {
	/// Hands the observer, where one is set, the level functions node records make of each call of another module's public
	/// mock in `world`, a mock root's, that fills a place and that no fill encloses
	/// (`levelFunctionRecords(of:variant:in:mockRootHoles:)`).
	/// - Parameter mockRootHoles: The mock root's holes, where it is a public mock whose tree holds places
	///   (`FillInnerScopes.ofPublicMockCall(_:in:mockRootHoles:)`).
	static func observe(root: String, world: TypeFactsGraph, mockRootHoles: SeamHoles?) {
		guard let observer else { return }
		for declaration in 0..<Int32(world.declarationCount) where world.construction(of: declaration) == .publicMockCall {
			let fills = world.scope(of: declaration).holeArguments.contains { argument in
				switch argument {
				case .fill: true
				case .passUp: false
				}
			}
			if fills, let variant = (0..<Int32(world.variantCount)).first(where: { world.declaration(of: $0) == declaration }) {
				do {
					try observer(LevelFunctionRecordsObservation(root: root, records: levelFunctionRecords(of: declaration, variant: variant, in: world, mockRootHoles: mockRootHoles)))
				} catch {
					// A call node records leave to the tree has no records to compare.
				}
			}
		}
	}

	/// The level functions of `call`, a call of another module's public mock in `world` that fills a place, reached as
	/// `variant`, as the tree records them (`PublicMockLevelFunctions.records`), made from the world alone.
	/// - Throws: The refusal of a call whose fills' facts node records leave to the tree, or that a fill encloses.
	static func levelFunctionRecords(of call: DeclarationID, variant: VariantID, in world: TypeFactsGraph, mockRootHoles: SeamHoles?) throws(NodeRecordRefusal) -> LevelFunctionRecords {
		// A call inside a fill refers to the call's fills and level functions by name, which makes them `@Sendable` or keeps
		// them out of their cases (`ScopeGenerator`'s `fillReferences`); node records leave such a call to the tree.
		guard !FillFacts.fillsHoldCall(call, in: world) else { throw .fillHoldsCall }
		let innerScopes = try FillInnerScopes.ofPublicMockCall(call, in: world, mockRootHoles: mockRootHoles)
		let allFacts: [FillFacts]
		switch FillFacts.of(call: call, in: world, levelsOfCallingTree: innerScopes.levelsOfCallingTree) {
		case let .facts(facts):
			allFacts = facts
		case let .refused(refusal):
			throw refusal
		}
		// What the root level functions read of the caller's scope, by label: the form no fill reads optionally first, then
		// in `Property` order, as `ScopeGenerator.publicMockLevelFunctions` chooses it.
		var callerReadFormsByLabel = [String: [Property: (field: SeamSignature.Hole.Field, argument: String)]]()
		var callerArguments = [Property: ArgumentSource]()
		for facts in allFacts {
			let sources = FillCallerSources.of(facts: facts, call: call, variant: variant, in: world)
			for (read, (parameter, source)) in zip(facts.callerReads, zip(facts.parametersTakenOfCallerReads, sources)) {
				callerArguments[parameter] = callerArguments[parameter] ?? source
				if let field = facts.parametersTaken.first(where: { $0.property == parameter }) {
					callerReadFormsByLabel[read.label, default: [:]].merge([parameter: (field, source.spelled)]) { form, _ in form }
				}
			}
		}
		var callerReads = [String: (field: SeamSignature.Hole.Field, argument: String)]()
		for (label, forms) in callerReadFormsByLabel {
			let properties = forms.keys.sorted()
			if let property = properties.first(where: { !$0.typeDescription.isOptional }) ?? properties.first {
				callerReads[label] = forms[property]
			}
		}
		let fillParameters = allFacts.map { (fillKey: $0.key, parameters: $0.memberParameters) }
		let unnamedLevels = FillDispatchers.of(call: call, in: world, fillParameters: fillParameters, innerScopes: innerScopes)
		let names = FillNames(
			reserving: [String](),
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
					innerScopeParameters: facts.innerScopeParameters,
					declaresFunction: facts.declaresFunction,
					readLabels: Set(facts.readLabels),
				)
			},
			dispatchers: levels.dispatchers,
			callerArguments: callerArguments,
			callerMemoArguments: [:],
		)
		var fillParametersByKey = [String: [SeamSignature.Hole.Field]]()
		for facts in allFacts {
			fillParametersByKey[facts.key] = facts.memberParameters
		}
		let levelFunctions = PublicMockLevelFunctions(
			dispatchers: levels.dispatchers.map(\.dispatcher),
			fillParametersByKey: fillParametersByKey,
			roots: levels.builtClosures.map { PublicMockLevelFunctions.Root(label: $0.label, dispatcherKey: $0.rootDispatcherKey, carriedStructs: $0.carriedStructNames) },
			reservedNames: Set(names.fills.map(\.functionName)),
			callerReads: callerReads,
			enclosingLevelCalls: [:],
		)
		// The fills an override closure of the call is handed a function over take each field of their payload by themselves.
		let overrideFillKeys = overrideFillKeys(of: call, facts: allFacts, levels: levels, levelFunctions: levelFunctions, in: world)
		var memberParameterFieldsByKey = fillParametersByKey
		for facts in allFacts where overrideFillKeys.contains(facts.key) && !facts.takesPayloadFields {
			memberParameterFieldsByKey[facts.key] = facts.payloadFields + facts.parametersTaken
		}
		// A level function holds the body of a fill it hands each value in the form the fill takes it, under its own label,
		// that declares no function (`FillInlining`).
		let calledWithOwnValues = levelFunctions.keysOfFillsCalledWithOwnValues
		var carriesPayloadByTargetKey = [String: Bool]()
		for dispatcher in levels.dispatchers {
			for dispatcherCase in dispatcher.dispatcher.cases {
				if let target = dispatcherCase.target {
					carriesPayloadByTargetKey[target.key] = dispatcherCase.carriesPayload
				}
			}
		}
		var inlinedFillsBindingScope = [String: Bool]()
		for facts in allFacts where decisions.inlinedFillKeys.contains(facts.key) && calledWithOwnValues.contains(facts.key) && !overrideFillKeys.contains(facts.key) && !facts.declaresFunction {
			// The fill binds from its scope each field its tree reads that it is not handed as a parameter of its own.
			inlinedFillsBindingScope[facts.key] = (carriesPayloadByTargetKey[facts.key] ?? false) && !Set(facts.bound).subtracting(facts.parametersTaken.map(\.property.label)).isEmpty
		}
		return levelFunctions.records(
			sendableKeys: decisions.sendableKeys,
			inlinedFillsBindingScope: inlinedFillsBindingScope,
			fillsTakingPayloadFields: Set(allFacts.filter(\.takesPayloadFields).map(\.key)).union(overrideFillKeys),
			fillMemberParameterFieldsByKey: memberParameterFieldsByKey,
			typesDeclaredEscaping: typesDeclaredEscaping(beneath: call, in: world),
		)
	}

	/// The fills an override closure of `call` is handed a function over, as `ScopeGenerator.publicMockOverrideBuilders`
	/// decides them: none where the called mock takes overrides, or where some builder the call fills is not filled by one
	/// fill that takes only its payload, of a place that forwards nothing or returns its wrapper's builder, whose payload's
	/// fields the called mock's hand-written mock takes by label and type.
	private static func overrideFillKeys(of call: DeclarationID, facts allFacts: [FillFacts], levels: FillDispatchers, levelFunctions: PublicMockLevelFunctions, in world: TypeFactsGraph) -> Set<String> {
		let scope = world.scope(of: call)
		guard let publicMockCall = scope.publicMockCall, !publicMockCall.takesOverrides else { return [] }
		let builderLabels = Set(levels.builtClosures.map(\.label))
		var parameterTypesByLabel = [String: TypeDescription]()
		for argument in scope.instantiable.mockInitializer?.arguments ?? [] where !builderLabels.contains(argument.innerLabel) && parameterTypesByLabel[argument.innerLabel] == nil {
			parameterTypesByLabel[argument.innerLabel] = argument.typeDescription
		}
		var keys = Set<String>()
		for closure in levels.builtClosures {
			let members = levelFunctions.rootMembers(ofDispatcherKeyed: closure.rootDispatcherKey) ?? []
			let fillTargets = members.compactMap(\.fillTakingOnlyItsPayload)
			guard fillTargets.count == members.count, Set(fillTargets.map(\.key)).count == 1, let target = fillTargets.first,
			      let facts = allFacts.first(where: { $0.key == target.key }),
			      facts.hole.forwardedType == nil || facts.takesPayloadFields,
			      (facts.payloadFields + facts.parametersTaken).allSatisfy({ parameterTypesByLabel[$0.property.label] == $0.property.typeDescription })
			else { return [] }
			keys.insert(target.key)
		}
		return keys
	}

	/// The types the tree beneath `declaration` declares `@escaping`, as the tree's generator of the node unions them.
	private static func typesDeclaredEscaping(beneath declaration: DeclarationID, in world: TypeFactsGraph) -> Set<TypeDescription> {
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
}
