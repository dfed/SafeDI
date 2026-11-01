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

/// A rule SafeDI's own code follows, which `SourceRuleTests` checks. A site that is safe is waived by a line comment
/// on the line of the site, or on the lines just above it:
/// `// safedi-source-rule: allow <rule> — <the invariant that makes the site safe>`.
enum SourceRule: String, CaseIterable {
	/// A force unwrap (`value!`, or `\.value!` in a key path), an implicitly unwrapped optional type (`Type!`) or failable
	/// initializer (`init!`), which trap on `nil`, or `unsafelyUnwrapped`, which traps on `nil` in a debug build and
	/// reads an undefined value in a release build.
	case forceUnwrap
	/// `try!`, which traps on an error.
	case forceTry
	/// `as!`, which traps on a failed cast.
	case forceCast
	/// A call of `fatalError`, `precondition`, `preconditionFailure`, `assert`, or `assertionFailure`.
	case trap
	/// `Dictionary(uniqueKeysWithValues:)`, `Dictionary(dictionaryLiteral:)`, or a dictionary literal whose keys are not
	/// distinct literals, each of which traps on a duplicate key.
	case uniqueKeysWithValues
	/// `try?` in a generator, which discards an error the generator must report.
	case optionalTry
	/// `__safeDI_` in a literal: `ReservedName` spells the prefix of generated builder functions, so a name cannot be
	/// generated without being reserved.
	case builderFunctionNamePrefix
	/// A string literal of one backtick: the identifier-spelling extensions alone add and remove backticks, so a name
	/// joined with other text keeps the spelling of a keyword or a raw identifier.
	case backtick

	/// Whether the rule applies to the file at `path`, relative to the repository root. SafeDI ships its sources and
	/// plugins, so neither traps.
	func applies(toFileAt path: String) -> Bool {
		switch self {
		case .forceUnwrap, .forceTry, .forceCast, .trap, .uniqueKeysWithValues:
			path.hasPrefix("Sources/") || path.hasPrefix("Plugins/")
		case .optionalTry:
			path.hasPrefix("Sources/SafeDICore/Generators/")
		case .builderFunctionNamePrefix:
			path.hasPrefix("Sources/") && path != "Sources/SafeDICore/Models/ReservedName.swift"
		case .backtick:
			path.hasPrefix("Sources/") && path != "Sources/SafeDICore/Extensions/IdentifierSpellingExtensions.swift"
		}
	}
}

/// A site that breaks a `SourceRule` without a waiver, or a waiver that does not waive a site as it should.
struct SourceRuleFinding: CustomStringConvertible {
	enum Subject: Equatable {
		/// A site that breaks the rule.
		case rule(SourceRule)
		/// A waiver that names no rule, gives no reason, or waives no site.
		case waiver
	}

	let path: String
	let line: Int
	let subject: Subject
	let message: String

	var description: String {
		let subjectName = switch subject {
		case let .rule(rule):
			rule.rawValue
		case .waiver:
			"waiver"
		}
		return "\(path):\(line): \(subjectName): \(message)"
	}
}

enum SourceRuleCheck {
	/// The comment text that begins a waiver.
	static let waiverMarker = "safedi-source-rule:"

	/// Every site in `source`, the file at `path` relative to the repository root, that breaks a rule applying to the
	/// file and is not waived, and every waiver in it that names no rule, gives no reason, or waives no site, in line
	/// order.
	static func findings(in source: String, at path: String) -> [SourceRuleFinding] {
		let tree = Parser.parse(source: source)
		let converter = SourceLocationConverter(fileName: path, tree: tree)
		let visitor = SourceRuleVisitor(path: path, converter: converter)
		visitor.walk(tree)
		let waivers = waivers(in: tree, converter: converter)

		var findings = [SourceRuleFinding]()
		var usedWaiverIndices = Set<Int>()
		for violation in visitor.violations {
			if let waiverIndex = waivers.firstIndex(where: { $0.rule == violation.rule && $0.waivedLine == violation.line }) {
				usedWaiverIndices.insert(waiverIndex)
			} else {
				findings.append(SourceRuleFinding(path: path, line: violation.line, subject: .rule(violation.rule), message: violation.message))
			}
		}
		for (index, waiver) in waivers.enumerated() {
			if let problem = waiver.problem {
				findings.append(SourceRuleFinding(path: path, line: waiver.line, subject: .waiver, message: problem))
			} else if let rule = waiver.rule, !usedWaiverIndices.contains(index) {
				findings.append(SourceRuleFinding(path: path, line: waiver.line, subject: .waiver, message: "the waiver of `\(rule.rawValue)` waives no site on line \(waiver.waivedLine)"))
			}
		}
		return findings.sorted { ($0.line, $0.description) < ($1.line, $1.description) }
	}

	/// The waivers in `tree`'s comments, in source order.
	private static func waivers(in tree: SourceFileSyntax, converter: SourceLocationConverter) -> [Waiver] {
		var waivers = [Waiver]()
		for token in tree.tokens(viewMode: .sourceAccurate) {
			// A waiver above a site is in the leading trivia of the site's first token, and one after it on its line
			// is in the trailing trivia of the line's last token: either way, it waives the line of its token.
			let waivedLine = converter.location(for: token.positionAfterSkippingLeadingTrivia).line
			for (trivia, startPosition) in [(token.leadingTrivia, token.position), (token.trailingTrivia, token.endPositionBeforeTrailingTrivia)] {
				var position = startPosition
				for piece in trivia {
					if case let .lineComment(text) = piece,
					   let waiver = Waiver(comment: text, line: converter.location(for: position).line, waivedLine: waivedLine)
					{
						waivers.append(waiver)
					}
					position += piece.sourceLength
				}
			}
		}
		return waivers
	}

	/// A comment that waives a rule on a line.
	private struct Waiver {
		/// The waiver in `comment`, a line comment on `line` that waives `waivedLine`, or `nil` when the comment is
		/// not a waiver.
		init?(comment: String, line: Int, waivedLine: Int) {
			let text = comment.dropFirst(2).trimmingCharacters(in: .whitespaces)
			guard text.hasPrefix(SourceRuleCheck.waiverMarker) else { return nil }
			self.line = line
			self.waivedLine = waivedLine
			let words = text.dropFirst(SourceRuleCheck.waiverMarker.count).split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
			// The reason follows a dash.
			let reason = words.count > 2
				? words[2].drop(while: { "—–-: ".contains($0) })
				: ""
			if words.first == "allow", words.count > 1, let rule = SourceRule(rawValue: String(words[1])) {
				self.rule = rule
				problem = reason.isEmpty ? "the waiver of `\(rule.rawValue)` gives no reason" : nil
			} else {
				rule = nil
				problem = "a waiver reads `\(SourceRuleCheck.waiverMarker) allow <rule> — <reason>`, where the rule is one of \(SourceRule.allCases.map { "`\($0.rawValue)`" }.joined(separator: ", "))"
			}
		}

		/// The line of the comment.
		let line: Int
		/// The line whose sites the waiver waives.
		let waivedLine: Int
		/// The rule waived, or `nil` when the waiver names none.
		let rule: SourceRule?
		/// What is wrong with the waiver, or `nil` when it names a rule and gives a reason.
		let problem: String?
	}
}

/// Finds the sites in a file that break the rules that apply to it.
private final class SourceRuleVisitor: SyntaxVisitor {
	init(path: String, converter: SourceLocationConverter) {
		self.path = path
		self.converter = converter
		super.init(viewMode: .sourceAccurate)
	}

	/// The sites found, each at the line of the token that breaks the rule.
	private(set) var violations = [(line: Int, rule: SourceRule, message: String)]()

	override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
		record(.forceUnwrap, at: node.exclamationMark, "a force unwrap traps on `nil`")
		return .visitChildren
	}

	override func visit(_ node: ImplicitlyUnwrappedOptionalTypeSyntax) -> SyntaxVisitorContinueKind {
		record(.forceUnwrap, at: node.exclamationMark, "an implicitly unwrapped optional traps when it is read as `nil`")
		return .visitChildren
	}

	override func visit(_ node: KeyPathOptionalComponentSyntax) -> SyntaxVisitorContinueKind {
		if node.questionOrExclamationMark.tokenKind == .exclamationMark {
			record(.forceUnwrap, at: node.questionOrExclamationMark, "a force unwrap traps on `nil`")
		}
		return .visitChildren
	}

	override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
		if let optionalMark = node.optionalMark, optionalMark.tokenKind == .exclamationMark {
			record(.forceUnwrap, at: optionalMark, "an implicitly unwrapped failable initializer traps when its `nil` result is read")
		}
		return .visitChildren
	}

	override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
		if node.declName.baseName.text == "unsafelyUnwrapped" {
			record(.forceUnwrap, at: node.declName.baseName, "`unsafelyUnwrapped` traps on `nil` in a debug build and reads an undefined value in a release build")
		}
		return .visitChildren
	}

	override func visit(_ node: DictionaryElementListSyntax) -> SyntaxVisitorContinueKind {
		// A dictionary type, such as the callee of `[String: Int]()`, has one element, which repeats no key.
		let keys = node.map(\.key)
		let literalKeys = keys.compactMap(Self.literalSpelling(of:))
		if keys.count > 1, literalKeys.count < keys.count || Set(literalKeys).count < literalKeys.count {
			record(.uniqueKeysWithValues, at: node, "a dictionary literal traps on a duplicate key unless its keys are distinct literals")
		}
		return .visitChildren
	}

	override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
		if node.questionOrExclamationMark?.tokenKind == .exclamationMark {
			record(.forceTry, at: node.tryKeyword, "`try!` traps on an error")
		} else if node.questionOrExclamationMark?.tokenKind == .postfixQuestionMark {
			record(.optionalTry, at: node.tryKeyword, "`try?` discards an error a generator must report")
		}
		return .visitChildren
	}

	override func visit(_ node: UnresolvedAsExprSyntax) -> SyntaxVisitorContinueKind {
		if node.questionOrExclamationMark?.tokenKind == .exclamationMark {
			record(.forceCast, at: node.asKeyword, "`as!` traps on a failed cast")
		}
		return .visitChildren
	}

	override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
		if Self.trappingFunctionNames.contains(node.baseName.text), node.namesStandardLibraryFunction {
			record(.trap, at: node.baseName, "`\(node.baseName.text)` traps")
		}
		// A reference to the initializer, such as `Dictionary.init(uniqueKeysWithValues:)`.
		if let label = node.argumentNames?.arguments.lazy.map(\.name.text).first(where: { Self.duplicateKeyTrappingLabels.keys.contains($0) }),
		   let message = Self.duplicateKeyTrappingLabels[label]
		{
			record(.uniqueKeysWithValues, at: node.baseName, message)
		}
		return .visitChildren
	}

	override func visit(_ node: LabeledExprSyntax) -> SyntaxVisitorContinueKind {
		if let label = node.label,
		   let message = Self.duplicateKeyTrappingLabels[label.text],
		   node.parent?.parent?.is(FunctionCallExprSyntax.self) == true
		{
			record(.uniqueKeysWithValues, at: label, message)
		}
		return .visitChildren
	}

	override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
		if node.segments.count == 1,
		   let segment = node.segments.first?.as(StringSegmentSyntax.self),
		   segment.content.text == "`"
		{
			record(.backtick, at: node.openingQuote, "only the identifier-spelling extensions add or remove a backtick")
		}
		return .visitChildren
	}

	override func visit(_ node: StringSegmentSyntax) -> SyntaxVisitorContinueKind {
		if node.content.text.contains(Self.builderFunctionNamePrefix) {
			record(.builderFunctionNamePrefix, at: node.content, Self.builderFunctionNamePrefixMessage)
		}
		return .visitChildren
	}

	override func visit(_ node: RegexLiteralExprSyntax) -> SyntaxVisitorContinueKind {
		if node.regex.text.contains(Self.builderFunctionNamePrefix) {
			record(.builderFunctionNamePrefix, at: node.regex, Self.builderFunctionNamePrefixMessage)
		}
		return .visitChildren
	}

	// MARK: Private

	private static let trappingFunctionNames: Set = ["fatalError", "precondition", "preconditionFailure", "assert", "assertionFailure"]
	/// The argument labels of the `Dictionary` initializers that trap on a duplicate key, each with its message.
	private static let duplicateKeyTrappingLabels = [
		"uniqueKeysWithValues": "`Dictionary(uniqueKeysWithValues:)` traps on a duplicate key",
		"dictionaryLiteral": "`Dictionary(dictionaryLiteral:)` traps on a duplicate key",
	]
	private static let builderFunctionNamePrefix = "__safeDI_"
	private static let builderFunctionNamePrefixMessage = "only `ReservedName.builderFunctionNamePrefix` spells `__safeDI_`"

	private let path: String
	private let converter: SourceLocationConverter

	private func record(_ rule: SourceRule, at node: some SyntaxProtocol, _ message: String) {
		guard rule.applies(toFileAt: path) else { return }
		violations.append((
			line: converter.location(for: node.positionAfterSkippingLeadingTrivia).line,
			rule: rule,
			message: message,
		))
	}

	/// `key` as written when it is a string literal without interpolation, or an integer, floating-point, or Boolean
	/// literal, or `nil` for any other key, whose value only the program knows. Two literals written differently can
	/// still be equal, such as `1` and `0x1`; those are not told apart.
	private static func literalSpelling(of key: ExprSyntax) -> String? {
		if let stringLiteral = key.as(StringLiteralExprSyntax.self),
		   stringLiteral.segments.allSatisfy({ $0.is(StringSegmentSyntax.self) })
		{
			stringLiteral.trimmedDescription
		} else if key.is(IntegerLiteralExprSyntax.self) || key.is(FloatLiteralExprSyntax.self) || key.is(BooleanLiteralExprSyntax.self) {
			key.trimmedDescription
		} else {
			nil
		}
	}
}

extension DeclReferenceExprSyntax {
	/// Whether this reference may name a function of the standard library: it is not the member of a member access, or
	/// it is a member of `Swift`. Syntax alone cannot tell such a reference from an unqualified read of a property of
	/// the same name, which the check reports too; a property so named is renamed or waived.
	fileprivate var namesStandardLibraryFunction: Bool {
		guard let memberAccess = parent?.as(MemberAccessExprSyntax.self), memberAccess.declName == self else { return true }
		return memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "Swift"
	}
}
