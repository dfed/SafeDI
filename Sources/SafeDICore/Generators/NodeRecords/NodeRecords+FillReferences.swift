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
	/// - Throws: Why node records leave a call inside a fill to the tree: it holds a call inside one of its own fills
	///   (`NodeRecordRefusal.fillCallNestsCall`), decides what it reuses from levels node records do not hand it
	///   (`fillSeamCallReadsCallingTreesLevels`), reads a value of the fill's case (`fillCallReadsCasePayload`), or has a
	///   `@Sendable` dispatcher lead to one of its own that serves both families (`fillCallReachesBothFamiliesDispatcher`).
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
				let scope = world.scope(of: node)
				if isFirstVisit, scope.seamCall != nil || scope.publicMockCall != nil {
					let call = try referencesOfCall(node, insideFillWithPayloadLabels: fill.payloadLabels, enclosingKeys: enclosingKeys, in: world, callingTreeHoldsHoles: callingTreeHoldsHoles)
					referenced.formUnion(call.referenced)
					// A `@Sendable` function between the fill and the call, or the call's own, refers to all the call refers to.
					references.referencedFromSendableFunctions.formUnion(insideSendableFunction ? call.referenced : call.referencedFromSendableFunctions)
					references.namedKeys.formUnion(call.named)
				} else if isFirstVisit {
					for child in world.edges(from: node) {
						pending.append((child, insideSendableFunction || NodeRecords.buildsInSendableFunction(child, in: world)))
					}
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
		guard isPublicMockCall || !callingTreeHoldsHoles else { throw .fillSeamCallReadsCallingTreesLevels }
		guard !readsPayloadValue else { throw .fillCallReadsCasePayload }
		var referenced = Set<String>()
		var referencedFromSendableFunctions = Set<String>()
		var named = Set<String>()
		var ownFills = [String]()
		var ownFillNodes = [DeclarationID]()
		var filledSites = Set<SeamSignature.Hole.Site>()
		// The fill nodes the call passes, one per fill argument, in their order: `TypeFactsGraph`'s graph adds a scope's fill
		// edges after its properties', in the order of its `holeArguments`.
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
			// The call passes the enclosing call's fill of a place of the same site by name. Where the place is of a `@Sendable`
			// builder, that fill, of the same hole, is `@Sendable` already, which the tree's reference from a `@Sendable`
			// function adds nothing to.
			if enclosingKeys.contains(key) {
				referenced.insert(key)
			} else {
				ownFills.append(key)
				ownFillNodes.append(fillNode)
			}
		}
		// What a call inside one of the call's own fills refers to of them is a later step's.
		guard !FillFacts.treesHoldCall(ownFillNodes, in: world) else { throw .fillCallNestsCall }
		let calledBuilders = scope.calledBuilders
		// The call passes the enclosing call's dispatcher of a builder's enum by name. A seam's builder that takes a builder
		// struct is handed the struct its root level returns, unless the enclosing call declares a dispatcher of the hole
		// type over its enum, as `Scope` decides it where the tree that makes the call holds no hole.
		let holeTypesOfEnclosingDispatchers = Set((calledBuilders?.builders ?? []).filter { enclosingKeys.contains(ScopeGenerator.FillDispatcher.key(of: $0.enumKey)) }.map(\.enumKey.holeType))
		let buildersReachingFilledSites: [SeamSignature.Builder] = calledBuilders.map { calledBuilders in
			let filledSiteNumbers = calledBuilders.siteNumbers(of: filledSites)
			return calledBuilders.builders.filter { calledBuilders.reaches(anyOf: filledSiteNumbers, from: $0.enumKey, onRoutesOf: isPublicMockCall ? $0.enumKey : nil) }
		} ?? []
		for builder in buildersReachingFilledSites {
			let returnsBuilderStruct = !isPublicMockCall && builder.takesBuilderStruct && !holeTypesOfEnclosingDispatchers.contains(builder.enumKey.holeType)
			let key = ScopeGenerator.FillDispatcher.key(of: builder.enumKey, returnsBuilderStruct: returnsBuilderStruct)
			if enclosingKeys.contains(key) {
				referenced.insert(key)
				named.insert(key)
				referencedFromSendableFunctions.formUnion(builder.enumKey.isSendable ? [key] : [])
			}
		}
		// Only the dispatchers' keys, families and cases' targets are read, never their names, which are placeholders.
		var names = GeneratedNameAllocator(reserving: [])
		let dispatchers = calledBuilders.map { calledBuilders in
			ScopeGenerator.FillDispatcher.dispatchers(
				of: calledBuilders,
				filledSites: filledSites,
				enclosingDispatchers: Dictionary(enclosingKeys.map { ($0, "enclosing \($0)") }, uniquingKeysWith: { first, _ in first }),
				fillNames: [:],
				names: &names,
				decidesPerRoute: isPublicMockCall,
			)
		} ?? []
		let ownKeys = Set(ownFills + dispatchers.map(\.key))
		let sendableDispatcherKeys = Set(dispatchers.filter(\.isSendableFamily).map(\.key))
		for dispatcher in dispatchers {
			let targetKeys = dispatcher.cases.compactMap(\.target?.key)
			named.formUnion(targetKeys)
			referenced.formUnion(targetKeys.filter { !ownKeys.contains($0) })
			// A `@Sendable` dispatcher refers to what its cases lead to from a `@Sendable` function. One whose case leads to a
			// dispatcher of its own call that serves both families would make that one `@Sendable` too: a later step's.
			guard !sendableDispatcherKeys.contains(dispatcher.key) || targetKeys.allSatisfy({ !ownKeys.contains($0) || sendableDispatcherKeys.contains($0) || ownFills.contains($0) }) else { throw .fillCallReachesBothFamiliesDispatcher }
			referencedFromSendableFunctions.formUnion(sendableDispatcherKeys.contains(dispatcher.key) ? targetKeys.filter { !ownKeys.contains($0) } : [])
		}
		return (referenced, referencedFromSendableFunctions, named.subtracting(ownKeys))
	}
}
