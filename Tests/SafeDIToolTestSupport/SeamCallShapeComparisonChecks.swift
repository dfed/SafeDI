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

import SafeDICore

extension SeamPlaceLevels {
	/// Test only, deleted before merge: where comparing a seam's own signature with the callers' with a hole per case of
	/// their call shapes finds otherwise than comparing them with a hole per site (`SeamPlaceLevels.CallShapeComparison`).
	var callShapeComparisonMismatches: [String] {
		guard let comparison = callShapeComparison, comparison.differsPerSite != comparison.differsPerCase else { return [] }
		return ["The call shapes of `\(seamType.asSource)`’s own and callers’ signatures \(comparison.differsPerSite ? "differ" : "agree") with a hole per site, but \(comparison.differsPerCase ? "differ" : "agree") with a hole per case"]
	}

	/// Test only, deleted before merge: where a signature's call shape holds less of a case's places than its holes per
	/// site do (`SeamPlaceLevels.CallShapeFold`): each case's hole takes the builder labels every site of the case has,
	/// the narrowest of their accesses, and per label every field one of them carries, and each site of no case keeps its
	/// own hole. So two signatures whose holes per site differ, other than in which site carries a field, differ per case.
	var callShapeFoldMismatches: [String] {
		guard let fold = callShapeFold else { return [] }
		let seamName = "`\(seamType.asSource)`"
		func caseOfSite(_ site: Int) -> Int? {
			guard fold.caseIndexBySite.indices.contains(site), fold.caseHasAccess.indices.contains(fold.caseIndexBySite[site]), fold.caseHasAccess[fold.caseIndexBySite[site]] else { return nil }
			return fold.caseIndexBySite[site]
		}
		var mismatches = [String]()
		var position = 0
		var casesFound = Set<Int>()
		for (site, siteHole) in fold.siteHoles.enumerated() {
			let caseIndex = caseOfSite(site)
			guard caseIndex.map({ !casesFound.contains($0) }) ?? true else { continue }
			guard position < fold.caseHoles.count else {
				mismatches.append("The call shape of \(seamName) holds \(fold.caseHoles.count) holes, fewer than its places’ cases and sites of no case")
				break
			}
			guard let caseIndex else {
				if fold.caseHoles[position] != siteHole {
					mismatches.append("The call shape of \(seamName) holds otherwise than its site \(site), which is of no case")
				}
				position += 1
				continue
			}
			casesFound.insert(caseIndex)
			let caseHole = fold.caseHoles[position]
			position += 1
			let sitesOfCase = fold.siteHoles.indices.filter { caseOfSite($0) == caseIndex }.map { fold.siteHoles[$0] }
			for other in sitesOfCase where other.builderLabel != caseHole.builderLabel || other.narrowerTierBuilderLabels != caseHole.narrowerTierBuilderLabels {
				mismatches.append("The call shape of \(seamName) builds case \(caseIndex) with `\(caseHole.builderLabel)`, where one of its sites builds with `\(other.builderLabel)`")
			}
			if sitesOfCase.map(\.tierAccess).min() != caseHole.tierAccess {
				mismatches.append("The call shape of \(seamName) takes case \(caseIndex) at `\(caseHole.tierAccess)`, not at its sites’ narrowest access")
			}
			let siteFields = Dictionary(grouping: sitesOfCase.flatMap(\.fields), by: \.label).mapValues(Set.init)
			let caseFields = Dictionary(grouping: caseHole.fields, by: \.label).mapValues(Set.init)
			if siteFields != caseFields {
				mismatches.append("The call shape of \(seamName) holds fields \(caseHole.fields.map { "\($0.label): \($0.type)" }) for case \(caseIndex), whose sites carry \(siteFields.keys.sorted().map { label in "\(label): \(siteFields[label, default: []].map(\.type).sorted())" })")
			}
		}
		if position < fold.caseHoles.count {
			mismatches.append("The call shape of \(seamName) holds \(fold.caseHoles.count) holes, more than its places’ cases and sites of no case")
		}
		return mismatches
	}
}
