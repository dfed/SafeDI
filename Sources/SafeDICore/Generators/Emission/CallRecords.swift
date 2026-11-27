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

/// What a place that calls another module's seam records beyond a built place (`BuiltPlaceRecord.callFields`): the
/// statement its builder function begins with, and what it hands each of the seam's builders after its arguments. The
/// engine writes both. Kept out of `PlaceRecord.swift`, whose words name no seam, hole or fill.
final class CallFields: Sendable {
	/// The statement the place's builder function begins with.
	let leadingStatement: CallGuard?
	/// What the call hands each builder the seam takes, after `BuiltPlaceRecord.arguments`, in the signature's builder
	/// order.
	let closureArguments: [ClosureArgumentEntry]
	/// The builders the call builds, which a `.built` closure argument names by index (`BuiltClosure`).
	let builtClosures: [BuiltClosure]

	init(leadingStatement: CallGuard?, closureArguments: [ClosureArgumentEntry], builtClosures: [BuiltClosure] = []) {
		self.leadingStatement = leadingStatement
		self.closureArguments = closureArguments
		self.builtClosures = builtClosures
	}
}

/// The line before a call of a seam's generated initializer: `_ = <calledType>.<guardTypeName>.self`, with the call's
/// comment, so that a call generated from another signature fails to compile there rather than pass `nil` where the
/// initializer expects a value (today `SeamCall.guardLine(for:)`).
struct CallGuard: Hashable, Sendable {
	/// The seam called.
	let calledType: TypeDescription
	/// The guard enum the seam's module declares for the signature the call was generated from
	/// (`SeamSignature.guardTypeName`): a name the call does not allocate.
	let guardTypeName: String
	/// What the line's comment says to do when the line does not compile.
	let comment: SeamCallComment
}

/// One builder a call hands the seam it calls, under the builder's label in the tier called.
struct ClosureArgumentEntry: Sendable {
	let label: String
	let value: ClosureArgument
}

/// What a call hands one of the seam's builders.
enum ClosureArgument: Sendable {
	/// A builder or level struct the caller's tree binds, which the call passes up whole.
	case passedOn(PassedOnRead)
	/// A builder the call builds (the fills lane's records), by its index in the call's built closures.
	case built(BuiltClosureID)
	/// Nothing: a builder the tier takes optionally, which the call neither builds nor passes up.
	case `nil`
}

/// A built closure's index in its call's record.
typealias BuiltClosureID = Int32

/// A read of the struct a caller's tree binds for one hole of the seam it calls, named by the hole, never by the name
/// the struct is bound under, which is allocated last.
struct PassedOnRead: Hashable, Sendable {
	/// The seam called.
	let calledType: TypeDescription
	/// The label of the called seam's builder the struct is handed as (`SeamSignature.Builder`).
	let builderLabel: String
	/// The struct's type, as the caller's tree binds it.
	let type: TypeDescription
	/// SafeDI cannot tell the struct is `Sendable`, so no `@Sendable` function captures it.
	var staysOutsideSendableFunctions: Bool {
		true
	}
}
