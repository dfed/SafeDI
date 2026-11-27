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

/// What a place whose builder function begins with a statement of its kind's records beyond a built place
/// (`BuiltPlaceRecord.callFields`): that statement, and, for a place that calls another module's seam, what it hands
/// each of the seam's builders after its arguments. The engine writes both. Kept out of `PlaceRecord.swift`, whose words
/// name no seam, hole or fill.
final class CallFields: Sendable {
	/// The statement the place's builder function begins with.
	let leadingStatement: LeadingStatement?
	/// What the call hands each builder the seam takes, after `BuiltPlaceRecord.arguments`, in the signature's builder
	/// order.
	let closureArguments: [ClosureArgumentEntry]
	/// The builders the call builds, which a `.built` closure argument names by index (`BuiltClosure`).
	let builtClosures: [BuiltClosure]

	init(leadingStatement: LeadingStatement?, closureArguments: [ClosureArgumentEntry], builtClosures: [BuiltClosure] = []) {
		self.leadingStatement = leadingStatement
		self.closureArguments = closureArguments
		self.builtClosures = builtClosures
	}
}

/// The statement a place's builder function begins with, before its children: structure a kind supplies, which the
/// engine spells, so that no record holds text. Two functions whose leading statements differ are two functions
/// (`TypeKeyLayout.structuralKey(of:isInSendableFamily:parts:)`).
enum LeadingStatement: Hashable, Sendable {
	/// The guard line of a call of another module's seam.
	case callGuard(CallGuard)
	/// The lines with which a function on a cycle of a mock's tree finds the place it builds (`EnteredPlace`).
	case enteredPlace(EnteredPlace)

	/// The statement's lines, in order, unindented.
	var spelledLines: [String] {
		switch self {
		case let .callGuard(callGuard):
			[callGuard.spelled]
		case let .enteredPlace(enteredPlace):
			enteredPlace.spelledLines
		}
	}
}

/// How a function on a cycle of a mock's tree finds the place it builds, in the three lines its body begins with. A
/// call of the function either enters a new place or returns to one a function above it entered, and only the mock's
/// run tells which, so the function reads its slot of the entered places it was handed
/// (`ReservedName.mockEnteredPlacesParameterName`): a place found there is the one entered before, with its
/// configuration and the places as they were above it; otherwise the function enters a new place, whose configuration
/// is the nearest one of its type among the entered places, else the one it was handed. The second and third lines bind
/// that configuration and the places beneath this one under the names of the function's own parameters, so every
/// statement after them reads as in a function off every cycle. A function off every cycle that a function on one reads
/// the nearest configuration of its type from has no slot: it enters only the nearest place of its type, in one line,
/// and reads the configuration it was handed.
struct EnteredPlace: Hashable, Sendable {
	/// The member of the entered places that holds this function's place: its property's slot; `nil` for a function off
	/// every cycle, which only enters the nearest place of its type.
	let slot: String?
	/// The member of the entered places that holds the nearest place of this function's configuration's type, where the
	/// type is reached under several properties; `nil` where this function's property is the only one of its type. Set
	/// wherever `slot` is `nil`.
	let nearestOfTypeSlot: String?

	/// The lines.
	var spelledLines: [String] {
		let enteredPlaces = ReservedName.mockEnteredPlacesParameterName
		let place = ReservedName.mockEnteredPlaceName
		let handedConfiguration = ReservedName.mockOverridesParameterName
		guard let slot else {
			return nearestOfTypeSlot.map { ["let \(enteredPlaces) = \(enteredPlaces).\(Self.enteringFunctionName)(\($0.spelledAsArgumentLabel): .init(\(handedConfiguration), \(Self.enteredAboveArgumentLabel): \(enteredPlaces)))"] } ?? []
		}
		let newConfiguration = nearestOfTypeSlot.map { "\(enteredPlaces).\($0)?.\(Self.configurationMemberName) ?? \(handedConfiguration)" } ?? handedConfiguration
		return [
			"let \(place) = \(enteredPlaces).\(slot) ?? .init(\(newConfiguration), \(Self.enteredAboveArgumentLabel): \(enteredPlaces))",
			"let \(handedConfiguration) = \(place).\(Self.configurationMemberName)",
			"let \(enteredPlaces) = \(place).\(Self.enteredAboveMemberName).\(Self.enteringFunctionName)(\(slot.spelledAsArgumentLabel): \(place))",
		]
	}

	/// The member of a place that holds its configuration.
	static let configurationMemberName = "configuration"
	/// The member of a place that holds the places entered above it.
	static let enteredAboveMemberName = "enteredAbove"
	/// The label under which a new place takes the places entered above it.
	static let enteredAboveArgumentLabel = "above"
	/// The function of the entered places that returns them with one more place entered, labeled by its slot.
	static let enteringFunctionName = "entering"
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
	/// the name the tree binds it under. `nil` for a call that fills a builder, whose record does not hold yet what its
	/// dispatchers and fills read.
	public let readNames: [String]?
	/// The names the record says the text binds, and the functions it declares; `nil` where `readNames` is.
	public let boundNames: [String]?
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

	/// The read, as a value of the construction whose argument reads `structRead`, the struct the member is called on.
	func value(reading structRead: PlaceRead, caseName: String) -> ValuePath {
		switch self {
		case .carrierChild:
			.member(caseName, of: .read(structRead))
		case .carrierMember:
			.call(caseName, of: .read(structRead), arguments: [], argumentsWrapper: nil)
		case let .member(valuesType):
			.call(caseName, of: .read(structRead), arguments: [], argumentsWrapper: valuesType)
		}
	}

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
