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
	/// every route, however often it goes around.
	///
	/// It holds its memos for as long as its owner keeps it: one computation of a seam's holes, or one caller's reads of a
	/// signature.
	public final class Query {
		/// A query over every route of a case's family.
		/// - Parameter calledPlaces: The place graph of the seam or public mock a passed-up case refers to
		///   (`CalledCase`), or `nil` where the run holds none; never asked where no case is passed up. The query of a called
		///   graph is made the same way, with the reference's `isPublicMock`.
		/// - Parameter isPublicMock: Whether `places` is the graph of a public mock's plan, not of a seam's signature. Where
		///   seams call each other, a reference of a seam beneath to this graph's type of the same kind is a case of this
		///   graph (`pathToHoldingSeam(of:)`).
		public convenience init(
			of places: SeamSignature.Places,
			calledPlaces: ((SeamSignature.Places.CalledCase) -> SeamSignature.Places?)? = nil,
			ofPublicMock isPublicMock: Bool = false,
		) {
			self.init(places: places, excludedEntries: [], calledPlaces: calledPlaces, isPublicMock: isPublicMock)
		}

		/// A query over only the routes whose stack (`stack(along:)`) holds none of `excludedEntries`. It is given no called
		/// graph: the entries are of this graph's stack, which a called graph's routes do not have, so a passed-up case is
		/// never resolved through it (`calledCase(of:)` is `nil`), and no called graph's query can range over fewer routes
		/// than all.
		public convenience init(
			of places: SeamSignature.Places,
			excludingRoutesWhoseStackHolds excludedEntries: Set<SeamSignature.Places.StackEntry>,
		) {
			self.init(places: places, excludedEntries: excludedEntries, calledPlaces: nil, isPublicMock: false)
		}

		private init(
			places: SeamSignature.Places,
			excludedEntries: Set<SeamSignature.Places.StackEntry>,
			calledPlaces: ((SeamSignature.Places.CalledCase) -> SeamSignature.Places?)?,
			isPublicMock: Bool,
		) {
			self.places = places
			self.calledPlaces = calledPlaces
			self.isPublicMock = isPublicMock
			self.excludedEntries = excludedEntries
			// Labels are the same before every next property, so each list's are found once.
			let lastIndexByLabelByList = places.declarationLists.map { declarations in
				var indexByLabel = [String: Int]()
				for (index, declaration) in declarations.enumerated() {
					indexByLabel[declaration.field.property.label] = index
				}
				return indexByLabel
			}
			lastDeclarationIndexByLabel = places.levels.map { lastIndexByLabelByList[$0.declarationList] }
			(plainReach, openReach) = Self.reaches(of: places.levels)
			validity = excludedEntries.isEmpty ? [] : Self.validity(of: places.levels, excluding: excludedEntries, plainReach: plainReach, openReach: openReach)
		}

		public let places: SeamSignature.Places

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

		/// The uncarried declaration `answer` is for a place of the case at `caseIndex`, or `nil` for a field or the caller's own.
		/// Its `placesInTree` is left empty: the cases are in the declaration's `buildability`.
		public func uncarriedDeclaration(of answer: SeamSignature.Places.Answer, at caseIndex: Int) -> SeamSignature.Hole.UncarriedDeclaration? {
			uncarriedDeclarationAndGraphDeclaration(of: answer, at: caseIndex)?.uncarried
		}

		/// The same, with the graph's declaration it is made from.
		func uncarriedDeclarationAndGraphDeclaration(of answer: SeamSignature.Places.Answer, at caseIndex: Int) -> (uncarried: SeamSignature.Hole.UncarriedDeclaration, graphDeclaration: SeamSignature.Places.Declaration)? {
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
			return (uncarried, declaration)
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
					for declaration in places.declarationsBeforeAnyNextProperty(ofLevel: level) {
						let label = declaration.field.property.label
						labels.removeAll { $0 == label }
						labels.append(label)
					}
				}
			}
			var seen = Set(labels)
			for level in levelsReaching(caseIndex) {
				for declaration in places.declarationsBeforeAnyNextProperty(ofLevel: level) where seen.insert(declaration.field.property.label).inserted {
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
			cycleReentryElements(ofLabel: label, at: caseIndex).map { cycleReentryDeclaration(of: $0) }
		}

		/// What `cycleReentryDeclarations(ofLabel:at:)` lists, as the fold finds it, each once.
		private func cycleReentryElements(ofLabel label: String, at caseIndex: Int) -> [ReentryElement] {
			let placeCase = places.cases[caseIndex]
			guard let start = startState(of: placeCase) else { return [] }
			// The place's own label is never re-entered: every call is made inside a tree that builds a declaration of it.
			guard places.levels[placeCase.ownerLevel].key.nextProperty?.label != label else { return [.none] }
			let reached = reentryFold.value(
				of: AnswerKey(level: placeCase.ownerLevel, label: label, state: start, crossed: placeCase.siteOpensSendableFunction),
				direct: { [unowned self] key in
					guard lastDeclarationIndexByLabel[key.level][key.label] != nil || places.levels[key.level].parents.isEmpty else { return nil }
					return isValid(key.level, key.state) ? [.none] : []
				},
				children: { [unowned self] key in
					let opens = places.levels[key.level].opensSendableFunction.isPresent
					return transitions(from: key.level, state: key.state).map { parent, state in
						(AnswerKey(level: parent, label: key.label, state: state, crossed: key.crossed || opens), { [unowned self] element in
							guard case .none = element else { return element }
							return reentry(ofLabel: key.label, atLevel: key.level, beneath: parent, placeIsInFurtherSendableFunction: key.crossed)
						})
					}
				},
			)
			var reentries = [ReentryElement]()
			var seen = Set<ReentryElement>()
			for element in reached where seen.insert(element).inserted {
				reentries.append(element)
			}
			return reentries
		}

		/// The declaration a re-entry hands the type built again, or `nil` for a route on which none does. `calledSeamType`
		/// names the seam whose tree holds the place, where the cycle builds again a call that presents it.
		private func cycleReentryDeclaration(of element: ReentryElement, calledSeamType: TypeDescription? = nil) -> SeamSignature.Hole.CycleReentryDeclaration? {
			guard case let .reentry(_, declaringParent, reentry, placeIsInFurtherSendableFunction) = element else { return nil }
			return SeamSignature.Hole.CycleReentryDeclaration(
				property: reentry.property,
				declaringType: reentry.declaringType,
				declarationLocation: reentry.declarationLocation,
				parameterTakingType: reentry.parameterTakingType,
				closedOnProperty: reentry.closedOnProperty,
				closedOnBuiltType: reentry.closedOnBuiltType,
				closedOnDeclaringType: declaringType(ofPropertyAfter: declaringParent),
				reenteringType: reentry.reenteringType,
				calledSeamType: calledSeamType,
				placeIsInFurtherSendableFunction: placeIsInFurtherSendableFunction,
			)
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
			return hidden.map(declarationHiddenByField(of:))
		}

		/// The declaration `element`'s field hides, as a place reads it.
		private func declarationHiddenByField(of element: HiddenElement) -> SeamSignature.Hole.DeclarationHiddenByField {
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

		/// The nearest declaration of the label of the declaration at `index` of `level` before it, on the routes from
		/// `level` in `state`: an earlier declaration of the label at the level, or the nearest one above.
		private func reached(before index: Int, at level: Int, state: RouteState) -> [SeamSignature.Places.Reached] {
			let declarations = places.declarationsBeforeAnyNextProperty(ofLevel: level)
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

		/// The route the case at `caseIndex` is named by where a diagnostic or a name made from a path names one place: its
		/// first place's in builder-label order (`Case.namingRoute`). `nil` only for a case no place reaches, which no
		/// computation makes.
		public func representativeRoute(of caseIndex: Int) -> Route? {
			let namingRoute = places.cases[caseIndex].namingRoute
			return namingRoute.isEmpty ? nil : Route(levels: namingRoute)
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

		/// The entries `property`, built for `concreteType`, puts on the stack, innermost first: where it is lazily
		/// instantiated, its instance first and then the wrapper, as `Scope.createScopeGenerator` stacks them.
		static func entries(of property: Property, builtAs concreteType: TypeDescription) -> [SeamSignature.Places.StackEntry] {
			var entries = [SeamSignature.Places.StackEntry]()
			if let instance = property.asLazilyInstantiatedInstanceProperty {
				entries.append(SeamSignature.Places.StackEntry(property: instance, concreteType: concreteType))
			}
			entries.append(SeamSignature.Places.StackEntry(property: property, concreteType: concreteType))
			return entries
		}

		/// One joint value the places of a case read of a label over some of its routes: the answer, the scope a cycle
		/// re-enters between the place and the label's nearest declaration, and the declaration a fill's field hides there,
		/// with the least of those routes in source order.
		public struct LabelVariant: Sendable {
			public let answer: SeamSignature.Places.Answer
			public let cycleReentry: SeamSignature.Hole.CycleReentryDeclaration?
			public let hiddenByField: SeamSignature.Hole.DeclarationHiddenByField?
			/// The least route reading this value, as `representativeRoute(of:ofLabel:answer:)` orders routes.
			public let leastRoute: Route
		}

		/// Every distinct joint value the places of the case at `caseIndex` read of `label` over its routes, each with its
		/// least route, in the order of those routes. A route reads one answer, at most one re-entry and at most one hidden
		/// declaration, which `answers(ofLabel:at:)`, `cycleReentryDeclarations(ofLabel:at:)` and
		/// `declarationsHiddenByFields(ofLabel:at:)` list apart; routes that share an answer can differ in the other two.
		public func labelVariants(ofLabel label: String, at caseIndex: Int) -> [LabelVariant] {
			let placeCase = places.cases[caseIndex]
			guard let start = startState(of: placeCase) else { return [] }
			// The place's own label is never re-entered: every call is made inside a tree that builds a declaration of it.
			let tracksReentry = places.levels[placeCase.ownerLevel].key.nextProperty?.label != label
			let crossedAtSite = placeCase.siteOpensSendableFunction
			let elements = variantFold.value(
				of: AnswerKey(level: placeCase.ownerLevel, label: label, state: start, crossed: crossedAtSite),
				direct: { [unowned self] key in
					guard let answers = directAnswers(of: key) else { return nil }
					guard isValid(key.level, key.state) else { return [] }
					return answers.flatMap { answer in
						hiddenElements(of: answer, crossed: key.crossed, state: key.state).map { hidden in
							VariantElement(answer: answer, reentry: .none, hidden: hidden)
						}
					}
				},
				children: { [unowned self] key in
					let opens = places.levels[key.level].opensSendableFunction.isPresent
					let crossesHere = opens && !key.crossed
					let level = key.level
					return transitions(from: key.level, state: key.state).map { parent, state in
						(AnswerKey(level: parent, label: key.label, state: state, crossed: key.crossed || opens), { [unowned self] element in
							var element = element
							if crossesHere {
								element.answer = element.answer.crossingFunction(at: level)
							}
							if tracksReentry, case .none = element.reentry {
								element.reentry = reentry(ofLabel: key.label, atLevel: level, beneath: parent, placeIsInFurtherSendableFunction: key.crossed)
							}
							// Past a `@Sendable` function, the fill's field is no field of the place.
							if opens {
								element.hidden = nil
							}
							return element
						})
					}
				},
			)
			var distinctElements = [VariantElement]()
			var seen = Set<VariantElement>()
			for element in elements where seen.insert(element).inserted {
				distinctElements.append(element)
			}
			let variants = distinctElements.compactMap { element -> LabelVariant? in
				let answer = crossedAtSite ? element.answer.crossingFunction(at: SeamSignature.Places.Answer.siteFunction) : element.answer
				guard let route = leastRoute(reading: element, ofLabel: label, at: caseIndex, tracksReentry: tracksReentry) else { return nil }
				return LabelVariant(
					answer: answer,
					cycleReentry: cycleReentryDeclaration(of: element.reentry),
					hiddenByField: element.hidden.map(declarationHiddenByField(of:)),
					leastRoute: route,
				)
			}
			return variants.sorted { precedesInSourceOrder($0.leastRoute, $1.leastRoute) }
		}

		/// The declarations a fill's field hides from a place that reads `answer`: none past a `@Sendable` function, and
		/// `nil` alone where the answer's declaration hides nothing.
		private func hiddenElements(of answer: SeamSignature.Places.Answer, crossed: Bool, state: RouteState) -> [HiddenElement?] {
			guard !crossed, case let .field(level, index) = answer, let hiding = places.declaration(level: level, declaration: index).fillFieldHiding else { return [nil] }
			let property = places.declaration(level: level, declaration: index).field.property
			var elements = [HiddenElement?]()
			var seen = Set<HiddenElement?>()
			for reached in reached(before: index, at: level, state: state) {
				let element: HiddenElement? = if case let .declaration(hiddenLevel, hiddenIndex) = reached, places.declaration(level: hiddenLevel, declaration: hiddenIndex).field.property != property {
					HiddenElement(fieldLevel: level, fieldIndex: index, hiddenLevel: hiddenLevel, hiddenIndex: hiddenIndex, hiding: hiding.calledSeam)
				} else {
					nil
				}
				if seen.insert(element).inserted {
					elements.append(element)
				}
			}
			return elements
		}

		/// The least route of the case at `caseIndex` on which its places read `element` of `label`.
		private func leastRoute(reading element: VariantElement, ofLabel label: String, at caseIndex: Int, tracksReentry: Bool) -> Route? {
			let placeCase = places.cases[caseIndex]
			guard let start = startState(of: placeCase) else { return nil }
			enum Phase: Hashable {
				/// Below the label's nearest declaration, with the innermost function crossed and the re-entry nearest the
				/// declaration so far.
				case beforeDeclaration(function: Int?, reentry: ReentryElement)
				/// Above a fill's field that hides a declaration, looking for the nearest declaration of its label.
				case seekingHidden(fieldLevel: Int, fieldIndex: Int)
				/// Past every declaration the value depends on.
				case past
			}
			/// A step of the walk up.
			struct Node: Hashable {
				let level: Int
				let state: RouteState
				let phase: Phase
			}
			let startNode = Node(level: placeCase.ownerLevel, state: start, phase: .beforeDeclaration(function: placeCase.siteOpensSendableFunction ? SeamSignature.Places.Answer.siteFunction : nil, reentry: .none))
			return leastRoute(
				from: startNode,
				level: \.level,
				next: { [unowned self] node in
					let past = [(Node(level: node.level, state: node.state, phase: .past), false)]
					switch node.phase {
					case let .beforeDeclaration(function, reentry):
						if let decided = decidedAnswer(at: node.level, label: label, state: node.state, function: function) {
							let answer = function == SeamSignature.Places.Answer.siteFunction ? element.answer.crossingFunction(at: SeamSignature.Places.Answer.siteFunction) : element.answer
							guard decided == answer, reentry == element.reentry else { return [] }
							guard function == nil, case let .field(level, index) = decided, let hiding = places.declaration(level: level, declaration: index).fillFieldHiding else {
								return element.hidden == nil ? past : []
							}
							let declarations = places.declarationsBeforeAnyNextProperty(ofLevel: level)
							if let earlier = declarations[..<index].lastIndex(where: { $0.field.property.label == label }) {
								return hidden(level: level, index: index, hiddenLevel: level, hiddenIndex: earlier, hiding: hiding.calledSeam) == element.hidden ? past : []
							}
							if places.levels[level].parents.isEmpty {
								return element.hidden == nil ? past : []
							}
							return transitions(from: level, state: node.state).map { parent, state in
								(Node(level: parent, state: state, phase: .seekingHidden(fieldLevel: level, fieldIndex: index)), true)
							}
						}
						let opens = places.levels[node.level].opensSendableFunction.isPresent
						return transitions(from: node.level, state: node.state).map { parent, state in
							// The re-entry nearest the declaration is the one the route reads.
							var nextReentry = reentry
							if tracksReentry, case let own = self.reentry(ofLabel: label, atLevel: node.level, beneath: parent, placeIsInFurtherSendableFunction: function != nil), own != .none {
								nextReentry = own
							}
							return (Node(level: parent, state: state, phase: .beforeDeclaration(function: function ?? (opens ? node.level : nil), reentry: nextReentry)), true)
						}
					case let .seekingHidden(fieldLevel, fieldIndex):
						if let index = lastDeclarationIndexByLabel[node.level][label] {
							guard isValid(node.level, node.state), let hiding = places.declaration(level: fieldLevel, declaration: fieldIndex).fillFieldHiding else { return [] }
							return hidden(level: fieldLevel, index: fieldIndex, hiddenLevel: node.level, hiddenIndex: index, hiding: hiding.calledSeam) == element.hidden ? past : []
						}
						if places.levels[node.level].parents.isEmpty {
							return element.hidden == nil ? past : []
						}
						return transitions(from: node.level, state: node.state).map { parent, state in
							(Node(level: parent, state: state, phase: node.phase), true)
						}
					case .past:
						return transitions(from: node.level, state: node.state).map { parent, state in
							(Node(level: parent, state: state, phase: .past), true)
						}
					}
				},
				isEnd: { [unowned self] node in
					node.phase == .past && places.levels[node.level].parents.isEmpty && isValid(node.level, node.state)
				},
			)
		}

		/// The declaration at `hiddenIndex` of `hiddenLevel` as the field at `index` of `level` hides it, or `nil` where it is a
		/// declaration of the field's own property.
		private func hidden(level: Int, index: Int, hiddenLevel: Int, hiddenIndex: Int, hiding: TypeDescription) -> HiddenElement? {
			guard places.declaration(level: hiddenLevel, declaration: hiddenIndex).field.property != places.declaration(level: level, declaration: index).field.property else { return nil }
			return HiddenElement(fieldLevel: level, fieldIndex: index, hiddenLevel: hiddenLevel, hiddenIndex: hiddenIndex, hiding: hiding)
		}

		/// The distinct depths below the owner of the case at `caseIndex` at which the stack its places are built with holds
		/// `property` built for `concreteType`, over the case's routes, each with its least route among those whose stack
		/// holds it there, in the order of those routes. The depth counts the declarations beneath the innermost such entry
		/// (`Hole.fillPathDeclarationsBeneath`): a lazily instantiated property's instance is no declaration of its own.
		public func depthsBelowOwner(ofProperty property: Property, builtAs concreteType: TypeDescription, at caseIndex: Int) -> [(depth: Int, leastRoute: Route)] {
			let placeCase = places.cases[caseIndex]
			guard let start = startState(of: placeCase) else { return [] }
			let target = SeamSignature.Places.StackEntry(property: property, concreteType: concreteType)
			enum Phase: Hashable {
				/// Below the entry, with the declarations counted beneath the last entry stacked so far, whose own count waits on
				/// the entry above it.
				case searching(depth: Int, last: Property?)
				case found(depth: Int)
			}
			/// A step of the walk up.
			struct Node: Hashable {
				let level: Int
				let state: RouteState
				let phase: Phase
			}
			/// The phase after stacking `entries` above the last entry, innermost first.
			func stacking(_ entries: [SeamSignature.Places.StackEntry], depth: Int, last: Property?) -> Phase {
				var depth = depth
				var last = last
				for entry in entries {
					if let previous = last, entry.property.asLazilyInstantiatedInstanceProperty != previous {
						depth += 1
					}
					if entry == target {
						return .found(depth: depth)
					}
					last = entry.property
				}
				return .searching(depth: depth, last: last)
			}
			let startNode = Node(level: placeCase.ownerLevel, state: start, phase: .searching(depth: 0, last: nil))
			let next = { [unowned self] (node: Node) -> [(Node, Bool)] in
				switch node.phase {
				case let .searching(depth, last):
					// A route a tree builds stacks no entry twice, so no depth it reaches passes the graph's count of entries;
					// a walk around a cycle of the graph does, and stops there.
					guard depth <= stackEntryCount else { return [] }
					let level = places.levels[node.level]
					guard let builtType = level.key.builtType else {
						// A fill's base stack ends the stack.
						guard case let .found(depth) = stacking(level.fillBaseStack, depth: depth, last: last) else { return [] }
						return [(Node(level: node.level, state: node.state, phase: .found(depth: depth)), false)]
					}
					return transitions(from: node.level, state: node.state).map { parent, state in
						guard let property = places.levels[parent].key.nextProperty else {
							return (Node(level: parent, state: state, phase: node.phase), true)
						}
						return (Node(level: parent, state: state, phase: stacking(Self.entries(of: property, builtAs: builtType), depth: depth, last: last)), true)
					}
				case .found:
					return transitions(from: node.level, state: node.state).map { parent, state in
						(Node(level: parent, state: state, phase: node.phase), true)
					}
				}
			}
			// The depths some route reaches, in the order the walk finds them.
			var depths = [Int]()
			var seen: Set<Node> = [startNode]
			var toVisit = [startNode]
			while let node = toVisit.popLast() {
				if case let .found(depth) = node.phase, places.levels[node.level].parents.isEmpty, isValid(node.level, node.state), !depths.contains(depth) {
					depths.append(depth)
				}
				for (parent, _) in next(node) where seen.insert(parent).inserted {
					toVisit.append(parent)
				}
			}
			let routes = depths.compactMap { depth -> (depth: Int, leastRoute: Route)? in
				leastRoute(from: startNode, level: \.level, next: next, isEnd: { [unowned self] node in
					node.phase == .found(depth: depth) && places.levels[node.level].parents.isEmpty && isValid(node.level, node.state)
				}).map { (depth, $0) }
			}
			return routes.sorted { precedesInSourceOrder($0.leastRoute, $1.leastRoute) }
		}

		/// Whether `lhs` precedes `rhs` by the properties the code declares along each, root first (`precedesOnRoute`): a route
		/// whose properties are a prefix of the other's first, a location-less declaration after every located one.
		private func precedesInSourceOrder(_ lhs: Route, _ rhs: Route) -> Bool {
			let lhsProperties = declaredPathToOwner(along: lhs)
			let rhsProperties = declaredPathToOwner(along: rhs)
			for (lhsProperty, rhsProperty) in zip(lhsProperties, rhsProperties) where lhsProperty.declarationLocation != rhsProperty.declarationLocation || lhsProperty.property.label != rhsProperty.property.label {
				return Self.precedesOnRoute(lhsProperty, rhsProperty)
			}
			return lhsProperties.count < rhsProperties.count
		}

		/// The least route, by the source locations of the properties the code declares along it, root first (a route whose
		/// locations are a prefix of another's first, a location-less declaration after every located one), among the routes
		/// of a walk up from `startNode` that reach a node `isEnd` accepts, so neither a name nor the order in which the places
		/// were reached decides it. `next` gives each node the nodes it leads up to, each with whether the step goes up an edge
		/// of the graph or stays at its level. Found from the ends down, one location at a time, over the nodes that lead to an
		/// end, so no route is listed; a node a route has already passed is not entered again. `nil` when no route reaches one.
		/// The least route a walk up from `startNode` reaches an end by, as `leastRoute(from:level:next:isEnd:simple:)` finds
		/// it: the least that stacks no entry twice, a route the seam's tree can build, where the graph holds one; else the least.
		private func leastRoute<Node: Hashable>(from startNode: Node, level: (Node) -> Int, next: (Node) -> [(Node, Bool)], isEnd: (Node) -> Bool) -> Route? {
			leastRoute(from: startNode, level: level, next: next, isEnd: isEnd, simple: true) ?? leastRoute(from: startNode, level: level, next: next, isEnd: isEnd, simple: false)
		}

		/// The least route, in source order, by which a walk up from `startNode` reaches an end. Where `simple`, a route stacks
		/// no entry twice: two levels alike are one level of the graph, so a route up can join builds of a tangle of cycles
		/// that no tree holds together, climbing through a member already on it. Read from the ends down, each step takes the
		/// least edge from which the start is still reachable without stacking an entry the route holds, so every choice is
		/// final; a level outside every cycle of the graph needs no such check.
		private func leastRoute<Node: Hashable>(from startNode: Node, level: (Node) -> Int, next: (Node) -> [(Node, Bool)], isEnd: (Node) -> Bool, simple: Bool) -> Route? {
			// The walk up, each node with the nodes it leads up to.
			var parentsByNode = [Node: [(node: Node, isEdge: Bool)]]()
			var nodesInOrderReached = [startNode]
			var ends = [Node]()
			var toVisit = [startNode]
			var seen: Set<Node> = [startNode]
			while let node = toVisit.popLast() {
				if isEnd(node) {
					ends.append(node)
				}
				let parents = next(node).map { (node: $0.0, isEdge: $0.1) }
				parentsByNode[node] = parents
				for parent in parents where seen.insert(parent.node).inserted {
					nodesInOrderReached.append(parent.node)
					toVisit.append(parent.node)
				}
			}
			// The nodes that lead up to an end, or that are one: only they are on a route the walk accepts.
			var childrenByNode = [Node: [(node: Node, isEdge: Bool)]]()
			for node in nodesInOrderReached {
				for parent in parentsByNode[node] ?? [] {
					childrenByNode[parent.node, default: []].append((node, parent.isEdge))
				}
			}
			var onRoute = Set<Node>()
			var toMark = ends
			while let node = toMark.popLast() {
				guard onRoute.insert(node).inserted else { continue }
				toMark += (childrenByNode[node] ?? []).map(\.node)
			}
			guard onRoute.contains(startNode) else { return nil }
			// From the ends down, one declared property at a time: every walk in `frontier` has read the same properties, and a
			// walk holds the properties of the edge it is on that it has not read yet. Properties are read by their locations,
			// then, where those are equal (a module's view of another reads none), by their labels, as a message spelling the
			// route from its root would sort.
			typealias Walk = (levels: [Int], node: Node, pending: ArraySlice<SeamSignature.Hole.DeclaredProperty>, entries: Set<SeamSignature.Places.StackEntry>)
			/// The entry the edge from `upper` down to `lower` stacks; `nil` into a fill, whose tree starts a stack of its own.
			func entry(from upper: Node, to lower: Node) -> SeamSignature.Places.StackEntry? {
				guard let property = places.levels[level(upper)].key.nextProperty, let builtType = places.levels[level(lower)].key.builtType else { return nil }
				return SeamSignature.Places.StackEntry(property: property, concreteType: builtType)
			}
			/// Whether a walk down from `node` reaches the start without stacking any of `entries`, or past a fill.
			func reachesStart(from node: Node, avoiding entries: Set<SeamSignature.Places.StackEntry>) -> Bool {
				var seen: Set<Node> = [node]
				var toVisit = [node]
				while let node = toVisit.popLast() {
					if node == startNode {
						return true
					}
					for (child, isEdge) in childrenByNode[node] ?? [] where onRoute.contains(child) && !seen.contains(child) {
						if isEdge {
							guard let entry = entry(from: node, to: child) else { return true }
							guard !entries.contains(entry) else { continue }
						}
						seen.insert(child)
						toVisit.append(child)
					}
				}
				return false
			}
			// A node is entered by the first walk to read every location on the way to it, which is the least walk there.
			var entered = Set<Node>()
			var frontier = ends.map { (levels: [level($0)], node: $0, pending: ArraySlice<SeamSignature.Hole.DeclaredProperty>(), entries: Set<SeamSignature.Places.StackEntry>()) }
			while !frontier.isEmpty {
				// Each walk with nothing pending goes on down each of its steps; a step that stays at its level reads nothing.
				var expanded = [Walk]()
				var index = 0
				while index < frontier.count {
					let walk = frontier[index]
					index += 1
					guard walk.pending.isEmpty else {
						expanded.append(walk)
						continue
					}
					guard entered.insert(walk.node).inserted else { continue }
					if walk.node == startNode {
						return Route(levels: walk.levels)
					}
					for (child, isEdge) in childrenByNode[walk.node] ?? [] where onRoute.contains(child) && !entered.contains(child) {
						if isEdge {
							let childLevel = level(child)
							var entries = walk.entries
							if simple {
								if let entry = entry(from: walk.node, to: child) {
									guard entries.insert(entry).inserted, cycleContext.cycleComponent[childLevel] == nil || reachesStart(from: child, avoiding: entries) else { continue }
								} else {
									entries = []
								}
							}
							let parentPosition = places.levels[childLevel].parents.firstIndex(of: level(walk.node)) ?? 0
							frontier.append((levels: walk.levels + [childLevel], node: child, pending: places.levels[childLevel].declaredSegmentByParent[parentPosition][...], entries: entries))
						} else {
							frontier.append((levels: walk.levels, node: child, pending: [], entries: walk.entries))
						}
					}
				}
				// Keep the walks whose next declared property sorts first.
				guard let least = expanded.lazy.compactMap(\.pending.first).min(by: Self.precedesOnRoute) else { return nil }
				frontier = expanded.compactMap { walk in
					guard let next = walk.pending.first, next.declarationLocation == least.declarationLocation, next.property.label == least.property.label else { return nil }
					var advanced = walk
					advanced.pending = walk.pending.dropFirst()
					return advanced
				}
			}
			return nil
		}

		/// Whether `lhs` sorts before `rhs` on a route: by location, then, where the locations are equal, by label.
		private static func precedesOnRoute(_ lhs: SeamSignature.Hole.DeclaredProperty, _ rhs: SeamSignature.Hole.DeclaredProperty) -> Bool {
			guard lhs.declarationLocation == rhs.declarationLocation else {
				return Dependency.DeclarationLocation.precedesInSourceOrder(lhs.declarationLocation, rhs.declarationLocation)
			}
			return lhs.property.label < rhs.property.label
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

		// MARK: Places a call presents

		/// A case of a called seam's graph, with the query that answers it.
		public struct ResolvedCase {
			public init(query: Query, caseIndex: Int) {
				self.query = query
				self.caseIndex = caseIndex
			}

			public let query: Query
			public let caseIndex: Int
		}

		/// The case of the called seam's graph that the case at `caseIndex` stands for, or `nil` for a case of the seam's own
		/// places, or where the run holds no graph of the called seam. One query per called seam serves every case that refers
		/// into it, so its memos are shared between them.
		public func calledCase(of caseIndex: Int) -> ResolvedCase? {
			guard let reference = places.cases[caseIndex].passedUp else { return nil }
			return resolved(reference)
		}

		/// The fills on the routes to the case at `caseIndex`, each with the case of the called seam's graph it fills a place of,
		/// in the order a walk up the routes from the case's owner first meets each fill. A place inside a fill reads, past the
		/// fill's tree, what the called seam's tree declares on its routes to that case, and past those what the scopes that
		/// enclose the call declare; the called case's answers of a label (`answers(ofLabel:at:)` on its query) say which of its
		/// routes declare it. A fill whose called seam's graph the run does not hold is left out.
		public func filledCases(onRoutesTo caseIndex: Int) -> [(fillLevel: Int, filledCase: ResolvedCase)] {
			guard let start = startState(of: places.cases[caseIndex]) else { return [] }
			struct Visit: Hashable {
				let level: Int
				let state: RouteState
			}
			var filledCases = [(fillLevel: Int, filledCase: ResolvedCase)]()
			var seenLevels = Set<Int>()
			var seen: Set = [Visit(level: places.cases[caseIndex].ownerLevel, state: start)]
			var toVisit = Array(seen)
			var visitIndex = 0
			while visitIndex < toVisit.count {
				let visited = toVisit[visitIndex]
				visitIndex += 1
				if let reference = places.levels[visited.level].key.filledCase, seenLevels.insert(visited.level).inserted, let filledCase = resolved(reference) {
					filledCases.append((visited.level, filledCase))
				}
				for (parent, state) in transitions(from: visited.level, state: visited.state) where seen.insert(Visit(level: parent, state: state)).inserted {
					toVisit.append(Visit(level: parent, state: state))
				}
			}
			return filledCases
		}

		/// `reference` resolved in the called seam's graph, or `nil` where the run holds none of it.
		private func resolved(_ reference: SeamSignature.Places.CalledCase) -> ResolvedCase? {
			let key = CalledSeam(seamType: reference.seamType, isPublicMock: reference.isPublicMock)
			let query: Query
			if let known = calledQueries[key] {
				query = known
			} else {
				guard let called = calledPlaces?(reference) else { return nil }
				query = Query(of: called, calledPlaces: calledPlaces, ofPublicMock: reference.isPublicMock)
				calledQueries[key] = query
			}
			guard query.places.cases.indices.contains(reference.caseIndex) else { return nil }
			return ResolvedCase(query: query, caseIndex: reference.caseIndex)
		}

		/// The case at `caseIndex`, then the case each stands for in turn, down to the case of the seam whose tree holds the
		/// places. A case met again ends the chain: seams that call each other inside a lazy cycle can each present the
		/// other's places.
		public func casesPresented(from caseIndex: Int) -> [ResolvedCase] {
			var chain = [ResolvedCase(query: self, caseIndex: caseIndex)]
			var seen = Set<PresentedCase>()
			while let last = chain.last, let reference = last.query.places.cases[last.caseIndex].passedUp,
			      seen.insert(PresentedCase(seam: CalledSeam(seamType: reference.seamType, isPublicMock: reference.isPublicMock), caseIndex: reference.caseIndex)).inserted,
			      let called = last.query.calledCase(of: last.caseIndex)
			{
				chain.append(called)
			}
			return chain
		}

		/// What the levels on the routes to the case at `caseIndex` declare, in the order a walk up from its owner meets them,
		/// each with no reason: for a place a call presents, what the paths to the call bind, which a fill of the place by a
		/// type above this seam cannot read (`Hole.UncarriedDeclaration.Reason.boundByPassingUpSeam`). A parameter of the seam,
		/// and a value a public mock's root binds from its caller's argument, is the caller's own declaration, so it is left
		/// out.
		public func declarationsBoundOnRoutes(to caseIndex: Int) -> [SeamSignature.Hole.UncarriedDeclaration] {
			levelsReaching(caseIndex).flatMap { level in
				places.declarationsBeforeAnyNextProperty(ofLevel: level).filter { !$0.isSeamParameter && !$0.isBoundFromCallersArgument }.map { declaration in
					SeamSignature.Hole.UncarriedDeclaration(
						property: declaration.field.property,
						declaringType: declaration.field.declaringType,
						declarationLocation: declaration.field.declarationLocation,
						parameterTakingType: declaration.field.parameterTakingType,
						builtAfter: nil,
						reason: .other,
					)
				}
			}
		}

		// MARK: Places a call presents, through every seam that presents them

		/// The cases of this graph that present the places the case at `caseIndex` presents, itself among them, in the order
		/// of `cases`: one per call of the seam's tree that presents them and case of the called seam it presents them
		/// through (`Case.firstCasePresentingSamePlaces`). The case alone, for a case no other shares its places with.
		public func casesPresentingSamePlaces(as caseIndex: Int) -> [Int] {
			casesByFirstCase[places.cases[caseIndex].firstCasePresentingSamePlaces ?? caseIndex] ?? [caseIndex]
		}

		/// The case of the seam whose tree holds the places of the case at `caseIndex`, with that seam's query: the case itself
		/// for a case of the seam's own places. A reader asks every question about the places of `query` at `caseIndex` and
		/// resolves the indices of what it is answered in `query.places`, whether or not a call presents the places; what the
		/// seams on the way add is `presentationAdditions(of:)`. `nil` where the run does not hold the graph of a seam on a
		/// way to that seam.
		///
		/// It follows every call that presents the places (`casesPresentingSamePlaces(as:)`), in every seam on the way, each
		/// seam's cases once. So it ends where two seams that call each other each present the places first through the other,
		/// which the reference of one case alone (`casesPresented(from:)`) does not.
		public func holdingCase(of caseIndex: Int) -> ResolvedCase? {
			let firstCase = places.cases[caseIndex].firstCasePresentingSamePlaces ?? caseIndex
			guard places.cases[firstCase].passedUp != nil else { return ResolvedCase(query: self, caseIndex: firstCase) }
			return presentation(of: caseIndex).map { holdingCase(of: $0) }
		}

		/// A declaration a seam binds in its tree on a path to a call that presents places.
		public struct BoundOnPathToCall {
			/// The declaration, with no reason: `Hole.UncarriedDeclaration.Reason.boundByPassingUpSeam` names the seam whose
			/// graph `presentingCase.query` reads and the place of the called seam `presentingCase`'s `passedUp` refers to.
			public let declaration: SeamSignature.Hole.UncarriedDeclaration
			/// The case of the call, in the graph of the seam that binds the declaration.
			public let presentingCase: ResolvedCase
		}

		/// What the seams that present the places of a case add to them, joined over every call that presents them.
		public struct PresentationAdditions {
			/// What the paths to the calls bind, which a fill of the places by a type above cannot read: every distinct
			/// declaration of each call's case, the seam asked first, then each seam in the order its calls first reach it, a
			/// seam's cases in the order of its graph, a case's declarations in the order a walk up from the call meets them
			/// (`declarationsBoundOnRoutes(to:)`).
			public let boundOnPathsToCalls: [BoundOnPathToCall]
			/// `Case.calledCopyDeclarations` of every case that presents the places, in that order, the first of each equal
			/// entry. The holding case's own are read from it.
			public let calledCopyDeclarations: [SeamSignature.Hole.UncarriedDeclaration]
			/// Whether a seam takes the builder of the places `@Sendable`: a call that presents them is made inside a `@Sendable`
			/// function or takes the builder `@Sendable`, or the seam that holds them builds them inside one.
			public let isPassedOnSendable: Bool
		}

		/// What the seams that present the places of the case at `caseIndex` add to them, on every way from this seam to the
		/// seam that holds them; for a case of the seam's own places, nothing, with the case's own `@Sendable`. `nil` where
		/// the run does not hold the graph of a seam on a way. Computed on each call: a reader keeps what it is given.
		public func presentationAdditions(of caseIndex: Int) -> PresentationAdditions? {
			guard let presentation = presentation(of: caseIndex) else { return nil }
			let holding = holdingCase(of: presentation)
			let holdingCase = holding.query.places.cases[holding.caseIndex]
			// The holding seam's own place takes its builder `@Sendable` where it is built inside a `@Sendable` function, which
			// its seam settles with its builders, after its places.
			var isPassedOnSendable = holdingCase.isPassedOnSendable || holdingCase.isBuiltInSendableFunction || holdingCase.siteOpensSendableFunction
			var boundOnPathsToCalls = [BoundOnPathToCall]()
			var boundSeen = Set<BoundOnPathToCallKey>()
			var calledCopyDeclarations = [SeamSignature.Hole.UncarriedDeclaration]()
			var calledCopiesSeen = Set<SeamSignature.Hole.UncarriedDeclaration>()
			for (seamIndex, seam) in presentation.seams.enumerated() {
				let query = seam.query ?? self
				for presentingIndex in seam.cases {
					let presentingCase = query.places.cases[presentingIndex]
					isPassedOnSendable = isPassedOnSendable || presentingCase.isPassedOnSendable
					for declaration in presentingCase.calledCopyDeclarations where calledCopiesSeen.insert(declaration).inserted {
						calledCopyDeclarations.append(declaration)
					}
					for declaration in query.declarationsBoundOnRoutes(to: presentingIndex) where boundSeen.insert(BoundOnPathToCallKey(seam: seamIndex, presented: presentingCase.passedUp, declaration: declaration)).inserted {
						boundOnPathsToCalls.append(BoundOnPathToCall(declaration: declaration, presentingCase: ResolvedCase(query: query, caseIndex: presentingIndex)))
					}
				}
			}
			return PresentationAdditions(boundOnPathsToCalls: boundOnPathsToCalls, calledCopyDeclarations: calledCopyDeclarations, isPassedOnSendable: isPassedOnSendable)
		}

		/// What the places of a case read of a label, where calls may present them.
		public enum PresentedAnswer {
			/// An answer in the graph of the seam that holds the places (`holdingCase(of:)`), never the caller's own.
			case ofHoldingSeam(SeamSignature.Places.Answer)
			/// No declaration of the holding seam's tree answers the read, and a seam on a way binds the label on a path to a
			/// call that presents the places: `answer` in the graph `presentingCase.query` reads, at the case of that call.
			case boundByPassingUpSeam(presentingCase: ResolvedCase, answer: SeamSignature.Places.Answer)
			/// No seam's tree answers the read on some way: the world of this seam's caller does.
			case callersOwn
		}

		/// What the places of the case at `caseIndex` read of `label`: the answers of the case that holds them, in their order.
		/// An answer that leaves the holding seam's tree (the caller's own, and a value a public mock's root binds from its
		/// caller's argument) is answered by the seams that present the places: in place of the first such answer stand the
		/// declarations of `label` nearest above on the paths to the calls, the seam that calls the holding seam first, each
		/// seam's calls in the order of its graph, a seam above another asked only where a path to a call of the one beneath
		/// binds none; the answer itself follows only where, on some way up to this seam's caller, no path binds one. `nil`
		/// where the run does not hold the graph of a seam on a way.
		public func presentedAnswers(ofLabel label: String, at caseIndex: Int) -> [PresentedAnswer]? {
			guard let presentation = presentation(of: caseIndex) else { return nil }
			let holding = holdingCase(of: presentation)
			// Each call that a read leaving the seam beneath it reaches, the calls of the holding seam first.
			var calls = presentation.callsOfHoldingSeam
			// A read that leaves the holding seam's tree at a call that presents its places back goes on at the calls of the
			// holding seam, which are asked first.
			var seamsLeft = Set(presentation.holdingSeam.map { [$0] } ?? [])
			var boundAbove = [PresentedAnswer]()
			// A case of the seam's own places is read by the seam's caller with no seam between.
			var reachesCaller = presentation.seams.isEmpty || presentation.holdingSeam == 0
			var areCallsAsked = false
			var answers = [PresentedAnswer]()
			for answer in holding.query.answers(ofLabel: label, at: holding.caseIndex) {
				guard holding.query.leavesHoldingSeam(answer) else {
					answers.append(.ofHoldingSeam(answer))
					continue
				}
				if !areCallsAsked {
					areCallsAsked = true
					var callIndex = 0
					while callIndex < calls.count {
						let call = calls[callIndex]
						callIndex += 1
						let query = presentation.seams[call.seam].query ?? self
						var leavesSeam = false
						for answerAtCall in query.answers(ofLabel: label, at: call.caseIndex) {
							if query.leavesPresentingSeam(answerAtCall) {
								leavesSeam = true
							} else {
								boundAbove.append(.boundByPassingUpSeam(presentingCase: ResolvedCase(query: query, caseIndex: call.caseIndex), answer: answerAtCall))
							}
						}
						guard leavesSeam else { continue }
						// The seam asked is left for its caller, and, where a seam beneath calls it, for that seam too.
						if call.seam == 0 {
							reachesCaller = true
						}
						if seamsLeft.insert(call.seam).inserted {
							calls += presentation.seams[call.seam].calls
						}
					}
					answers += boundAbove
				}
				if reachesCaller {
					answers.append(answer == .callersOwn ? .callersOwn : .ofHoldingSeam(answer))
				}
			}
			return answers
		}

		/// For `label`, read of the places of the case at `caseIndex` where the graph of the seam that holds them answers
		/// `answer`, what a cycle around a call that presents them hands the call's type built again, every distinct one: a
		/// cycle a passing-up seam's tree closes on a scope above its call builds the call again beneath what the scopes
		/// between declare, as it builds a place of its own again (`cycleReentryDeclarations(ofLabel:at:)` at the call's case),
		/// while the builder hands the place the same values at every level. Each names the holding seam as the seam the call
		/// builds (`CycleReentryDeclaration.calledSeamType`), whose receive of the label carries it to the place. The calls are
		/// asked as `presentedAnswers(ofLabel:at:)` asks them: those of the holding seam first, and a seam above another only
		/// where a read leaves the seam beneath. Empty where `answer` stays in the holding seam's tree, for the place's own
		/// label, for a case of the seam's own places, or where the run does not hold the graph of a seam on a way.
		public func presentedCycleReentryDeclarations(ofLabel label: String, reading answer: SeamSignature.Places.Answer, at caseIndex: Int) -> [SeamSignature.Hole.CycleReentryDeclaration] {
			guard let presentation = presentation(of: caseIndex) else { return [] }
			let holding = holdingCase(of: presentation)
			let holdingCase = holding.query.places.cases[holding.caseIndex]
			guard holding.query.leavesHoldingSeam(answer),
			      holding.query.places.levels[holdingCase.ownerLevel].key.nextProperty?.label != label,
			      let holdingSeam = holding.query.ownSeam
			else { return [] }
			var calls = presentation.callsOfHoldingSeam
			var seamsLeft = Set(presentation.holdingSeam.map { [$0] } ?? [])
			var declarations = [SeamSignature.Hole.CycleReentryDeclaration]()
			// Each re-entry once, by its graph and its place there.
			var seen = Set<PresentedReentry>()
			var callIndex = 0
			while callIndex < calls.count {
				let call = calls[callIndex]
				callIndex += 1
				let query = presentation.seams[call.seam].query ?? self
				for element in query.cycleReentryElements(ofLabel: label, at: call.caseIndex) where seen.insert(PresentedReentry(graph: ObjectIdentifier(query), element: element)).inserted {
					if let declaration = query.cycleReentryDeclaration(of: element, calledSeamType: holdingSeam.seamType) {
						declarations.append(declaration)
					}
				}
				// A read the seam asked leaves its tree goes on at the calls of it.
				if query.answers(ofLabel: label, at: call.caseIndex).contains(where: query.leavesPresentingSeam), seamsLeft.insert(call.seam).inserted {
					calls += presentation.seams[call.seam].calls
				}
			}
			return declarations
		}

		/// Whether a read that `answer` answers at a case of this seam's own places is answered above the seam: the caller's
		/// own, and a value a public mock's root binds from its caller's argument, which a declaration on a path to a call of
		/// the mock stands in place of (`Case.uncarriedReplacedOnPathsToCalls`).
		private func leavesHoldingSeam(_ answer: SeamSignature.Places.Answer) -> Bool {
			switch answer {
			case .callersOwn:
				true
			case .field, .uncarried:
				false
			case let .boundOutsideSendableFunction(level, declaration, _):
				places.declaration(level: level, declaration: declaration).isBoundFromCallersArgument
			}
		}

		/// Whether a read that `answer` answers at the case of a call that presents places is answered above this seam: the
		/// caller's own, a parameter of the seam, and a value a public mock's root binds from its caller's argument, which are
		/// the caller's declarations (`declarationsBoundOnRoutes(to:)`).
		private func leavesPresentingSeam(_ answer: SeamSignature.Places.Answer) -> Bool {
			switch answer {
			case .callersOwn:
				return true
			case let .field(level, index), let .uncarried(level, index), let .boundOutsideSendableFunction(level, index, _):
				let declaration = places.declaration(level: level, declaration: index)
				return declaration.isSeamParameter || declaration.isBoundFromCallersArgument
			}
		}

		/// The calls from this seam down to the seam that holds the places of a case, one of each seam on the way.
		public struct PathToHoldingSeam {
			/// The call of each seam, outermost first: its case in its seam's graph, and the route to it from that seam's root.
			public let calls: [(presentingCase: ResolvedCase, route: Route)]

			/// The properties from this seam's root to the last call (`sitePath(along:)` of each route in turn), which stand
			/// before the place's path in the holding seam.
			public var sitePath: [Property] {
				calls.flatMap { $0.presentingCase.query.sitePath(along: $0.route) }
			}

			/// The types from this seam, itself excluded, through the last call (`typesToOwner(along:)` of each route in turn).
			public var types: [SeamSignature.Hole.PathType] {
				calls.flatMap { $0.presentingCase.query.typesToOwner(along: $0.route) }
			}

			/// The properties the code declares from this seam's root to the last call (`declaredPathToOwner(along:)` of each
			/// route in turn), as `Hole.passedUpRoute` holds them.
			public var declaredPath: [SeamSignature.Hole.DeclaredProperty] {
				calls.flatMap { $0.presentingCase.query.declaredPathToOwner(along: $0.route) }
			}
		}

		/// The path a diagnostic about the places of the case at `caseIndex` prints before the place's own path in the seam
		/// that holds them: no call for a case of the seam's own places. At each seam in turn, outermost first, it takes the
		/// call whose least route (`leastRoute(to:)`) precedes the others' in source order, among the calls of the holding
		/// seam and of a seam from which calls still lead to it through no seam the path has passed, so that the path ends
		/// where seams call each other; of two calls with one least route, the case first in the seam's graph. So neither a
		/// name nor the order in which the calls were reached decides it. `nil` where the run does not hold the graph of a
		/// seam on a way.
		public func pathToHoldingSeam(of caseIndex: Int) -> PathToHoldingSeam? {
			guard let presentation = presentation(of: caseIndex) else { return nil }
			var calls = [(presentingCase: ResolvedCase, route: Route)]()
			var seamsPassed = Set<Int>()
			// The seam's own places are reached by no call.
			var nextSeam = presentation.seams.isEmpty || presentation.holdingSeam == 0 ? nil : 0 as Int?
			while let seamIndex = nextSeam {
				seamsPassed.insert(seamIndex)
				let seam = presentation.seams[seamIndex]
				let query = seam.query ?? self
				var least: (caseIndex: Int, route: Route, seamBeneath: Int?)?
				for (presentingIndex, called) in zip(seam.cases, seam.called) {
					let seamBeneath: Int?
					switch called {
					case .holdingSeam:
						seamBeneath = nil
					case let .seam(beneath):
						guard presentation.callsLeadToHoldingSeam(from: beneath, throughNoneOf: seamsPassed) else { continue }
						seamBeneath = beneath
					}
					guard let route = query.leastRoute(to: presentingIndex) else { continue }
					if least.map({ query.precedesInSourceOrder(route, $0.route) }) ?? true {
						least = (presentingIndex, route, seamBeneath)
					}
				}
				guard let least else { return nil }
				calls.append((ResolvedCase(query: query, caseIndex: least.caseIndex), least.route))
				nextSeam = least.seamBeneath
			}
			return PathToHoldingSeam(calls: calls)
		}

		/// The least route to the case at `caseIndex` in its family, by the source locations of the properties the code
		/// declares along it, root first (`leastRoute(from:level:next:isEnd:)`). `nil` only for a case no place reaches.
		public func leastRoute(to caseIndex: Int) -> Route? {
			let placeCase = places.cases[caseIndex]
			guard let start = startState(of: placeCase) else { return nil }
			struct Node: Hashable {
				let level: Int
				let state: RouteState
			}
			return leastRoute(
				from: Node(level: placeCase.ownerLevel, state: start),
				level: \.level,
				next: { [unowned self] node in
					transitions(from: node.level, state: node.state).map { (Node(level: $0.parent, state: $0.state), true) }
				},
				isEnd: { [unowned self] node in
					places.levels[node.level].parents.isEmpty && isValid(node.level, node.state)
				},
			)
		}

		/// The seams that present the places of one case, from this seam down to the seam that holds them.
		private struct Presentation {
			/// A seam on a way to the holding seam, with the cases of its graph that present the places.
			struct Seam {
				/// The seam's query, or `nil` for the query that holds this record, which it must not keep alive.
				let query: Query?
				/// The cases, in the order of the graph's cases.
				let cases: [Int]
				/// For each of `cases`, what its call is of.
				var called = [Called]()
				/// The calls of this seam, in the seams above it: where a read that leaves this seam's tree goes on.
				var calls = [Call]()
			}

			enum Called {
				case holdingSeam
				/// The seam at this index of `seams`.
				case seam(Int)
			}

			struct Call {
				let seam: Int
				let caseIndex: Int
			}

			/// This seam first, then each seam in the order the calls of the seams before it first reach it. Empty for a
			/// case of the seam's own places that no call of its tree presents back to it. The holding seam is among them
			/// where calls of its own tree present its places through another seam, with the cases of those calls.
			var seams: [Seam]
			/// The query of the seam that holds the places, or `nil` for the query that holds this record, which it must not
			/// keep alive, and the case of its graph.
			let holdingQuery: Query?
			let holdingCaseIndex: Int
			/// The holding seam's index in `seams`, where it is among them.
			var holdingSeam: Int?
			var callsOfHoldingSeam: [Call]

			/// Whether calls lead from the seam at `seam` down to the holding seam through no seam of `seamsPassed`, the
			/// seam itself included.
			func callsLeadToHoldingSeam(from seam: Int, throughNoneOf seamsPassed: Set<Int>) -> Bool {
				guard !seamsPassed.contains(seam) else { return false }
				var seamsSeen = seamsPassed.union([seam])
				var seamsToVisit = [seam]
				while let visited = seamsToVisit.popLast() {
					for called in seams[visited].called {
						switch called {
						case .holdingSeam:
							return true
						case let .seam(beneath):
							if seamsSeen.insert(beneath).inserted {
								seamsToVisit.append(beneath)
							}
						}
					}
				}
				return false
			}
		}

		private struct PresentingSeam: Hashable {
			/// `nil` for the seam whose query is asked.
			let seam: CalledSeam?
			let firstCase: Int
		}

		private struct PresentedReentry: Hashable {
			let graph: ObjectIdentifier
			let element: ReentryElement
		}

		private struct BoundOnPathToCallKey: Hashable {
			let seam: Int
			let presented: SeamSignature.Places.CalledCase?
			let declaration: SeamSignature.Hole.UncarriedDeclaration
		}

		private func holdingCase(of presentation: Presentation) -> ResolvedCase {
			ResolvedCase(query: presentation.holdingQuery ?? self, caseIndex: presentation.holdingCaseIndex)
		}

		private func presentation(of caseIndex: Int) -> Presentation? {
			let firstCase = places.cases[caseIndex].firstCasePresentingSamePlaces ?? caseIndex
			// The seam's own places, which no call presents.
			guard places.cases[firstCase].passedUp != nil || casesPresentingSamePlaces(as: firstCase).count > 1 else { return Presentation(seams: [], holdingQuery: nil, holdingCaseIndex: firstCase, callsOfHoldingSeam: []) }
			if let known = presentationByFirstCase[firstCase] {
				return known
			} else {
				let presentation = presentation(ofCasesFrom: firstCase)
				presentationByFirstCase.updateValue(presentation, forKey: firstCase)
				return presentation
			}
		}

		/// The presentation of the places the case at `firstCase`, the first of its cases a call presents them through,
		/// presents. Every graph is resolved by this query, so one query serves a seam however many seams call it.
		private func presentation(ofCasesFrom firstCase: Int) -> Presentation? {
			// The cases of calls: a seam's own case, which its calls that present its places back to it are linked to, calls
			// nothing.
			var seams = [Presentation.Seam(query: nil, cases: casesPresentingSamePlaces(as: firstCase).filter { places.cases[$0].passedUp != nil })]
			var seamIndexByKey = [PresentingSeam(seam: nil, firstCase: firstCase): 0]
			var holdingCase: (query: Query?, caseIndex: Int)?
			var holdingSeam: Int?
			if places.cases[firstCase].passedUp == nil {
				holdingCase = (nil, firstCase)
				holdingSeam = 0
			}
			var callsOfHoldingSeam = [Presentation.Call]()
			var seamIndex = 0
			while seamIndex < seams.count {
				let query = seams[seamIndex].query ?? self
				for presentingIndex in seams[seamIndex].cases {
					guard let reference = query.places.cases[presentingIndex].passedUp else { return nil }
					let call = Presentation.Call(seam: seamIndex, caseIndex: presentingIndex)
					let calledSeam = CalledSeam(seamType: reference.seamType, isPublicMock: reference.isPublicMock)
					// A seam beneath that calls this seam presents the places through this graph's own cases: the seam asked,
					// met again, and never a second seam on a way.
					if calledSeam == ownSeam, places.cases.indices.contains(reference.caseIndex), let seamAsked = seamIndexByKey[PresentingSeam(seam: nil, firstCase: places.cases[reference.caseIndex].firstCasePresentingSamePlaces ?? reference.caseIndex)] {
						if holdingSeam == seamAsked {
							seams[seamIndex].called.append(.holdingSeam)
							callsOfHoldingSeam.append(call)
						} else {
							seams[seamIndex].called.append(.seam(seamAsked))
							seams[seamAsked].calls.append(call)
						}
						continue
					}
					guard let called = resolved(reference) else { return nil }
					let calledFirstCase = called.query.places.cases[called.caseIndex].firstCasePresentingSamePlaces ?? called.caseIndex
					let key = PresentingSeam(seam: calledSeam, firstCase: calledFirstCase)
					if called.query.places.cases[calledFirstCase].passedUp == nil {
						holdingCase = holdingCase ?? (called.query, calledFirstCase)
						seams[seamIndex].called.append(.holdingSeam)
						callsOfHoldingSeam.append(call)
						// The calls of the holding seam's own tree that present its places back to it, through the seams they
						// call: a read that leaves a seam they call goes on at them.
						let callsBack = called.query.casesPresentingSamePlaces(as: calledFirstCase).filter { called.query.places.cases[$0].passedUp != nil }
						if !callsBack.isEmpty, seamIndexByKey[key] == nil {
							seamIndexByKey[key] = seams.count
							holdingSeam = seams.count
							seams.append(Presentation.Seam(query: called.query, cases: callsBack))
						}
					} else {
						let seamBeneath: Int
						if let known = seamIndexByKey[key] {
							seamBeneath = known
						} else {
							seamBeneath = seams.count
							seamIndexByKey[key] = seamBeneath
							seams.append(Presentation.Seam(query: called.query, cases: called.query.casesPresentingSamePlaces(as: calledFirstCase)))
						}
						seams[seamIndex].called.append(.seam(seamBeneath))
						seams[seamBeneath].calls.append(call)
					}
				}
				seamIndex += 1
			}
			guard let holdingCase else { return nil }
			return Presentation(seams: seams, holdingQuery: holdingCase.query, holdingCaseIndex: holdingCase.caseIndex, holdingSeam: holdingSeam, callsOfHoldingSeam: callsOfHoldingSeam)
		}

		/// The cases of the graph by the first case that presents their places (`Case.firstCasePresentingSamePlaces`), each
		/// list in the order of `cases`.
		private lazy var casesByFirstCase = Dictionary(grouping: places.cases.indices) { places.cases[$0].firstCasePresentingSamePlaces ?? $0 }
		/// The presentation of the places of each case a call presents, by the first case that presents them; `nil` where a
		/// graph on a way is not in hand.
		private var presentationByFirstCase = [Int: Presentation?]()

		private struct CalledSeam: Hashable {
			let seamType: TypeDescription
			let isPublicMock: Bool
		}

		private struct PresentedCase: Hashable {
			let seam: CalledSeam
			let caseIndex: Int
		}

		private let calledPlaces: ((SeamSignature.Places.CalledCase) -> SeamSignature.Places?)?
		private let isPublicMock: Bool
		/// The seam or public mock this graph is of: what a reference of another graph names where it refers to a case of
		/// this one. `nil` for a graph with no level.
		private lazy var ownSeam = places.levels.first(where: \.key.isSeamRoot)?.key.builtType.map { CalledSeam(seamType: $0, isPublicMock: isPublicMock) }
		/// The query of each called seam a case was asked through, kept as long as this query.
		private var calledQueries = [CalledSeam: Query]()

		// MARK: Private

		private let lastDeclarationIndexByLabel: [[String: Int]]
		/// What the derivation of cycle re-entries reads of the graph (`Places.cycleContext()`).
		private lazy var cycleContext = places.cycleContext()
		/// How many distinct entries the graph's edges stack: no route the seam's tree builds stacks more.
		private lazy var stackEntryCount = Set(places.levels.indices.flatMap { level in
			places.levels[level].parents.compactMap { parent in entry(ofLevel: level, beneath: parent) }
		}).count
		private var reentriesByEdge = [ReentryEdge: Reentries]()

		private struct ReentryEdge: Hashable {
			let level: Int
			let parent: Int
		}

		private struct Reentries {
			let list: [SeamSignature.Places.CycleReentry]
			let firstIndexByLabel: [String: Int]
		}

		/// What a cycle that closes on the scope of `level` built beneath `parent` hands the type built again
		/// (`Places.cycleReentries(ofLevel:beneath:context:)`), each label's first at its index.
		private func reentries(ofLevel level: Int, beneath parent: Int) -> Reentries {
			let edge = ReentryEdge(level: level, parent: parent)
			if let reentries = reentriesByEdge[edge] {
				return reentries
			}
			let list = places.cycleReentries(ofLevel: level, beneath: parent, context: cycleContext)
			var firstIndexByLabel = [String: Int]()
			for (index, reentry) in list.enumerated() where firstIndexByLabel[reentry.property.label] == nil {
				firstIndexByLabel[reentry.property.label] = index
			}
			let reentries = Reentries(list: list, firstIndexByLabel: firstIndexByLabel)
			reentriesByEdge[edge] = reentries
			return reentries
		}

		/// The first re-entry of `label` of the scope of `level` built beneath `parent`, or `.none`;
		/// `placeIsInFurtherSendableFunction` where a level beneath `level` on the route, or the site, opens a `@Sendable` function.
		private func reentry(ofLabel label: String, atLevel level: Int, beneath parent: Int, placeIsInFurtherSendableFunction: Bool) -> ReentryElement {
			let reentries = reentries(ofLevel: level, beneath: parent)
			guard let index = reentries.firstIndexByLabel[label] else { return .none }
			return .reentry(level: level, declaringParent: parent, reentry: reentries.list[index], placeIsInFurtherSendableFunction: placeIsInFurtherSendableFunction)
		}

		/// The entry the edge from `level` up to `parent` stacks, or `nil` where it stacks none: an edge into a fill, whose
		/// tree starts a stack of its own.
		private func entry(ofLevel level: Int, beneath parent: Int) -> SeamSignature.Places.StackEntry? {
			guard let property = places.levels[parent].key.nextProperty, let builtType = places.levels[level].key.builtType else { return nil }
			return SeamSignature.Places.StackEntry(property: property, concreteType: builtType)
		}

		/// Per level, whether some route from the seam's root reaches it with no level on it, the level included, opening a
		/// `@Sendable` function.
		private let plainReach: [Bool]
		/// Per level, whether some route from the seam's root reaches it with some level on it, the level included, opening one.
		private let openReach: [Bool]
		private var answerFold = Fold<AnswerKey, SeamSignature.Places.Answer>()
		private var hiddenFold = Fold<AnswerKey, HiddenElement>()
		private var nearestFold = Fold<StateKey, SeamSignature.Places.Reached>()
		private var reentryFold = Fold<AnswerKey, ReentryElement>()
		private var variantFold = Fold<AnswerKey, VariantElement>()

		/// The entries a route's stack holds none of, for any question to range over it.
		private let excludedEntries: Set<SeamSignature.Places.StackEntry>
		/// Where `excludedEntries` is not empty, per level and route state (`RouteState.index`), whether some route up from
		/// the level in that state reaches a root of its family with no excluded entry on its stack.
		private let validity: [[Bool]]

		/// What a walk up from a case's owner still requires of the rest of its route to keep it in the case's family.
		private enum Family: Int, Hashable {
			/// A plain place: no level on the route may open a `@Sendable` function.
			case plainOnly
			/// A place of the `@Sendable` family that no function encloses yet: some level above must open one.
			case needsOpenAbove
			/// Any route will do.
			case any
		}

		private struct RouteState: Hashable {
			let family: Family
			/// Whether the route is still below its nearest fill, where the stack the owner is built with ends, so that an
			/// entry the next edge stacks can exclude it. Never, where no entry excludes a route.
			let isStacking: Bool

			static let count = 6

			var index: Int {
				family.rawValue * 2 + (isStacking ? 1 : 0)
			}

			init(family: Family, isStacking: Bool) {
				self.family = family
				self.isStacking = isStacking
			}

			init(index: Int) {
				family = Family(rawValue: index / 2) ?? .any
				isStacking = index % 2 == 1
			}
		}

		private struct AnswerKey: Hashable {
			let level: Int
			let label: String
			let state: RouteState
			/// Whether a `@Sendable` function lies between the level and the place.
			let crossed: Bool
		}

		private struct LevelStateKey: Hashable {
			let level: Int
			let state: RouteState
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
			/// A re-entry of the scope of `level` built beneath `declaringParent`.
			case reentry(level: Int, declaringParent: Int, reentry: SeamSignature.Places.CycleReentry, placeIsInFurtherSendableFunction: Bool)
		}

		/// What one route reads of a label (`LabelVariant`).
		private struct VariantElement: Hashable {
			var answer: SeamSignature.Places.Answer
			var reentry: ReentryElement
			var hidden: HiddenElement?
		}

		private func startState(of placeCase: SeamSignature.Places.Case) -> RouteState? {
			let family: Family
			if !placeCase.isBuiltInSendableFunction {
				guard plainReach[placeCase.ownerLevel], !placeCase.siteOpensSendableFunction else { return nil }
				family = .plainOnly
			} else if placeCase.siteOpensSendableFunction {
				family = .any
			} else {
				guard openReach[placeCase.ownerLevel] else { return nil }
				family = .needsOpenAbove
			}
			let state = RouteState(family: family, isStacking: !excludedEntries.isEmpty)
			return isValid(placeCase.ownerLevel, state) ? state : nil
		}

		/// Whether a route that ends its walk at `level`, in `state`, is of the case's family, with no excluded entry on its
		/// stack.
		private func isValid(_ level: Int, _ state: RouteState) -> Bool {
			guard excludedEntries.isEmpty else { return validity[level][state.index] }
			return Self.isOfFamily(level, state.family, openReach: openReach)
		}

		/// Whether a route that ends its walk at `level`, with `family`, is of the case's family.
		private static func isOfFamily(_ level: Int, _ family: Family, openReach: [Bool]) -> Bool {
			switch family {
			case .plainOnly, .any:
				true
			case .needsOpenAbove:
				openReach[level]
			}
		}

		/// The parents a walk at `level` in `state` may go on to, each with the state there, in the order of `parents`.
		private func transitions(from level: Int, state: RouteState) -> [(parent: Int, state: RouteState)] {
			let parents = Self.familyParents(of: level, family: state.family, in: places.levels, plainReach: plainReach, openReach: openReach)
			guard !excludedEntries.isEmpty else {
				return parents.map { ($0.parent, RouteState(family: $0.family, isStacking: false)) }
			}
			return parents.compactMap { parent, family in
				guard let isStacking = Self.isStacking(above: level, toward: parent, state: state, in: places.levels, excluding: excludedEntries) else { return nil }
				let parentState = RouteState(family: family, isStacking: isStacking)
				return validity[parent][parentState.index] ? (parent, parentState) : nil
			}
		}

		/// Whether a route in `state` at `level` is still stacking on the edge to `parent`, or `nil` where that edge stacks an
		/// excluded entry.
		private static func isStacking(above level: Int, toward parent: Int, state: RouteState, in levels: [SeamSignature.Places.Level], excluding excludedEntries: Set<SeamSignature.Places.StackEntry>) -> Bool? {
			guard state.isStacking, let builtType = levels[level].key.builtType else { return false }
			guard let property = levels[parent].key.nextProperty else { return true }
			return entries(of: property, builtAs: builtType).contains(where: excludedEntries.contains) ? nil : true
		}

		/// The parents a walk at `level` with `family` may go on to in its family, each with the family there.
		private static func familyParents(of level: Int, family: Family, in levels: [SeamSignature.Places.Level], plainReach: [Bool], openReach: [Bool]) -> [(parent: Int, family: Family)] {
			let opens = levels[level].opensSendableFunction.isPresent
			let parents = levels[level].parents
			switch family {
			case .plainOnly:
				// Only levels a plain route reaches are asked about in this family, and none of them opens a `@Sendable` function:
				// `startState(of:)` and this filter keep to `plainReach`, so the validity table's entries elsewhere are never read.
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

		/// Per level and route state, whether some route up from the level in that state reaches a root of its family with
		/// no entry of `excludedEntries` on its stack: a least fixed point over the parents, since the graph can hold a cycle,
		/// each level judged again when a parent turns valid.
		private static func validity(of levels: [SeamSignature.Places.Level], excluding excludedEntries: Set<SeamSignature.Places.StackEntry>, plainReach: [Bool], openReach: [Bool]) -> [[Bool]] {
			var validity = [[Bool]](repeating: [Bool](repeating: false, count: RouteState.count), count: levels.count)
			var children = [[Int]](repeating: [], count: levels.count)
			for (index, level) in levels.enumerated() {
				for parent in level.parents {
					children[parent].append(index)
				}
			}
			func isValid(_ level: Int, _ state: RouteState) -> Bool {
				var state = state
				// A fill's base stack ends the stack.
				if state.isStacking, levels[level].key.builtType == nil {
					guard !levels[level].fillBaseStack.contains(where: excludedEntries.contains) else { return false }
					state = RouteState(family: state.family, isStacking: false)
				}
				if levels[level].parents.isEmpty {
					return isOfFamily(level, state.family, openReach: openReach)
				}
				return familyParents(of: level, family: state.family, in: levels, plainReach: plainReach, openReach: openReach).contains { parent, family in
					guard let isStacking = Self.isStacking(above: level, toward: parent, state: state, in: levels, excluding: excludedEntries) else { return false }
					return validity[parent][RouteState(family: family, isStacking: isStacking).index]
				}
			}
			var toJudge = levels.indices.flatMap { level in (0..<RouteState.count).map { (level, $0) } }
			while let (level, index) = toJudge.popLast() {
				guard !validity[level][index], isValid(level, RouteState(index: index)) else { continue }
				validity[level][index] = true
				for child in children[level] {
					toJudge += (0..<RouteState.count).map { (child, $0) }
				}
			}
			return validity
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

		private func answerChildren(of key: AnswerKey) -> [(AnswerKey, (SeamSignature.Places.Answer) -> SeamSignature.Places.Answer?)] {
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
		if case .boundOutsideSendableFunction = self {
			true
		} else {
			false
		}
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
/// each transformed, in children order, with no element twice. A transform that gives `nil` drops the element: the route
/// it stands for is none a tree builds.
///
/// A key met again while it is still being walked gives nothing at first; every key whose value took from such a key is
/// then computed again, in the order the walk finished them, until none grows, so each value is the union over every
/// route, as a value computed from a finite graph of routes must be. It holds its memo as long as its owner does.
private struct Fold<Key: Hashable, Element: Hashable> {
	private var memo = [Key: [Element]]()

	mutating func value(
		of start: Key,
		direct: (Key) -> [Element]?,
		children: (Key) -> [(Key, (Element) -> Element?)],
	) -> [Element] {
		if let known = memo[start] {
			return known
		}
		var onStack = Set<Key>()
		var provisional = [Key]()
		var provisionalSet = Set<Key>()
		var childrenByKey = [Key: [(Key, (Element) -> Element?)]]()
		var stack = [(key: start, isExpanded: false)]
		while let (key, isExpanded) = stack.popLast() {
			if isExpanded {
				let keyChildren = childrenByKey[key] ?? []
				var isPartial = false
				memo[key] = Self.union(of: keyChildren, in: memo) { child in
					if onStack.contains(child) {
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

	private static func union(of children: [(Key, (Element) -> Element?)], in memo: [Key: [Element]], noting: (Key) -> Void) -> [Element] {
		var elements = [Element]()
		var seen = Set<Element>()
		for (child, transform) in children {
			noting(child)
			for element in memo[child] ?? [] {
				guard let transformed = transform(element) else { continue }
				if seen.insert(transformed).inserted {
					elements.append(transformed)
				}
			}
		}
		return elements
	}
}
