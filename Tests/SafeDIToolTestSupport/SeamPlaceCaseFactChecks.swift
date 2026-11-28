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
	/// Deleted when places come from facts: each place whose own facts differ from what its case answers for every place of the
	/// case, where a reader takes the case's answer instead of each place's (`SeamPlaceCaseFactChecks`).
	var placeCaseFactMismatches: [String] {
		placesObservation.map(SeamPlaceCaseFactChecks.mismatches(of:)) ?? []
	}
}

enum SeamPlaceCaseFactChecks {
	static func mismatches(of observation: SeamSignature.Places.Observation) -> [String] {
		var mismatches = [String]()
		var firstSpellingByCase = [Int: (spelling: Spelling, path: String)]()
		let query = SeamSignature.Places.Query(of: observation.places, calledPlaces: observation.calledPlaces(of:))
		for (hole, caseIndex) in zip(observation.siteHoles, observation.caseIndexBySite) where caseIndex >= 0 {
			let place = "\(observation.seamType.asSource) at \(hole.sitePath.map(\.label).joined(separator: "."))"
			// A builder that reaches the case is no wider than the narrowest of its places (`shapedBuilders`).
			let own = SeamSignature.Places.Case.Access(level: hole.tierAccess, cause: hole.accessCause)
			if let narrowest = observation.places.cases[caseIndex].narrowestAccess {
				if own != narrowest {
					mismatches.append("The access of the place of \(place) is \(own), its case’s narrowest \(narrowest)")
				}
			} else {
				mismatches.append("The case of the place of \(place) holds no access")
			}
			// The scope enums' readers that take one place of a case for all of them: the builder's form and the wrapper's
			// spelling (`LevelBuilderForms`, `PlaceSpelling`), the forwarded type an enum names, a case's return type and the
			// dispatcher's wrapper builder (`ScopeGenerator`), each from the place's property; and whether the place is below the
			// called type's root (`MockOrchestration`), from its path's length, which the case's naming route gives.
			// A place a call presents is below the root of the seam that holds it, or not, as the naming route of that seam's
			// case says (`Query.holdingCase(of:)`): the route of the presenting case leads to the call. Seams that call each
			// other settle over several passes, and on a pass before the last the calls can lead to a case of another place,
			// which is not compared.
			let isBelowRoot = hole.sitePath.count > 1
			if let holding = query.holdingCase(of: caseIndex) {
				let holdingPlaces = holding.query.places
				let holdingCase = holdingPlaces.cases[holding.caseIndex]
				let holdsThePlace = observation.places.cases[caseIndex].passedUp == nil
					|| (holdingPlaces.levels.first(where: \.key.isSeamRoot)?.key.builtType == hole.site.seamType && holdingPlaces.levels[holdingCase.ownerLevel].key.nextProperty == hole.property)
				if holdsThePlace, isBelowRoot != (holdingCase.namingRoute.count > 1) {
					mismatches.append("The place of \(place) is \(isBelowRoot ? "" : "not ")below its seam’s root, its case’s naming route of \(holdingCase.namingRoute.count) levels says otherwise")
				}
			}
			let spelling = Spelling(of: hole)
			if let first = firstSpellingByCase[caseIndex] {
				if first.spelling != spelling {
					mismatches.append("The place of \(place) spells \(spelling), its case’s first place at \(first.path) spells \(first.spelling)")
				}
			} else {
				firstSpellingByCase[caseIndex] = (spelling, hole.sitePath.map(\.label).joined(separator: "."))
			}
		}
		return mismatches
	}

	/// What a reader that takes one place of a case reads of it, each spelled: the property's type decides whether the place
	/// is held in an instantiator.
	private struct Spelling: Equatable, CustomStringConvertible {
		init(of hole: SeamSignature.Hole) {
			property = hole.property.asSource
			wrapper = hole.property.typeDescription.unwrapped.strippingEscaping.asSource
			forwarded = hole.forwardedType?.strippingEscaping.asSource
			ownerType = hole.ownerType.asSource
		}

		let property: String
		let wrapper: String
		let forwarded: String?
		let ownerType: String

		var description: String {
			"\(ownerType).\(property) (\(wrapper) forwarding \(forwarded ?? "nothing"))"
		}
	}
}
