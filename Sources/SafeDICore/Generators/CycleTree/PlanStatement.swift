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

// The shapes a plan's later parts are written against. Nothing builds them yet: the layout of a plan's functions and
// the walks of a plan's tree are written against these names while the plan itself is compared with today's tree.

/// What a label of `LabelsReadFromAbove` resolves to at one call of a cyclic declaration's function, by value, never by
/// a position on a path.
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

/// One body to build and emit: a declaration on a cycle, in one family, under one set of answers.
struct Variant: Hashable, Sendable {
	/// The declaration's position in `PerTypePlan.graph`.
	let declaration: Int
	/// Whether the body is built inside a `@Sendable` function.
	let isInSendableFamily: Bool
	/// What each label the declaration reads from above resolves to, in the order of `LabelsReadFromAbove.labels(of:)`.
	let answers: [Answer]
}

/// A statement of a variant's body, or of the root's.
enum PlanStatement: Sendable {
	/// A property on no cycle, built per path beneath this body, as today.
	case built(ConstructionScope.PropertyToGenerate)
	/// A property on a cycle, at its first build and where a path would close on it alike: a call of the function of
	/// `variant`, a position in the plan's variants, passed `arguments`, one per label the variant's declaration reads
	/// from above.
	case call(variant: Int, property: Property, arguments: [Answer])
}

/// Why a statement of a root's body is built per path, as today, where a plan could not stand for every path.
enum PerPathReason: Hashable, Sendable {
	/// The statement's tree holds a place the layout by type does not plan.
	case reachesUnplannedPlace
	/// Places of one declaration build bodies that differ.
	case componentIsNotUniform
	/// Two declarations of one cycle share a cycle identity (`PerTypePlan.twins`).
	case twinsOfOneIdentity
	/// No one type takes what every call of a function passes for a label.
	case parameterHasNoType
	/// A `@Sendable` function would capture a wrapper declared outside it, which is reported once per chain.
	case captureFinding
	/// A tier omits a value a call would pass, which is reported at a declaration on the path.
	case tierOmissionFinding
	/// A label no one parameter can pass, which is reported at its first receive in the body.
	case unpassableCycleLabel
	/// The bodies of one declaration, built as one property, differ in more answers than a bound allows
	/// (`VariantBodies.bodiesPerKeyLimit`): a label no optional parameter merges, such as one declared in two forms.
	case bodiesOfOneDeclarationPassBound
}
