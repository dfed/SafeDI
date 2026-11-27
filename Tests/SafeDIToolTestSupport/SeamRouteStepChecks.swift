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
	/// Test only, deleted before merge: each route a seam's enums nested by type computed whose steps differ from its
	/// edges' steps (`SeamRouteStepObservation`), each bound at the step's own path length. Holds while the seam's tree reads a
	/// route per place, and lets that tree read the steps by edge instead.
	var routeStepMismatches: [String] {
		routeSteps.compactMap { observation in
			ConstructionMemoChecks.difference(between: observation.computed, and: observation.rebuilt).map { difference in
				"The route of \(observation.seamType.asSource) to \(observation.sitePath.map(\.label).joined(separator: ".")) differs from its edges’ steps:\n\(difference)"
			}
		}
	}
}
