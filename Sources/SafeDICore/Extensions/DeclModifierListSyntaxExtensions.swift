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

import SwiftSyntax

extension DeclModifierListSyntax {
	public var containsPublicOrOpen: Bool {
		contains(where: { modifier in
			modifier.name.text == "public"
				|| modifier.name.text == "open"
		})
	}

	public var staticModifier: Element? {
		first(where: { modifier in
			modifier.name.text == "static"
		})
	}

	/// The modifier that sets the access level of the declaration these modifiers belong to, with the level it sets,
	/// or `nil` when no modifier does and the declaration has the default access level, `internal`. The compiler
	/// rejects a detail, such as `(set)`, on the access modifier of every declaration SafeDI reads, so a modifier is
	/// read by its name alone.
	var accessModifier: (accessLevel: AccessLevel, name: TokenSyntax)? {
		lazy
			.compactMap { modifier in
				AccessLevel(modifier.name.tokenKind).map { (accessLevel: $0, name: modifier.name) }
			}
			.first
	}

	/// Where the declaration these modifiers belong to begins after its attributes, which is where a modifier is
	/// inserted: at its first modifier, or at `keyword`, the keyword that introduces it, when it has none.
	func declarationStartPosition(introducedBy keyword: TokenSyntax) -> AbsolutePosition {
		(first?.name ?? keyword).positionAfterSkippingLeadingTrivia
	}
}

// MARK: - AccessLevel

extension AccessLevel {
	/// The access level a modifier named by `tokenKind` sets, or `nil` when the modifier sets none.
	fileprivate init?(_ tokenKind: TokenKind) {
		switch tokenKind {
		case .keyword(.open):
			self = .open
		case .keyword(.public):
			self = .public
		case .keyword(.package):
			self = .package
		case .keyword(.internal):
			self = .internal
		case .keyword(.fileprivate):
			self = .fileprivate
		case .keyword(.private):
			self = .private
		default:
			// Every other modifier, such as `static` or `final`, sets something other than an access level.
			return nil
		}
	}
}
