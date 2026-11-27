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

/// One way a place can depend on what is above it: every read a node of a world's graph declares is one of these, so a
/// fold over nodes asks nothing it did not declare. A new feature that reads the context above a place adds a channel,
/// which the compiler then makes every switch over channels handle.
///
/// A read of a label is hidden by a node that binds the label: what is above that node cannot answer it. A read of no
/// label is hidden only where its answer is fixed, as an edge that opens a `@Sendable` function fixes the family.
enum ReadChannel: UInt8, Sendable {
	/// The nearest declaration of a label: its form, whether it is still being built, and whether it is read as the
	/// instance of a lazy wrapper. Today `NearestDeclarations.resolving(_:)`.
	case value
	/// Whether a receive of a label only if available is handed a value or `nil`: the declaration may be built later, or
	/// still be building. Today `NearestDeclarations.resolvingBinding(of:)`.
	case optional
	/// The nearest declaration of a label as a receive only if available reads it: its form, and whether it is still
	/// being built, all of which the optional parameter it is passed carries (rule 1). A required receive of the label
	/// reads `value` beside it, whose answer keys in full. Logged as `value`'s read is.
	case optionalValue
	/// What a renamed receive is bound from where its alias is declared, and whether that sibling is still being built.
	case alias
	/// Whether a member of a loop of builders, or one of two twins, is made again where the place is built: a value the
	/// place's function or its call makes again rather than finds above.
	case madeAgain
	/// What a mock root binds or pins for a label: whether a receive only if available is passed `nil` there. Today
	/// `NearestDeclarations.resolvingPassesNil(to:receivedBy:on:)`.
	case mock
	/// A seam's payload or enum member of a label bound above the place.
	case carrier
	/// A field of the case a fill fills, or what the fill stack holds of a label.
	case fill
	/// Whether a `@Sendable` function encloses the place.
	case family
	/// Where a mock's place reads its override: its parent's configuration, the nearest configuration of its type above,
	/// or none, and whether the override closure must be `@Sendable`.
	case override

	/// Whether a read of the channel asks about a label.
	var asksAboutLabel: Bool {
		switch self {
		case .value, .optional, .optionalValue, .alias, .madeAgain, .mock, .carrier, .fill:
			true
		case .family, .override:
			false
		}
	}

	/// Whether an answer to a read of the channel is a value a body is handed, which the outcomes fold decides is `nil`,
	/// captured or a parameter. The others key the variant instead: the family, a carrier bound above, what a mock root
	/// pins.
	var carriesValue: Bool {
		switch self {
		case .value, .optional, .optionalValue, .alias, .madeAgain, .override, .fill:
			true
		case .family, .carrier, .mock:
			false
		}
	}

	/// The channel's name, as a read's text spells it.
	var name: String {
		switch self {
		case .value:
			"value"
		case .optional:
			"optional"
		case .optionalValue:
			"optionalValue"
		case .alias:
			"alias"
		case .madeAgain:
			"madeAgain"
		case .mock:
			"mock"
		case .carrier:
			"carrier"
		case .fill:
			"fill"
		case .family:
			"family"
		case .override:
			"override"
		}
	}
}

/// A read a node declares: its channel and, for a channel that asks about one, the world's ID of the label it asks
/// about. Two 32-bit values, so a fold compares and hashes reads without touching a label's text.
struct Read: Hashable, Sendable {
	/// A read of a channel that asks about `label`.
	init(_ channel: ReadChannel, label: Int32) {
		self.channel = channel
		self.label = label
	}

	/// A read of a channel that asks about no label.
	init(_ channel: ReadChannel) {
		self.channel = channel
		label = -1
	}

	let channel: ReadChannel
	/// The world's ID of the label, or -1 for a channel that asks about none.
	let label: Int32

	/// The read as text: the channel's name, and the label it asks about where it asks about one, spelled from the world's
	/// labels.
	func description(labels: [String]) -> String {
		channel.asksAboutLabel ? "\(channel.name)(\(labels[Int(label)]))" : channel.name
	}
}
