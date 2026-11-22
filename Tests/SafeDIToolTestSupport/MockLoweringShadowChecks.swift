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
import Testing

/// Stage D1's shadow in the tests: the executors install `MockLoweringShadow.observer`, which tallies how the lowering
/// of each mock root compares with the emitter's code. The tally fails nothing until the switch pull request; it is
/// read as a report line (`reportLine`), which a process prints when it exits where `SAFEDI_MOCK_LOWERING_REPORT` is set.
public enum MockLoweringShadowChecks {
	/// Whether the executors leave the shadow off, which only the test that compares the output with it on and off sets.
	@TaskLocal public static var isDisabled = false

	/// The tally the executors' observer records into: the process's, but where a test that reads its own sets it.
	@TaskLocal public static var tally = Tally.process

	/// An observer that tallies each comparison in `tally`, then hands it to `enclosingObserver`; `nil` where the shadow is
	/// disabled, which leaves `enclosingObserver` as it is.
	public static func tallying(
		into tally: Tally = MockLoweringShadowChecks.tally,
		handingOn enclosingObserver: (@Sendable (MockLoweringShadow.Comparison) -> Void)?,
	) -> (@Sendable (MockLoweringShadow.Comparison) -> Void)? {
		guard !isDisabled else { return enclosingObserver }
		Tally.printsReportAtExitWhenAsked()
		return { comparison in
			tally.record(comparison)
			enclosingObserver?(comparison)
		}
	}

	/// The comparisons of the mock roots one process, or one test, generated, by outcome.
	public final class Tally: Sendable {
		/// The tally of every test of the process.
		public static let process = Tally()

		public init() {}

		public func record(_ comparison: MockLoweringShadow.Comparison) {
			if case let .unsupported(rule) = comparison.outcome,
			   let rules = ProcessInfo.processInfo.environment["SAFEDI_MOCK_LOWERING_LIST_RULES"],
			   rules.split(separator: ",").contains(Substring(rule.rawValue))
			{
				print("mock-lowering unsupported (\(rule.rawValue)): \(comparison.mockedType) in \(Test.current?.name ?? "?")")
			}
			if self === Tally.process, case .differs = comparison.outcome {
				print("mock-lowering differs: \(comparison.mockedType) in \(Test.current?.name ?? "?")")
			}
			lock.withLock {
				switch comparison.subject {
				case .mockCode:
					state.record(comparison)
				case .mergedCode, .moduleConfigurations:
					configurationState.record(comparison)
				}
			}
		}

		/// The share of mock roots whose lowering is byte-identical, with the differing and unsupported roots, the latter
		/// by rule in rule order: `mock-lowering: 12/40 roots identical (30.0%); 3 differ; unsupported: not yet ported 25`.
		public var reportLine: String {
			lock.withLock {
				state.reportLine(prefix: "mock-lowering", noun: "roots")
			}
		}

		/// The same for the configuration structs: each root's merged code and each module's shared configuration code,
		/// `mock-lowering structs: 12/40 identical (30.0%); …`.
		public var configurationReportLine: String {
			lock.withLock {
				configurationState.reportLine(prefix: "mock-lowering structs", noun: nil)
			}
		}

		/// Registers, once per process and only where `SAFEDI_MOCK_LOWERING_REPORT` is set, a handler that prints the
		/// process's report line to standard error when it exits.
		static func printsReportAtExitWhenAsked() {
			_ = registeredReportAtExit
		}

		private static let registeredReportAtExit: Bool = {
			guard ProcessInfo.processInfo.environment["SAFEDI_MOCK_LOWERING_REPORT"] != nil else { return false }
			atexit {
				FileHandle.standardError.write(Data((Tally.process.reportLine + "\n" + Tally.process.configurationReportLine + "\n").utf8))
			}
			return true
		}()

		private static let differencesKept = 20

		private struct State {
			var identical = 0
			var differing = 0
			var unsupportedByRule = [String: Int]()
			var firstDifferences = [MockLoweringShadow.Comparison]()

			mutating func record(_ comparison: MockLoweringShadow.Comparison) {
				switch comparison.outcome {
				case .identical:
					identical += 1
				case .differs:
					differing += 1
					if firstDifferences.count < Tally.differencesKept {
						firstDifferences.append(comparison)
					}
				case let .unsupported(rule):
					unsupportedByRule[rule.rawValue, default: 0] += 1
				}
			}

			func reportLine(prefix: String, noun: String?) -> String {
				let unsupported = unsupportedByRule.values.reduce(0, +)
				let total = identical + differing + unsupported
				let share = total == 0 ? 0 : Double(identical) * 100 / Double(total)
				var line = "\(prefix): \(identical)/\(total) \(noun.map { "\($0) " } ?? "")identical (\(String(format: "%.1f", share))%); \(differing) differ"
				let unsupportedRules = MockLowering.Rule.allCases.compactMap { rule in
					unsupportedByRule[rule.rawValue].map { "\(rule.rawValue) \($0)" }
				}
				if !unsupportedRules.isEmpty {
					line += "; unsupported: " + unsupportedRules.joined(separator: ", ")
				}
				for difference in firstDifferences {
					guard case let .differs(lineNumber, emitted, lowered) = difference.outcome else { continue }
					line += "\n  \(difference.mockedType) line \(lineNumber):\n    emitted: \(emitted ?? "(end)")\n    lowered: \(lowered ?? "(end)")"
				}
				return line
			}
		}

		private let lock = NSLock()
		nonisolated(unsafe) private var state = State()
		nonisolated(unsafe) private var configurationState = State()
	}
}
