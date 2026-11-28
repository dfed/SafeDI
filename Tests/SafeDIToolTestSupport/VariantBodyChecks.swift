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

/// Checks, for every place of a production root's tree, that a body built from the scope's copy with call places,
/// beneath only the answers its path gives the labels the body is keyed by, passes `nil` to the receives today's build
/// of the place passes `nil` to.
enum VariantBodyChecks {
	/// Runs `operation` while comparing each place with its body, handing each comparison to `enclosingObserver` too, and
	/// records an issue for each place whose body passes `nil` otherwise.
	static func comparing<Result>(
		handingOn enclosingObserver: TaskLocalFunction<@Sendable (_ place: String, _ todaysUnavailableProperties: [String], _ bodysUnavailableProperties: [String]) -> Void>?,
		_ operation: () async throws -> Result,
	) async throws -> Result {
		try await VariantBodyObservation.$observer.withValue(TaskLocalFunction { place, todaysUnavailableProperties, bodysUnavailableProperties in
			if todaysUnavailableProperties != bodysUnavailableProperties {
				Issue.record(Comment(rawValue: """
				The body of \(place) passes nil to other receives than today's build of the place:
				today: \(todaysUnavailableProperties)
				body: \(bodysUnavailableProperties)
				"""))
			}
			enclosingObserver?(place, todaysUnavailableProperties, bodysUnavailableProperties)
		}) {
			try await operation()
		}
	}
}
