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

import Foundation
import SwiftParser
import SwiftSyntax

extension String {
	/// This name as generated code spells it where it declares or refers to a value: without the backticks it
	/// was written with, then in backticks only where Swift requires them there – a keyword such as `default`
	/// or `self`, or a raw identifier such as `my leaf`. SafeDI reads every name a declaration gives into this
	/// spelling, so `` `thing` `` and `thing` name one property, and `default` and `` `default` `` another.
	var spelledAsIdentifier: String {
		let name = spelledWithoutBackticks
		return if name.isValidSwiftIdentifier(for: .variableName) {
			name
		} else {
			"`\(name)`"
		}
	}

	/// This name without the backticks it was written with, as prose names it: `` `inout` `` is `inout`.
	public var spelledWithoutBackticks: String {
		// Most names hold no backtick, and scanning their bytes is far cheaper than rebuilding them by character.
		utf8.contains(UInt8(ascii: "`")) ? String(filter { $0 != "`" }) : self
	}

	/// The identifier that this text, which joins names in `spelledAsIdentifier` spelling with text such as
	/// `__safeDI_` or `_lazilyInstantiated`, spells: `__safeDI_` + `` `default` `` is `__safeDI_default`, and
	/// `__safeDI_` + `` `my leaf` `` is `` `__safeDI_my leaf` ``. Joining names that need no backticks with
	/// such text makes a name that needs none, so only text holding a backtick is spelled again.
	var spelledAsJoinedIdentifier: String {
		contains("`") ? spelledAsIdentifier : self
	}

	/// This name, in `spelledAsIdentifier` spelling, as a call spells it as an argument label. Swift takes every
	/// keyword but `inout` as an argument label without backticks, and warns where a call escapes one, so only
	/// `inout`, `_`, and raw identifiers keep their backticks. A name of letters alone needs backticks only
	/// when it is a keyword.
	var spelledAsArgumentLabel: String {
		guard first == "`" else { return self }
		let name = dropFirst().dropLast()
		return if name != "inout", name.allSatisfy({ $0.isASCII && $0.isLetter }) {
			String(name)
		} else {
			self
		}
	}
}

extension String {
	/// This name, in `spelledAsIdentifier` spelling, as a type's member declaration spells it: `Type` and `Protocol` in
	/// backticks too, which Swift rejects as a member's name written bare, since `foo.Type` and `foo.Protocol` are
	/// metatypes.
	var spelledAsMemberDeclarationName: String {
		switch spelledWithoutBackticks {
		case "Type", "Protocol":
			"`\(spelledWithoutBackticks)`"
		default:
			self
		}
	}

	/// This name, in `spelledAsIdentifier` spelling, as an expression spells it after a `.` to read a member: as an
	/// argument label, except `init` and `self`, which keep their backticks, since `foo.init` and `foo.self` are an
	/// initializer and the value itself.
	var spelledAsMemberReference: String {
		switch spelledWithoutBackticks {
		case "init", "self":
			self
		default:
			spelledAsArgumentLabel
		}
	}
}

extension TokenSyntax {
	/// The name this token gives a parameter, in `spelledAsIdentifier` spelling, or `_` for a wildcard.
	var spelledAsParameterName: String {
		tokenKind == .wildcard ? text : text.spelledAsIdentifier
	}
}
