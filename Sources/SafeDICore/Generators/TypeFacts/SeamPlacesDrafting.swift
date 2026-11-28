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
	/// The least route from the seam's root to the owner level in source order, root first, the owner last: what names
	/// the case, never the order a walk reached it in. Empty for a case passed up.
	let namingRoute: [SeamPlacesLevelID]
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
				cases.append(SeamPlacesCaseDraft(owner: site.owner, isBuiltInSendableFunction: isSendable, siteOpensSendableFunction: isSendableHole, sites: [site], passedUp: nil, firstCasePresentingSamePlaces: nil, namingRoute: []))
			}
		}
		/// Where the property an edge builds is declared, which orders routes in source order: a fill's is none, after
		/// every declared one.
		func declaredProperty(of level: SeamPlacesLevelID) -> (location: Dependency.DeclarationLocation?, label: String) {
			let declaration = world.declaration(of: level.variant)
			let targets = world.edges(from: declaration)
			let target = world.graph.nodes[Int(targets[targets.startIndex + Int(level.edge)])]
			guard !target.key.isFill, let property = target.property else { return (nil, "") }
			let location = world.graph.nodes[Int(declaration)].scope.instantiable.dependencies.first { $0.property == property }?.declarationLocation
			return (location, property.label)
		}
		func precedes(_ lhs: SeamPlacesLevelID, _ rhs: SeamPlacesLevelID) -> Bool {
			let (lhsLocation, lhsLabel) = declaredProperty(of: lhs)
			let (rhsLocation, rhsLabel) = declaredProperty(of: rhs)
			guard lhsLocation == rhsLocation else {
				return Dependency.DeclarationLocation.precedesInSourceOrder(lhsLocation, rhsLocation)
			}
			return lhsLabel < rhsLabel
		}
		/// The least route to `owner` in source order: from the root down, each step the least edge from whose callee the
		/// owner's variant is still reached, so no route is listed.
		func namingRoute(to owner: SeamPlacesLevelID) -> [SeamPlacesLevelID] {
			var reachesOwner = Set([owner.variant])
			var up = [owner.variant]
			while let variant = up.popLast() {
				for parent in parentsByVariant[Int(variant)] where reachesOwner.insert(parent.variant).inserted {
					up.append(parent.variant)
				}
			}
			var route = [SeamPlacesLevelID]()
			var variant = rootVariant
			while variant != owner.variant {
				let declaration = world.declaration(of: variant)
				let callees = world.calls(of: variant)
				let steps = world.edgeFacts(from: declaration).indices.compactMap { index -> SeamPlacesLevelID? in
					let offset = index - world.edgeFacts(from: declaration).startIndex
					let callee = callees[callees.startIndex + offset]
					guard !world.edgeFacts(from: declaration)[index].isCallEdge, reachesOwner.contains(callee) else { return nil }
					return SeamPlacesLevelID(variant: variant, edge: Int32(offset))
				}
				guard let step = steps.min(by: precedes) else { return [] }
				route.append(step)
				variant = callees[callees.startIndex + Int(step.edge)]
			}
			return route + [owner]
		}
		// The cases in builder-label order: by the hole's label, and the cases of one label by their naming routes.
		let namedCases = cases.map { draftCase in
			SeamPlacesCaseDraft(
				owner: draftCase.owner,
				isBuiltInSendableFunction: draftCase.isBuiltInSendableFunction,
				siteOpensSendableFunction: draftCase.siteOpensSendableFunction,
				sites: draftCase.sites,
				passedUp: nil,
				firstCasePresentingSamePlaces: nil,
				namingRoute: namingRoute(to: draftCase.owner),
			)
		}
		func holeLabel(of draftCase: SeamPlacesCaseDraft) -> String {
			world.graph.nodes[Int(draftCase.sites[0].hole)].property?.label ?? ""
		}
		func routePrecedes(_ lhs: [SeamPlacesLevelID], _ rhs: [SeamPlacesLevelID]) -> Bool {
			for (lhsLevel, rhsLevel) in zip(lhs, rhs) where lhsLevel != rhsLevel {
				return precedes(lhsLevel, rhsLevel)
			}
			return lhs.count < rhs.count
		}
		self.cases = namedCases.sorted { lhs, rhs in
			let (lhsLabel, rhsLabel) = (holeLabel(of: lhs), holeLabel(of: rhs))
			guard lhsLabel == rhsLabel else { return lhsLabel < rhsLabel }
			guard lhs.namingRoute == rhs.namingRoute else { return routePrecedes(lhs.namingRoute, rhs.namingRoute) }
			return !lhs.isBuiltInSendableFunction && rhs.isBuiltInSendableFunction
		}
		self.levels = levels.map(withParents)
		self.closingLevels = closingLevels.map(withParents)
		self.sites = sites
		self.families = families
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
	/// The families each variant's body is built in on the routes to it that reach a place.
	let families: [SeamPlacesFamilies]
	/// The variants the walk reached, in the order it reached them.
	let variantOrder: [VariantID]
	let world: TypeFactsGraph

	/// Test only, deleted before merge: how the drafts' levels and own cases differ from `places`, the stored place graph
	/// of the same seam, a line per difference, empty where none does. A stored level is a type built before a next
	/// property, merged over every build, and a facts level one per variant and edge, so they are compared by that key.
	/// A stored level that only owns a passed-up case is the passed-up cases' (`passedUpCases()`). Where the stored graph
	/// splits a key's case per route (a ring), only the key is compared.
	func levelAndSiteDifferences(from places: SeamSignature.Places) -> [String] {
		func edgeTarget(of level: SeamPlacesLevelID) -> TypeFactsDeclaration {
			let targets = world.edges(from: world.declaration(of: level.variant))
			return world.graph.nodes[Int(targets[targets.startIndex + Int(level.edge)])]
		}
		func builtType(of variant: VariantID) -> String {
			let node = world.graph.nodes[Int(world.declaration(of: variant))]
			return node.key.isFill ? "fill" : node.scope.instantiable.concreteInstantiable.asSource
		}
		func key(of level: SeamPlacesLevelDraft) -> String {
			let next = edgeTarget(of: level.id)
			return "\(builtType(of: level.id.variant)) before \(next.key.isFill ? "fill" : next.property?.label ?? "fill")"
		}
		func storedKey(of level: SeamSignature.Places.Level) -> String {
			"\(level.key.builtType?.asSource ?? "fill") before \(level.key.nextProperty?.label ?? "fill")"
		}
		let ownerLevelsOfOwnCases = Set(places.cases.filter { $0.passedUp == nil }.map(\.ownerLevel))
		let ownerLevelsOfPassedUpCasesOnly = Set(places.cases.filter { $0.passedUp != nil }.map(\.ownerLevel)).subtracting(ownerLevelsOfOwnCases)
		var storedKeys = Set<String>()
		var passedUpKeys = Set<String>()
		for (index, level) in places.levels.enumerated() {
			if ownerLevelsOfPassedUpCasesOnly.contains(index) {
				passedUpKeys.insert(storedKey(of: level))
			} else {
				storedKeys.insert(storedKey(of: level))
			}
		}
		let draftKeys = Set((levels + closingLevels).map(key(of:)))
		var differences = [String]()
		for draftKey in draftKeys.subtracting(storedKeys).sorted() {
			differences.append("level \(draftKey): drafted, not stored")
		}
		for storedKey in storedKeys.subtracting(draftKeys).subtracting(passedUpKeys).sorted() {
			differences.append("level \(storedKey): stored, not drafted")
		}
		// The own cases, by type, hole and family, and each one's naming route where the stored graph holds one case of it.
		func caseKey(type: String, hole: String, isSendable: Bool) -> String {
			"\(type) before \(hole)\(isSendable ? ", @Sendable" : "")"
		}
		var storedCasesByKey = [String: [SeamSignature.Places.Case]]()
		for placeCase in places.cases where placeCase.passedUp == nil {
			let level = places.levels[placeCase.ownerLevel]
			storedCasesByKey[caseKey(type: level.key.builtType?.asSource ?? "fill", hole: level.key.nextProperty?.label ?? "fill", isSendable: placeCase.isBuiltInSendableFunction), default: []].append(placeCase)
		}
		var draftCaseKeys = Set<String>()
		for draftCase in cases {
			let hole = world.graph.nodes[Int(draftCase.sites[0].hole)]
			let draftKey = caseKey(type: builtType(of: draftCase.owner.variant), hole: hole.property?.label ?? "fill", isSendable: draftCase.isBuiltInSendableFunction)
			draftCaseKeys.insert(draftKey)
			guard let storedCases = storedCasesByKey[draftKey] else {
				differences.append("case \(draftKey): drafted, not stored")
				continue
			}
			guard storedCases.count == 1 else { continue }
			let draftRoute = draftCase.namingRoute.dropLast().map { edgeTarget(of: $0).property?.label ?? "fill" }
			let storedRoute = storedCases[0].namingRoute.flatMap { places.levels[$0].pathSegment.map(\.label) }
			if draftRoute != storedRoute {
				differences.append("case \(draftKey): named by \(draftRoute.joined(separator: ".")) drafted, \(storedRoute.joined(separator: ".")) stored")
			}
		}
		for storedKey in Set(storedCasesByKey.keys).subtracting(draftCaseKeys).sorted() {
			differences.append("case \(storedKey): stored, not drafted")
		}
		return differences
	}
}
