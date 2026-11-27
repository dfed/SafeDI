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

/// The statements a builder function's body writes before the value it returns, each the lines one statement writes: a
/// child's code, a seam call's guard line, a member call, a fill place's binding, a loop member's rebinding. No statement
/// is empty: every scope a body emits writes a line (`.claude/rules/emission-decisions.md`, "Empty chunks").
struct BuilderBody: Sendable {
	let statements: [GeneratedCode]
	/// Whether the body writes `return ` before its value though it writes no statement: the function of a constant a
	/// kind builds in a function whatever its body holds (`BuiltPlaceRecord.functionAlwaysWritesReturn`), as a mock does
	/// for a node whose construction reads a field of its configuration.
	var alwaysWritesReturn = false

	/// Whether the body writes anything before its value. A constant whose body writes nothing is constructed in place,
	/// with no builder function.
	var hasStatements: Bool {
		!statements.isEmpty
	}

	/// What precedes the value on the body's last line: `return ` after statements and where a record says so
	/// (`alwaysWritesReturn`), and nothing in any other body that is only its value, which Swift returns implicitly. One
	/// rule for every builder function the production emitter writes: a constant's, an instantiator's, a lazy wrapper's and a loop member's `_received` function. A mock's builder functions
	/// keep a rule of their own, over the six kinds of line they write (`ScopeGenerator.generateInstantiatorBinding`).
	var returnKeyword: String {
		hasStatements || alwaysWritesReturn ? "return " : ""
	}
}
