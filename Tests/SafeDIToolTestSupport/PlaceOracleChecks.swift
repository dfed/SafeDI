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
import Testing

extension PlaceObservation {
	/// An observer that records an issue for each place whose plan does not hold what its kind holds, then hands the
	/// observation on to `enclosingObserver`.
	static func checkingPlaces(handingOn enclosingObserver: (@Sendable (PlaceObservation) -> Void)?) -> @Sendable (PlaceObservation) -> Void {
		{ observation in
			for violation in observation.violations {
				Issue.record(Comment(rawValue: violation))
			}
			enclosingObserver?(observation)
		}
	}
}

/// What `operation` returns, with the place observations of every production body the tool generates while it runs, in
/// the order it generates them.
func collectingPlaceObservations<Result>(during operation: () async throws -> Result) async rethrows -> (result: Result, observations: [PlaceObservation]) {
	let (stream, continuation) = AsyncStream.makeStream(of: PlaceObservation.self)
	let enclosingObserver = PlaceObservation.observer
	let result = try await PlaceObservation.$observer.withValue({ observation in
		continuation.yield(observation)
		enclosingObserver?(observation)
	}) {
		try await operation()
	}
	continuation.finish()
	var observations = [PlaceObservation]()
	for await observation in stream {
		observations.append(observation)
	}
	return (result, observations)
}
