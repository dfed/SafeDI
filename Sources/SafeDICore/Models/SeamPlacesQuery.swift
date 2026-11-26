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

extension SeamSignature.Places {
	/// A route from the seam's root to a case's owner level: the levels on it, root first.
	public struct Route: Hashable, Sendable {
		public init(levels: [Int]) {
			self.levels = levels
		}

		public let levels: [Int]
	}

	/// The questions a case's places ask of the graph, each answered over every route to the case's owner level in the
	/// case's family, and memoized per level, label and what the route has crossed, so one query serves every case and
	/// label of one signature.
	///
	/// Every walk goes up the graph with an explicit stack, since a seam's tree can be deeper than a concurrency thread's
	/// stack allows a recursive walk to go (`cycle-generation.md`, "Walks"). A lazy cycle can build one level variant again
	/// beneath itself, so the graph can hold a cycle: a walk that meets a level it is still walking takes nothing from it at
	/// first, and then computes the levels of that cycle again until none of their answers grows, which is the union over
	/// every route, however often it goes around (`cycleRevisits` counts the meetings).
	///
	/// It holds its memos for as long as its owner keeps it: one computation of a seam's holes, or one caller's reads of a
	/// signature.
	public final class Query {
		public init(of places: SeamSignature.Places) {
			self.places = places
			lastDeclarationIndexByLabel = places.levels.map { level in
				var indexByLabel = [String: Int]()
				for (index, declaration) in level.declarations.enumerated() {
					indexByLabel[declaration.field.property.label] = index
				}
				return indexByLabel
			}
			firstReentryIndexByLabel = places.levels.map { level in
				var indexByLabel = [String: Int]()
				for (index, reentry) in level.cycleReentries.enumerated() where indexByLabel[reentry.property.label] == nil {
					indexByLabel[reentry.property.label] = index
				}
				return indexByLabel
			}
			(plainReach, openReach) = Self.reaches(of: places.levels)
		}

		public let places: SeamSignature.Places
		/// How often a walk met a level it was still walking: a cycle in the graph.
		public var cycleRevisits: Int {
			answerFold.revisits + hiddenFold.revisits + nearestFold.revisits + reentryFold.revisits
		}

		// MARK: Answers

		/// What the places of the case at `caseIndex` read of `label`: one answer per distinct answer over the routes to the
		/// case, the answer on the case's representative route first.
		public func answers(ofLabel label: String, at caseIndex: Int) -> [SeamSignature.Places.Answer] {
			let placeCase = places.cases[caseIndex]
			guard let start = startState(of: placeCase) else { return [] }
			let crossedAtSite = placeCase.siteOpensSendableFunction
			let answers = answerFold.value(
				of: AnswerKey(level: placeCase.ownerLevel, label: label, state: start, crossed: crossedAtSite),
				direct: directAnswers(of:),
				children: answerChildren(of:),
			)
			guard crossedAtSite else { return answers }
			return answers.map { $0.crossingFunction(at: SeamSignature.Places.Answer.siteFunction) }
		}

		/// The fields the places of the case at `caseIndex` carry, the first per label in label order (`labels(reaching:)`),
		/// as the scope struct of the case's first place declares them.
		public func fields(of caseIndex: Int) -> [SeamSignature.Hole.Field] {
			labels(reaching: caseIndex).compactMap { label in
				answers(ofLabel: label, at: caseIndex).lazy.compactMap { answer -> SeamSignature.Hole.Field? in
					guard case let .field(level, declaration) = answer else { return nil }
					return self.places.declaration(level: level, declaration: declaration).field
				}.first
			}
		}

		/// The declarations the places of the case at `caseIndex` carry no field of, every distinct one per label, in label
		/// order.
		public func uncarriedDeclarations(of caseIndex: Int) -> [SeamSignature.Hole.UncarriedDeclaration] {
			labels(reaching: caseIndex).flatMap { label in
				answers(ofLabel: label, at: caseIndex).compactMap { uncarriedDeclaration(of: $0, at: caseIndex) }
			}
		}

		/// The uncarried declaration `answer` is for a place of the case at `caseIndex`, or `nil` for a field or the caller's own.
		/// Its `placesInTree` is left empty: the cases are in the declaration's `buildability`.
		public func uncarriedDeclaration(of answer: SeamSignature.Places.Answer, at caseIndex: Int) -> SeamSignature.Hole.UncarriedDeclaration? {
			let reason: SeamSignature.Hole.UncarriedDeclaration.Reason
			let builtAfter: Property?
			let declaration: SeamSignature.Places.Declaration
			switch answer {
			case .field, .callersOwn:
				return nil
			case let .uncarried(level, index):
				declaration = places.declaration(level: level, declaration: index)
				reason = declaration.reason
				builtAfter = declaration.builtAfter
			case let .boundOutsideSendableFunction(level, index, functionLevel):
				declaration = places.declaration(level: level, declaration: index)
				let function = sendableFunction(at: functionLevel, of: caseIndex)
				reason = .boundOutsideSendableFunction(functionProperty: function.property, function: function.function, isForwarded: declaration.isForwarded, cycleParameter: declaration.cycleParameterOrigin, alias: declaration.alias)
				builtAfter = nil
			}
			var uncarried = SeamSignature.Hole.UncarriedDeclaration(
				property: declaration.field.property,
				declaringType: declaration.field.declaringType,
				declarationLocation: declaration.field.declarationLocation,
				parameterTakingType: declaration.field.parameterTakingType,
				builtAfter: builtAfter,
				reason: reason,
				isBoundFromCallersArgument: answer.isBoundOutsideSendableFunction && declaration.isBoundFromCallersArgument,
			)
			if let buildability = declaration.buildability {
				uncarried.isBuildableAboveSeam = true
				uncarried.labelsHeldAboveSeam = Set(buildability.labelsHeldAboveSeam)
			}
			return uncarried
		}

		/// The `@Sendable` function opened at `functionLevel` on a route to the case at `caseIndex`.
		private func sendableFunction(at functionLevel: Int, of caseIndex: Int) -> SeamSignature.Places.SendableFunctionOpened {
			if functionLevel != SeamSignature.Places.Answer.siteFunction, let opened = places.levels[functionLevel].opensSendableFunction {
				opened
			} else {
				// A `Sendable` wrapper the seam builds around the builder is a function of its own, which binds nothing.
				SeamSignature.Places.SendableFunctionOpened(property: sitePropertyOrPlaceholder(of: caseIndex), function: .other)
			}
		}

		private func sitePropertyOrPlaceholder(of caseIndex: Int) -> Property {
			places.levels[places.cases[caseIndex].ownerLevel].key.nextProperty ?? Property(label: "", typeDescription: .void(.tuple))
		}

		/// The labels any level on a route to the case at `caseIndex` declares: those of the representative route in the order
		/// it binds them, a label bound again moving to its later place, then those only other routes declare, in the order a
		/// walk of the routes meets them.
		public func labels(reaching caseIndex: Int) -> [String] {
			var labels = [String]()
			if let route = representativeRoute(of: caseIndex) {
				for level in route.levels {
					for declaration in places.levels[level].declarations {
						let label = declaration.field.property.label
						labels.removeAll { $0 == label }
						labels.append(label)
					}
				}
			}
			var seen = Set(labels)
			for level in levelsReaching(caseIndex) {
				for declaration in places.levels[level].declarations where seen.insert(declaration.field.property.label).inserted {
					labels.append(declaration.field.property.label)
				}
			}
			return labels
		}

		// MARK: Cycle re-entry

		/// For `label`, what a cycle that re-enters a scope on a route to the case at `caseIndex` hands the type built again,
		/// every distinct one over the routes: the outermost re-entered level between the place and the nearest declaration of
		/// the label. `nil` stands for a route on which none does.
		public func cycleReentryDeclarations(ofLabel label: String, at caseIndex: Int) -> [SeamSignature.Hole.CycleReentryDeclaration?] {
			let placeCase = places.cases[caseIndex]
			guard let start = startState(of: placeCase) else { return [] }
			// The place's own label is never re-entered: every call is made inside a tree that builds a declaration of it.
			guard places.levels[placeCase.ownerLevel].key.nextProperty?.label != label else { return [nil] }
			let reached = reentryFold.value(
				of: StateKey(level: placeCase.ownerLevel, label: label, state: start),
				direct: { [unowned self] key in
					if lastDeclarationIndexByLabel[key.level][key.label] != nil || places.levels[key.level].parents.isEmpty {
						return isValid(key.level, key.state) ? [.none] : []
					}
					return nil
				},
				children: { [unowned self] key in
					let own = firstReentryIndexByLabel[key.level][key.label]
					return transitions(from: key.level, state: key.state).map { parent, state in
						(StateKey(level: parent, label: key.label, state: state), { element in
							guard case .none = element, let own else { return element }
							return .reentry(level: key.level, index: own, declaringParent: parent)
						})
					}
				},
			)
			return reached.map { element in
				guard case let .reentry(level, index, declaringParent) = element else { return nil }
				let reentry = places.levels[level].cycleReentries[index]
				return SeamSignature.Hole.CycleReentryDeclaration(
					property: reentry.property,
					declaringType: reentry.declaringType,
					declarationLocation: reentry.declarationLocation,
					parameterTakingType: reentry.parameterTakingType,
					closedOnProperty: reentry.closedOnProperty,
					closedOnBuiltType: reentry.closedOnBuiltType,
					closedOnDeclaringType: declaringType(ofPropertyAfter: declaringParent),
					reenteringType: reentry.reenteringType,
				)
			}
		}

		/// The cycle re-entry declarations of the case at `caseIndex`, every distinct one per label, labels in the order the
		/// routes' levels first re-enter them.
		public func cycleReentryDeclarations(of caseIndex: Int) -> [SeamSignature.Hole.CycleReentryDeclaration] {
			var labels = [String]()
			var seen = Set<String>()
			for level in levelsReaching(caseIndex) {
				for reentry in places.levels[level].cycleReentries where seen.insert(reentry.property.label).inserted {
					labels.append(reentry.property.label)
				}
			}
			return labels.flatMap { cycleReentryDeclarations(ofLabel: $0, at: caseIndex).compactMap(\.self) }
		}

		/// The type that declares the property of the level after `level`: the type it builds, or the owner of the hole a
		/// fill fills.
		private func declaringType(ofPropertyAfter level: Int) -> TypeDescription {
			let key = places.levels[level].key
			return key.builtType ?? places.levels[level].fillOwnerType ?? .void(.tuple)
		}

		// MARK: Declarations hidden by fields

		/// The declarations a fill's field bound from a parameter of the filled seam hides from the places of the case at
		/// `caseIndex`, for `label`, where that field is the nearest declaration of the label and a field there: the nearest
		/// declaration of another property above it, every distinct one over the routes.
		public func declarationsHiddenByFields(ofLabel label: String, at caseIndex: Int) -> [SeamSignature.Hole.DeclarationHiddenByField] {
			let placeCase = places.cases[caseIndex]
			guard let start = startState(of: placeCase), !placeCase.siteOpensSendableFunction else { return [] }
			let hidden = hiddenFold.value(
				of: AnswerKey(level: placeCase.ownerLevel, label: label, state: start, crossed: false),
				direct: { [unowned self] key in
					if let index = lastDeclarationIndexByLabel[key.level][key.label] {
						guard isValid(key.level, key.state) else { return [] }
						let declaration = places.declaration(level: key.level, declaration: index)
						guard declaration.isBoundBeforeNextProperty, let hiding = declaration.fillFieldHiding else { return [] }
						return reached(before: index, at: key.level, state: key.state).compactMap { reached in
							guard case let .declaration(level, hiddenIndex) = reached else { return nil }
							let hiddenDeclaration = places.declaration(level: level, declaration: hiddenIndex)
							guard hiddenDeclaration.field.property != declaration.field.property else { return nil }
							return HiddenElement(fieldLevel: key.level, fieldIndex: index, hiddenLevel: level, hiddenIndex: hiddenIndex, hiding: hiding.calledSeam)
						}
					}
					if places.levels[key.level].parents.isEmpty {
						return []
					}
					return nil
				},
				children: { [unowned self] key in
					// Past a `@Sendable` function, the fill's field is no field of the place.
					guard !places.levels[key.level].opensSendableFunction.isPresent else { return [] }
					return transitions(from: key.level, state: key.state).map { parent, state in
						(AnswerKey(level: parent, label: key.label, state: state, crossed: false), { $0 })
					}
				},
			)
			return hidden.map { element in
				let declaration = places.declaration(level: element.fieldLevel, declaration: element.fieldIndex)
				let hiddenDeclaration = places.declaration(level: element.hiddenLevel, declaration: element.hiddenIndex)
				let calledSeam = if case let .boundByPassingUpSeam(_, _, place) = hiddenDeclaration.reason {
					place.seamType
				} else {
					element.hiding
				}
				return SeamSignature.Hole.DeclarationHiddenByField(
					property: hiddenDeclaration.field.property,
					declaringType: hiddenDeclaration.field.declaringType,
					declarationLocation: hiddenDeclaration.field.declarationLocation,
					calledSeam: calledSeam,
					receivingSeam: declaration.fillFieldHiding?.receivingSeam ?? calledSeam,
				)
			}
		}

		/// The declarations hidden by fields of the case at `caseIndex`, in the order of its fields' labels.
		public func declarationsHiddenByFields(of caseIndex: Int) -> [SeamSignature.Hole.DeclarationHiddenByField] {
			fields(of: caseIndex).flatMap { declarationsHiddenByFields(ofLabel: $0.property.label, at: caseIndex) }
		}

		/// The nearest declaration of the label of the declaration at `index` of `level` before it, on the routes from
		/// `level` in `state`: an earlier declaration of the label at the level, or the nearest one above.
		private func reached(before index: Int, at level: Int, state: RouteState) -> [SeamSignature.Places.Reached] {
			let declarations = places.levels[level].declarations
			let label = declarations[index].field.property.label
			if let earlier = declarations[..<index].lastIndex(where: { $0.field.property.label == label }) {
				return [.declaration(level: level, declaration: earlier)]
			}
			var reached = [SeamSignature.Places.Reached]()
			var seen = Set<SeamSignature.Places.Reached>()
			for (parent, parentState) in transitions(from: level, state: state) {
				for element in nearestDeclarations(ofLabel: label, at: parent, state: parentState) where seen.insert(element).inserted {
					reached.append(element)
				}
			}
			return reached
		}

		/// The nearest declaration of `label` on each route up from `level` in `state`, or `.none` where a route declares none.
		private func nearestDeclarations(ofLabel label: String, at level: Int, state: RouteState) -> [SeamSignature.Places.Reached] {
			nearestFold.value(
				of: StateKey(level: level, label: label, state: state),
				direct: { [unowned self] key in
					if let index = lastDeclarationIndexByLabel[key.level][key.label] {
						return isValid(key.level, key.state) ? [.declaration(level: key.level, declaration: index)] : []
					}
					if places.levels[key.level].parents.isEmpty {
						return isValid(key.level, key.state) ? [.none] : []
					}
					return nil
				},
				children: { [unowned self] key in
					transitions(from: key.level, state: key.state).map { parent, state in
						(StateKey(level: parent, label: key.label, state: state), { $0 })
					}
				},
			)
		}

		// MARK: Routes

		/// The route the case at `caseIndex` is named by where a diagnostic names one place: the first route a walk up from
		/// the owner level meets, taking each level's parents in the order the places first reached them, among the routes of
		/// the case's family. `nil` only for a case no route reaches, which no computation makes.
		public func representativeRoute(of caseIndex: Int) -> Route? {
			let placeCase = places.cases[caseIndex]
			guard let start = startState(of: placeCase) else { return nil }
			if let known = representativeRouteByCase[caseIndex] {
				return known
			}
			struct Step: Hashable {
				let level: Int
				let state: RouteState
			}
			var visited: Set<Step> = [Step(level: placeCase.ownerLevel, state: start)]
			var path = [(step: Step, nextTransition: Int)]()
			path.append((Step(level: placeCase.ownerLevel, state: start), 0))
			var found: [Int]?
			while let (step, nextTransition) = path.last {
				if places.levels[step.level].parents.isEmpty {
					if isValid(step.level, step.state) {
						found = path.map(\.step.level)
						break
					}
					path.removeLast()
					continue
				}
				let transitions = transitions(from: step.level, state: step.state)
				guard nextTransition < transitions.count else {
					path.removeLast()
					continue
				}
				path[path.count - 1].nextTransition += 1
				let (parent, state) = transitions[nextTransition]
				let next = Step(level: parent, state: state)
				guard visited.insert(next).inserted else { continue }
				path.append((next, 0))
			}
			let route = found.map { Route(levels: $0.reversed()) }
			representativeRouteByCase[caseIndex] = route
			return route
		}

		/// The properties from the seam's root to the hole's property along `route`, as `Hole.sitePath` spells them.
		public func sitePath(along route: Route) -> [Property] {
			var path = route.levels.flatMap { places.levels[$0].pathSegment }
			if let owner = route.levels.last, let property = places.levels[owner].key.nextProperty {
				path.append(property)
			}
			return path
		}

		/// The types from the seam, itself excluded, to the hole's owner along `route` (`Hole.typesToOwner`).
		public func typesToOwner(along route: Route) -> [SeamSignature.Hole.PathType] {
			route.levels.flatMap { places.levels[$0].pathTypes }
		}

		/// The properties the code declares from the root to the owner's level along `route`, each read on the edge it is
		/// declared on (`Hole.declaredSitePath` but the hole's own property).
		public func declaredPathToOwner(along route: Route) -> [SeamSignature.Hole.DeclaredProperty] {
			var path = [SeamSignature.Hole.DeclaredProperty]()
			for (parent, level) in zip(route.levels, route.levels.dropFirst()) {
				guard let parentPosition = places.levels[level].parents.firstIndex(of: parent) else { continue }
				path += places.levels[level].declaredSegmentByParent[parentPosition]
			}
			return path
		}

		/// The stack the owner of a place at the end of `route` is built with, innermost first (`Hole.fillPropertyStack` and
		/// `fillConcreteTypeStack`, zipped): each property on the way up to the seam's root or to the nearest fill, a lazily
		/// instantiated one preceded by its instance, then that fill's base stack.
		public func stack(along route: Route) -> [SeamSignature.Places.StackEntry] {
			var entries = [SeamSignature.Places.StackEntry]()
			for (parent, level) in zip(route.levels, route.levels.dropFirst()).reversed() {
				guard let builtType = places.levels[level].key.builtType else {
					return entries + places.levels[level].fillBaseStack
				}
				guard let property = places.levels[parent].key.nextProperty else { continue }
				entries += Self.entries(of: property, builtAs: builtType)
			}
			if let first = route.levels.first, places.levels[first].key.builtType == nil {
				entries += places.levels[first].fillBaseStack
			}
			return entries
		}

		/// The entries `property`, built for `concreteType`, puts on the stack, innermost first: its instance just outside it
		/// where it is lazily instantiated, as `Scope.createScopeGenerator` stacks them.
		static func entries(of property: Property, builtAs concreteType: TypeDescription) -> [SeamSignature.Places.StackEntry] {
			var entries = [SeamSignature.Places.StackEntry(property: property, concreteType: concreteType)]
			if let instance = property.asLazilyInstantiatedInstanceProperty {
				entries.append(SeamSignature.Places.StackEntry(property: instance, concreteType: concreteType))
			}
			return entries
		}

		/// The route a diagnostic about `answer`, the answer the places of the case at `caseIndex` read of `label`, names its
		/// place by: of the routes of the case's family on which the places read that answer, the least by the source
		/// locations of the properties the code declares along it, root first (a route whose locations are a prefix of
		/// another's first, a location-less declaration after every located one), so neither a name nor the order in which
		/// the places were reached decides it. Found from the roots down, one location at a time, over the levels that lead to
		/// the answer, so no route is listed; a level a route has already passed is not entered again. `nil` when no route
		/// reads `answer`.
		public func representativeRoute(of caseIndex: Int, ofLabel label: String, answer: SeamSignature.Places.Answer) -> Route? {
			let placeCase = places.cases[caseIndex]
			guard let start = startState(of: placeCase) else { return nil }
			// A step of a walk up from the owner: before the nearest declaration of the label, with the innermost function
			// crossed so far, or past it, where only the family matters.
			struct Node: Hashable {
				let level: Int
				let state: RouteState
				let isPastDeclaration: Bool
				let function: Int?
			}
			let startNode = Node(level: placeCase.ownerLevel, state: start, isPastDeclaration: false, function: placeCase.siteOpensSendableFunction ? SeamSignature.Places.Answer.siteFunction : nil)
			// The walk up, each node with the nodes it leads up to; a node that decides the answer leads to the same level past
			// the declaration, when the answer is `answer`.
			var parentsByNode = [Node: [Node]]()
			var nodesInOrderReached = [startNode]
			var roots = [Node]()
			var toVisit = [startNode]
			var seen: Set<Node> = [startNode]
			while let node = toVisit.popLast() {
				var next = [Node]()
				if !node.isPastDeclaration, let decided = decidedAnswer(at: node.level, label: label, state: node.state, function: node.function) {
					if decided == answer {
						next.append(Node(level: node.level, state: node.state, isPastDeclaration: true, function: nil))
					}
				} else if places.levels[node.level].parents.isEmpty {
					if isValid(node.level, node.state) {
						roots.append(node)
					}
				} else {
					let opens = places.levels[node.level].opensSendableFunction.isPresent
					for (parent, state) in transitions(from: node.level, state: node.state) {
						let function = node.isPastDeclaration ? nil : node.function ?? (opens ? node.level : nil)
						next.append(Node(level: parent, state: state, isPastDeclaration: node.isPastDeclaration, function: function))
					}
				}
				parentsByNode[node] = next
				for parent in next where seen.insert(parent).inserted {
					nodesInOrderReached.append(parent)
					toVisit.append(parent)
				}
			}
			// The nodes that lead up to a root reached past the answer's declaration, or that are such a root: only they are
			// on a route that reads `answer`.
			var childrenByNode = [Node: [Node]]()
			for node in nodesInOrderReached {
				for parent in parentsByNode[node] ?? [] {
					childrenByNode[parent, default: []].append(node)
				}
			}
			var onRoute = Set<Node>()
			var toMark = roots.filter(\.isPastDeclaration)
			while let node = toMark.popLast() {
				guard onRoute.insert(node).inserted else { continue }
				toMark += childrenByNode[node] ?? []
			}
			guard onRoute.contains(startNode) else { return nil }
			// From the roots down, one location at a time: every walk in `frontier` has read the same locations, and a walk
			// holds the locations of the edge it is on that it has not read yet.
			struct Walk {
				var levels: [Int]
				var node: Node
				var pending: ArraySlice<Dependency.DeclarationLocation?>
			}
			var entered = Set<Node>()
			var frontier = [Walk]()
			for root in roots where onRoute.contains(root) && entered.insert(root).inserted {
				frontier.append(Walk(levels: [root.level], node: root, pending: []))
			}
			while !frontier.isEmpty {
				// Each walk with nothing pending goes on down each of its edges; a step to the same level past or before the
				// declaration reads nothing.
				var expanded = [Walk]()
				var index = 0
				while index < frontier.count {
					let walk = frontier[index]
					index += 1
					guard walk.pending.isEmpty else {
						expanded.append(walk)
						continue
					}
					if walk.node == startNode {
						return Route(levels: walk.levels)
					}
					for child in childrenByNode[walk.node] ?? [] where onRoute.contains(child) && entered.insert(child).inserted {
						if child.level == walk.node.level, child.isPastDeclaration != walk.node.isPastDeclaration {
							frontier.append(Walk(levels: walk.levels, node: child, pending: []))
						} else {
							let parentPosition = places.levels[child.level].parents.firstIndex(of: walk.node.level) ?? 0
							let segment = places.levels[child.level].declaredSegmentByParent[parentPosition].map(\.declarationLocation)
							frontier.append(Walk(levels: walk.levels + [child.level], node: child, pending: segment[...]))
						}
					}
				}
				// Keep the walks whose next location sorts first.
				guard let least = expanded.lazy.compactMap(\.pending.first).min(by: Dependency.DeclarationLocation.precedesInSourceOrder) else { return nil }
				frontier = expanded.compactMap { walk in
					guard let next = walk.pending.first, next == least else { return nil }
					var advanced = walk
					advanced.pending = walk.pending.dropFirst()
					return advanced
				}
			}
			return nil
		}

		/// The answer the declaration of `label` at `level` gives a walk that reached it in `state`, having crossed `function`
		/// first, or `nil` where `level` declares no `label`. A root that declares none gives the caller's own.
		private func decidedAnswer(at level: Int, label: String, state: RouteState, function: Int?) -> SeamSignature.Places.Answer? {
			guard let index = lastDeclarationIndexByLabel[level][label] else {
				return places.levels[level].parents.isEmpty && isValid(level, state) ? .callersOwn : nil
			}
			let declaration = places.declaration(level: level, declaration: index)
			guard declaration.isBoundBeforeNextProperty else { return .uncarried(level: level, declaration: index) }
			guard let function else { return .field(level: level, declaration: index) }
			return declaration.isSeamParameter ? .callersOwn : .boundOutsideSendableFunction(level: level, declaration: index, functionLevel: function)
		}

		/// The levels on any route to the case at `caseIndex` in its family, in the order a walk up from the owner meets them.
		public func levelsReaching(_ caseIndex: Int) -> [Int] {
			let placeCase = places.cases[caseIndex]
			guard let start = startState(of: placeCase) else { return [] }
			struct Step: Hashable {
				let level: Int
				let state: RouteState
			}
			var levels = [Int]()
			var seenLevels = Set<Int>()
			var visited = Set<Step>()
			var toVisit = [Step(level: placeCase.ownerLevel, state: start)]
			while let step = toVisit.popLast() {
				guard visited.insert(step).inserted else { continue }
				if seenLevels.insert(step.level).inserted {
					levels.append(step.level)
				}
				for (parent, state) in transitions(from: step.level, state: step.state).reversed() {
					toVisit.append(Step(level: parent, state: state))
				}
			}
			return levels
		}

		// MARK: Private

		private let lastDeclarationIndexByLabel: [[String: Int]]
		private let firstReentryIndexByLabel: [[String: Int]]
		/// Per level, whether some route from the seam's root reaches it with no level on it, the level included, opening a
		/// `@Sendable` function.
		private let plainReach: [Bool]
		/// Per level, whether some route from the seam's root reaches it with some level on it, the level included, opening one.
		private let openReach: [Bool]
		private var answerFold = Fold<AnswerKey, SeamSignature.Places.Answer>()
		private var hiddenFold = Fold<AnswerKey, HiddenElement>()
		private var nearestFold = Fold<StateKey, SeamSignature.Places.Reached>()
		private var reentryFold = Fold<StateKey, ReentryElement>()
		private var representativeRouteByCase = [Int: Route?]()

		/// What a walk up from a case's owner still requires of the rest of its route to keep it in the case's family.
		private enum RouteState: Hashable {
			/// A plain place: no level on the route may open a `@Sendable` function.
			case plainOnly
			/// A place of the `@Sendable` family that no function encloses yet: some level above must open one.
			case needsOpenAbove
			/// Any route will do.
			case any
		}

		private struct AnswerKey: Hashable {
			let level: Int
			let label: String
			let state: RouteState
			/// Whether a `@Sendable` function lies between the level and the place.
			let crossed: Bool
		}

		private struct StateKey: Hashable {
			let level: Int
			let label: String
			let state: RouteState
		}

		private struct HiddenElement: Hashable {
			let fieldLevel: Int
			let fieldIndex: Int
			let hiddenLevel: Int
			let hiddenIndex: Int
			let hiding: TypeDescription
		}

		private enum ReentryElement: Hashable {
			case none
			case reentry(level: Int, index: Int, declaringParent: Int)
		}

		private func startState(of placeCase: SeamSignature.Places.Case) -> RouteState? {
			if !placeCase.isBuiltInSendableFunction {
				return plainReach[placeCase.ownerLevel] && !placeCase.siteOpensSendableFunction ? .plainOnly : nil
			}
			if placeCase.siteOpensSendableFunction {
				return .any
			}
			return openReach[placeCase.ownerLevel] ? .needsOpenAbove : nil
		}

		/// Whether a route that ends its walk at `level`, in `state`, is of the case's family.
		private func isValid(_ level: Int, _ state: RouteState) -> Bool {
			switch state {
			case .plainOnly, .any:
				true
			case .needsOpenAbove:
				openReach[level]
			}
		}

		/// The parents a walk at `level` in `state` may go on to, each with the state there, in the order of `parents`.
		private func transitions(from level: Int, state: RouteState) -> [(parent: Int, state: RouteState)] {
			let opens = places.levels[level].opensSendableFunction.isPresent
			let parents = places.levels[level].parents
			switch state {
			case .plainOnly:
				guard !opens else { return [] }
				return parents.filter { plainReach[$0] }.map { ($0, .plainOnly) }
			case .needsOpenAbove:
				if opens {
					return parents.map { ($0, .any) }
				}
				return parents.filter { openReach[$0] }.map { ($0, .needsOpenAbove) }
			case .any:
				return parents.map { ($0, .any) }
			}
		}

		private func directAnswers(of key: AnswerKey) -> [SeamSignature.Places.Answer]? {
			if let index = lastDeclarationIndexByLabel[key.level][key.label] {
				guard isValid(key.level, key.state) else { return [] }
				let declaration = places.declaration(level: key.level, declaration: index)
				guard declaration.isBoundBeforeNextProperty else { return [.uncarried(level: key.level, declaration: index)] }
				guard key.crossed else { return [.field(level: key.level, declaration: index)] }
				// A parameter of the seam is the caller's own, which a fill reads from its own scope.
				return declaration.isSeamParameter ? [.callersOwn] : [.boundOutsideSendableFunction(level: key.level, declaration: index, functionLevel: SeamSignature.Places.Answer.pendingFunction)]
			}
			if places.levels[key.level].parents.isEmpty {
				return isValid(key.level, key.state) ? [.callersOwn] : []
			}
			return nil
		}

		private func answerChildren(of key: AnswerKey) -> [(AnswerKey, (SeamSignature.Places.Answer) -> SeamSignature.Places.Answer)] {
			let opens = places.levels[key.level].opensSendableFunction.isPresent
			let crossesHere = opens && !key.crossed
			return transitions(from: key.level, state: key.state).map { parent, state in
				let level = key.level
				return (AnswerKey(level: parent, label: key.label, state: state, crossed: key.crossed || opens), { answer in
					crossesHere ? answer.crossingFunction(at: level) : answer
				})
			}
		}

		/// Which levels some route reaches in plain code, and which some route reaches inside a `@Sendable` function: a fixed
		/// point over the parents, since the graph can hold a cycle.
		private static func reaches(of levels: [SeamSignature.Places.Level]) -> (plain: [Bool], open: [Bool]) {
			var plain = [Bool](repeating: false, count: levels.count)
			var open = [Bool](repeating: false, count: levels.count)
			var children = [[Int]](repeating: [], count: levels.count)
			for (index, level) in levels.enumerated() {
				for parent in level.parents {
					children[parent].append(index)
				}
			}
			var toVisit = [Int]()
			for (index, level) in levels.enumerated() where level.parents.isEmpty {
				let opens = level.opensSendableFunction.isPresent
				plain[index] = !opens
				open[index] = opens
				toVisit.append(index)
			}
			while let level = toVisit.popLast() {
				for child in children[level] {
					let opens = levels[child].opensSendableFunction.isPresent
					let reachesPlain = plain[child] || plain[level] && !opens
					let reachesOpen = open[child] || open[level] || opens && (plain[level] || open[level])
					guard reachesPlain != plain[child] || reachesOpen != open[child] else { continue }
					plain[child] = reachesPlain
					open[child] = reachesOpen
					toVisit.append(child)
				}
			}
			return (plain, open)
		}
	}
}

extension SeamSignature.Places.Answer {
	/// A placeholder for the function a walk crosses further down, which the level that opens it fills in.
	fileprivate static let pendingFunction = -2

	fileprivate var isBoundOutsideSendableFunction: Bool {
		if case .boundOutsideSendableFunction = self { true } else { false }
	}

	/// The answer with the function a walk crosses at `level` filled in, where it is still pending.
	fileprivate func crossingFunction(at level: Int) -> Self {
		guard case let .boundOutsideSendableFunction(declarationLevel, declaration, functionLevel) = self, functionLevel == Self.pendingFunction else { return self }
		return .boundOutsideSendableFunction(level: declarationLevel, declaration: declaration, functionLevel: level)
	}
}

extension Optional {
	fileprivate var isPresent: Bool {
		self != nil
	}
}

/// A memoized fold up a graph that can hold a cycle: each key's value is its own answer, or the union of its children's,
/// each transformed, in children order, with no element twice.
///
/// A key met again while it is still being walked gives nothing at first; every key whose value took from such a key is
/// then computed again, in the order the walk finished them, until none grows, so each value is the union over every
/// route, as a value computed from a finite graph of routes must be. It holds its memo as long as its owner does.
private struct Fold<Key: Hashable, Element: Hashable> {
	private var memo = [Key: [Element]]()
	/// How often a walk met a key it was still walking. Each fold counts its own, since one fold's walk can ask another.
	private(set) var revisits = 0

	mutating func value(
		of start: Key,
		direct: (Key) -> [Element]?,
		children: (Key) -> [(Key, (Element) -> Element)],
	) -> [Element] {
		if let known = memo[start] {
			return known
		}
		var onStack = Set<Key>()
		var provisional = [Key]()
		var provisionalSet = Set<Key>()
		var childrenByKey = [Key: [(Key, (Element) -> Element)]]()
		var stack = [(key: start, isExpanded: false)]
		while let (key, isExpanded) = stack.popLast() {
			if isExpanded {
				let keyChildren = childrenByKey[key] ?? []
				var isPartial = false
				memo[key] = Self.union(of: keyChildren, in: memo) { child in
					if onStack.contains(child) {
						revisits += 1
						isPartial = true
					} else if provisionalSet.contains(child) {
						isPartial = true
					}
				}
				onStack.remove(key)
				if isPartial {
					provisional.append(key)
					provisionalSet.insert(key)
				}
				continue
			}
			guard memo[key] == nil, !onStack.contains(key) else { continue }
			if let value = direct(key) {
				memo[key] = value
				continue
			}
			let keyChildren = children(key)
			childrenByKey[key] = keyChildren
			onStack.insert(key)
			stack.append((key, true))
			for (child, _) in keyChildren.reversed() where memo[child] == nil && !onStack.contains(child) {
				stack.append((child, false))
			}
		}
		// The keys of a cycle grow together until none does.
		var grew = !provisional.isEmpty
		while grew {
			grew = false
			for key in provisional {
				let value = Self.union(of: childrenByKey[key] ?? [], in: memo) { _ in }
				if value.count != memo[key]?.count {
					memo[key] = value
					grew = true
				}
			}
		}
		return memo[start] ?? []
	}

	private static func union(of children: [(Key, (Element) -> Element)], in memo: [Key: [Element]], noting: (Key) -> Void) -> [Element] {
		var elements = [Element]()
		var seen = Set<Element>()
		for (child, transform) in children {
			noting(child)
			for element in memo[child] ?? [] {
				let transformed = transform(element)
				if seen.insert(transformed).inserted {
					elements.append(transformed)
				}
			}
		}
		return elements
	}
}
