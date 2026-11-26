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

/// What a label a cyclic declaration reads from above resolves to at one call of its function, by value, never by a
/// position on a path. The layout engine's vocabulary for a call's arguments and a body's answers (`TypeKeyVariantPlan`).
enum Answer: Hashable, Sendable {
	/// Nothing above the call provides the label: the function is passed `nil`.
	case none
	/// The nearest declaration's property, and whether it is still being built where the call is made.
	case declared(Property, isBeingBuilt: Bool)
	/// The nearest declaration's property, a member of a loop of builders that the scope making the call builds after
	/// the call: no call can read that declaration yet, so the call passes the member's wrapper made again around its
	/// function, as today's `__safeDI_<label>_received` function does (`ReceivedBuilderLoops`). An argument of a call
	/// only: the body called is keyed by the declaration (`declared`), which every call of it answers alike.
	case declaredMadeAgainAtCall(Property)
	/// The instance of the nearest declaration, a lazily instantiated property.
	case instance(of: Property)
}
