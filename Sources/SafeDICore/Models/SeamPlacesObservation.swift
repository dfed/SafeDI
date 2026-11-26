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
	/// Test only, deleted before merge: a seam's places as today's per-site walk gives them, beside the place graph built for
	/// the same seam, which the differential oracle of the tests compares (`SeamPlacesOracle`). Nothing generated reads it.
	public struct Observation: Sendable {
		public init(seamType: TypeDescription, places: SeamSignature.Places, siteHoles: [SeamSignature.Hole], caseIndexBySite: [Int], routeBySite: [Route]) {
			self.seamType = seamType
			self.places = places
			self.siteHoles = siteHoles
			self.caseIndexBySite = caseIndexBySite
			self.routeBySite = routeBySite
		}

		/// The seam, or the public mock, whose places these are.
		public let seamType: TypeDescription
		/// The place graph built for the seam.
		public let places: SeamSignature.Places
		/// Today's holes, one per site, as the signature holds them once every per-site list is final.
		public let siteHoles: [SeamSignature.Hole]
		/// For each of `siteHoles`, the index in `places.cases` of its case, or `-1` for a place a call passes up, which no case
		/// holds yet.
		public let caseIndexBySite: [Int]
		/// For each of `siteHoles`, the levels the walk that built the graph took to the site's owner, root first; empty for a
		/// place a call passes up.
		public let routeBySite: [Route]
	}

	/// Test only, deleted before merge: called with each seam's places when its holes are computed, while a test observes.
	@TaskLocal public static var observer: (@Sendable (Observation) -> Void)?
}
