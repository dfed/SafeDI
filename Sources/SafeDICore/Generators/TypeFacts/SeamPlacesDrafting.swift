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

// The drafts a seam's place graph (`SeamSignature.Places`) is assembled from, read off the seam's facts world alone: one
// level per (variant, edge) on a route to a hole or to a call that presents places, a site per hole edge, and a case per
// owner level and family. Nothing here reads the seam's generator tree.

/// A level: the body of one variant before one of its edges.
struct SeamPlacesLevelID: Hashable, Sendable {
	/// The edge of the seam root's variant before which its parameters are bound and nothing else is.
	static let seamRootTop: Int32 = -1

	let variant: VariantID
	/// The edge's index in `edgeFacts(from: declaration(of: variant))`, or `seamRootTop`.
	let edge: Int32
}

/// The fill an edge passes, where the edge is a fill's: the hole of the called signature it fills.
struct SeamPlacesFillDraft: Equatable, Sendable {
	/// The world's ID of the seam or public mock called.
	let calledType: Int32
	let isPublicMock: Bool
	/// The hole's position among the called signature's holes.
	let holeIndex: Int32
}

/// The body of one variant before one of its edges, with what a place beneath reads of it.
struct SeamPlacesLevelDraft: Equatable, Sendable {
	let id: SeamPlacesLevelID
	/// Every level whose edge calls this level's variant, in facts order: the levels a route can come down from. Empty
	/// for the seam's root.
	let parents: [SeamPlacesLevelID]
	/// How many of the variant's bindings (`TypeFactsGraph.worldBindings(of:)`) are bound before the edge. Later bindings
	/// hide farther declarations of their label but hold no value there.
	let bindingsBefore: Int32
	/// The edge's position in the order the body builds its children, and the loop of builders it is a member of (-1).
	let nextPosition: Int32
	let nextLoop: Int32
	/// The function the edge opens around its child.
	let opens: TypeFactsFunctionOpened
	/// For a fill's edge, what it fills.
	let fill: SeamPlacesFillDraft?
	/// For a call that closes a cycle, the level of the build it closes on.
	let closesOn: SeamPlacesLevelID?
}

/// A field of a site: a declaration a hole's owner level can see, by the level and binding that declare it.
struct SeamPlacesFieldDraft: Equatable, Sendable {
	let label: WorldLabelID
	let declaredAt: SeamPlacesLevelID
	/// The binding's index in `worldBindings(of: declaration(of: declaredAt.variant))`.
	let binding: Int32
}

/// A hole edge beneath its owner level.
struct SeamPlacesSiteDraft: Equatable, Sendable {
	/// The level before the hole's edge.
	let owner: SeamPlacesLevelID
	/// The hole's leaf.
	let hole: DeclarationID
	/// The owner level's own declarations bound before the hole, in binding order. The fields of the levels above are
	/// theirs, reached through `SeamPlacesLevelDraft.parents`, so a site holds no list that grows with its routes.
	let fields: [SeamPlacesFieldDraft]
}

/// The places of one owner level in one family: one `.place(sites:)` case.
struct SeamPlacesCaseDraft: Equatable, Sendable {
	let owner: SeamPlacesLevelID
	let isBuiltInSendableFunction: Bool
	let siteOpensSendableFunction: Bool
	/// Empty for a case passed up from a called seam.
	let sites: [SeamPlacesSiteDraft]
	/// For a case passed up from a called seam, that seam's case: a reference, never a copy of its levels.
	let passedUp: SeamSignature.Places.CalledCase?
	/// The first case, in facts order, that presents the same places.
	let firstCasePresentingSamePlaces: Int?
}

/// The families a body is built in on the routes to it.
struct SeamPlacesFamilies: OptionSet, Sendable {
	let rawValue: UInt8

	static let plain = SeamPlacesFamilies(rawValue: 1 << 0)
	static let sendable = SeamPlacesFamilies(rawValue: 1 << 1)
}

extension TypeFactsFunctionOpened {
	/// Whether the function is `@Sendable`, which makes everything beneath it be built in the `@Sendable` family.
	var opensSendableFunction: Bool {
		switch self {
		case .none, .instantiatorBuilder:
			false
		case .sendableInstantiatorBuilder, .sendableLazyWrapper, .otherSendableFunction:
			true
		}
	}
}

/// A seam's drafts, read off the facts world of its own tree: every level on a route from the seam's root to a hole, or
/// to a call that presents places of the seam it calls, and a site per hole edge.
///
/// A route goes down an edge that builds its child in line, never a call that closes a cycle: what is beneath the closed-on
/// build is built in its own function. The levels of the routes to those calls are `closingLevels`, which the re-entries
/// read (`closesOn`).
struct SeamPlacesDrafts: Sendable {
	init(world: TypeFactsGraph) {
		let variantCount = world.variantCount
		let fillByEdge = Dictionary(world.fills.map { (Int($0.edge), $0) }, uniquingKeysWith: { first, _ in first })
		/// Whether the edge's child is a place of the seam's own: a hole, or a call that passes places up.
		func isPlaceEdge(target: DeclarationID) -> Bool {
			let node = world.graph.nodes[Int(target)]
			switch node.key.leaf {
			case .hole:
				return true
			case .alias:
				return false
			case .none:
				return node.scope.holeArguments.contains { argument in
					switch argument {
					case .passUp:
						true
					case .fill:
						false
					}
				}
			}
		}
		// Which variants hold a place beneath them on a route, and which a call that closes a cycle: a fold up the calls
		// that build in line, from the variants whose own edges hold one.
		var holdsPlace = [Bool](repeating: false, count: variantCount)
		var holdsClosingCall = [Bool](repeating: false, count: variantCount)
		var callers = [[VariantID]](repeating: [], count: variantCount)
		for variant in 0..<VariantID(variantCount) {
			let declaration = world.declaration(of: variant)
			let targets = world.edges(from: declaration)
			for ((target, edge), callee) in zip(zip(targets, world.edgeFacts(from: declaration)), world.calls(of: variant)) {
				if edge.isCallEdge {
					holdsClosingCall[Int(variant)] = true
				} else {
					if isPlaceEdge(target: target) {
						holdsPlace[Int(variant)] = true
					}
					callers[Int(callee)].append(variant)
				}
			}
		}
		for column in [0, 1] {
			var pending = (0..<VariantID(variantCount)).filter { column == 0 ? holdsPlace[Int($0)] : holdsClosingCall[Int($0)] }
			while let variant = pending.popLast() {
				for caller in callers[Int(variant)] where !(column == 0 ? holdsPlace[Int(caller)] : holdsClosingCall[Int(caller)]) {
					if column == 0 {
						holdsPlace[Int(caller)] = true
					} else {
						holdsClosingCall[Int(caller)] = true
					}
					pending.append(caller)
				}
			}
		}
		// The levels, in the order a walk from the seam's root in build order first reaches them.
		var levels = [SeamPlacesLevelDraft]()
		var closingLevels = [SeamPlacesLevelDraft]()
		var sites = [SeamPlacesSiteDraft]()
		var parentsByVariant = [[SeamPlacesLevelID]](repeating: [], count: variantCount)
		var visited = [Bool](repeating: false, count: variantCount)
		var order = [VariantID]()
		let rootVariant = world.rootVariant(0)
		var pending = [rootVariant]
		visited[Int(rootVariant)] = true
		while let variant = pending.popLast() {
			order.append(variant)
			let declaration = world.declaration(of: variant)
			let targets = world.edges(from: declaration)
			let facts = world.edgeFacts(from: declaration)
			let callees = world.calls(of: variant)
			let edgeIndices = facts.indices.sorted { facts[$0].buildPosition < facts[$1].buildPosition }
			var children = [VariantID]()
			for edgeIndex in edgeIndices {
				let edge = facts[edgeIndex]
				let callee = callees[callees.startIndex + edgeIndex - facts.startIndex]
				let target = targets[targets.startIndex + edgeIndex - facts.startIndex]
				let isPlace = !edge.isCallEdge && isPlaceEdge(target: target)
				let leadsToPlace = !edge.isCallEdge && holdsPlace[Int(callee)]
				let leadsToClosingCall = edge.isCallEdge || holdsClosingCall[Int(callee)]
				guard isPlace || leadsToPlace || leadsToClosingCall else { continue }
				let id = SeamPlacesLevelID(variant: variant, edge: Int32(edgeIndex - facts.startIndex))
				let level = SeamPlacesLevelDraft(
					id: id,
					parents: [],
					bindingsBefore: edge.bindingsBefore,
					nextPosition: edge.buildPosition,
					nextLoop: edge.loop,
					opens: edge.opens,
					fill: edge.isFill ? fillByEdge[world.graph.edgeOffset(of: Int(declaration)) + edgeIndex - facts.startIndex].map {
						SeamPlacesFillDraft(calledType: $0.calledType, isPublicMock: $0.isPublicMock, holeIndex: $0.holeIndex)
					} : nil,
					closesOn: nil,
				)
				if isPlace || leadsToPlace {
					levels.append(level)
				} else {
					closingLevels.append(level)
				}
				if isPlace, world.graph.nodes[Int(target)].key.leaf == .hole {
					// The owner level's own declarations bound before the hole; the farther ones are its parents' levels', which
					// a question about the case answers over the routes to it.
					let bindings = world.worldBindings(of: Int(declaration))
					let fields = bindings.prefix(Int(edge.bindingsBefore)).enumerated().map { index, binding in
						SeamPlacesFieldDraft(label: binding.label, declaredAt: id, binding: Int32(index))
					}
					sites.append(SeamPlacesSiteDraft(owner: id, hole: target, fields: fields))
				}
				if !edge.isCallEdge {
					parentsByVariant[Int(callee)].append(id)
					if !visited[Int(callee)] {
						visited[Int(callee)] = true
						children.append(callee)
					}
				}
			}
			pending.append(contentsOf: children.reversed())
		}
		func withParents(_ level: SeamPlacesLevelDraft) -> SeamPlacesLevelDraft {
			SeamPlacesLevelDraft(
				id: level.id,
				parents: parentsByVariant[Int(level.id.variant)],
				bindingsBefore: level.bindingsBefore,
				nextPosition: level.nextPosition,
				nextLoop: level.nextLoop,
				opens: level.opens,
				fill: level.fill,
				closesOn: level.closesOn,
			)
		}
		// The families each variant's body is built in on the routes to it: a `@Sendable` function an edge opens encloses
		// everything beneath it.
		var families = [SeamPlacesFamilies](repeating: [], count: variantCount)
		families[Int(rootVariant)] = .plain
		var familyWork = [rootVariant]
		while let variant = familyWork.popLast() {
			let declaration = world.declaration(of: variant)
			for (edge, callee) in zip(world.edgeFacts(from: declaration), world.calls(of: variant)) where !edge.isCallEdge && holdsPlace[Int(callee)] {
				let reached = edge.opens.opensSendableFunction ? SeamPlacesFamilies.sendable : families[Int(variant)]
				guard !families[Int(callee)].isSuperset(of: reached) else { continue }
				families[Int(callee)].formUnion(reached)
				familyWork.append(callee)
			}
		}
		// A case per site and family: each hole edge of a variant is one owner level.
		var cases = [SeamPlacesCaseDraft]()
		for site in sites {
			let isSendableHole = world.graph.nodes[Int(site.hole)].property?.propertyType.isSendable ?? false
			for (family, isSendable) in [(SeamPlacesFamilies.plain, false), (.sendable, true)] where families[Int(site.owner.variant)].contains(family) {
				cases.append(SeamPlacesCaseDraft(owner: site.owner, isBuiltInSendableFunction: isSendable, siteOpensSendableFunction: isSendableHole, sites: [site], passedUp: nil, firstCasePresentingSamePlaces: nil))
			}
		}
		self.cases = cases
		self.levels = levels.map(withParents)
		self.closingLevels = closingLevels.map(withParents)
		self.sites = sites
		variantOrder = order
		self.world = world
	}

	/// The levels on routes to places, in the order a walk from the seam's root in build order first reaches them.
	let levels: [SeamPlacesLevelDraft]
	/// The levels on routes only to calls that close cycles.
	let closingLevels: [SeamPlacesLevelDraft]
	let sites: [SeamPlacesSiteDraft]
	/// The cases of the seam's own places, a case per site and family.
	let cases: [SeamPlacesCaseDraft]
	/// The variants the walk reached, in the order it reached them.
	let variantOrder: [VariantID]
	private let world: TypeFactsGraph

	/// Test only, deleted before merge: how the drafts' levels compare with `places`, the stored place graph of the same
	/// seam, as lines of a report. A facts level is per declaration and its answers, where a stored level merges every
	/// build of a type before one next property, so the counts are reported by both keys.
	func levelReport(against places: SeamSignature.Places) -> [String] {
		func key(of level: SeamPlacesLevelDraft) -> String {
			let declaration = world.declaration(of: level.id.variant)
			let node = world.graph.nodes[Int(declaration)]
			let target = world.edges(from: declaration)[world.edges(from: declaration).startIndex + Int(level.id.edge)]
			let next = world.graph.nodes[Int(target)]
			let built = node.key.isFill ? "fill" : node.scope.instantiable.concreteInstantiable.asSource
			let nextProperty = next.key.isFill ? "fill" : next.property.map { "\($0.label): \($0.typeDescription.asSource)" } ?? "none"
			return "\(built) before \(nextProperty)"
		}
		let storedKeys = Set(places.levels.map { level in
			let built = level.key.builtType?.asSource ?? "fill"
			let nextProperty = level.key.nextProperty.map { "\($0.label): \($0.typeDescription.asSource)" } ?? "fill"
			return "\(built) before \(nextProperty)"
		})
		let draftKeys = Set(levels.map(key(of:)))
		let closingKeys = Set(closingLevels.map(key(of:)))
		let declarations = Set(levels.map { world.declaration(of: $0.id.variant) })
		let storedCaseKeys = Set(places.cases.filter { $0.passedUp == nil }.map { placeCase in
			let level = places.levels[placeCase.ownerLevel]
			return "\(level.key.builtType?.asSource ?? "fill") before \(level.key.nextProperty?.label ?? "fill") sendable \(placeCase.isBuiltInSendableFunction)"
		})
		let draftCaseKeys = Set(cases.map { draftCase in
			let declaration = world.declaration(of: draftCase.owner.variant)
			let node = world.graph.nodes[Int(declaration)]
			let hole = world.graph.nodes[Int(draftCase.sites[0].hole)]
			return "\(node.key.isFill ? "fill" : node.scope.instantiable.concreteInstantiable.asSource) before \(hole.property?.label ?? "fill") sendable \(draftCase.isBuiltInSendableFunction)"
		})
		return [
			"levels: facts \(levels.count) (\(Set(levels.map(\.id.variant)).count) variants of \(declarations.count) declarations, \(draftKeys.count) type-and-next keys), closing-only \(closingLevels.count) (\(closingKeys.subtracting(draftKeys).count) more keys), stored \(places.levels.count) (\(storedKeys.count) keys); keys only in facts \(draftKeys.union(closingKeys).subtracting(storedKeys).count), only stored \(storedKeys.subtracting(draftKeys.union(closingKeys)).count) \(storedKeys.subtracting(draftKeys.union(closingKeys)).sorted().prefix(4)) only facts \(draftKeys.union(closingKeys).subtracting(storedKeys).sorted().prefix(4)); sites \(sites.count); cases: facts \(cases.count) (\(draftCaseKeys.count) keys), stored own \(places.cases.filter { $0.passedUp == nil }.count) (\(storedCaseKeys.count) keys), keys only in facts \(draftCaseKeys.subtracting(storedCaseKeys).sorted().prefix(3)), only stored \(storedCaseKeys.subtracting(draftCaseKeys).sorted().prefix(3)); variants \(world.variantCount), declarations \(world.declarationCount)",
		]
	}
}
