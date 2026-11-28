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
	/// The claim of `declaration` as `builtByInitializer` where it fills a place of the seam its parent calls, once a test
	/// turns on records of filled calls (`NodeRecordsObservation.recordsFilledCalls`): its place is the body of its fill's
	/// function, which the call's record declares (`filledSeamCallRecord`), built as its type's initializer builds it.
	static func fillClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard NodeRecordsObservation.recordsFilledCalls, world.construction(of: declaration) == .fill else { return nil }
		return NodeRecordClaim(kind: .builtByInitializer, discharges: wrapperRefusalsDischarged(of: declaration, in: world).union([.construction]))
	}

	/// The record of `declaration`'s place where its call fills places of the seam it calls (`FilledCallRecords`): a call the
	/// engine spells where its place is written (`InPlaceCall`), as `seamCallRecord` makes one, whose function holds after
	/// its guard line the call's children, each fill's function or, where a dispatcher's case holds it, nothing, and then the
	/// call's dispatchers, each one that captures nothing of the call a root function the root declares once
	/// (`RootFunctionHoisting`), and whose construction passes each builder it fills the call of its root dispatcher. A fill's
	/// body is its place laid out by the engine with what the fill binds and takes declared around it.
	/// - Parameters:
	///   - isInSeamTree: Whether the world is a seam's own tree, whose fills a seam's own tree would reach otherwise: the claim
	///     accepts a filled call only where its records assemble (`filledSeamCallClaim(of:in:)`), as a root's call.
	///   - childPlaces: The declaration and place of each of the node's children, in the order its body builds them.
	///   - typesDeclaredEscapingOf: The types a node's tree declares `@escaping`, as the tree's generator of the node unions
	///     them over its children.
	/// - Throws: `NodeRecordRefusal.fill` in a seam's own tree, and `NodeRecordRefusal.notLaidOut` where the engine cannot
	///   lay a fill's body out.
	static func filledSeamCallRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		isInSeamTree: Bool,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		typesDeclaredEscaping: Set<TypeDescription>,
		childPlaces: [(declaration: DeclarationID, place: GeneratedCode)],
		typesDeclaredEscapingOf: (DeclarationID) -> Set<TypeDescription>,
	) throws -> AliasPlaceRecord {
		guard !isInSeamTree, case let .success(records) = world.filledCallRecords(of: declaration) else { throw NodeRecordRefusal.fill }
		let scope = world.scope(of: declaration)
		let construction = try builtByInitializerRecord(of: declaration, variant: variant, in: world, lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties, alwaysDeclaresFunction: true, typesDeclaredEscaping: typesDeclaredEscaping, children: [])
		let indent = ScopeGenerator.standardIndent
		// The names a fill's body sees where the call declares it, which a function laid out inside it is named apart from:
		// the call's function, its other children and their functions, its dispatchers and its fills.
		let fillDeclarations = Set(records.fills.map(\.facts.declaration))
		let childLabels = childPlaces.filter { !fillDeclarations.contains($0.declaration) }.compactMap { world.property(of: $0.declaration)?.label }
		let namesInScope = Set([construction.functionName] + childLabels + childLabels.map(ScopeGenerator.functionName(toBuildPropertyNamed:)) + records.dispatcherNames.values + records.fills.map(\.functionName))
		// A fill node reached on several routes is the place of one fill per case that reaches it, in the call's order.
		let fillsByDeclaration = Dictionary(grouping: records.fills, by: \.facts.declaration)
		var statements = [GeneratedCode]()
		var inlinedFills = [String: ScopeGenerator.FillDispatcher.InlinedFill]()
		for child in childPlaces {
			if let fills = fillsByDeclaration[child.declaration] {
				for fill in fills {
					let typesEscaping = typesDeclaredEscapingOf(fill.facts.declaration)
					if records.decisions.inlinedFillKeys.contains(fill.facts.key),
					   let inlinedFill = try ScopeGenerator.FillDispatcher.InlinedFill(hole: fill.facts.hole, carrierUse: fill.facts.carrierUse, builtProperty: world.property(of: fill.facts.declaration), code: records.functionLines(of: fill, place: child.place, typesDeclaredEscaping: typesEscaping, namesInScope: namesInScope).map { indent + $0 }.joined(separator: "\n"), leadingMemberWhitespace: indent)
					{
						inlinedFills[fill.facts.key] = inlinedFill
					} else {
						try statements.append(.indented(records.functionCode(of: fill, place: child.place, typesDeclaredEscaping: typesEscaping, namesInScope: namesInScope), by: indent))
					}
				}
			} else {
				statements.append(.indented(child.place, by: indent))
			}
		}
		// A dispatcher the root declares once is left out where the call is spelled, and found there by the root
		// (`RootFunctionHoisting`), which keeps the path key's body where it cannot declare one once.
		let dispatcherDeclarations = records.dispatcherDeclarations(inlinedFills: inlinedFills, indent: indent, typesDeclaredEscaping: typesDeclaredEscaping)
		let rootFunctionNames = Set(RootFunctionHoisting.records(in: dispatcherDeclarations).map(\.name))
		statements.append(rootFunctionNames.isEmpty ? .lines(dispatcherDeclarations) : .omittingRootFunctions(.lines(dispatcherDeclarations), named: rootFunctionNames))
		// The construction hands each builder it fills the call of its root dispatcher, which reads nothing but what the
		// dispatcher's declaration reads.
		var arguments = construction.arguments
		var argumentValues = [Int: ValuePath]()
		for (argument, closure) in zip(records.closureArguments, records.builtClosures) {
			argumentValues[arguments.count] = .spliced([.text(closure.spelled(dispatcherName: records.dispatcherNames[closure.rootDispatcherKey] ?? "", structNames: []))])
			arguments.append(PlaceRead(argumentLabel: argument.label, label: argument.label, property: Property(label: argument.label, typeDescription: .void(.tuple)), source: .spelledArgument(argument.label), staysOutsideSendableFunctions: true))
		}
		var record = BuiltPlaceRecord(
			property: construction.property,
			isErased: construction.isErased,
			concreteType: construction.concreteType,
			isExtension: construction.isExtension,
			target: .initializer(construction.concreteType),
			arguments: arguments,
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: construction.functionName,
			isSendable: construction.isSendable,
			typesDeclaredEscaping: typesDeclaredEscaping,
			lineEnd: "",
			hasFunction: true,
			children: [],
			node: PlanNode(),
		)
		record.argumentValues = argumentValues
		record.callFields = CallFields(leadingStatement: scope.seamCall?.callGuard(for: construction.concreteType), closureArguments: records.closureArguments, builtClosures: records.builtClosures)
		// What the root dispatcher hands of the caller's scope, which the call's function captures.
		let reads = construction.arguments + records.callerReads
		var alias = AliasPlaceRecord(property: construction.property, fulfillingProperty: nil, text: "", reads: reads)
		alias.declaredFunctionNames = [construction.functionName]
		alias.call = InPlaceCall(record: record, statementsBeforeLeadingStatement: [], statementsAfterLeadingStatement: statements)
		return alias
	}
}

extension FilledCallRecords.Fill {
	/// The declarations around the fill's body: what the fill binds of its case and takes as a function's parameters, and
	/// what it reads of the caller's scope and takes no parameter of, which it captures as the caller declares it.
	var outerDeclarations: [Property] {
		let taken = signature.bound.map(\.field.property) + signature.fieldsTakenUnbound.map(\.property) + signature.parameters.map(\.property)
		let takenLabels = Set(taken.map(\.label))
		let captured = callerDeclarations.filter { !takenLabels.contains($0.label) }
		let capturedLabels = Set(captured.map(\.label))
		return captured + facts.parametersTakenOfCallerReads.filter { !takenLabels.contains($0.label) && !capturedLabels.contains($0.label) } + taken
	}
}

extension FilledCallRecords {
	/// The function of `fill`, whose place is `place`, as the tree writes it with no indentation: its lines up to its tree,
	/// its place laid out with what it binds, takes and captures declared around it, the return of a constant's value, and
	/// its close.
	/// - Parameter namesInScope: The names visible where the call declares the fill, beside what the fill binds and takes.
	/// - Throws: `NodeRecordRefusal.notLaidOut` where the engine cannot lay the place out.
	func functionCode(of fill: Fill, place: GeneratedCode, typesDeclaredEscaping: Set<TypeDescription>, namesInScope: Set<String>) throws(NodeRecordRefusal) -> GeneratedCode {
		let (outerDeclarations, names) = bodyDeclarations(of: fill, namesInScope: namesInScope)
		guard let body = TypeKeyBody.statements(ofBodyHolding: place, outerDeclarations: outerDeclarations, namesInScope: names) else { throw .notLaidOut }
		let indent = ScopeGenerator.standardIndent
		var lines = [GeneratedCode]()
		for line in fill.signature.spelledSignature(functionName: fill.functionName, scopeParameterName: fill.scopeParameterName, indent: indent, typesDeclaredEscaping: typesDeclaredEscaping) {
			lines.append(.text(line))
		}
		lines.append(.indented(.lines(body), by: indent))
		if fill.signature.returnsBoundValue {
			lines.append(.text(indent + "return \(fill.facts.hole.property.label)"))
		}
		lines.append(.text("}"))
		return .lines(lines)
	}

	/// `functionCode(of:place:typesDeclaredEscaping:namesInScope:)`'s lines, for a fill a dispatcher's case holds, whose
	/// body it takes as lines (`TypeKeyBody.lines(ofBodyHolding:outerDeclarations:namesInScope:)`, a bridge).
	func functionLines(of fill: Fill, place: GeneratedCode, typesDeclaredEscaping: Set<TypeDescription>, namesInScope: Set<String>) throws(NodeRecordRefusal) -> [String] {
		let (outerDeclarations, names) = bodyDeclarations(of: fill, namesInScope: namesInScope)
		guard let body = TypeKeyBody.lines(ofBodyHolding: place, outerDeclarations: outerDeclarations, namesInScope: names) else { throw .notLaidOut }
		let indent = ScopeGenerator.standardIndent
		var lines = fill.signature.spelledSignature(functionName: fill.functionName, scopeParameterName: fill.scopeParameterName, indent: indent, typesDeclaredEscaping: typesDeclaredEscaping)
		lines += body.map { indent + $0 }
		if fill.signature.returnsBoundValue {
			lines.append(indent + "return \(fill.facts.hole.property.label)")
		}
		lines.append("}")
		return lines
	}

	/// What a fill's body is laid out with: the declarations around it (`Fill.outerDeclarations`), and the names in scope
	/// where it is declared.
	private func bodyDeclarations(of fill: Fill, namesInScope: Set<String>) -> (outerDeclarations: [Property], namesInScope: Set<String>) {
		let outerDeclarations = fill.outerDeclarations
		return (outerDeclarations, namesInScope.union(outerDeclarations.map(\.label) + [fill.scopeParameterName]))
	}

	/// The declarations of the call's dispatchers, in the order the call declares them, each indented by `indent`: a root
	/// function the root declares once where it captures nothing of the call, and otherwise text in the call's body.
	/// - Parameter inlinedFills: The fills a dispatcher's case holds, by key.
	func dispatcherDeclarations(inlinedFills: [String: ScopeGenerator.FillDispatcher.InlinedFill], indent: String, typesDeclaredEscaping: Set<TypeDescription>) -> [GeneratedCode] {
		var fillParametersByKey = [String: [SeamSignature.Hole.Field]]()
		for fill in fills {
			fillParametersByKey[fill.facts.key] = fill.facts.memberParameters
		}
		let fillsTakingPayloadFields = Set(fills.filter(\.facts.takesPayloadFields).map(\.facts.key))
		return dispatchers.map { dispatcher in
			let asRootFunction = decisions.rootFunctionDispatcherKeys.contains(dispatcher.key)
			let text = fields.declaration(
				of: dispatcher,
				among: dispatchers,
				asRootFunction: asRootFunction,
				indent: indent,
				inlinedFills: inlinedFills,
				fillParametersByKey: fillParametersByKey,
				typesDeclaredEscaping: typesDeclaredEscaping,
				fillsTakingPayloadFields: fillsTakingPayloadFields,
			)
			guard asRootFunction else { return .text(text) }
			let targetKeys = dispatcher.dispatcher.cases.compactMap(\.target?.key)
			return .rootFunction(RootFunctionRecord(
				key: RootFunctionKey(
					calledSeam: dispatcher.dispatcher.seamType,
					level: dispatcher.key,
					isSendable: dispatcher.isSendable,
					inlinedFillKeys: Set(targetKeys.filter { inlinedFills[$0] != nil }),
					fillsTakingPayloadFields: fillsTakingPayloadFields.intersection(targetKeys),
					typesDeclaredEscaping: typesDeclaredEscaping,
					labelsHiddenByReenteringCalls: [],
					indentation: indent,
				),
				name: dispatcherNames[dispatcher.key] ?? "",
				// The declaration after its indentation and the attributes it is spelled with (`RootFunctionRecord.spelled`).
				textWithoutAttributes: String(text.dropFirst(indent.count + LocalFunctionInlining.attribute.count)),
				isSendable: dispatcher.isSendable,
				calls: dispatcher.dispatcher.cases.compactMap { dispatcherCase in
					dispatcherCase.target.flatMap { inlinedFills[$0.key] == nil ? $0.name : nil }
				},
			))
		}
	}

	/// What the root dispatcher hands of the caller's scope: a read of each declaration the caller's arguments name.
	var callerReads: [PlaceRead] {
		[]
	}
}
