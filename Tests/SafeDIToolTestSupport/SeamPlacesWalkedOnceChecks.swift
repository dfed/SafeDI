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

import Foundation
import SafeDICore

/// Test only, deleted before merge: the place graph one walk of a seam's tree builds
/// (`DependencyTreeGenerator.placesWalkingTreeOnce`) must equal the graph the per-site walk builds, level for level and case
/// for case, numbered alike, and the walk must visit the per-site walk's sites with the same cases and routes.
/// `SeamPlacesOracle.mismatches(of:)` reports what this finds beside its own.
public enum SeamPlacesWalkedOnceChecks {
	public static func mismatches(of observation: SeamSignature.Places.Observation) -> [String] {
		guard let walked = observation.walkedOnce else { return [] }
		var found = [String]()
		func record(_ mismatch: String) {
			if found.count < 8 {
				found.append(mismatch)
			}
		}
		// The sites: every site of the seam's own tree, each once, with the per-site walk's case and route.
		let ownSiteIndices = observation.siteHoles.indices.filter { observation.siteHoles[$0].innerSeamType == nil }
		let ownPaths = ownSiteIndices.map { spelled(observation.siteHoles[$0].sitePath) }
		let walkedPaths = walked.sitePaths.map(spelled)
		if ownPaths.sorted() != walkedPaths.sorted() {
			record("sites: the per-site walk has \(ownPaths.count), the one walk \(walkedPaths.count); first only per-site \(Set(ownPaths).subtracting(walkedPaths).sorted().first ?? "none"), first only walked \(Set(walkedPaths).subtracting(ownPaths).sorted().first ?? "none")")
		}
		for index in observation.caseIndexBySite.indices {
			let path = spelled(observation.siteHoles[index].sitePath)
			if observation.caseIndexBySite[index] != walked.caseIndexBySite[index] {
				record("site \(path): case \(observation.caseIndexBySite[index]) per site, \(walked.caseIndexBySite[index]) walked once")
			}
			if observation.routeBySite[index] != walked.routeBySite[index] {
				record("site \(path): route \(observation.routeBySite[index].levels) per site, \(walked.routeBySite[index].levels) walked once")
			}
		}
		// The graph, record for record.
		let perSite = observation.places
		if perSite.levels.count != walked.places.levels.count {
			record("levels: \(perSite.levels.count) per site, \(walked.places.levels.count) walked once")
		}
		for (index, (level, walkedLevel)) in zip(perSite.levels, walked.places.levels).enumerated() where json(level) != json(walkedLevel) {
			record("level \(index): per site \(json(level)), walked once \(json(walkedLevel))")
		}
		if perSite.cases.count != walked.places.cases.count {
			record("cases: \(perSite.cases.count) per site, \(walked.places.cases.count) walked once")
		}
		for (index, (placeCase, walkedCase)) in zip(perSite.cases, walked.places.cases).enumerated() where json(placeCase) != json(walkedCase) {
			record("case \(index): per site \(json(placeCase)), walked once \(json(walkedCase))")
		}
		guard !found.isEmpty else { return [] }
		return ["The place graph one walk of `\(observation.seamType.asSource)` builds differs from the per-site walk's: " + found.joined(separator: "; ")]
	}

	private static func spelled(_ path: [Property]) -> String {
		path.map(\.label).joined(separator: ".")
	}

	private static func json(_ value: some Encodable) -> String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "unencodable"
	}
}
