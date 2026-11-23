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
import Testing
@testable import SafeDIToolTestSupport

struct SafeDIToolGraphFuzzerAPIVersionTests {
	@Test(.enabled(if: ProcessInfo.processInfo.environment["SAFEDI_API_VERSION_AGREEMENT_SEEDS"] != nil, "Set SAFEDI_API_VERSION_AGREEMENT_SEEDS to run"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func longRun_findsNoDisagreement_whenEnabledByEnvironment() async throws {
		let environment = ProcessInfo.processInfo.environment
		let seeds = Self.seeds(from: environment["SAFEDI_API_VERSION_AGREEMENT_SEEDS"] ?? "")
		let report = GraphFuzzerReport(path: environment["SAFEDI_API_VERSION_AGREEMENT_REPORT"])
		report.append("api-version-agreement seeds=\(seeds.count)")
		guard compileVerificationIsEnabled else {
			report.append("problem The agreement oracle compiles generated code. Unset SAFEDI_SKIP_COMPILE_CHECK.")
			Issue.record("The agreement oracle compiles generated code. Unset SAFEDI_SKIP_COMPILE_CHECK.")
			return
		}
		let start = Date()
		let verdicts = try await GraphFuzzerAPIVersionAgreement.verdicts(forSeeds: seeds)
		var classCounts = [GraphFuzzerReleaseAcceptanceClass: Int]()
		var unbuildableBuilderProbeCount = 0
		var unbuildableBuilderGraphCount = 0
		var mockProbeCount = 0
		for verdict in verdicts {
			classCounts[verdict.verdict.verdictClass, default: 0] += 1
			mockProbeCount += verdict.verdict.mockProbeCount
			unbuildableBuilderProbeCount += verdict.unbuildableBuilderProbeCount
			if verdict.unbuildableBuilderProbeCount > 0 {
				unbuildableBuilderGraphCount += 1
			}
			report.append("seed \(verdict.seed) \(verdict.verdict.classDescription) roots=\(verdict.verdict.rootProbeCount) mocks=\(verdict.verdict.mockProbeCount) d12=\(verdict.unbuildableBuilderProbeCount)")
			guard verdict.verdict.verdictClass.isBreak || verdict.verdict.verdictClass == .valuesNotCompared else { continue }
			for detailLine in verdict.verdict.details.split(separator: "\n") {
				report.append("    \(detailLine)")
			}
			Issue.record(Comment(rawValue: "Seed \(verdict.seed): .v3Unstable class \(verdict.verdict.verdictClass.rawValue) against .v2\n\(verdict.verdict.details)"))
		}
		report.append("classes " + GraphFuzzerReleaseAcceptanceClass.allCases.sorted().map { "\($0.rawValue)=\(classCounts[$0, default: 0])" }.joined(separator: " "))
		report.append("probes mocks=\(mockProbeCount) d12=\(unbuildableBuilderProbeCount) d12-graphs=\(unbuildableBuilderGraphCount)")
		report.append("cpu wall=\(Int(Date().timeIntervalSince(start).rounded()))")
		report.append("completed \(verdicts.count)")
	}

	/// The seeds `specification` names: `a..<b`, or a comma-separated list.
	static func seeds(from specification: String) -> [UInt64] {
		let bounds = specification.components(separatedBy: "..<")
		if bounds.count == 2, let lower = UInt64(bounds[0]), let upper = UInt64(bounds[1]) {
			return Array(lower..<upper)
		}
		return specification.split(separator: ",").compactMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }
	}
}
