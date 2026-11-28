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

/// Checks, for every production root, that a root whose tree today reports a label no one parameter can pass is one the
/// plan's detector keeps on today's tree: the detector may fire where today reports nothing, never the other way.
enum UnpassableCycleLabelChecks {
	/// Runs `operation` while checking each root, handing each to `enclosingObserver` too, and records an issue for each
	/// root whose tree reports a label the detector missed.
	static func checking<Result>(
		handingOn enclosingObserver: TaskLocalFunction<@Sendable (_ root: String, _ detectorFires: Bool, _ todaysTreeReports: Bool) -> Void>?,
		_ operation: () async throws -> Result,
	) async throws -> Result {
		try await UnpassableCycleLabelObservation.$observer.withValue(TaskLocalFunction { root, detectorFires, todaysTreeReports in
			if todaysTreeReports, !detectorFires {
				Issue.record(Comment(rawValue: "The tree of \(root) reports a label no one parameter can pass, which the plan’s detector does not keep on today’s tree."))
			}
			enclosingObserver?(root, detectorFires, todaysTreeReports)
		}) {
			try await UnpassableCycleLabelObservation.$factsObserver.withValue(TaskLocalFunction { root, factsLabels, todaysTreeLabels, factsParameterLines, todaysTreeParameterLines in
				if factsLabels != todaysTreeLabels {
					Issue.record(Comment(rawValue: "UNPASSABLE-FACTS The facts of \(root) find \(factsLabels) where its tree reports \(todaysTreeLabels)."))
				}
				if factsParameterLines != todaysTreeParameterLines {
					Issue.record(Comment(rawValue: "CYCLE-FUNCTION-PARAMETERS The facts of \(root) find \(factsParameterLines) where its tree declares \(todaysTreeParameterLines)."))
				}
			}) {
				try await operation()
			}
		}
	}
}
