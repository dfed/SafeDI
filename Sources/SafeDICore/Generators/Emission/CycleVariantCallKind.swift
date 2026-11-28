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

/// How a call of a variant of the per-type plan of a root's cycles builds the variant's value: the value itself, or a
/// wrapper or generated initializer whose closure the call hands the variant's function.
enum CycleVariantCallKind: Sendable {
	/// The call builds the value where it is made: a constant.
	case value
	/// The call hands an instantiator or a lazy wrapper the variant's function.
	case wrapper
	/// The call is of another module's generated initializer, which builds the value in its own module.
	case generatedInitializer
}

extension CycleVariantRecord {
	/// Whether a call of the variant of kind `kind` builds the variant's body in the body of the function that makes the
	/// call: a call that builds the value where it is made, of a variant whose place declares no builder function of its
	/// own (`BuiltPlaceRecord.hasFunction`). The per-type facts read it for each call of each variant
	/// (`TypeFactsOutcomes.Input.buildsInCallersBody`).
	func buildsInCallersBody(throughCallOfKind kind: CycleVariantCallKind) -> Bool {
		switch kind {
		case .value:
			!record.hasFunction
		case .wrapper,
		     .generatedInitializer:
			false
		}
	}
}
