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

// A seam's place graph assembled from its facts drafts, one level per drafted level and entry, never per route: step 1
// of the assembler, the levels outside fills and their declaration lists. Test only, until the assembled graph replaces
// the walk's under a test switch.

/// The levels outside fills of a seam's place graph, assembled from its drafts, with their declaration lists.
struct SeamPlacesLevelAssembly {
	/// The levels, in the order the drafts reach them: the levels on routes to places, then the levels only on routes to
	/// calls that close cycles.
	let levels: [SeamSignature.Places.Level]
	let declarationLists: [[SeamSignature.Places.Declaration]]
	/// For each level, the drafted level it was assembled from.
	let draftedLevels: [SeamPlacesLevelID]
	/// The level each drafted level is built in line as.
	let inLineLevelByDraft: [SeamPlacesLevelID: Int]
	/// For each drafted level whose next edge is a call that passes up places, the level of the called seam that owns their
	/// cases.
	let passingUpLevelByCall: [SeamPlacesLevelID: Int]
	/// For each drafted level whose next edge is a fill, the fill's entry level for the hole that edge fills.
	let entryLevelByCall: [SeamPlacesLevelID: Int]
}

extension SeamPlacesDrafts {
	/// The levels outside fills and their declaration lists, from the drafted levels. A drafted level becomes a level for
	/// each way its next edge is entered: built in line, and closing a cycle on an entry above, where some route to it does
	/// each. Levels alike in everything but their parents are one level with every parent. A level's parents are the levels
	/// whose next edge builds its scope in line, since a call that closes a cycle enters no body.
	func assembledLevels(parameters: [SeamSignature.Parameter], access: SeamPlacesFieldAccess? = nil) -> SeamPlacesLevelAssembly {
		let drafter = SeamPlacesDeclarationDrafter(drafts: self, parameters: parameters, access: access)
		let rootVariant = drafter.rootVariant
		let closesOn = Dictionary(closedOnEntries().map { ($0.level, $0.entry) }, uniquingKeysWith: { first, _ in first })
		let draftByLevel = Dictionary((levels + closingLevels).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

		func node(of variant: VariantID) -> TypeFactsDeclaration {
			world.graph.nodes[Int(world.declaration(of: variant))]
		}
		func target(of level: SeamPlacesLevelID) -> DeclarationID {
			let targets = world.edges(from: world.declaration(of: level.variant))
			return targets[targets.startIndex + Int(level.edge)]
		}
		// The `@Sendable` function a level's scope is built in, which the edge of its first parent that builds it in line opens.
		func opensSendableFunction(into draft: SeamPlacesLevelDraft) -> SeamSignature.Places.SendableFunctionOpened? {
			guard let parent = draft.parents.first(where: buildsInLine), let parentDraft = draftByLevel[parent], let property = node(of: draft.id.variant).property else { return nil }
			let builtType = world.typeTable[Int(world.builtTypes[Int(target(of: parent))])]
			switch parentDraft.opens {
			case .none, .instantiatorBuilder:
				return nil
			case .sendableInstantiatorBuilder:
				return .init(property: property, function: .instantiator(builtType: builtType))
			case .sendableLazyWrapper:
				return .init(property: property, function: .sendableLazyWrapper(builtType: builtType))
			case .otherSendableFunction:
				return .init(property: property, function: .other)
			}
		}
		// The declarations a variant's scope binds: the seam's root, its parameters, then its children; any other scope, its
		// bindings.
		func declarations(of variant: VariantID) -> [SeamSignature.Places.Declaration] {
			let parameterDeclarations = variant == rootVariant ? parameters.map(drafter.parameterDeclaration(of:)) : []
			return parameterDeclarations + world.worldBindings(of: Int(world.declaration(of: variant))).filter { variant != rootVariant || !$0.isForwarded }.map { drafter.declaration(of: $0, atVariant: variant).declaration }
		}
		// What a parent declares on the way to a level: the level's property, declared by the parent's type.
		func declaredSegment(of draft: SeamPlacesLevelDraft, from parent: SeamPlacesLevelID) -> [SeamSignature.Hole.DeclaredProperty] {
			guard let property = node(of: draft.id.variant).property else { return [] }
			let parentInstantiable = node(of: parent.variant).scope.instantiable
			return [SeamSignature.Hole.DeclaredProperty(
				property: property,
				declaringType: parentInstantiable.concreteInstantiable,
				declarationLocation: parentInstantiable.dependencies.first { $0.property == property }?.declarationLocation,
			)]
		}

		struct ListKey: Hashable {
			let builtType: TypeDescription?
			let declarations: [SeamSignature.Places.Declaration]
			let opensSendableFunction: SeamSignature.Places.SendableFunctionOpened?
			let pathSegment: [Property]
		}
		struct LevelKey: Hashable {
			let declarationList: Int
			let key: SeamSignature.Places.LevelKey
			let nextPosition: Int32
			let nextLoop: Int32
			let closesOn: SeamSignature.Places.StackEntry?
		}
		struct AssembledLevel {
			let draft: SeamPlacesLevelDraft
			let key: SeamSignature.Places.LevelKey
			let declarationList: Int
			let opensSendableFunction: SeamSignature.Places.SendableFunctionOpened?
			var fillBaseStack = [SeamSignature.Places.StackEntry]()
			var fillOwnerType: TypeDescription?
			let pathSegment: [Property]
			let pathTypes: [SeamSignature.Hole.PathType]
			let closesOn: SeamSignature.Places.StackEntry?
			/// Whether the level builds no child next: a passing-up call's, which `draft` encloses, and a fill's entry level.
			var hasNoNextPosition = false
			var parents = [Int]()
			var declaredSegmentByParent = [[SeamSignature.Hole.DeclaredProperty]]()
		}
		var lists = [[SeamSignature.Places.Declaration]]()
		var listIndexByKey = [ListKey: Int]()
		var assembled = [AssembledLevel]()
		var levelIndexByKey = [LevelKey: Int]()
		// The level each drafted level is built in line as, which its children's levels are enclosed by.
		var inLineLevelByDraft = [SeamPlacesLevelID: Int]()
		var levelsByDraft = [SeamPlacesLevelID: [Int]]()
		// Whether each variant is built in a fill's tree: a fill, or a scope a variant in a fill's tree builds in line. The
		// drafts list a level after the levels that build it in line, but for those a cycle closes on.
		var isInFill = Set<VariantID>()
		var isInFillChanged = true
		while isInFillChanged {
			isInFillChanged = false
			for draft in levels + closingLevels where !isInFill.contains(draft.id.variant) && (node(of: draft.id.variant).key.isFill || draft.parents.contains { buildsInLine($0) && isInFill.contains($0.variant) }) {
				isInFill.insert(draft.id.variant)
				isInFillChanged = true
			}
		}
		// The holes each fill variant fills, each with the level of the call whose edge passes it, in draft order: one fill
		// can fill several holes of one call, a seam's own and one it passes up.
		struct FillEntry {
			let call: SeamPlacesLevelID
			let fill: SeamPlacesFillDraft
			let hole: SeamSignature.Hole
			let calledCase: SeamSignature.Places.CalledCase?
		}
		var fillEntriesByVariant = [VariantID: [FillEntry]]()
		for draft in levels + closingLevels {
			guard let fill = draft.fill, let calledBuilders = node(of: draft.id.variant).scope.calledBuilders, Int(fill.holeIndex) < calledBuilders.holes.count else { continue }
			let calls = world.calls(of: draft.id.variant)
			let callee = calls[calls.startIndex + Int(draft.id.edge)]
			guard !(fillEntriesByVariant[callee] ?? []).contains(where: { $0.fill.holeIndex == fill.holeIndex && $0.fill.calledType == fill.calledType }) else { continue }
			let hole = calledBuilders.holes[Int(fill.holeIndex)]
			let calledType = world.typeTable[Int(fill.calledType)]
			fillEntriesByVariant[callee, default: []].append(FillEntry(
				call: draft.id,
				fill: fill,
				hole: hole,
				calledCase: calledBuilders.caseIndexBySite[hole.site].map { SeamSignature.Places.CalledCase(seamType: calledType, isPublicMock: fill.isPublicMock, caseIndex: $0) },
			))
		}
		// A fill's entry level, beneath the call level whose edge passes it: the declarations on the paths of the places it
		// stands for that their structs do not carry, each label once, then the fields it binds from the struct, which are
		// those no such declaration's label hides, and of a deferred parameter only where the place is passed up.
		// A fill of a case nested by type stands for every place of the case the call fills, the first such fill of the call:
		// it binds the fields every route to the case hands (`ScopeGenerator.caseFields(of:calledBuilders:placesQuery:)`), and
		// the declarations any of the places leaves uncarried. Every other fill stands for its hole alone.
		var caseHolesByKeyByCall = [VariantID: [String: [SeamSignature.Hole]]]()
		func standsFor(_ entry: FillEntry) -> (places: [SeamSignature.Hole], fields: [SeamSignature.Hole.Field]) {
			let hole = entry.hole
			guard hole.enumPlace != nil else { return ([hole], hole.fields) }
			let scope = node(of: entry.call.variant).scope
			let caseHolesByKey = caseHolesByKeyByCall[entry.call.variant] ?? {
				var caseHolesByKey = [String: [SeamSignature.Hole]]()
				for case let .fill(fillHole, _, _) in scope.holeArguments where fillHole.enumPlace != nil {
					caseHolesByKey[ScopeGenerator.fillCaseKey(of: fillHole), default: []].append(fillHole)
				}
				caseHolesByKeyByCall[entry.call.variant] = caseHolesByKey
				return caseHolesByKey
			}()
			guard let places = caseHolesByKey[ScopeGenerator.fillCaseKey(of: hole)], places.first?.site == hole.site else { return ([hole], hole.fields) }
			return (places, ScopeGenerator.caseFields(of: places, calledBuilders: scope.calledBuilders, placesQuery: scope.calledBuilders.flatMap { $0.places.cases.isEmpty ? nil : $0.placesQuery }).fields)
		}
		func entryDeclarations(of entry: FillEntry) -> [SeamSignature.Places.Declaration] {
			let hole = entry.hole
			let calledType = world.typeTable[Int(entry.fill.calledType)]
			let (places, fields) = standsFor(entry)
			var declarations = [SeamSignature.Places.Declaration]()
			var labels = Set<String>()
			for uncarried in places.flatMap(\.uncarriedDeclarations) where labels.insert(uncarried.property.label).inserted {
				declarations.append(SeamSignature.Places.Declaration(
					field: SeamSignature.Hole.Field(property: uncarried.property, access: access?.seamTypeAccess ?? .internal, declaringType: uncarried.declaringType, declarationLocation: uncarried.declarationLocation, parameterTakingType: uncarried.parameterTakingType),
					isBoundBeforeNextProperty: false,
					builtAfter: uncarried.builtAfter,
					reason: uncarried.reason,
					isForwarded: false,
					cycleParameterOrigin: nil,
					alias: nil,
					isBoundFromCallersArgument: false,
					isCycleParameter: false,
					isReboundByBuilderFunction: false,
					isFieldOfSeamParameter: false,
					fillFieldHiding: nil,
					buildability: nil,
				))
			}
			let uncarriedOnSomeRoute = Set(places.flatMap { place in
				let fieldLabels = Set(place.fields.map(\.property.label))
				return place.uncarriedDeclarations.map(\.property.label).filter { !fieldLabels.contains($0) }
			})
			let readsDeferredFieldsFromStruct = hole.innerSeamType != nil && world.constructions[Int(world.declaration(of: entry.call.variant))] != .publicMockCall
			for field in fields where (!field.isDeferredParameter || readsDeferredFieldsFromStruct) && !uncarriedOnSomeRoute.contains(field.property.label) {
				let fieldAccess = access?.access(of: field.property, declaredBy: field.declaringType)
				declarations.append(SeamSignature.Places.Declaration(
					field: SeamSignature.Hole.Field(
						property: field.property,
						access: fieldAccess?.level ?? .internal,
						accessCause: fieldAccess?.cause,
						declaringType: field.declaringType,
						declarationLocation: field.declarationLocation,
						isReceivedOnlyIfAvailable: field.isReceivedOnlyIfAvailable,
						parameterTakingType: field.parameterTakingType,
						seamParameterOrigin: field.isBoundByPublicMockRoot ? nil : field.seamParameterOrigin,
					),
					isBoundBeforeNextProperty: true,
					builtAfter: nil,
					reason: .other,
					isForwarded: false,
					cycleParameterOrigin: nil,
					alias: nil,
					isBoundFromCallersArgument: false,
					isCycleParameter: false,
					isReboundByBuilderFunction: false,
					isFieldOfSeamParameter: field.isSeamParameter,
					fillFieldHiding: field.isSeamParameter ? .init(calledSeam: calledType, receivingSeam: hole.scopeSeamType) : nil,
					buildability: nil,
				))
			}
			return declarations
		}
		func indexOfList(_ declarations: [SeamSignature.Places.Declaration], builtType: TypeDescription?, opensSendableFunction: SeamSignature.Places.SendableFunctionOpened?, pathSegment: [Property]) -> Int {
			let listKey = ListKey(builtType: builtType, declarations: declarations, opensSendableFunction: opensSendableFunction, pathSegment: pathSegment)
			if let known = listIndexByKey[listKey] {
				return known
			}
			listIndexByKey[listKey] = lists.count
			lists.append(declarations)
			return lists.count - 1
		}
		// Each fill's entry level: no type of its own, its next property the hole's, built beneath the filled seam's path.
		var entryLevelsByFillVariant = [VariantID: [Int]]()
		var entryLevelByCall = [SeamPlacesLevelID: Int]()
		for (variant, entry) in fillEntriesByVariant.sorted(by: { $0.key < $1.key }).flatMap({ variant, entries in entries.map { (variant, $0) } }) {
			guard let callDraft = draftByLevel[entry.call] else { continue }
			let hole = entry.hole
			let opened: SeamSignature.Places.SendableFunctionOpened? = hole.isSendable ? .init(property: hole.property, function: .other) : nil
			let pathSegment = hole.pathBeforePropertyInItsFill
			let list = indexOfList(entryDeclarations(of: entry), builtType: nil, opensSendableFunction: opened, pathSegment: pathSegment)
			let key = SeamSignature.Places.LevelKey(builtType: nil, nextProperty: hole.property, isSeamRoot: false, isInFill: true, filledType: world.typeTable[Int(entry.fill.calledType)], filledCase: entry.calledCase)
			let levelKey = LevelKey(declarationList: list, key: key, nextPosition: -1, nextLoop: -1, closesOn: nil)
			if let known = levelIndexByKey[levelKey] {
				entryLevelsByFillVariant[variant, default: []].append(known)
				entryLevelByCall[entry.call] = known
				continue
			}
			entryLevelByCall[entry.call] = assembled.count
			levelIndexByKey[levelKey] = assembled.count
			entryLevelsByFillVariant[variant, default: []].append(assembled.count)
			assembled.append(AssembledLevel(
				draft: callDraft,
				key: key,
				declarationList: list,
				opensSendableFunction: opened,
				fillBaseStack: zip(hole.fillPropertyStack, hole.fillConcreteTypeStack).map { SeamSignature.Places.StackEntry(property: $0, concreteType: $1) },
				fillOwnerType: hole.ownerType,
				pathSegment: pathSegment,
				pathTypes: hole.typesToOwner,
				closesOn: nil,
				hasNoNextPosition: true,
			))
		}
		for draft in levels + closingLevels {
			let variantNode = node(of: draft.id.variant)
			let instantiable = variantNode.scope.instantiable
			let builtType = instantiable.concreteInstantiable
			let fillEntry = fillEntriesByVariant[draft.id.variant]?.first
			let opened = fillEntry == nil ? opensSendableFunction(into: draft) : nil
			let pathSegment = draft.id.variant == rootVariant ? [] : fillEntry.map { [$0.hole.property] } ?? variantNode.property.map { [$0] } ?? []
			let listDeclarations = declarations(of: draft.id.variant)
			let listKey = ListKey(builtType: builtType, declarations: listDeclarations, opensSendableFunction: opened, pathSegment: pathSegment)
			let listIndex: Int
			if let known = listIndexByKey[listKey] {
				listIndex = known
			} else {
				listIndex = lists.count
				listIndexByKey[listKey] = listIndex
				lists.append(listDeclarations)
			}
			let next = world.graph.nodes[Int(target(of: draft.id))]
			let key = SeamSignature.Places.LevelKey(builtType: builtType, nextProperty: next.key.isFill ? nil : next.property, isSeamRoot: draft.id.variant == rootVariant, isInFill: isInFill.contains(draft.id.variant), filledType: nil)
			var entries = [SeamSignature.Places.StackEntry?]()
			if buildsInLine(draft.id) || !closesCycle(draft.id) {
				entries.append(nil)
			}
			if closesCycle(draft.id), let entry = closesOn[draft.id] {
				entries.append(entry)
			}
			for entry in entries {
				let levelKey = LevelKey(declarationList: listIndex, key: key, nextPosition: draft.nextPosition, nextLoop: draft.nextLoop, closesOn: entry)
				let index: Int
				if let known = levelIndexByKey[levelKey] {
					index = known
				} else {
					index = assembled.count
					levelIndexByKey[levelKey] = index
					assembled.append(AssembledLevel(
						draft: draft,
						key: key,
						declarationList: listIndex,
						opensSendableFunction: opened,
						pathSegment: pathSegment,
						pathTypes: draft.id.variant == rootVariant ? [] : [SeamSignature.Hole.PathType(type: builtType, moduleName: instantiable.moduleName)],
						closesOn: entry,
					))
				}
				levelsByDraft[draft.id, default: []].append(index)
				if entry == nil {
					inLineLevelByDraft[draft.id] = index
				}
			}
		}
		// A call that passes up places of the seam it calls owns their cases at a level of the called seam with no next
		// property and no declarations, enclosed by the level whose next edge is the call.
		var passingUpLevelByCall = [SeamPlacesLevelID: Int]()
		for draft in levels where buildsInLine(draft.id) && !world.passUps(of: Int(target(of: draft.id))).isEmpty {
			let call = world.graph.nodes[Int(target(of: draft.id))]
			let calledType = world.typeTable[Int(world.builtTypes[Int(target(of: draft.id))])]
			let opened: SeamSignature.Places.SendableFunctionOpened? = switch draft.opens {
			case .none, .instantiatorBuilder:
				nil
			case .sendableInstantiatorBuilder:
				call.property.map { .init(property: $0, function: .instantiator(builtType: calledType)) }
			case .sendableLazyWrapper:
				call.property.map { .init(property: $0, function: .sendableLazyWrapper(builtType: calledType)) }
			case .otherSendableFunction:
				call.property.map { .init(property: $0, function: .other) }
			}
			let pathSegment = call.property.map { [$0] } ?? []
			let listKey = ListKey(builtType: calledType, declarations: [], opensSendableFunction: opened, pathSegment: pathSegment)
			let listIndex: Int
			if let known = listIndexByKey[listKey] {
				listIndex = known
			} else {
				listIndex = lists.count
				listIndexByKey[listKey] = listIndex
				lists.append([])
			}
			// A fill whose fulfiller is a seam call is that call: its level is in the fill.
			let key = SeamSignature.Places.LevelKey(builtType: calledType, nextProperty: nil, isSeamRoot: false, isInFill: call.key.isFill || isInFill.contains(draft.id.variant), filledType: nil)
			let levelKey = LevelKey(declarationList: listIndex, key: key, nextPosition: -1, nextLoop: -1, closesOn: nil)
			let index: Int
			if let known = levelIndexByKey[levelKey] {
				index = known
			} else {
				index = assembled.count
				levelIndexByKey[levelKey] = index
				assembled.append(AssembledLevel(
					draft: draft,
					key: key,
					declarationList: listIndex,
					opensSendableFunction: opened,
					pathSegment: pathSegment,
					pathTypes: [SeamSignature.Hole.PathType(type: calledType, moduleName: call.scope.instantiable.moduleName)],
					closesOn: nil,
					hasNoNextPosition: true,
				))
			}
			passingUpLevelByCall[draft.id] = index
		}
		// A fill's entry level is enclosed by its call's level, and declares on the way what the filled seam's path does; the
		// fulfiller's levels are enclosed by the entry level, which declares the hole's property on the way.
		for (variant, entries) in fillEntriesByVariant.sorted(by: { $0.key < $1.key }) {
			for (entry, entryLevel) in zip(entries, entryLevelsByFillVariant[variant] ?? []) {
				guard let callLevel = inLineLevelByDraft[entry.call], !assembled[entryLevel].parents.contains(callLevel) else { continue }
				assembled[entryLevel].parents.append(callLevel)
				assembled[entryLevel].declaredSegmentByParent.append(entry.hole.declaredPathBeforePropertyInItsFill)
			}
		}
		// Each level's parents, in the order the drafts reach them, once each.
		for draft in levels + closingLevels {
			if let entries = fillEntriesByVariant[draft.id.variant], let entryLevels = entryLevelsByFillVariant[draft.id.variant] {
				for index in levelsByDraft[draft.id] ?? [] {
					for (entry, entryLevel) in zip(entries, entryLevels) where !assembled[index].parents.contains(entryLevel) {
						assembled[index].parents.append(entryLevel)
						assembled[index].declaredSegmentByParent.append([SeamSignature.Hole.DeclaredProperty(property: entry.hole.property, declaringType: entry.hole.ownerType, declarationLocation: entry.hole.declarationLocation)])
					}
				}
			} else {
				for index in levelsByDraft[draft.id] ?? [] {
					for parent in draft.parents where buildsInLine(parent) {
						guard let parentIndex = inLineLevelByDraft[parent], !assembled[index].parents.contains(parentIndex) else { continue }
						assembled[index].parents.append(parentIndex)
						assembled[index].declaredSegmentByParent.append(declaredSegment(of: draft, from: parent))
					}
				}
			}
		}
		for (call, index) in passingUpLevelByCall.sorted(by: { $0.value < $1.value }) {
			// A fill's call is enclosed by the fill's entry level, which declares the hole's property on the way, as the
			// fulfiller's levels are.
			let calls = world.calls(of: call.variant)
			if let entryLevel = entryLevelByCall[call], let entry = fillEntriesByVariant[calls[calls.startIndex + Int(call.edge)]]?.first(where: { $0.call == call }) {
				guard !assembled[index].parents.contains(entryLevel) else { continue }
				assembled[index].parents.append(entryLevel)
				assembled[index].declaredSegmentByParent.append([SeamSignature.Hole.DeclaredProperty(property: entry.hole.property, declaringType: entry.hole.ownerType, declarationLocation: entry.hole.declarationLocation)])
			} else {
				guard let parentIndex = inLineLevelByDraft[call], !assembled[index].parents.contains(parentIndex) else { continue }
				let callProperty = world.graph.nodes[Int(target(of: call))].property
				let parentInstantiable = node(of: call.variant).scope.instantiable
				assembled[index].parents.append(parentIndex)
				assembled[index].declaredSegmentByParent.append(callProperty.map { property in
					[SeamSignature.Hole.DeclaredProperty(property: property, declaringType: parentInstantiable.concreteInstantiable, declarationLocation: parentInstantiable.dependencies.first { $0.property == property }?.declarationLocation)]
				} ?? [])
			}
		}
		return SeamPlacesLevelAssembly(
			levels: assembled.map { level in
				SeamSignature.Places.Level(
					key: level.key,
					declarationList: level.declarationList,
					nextPosition: level.hasNoNextPosition || level.draft.nextPosition < 0 ? nil : Int(level.draft.nextPosition),
					nextLoop: level.hasNoNextPosition || level.draft.nextLoop < 0 ? nil : Int(level.draft.nextLoop),
					opensSendableFunction: level.opensSendableFunction,
					fillBaseStack: level.fillBaseStack,
					fillOwnerType: level.fillOwnerType,
					pathSegment: level.pathSegment,
					pathTypes: level.pathTypes,
					parents: level.parents,
					declaredSegmentByParent: level.declaredSegmentByParent,
					closesOn: level.closesOn,
				)
			},
			declarationLists: lists,
			draftedLevels: assembled.map(\.draft.id),
			inLineLevelByDraft: inLineLevelByDraft,
			passingUpLevelByCall: passingUpLevelByCall,
			entryLevelByCall: entryLevelByCall,
		)
	}
}

extension SeamPlacesLevelAssembly {
	/// How the assembled levels differ from the levels of `places`, a seam's stored graph: each level whole,
	/// its declarations, its parents' keys and what each parent declares on the way included, but its declarations' field
	/// access and places in their trees, which the assembly does not give yet. The first line is a count report. Test only.
	func differences(from places: SeamSignature.Places) -> [String] {
		func normalized(_ declaration: SeamSignature.Places.Declaration) -> SeamSignature.Places.Declaration {
			let field = declaration.field
			let normalized = SeamSignature.Places.Declaration(
				field: SeamSignature.Hole.Field(
					property: field.property,
					access: .internal,
					declaringType: field.declaringType,
					declarationLocation: field.declarationLocation,
					isReceivedOnlyIfAvailable: field.isReceivedOnlyIfAvailable,
					parameterTakingType: field.parameterTakingType,
					deferral: field.deferral,
					bindsMemo: field.bindsMemo,
					isSeamParameter: field.isSeamParameter,
					isBoundByPublicMockRoot: field.isBoundByPublicMockRoot,
					seamParameterOrigin: field.seamParameterOrigin,
				),
				isBoundBeforeNextProperty: declaration.isBoundBeforeNextProperty,
				builtAfter: declaration.builtAfter,
				reason: declaration.reason,
				isForwarded: declaration.isForwarded,
				cycleParameterOrigin: declaration.cycleParameterOrigin,
				alias: declaration.alias,
				isBoundFromCallersArgument: declaration.isBoundFromCallersArgument,
				isCycleParameter: declaration.isCycleParameter,
				isReboundByBuilderFunction: declaration.isReboundByBuilderFunction,
				isFieldOfSeamParameter: declaration.isFieldOfSeamParameter,
				fillFieldHiding: declaration.fillFieldHiding,
				buildability: declaration.buildability.map { .init(labelsHeldAboveSeam: $0.labelsHeldAboveSeam, placesInTree: []) },
			)
			return declaration.child.map(normalized.asChild) ?? normalized
		}
		func spelledKey(_ key: SeamSignature.Places.LevelKey) -> String {
			"\(key.builtType?.asSource ?? "fill") before \(key.nextProperty?.label ?? "fill")"
		}
		struct Spelling: Hashable {
			let key: String
			let fullKey: SeamSignature.Places.LevelKey
			let fillBaseStack: [SeamSignature.Places.StackEntry]
			let fillOwnerType: TypeDescription?
			let declarations: [SeamSignature.Places.Declaration]
			let nextPosition: Int?
			let nextLoop: Int?
			let opensSendableFunction: SeamSignature.Places.SendableFunctionOpened?
			let pathSegment: [Property]
			let pathTypes: [SeamSignature.Hole.PathType]
			let closesOn: SeamSignature.Places.StackEntry?
			let parents: [String]
		}
		func spellings(of levels: [SeamSignature.Places.Level], lists: [[SeamSignature.Places.Declaration]]) -> [Spelling] {
			levels.map { level in
				Spelling(
					key: spelledKey(level.key),
					fullKey: level.key,
					fillBaseStack: level.fillBaseStack,
					fillOwnerType: level.fillOwnerType,
					declarations: lists[level.declarationList].map(normalized),
					nextPosition: level.nextPosition,
					nextLoop: level.nextLoop,
					opensSendableFunction: level.opensSendableFunction,
					pathSegment: level.pathSegment,
					pathTypes: level.pathTypes,
					closesOn: level.closesOn,
					parents: zip(level.parents, level.declaredSegmentByParent).map { parent, segment in
						"\(spelledKey(levels[parent].key)) declaring \(segment.map { "\($0.property.label) by \($0.declaringType?.asSource ?? "none") at \(Dependency.DeclarationLocation.reportSpelling(of: $0.declarationLocation))" }.joined(separator: ", "))"
					}.sorted(),
				)
			}
		}
		let stored = spellings(of: places.levels, lists: places.declarationLists)
		let assembled = spellings(of: levels, lists: declarationLists)
		let assembledSet = Set(assembled)
		var assembledByKey = [String: [Spelling]]()
		for spelling in assembled {
			assembledByKey[spelling.key, default: []].append(spelling)
		}
		var differences = Set<String>()
		var alike = 0
		var alikeInFills = 0
		for (spelling, level) in zip(stored, places.levels) {
			guard !assembledSet.contains(spelling) else {
				if level.key.isInFill {
					alikeInFills += 1
				} else {
					alike += 1
				}
				continue
			}
			guard let candidates = assembledByKey[spelling.key] else {
				differences.insert("assembled levels: \(spelling.key): stored, none assembled: \(spelling.declarations.count) declarations, position \(spelling.nextPosition.map(String.init) ?? "none"), segment \(spelling.pathSegment.map(\.label).joined(separator: ".")), types \(spelling.pathTypes.map(\.type.asSource).joined(separator: ".")), parents \(spelling.parents.joined(separator: "; "))")
				continue
			}
			// Name the parts no assembled level of the key shares.
			let parts: [(String, (Spelling) -> String)] = [
				("key", { "in fill \($0.fullKey.isInFill) filled \($0.fullKey.filledType?.asSource ?? "none") case \($0.fullKey.filledCase.map { "\($0.caseIndex)" } ?? "none")" }),
				("fill stack", { "\($0.fillBaseStack.map { "\($0.property.label): \($0.concreteType.asSource)" }) owner \($0.fillOwnerType?.asSource ?? "none")" }),
				("declarations", { "\($0.declarations)" }),
				("position", { "\($0.nextPosition.map(String.init) ?? "none")" }),
				("loop", { "\($0.nextLoop.map(String.init) ?? "none")" }),
				("opens", { "\($0.opensSendableFunction.map { "\($0)" } ?? "none")" }),
				("segment", { $0.pathSegment.map(\.label).joined(separator: ".") }),
				("types", { "\($0.pathTypes)" }),
				("closes on", { $0.closesOn.map { "\($0.property.label): \($0.concreteType.asSource)" } ?? "none" }),
				("parents", { $0.parents.joined(separator: "; ") }),
			]
			for (name, part) in parts where !candidates.contains(where: { part($0) == part(spelling) }) {
				differences.insert("assembled levels: \(spelling.key): \(name): stored \(part(spelling)), assembled \(Set(candidates.map(part)).sorted().joined(separator: " | "))")
			}
		}
		let inFillCount = places.levels.count(where: \.key.isInFill)
		return ["report: assembled levels: \(places.levels.count - inFillCount) stored outside fills, \(levels.count) assembled, \(alike) alike, \(inFillCount) stored in fills, \(alikeInFills) alike"] + differences.sorted()
	}
}
