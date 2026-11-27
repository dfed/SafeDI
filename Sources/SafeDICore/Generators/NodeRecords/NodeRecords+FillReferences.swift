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

/// What the calls inside a call's fills refer to by name of the call's own fills and dispatchers, as the tree gathers it
/// beneath the call (`ScopeGenerator`'s `fillReferences(holeCallArguments:builderCallArguments:children:buildsInSendableFunction:)`):
/// a call inside a fill passes the enclosing call's fill of a place of the same site, passes the enclosing call's
/// dispatcher for a builder of the same enum, and has cases of its own dispatchers lead to the enclosing call's
/// dispatchers, each of which it refers to by name. What it refers to from a `@Sendable` function is `@Sendable`, and a
/// fill one of them names is never held in a dispatcher's case (`FillEmissionDecisions`).
struct FillReferences: Sendable {
	/// The keys of the call's fills and dispatchers each fill's tree refers to by name, by the fill's key.
	var referencesByFillKey = [String: Set<String>]()
	/// The keys of the call's fills and dispatchers a `@Sendable` function inside one of its fills refers to.
	var referencedFromSendableFunctions = Set<String>()
	/// The keys of the call's fills and dispatchers a call inside one of its fills names: an argument it passes, or the
	/// target of a case of one of its dispatchers.
	var namedKeys = Set<String>()

	/// What the calls inside the fills of `call` refer to of its fills and dispatchers.
	/// - Parameters:
	///   - fills: The call's fills that emit code, each with its node and the labels of its case's payload.
	///   - dispatchers: The call's dispatchers.
	///   - callingTreeHoldsHoles: Whether the tree that makes the call holds holes, whose levels a seam's call inside a fill
	///     would read to decide which of the enclosing call's dispatchers it reuses.
	/// - Throws: `NodeRecordRefusal.fillHoldsCall` where a call inside a fill holds a call inside one of its own fills, or
	///   decides what it reuses from levels node records do not hand it.
	static func of(
		fills: [(key: String, node: DeclarationID, payloadLabels: Set<String>)],
		dispatchers: [ScopeGenerator.FillDispatcher],
		in world: some NodeRecordSources,
		callingTreeHoldsHoles: Bool,
	) throws(NodeRecordRefusal) -> FillReferences {
		let enclosingKeys = Set(fills.map(\.key) + dispatchers.map(\.key))
		var references = FillReferences()
		for fill in fills {
			var referenced = Set<String>()
			// Each node of the fill's tree once inside a `@Sendable` function and once outside, as it is reached.
			var pending = [(node: fill.node, insideSendableFunction: NodeRecords.buildsInSendableFunction(fill.node, in: world))]
			var visitedInsideSendableFunction = Set<DeclarationID>()
			var visitedOutsideSendableFunction = Set<DeclarationID>()
			while let (node, insideSendableFunction) = pending.popLast() {
				let isFirstVisit = insideSendableFunction ? visitedInsideSendableFunction.insert(node).inserted : visitedOutsideSendableFunction.insert(node).inserted
				guard isFirstVisit else { continue }
				let scope = world.scope(of: node)
				if node != fill.node, scope.seamCall != nil || scope.publicMockCall != nil {
					let call = try referencesOfCall(node, insideFillWithPayloadLabels: fill.payloadLabels, enclosingKeys: enclosingKeys, in: world, callingTreeHoldsHoles: callingTreeHoldsHoles)
					referenced.formUnion(call.referenced)
					// A `@Sendable` function between the fill and the call, or the call's own, refers to all the call refers to.
					references.referencedFromSendableFunctions.formUnion(insideSendableFunction ? call.referenced : call.referencedFromSendableFunctions)
					references.namedKeys.formUnion(call.named)
					continue
				}
				for child in world.edges(from: node) {
					pending.append((child, insideSendableFunction || NodeRecords.buildsInSendableFunction(child, in: world)))
				}
			}
			if !referenced.isEmpty {
				references.referencesByFillKey[fill.key] = referenced
			}
		}
		return references
	}

	/// What `call`, a call inside a fill whose case's payload holds `payloadLabels` of the call whose fills and dispatchers
	/// are `enclosingKeys`, refers to of them.
	private static func referencesOfCall(
		_ call: DeclarationID,
		insideFillWithPayloadLabels payloadLabels: Set<String>,
		enclosingKeys: Set<String>,
		in world: some NodeRecordSources,
		callingTreeHoldsHoles: Bool,
	) throws(NodeRecordRefusal) -> (referenced: Set<String>, referencedFromSendableFunctions: Set<String>, named: Set<String>) {
		let scope = world.scope(of: call)
		let isPublicMockCall = scope.publicMockCall != nil
		// A seam's call decides whether a dispatcher returns its builder struct from the levels of the tree that makes it. A
		// value of the fill's case a call reads, which the fill then takes by itself, its facts do not hold yet.
		let readsPayloadValue = world.reads(of: call).contains { payloadLabels.contains(world.text(ofLabel: world.read($0).label)) }
		guard isPublicMockCall || !callingTreeHoldsHoles, !readsPayloadValue else { throw .fillHoldsCall }
		var referenced = Set<String>()
		var referencedFromSendableFunctions = Set<String>()
		var named = Set<String>()
		var ownFills = [(key: String, isSendable: Bool)]()
		var ownFillNodes = [DeclarationID]()
		var filledSites = Set<SeamSignature.Hole.Site>()
		// The fill nodes the call passes, one per fill argument, in their order.
		let fillNodes = world.edges(from: call).filter { world.construction(of: $0) == .fill }
		let filledHoles = scope.holeArguments.compactMap { argument -> SeamSignature.Hole? in
			switch argument {
			case let .fill(hole, _, _): hole
			case .passUp: nil
			}
		}
		for (hole, fillNode) in zip(filledHoles, fillNodes) {
			filledSites.insert(hole.site)
			let key = ScopeGenerator.fillKey(of: hole)
			// The call passes the enclosing call's fill of a place of the same site by name.
			if enclosingKeys.contains(key) {
				referenced.insert(key)
				if hole.isSendable {
					referencedFromSendableFunctions.insert(key)
				}
			} else {
				ownFills.append((key, hole.isSendable))
				ownFillNodes.append(fillNode)
			}
		}
		// What a call inside one of the call's own fills refers to of them is a later step's.
		guard !FillFacts.treesHoldCall(ownFillNodes, in: world) else { throw .fillHoldsCall }
		let dispatchers: [ScopeGenerator.FillDispatcher]
		if let calledBuilders = scope.calledBuilders {
			let filledSiteNumbers = calledBuilders.siteNumbers(of: filledSites)
			// The call passes the enclosing call's dispatcher of a builder's enum by name. A seam's builder that takes a builder
			// struct is handed the struct its root level returns, unless the enclosing call declares a dispatcher of the hole
			// type over its enum, as `Scope` decides it where the tree that makes the call holds no hole.
			for builder in calledBuilders.builders where calledBuilders.reaches(anyOf: filledSiteNumbers, from: builder.enumKey, onRoutesOf: isPublicMockCall ? builder.enumKey : nil) {
				let returnsBuilderStruct = !isPublicMockCall && builder.takesBuilderStruct && !calledBuilders.builders.contains { calledBuilder in
					calledBuilder.enumKey.holeType == builder.enumKey.holeType && enclosingKeys.contains(ScopeGenerator.FillDispatcher.key(of: calledBuilder.enumKey))
				}
				let key = ScopeGenerator.FillDispatcher.key(of: builder.enumKey, returnsBuilderStruct: returnsBuilderStruct)
				if enclosingKeys.contains(key) {
					referenced.insert(key)
					named.insert(key)
					if builder.enumKey.isSendable {
						referencedFromSendableFunctions.insert(key)
					}
				}
			}
			var names = GeneratedNameAllocator(reserving: [])
			dispatchers = ScopeGenerator.FillDispatcher.dispatchers(
				of: calledBuilders,
				filledSites: filledSites,
				enclosingDispatchers: Dictionary(enclosingKeys.map { ($0, "enclosing \($0)") }, uniquingKeysWith: { first, _ in first }),
				fillNames: [:],
				names: &names,
				decidesPerRoute: isPublicMockCall,
			)
		} else {
			dispatchers = []
		}
		let ownKeys = Set(ownFills.map(\.key) + dispatchers.map(\.key))
		var referencesByKey = [String: [String]]()
		for dispatcher in dispatchers {
			let targetKeys = dispatcher.cases.compactMap(\.target?.key)
			referencesByKey[dispatcher.key] = targetKeys
			named.formUnion(targetKeys)
			referenced.formUnion(targetKeys.filter { !ownKeys.contains($0) })
		}
		// The call's fills and dispatchers that are `@Sendable` refer to what they refer to from a `@Sendable` function.
		var keysToVisit = ownFills.filter(\.isSendable).map(\.key) + dispatchers.filter(\.isSendableFamily).map(\.key)
		var sendableKeys = Set(keysToVisit)
		while let key = keysToVisit.popLast() {
			for target in referencesByKey[key] ?? [] {
				if ownKeys.contains(target) {
					if sendableKeys.insert(target).inserted {
						keysToVisit.append(target)
					}
				} else {
					referencedFromSendableFunctions.insert(target)
				}
			}
		}
		return (referenced, referencedFromSendableFunctions, named.subtracting(ownKeys))
	}
}
