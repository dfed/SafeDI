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
enum FillRefusal: String, Error, Sendable, CaseIterable {
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
	/// The labels of the fields the fill binds, in field order.
	let bound: [String]
	/// What the fill takes after its case's values, in order (`ScopeGenerator.fillParameterFields`).
	let parametersTaken: [SeamSignature.Hole.Field]
	/// What the fill reads of the caller's scope, by label, in label order.
	let callerReads: [CallerRead]
	/// The labels the fill's tree reads from above it, sorted.
	let readLabels: [String]
	/// The labels the fill's tree reads or declares, which its scope parameter is named apart from, sorted.
	let labelsReadOrDeclared: [String]
	/// Whether the fill's body declares a function (`FillEmissionDecisions.Fill.declaresFunction`).
	let declaresFunction: Bool
	/// Whether the property the fill builds is a constant.
	let returnsBoundValue: Bool

	/// The facts as text, which two makings of them compare by.
	var projection: String {
		[
			"bound: \(bound.joined(separator: ", "))",
			"parameters: \(parametersTaken.map(\.property.asSource).joined(separator: ", "))",
			"caller reads: \(callerReads.map { "\($0.label)\($0.isRequired ? "" : "?")" }.joined(separator: ", "))",
			"reads: \(readLabels.joined(separator: ", "))",
			"reads or declares: \(labelsReadOrDeclared.joined(separator: ", "))",
			"declares function: \(declaresFunction), returns bound value: \(returnsBoundValue)",
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
	static func of(call: DeclarationID, in world: TypeFactsGraph) -> Result<[FillFacts], FillRefusal> {
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
		guard !handsMemo else { return .failure(.fillHandedMemo) }
		// The fill nodes the call passes, one per fill argument, in their order.
		let fillNodes = world.edges(from: call).filter { world.construction(of: $0) == .fill }
		var allFacts = [FillFacts]()
		for ((fill, _, _), fillNode) in zip(callFills.fills, fillNodes) where fill.emitsCode {
			allFacts.append(facts(of: fill, node: fillNode, in: world, log: &log))
		}
		return .success(allFacts)
	}

	/// The facts of `fill`, whose node is `node`.
	private static func facts(of fill: ScopeGeneratorUnderConstruction.Fill, node: DeclarationID, in world: TypeFactsGraph, log: inout ConstructionLog) -> FillFacts {
		// What the fill's tree reads from above it, by label: required where a read asks for the label's value.
		var readLabels = Set<String>()
		var requiredLabels = Set<String>()
		// The fill's node is the declaration of the property it fills, built as the fill builds it, whose subtree's reads hold
		// the read of the node's own label.
		let filledProperty = world.property(of: node)
		for readID in world.reads(of: node) {
			let read = world.read(readID)
			// A required read of the node's own label is the node's declaration of it, never a read of the caller's.
			guard read.channel != .value || world.text(ofLabel: read.label) != filledProperty?.label else { continue }
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
		if let selection = ScopeGenerator.FillFieldSelection(hole: boundFill.hole, boundLabels: boundFill.boundLabels, fields: boundFill.fields, treeReads: treeReads) {
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
			bound: boundFill.fields.filter { boundFill.boundLabels.contains($0.property.label) && treeReads.reads($0.property) }.map(\.property.label),
			parametersTaken: parametersTaken,
			callerReads: callerReads.parameterByLabel.keys.sorted().map { CallerRead(label: $0, isRequired: requiredLabels.contains($0)) },
			readLabels: readLabels.sorted(),
			labelsReadOrDeclared: Set(boundFill.fields.map(\.property.label)).union(readLabels).sorted(),
			declaresFunction: declaresFunction,
			returnsBoundValue: filledProperty?.propertyType.isConstant ?? false,
		)
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
			guard scope.holeArguments.contains(where: { if case .fill = $0 { true } else { false } }) else { continue }
			if let refusal = FillFacts.refusal(ofCall: declaration, in: world, routeCounts: routeCounts) {
				refusals.append(refusal)
			} else {
				switch FillFacts.of(call: declaration, in: world) {
				case let .success(allFacts):
					for facts in allFacts {
						fromRecords[facts.key] = facts.projection
					}
				case let .failure(refusal):
					refusals.append(refusal)
				}
			}
		}
		observer(FillFactsObservation(root: root, fromRecords: fromRecords, tree: treeProjections, refusals: refusals.map(\.rawValue).sorted()))
	}
}
