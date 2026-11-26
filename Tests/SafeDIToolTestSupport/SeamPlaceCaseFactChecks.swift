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
	/// Test only, deleted before merge: each place whose own facts differ from what its case answers for every place of the
	/// case, where a reader takes the case's answer instead of each place's (`SeamPlaceCaseFactChecks`).
	var placeCaseFactMismatches: [String] {
		placesObservation.map(SeamPlaceCaseFactChecks.mismatches(of:)) ?? []
	}
}

enum SeamPlaceCaseFactChecks {
	static func mismatches(of observation: SeamSignature.Places.Observation) -> [String] {
		var mismatches = [String]()
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
		}
		return mismatches
	}
}
