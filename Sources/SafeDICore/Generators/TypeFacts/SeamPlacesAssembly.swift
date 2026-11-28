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
}

extension SeamPlacesDrafts {
	/// The levels outside fills and their declaration lists, from the drafted levels. A drafted level becomes a level for
	/// each way its next edge is entered: built in line, and closing a cycle on an entry above, where some route to it does
	/// each. Levels alike in everything but their parents are one level with every parent. A level's parents are the levels
	/// whose next edge builds its scope in line, since a call that closes a cycle enters no body.
	func assembledLevelsOutsideFills(parameters: [SeamSignature.Parameter]) -> SeamPlacesLevelAssembly {
		let drafter = SeamPlacesDeclarationDrafter(drafts: self, parameters: parameters)
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
			let builtType: TypeDescription
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
			let pathSegment: [Property]
			let pathTypes: [SeamSignature.Hole.PathType]
			let closesOn: SeamSignature.Places.StackEntry?
			/// Whether the level is a passing-up call's, which `draft` encloses: it has no next property.
			var isPassingUpCall = false
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
		for draft in levels + closingLevels where draft.fill == nil && !node(of: draft.id.variant).key.isFill {
			let variantNode = node(of: draft.id.variant)
			let instantiable = variantNode.scope.instantiable
			let builtType = instantiable.concreteInstantiable
			let opened = opensSendableFunction(into: draft)
			let pathSegment = draft.id.variant == rootVariant ? [] : variantNode.property.map { [$0] } ?? []
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
			let key = SeamSignature.Places.LevelKey(builtType: builtType, nextProperty: next.key.isFill ? nil : next.property, isSeamRoot: draft.id.variant == rootVariant, isInFill: false, filledType: nil)
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
		for draft in levels where draft.fill == nil && !node(of: draft.id.variant).key.isFill && buildsInLine(draft.id) && !world.passUps(of: Int(target(of: draft.id))).isEmpty {
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
			let key = SeamSignature.Places.LevelKey(builtType: calledType, nextProperty: nil, isSeamRoot: false, isInFill: false, filledType: nil)
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
					isPassingUpCall: true,
				))
			}
			passingUpLevelByCall[draft.id] = index
		}
		// Each level's parents, in the order the drafts reach them, once each.
		for draft in levels + closingLevels {
			for index in levelsByDraft[draft.id] ?? [] {
				for parent in draft.parents where buildsInLine(parent) {
					guard let parentIndex = inLineLevelByDraft[parent], !assembled[index].parents.contains(parentIndex) else { continue }
					assembled[index].parents.append(parentIndex)
					assembled[index].declaredSegmentByParent.append(declaredSegment(of: draft, from: parent))
				}
			}
		}
		for (call, index) in passingUpLevelByCall.sorted(by: { $0.value < $1.value }) {
			guard let parentIndex = inLineLevelByDraft[call], !assembled[index].parents.contains(parentIndex) else { continue }
			let callProperty = world.graph.nodes[Int(target(of: call))].property
			let parentInstantiable = node(of: call.variant).scope.instantiable
			assembled[index].parents.append(parentIndex)
			assembled[index].declaredSegmentByParent.append(callProperty.map { property in
				[SeamSignature.Hole.DeclaredProperty(property: property, declaringType: parentInstantiable.concreteInstantiable, declarationLocation: parentInstantiable.dependencies.first { $0.property == property }?.declarationLocation)]
			} ?? [])
		}
		return SeamPlacesLevelAssembly(
			levels: assembled.map { level in
				SeamSignature.Places.Level(
					key: level.key,
					declarationList: level.declarationList,
					nextPosition: level.isPassingUpCall || level.draft.nextPosition < 0 ? nil : Int(level.draft.nextPosition),
					nextLoop: level.isPassingUpCall || level.draft.nextLoop < 0 ? nil : Int(level.draft.nextLoop),
					opensSendableFunction: level.opensSendableFunction,
					fillBaseStack: [],
					fillOwnerType: nil,
					pathSegment: level.pathSegment,
					pathTypes: level.pathTypes,
					parents: level.parents,
					declaredSegmentByParent: level.declaredSegmentByParent,
					closesOn: level.closesOn,
				)
			},
			declarationLists: lists,
			draftedLevels: assembled.map(\.draft.id),
		)
	}
}

extension SeamPlacesLevelAssembly {
	/// How the assembled levels differ from the levels outside fills of `places`, a seam's stored graph: each level whole,
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
					declarations: lists[level.declarationList].map(normalized),
					nextPosition: level.nextPosition,
					nextLoop: level.nextLoop,
					opensSendableFunction: level.opensSendableFunction,
					pathSegment: level.pathSegment,
					pathTypes: level.pathTypes,
					closesOn: level.closesOn,
					parents: zip(level.parents, level.declaredSegmentByParent).map { parent, segment in
						"\(spelledKey(levels[parent].key)) declaring \(segment.map { "\($0.property.label) by \($0.declaringType?.asSource ?? "none") at \($0.declarationLocation.map { "\($0.order) \($0.placement)" } ?? "none")" }.joined(separator: ", "))"
					}.sorted(),
				)
			}
		}
		let storedLevels = places.levels.filter { !$0.key.isInFill }
		let stored = spellings(of: places.levels, lists: places.declarationLists).enumerated().filter { !places.levels[$0.offset].key.isInFill }.map(\.element)
		let assembled = spellings(of: levels, lists: declarationLists)
		let assembledSet = Set(assembled)
		var assembledByKey = [String: [Spelling]]()
		for spelling in assembled {
			assembledByKey[spelling.key, default: []].append(spelling)
		}
		var differences = Set<String>()
		var alike = 0
		for spelling in stored {
			guard !assembledSet.contains(spelling) else {
				alike += 1
				continue
			}
			guard let candidates = assembledByKey[spelling.key] else {
				differences.insert("assembled levels: \(spelling.key): stored, none assembled")
				continue
			}
			// Name the parts no assembled level of the key shares.
			let parts: [(String, (Spelling) -> String)] = [
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
		return ["report: assembled levels: \(storedLevels.count) stored outside fills, \(levels.count) assembled, \(alike) alike"] + differences.sorted()
	}
}
