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

// A seam's whole place graph assembled from its facts drafts, in place of the walk's, where a test turns the switch on
// (`NodeRecordsObservation.assemblesPlacesFromFacts`): what the oracle runs the generator on. The per-case additions
// the facts do not give yet (the called copies, the declarations replaced on paths to calls, the re-entering
// declarations) are carried over from the walk's case each assembled case matches.

extension SeamPlacesDrafts {
	/// The graph assembled from the drafts, with each of `stored`'s cases' index in it: the assembled case of the same
	/// spelling (`SeamPlacesLevelAssembly.spellings(of:levels:)`), else the first of the same kind, family and owner, each
	/// assembled case matched once; `nil` for a stored case none matches.
	func assembledPlaces(parameters: [SeamSignature.Parameter], access: SeamPlacesFieldAccess, replacing stored: SeamSignature.Places) -> (places: SeamSignature.Places, assembledIndexOfStoredCase: [Int?]) {
		let assembly = assembledLevels(parameters: parameters, access: access)
		let caseAssembly = assembly.cases(of: self, access: access)
		var fold = SeamPlacesCaseAssembly.PlacesInTreeFold(drafts: self, cases: caseAssembly)
		// Each child's places in its tree, the union over the levels that share its list.
		struct ListedDeclaration: Hashable {
			let list: Int
			let declaration: Int
		}
		var placesByListed = [ListedDeclaration: [Int]]()
		for (level, draft) in zip(assembly.levels, assembly.draftedLevels) where level.key.builtType != nil {
			let declaration = world.declaration(of: draft.variant)
			let targets = world.edges(from: declaration)
			let familyFlags = [(SeamPlacesFamilies.plain, false), (.sendable, true)].filter { families[Int(draft.variant)].contains($0.0) }.map(\.1)
			for (index, listed) in assembly.declarationLists[level.declarationList].enumerated() where listed.buildability != nil {
				guard let edge = targets.firstIndex(where: { !world.graph.nodes[Int($0)].key.isFill && world.graph.nodes[Int($0)].property == listed.field.property }) else { continue }
				let edgeLevel = SeamPlacesLevelID(variant: draft.variant, edge: Int32(edge - targets.startIndex))
				let found = (familyFlags.isEmpty ? [false] : familyFlags).flatMap { fold.cases(beneath: edgeLevel, isSendable: $0) }
				let key = ListedDeclaration(list: level.declarationList, declaration: index)
				placesByListed[key] = ((placesByListed[key] ?? []) + found).uniqued()
			}
		}
		let lists = assembly.declarationLists.enumerated().map { listIndex, list in
			list.enumerated().map { index, declaration in
				guard let buildability = declaration.buildability else { return declaration }
				return declaration.withBuildability(SeamSignature.Places.Buildability(
					labelsHeldAboveSeam: buildability.labelsHeldAboveSeam,
					placesInTree: placesByListed[ListedDeclaration(list: listIndex, declaration: index)] ?? [],
				))
			}
		}
		// Each stored case's match among the assembled ones.
		let assembledSpellings = SeamPlacesLevelAssembly.spellings(of: caseAssembly.cases, levels: assembly.levels)
		let storedSpellings = SeamPlacesLevelAssembly.spellings(of: stored.cases, levels: stored.levels)
		func head(_ spelling: String) -> Substring {
			spelling.prefix { $0 != ";" }
		}
		var unmatched = Set(caseAssembly.cases.indices)
		var assembledIndexOfStoredCase = [Int?]()
		for storedSpelling in storedSpellings {
			let match = caseAssembly.cases.indices.first { unmatched.contains($0) && assembledSpellings[$0] == storedSpelling }
				?? caseAssembly.cases.indices.first { unmatched.contains($0) && head(assembledSpellings[$0]) == head(storedSpelling) }
			if let match {
				unmatched.remove(match)
			}
			assembledIndexOfStoredCase.append(match)
		}
		var storedCaseOfAssembled = [Int: Int]()
		for (storedIndex, assembledIndex) in assembledIndexOfStoredCase.enumerated() {
			if let assembledIndex {
				storedCaseOfAssembled[assembledIndex] = storedIndex
			}
		}
		let cases = caseAssembly.cases.enumerated().map { index, placeCase in
			let storedCase = storedCaseOfAssembled[index].map { stored.cases[$0] }
			return SeamSignature.Places.Case(
				ownerLevel: placeCase.ownerLevel,
				isBuiltInSendableFunction: placeCase.isBuiltInSendableFunction,
				siteOpensSendableFunction: placeCase.siteOpensSendableFunction,
				passedUp: placeCase.passedUp,
				firstCasePresentingSamePlaces: placeCase.firstCasePresentingSamePlaces,
				isPassedOnSendable: placeCase.isPassedOnSendable,
				calledCopyDeclarations: storedCase?.calledCopyDeclarations ?? [],
				uncarriedReplacedOnPathsToCalls: storedCase?.uncarriedReplacedOnPathsToCalls ?? [],
				reenteringCallDeclarations: storedCase?.reenteringCallDeclarations ?? [],
				reenteringPlaceFields: storedCase?.reenteringPlaceFields ?? [],
				namingRoute: placeCase.namingRoute,
				narrowestAccess: placeCase.narrowestAccess,
			)
		}
		return (SeamSignature.Places(levels: assembly.levels, cases: cases, declarationLists: lists), assembledIndexOfStoredCase)
	}
}
