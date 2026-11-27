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

/// Why node records leave a root's filled seam call to the tree in step 3 (`lanes/node-records-fills/step3-interface.md`),
/// each its own reason, so a count of refused calls says what is left.
enum FillRefusal: String, Sendable, CaseIterable {
	/// The world is a mock root's.
	case fillMockWorld
	/// The call is of another module's public mock.
	case fillPublicMockCall
	/// A fill encloses the call.
	case fillInsideFill
	/// The call is on a cycle.
	case fillCycleMember
	/// The call is reached on more than one route, whose caller's declarations may differ.
	case fillCallSeveralVariants
	/// A fill of the call makes a call of a seam or a public mock, which may re-enter this call's levels.
	case fillHoldsCall
	/// A dispatcher of the call carries a seam's deferred fields, so a fill may take a memo in a form only the forms its tree
	/// reads decide, which the world's reads, by label, do not hold.
	case fillHandedMemo
}

/// What one fill of a root's seam call binds, takes and reads, made from the world's facts alone (step 3, row 2): its
/// identity, the case values it binds, what it takes after them, what it reads of the caller's scope, and whether its body
/// declares a function. Keyed by the fill's key, never by a name.
struct FillFacts: Sendable {
	/// One label the fill reads of the caller's scope, through the root dispatcher.
	struct CallerRead: Sendable {
		let label: String
		/// Whether a read of the fill's tree requires it, so the fill takes it non-optional.
		let isRequired: Bool
	}

	/// The fill's key (`ScopeGenerator.fillKey(of:)`).
	let key: String
	/// The fill's node.
	let declaration: DeclarationID
	/// The stem the fill's function is named from, which `FillNames` claims a name from.
	let functionNameStem: String
	/// The place the fill fills, its case's first.
	let hole: SeamSignature.Hole
	/// How a member of the seam's carrier takes the case's values, where it does.
	let carrierUse: SeamCarrierValues.Use?
	/// Whether the fill takes each field of its payload by itself: one that returns its wrapper's builder.
	let takesPayloadFields: Bool
	/// The labels of the fields the fill binds before its tree, read or not.
	let boundLabels: [String]
	/// The labels of the fields the fill binds, in field order.
	let bound: [String]
	/// What the fill takes after its case's values, in order (`ScopeGenerator.fillParameterFields`).
	let parametersTaken: [SeamSignature.Hole.Field]
	/// What a level function's member hands the fill (`ScopeGenerator.fillMemberParameterFields(takingPayloadFields:)`):
	/// the payload's fields first where `takesPayloadFields`, then `parametersTaken`.
	let memberParameters: [SeamSignature.Hole.Field]
	/// What the fill reads of the caller's scope, by label, in label order.
	let callerReads: [CallerRead]
	/// The parameter the fill takes for each of `callerReads`, in their order.
	let parametersTakenOfCallerReads: [Property]
	/// The labels the fill's tree reads from above it, sorted.
	let readLabels: [String]
	/// The labels the fill's tree reads or declares, which its scope parameter is named apart from, sorted.
	let labelsReadOrDeclared: [String]
	/// Whether the fill's body declares a function (`FillEmissionDecisions.Fill.declaresFunction`).
	let declaresFunction: Bool
	/// Whether the property the fill builds is a constant.
	let returnsBoundValue: Bool
	/// Whether the fill's tree reads the inner-scope levels it is offered (`FillInnerScopes`): never, for a fill of a
	/// root's call that holds no call of its own (`FillRefusal.fillHoldsCall`), since only a seam's own tree holds its
	/// hole sites.
	let readsInnerScopes: Bool

	/// The facts of a call's fills, or why node records leave them to the tree.
	enum OfCall {
		case facts([FillFacts])
		case refused(FillRefusal)
	}

	/// The facts as text, which two makings of them compare by. The stem is left out: the tree's fill keeps the hole of its
	/// first place, which a nested seam's levels route again after the name is claimed, so `FillNamesObservation` checks
	/// the names claimed from the stems instead.
	var projection: String {
		[
			"bound: \(bound.joined(separator: ", "))",
			"parameters: \(parametersTaken.map(\.property.asSource).joined(separator: ", "))",
			"member parameters: \(memberParameters.map(\.property.asSource).joined(separator: ", ")), takes payload fields: \(takesPayloadFields), carrier use: \(carrierUse.map { "\($0)" } ?? "none")",
			"bound labels: \(boundLabels.joined(separator: ", "))",
			"caller reads: \(callerReads.map { "\($0.label)\($0.isRequired ? "" : "?")" }.joined(separator: ", "))",
			"reads: \(readLabels.joined(separator: ", "))",
			"reads or declares: \(labelsReadOrDeclared.joined(separator: ", "))",
			"declares function: \(declaresFunction), returns bound value: \(returnsBoundValue), reads inner scopes: \(readsInnerScopes)",
		].joined(separator: "; ")
	}

	/// Why node records leave `call`, a seam call that fills a place, to the tree, or `nil`.
	static func refusal(ofCall call: DeclarationID, in world: TypeFactsGraph, routeCounts: [Int]) -> FillRefusal? {
		if world.isMockWorld {
			.fillMockWorld
		} else if world.scope(of: call).publicMockCall != nil {
			.fillPublicMockCall
		} else if world.firstRoute(to: call).dropLast().contains(where: { world.construction(of: $0) == .fill }) {
			.fillInsideFill
		} else if world.isOnCycle(call) {
			.fillCycleMember
		} else if routeCounts[Int(call)] > 1 {
			.fillCallSeveralVariants
		} else if fillsHoldCall(call, in: world) {
			.fillHoldsCall
		} else {
			nil
		}
	}

	/// Whether a fill `call` passes builds, somewhere in its tree, a call of a seam or a public mock.
	static func fillsHoldCall(_ call: DeclarationID, in world: TypeFactsGraph) -> Bool {
		// A fill's node is built as its call builds it, a call of a seam or a public mock too, which its scope says.
		var pending = world.edges(from: call).filter { world.construction(of: $0) == .fill }
		var visited = Set(pending)
		while let declaration = pending.popLast() {
			let scope = world.scope(of: declaration)
			guard scope.seamCall == nil, scope.publicMockCall == nil else { return true }
			for target in world.edges(from: declaration) where visited.insert(target).inserted {
				pending.append(target)
			}
		}
		return false
	}

	/// The number of variants of each declaration of `world`.
	static func routeCounts(in world: TypeFactsGraph) -> [Int] {
		var counts = [Int](repeating: 0, count: world.declarationCount)
		for variant in 0..<Int32(world.variantCount) {
			counts[Int(world.declaration(of: variant))] += 1
		}
		return counts
	}

	/// The facts of each fill of `call` that generates code, in the order of the call's fill arguments, or why node records
	/// leave the call's fills to the tree.
	static func of(call: DeclarationID, in world: TypeFactsGraph) -> OfCall {
		let scope = world.scope(of: call)
		var log = ConstructionLog(recording: false)
		let callFills = ScopeGeneratorUnderConstruction.callFills(
			of: scope,
			holeArguments: scope.holeArguments,
			callPath: [],
			enclosingFills: [:],
			enclosingFillNames: .init([]),
			enclosingCarriedInnerScopes: [:],
			seamHoles: SeamHoles(),
			childNearestDeclarations: NearestDeclarations(),
			fillLabelsReadOnlyAsPlaceField: { _ in [] },
			fillSendableWrapperReads: { _ in [:] },
			log: &log,
		)
		let handsMemo = callFills.dispatchers.contains { dispatcher in
			dispatcher.cases.contains { $0.carriesDeferredFields && $0.values?.contains(where: \.isDeferredParameter) == true }
		}
		guard !handsMemo else { return .refused(.fillHandedMemo) }
		// The fill nodes the call passes, one per fill argument, in their order.
		let fillNodes = world.edges(from: call).filter { world.construction(of: $0) == .fill }
		var allFacts = [FillFacts]()
		for ((fill, _, _), fillNode) in zip(callFills.fills, fillNodes) where fill.emitsCode {
			allFacts.append(facts(of: fill, node: fillNode, in: world, log: &log))
		}
		return .facts(allFacts)
	}

	/// The facts of `fill`, whose node is `node`.
	private static func facts(of fill: ScopeGeneratorUnderConstruction.Fill, node: DeclarationID, in world: TypeFactsGraph, log: inout ConstructionLog) -> FillFacts {
		// What the fill's tree reads from above it, by label: required where a read asks for the label's value.
		var readLabels = Set<String>()
		var requiredLabels = Set<String>()
		// The fill's node is the declaration of the property it fills, built as the fill builds it.
		let filledProperty = world.property(of: node)
		for readID in world.reads(of: node) {
			let read = world.read(readID)
			// The node's own label is the fill's to build: a child closing a cycle on it reads the node, and only a receive of
			// it only if available beneath reads the caller's, never required.
			if read.channel == .value, world.text(ofLabel: read.label) == filledProperty?.label {
				if world.edges(from: node).contains(where: { child in
					world.reads(of: child).contains { world.read($0) == Read(.optional, label: read.label) }
				}) {
					readLabels.insert(world.text(ofLabel: read.label))
				}
				continue
			}
			switch read.channel {
			case .value:
				readLabels.insert(world.text(ofLabel: read.label))
				requiredLabels.insert(world.text(ofLabel: read.label))
			case .optional, .optionalValue, .fill:
				readLabels.insert(world.text(ofLabel: read.label))
			case .alias, .madeAgain, .mock, .carrier, .family, .override:
				break
			}
		}
		let (boundFill, _) = ScopeGeneratorUnderConstruction.boundFill(fill, readsDeferredFieldsFromStruct: fill.hole.innerSeamType != nil, deferredLabelsBoundFromStruct: [], deferredLabelsBoundByValue: [])
		let received = Set(boundFill.fields.map(\.property).filter { readLabels.contains($0.label) })
		let treeReads = FillTreeReadFacts(
			received: received,
			required: received.filter { requiredLabels.contains($0.label) },
			readsInnerScopes: false,
			fieldsCarriedBySites: [],
		)
		let callerReads = ScopeGeneratorUnderConstruction.callerReads(of: boundFill, child: treeReads, labelsHandedToReenteredFunctions: [], log: &log)
		var parametersTaken = [SeamSignature.Hole.Field]()
		var payloadFields = [SeamSignature.Hole.Field]()
		if let selection = ScopeGenerator.FillFieldSelection(hole: boundFill.hole, boundLabels: boundFill.boundLabels, fields: boundFill.fields, treeReads: treeReads) {
			payloadFields = selection.payloadFieldIndices.map { boundFill.fields[$0] }
			for index in selection.parameterFieldIndices {
				let field = boundFill.fields[index]
				parametersTaken.append(callerReads.parameterByLabel[field.property.label] ?? field)
			}
		}
		parametersTaken.append(contentsOf: callerReads.innerScopeParameters)
		let filledScope = world.scope(of: node)
		let declaresFunction = filledProperty?.propertyType.isConstant == false
			|| !filledScope.propertiesToGenerate.isEmpty
			|| filledScope.seamCall != nil
			|| filledScope.publicMockCall != nil
		return FillFacts(
			key: fill.key,
			declaration: node,
			functionNameStem: fill.functionNameStem,
			hole: boundFill.hole,
			carrierUse: fill.carrierUse,
			takesPayloadFields: fill.returnsWrapperBuilder,
			boundLabels: boundFill.fields.map(\.property.label).filter(boundFill.boundLabels.contains),
			bound: boundFill.fields.filter { boundFill.boundLabels.contains($0.property.label) && treeReads.reads($0.property) }.map(\.property.label),
			parametersTaken: parametersTaken,
			memberParameters: (fill.returnsWrapperBuilder ? payloadFields : []) + parametersTaken,
			callerReads: callerReads.parameterByLabel.keys.sorted().map { CallerRead(label: $0, isRequired: requiredLabels.contains($0)) },
			parametersTakenOfCallerReads: callerReads.parameterByLabel.sorted { $0.key < $1.key }.map(\.value.property),
			readLabels: readLabels.sorted(),
			labelsReadOrDeclared: Set(boundFill.fields.map(\.property.label)).union(readLabels).sorted(),
			declaresFunction: declaresFunction,
			returnsBoundValue: filledProperty?.propertyType.isConstant ?? false,
			readsInnerScopes: treeReads.readsInnerScopes,
		)
	}
}

/// What a call hands each read a fill makes of the caller's scope, on one of the call's variants (step 3, row 2): the
/// caller's nearest declaration of the read's label, or `nil` where none answers it. Per variant, since the declarations
/// above a call are the one thing two routes to it can differ in.
enum FillCallerSources {
	/// The source of each of `facts`' caller reads, in their order, where `call` is reached as `variant`.
	static func of(facts: FillFacts, call: DeclarationID, variant: VariantID, in world: TypeFactsGraph) -> [ArgumentSource] {
		let edges = world.edges(from: call)
		let reads = Array(world.reads(of: facts.declaration))
		guard let edge = edges.firstIndex(of: facts.declaration) else { return facts.callerReads.map { _ in .nil } }
		let sources = Array(world.sources(ofCall: edge - edges.startIndex, of: variant))
		return zip(facts.callerReads, facts.parametersTakenOfCallerReads).map { callerRead, parameter in
			// The read of the label's value, else its read only if available.
			let readIndex = reads.indices.first { world.read(reads[$0]).channel == .value && world.text(ofLabel: world.read(reads[$0]).label) == callerRead.label }
				?? reads.indices.first { world.read(reads[$0]).channel == .optionalValue && world.text(ofLabel: world.read(reads[$0]).label) == callerRead.label }
			guard let readIndex, readIndex < sources.count, let declared = declaration(of: callerRead.label, answering: sources[readIndex], callee: variant, in: world) else { return .nil }
			return argument(reading: parameter, declaredAs: declared)
		}
	}

	/// The declaration that answers a read `source` hands `callee`, built before the read, or `nil` where none does.
	private static func declaration(of label: String, answering source: AnswerSource, callee: VariantID, in world: TypeFactsGraph) -> Property? {
		// The call's own edge to the fill answers a read of a field the fill binds with that field (the fill channel): a caller
		// read is a field no place of the case carries, so the caller's nearest declaration of the label answers it.
		guard source.kind != .bound || source.payload != world.declaration(of: callee) else {
			return nearestDeclaration(of: label, above: callee, in: world)
		}
		var source = source
		var callee = callee
		while true {
			switch source.kind {
			case .none:
				// No declaration before the call answers the read: the scope that makes the call builds a declaration of its own
				// made after the call first, where it makes one.
				return world.edges(from: world.declaration(of: callee)).lazy.filter { world.construction(of: $0) != .fill }.compactMap { world.property(of: $0) }.first { $0.label == label }
			case .bound:
				// The declaration that binds the read: a property its scope builds, else one its type receives or forwards.
				let binder = source.payload
				return world.edges(from: binder).lazy.filter { world.construction(of: $0) != .fill }.compactMap { world.property(of: $0) }.first { $0.label == label }
					?? world.scope(of: binder).instantiable.dependencies.lazy.map(\.property).first { $0.label == label }
			case .passedThrough:
				// The callee's caller answers its read at the position the source names.
				guard let (caller, edge) = self.caller(of: callee, in: world) else { return nil }
				source = world.sources(ofCall: edge, of: caller)[world.sources(ofCall: edge, of: caller).startIndex + Int(source.payload)]
				callee = caller
			}
		}
	}

	/// The nearest declaration of `label` in the scopes that enclose `variant`'s declaration: a property one of them builds, else
	/// one its type receives or forwards.
	private static func nearestDeclaration(of label: String, above variant: VariantID, in world: TypeFactsGraph) -> Property? {
		var variant = variant
		while let (caller, _) = caller(of: variant, in: world) {
			let binder = world.declaration(of: caller)
			if let declared = world.edges(from: binder).lazy.filter({ world.construction(of: $0) != .fill }).compactMap({ world.property(of: $0) }).first(where: { $0.label == label })
				?? world.scope(of: binder).instantiable.dependencies.lazy.map(\.property).first(where: { $0.label == label })
			{
				return declared
			}
			variant = caller
		}
		return nil
	}

	/// The variant that calls `variant`, and the index of the edge it calls it on.
	private static func caller(of variant: VariantID, in world: TypeFactsGraph) -> (VariantID, Int)? {
		for caller in 0..<Int32(world.variantCount) {
			let calls = world.calls(of: caller)
			if let index = calls.firstIndex(of: variant) {
				return (caller, index - calls.startIndex)
			}
		}
		return nil
	}

	/// What a call hands `parameter` where `declared` is the nearest declaration of its label, as
	/// `ScopeGeneratorUnderConstruction` hands a fill's caller read.
	private static func argument(reading parameter: Property, declaredAs declared: Property) -> ArgumentSource {
		let forms = CycleParameter.forms(providedBy: declared)
		guard parameter.formsReadByOnlyIfAvailableReceive.contains(where: forms.contains) else {
			guard let instanceProperty = parameter.asLazilyInstantiatedInstanceProperty, instanceProperty.formsReadByOnlyIfAvailableReceive.contains(where: forms.contains) else { return .nil }
			let instance = argument(reading: instanceProperty, declaredAs: declared)
			let wrapperType = parameter.typeDescription.unwrapped
			return declared.typeDescription.isOptional
				? .optionalWrapper(of: instance, wrapperType: wrapperType)
				: .wrapper(of: instance, wrapperType: wrapperType)
		}
		return !parameter.propertyType.isLazilyInstantiated && declared.propertyType.isLazilyInstantiated
			? .lazyInstance(label: parameter.label, throughOptional: false)
			: .binding(label: parameter.label)
	}
}

/// What a test compares of one root's filled seam calls: the facts node records make of each fill from the world, and the
/// facts the tree builds the same fills with, each by the fill's key as its projection (`FillFacts.projection`).
public struct FillFactsObservation: Sendable {
	public let root: String
	/// The projections of the fills node records make facts of, by key.
	public let fromRecords: [String: String]
	/// The projections of the tree's fills of the root's seam calls no fill encloses, by key.
	public let tree: [String: String]
	/// The reason node records leave each filled call they leave to the tree (`FillRefusal`), sorted.
	public let refusals: [String]

	/// Called with each production root's filled calls, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: (@Sendable (FillFactsObservation) -> Void)?

	/// Hands the observer, where one is set, the facts of `world`'s filled calls beside `treeProjections`, the tree's
	/// (`ScopeGenerator.fillFactsProjectionsOfCallsOutsideFills()`).
	static func observe(root: String, world: TypeFactsGraph, treeProjections: [String: String]) {
		guard let observer else { return }
		let routeCounts = FillFacts.routeCounts(in: world)
		var fromRecords = [String: String]()
		var refusals = [FillRefusal]()
		for declaration in 0..<Int32(world.declarationCount) where world.construction(of: declaration) == .seamCall {
			let scope = world.scope(of: declaration)
			guard scope.holeArguments.contains(where: {
				if case .fill = $0 {
					true
				} else {
					false
				}
			}) else { continue }
			if let refusal = FillFacts.refusal(ofCall: declaration, in: world, routeCounts: routeCounts) {
				refusals.append(refusal)
			} else {
				switch FillFacts.of(call: declaration, in: world) {
				case let .facts(allFacts):
					let variant = (0..<Int32(world.variantCount)).first { world.declaration(of: $0) == declaration } ?? 0
					for facts in allFacts {
						let sources = FillCallerSources.of(facts: facts, call: declaration, variant: variant, in: world)
						fromRecords[facts.key] = facts.projection + "; sources: " + zip(facts.callerReads, sources).map { "\($0.label) \($1.spelled)" }.joined(separator: ", ")
					}
				case let .refused(refusal):
					refusals.append(refusal)
				}
			}
		}
		observer(FillFactsObservation(root: root, fromRecords: fromRecords, tree: treeProjections, refusals: refusals.map(\.rawValue).sorted()))
	}
}
