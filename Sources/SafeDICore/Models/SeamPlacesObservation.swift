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
	/// The place graph's test read, deleted when places come from facts: a seam's places as today's per-site walk gives
	/// them, beside the place graph built for the same seam, which the differential oracle of the tests compares
	/// (`SeamPlacesOracle`). Nothing generated reads it.
	/// It rides on the levels a test observes (`SeamPlaceLevels.placesObservation`), so a test sets no task-local value of its
	/// own for it.
	public struct Observation: Sendable {
		/// The place graph of a seam or public mock a call in the tree presents places of.
		public struct CalledPlaces: Sendable {
			public init(seamType: TypeDescription, isPublicMock: Bool, called: Called, placesOfSeamsBeneath: @escaping @Sendable (CalledCase) -> Called?) {
				self.seamType = seamType
				self.isPublicMock = isPublicMock
				self.called = called
				self.placesOfSeamsBeneath = placesOfSeamsBeneath
			}

			public let seamType: TypeDescription
			public let isPublicMock: Bool
			/// The called seam's graph and places, as the call takes them.
			public let called: Called
			public var places: SeamSignature.Places {
				called.places
			}

			/// What the called seam's own passed-up cases refer into.
			public let placesOfSeamsBeneath: @Sendable (CalledCase) -> Called?
		}

		/// What `reference` refers into: the called seam of a direct call, or one a called seam's own passed-up case refers
		/// into, or `nil` where the run holds none.
		public func called(of reference: CalledCase) -> Called? {
			if let direct = calledPlaces.first(where: { $0.seamType == reference.seamType && $0.isPublicMock == reference.isPublicMock }) {
				direct.called
			} else {
				calledPlaces.lazy.compactMap { $0.placesOfSeamsBeneath(reference) }.first
			}
		}

		/// The graph `reference` refers into (`called(of:)`), which a query takes.
		public func calledPlaces(of reference: CalledCase) -> SeamSignature.Places? {
			called(of: reference)?.places
		}

		public init(seamType: TypeDescription, places: SeamSignature.Places, siteHoles: [SeamSignature.Hole], caseIndexBySite: [Int], routeBySite: [Route], laterRoutesOfPassedUpCases: [(caseIndex: Int, route: Route)] = [], calledPlaces: [CalledPlaces] = [], walkedOnce: WalkedOnce? = nil) {
			self.calledPlaces = calledPlaces
			self.seamType = seamType
			self.places = places
			self.siteHoles = siteHoles
			self.caseIndexBySite = caseIndexBySite
			self.routeBySite = routeBySite
			self.laterRoutesOfPassedUpCases = laterRoutesOfPassedUpCases
			self.walkedOnce = walkedOnce
		}

		/// The place graph one walk of the seam's tree built (`DependencyTreeGenerator.placesWalkingTreeOnce`), which must equal
		/// `places`, with what that walk gave each of `siteHoles`, in the same order: its case and its route, for a place a call
		/// passes up the first call's, and the paths of the sites of the seam's own tree it visited.
		public struct WalkedOnce: Sendable {
			public init(places: SeamSignature.Places, sitePaths: [[Property]], caseIndexBySite: [Int], routeBySite: [Route]) {
				self.places = places
				self.sitePaths = sitePaths
				self.caseIndexBySite = caseIndexBySite
				self.routeBySite = routeBySite
			}

			public let places: SeamSignature.Places
			/// The sites of the seam's own tree the walk visited, in the order it visited them.
			public let sitePaths: [[Property]]
			public let caseIndexBySite: [Int]
			public let routeBySite: [Route]
		}

		/// The place graph one walk of the seam's tree built, beside the one the per-site walk built.
		public let walkedOnce: WalkedOnce?

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
		/// For a place several calls present, the case and route of each call after the first, whose route `routeBySite` holds.
		public let laterRoutesOfPassedUpCases: [(caseIndex: Int, route: Route)]
		/// The graphs of the seams and public mocks whose places a call in the tree presents, one per such call.
		public let calledPlaces: [CalledPlaces]
	}
}
