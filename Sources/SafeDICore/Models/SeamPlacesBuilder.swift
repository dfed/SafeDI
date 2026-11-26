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
	}

	private struct LevelVariant {
		var draft: LevelDraft
		var parents = [Int]()
		var declaredSegmentByParent = [[SeamSignature.Hole.DeclaredProperty]]()
		/// The sites already in each declaration's `placesInTree`, so a site reached on many routes is listed once.
		var placesInTreeSeen: [Set<SeamSignature.Hole.Site>]

		init(draft: LevelDraft) {
			self.draft = draft
			placesInTreeSeen = draft.declarations.map { Set($0.placesInTree) }
		}
	}

	private struct CaseDraft {
		let ownerLevel: Int
		let isBuiltInSendableFunction: Bool
		let siteOpensSendableFunction: Bool
		var isPassedOnSendable = false
		var calledCopyDeclarations = UnionOfDistinct<SeamSignature.Hole.UncarriedDeclaration>()
		var uncarriedReplacedOnPathsToCalls = UnionOfDistinct<SeamSignature.Hole.UncarriedDeclaration>()
		var reenteringCallDeclarations = UnionOfDistinct<SeamSignature.Hole.ReenteringCallDeclaration>()
		var reenteringPlaceFields = UnionOfDistinct<SeamSignature.Hole.ReenteringPlaceField>()
	}

	private struct CaseKey: Hashable {
		let ownerLevel: Int
		let isBuiltInSendableFunction: Bool
	}

	private struct EdgeKey: Hashable {
		let level: Int
		let parent: Int
	}

	private var variants = [LevelVariant]()
	private var variantIndexByProjection = [VariantProjection: Int]()
	private var edges = Set<EdgeKey>()
	private var cases = [CaseDraft]()
	private var caseIndexByKey = [CaseKey: Int]()
	private var caseIndexBySite = [SeamSignature.Hole.Site: Int]()

	/// Adds the levels of one site's path, root first, and returns the index of the site's case and the route its levels
	/// make.
	mutating func addSite(
		_ site: SeamSignature.Hole.Site,
		levels: [LevelDraft],
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
		let key = CaseKey(ownerLevel: route.last ?? 0, isBuiltInSendableFunction: isBuiltInSendableFunction)
		let caseIndex: Int
		if let known = caseIndexByKey[key] {
			caseIndex = known
		} else {
			caseIndex = cases.count
			caseIndexByKey[key] = caseIndex
			cases.append(CaseDraft(ownerLevel: key.ownerLevel, isBuiltInSendableFunction: isBuiltInSendableFunction, siteOpensSendableFunction: siteOpensSendableFunction))
		}
		caseIndexBySite[site] = caseIndex
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
	) {
		cases[caseIndex].isPassedOnSendable = cases[caseIndex].isPassedOnSendable || isPassedOnSendable
		cases[caseIndex].calledCopyDeclarations.add(calledCopyDeclarations)
		cases[caseIndex].uncarriedReplacedOnPathsToCalls.add(uncarriedReplacedOnPathsToCalls)
		cases[caseIndex].reenteringCallDeclarations.add(reenteringCallDeclarations)
		cases[caseIndex].reenteringPlaceFields.add(reenteringPlaceFields)
	}

	/// The graph, each declaration's places in its tree mapped to their cases, a site of no case left out, and each case
	/// named by the route in `namingRouteByCase`.
	func places(namingRouteByCase: [Int: [Int]]) -> SeamSignature.Places {
		let levels = variants.map { variant in
			SeamSignature.Places.Level(
				key: variant.draft.key,
				declarations: variant.draft.declarations.map { draft in
					guard let buildability = draft.declaration.buildability else { return draft.declaration }
					return draft.declaration.withBuildability(SeamSignature.Places.Buildability(
						labelsHeldAboveSeam: buildability.labelsHeldAboveSeam,
						placesInTree: draft.placesInTree.compactMap { caseIndexBySite[$0] }.uniqued(),
					))
				},
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
		return SeamSignature.Places(
			levels: levels,
			cases: cases.enumerated().map { caseIndex, draft in
				SeamSignature.Places.Case(
					ownerLevel: draft.ownerLevel,
					isBuiltInSendableFunction: draft.isBuiltInSendableFunction,
					siteOpensSendableFunction: draft.siteOpensSendableFunction,
					passedUp: nil,
					isPassedOnSendable: draft.isPassedOnSendable,
					calledCopyDeclarations: draft.calledCopyDeclarations.elements,
					uncarriedReplacedOnPathsToCalls: draft.uncarriedReplacedOnPathsToCalls.elements,
					reenteringCallDeclarations: draft.reenteringCallDeclarations.elements,
					reenteringPlaceFields: draft.reenteringPlaceFields.elements,
					namingRoute: namingRouteByCase[caseIndex] ?? [],
				)
			},
		)
	}

	/// The index of the variant `draft` is of: every fact of the level but the sites of the places in a declaration's tree,
	/// which differ by path and become one case, and the edge it was reached by.
	private mutating func variantIndex(of draft: LevelDraft) -> Int {
		let projection = VariantProjection(
			key: draft.key,
			declarations: draft.declarations.map(\.declaration),
			opensSendableFunction: draft.opensSendableFunction,
			cycleReentries: draft.cycleReentries,
			fillBaseStack: draft.fillBaseStack,
			fillOwnerType: draft.fillOwnerType,
			pathSegment: draft.pathSegment,
			pathTypes: draft.pathTypes,
		)
		if let known = variantIndexByProjection[projection] {
			// A declaration's tree holds the places of every route through the level: a place's family, and so its case, can
			// differ by the route above.
			for (index, declaration) in draft.declarations.enumerated() {
				for site in declaration.placesInTree where variants[known].placesInTreeSeen[index].insert(site).inserted {
					variants[known].draft.declarations[index].placesInTree.append(site)
				}
			}
			return known
		}
		variantIndexByProjection[projection] = variants.count
		variants.append(LevelVariant(draft: draft))
		return variants.count - 1
	}

	/// Every fact of a level but its declarations' places in their trees, source locations included. Types compare as types
	/// (`any Service` equals `Service`), not as spelled: every fact of a level comes from the declarations of its type and of
	/// the edge above it, which spell each type once, so two routes to one level spell its types alike. The tests' oracle
	/// compares every place's fields, spelling included, with the per-site walk's.
	private struct VariantProjection: Hashable {
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
		)
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
		)
	}
}
