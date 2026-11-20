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

/// Which fills of one call a dispatcher's case, or a public mock's level function, holds in place of calling the fill's
/// function, as far as that is decided without the fill's text. Whether the text can be held (`ScopeGenerator.inlinedFill`)
/// is still read from the text, until fills are planned as builder functions (`.claude/rules/emission-decisions.md`).
struct FillInlining: Sendable {
	/// The fills the call's tree may hold in place (`ScopeGenerator.inlinableFillKeys`).
	let inlinableFillKeys: Set<String>
	/// For a call of another module's public mock, the fills its level functions call with their own values
	/// (`PublicMockLevelFunctions.keysOfFillsCalledWithOwnValues`); `nil` for a seam's call.
	let publicMockInlinableFillKeys: Set<String>?
	/// The fills an override closure of the call is handed a function over, which call the fill's function.
	let overrideFillKeys: Set<String>
	/// The fills a case of a dispatcher that returns its level's builder struct targets.
	let keysTargetedByBuilderStructDispatchers: Set<String>

	/// Whether the fill of `key` may be held in place, before its text is read.
	func mayHold(_ key: String) -> Bool {
		inlinableFillKeys.contains(key) && (publicMockInlinableFillKeys?.contains(key) ?? true) && !overrideFillKeys.contains(key)
	}

	/// Whether the fill of `key`, whose body declares a function where `declaresFunction`, keeps its function: a builder
	/// struct's member holds the fill's body in a closure, inside which no function is declared, since one declared there
	/// can be isolated as the code around the closure is.
	func keepsFunction(_ key: String, declaresFunction: Bool) -> Bool {
		declaresFunction && (publicMockInlinableFillKeys != nil || keysTargetedByBuilderStructDispatchers.contains(key))
	}
}
