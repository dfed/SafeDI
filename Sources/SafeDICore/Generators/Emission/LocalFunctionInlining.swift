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

/// Whether the local functions the code being generated declares are `@inline(never)`: only in a seam’s tree, generated
/// in the seam’s own module (`ScopeGenerator.generatePropertyCode`), which builds that tree from generators no other
/// tree holds, so whether a function is declared so depends only on the tree it is in.
///
/// Swift 6.2’s optimizer inlines the local builder functions of a seam’s generated initializer into one another, which
/// costs a release compile and the binary more than the calls save at run time. Measured with Swift 6.2.4 on Linux, on
/// an app of 150 screens in six feature modules, each behind a seam, compiled whole-module with `-O`: declaring them
/// `@inline(never)` cut a feature module’s compile by 14 to 18% of the compiler’s instructions and its code by 36%, and
/// a full walk of the app’s tree ran 7 to 11% faster on 0.9% more instructions. A debug build compiles to an object of
/// the same size, with the compiler’s instructions within 0.3%.
///
/// A root’s tree and a mock’s keep their functions inlinable. The same 150 screens built inline by one root compiled 16%
/// faster with the attribute, but a full walk ran 2 to 4% slower on 2% more instructions, and generated code is kept
/// fast to run over fast to compile. A mock module’s debug compile, where mocks are built, does not change.
enum LocalFunctionInlining {
	/// Set while a seam’s root generates its code in the seam’s own module.
	@TaskLocal static var isNeverInlined = false

	/// The attribute a local function the code being generated declares starts with: `@inline(never) ` where
	/// `isNeverInlined`, and nothing otherwise.
	static var attribute: String {
		isNeverInlined ? "@inline(never) " : ""
	}
}
