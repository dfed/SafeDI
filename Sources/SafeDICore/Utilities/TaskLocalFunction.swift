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

/// A function held in a task-local value. A `@TaskLocal` whose value is a function, optional or not, crashes in Swift
/// 6.3's release builds (Swift 6.3.3 on Linux, "Bad pointer dereference at 0xfffffffffffffff8" in
/// `swift_task_localValuePush`) whenever `withValue` binds it, `nil` included, while a struct holding the function binds
/// in every build; Swift 6.2.4 and 6.4.3 bind either. So every task-local function is held in this struct, which
/// `SourceRuleTests`' `taskLocalFunction` rule enforces, and is called as the function it holds.
public struct TaskLocalFunction<Function: Sendable>: Sendable {
	// MARK: Initialization

	public init<Argument, Result>(_ function: @escaping @Sendable (Argument) -> Result) where Function == @Sendable (Argument) -> Result {
		self.function = function
	}

	public init<First, Second, Result>(_ function: @escaping @Sendable (First, Second) -> Result) where Function == @Sendable (First, Second) -> Result {
		self.function = function
	}

	public init<First, Second, Third, Result>(_ function: @escaping @Sendable (First, Second, Third) -> Result) where Function == @Sendable (First, Second, Third) -> Result {
		self.function = function
	}

	public init<First, Second, Third, Fourth, Fifth, Result>(_ function: @escaping @Sendable (First, Second, Third, Fourth, Fifth) -> Result) where Function == @Sendable (First, Second, Third, Fourth, Fifth) -> Result {
		self.function = function
	}

	// MARK: Public

	/// The function this value holds.
	public let function: Function

	public func callAsFunction<Argument, Result>(_ argument: Argument) -> Result where Function == @Sendable (Argument) -> Result {
		function(argument)
	}

	public func callAsFunction<First, Second, Result>(_ first: First, _ second: Second) -> Result where Function == @Sendable (First, Second) -> Result {
		function(first, second)
	}

	public func callAsFunction<First, Second, Third, Result>(_ first: First, _ second: Second, _ third: Third) -> Result where Function == @Sendable (First, Second, Third) -> Result {
		function(first, second, third)
	}
}
