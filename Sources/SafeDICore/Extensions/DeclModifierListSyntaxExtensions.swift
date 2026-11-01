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
	public var staticModifier: Element? {
		first(where: { modifier in
			modifier.name.text == "static"
		})
	}

	/// The access these modifiers spell on the declaration that `keyword` introduces: the level the first access
	/// modifier names, or `internal` when none does. The compiler rejects a detail, such as `(set)`, on the access
	/// modifier of every declaration SafeDI reads, so a modifier is read by its name alone.
	/// - Parameter sourceLocationConverter: A converter for the tree that holds the declaration. When provided, the
	///   access records where its modifier is and where the declaration begins after its attributes.
	func access(introducedBy keyword: TokenSyntax, sourceLocationConverter: SourceLocationConverter?) -> AccessDeclaration {
		let accessModifier = lazy
			.compactMap { modifier in
				AccessLevel(modifier.name.tokenKind).map { (level: $0, name: modifier.name) }
			}
			.first
		return AccessDeclaration(
			level: accessModifier?.level ?? .internal,
			modifierRange: accessModifier.flatMap { sourceLocationConverter?.sourceRange(of: $0.name) },
			declarationStartLocation: sourceLocationConverter?.declarationLocation(for: (first?.name ?? keyword).positionAfterSkippingLeadingTrivia),
			isExtension: keyword.tokenKind == .keyword(.extension),
		)
	}
}

// MARK: - WithModifiersSyntax

extension WithModifiersSyntax {
	/// This declaration without the modifier that makes it `private` or `fileprivate`, which generated code, always in
	/// a file of its own, can never use, together with the level that modifier set, or `nil` when no modifier does.
	/// See `removingModifiers(setting:keyword:)`.
	public func removingPrivateOrFilePrivateModifier(keyword: WritableKeyPath<Self, TokenSyntax>) -> (declaration: Self, accessLevel: AccessLevel)? {
		modifiers.lazy.compactMap { AccessLevel($0.name.tokenKind) }.first(where: \.isPrivateOrFilePrivate).map { accessLevel in
			(removingModifiers(setting: accessLevel, keyword: keyword), accessLevel)
		}
	}

	/// This declaration without the modifiers that set `accessLevel`. The token that followed a removed modifier – the
	/// next modifier, or `keyword`, which introduces the declaration, when none follows – takes the modifier's leading
	/// trivia, so the declaration keeps its line and indentation.
	public func removingModifiers(setting accessLevel: AccessLevel, keyword: WritableKeyPath<Self, TokenSyntax>) -> Self {
		var declaration = self
		var remainingModifiers = [DeclModifierSyntax]()
		var removedLeadingTrivia = Trivia()
		for modifier in modifiers {
			if AccessLevel(modifier.name.tokenKind) == accessLevel {
				removedLeadingTrivia = removedLeadingTrivia + modifier.leadingTrivia
			} else {
				remainingModifiers.append(modifier.with(\.leadingTrivia, removedLeadingTrivia + modifier.leadingTrivia))
				removedLeadingTrivia = []
			}
		}
		declaration[keyPath: keyword].leadingTrivia = removedLeadingTrivia + declaration[keyPath: keyword].leadingTrivia
		declaration.modifiers = DeclModifierListSyntax(remainingModifiers)
		return declaration
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
