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

/// How SafeDITool evaluated one `#if` condition that guards SafeDI declarations.
///
/// SafeDITool scans sources before the compiler runs and takes the compilation conditions it was
/// given as complete, so a decision can be wrong when the build defines a condition the SafeDI
/// integration did not report. ``compileTimeAssertions(for:)`` turns each decision into an `#error`
/// directive the generated code carries, so a wrong decision fails the build where the generated code
/// is compiled, naming the condition.
public struct ConditionalCompilationDecision: Codable, Hashable, Comparable, Sendable {
	// MARK: Initialization

	/// - Parameters:
	///   - condition: The source of the `#if` or `#elseif` condition, e.g. `DEBUG && !STAGING`.
	///   - isActive: Whether SafeDITool evaluated the condition as true.
	public init(condition: String, isActive: Bool) {
		self.condition = condition
		self.isActive = isActive
	}

	// MARK: Public

	public let condition: String
	public let isActive: Bool

	/// Swift source that fails to compile wherever the compiler disagrees with any of `decisions`,
	/// or an empty string when there are none. Emitted after the header of each generated file.
	public static func compileTimeAssertions(for decisions: [Self]) -> String {
		Set(decisions)
			.sorted()
			.map { decision in
				let assertedCondition = decision.isActive ? "!(\(decision.condition))" : decision.condition
				let assumption = decision.isActive ? "active" : "inactive"
				let contradiction = decision.isActive ? "inactive" : "active"
				let message = "SafeDI scanned this module assuming `#if \(decision.condition)` was \(assumption), but it is \(contradiction) in this compilation. Report the conditions this target compiles with to SafeDITool, as the \\\"Reporting active conditions\\\" section of the SafeDI manual describes for your build system."
				return "#if \(assertedCondition)\n#error(\"\(message)\")\n#endif\n\n"
			}
			.joined()
	}

	public static func < (lhs: Self, rhs: Self) -> Bool {
		(lhs.condition, lhs.isActive ? 1 : 0) < (rhs.condition, rhs.isActive ? 1 : 0)
	}
}
