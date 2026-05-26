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

public struct UnevaluableConditionalCompilationConditionError: Error, CustomStringConvertible, Equatable, Sendable {
	public let condition: String
	public let suggestedActiveCondition: String?

	public init(
		condition: String,
		suggestedActiveCondition: String? = nil,
	) {
		self.condition = condition
		self.suggestedActiveCondition = suggestedActiveCondition
	}

	public var description: String {
		if let suggestedActiveCondition {
			"Unable to evaluate conditional compilation condition `\(condition)` while scanning SafeDI declarations. Pass the active condition to SafeDITool with `--active-compilation-conditions \(suggestedActiveCondition)`, or remove the SafeDI declaration from the conditional branch."
		} else {
			"Unable to evaluate conditional compilation condition `\(condition)` while scanning SafeDI declarations. SafeDITool can only evaluate boolean literals, `!`, `&&`, `||`, parentheses, and active custom compilation conditions while scanning SafeDI declarations."
		}
	}
}
