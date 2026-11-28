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

/// The routes a case of a family is named by: those that open no `@Sendable` function, those that open one, or, for a
/// case already in one, every route.
enum SeamPlacesRouteFamily: Hashable {
	case plain
	case opensSendableFunction
	case either
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
		let rootVariant = world.rootVariant(0)
		let (buildsInLine, closesCycle) = Self.routeFold(of: world)
		// Which variants hold a place beneath them on a route, and which a call that closes a cycle: a fold up the calls
		// that build in line, from the variants whose own edges hold one.
		var holdsPlace = [Bool](repeating: false, count: variantCount)
		var holdsClosingCall = [Bool](repeating: false, count: variantCount)
		var callers = [[VariantID]](repeating: [], count: variantCount)
		for variant in 0..<VariantID(variantCount) {
			let declaration = world.declaration(of: variant)
			let targets = world.edges(from: declaration)
			let callOffset = world.variants.callOffset(of: Int(variant))
			for (index, (target, callee)) in zip(targets, world.calls(of: variant)).enumerated() {
				if closesCycle[callOffset + index] {
					holdsClosingCall[Int(variant)] = true
				}
				if buildsInLine[callOffset + index] {
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
		var pending = [rootVariant]
		visited[Int(rootVariant)] = true
		while let variant = pending.popLast() {
			order.append(variant)
			let declaration = world.declaration(of: variant)
			let targets = world.edges(from: declaration)
			let facts = world.edgeFacts(from: declaration)
			let callees = world.calls(of: variant)
			let callOffset = world.variants.callOffset(of: Int(variant))
			let edgeIndices = facts.indices.sorted { facts[$0].buildPosition < facts[$1].buildPosition }
			var children = [VariantID]()
			for edgeIndex in edgeIndices {
				let edge = facts[edgeIndex]
				let callee = callees[callees.startIndex + edgeIndex - facts.startIndex]
				let target = targets[targets.startIndex + edgeIndex - facts.startIndex]
				let isInLine = buildsInLine[callOffset + edgeIndex - facts.startIndex]
				let isPlace = isInLine && isPlaceEdge(target: target)
				let leadsToPlace = isInLine && holdsPlace[Int(callee)]
				let leadsToClosingCall = closesCycle[callOffset + edgeIndex - facts.startIndex] || isInLine && holdsClosingCall[Int(callee)]
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
				if isInLine {
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
			let callOffset = world.variants.callOffset(of: Int(variant))
			for (index, (edge, callee)) in zip(world.edgeFacts(from: declaration), world.calls(of: variant)).enumerated() where buildsInLine[callOffset + index] && holdsPlace[Int(callee)] {
				let reached = edge.opens.opensSendableFunction ? SeamPlacesFamilies.sendable : families[Int(variant)]
				guard !families[Int(callee)].isSuperset(of: reached) else { continue }
				families[Int(callee)].formUnion(reached)
				familyWork.append(callee)
			}
		}
		// A case per site and family: each hole edge of a variant is one owner level.
		var cases = [SeamPlacesCaseDraft]()
		for site in sites {
			// A hole held in a `@Sendable` wrapper is built in the function the wrapper opens, on every route to it.
			let isSendableHole = world.graph.nodes[Int(site.hole)].property?.propertyType.isSendable ?? false
			let siteFamilies = isSendableHole ? SeamPlacesFamilies.sendable : families[Int(site.owner.variant)]
			for (family, isSendable) in [(SeamPlacesFamilies.plain, false), (.sendable, true)] where siteFamilies.contains(family) {
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
		// The cases in builder-label order: by the hole's label, and the cases of one label by their naming routes.
		let namedCases = cases.map { draftCase in
			SeamPlacesCaseDraft(
				owner: draftCase.owner,
				isBuiltInSendableFunction: draftCase.isBuiltInSendableFunction,
				siteOpensSendableFunction: draftCase.siteOpensSendableFunction,
				sites: draftCase.sites,
				passedUp: nil,
				firstCasePresentingSamePlaces: nil,
				namingRoute: Self.namingRoute(to: draftCase.owner, in: world, buildsInLine: buildsInLine, family: draftCase.siteOpensSendableFunction ? .either : draftCase.isBuiltInSendableFunction ? .opensSendableFunction : .plain),
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
		// A case's name is its hole's label, named apart from the others of that label by the first of its owner's type and
		// its path's labels that tells them apart (`identifierSafeNames`), so the cases of one label go by those in turn.
		func namingKey(of draftCase: SeamPlacesCaseDraft) -> (label: String, owner: String, path: String) {
			(
				holeLabel(of: draftCase),
				world.graph.nodes[Int(world.declaration(of: draftCase.owner.variant))].scope.instantiable.concreteInstantiable.asIdentifier,
				draftCase.namingRoute.dropLast().flatMap { Self.pathLabels(of: $0, in: world) }.joined(separator: "_"),
			)
		}
		self.cases = namedCases.sorted { lhs, rhs in
			let (lhsKey, rhsKey) = (namingKey(of: lhs), namingKey(of: rhs))
			guard lhsKey == rhsKey else { return lhsKey < rhsKey }
			guard lhs.namingRoute == rhs.namingRoute else { return routePrecedes(lhs.namingRoute, rhs.namingRoute) }
			return !lhs.isBuiltInSendableFunction && rhs.isBuiltInSendableFunction
		}
		self.buildsInLine = buildsInLine
		self.closesCycle = closesCycle
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
	/// For each call of each variant, by its position among every variant's calls (`TypeFactsVariants.callOffset(of:)`):
	/// whether some route builds the callee in line there, and whether some route closes a cycle there (`routeFold(of:)`).
	/// A call can do both, where routes with and without the callee's cycle identity above reach it.
	let buildsInLine: [Bool]
	let closesCycle: [Bool]

	/// Whether some route builds the level's edge in line, and whether some route closes a cycle at it.
	func buildsInLine(_ level: SeamPlacesLevelID) -> Bool {
		buildsInLine[world.variants.callOffset(of: Int(level.variant)) + Int(level.edge)]
	}

	func closesCycle(_ level: SeamPlacesLevelID) -> Bool {
		closesCycle[world.variants.callOffset(of: Int(level.variant)) + Int(level.edge)]
	}

	/// The labels a step of a route adds to a site's path: its property's, or, for a fill, the way from the seam it fills
	/// to the hole's owner, then the hole's property.
	static func pathLabels(of level: SeamPlacesLevelID, in world: TypeFactsGraph) -> [String] {
		let declaration = world.declaration(of: level.variant)
		let targets = world.edges(from: declaration)
		let target = world.graph.nodes[Int(targets[targets.startIndex + Int(level.edge)])]
		let label = target.property?.label.spelledWithoutBackticks ?? ""
		let edge = world.graph.edgeOffset(of: Int(declaration)) + Int(level.edge)
		guard target.key.isFill else { return [label] }
		// The fills are in edge order, so the edge's fill is found by halving.
		var low = 0
		var high = world.fills.count
		while low < high {
			let middle = (low + high) / 2
			if Int(world.fills[middle].edge) < edge {
				low = middle + 1
			} else {
				high = middle
			}
		}
		let fill = world.fills[low]
		// A fill's node is both the walk's fill, whose segment is the way from the seam it fills to the hole's owner
		// (`SeamSignature.Hole.pathBeforePropertyInItsFill`), and what the fill builds for the hole's property.
		return world.fillSitePathLabels[Int(fill.sitePathStart)..<Int(fill.sitePathStart + fill.sitePathCount)].map { world.labelTexts[Int($0)].spelledWithoutBackticks } + [label]
	}

	/// The route that names a case owned by `owner`, root first, `owner` last: of the routes of `family` from the seam's root
	/// down the calls that build in line, the one whose labels, joined with `_`, sort first, as the builder of the site at the end of
	/// it is named and the case is named by its first site in builder-label order (`Hole.pathLabels(of:)`); routes alike
	/// in their labels go by source order. Found by the least suffix from each variant down to the owner, which a common
	/// prefix leaves least, so no route is listed. Empty where no route reaches the owner.
	static func namingRoute(to owner: SeamPlacesLevelID, in world: TypeFactsGraph, buildsInLine: [Bool], family: SeamPlacesRouteFamily) -> [SeamPlacesLevelID] {
		/// Where a property is declared, which breaks a tie of labels in source order.
		func declarationLocation(of level: SeamPlacesLevelID) -> Dependency.DeclarationLocation? {
			let declaration = world.declaration(of: level.variant)
			let targets = world.edges(from: declaration)
			let target = world.graph.nodes[Int(targets[targets.startIndex + Int(level.edge)])]
			guard !target.key.isFill, let property = target.property else { return nil }
			return world.graph.nodes[Int(declaration)].scope.instantiable.dependencies.first { $0.property == property }?.declarationLocation
		}
		struct Best {
			let suffix: String
			/// The route's steps from the variant down to the owner, the owner's own edge left out.
			let steps: [SeamPlacesLevelID]
		}
		struct Visit: Hashable {
			let variant: VariantID
			let family: SeamPlacesRouteFamily
		}
		var best = [Visit: Best?]()
		var onRoute = Set<Visit>()
		/// The least route from `variant` down to the owner, and whether finding it cut a loop, which leaves the answer
		/// one of the routes the visit could take from where it was reached, so it is not kept for other visits.
		func least(from variant: VariantID, family: SeamPlacesRouteFamily) -> (best: Best?, cutsLoop: Bool) {
			if variant == owner.variant {
				switch family {
				case .plain, .either:
					return (Best(suffix: "", steps: []), false)
				case .opensSendableFunction:
					return (nil, false)
				}
			}
			let visit = Visit(variant: variant, family: family)
			if let known = best[visit] {
				return (known, false)
			}
			// A variant met again on the route it is reached by would loop: no least route passes it twice.
			guard onRoute.insert(visit).inserted else { return (nil, true) }
			defer { onRoute.remove(visit) }
			var cutsLoop = false
			let callees = world.calls(of: variant)
			let callOffset = world.variants.callOffset(of: Int(variant))
			let edges = world.edgeFacts(from: world.declaration(of: variant))
			var found: Best?
			for (index, callee) in callees.enumerated() where buildsInLine[callOffset + index] {
				let familyBelow: SeamPlacesRouteFamily
				if edges[edges.startIndex + index].opens.opensSendableFunction {
					switch family {
					case .plain:
						continue
					case .opensSendableFunction, .either:
						familyBelow = .either
					}
				} else {
					familyBelow = family
				}
				let reached = least(from: callee, family: familyBelow)
				cutsLoop = cutsLoop || reached.cutsLoop
				guard let below = reached.best else { continue }
				let step = SeamPlacesLevelID(variant: variant, edge: Int32(index))
				let labels = pathLabels(of: step, in: world).joined(separator: "_")
				let suffix = callee == owner.variant ? labels : "\(labels)_\(below.suffix)"
				if let current = found {
					guard suffix < current.suffix || suffix == current.suffix && Dependency.DeclarationLocation.precedesInSourceOrder(declarationLocation(of: step), declarationLocation(of: current.steps[0])) else { continue }
				}
				found = Best(suffix: suffix, steps: [step] + below.steps)
			}
			if !cutsLoop {
				best[visit] = found
			}
			return (found, cutsLoop)
		}
		guard let found = least(from: world.rootVariant(0), family: family).best else { return [] }
		return found.steps + [owner]
	}

	/// Where each call builds its callee in line and where it closes a cycle, as the tree unfolds it
	/// (`TypeFactsGraph.unfolded`): a call closes where its callee's cycle identity is on the route above it, the route
	/// beneath a fill starting again from the fills above it. An edge off every cycle (`isCallEdge` false) only builds in
	/// line. Routes are folded down the calls that build in line, keeping for each variant the identities some route has
	/// above it and those every route has, so the fold grows with the variants and identities, never with the routes.
	static func routeFold(of world: TypeFactsGraph) -> (buildsInLine: [Bool], closesCycle: [Bool]) {
		struct Above: Equatable {
			/// The identities on some route above, and on every route above (`nil` before any route arrives).
			var some = Set<CycleID>()
			var every: Set<CycleID>?
			/// The same, of the fills above alone, which the route beneath a fill starts again from.
			var someFills = Set<CycleID>()
			var everyFill: Set<CycleID>?

			mutating func meet(some: Set<CycleID>, every: Set<CycleID>, someFills: Set<CycleID>, everyFill: Set<CycleID>) -> Bool {
				let before = self
				self.some.formUnion(some)
				self.every = self.every.map { $0.intersection(every) } ?? every
				self.someFills.formUnion(someFills)
				self.everyFill = self.everyFill.map { $0.intersection(everyFill) } ?? everyFill
				return self != before
			}
		}
		let callCount = (0..<world.variantCount).reduce(0) { $0 + world.calls(of: VariantID($1)).count }
		var buildsInLine = [Bool](repeating: false, count: callCount)
		var closesCycle = [Bool](repeating: false, count: callCount)
		var above = [Above](repeating: Above(), count: world.variantCount)
		let rootVariant = world.rootVariant(0)
		_ = above[Int(rootVariant)].meet(some: [], every: [], someFills: [], everyFill: [])
		var pending = [rootVariant]
		var isPending = [Bool](repeating: false, count: world.variantCount)
		isPending[Int(rootVariant)] = true
		while let variant = pending.popLast() {
			isPending[Int(variant)] = false
			let declaration = world.declaration(of: variant)
			let own = world.cycle(of: declaration)
			let state = above[Int(variant)]
			let callOffset = world.variants.callOffset(of: Int(variant))
			for (index, (edge, callee)) in zip(world.edgeFacts(from: declaration), world.calls(of: variant)).enumerated() {
				// What the callee has above it on the routes through this call.
				let (some, every, someFills, everyFill): (Set<CycleID>, Set<CycleID>, Set<CycleID>, Set<CycleID>)
				if edge.isFill {
					let target = world.cycle(of: world.declaration(of: callee))
					(some, every, someFills, everyFill) = (state.someFills, state.everyFill ?? [], state.someFills.union([target]), (state.everyFill ?? []).union([target]))
				} else {
					(some, every, someFills, everyFill) = (state.some.union([own]), (state.every ?? []).union([own]), state.someFills, state.everyFill ?? [])
				}
				let identity = world.cycle(of: world.declaration(of: callee))
				let inLine = !edge.isCallEdge || !every.contains(identity)
				if edge.isCallEdge, some.contains(identity) {
					closesCycle[callOffset + index] = true
				}
				guard inLine else { continue }
				buildsInLine[callOffset + index] = true
				if above[Int(callee)].meet(some: some, every: every, someFills: someFills, everyFill: everyFill), !isPending[Int(callee)] {
					isPending[Int(callee)] = true
					pending.append(callee)
				}
			}
		}
		return (buildsInLine, closesCycle)
	}

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
		// A fill's declaration builds the fulfiller's scope, which the stored graph holds as a level of its own beneath the
		// fill's, which builds no type and is followed by the fill's property.
		func builtType(of variant: VariantID) -> String {
			world.graph.nodes[Int(world.declaration(of: variant))].scope.instantiable.concreteInstantiable.asSource
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
		var draftKeys = Set(levels.map(key(of:)))
		let closingKeys = Set(closingLevels.map(key(of:))).subtracting(draftKeys)
		draftKeys.formUnion(closingKeys)
		for level in levels + closingLevels {
			let node = world.graph.nodes[Int(world.declaration(of: level.id.variant))]
			if node.key.isFill, let property = node.property {
				draftKeys.insert("fill before \(property.label)")
			}
		}
		var differences = [String]()
		for draftKey in draftKeys.subtracting(storedKeys).sorted() {
			differences.append("level \(draftKey): drafted\(closingKeys.contains(draftKey) ? " on a route to a closing call only" : ""), not stored")
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
		let caseKeys = cases.map { draftCase in
			caseKey(type: builtType(of: draftCase.owner.variant), hole: world.graph.nodes[Int(draftCase.sites[0].hole)].property?.label ?? "fill", isSendable: draftCase.isBuiltInSendableFunction)
		}
		var draftCountByKey = [String: Int]()
		for draftKey in caseKeys {
			draftCountByKey[draftKey, default: 0] += 1
		}
		for (draftKey, draftCount) in draftCountByKey.sorted(by: { $0.key < $1.key }) {
			guard let storedCount = storedCasesByKey[draftKey]?.count, storedCount != draftCount else { continue }
			differences.append("case \(draftKey): \(draftCount) drafted, \(storedCount) stored")
		}
		let draftCaseKeys = Set(caseKeys)
		for (draftCase, draftKey) in zip(cases, caseKeys) {
			guard let storedCases = storedCasesByKey[draftKey] else {
				differences.append("case \(draftKey): drafted, not stored")
				continue
			}
			guard storedCases.count == 1, draftCountByKey[draftKey] == 1 else { continue }
			let draftRoute = draftCase.namingRoute.dropLast().flatMap { Self.pathLabels(of: $0, in: world) }
			let storedRoute = storedCases[0].namingRoute.flatMap { places.levels[$0].pathSegment.map(\.label.spelledWithoutBackticks) }
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
