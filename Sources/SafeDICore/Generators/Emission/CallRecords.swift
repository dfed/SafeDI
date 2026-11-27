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

	init(leadingStatement: CallGuard?, closureArguments: [ClosureArgumentEntry]) {
		self.leadingStatement = leadingStatement
		self.closureArguments = closureArguments
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

	/// The line.
	var spelled: String {
		"_ = \(calledType.asSource).\(guardTypeName).self\(comment.lineEnd(for: calledType))"
	}
}

/// A call of another module's seam as `ScopeGenerator.seamCallRecord` writes it, where it passes no fill: its text, and
/// what its record, as the engine is to spell it, says of that text. Handed to `observer`, which the tests set to check that
/// the record lists every value the text reads, binds and declares, and that the engine's spelling of the record's guard
/// and builder arguments is the text's, where the call's code is generated in a task that inherits it.
public struct SeamCallRecordObservation: Sendable {
	/// The call's code.
	public let text: String
	/// The names the record says the text reads: its arguments' reads, and each struct it passes a builder up from, by
	/// the name the tree binds it under.
	public let readNames: [String]
	/// The names the record says the text binds, and the functions it declares.
	public let boundNames: [String]
	/// The record's guard line and builder arguments, spelled as the engine is to spell them.
	public let spelledFromRecord: [String]
	/// The guard line and builder arguments the text writes, in the same order.
	public let written: [String]

	/// Called with each call as its record is made, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: (@Sendable (SeamCallRecordObservation) -> Void)?
}

/// One builder a call hands the seam it calls, under the builder's label in the tier called.
struct ClosureArgumentEntry: Hashable, Sendable {
	let label: String
	let value: ClosureArgument
}

/// What a call hands one of the seam's builders.
enum ClosureArgument: Hashable, Sendable {
	/// A builder or level struct the caller's tree binds, which the call passes up whole.
	case passedOn(PassedOnRead)
	/// A builder the call builds (a fill's records), by its index in the call's built closures.
	case built(BuiltClosureID)
	/// Nothing: a builder the tier takes optionally, which the call neither builds nor passes up.
	case `nil`
}

/// A built closure's index in its call's record.
typealias BuiltClosureID = Int32

/// A read of the struct a caller's tree binds for one of the builders of the seam it calls: the member of the struct for
/// the call's own case, which returns the struct the called seam is handed. Keyed by the called seam's builder, under the
/// label its widest tier takes it by, which every tier's call shares, and by the struct's type, never by the name the struct
/// is bound under, which is allocated last.
struct PassedOnRead: Hashable, Sendable {
	/// The seam called.
	let calledType: TypeDescription
	/// The label the called seam's widest tier takes the builder under (`SeamSignature.Builder.label`).
	let builderLabel: String
	/// The type of the struct the member is called on, as the caller's tree binds it: the caller's own builder, or a level
	/// a member on the route returned.
	let structType: TypeDescription
	/// The name of the call's own case, the struct's member read.
	let caseName: String
	/// How the member is read.
	let member: PassedOnMember
}

/// How a call reads the member of the caller's struct for its own case.
enum PassedOnMember: Hashable, Sendable {
	/// A carrier's `let` child: `<struct>.<case>`.
	case carrierChild
	/// A carrier's member, which takes no values: `<struct>.<case>()`.
	case carrierMember
	/// A member handed its case's values, which hold nothing for the call's own case: `<struct>.<case>(<values>())`.
	case member(valuesType: TypeDescription)

	/// The read, of the struct bound as `structName`.
	func spelled(on structName: String, caseName: String) -> String {
		switch self {
		case .carrierChild:
			"\(structName).\(caseName)"
		case .carrierMember:
			"\(structName).\(caseName)()"
		case let .member(valuesType):
			"\(structName).\(caseName)(\(valuesType.asSource)())"
		}
	}
}
