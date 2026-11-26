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

/// Builds a seam's place graph (`SeamSignature.Places`) from the levels today's per-site walk (`fields(of:)` in
/// `SeamBuilderParameters`) gives each site, root first: a level variant once, however many paths reach it, with an edge
/// per parent it is reached from, and a case per owner level and family.
///
/// A step of the change that holds places by case: it reads the per-site walk, so it is as costly as that walk, and adds to
/// its cost the encoding of each level of each site's path. The walk that builds the graph directly, once per level variant,
/// replaces it. It holds its drafts for one computation of a seam's holes.
struct SeamPlacesBuilder {
	/// A declaration of a level, with the sites of the places of the tree it instantiates where a type above the seam could
	/// build that tree, which become cases once every site has one.
	struct DeclarationDraft {
		var declaration: SeamSignature.Places.Declaration
		var placesInTree: [SeamSignature.Hole.Site]
	}

	/// A level of one site's path, with the edge from the level before it.
	struct LevelDraft {
		let key: SeamSignature.Places.LevelKey
		var declarations: [DeclarationDraft]
		let opensSendableFunction: SeamSignature.Places.SendableFunctionOpened?
		var cycleReentries: [SeamSignature.Places.CycleReentry]
		let fillBaseStack: [SeamSignature.Places.StackEntry]
		let fillOwnerType: TypeDescription?
		let pathSegment: [Property]
		let pathTypes: [SeamSignature.Hole.PathType]
		/// The properties the code declares on the edge from the level before.
		let declaredSegment: [SeamSignature.Hole.DeclaredProperty]
		/// The position of the next property among the scope's children, and its loop of received builders.
		let nextPosition: Int?
		let nextLoop: Int?
	}

	private struct LevelVariant {
		let draft: LevelDraft
		let declarationList: Int
		var parents = [Int]()
		var declaredSegmentByParent = [[SeamSignature.Hole.DeclaredProperty]]()
	}

	/// The declarations every level of one build of a type holds, whatever its next property.
	private struct DeclarationList {
		var declarations: [DeclarationDraft]
		/// The sites already in each declaration's `placesInTree`, so a site reached on many routes is listed once.
		var placesInTreeSeen: [Set<SeamSignature.Hole.Site>]

		init(declarations: [DeclarationDraft]) {
			self.declarations = declarations
			placesInTreeSeen = declarations.map { Set($0.placesInTree) }
		}
	}

	private struct CaseDraft {
		let ownerLevel: Int
		let passedUp: SeamSignature.Places.CalledCase?
		let isBuiltInSendableFunction: Bool
		let siteOpensSendableFunction: Bool
		var isPassedOnSendable = false
		var calledCopyDeclarations = UnionOfDistinct<SeamSignature.Hole.UncarriedDeclaration>()
		var uncarriedReplacedOnPathsToCalls = UnionOfDistinct<SeamSignature.Hole.UncarriedDeclaration>()
		var reenteringCallDeclarations = UnionOfDistinct<SeamSignature.Hole.ReenteringCallDeclaration>()
		var reenteringPlaceFields = UnionOfDistinct<SeamSignature.Hole.ReenteringPlaceField>()
		var narrowestAccess: SeamSignature.Places.Case.Access?
	}

	private struct CaseKey: Hashable {
		let ownerLevel: Int
		let isBuiltInSendableFunction: Bool
		/// For a place a call presents, the called seam's case: its seam, whether it is a public mock's, and its index.
		var innerSeamType: TypeDescription?
		var innerIsPublicMock = false
		var innerCaseIndex = 0
	}

	private struct EdgeKey: Hashable {
		let level: Int
		let parent: Int
	}

	private var variants = [LevelVariant]()
	private var variantIndexByProjection = [VariantProjection: Int]()
	private var lists = [DeclarationList]()
	private var listIndexByProjection = [ListProjection: Int]()
	private var edges = Set<EdgeKey>()
	private var cases = [CaseDraft]()
	private var caseIndexByKey = [CaseKey: Int]()
	private var caseIndexBySite = [SeamSignature.Hole.Site: Int]()
	/// For each case, itself or a case before it that presents a site it presents: the cases that present the same places
	/// lead to one case, the first of them.
	private var earlierCasePresentingSamePlaces = [Int]()

	/// Adds the levels of one site's path, root first, and returns the index of the site's case and the route its levels
	/// make.
	mutating func addSite(
		_ site: SeamSignature.Hole.Site,
		levels: [LevelDraft],
		isBuiltInSendableFunction: Bool,
		siteOpensSendableFunction: Bool,
	) -> (caseIndex: Int, route: SeamSignature.Places.Route) {
		let (caseIndex, route) = addCase(levels: levels, passedUp: nil, isBuiltInSendableFunction: isBuiltInSendableFunction, siteOpensSendableFunction: siteOpensSendableFunction)
		caseIndexBySite[site] = caseIndex
		return (caseIndex, route)
	}

	/// Adds the levels of the path to a call that presents `site`, a place of the seam it calls, root first, the last the
	/// level that declares the call, and returns the index of the case of that call and of `reference`, the called seam's
	/// case, and the route to the call. A site several calls present keeps the case of the call added first.
	mutating func addPassedUpPlace(
		_ site: SeamSignature.Hole.Site,
		levels: [LevelDraft],
		reference: SeamSignature.Places.CalledCase,
		isBuiltInSendableFunction: Bool,
		siteOpensSendableFunction: Bool,
	) -> (caseIndex: Int, route: SeamSignature.Places.Route) {
		let (caseIndex, route) = addCase(levels: levels, passedUp: reference, isBuiltInSendableFunction: isBuiltInSendableFunction, siteOpensSendableFunction: siteOpensSendableFunction)
		if let firstCase = caseIndexBySite[site] {
			// The cases of two sites that share a case present the places of one case of the seam that holds them, so the
			// cases of both sites lead to one first case: the earlier of the two each led to.
			let first = firstCasePresentingSamePlaces(as: firstCase)
			let other = firstCasePresentingSamePlaces(as: caseIndex)
			earlierCasePresentingSamePlaces[max(first, other)] = min(first, other)
		} else {
			caseIndexBySite[site] = caseIndex
		}
		return (caseIndex, route)
	}

	/// The first case that presents the places the case at `caseIndex` presents, each case passed on the way led to it
	/// directly, so the next walk from it is one step.
	private mutating func firstCasePresentingSamePlaces(as caseIndex: Int) -> Int {
		var first = caseIndex
		while earlierCasePresentingSamePlaces[first] != first {
			first = earlierCasePresentingSamePlaces[first]
		}
		earlierCasePresentingSamePlaces[caseIndex] = first
		return first
	}

	private mutating func addCase(
		levels: [LevelDraft],
		passedUp: SeamSignature.Places.CalledCase?,
		isBuiltInSendableFunction: Bool,
		siteOpensSendableFunction: Bool,
	) -> (caseIndex: Int, route: SeamSignature.Places.Route) {
		var route = [Int]()
		for draft in levels {
			let index = variantIndex(of: draft)
			if let parent = route.last, edges.insert(EdgeKey(level: index, parent: parent)).inserted {
				variants[index].parents.append(parent)
				variants[index].declaredSegmentByParent.append(draft.declaredSegment)
			}
			route.append(index)
		}
		var key = CaseKey(ownerLevel: route.last ?? 0, isBuiltInSendableFunction: isBuiltInSendableFunction)
		if let passedUp {
			key.innerSeamType = passedUp.seamType
			key.innerIsPublicMock = passedUp.isPublicMock
			key.innerCaseIndex = passedUp.caseIndex
		}
		let caseIndex: Int
		if let known = caseIndexByKey[key] {
			caseIndex = known
		} else {
			caseIndex = cases.count
			caseIndexByKey[key] = caseIndex
			earlierCasePresentingSamePlaces.append(caseIndex)
			cases.append(CaseDraft(ownerLevel: key.ownerLevel, passedUp: passedUp, isBuiltInSendableFunction: isBuiltInSendableFunction, siteOpensSendableFunction: siteOpensSendableFunction))
		}
		return (caseIndex, SeamSignature.Places.Route(levels: route))
	}

	/// Adds what the calls and fills on a site's path add to its place (`SeamSignature.Places.Case`'s stored facts).
	mutating func addPresentation(
		ofCase caseIndex: Int,
		isPassedOnSendable: Bool,
		calledCopyDeclarations: [SeamSignature.Hole.UncarriedDeclaration],
		uncarriedReplacedOnPathsToCalls: [SeamSignature.Hole.UncarriedDeclaration],
		reenteringCallDeclarations: [SeamSignature.Hole.ReenteringCallDeclaration],
		reenteringPlaceFields: [SeamSignature.Hole.ReenteringPlaceField],
		access: SeamSignature.Places.Case.Access,
	) {
		// The first place in site order of the narrowest access keeps its cause.
		if cases[caseIndex].narrowestAccess.map({ access.level < $0.level }) ?? true {
			cases[caseIndex].narrowestAccess = access
		}
		cases[caseIndex].isPassedOnSendable = cases[caseIndex].isPassedOnSendable || isPassedOnSendable
		cases[caseIndex].calledCopyDeclarations.add(calledCopyDeclarations)
		cases[caseIndex].uncarriedReplacedOnPathsToCalls.add(uncarriedReplacedOnPathsToCalls)
		cases[caseIndex].reenteringCallDeclarations.add(reenteringCallDeclarations)
		cases[caseIndex].reenteringPlaceFields.add(reenteringPlaceFields)
	}

	// The one walk of a seam's tree (`DependencyTreeGenerator.placesWalkingTreeOnce`) adds a level once per scope and next
	// property, and a case once per site, through these.

	/// What tells apart the declaration list of every level that has every fact of `draft`'s but its next property
	/// (`declarationListIndex(of:)`).
	func listProjection(of draft: LevelDraft) -> ListProjection {
		ListProjection(
			key: SeamSignature.Places.LevelKey(builtType: draft.key.builtType, nextProperty: nil, isSeamRoot: draft.key.isSeamRoot, isInFill: draft.key.isInFill, filledType: draft.key.filledType, filledCase: draft.key.filledCase),
			declarations: draft.declarations.map(\.declaration),
			opensSendableFunction: draft.opensSendableFunction,
			cycleReentries: draft.cycleReentries,
			fillBaseStack: draft.fillBaseStack,
			fillOwnerType: draft.fillOwnerType,
			pathSegment: draft.pathSegment,
			pathTypes: draft.pathTypes,
		)
	}

	/// Adds the level `draft`, whose declaration list's projection is `listProjection`, beneath `parent`, and the edge from
	/// `parent` where it is new, and returns the level's index. The places in its declarations' trees are added apart, by
	/// `addPlacesInTree`.
	mutating func addLevel(_ draft: LevelDraft, listProjection: ListProjection, parent: Int?) -> Int {
		let listIndex = listIndexByProjection[listProjection] ?? addList(draft, projection: listProjection)
		let index = variantIndex(of: draft, inList: listIndex)
		if let parent, edges.insert(EdgeKey(level: index, parent: parent)).inserted {
			variants[index].parents.append(parent)
			variants[index].declaredSegmentByParent.append(draft.declaredSegment)
		}
		return index
	}

	/// Adds the sites of the places the tree of the declaration at `declarationIndex` of the level at `level` holds on one
	/// route through the level to those of the routes before it, each once.
	mutating func addPlacesInTree(_ sites: [SeamSignature.Hole.Site], ofDeclaration declarationIndex: Int, atLevel level: Int) {
		addPlacesInTree(sites, ofDeclaration: declarationIndex, inList: variants[level].declarationList)
	}

	/// Adds `site`'s place to the case of its owner level and family, and returns the case's index. For a place a call
	/// presents, `ownerLevel` is the call's level and `passedUp` the called seam's case; a site several calls present keeps
	/// the case of the call added first.
	mutating func addCase(
		ofSite site: SeamSignature.Hole.Site,
		ownerLevel: Int,
		passedUp: SeamSignature.Places.CalledCase?,
		isBuiltInSendableFunction: Bool,
		siteOpensSendableFunction: Bool,
	) -> Int {
		var key = CaseKey(ownerLevel: ownerLevel, isBuiltInSendableFunction: isBuiltInSendableFunction)
		if let passedUp {
			key.innerSeamType = passedUp.seamType
			key.innerIsPublicMock = passedUp.isPublicMock
			key.innerCaseIndex = passedUp.caseIndex
		}
		let caseIndex: Int
		if let known = caseIndexByKey[key] {
			caseIndex = known
		} else {
			caseIndex = cases.count
			caseIndexByKey[key] = caseIndex
			earlierCasePresentingSamePlaces.append(caseIndex)
			cases.append(CaseDraft(ownerLevel: ownerLevel, passedUp: passedUp, isBuiltInSendableFunction: isBuiltInSendableFunction, siteOpensSendableFunction: siteOpensSendableFunction))
		}
		if passedUp == nil || caseIndexBySite[site] == nil {
			caseIndexBySite[site] = caseIndex
		} else if let firstCase = caseIndexBySite[site] {
			// As `addPassedUpPlace`: the cases of two sites that share a case lead to one first case.
			let first = firstCasePresentingSamePlaces(as: firstCase)
			let other = firstCasePresentingSamePlaces(as: caseIndex)
			earlierCasePresentingSamePlaces[max(first, other)] = min(first, other)
		}
		return caseIndex
	}

	/// The graph, each declaration's places in its tree mapped to their cases, a site of no case left out, and each case
	/// named by the route in `namingRouteByCase`.
	func places(namingRouteByCase: [Int: [Int]]) -> SeamSignature.Places {
		let declarationLists = lists.map { list in
			list.declarations.map { draft in
				guard let buildability = draft.declaration.buildability else { return draft.declaration }
				return draft.declaration.withBuildability(SeamSignature.Places.Buildability(
					labelsHeldAboveSeam: buildability.labelsHeldAboveSeam,
					placesInTree: draft.placesInTree.compactMap { caseIndexBySite[$0] }.uniqued(),
				))
			}
		}
		let levels = variants.map { variant in
			SeamSignature.Places.Level(
				key: variant.draft.key,
				declarationList: variant.declarationList,
				nextPosition: variant.draft.nextPosition,
				nextLoop: variant.draft.nextLoop,
				opensSendableFunction: variant.draft.opensSendableFunction,
				cycleReentries: variant.draft.cycleReentries,
				fillBaseStack: variant.draft.fillBaseStack,
				fillOwnerType: variant.draft.fillOwnerType,
				pathSegment: variant.draft.pathSegment,
				pathTypes: variant.draft.pathTypes,
				parents: variant.parents,
				declaredSegmentByParent: variant.declaredSegmentByParent,
			)
		}
		// A case leads to an earlier one or to itself, so the first case of each is known once those before it are.
		var firstCaseByCase = [Int]()
		for (caseIndex, earlier) in earlierCasePresentingSamePlaces.enumerated() {
			firstCaseByCase.append(earlier == caseIndex ? caseIndex : firstCaseByCase[earlier])
		}
		return SeamSignature.Places(
			levels: levels,
			cases: cases.enumerated().map { caseIndex, draft in
				SeamSignature.Places.Case(
					ownerLevel: draft.ownerLevel,
					isBuiltInSendableFunction: draft.isBuiltInSendableFunction,
					siteOpensSendableFunction: draft.siteOpensSendableFunction,
					passedUp: draft.passedUp,
					firstCasePresentingSamePlaces: firstCaseByCase[caseIndex] == caseIndex ? nil : firstCaseByCase[caseIndex],
					isPassedOnSendable: draft.isPassedOnSendable,
					calledCopyDeclarations: draft.calledCopyDeclarations.elements,
					uncarriedReplacedOnPathsToCalls: draft.uncarriedReplacedOnPathsToCalls.elements,
					reenteringCallDeclarations: draft.reenteringCallDeclarations.elements,
					reenteringPlaceFields: draft.reenteringPlaceFields.elements,
					namingRoute: namingRouteByCase[caseIndex] ?? [],
					narrowestAccess: draft.narrowestAccess,
				)
			},
			declarationLists: declarationLists,
		)
	}

	/// The index of the variant `draft` is of: every fact of the level but the sites of the places in a declaration's tree,
	/// which differ by path and become one case, and the edge it was reached by.
	private mutating func variantIndex(of draft: LevelDraft) -> Int {
		variantIndex(of: draft, inList: declarationListIndex(of: draft))
	}

	/// The index of the variant of `draft`, whose declaration list is at `listIndex`.
	private mutating func variantIndex(of draft: LevelDraft, inList listIndex: Int) -> Int {
		let projection = VariantProjection(declarationList: listIndex, key: draft.key, nextPosition: draft.nextPosition, nextLoop: draft.nextLoop)
		if let known = variantIndexByProjection[projection] {
			return known
		}
		variantIndexByProjection[projection] = variants.count
		variants.append(LevelVariant(draft: draft, declarationList: listIndex))
		return variants.count - 1
	}

	/// The index of the declaration list of every level that has every fact of `draft`'s but its next property.
	private mutating func declarationListIndex(of draft: LevelDraft) -> Int {
		let projection = listProjection(of: draft)
		guard let known = listIndexByProjection[projection] else {
			return addList(draft, projection: projection)
		}
		// A declaration's tree holds the places of every route through the levels: a place's family, and so its case, can
		// differ by the route above.
		for (index, declaration) in draft.declarations.enumerated() {
			addPlacesInTree(declaration.placesInTree, ofDeclaration: index, inList: known)
		}
		return known
	}

	/// Adds the declaration list of `draft`, whose projection is `projection`, and returns its index.
	private mutating func addList(_ draft: LevelDraft, projection: ListProjection) -> Int {
		listIndexByProjection[projection] = lists.count
		lists.append(DeclarationList(declarations: draft.declarations))
		return lists.count - 1
	}

	private mutating func addPlacesInTree(_ sites: [SeamSignature.Hole.Site], ofDeclaration declarationIndex: Int, inList listIndex: Int) {
		for site in sites where lists[listIndex].placesInTreeSeen[declarationIndex].insert(site).inserted {
			lists[listIndex].declarations[declarationIndex].placesInTree.append(site)
		}
	}

	/// A level's facts: its declaration list's, and the next property's.
	private struct VariantProjection: Hashable {
		let declarationList: Int
		let key: SeamSignature.Places.LevelKey
		let nextPosition: Int?
		let nextLoop: Int?
	}

	/// Every fact of a level but its next property and its declarations' places in their trees, source locations included.
	/// Types compare as types (`any Service` equals `Service`), not as spelled: every fact of a level comes from the
	/// declarations of its type and of the edge above it, which spell each type once, so two routes to one level spell its
	/// types alike. The tests' oracle compares every place's fields, spelling included, with the per-site walk's.
	struct ListProjection: Hashable {
		let key: SeamSignature.Places.LevelKey
		let declarations: [SeamSignature.Places.Declaration]
		let opensSendableFunction: SeamSignature.Places.SendableFunctionOpened?
		let cycleReentries: [SeamSignature.Places.CycleReentry]
		let fillBaseStack: [SeamSignature.Places.StackEntry]
		let fillOwnerType: TypeDescription?
		let pathSegment: [Property]
		let pathTypes: [SeamSignature.Hole.PathType]
	}
}

/// The distinct elements added, in the order first added.
private struct UnionOfDistinct<Element: Hashable> {
	private(set) var elements = [Element]()
	private var seen = Set<Element>()

	mutating func add(_ newElements: [Element]) {
		for element in newElements where seen.insert(element).inserted {
			elements.append(element)
		}
	}
}

extension SeamSignature.Places.Declaration {
	/// The declaration with `buildability` in place of its own.
	func withBuildability(_ buildability: SeamSignature.Places.Buildability) -> Self {
		Self(
			field: field,
			isBoundBeforeNextProperty: isBoundBeforeNextProperty,
			builtAfter: builtAfter,
			reason: reason,
			isForwarded: isForwarded,
			cycleParameterOrigin: cycleParameterOrigin,
			alias: alias,
			isBoundFromCallersArgument: isBoundFromCallersArgument,
			isCycleParameter: isCycleParameter,
			isReboundByBuilderFunction: isReboundByBuilderFunction,
			isFieldOfSeamParameter: isFieldOfSeamParameter,
			fillFieldHiding: fillFieldHiding,
			buildability: buildability,
		).keepingChild(of: self)
	}

	/// The declaration marked as a fill's field bound from a parameter of the filled seam, or not.
	func withFieldOfSeamParameter(_ isFieldOfSeamParameter: Bool) -> Self {
		Self(
			field: field,
			isBoundBeforeNextProperty: isBoundBeforeNextProperty,
			builtAfter: builtAfter,
			reason: reason,
			isForwarded: isForwarded,
			cycleParameterOrigin: cycleParameterOrigin,
			alias: alias,
			isBoundFromCallersArgument: isBoundFromCallersArgument,
			isCycleParameter: isCycleParameter,
			isReboundByBuilderFunction: isReboundByBuilderFunction,
			isFieldOfSeamParameter: isFieldOfSeamParameter,
			fillFieldHiding: fillFieldHiding,
			buildability: buildability,
		).keepingChild(of: self)
	}

	/// The declaration with `other`'s child facts, if it has any.
	private func keepingChild(of other: Self) -> Self {
		other.child.map(asChild) ?? self
	}
}
