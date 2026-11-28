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
	/// A trap spelled in a string literal under `Sources`, which may be text of the code SafeDI generates: `fatalError`,
	/// `precondition`, `preconditionFailure`, `assert`, `assertionFailure` or `unsafelyUnwrapped` as a whole word, or `try!`
	/// or `as!`. Generated code never traps, so a diagnostic or a generated comment that spells one is reworded or, on a
	/// one-line literal, waived; a waiver cannot name a line inside a multi-line literal, whose `//` is text, so a site
	/// there is reworded.
	case generatedTrap
	/// `__safeDI_` in a literal: `ReservedName` spells the prefix of generated builder functions, so a name cannot be
	/// generated without being reserved.
	case builderFunctionNamePrefix
	/// A string literal of one backtick: the identifier-spelling extensions alone add and remove backticks, so a name
	/// joined with other text keeps the spelling of a keyword or a raw identifier.
	case backtick
	/// A straight apostrophe between letters in a string literal, such as `type's` or "`\(name)`'s": the text SafeDI
	/// emits spells an apostrophe ’ (U+2019). `Scripts/sweep-apostrophes.py` rewrites each site and the tests that
	/// compare it.
	case apostrophe
	/// `@testable import` in `Tests/SafeDIToolTestSupport`: a plain `swift build` of the package builds that regular
	/// target in release without `-enable-testing`, which rejects the import, so its helpers import `SafeDIToolLibrary`
	/// plainly, through the declarations the library makes `public` for them.
	case testableImport
	/// `nonisolated(unsafe)` or `@unchecked Sendable`, each of which opts out of the compiler's proof that SafeDI's own
	/// code is safe to run concurrently, a deinit-only field included. Only Dan admits one, for one site: its waiver cites
	/// his OK (`— Dan’s OK: <where he gave it>`), and no invariant stated in a waiver stands in for it.
	case uncheckedConcurrency
	/// A task group whose element (its `of:` type) is a tuple, or an optional tuple. Swift 6.3's `-Osize` (the published
	/// Linux binary's build), Swift 6.4's release builds and Xcode 26.4's release build of 2.3.1 miscompiled task groups
	/// whose element was a tuple holding a `Result` with an `any Error`, so `query` crashed or read nothing; the tests,
	/// built with `-enable-testing`, passed. A task group's element is a struct of the same fields, which those builds
	/// compile correctly.
	case taskGroupTupleElement
	/// A `@TaskLocal` whose value is a function, optional or not. Swift 6.3's release builds (Swift 6.3.3 on Linux, the
	/// published binaries' toolchain, and Xcode 26.4's) crash in `swift_task_localValuePush` ("Bad pointer dereference at
	/// 0xfffffffffffffff8") whenever `withValue` binds such a value, `nil` included, so 2.4.2's `query graph` crashed; the
	/// tests, built in debug, passed. A task-local function is held in a `TaskLocalFunction`, a struct, which every build
	/// binds.
	case taskLocalFunction
	/// A mock, an override, a configuration, a seam, a hole or a fill named in a type key file (`TypeKeyBody*.swift`) or
	/// in `PlaceRecord.swift`, in an identifier or a literal: the type key lays out any body from its places' records
	/// and knows no feature, so a feature that needs something of it records a fact in general terms on the place, and
	/// the layout reads the fact.
	case engineFeatureName
	/// `String`, `Property` or `TypeDescription` named in a fold of the per-type facts (`OrderedGraph.swift`, `ReadsFromAbove.swift`, `SiblingOrder.swift`, `TypeFactsColumns.swift`, `TypeFactsVariants.swift`, `TypeFactsOutcomes.swift`): a fold
	/// works on a world's 32-bit IDs and bit sets, and only building the graph, spelling code and wording a message
	/// touch a model of the source so a fold keeps no reference-counted value in its loops. A reader fold that still reads
	/// a declaration's `Property` is left out until the graph answers what it reads: `TypeFactsImports.swift`, which hands
	/// each declaration's type to `FulfillerImports`, until the frozen table holds each declaration's fulfiller modules;
	/// `TypeFactsReceivedValueSupplies.swift`, which reads a receive's label and an alias's properties, until its three
	/// bridge rules (the bindings before an edge, whether an edge is in a loop, the call a lazy cycle closes on) move to
	/// the graph, the last move deleting the tree walk.
	case typeFactsFoldModelName
	/// A scan of a string's characters in a generator: `split`, `replacingOccurrences` or `components(separatedBy:)`
	/// called on anything, or `contains` given a string literal. A generator's code runs per place or per node, and such
	/// a scan reads every character of its text there, which grew `generate` with the square of the tree where the text
	/// held a subtree's code. A text transform at every node goes over UTF-8 bytes (`GeneratedCodeText`); a site that
	/// runs a bounded number of times, or over a few elements (an `[String]` of attributes), is waived with why.
	case stringScan

	/// Whether the rule applies to the file at `path`, relative to the repository root. SafeDI ships its sources and
	/// plugins, so neither traps; the Tuist plugin's build script prints SafeDI's errors too, so it spells their
	/// apostrophes; and a plain release build of the package builds the test support target.
	func applies(toFileAt path: String) -> Bool {
		switch self {
		case .forceUnwrap, .forceTry, .forceCast, .trap, .uniqueKeysWithValues:
			path.hasPrefix("Sources/") || path.hasPrefix("Plugins/")
		case .optionalTry:
			path.hasPrefix("Sources/SafeDICore/Generators/")
		case .generatedTrap:
			path.hasPrefix("Sources/")
		case .builderFunctionNamePrefix:
			path.hasPrefix("Sources/") && path != "Sources/SafeDICore/Models/ReservedName.swift"
		case .backtick:
			path.hasPrefix("Sources/") && path != "Sources/SafeDICore/Extensions/IdentifierSpellingExtensions.swift"
		case .apostrophe:
			path.hasPrefix("Sources/") || path.hasPrefix("Plugins/") || path.hasPrefix("TuistPlugins/")
		case .testableImport:
			path.hasPrefix("Tests/SafeDIToolTestSupport/")
		case .uncheckedConcurrency, .taskGroupTupleElement:
			path.hasPrefix("Sources/") || path.hasPrefix("Plugins/")
		case .taskLocalFunction:
			path.hasPrefix("Sources/") || path.hasPrefix("Plugins/") || path.hasPrefix("Tests/SafeDIToolTestSupport/")
		case .engineFeatureName:
			path.hasPrefix("Sources/SafeDICore/Generators/Emission/TypeKeyBody") || path == "Sources/SafeDICore/Generators/Emission/PlaceRecord.swift"
		case .typeFactsFoldModelName:
			[
				"Sources/SafeDICore/Generators/TypeFacts/OrderedGraph.swift",
				"Sources/SafeDICore/Generators/TypeFacts/ReadsFromAbove.swift",
				"Sources/SafeDICore/Generators/TypeFacts/SiblingOrder.swift",
				"Sources/SafeDICore/Generators/TypeFacts/TypeFactsColumns.swift",
				"Sources/SafeDICore/Generators/TypeFacts/TypeFactsOutcomes.swift",
				"Sources/SafeDICore/Generators/TypeFacts/TypeFactsVariants.swift",
			].contains(path)
		case .stringScan:
			path.hasPrefix("Sources/SafeDICore/Generators/")
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
				problem = if reason.isEmpty {
					"the waiver of `\(rule.rawValue)` gives no reason"
				} else if rule == .uncheckedConcurrency, !Self.citesDansOK(reason) {
					"the waiver of `\(rule.rawValue)` must cite Dan’s explicit OK for this site: `— \(Self.dansOKMarker) <where he gave it>`"
				} else {
					nil
				}
			} else {
				rule = nil
				problem = "a waiver reads `\(SourceRuleCheck.waiverMarker) allow <rule> — <reason>`, where the rule is one of \(SourceRule.allCases.map { "`\($0.rawValue)`" }.joined(separator: ", "))"
			}
		}

		/// What a waiver of `uncheckedConcurrency` begins its reason with, before where Dan gave his OK.
		private static let dansOKMarker = "Dan’s OK:"

		/// Whether `reason` begins with `dansOKMarker`, its apostrophe straight or curly, and says where he gave it.
		private static func citesDansOK(_ reason: Substring) -> Bool {
			let reason = reason.replacingOccurrences(of: "'", with: "’")
			guard reason.hasPrefix(dansOKMarker) else { return false }
			return !reason.dropFirst(dansOKMarker.count).trimmingCharacters(in: .whitespaces).isEmpty
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

	override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
		if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
		   !Self.scansUTF8Bytes(memberAccess),
		   Self.stringScanFunctionNames.contains(memberAccess.declName.baseName.text)
		   || (memberAccess.declName.baseName.text == "contains" && node.arguments.contains { $0.expression.is(StringLiteralExprSyntax.self) })
		{
			let memberName = memberAccess.declName.baseName
			record(.stringScan, at: memberName, "`\(memberName.text)` reads every character of its text, and a generator’s code runs per place or per node: go over UTF-8 bytes (`GeneratedCodeText`), or waive a site that runs a bounded number of times with why")
		}
		if let calledName = node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
		   Self.taskGroupFunctionNames.contains(calledName),
		   let elementType = node.arguments.first(where: { $0.label?.text == "of" })?.expression,
		   Self.namesTupleMetatype(elementType)
		{
			record(.taskGroupTupleElement, at: elementType, "a task group whose element is a tuple miscompiles in release builds of Swift 6.3 and 6.4: return a struct")
		}
		return .visitChildren
	}

	/// Whether `memberAccess` is called on a string's UTF-8 view (`code.utf8.split(separator: UInt8(ascii: "\n"))`), which
	/// is the remedy the rule recommends: it compares bytes, not characters.
	private static func scansUTF8Bytes(_ memberAccess: MemberAccessExprSyntax) -> Bool {
		memberAccess.base?.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "utf8"
	}

	/// The members that scan every character of a string whatever their arguments.
	private static let stringScanFunctionNames: Set<String> = ["split", "replacingOccurrences", "components"]

	/// The functions that make a task group whose element type their `of:` argument names.
	private static let taskGroupFunctionNames: Set<String> = ["withTaskGroup", "withThrowingTaskGroup"]

	/// Whether `expression`, a task group's `of:` argument, is the metatype of a tuple or of an optional tuple:
	/// `(Int, String).self`, `(index: Int, read: Read)?.self`.
	private static func namesTupleMetatype(_ expression: ExprSyntax) -> Bool {
		guard let memberAccess = expression.as(MemberAccessExprSyntax.self), memberAccess.declName.baseName.text == "self", var base = memberAccess.base else {
			return false
		}
		while let optional = base.as(OptionalChainingExprSyntax.self) {
			base = optional.expression
		}
		guard let tuple = base.as(TupleExprSyntax.self) else {
			return false
		}
		return tuple.elements.count > 1 || tuple.elements.contains { $0.label != nil }
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

	override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
		let text: String? = if case let .identifier(text) = token.tokenKind {
			text
		} else if case let .stringSegment(text) = token.tokenKind {
			text
		} else {
			nil
		}
		if let text, let word = Self.featureWords(in: text).first {
			record(.engineFeatureName, at: token, "the type key and its records name no feature, and `\(text)` names `\(word)`: record the fact in general terms on the place, and read that")
		}
		if case let .identifier(text) = token.tokenKind, Self.modelNames.contains(text) {
			record(.typeFactsFoldModelName, at: token, "a fold of the per-type facts works on IDs and bit sets, and names no `\(text)`: intern the value where the graph is built, and read its ID")
		}
		return .visitChildren
	}

	override func visit(_ node: StringSegmentSyntax) -> SyntaxVisitorContinueKind {
		if node.content.text.contains(Self.builderFunctionNamePrefix) {
			record(.builderFunctionNamePrefix, at: node.content, Self.builderFunctionNamePrefixMessage)
		}
		if Self.containsStraightApostrophe(node) {
			record(.apostrophe, at: node.content, "the text SafeDI emits spells an apostrophe ’, never '")
		}
		for trap in Self.trapsSpelled(in: node.content.text) {
			record(.generatedTrap, at: node.content, "a literal in `Sources` spells `\(trap)`, so the code it generates could trap")
		}
		return .visitChildren
	}

	override func visit(_ node: DeclModifierSyntax) -> SyntaxVisitorContinueKind {
		if node.name.tokenKind == .keyword(.nonisolated), node.detail?.detail.text == "unsafe" {
			record(.uncheckedConcurrency, at: node.name, "`nonisolated(unsafe)` opts out of the compiler’s proof of concurrency safety")
		}
		return .visitChildren
	}

	override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
		if node.attributeName.trimmedDescription == "unchecked" {
			record(.uncheckedConcurrency, at: node.atSign, "`@unchecked Sendable` opts out of the compiler’s proof of concurrency safety")
		}
		// `@testable` in an import's attributes, directly or inside an `#if` among them, reported at the `import` keyword's
		// line, where a waiver goes.
		if node.attributeName.trimmedDescription == "testable", let importDeclaration = Self.importDeclaration(whoseAttributesHold: node) {
			record(.testableImport, at: importDeclaration.importKeyword, "a release build compiles `SafeDIToolTestSupport` without `-enable-testing`, which rejects `@testable import`")
		}
		return .visitChildren
	}

	override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
		let isTaskLocal = node.attributes.contains { element in
			element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "TaskLocal"
		}
		if isTaskLocal {
			for binding in node.bindings where Self.holdsFunction(binding) {
				record(.taskLocalFunction, at: binding.pattern, "a task-local function crashes Swift 6.3’s release builds in `swift_task_localValuePush` when `withValue` binds it: hold it in a `TaskLocalFunction`")
			}
		}
		return .visitChildren
	}

	/// Whether `binding`, a binding of a `@TaskLocal`, holds a function: its type, through any optional, parentheses and
	/// attributes, is a function type, or, without a type, its value is a closure.
	private static func holdsFunction(_ binding: PatternBindingSyntax) -> Bool {
		guard var type = binding.typeAnnotation?.type else {
			return binding.initializer?.value.is(ClosureExprSyntax.self) ?? false
		}
		while true {
			if let optional = type.as(OptionalTypeSyntax.self) {
				type = optional.wrappedType
			} else if let implicitlyUnwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
				type = implicitlyUnwrapped.wrappedType
			} else if let attributed = type.as(AttributedTypeSyntax.self) {
				type = attributed.baseType
			} else if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1, let element = tuple.elements.first, element.firstName == nil {
				type = element.type
			} else if let identifier = type.as(IdentifierTypeSyntax.self), identifier.name.text == "Optional",
			          let arguments = identifier.genericArgumentClause?.arguments, arguments.count == 1,
			          let argument = arguments.first.flatMap({ TypeSyntax($0.argument) })
			{
				type = argument
			} else {
				return type.is(FunctionTypeSyntax.self)
			}
		}
	}

	override func visit(_ node: RegexLiteralExprSyntax) -> SyntaxVisitorContinueKind {
		if node.regex.text.contains(Self.builderFunctionNamePrefix) {
			record(.builderFunctionNamePrefix, at: node.regex, Self.builderFunctionNamePrefixMessage)
		}
		return .visitChildren
	}

	// MARK: Private

	private static let trappingFunctionNames: Set = ["fatalError", "precondition", "preconditionFailure", "assert", "assertionFailure"]

	/// The model types a fold of the per-type facts must not name (`typeFactsFoldModelName`).
	private static let modelNames: Set = ["String", "Property", "TypeDescription"]

	/// The words that name a feature the type key must not know, each in the forms an identifier spells it.
	private static let featureWords: Set = ["mock", "mocks", "mocked", "override", "overrides", "overridden", "configuration", "configurations", "seam", "seams", "hole", "holes", "fill", "fills", "filled"]

	/// The feature words `text` spells, in order: a word is a run of letters that a capital letter begins or follows,
	/// as in `seamRoot` and `SafeDIOverrides`, so `fulfillingProperty` spells none.
	private static func featureWords(in text: String) -> [String] {
		var words = [String]()
		var word = ""
		for character in text + " " {
			if character.isLetter, !character.isUppercase {
				word.append(character)
			} else {
				if featureWords.contains(word.lowercased()) {
					words.append(word.lowercased())
				}
				word = character.isLetter ? String(character) : ""
			}
		}
		return words
	}

	/// The traps `text` spells, in the order they first appear: a name in `trappingFunctionNames`, or `unsafelyUnwrapped`, as
	/// a whole word, neither preceded nor followed by a letter, a digit or `_`; or `try` or `as` as a whole word followed by
	/// `!`.
	private static func trapsSpelled(in text: String) -> [String] {
		let characters = Array(text)
		func isIdentifierCharacter(_ character: Character) -> Bool {
			character.isLetter || character.isNumber || character == "_"
		}
		var traps = [String]()
		var wordStart: Int?
		for index in 0...characters.count {
			if index < characters.count, isIdentifierCharacter(characters[index]) {
				wordStart = wordStart ?? index
			} else if let start = wordStart {
				let word = String(characters[start..<index])
				let trap: String? = if trappingFunctionNames.contains(word) || word == "unsafelyUnwrapped" {
					word
				} else if ["try", "as"].contains(word), index < characters.count, characters[index] == "!" {
					word + "!"
				} else {
					nil
				}
				if let trap, !traps.contains(trap) {
					traps.append(trap)
				}
				wordStart = nil
			}
		}
		return traps
	}

	/// The argument labels of the `Dictionary` initializers that trap on a duplicate key, each with its message.
	private static let duplicateKeyTrappingLabels = [
		"uniqueKeysWithValues": "`Dictionary(uniqueKeysWithValues:)` traps on a duplicate key",
		"dictionaryLiteral": "`Dictionary(dictionaryLiteral:)` traps on a duplicate key",
	]
	private static let builderFunctionNamePrefix = "__safeDI_"
	private static let builderFunctionNamePrefixMessage = "only `ReservedName.builderFunctionNamePrefix` spells `__safeDI_`"

	private let path: String
	private let converter: SourceLocationConverter

	/// Whether `segment` holds a ' that a letter follows and that a letter, a digit, a backtick or an interpolation
	/// precedes: an apostrophe, not a quotation mark such as `'\(path)'` or a quoted character such as `"'"`.
	private static func containsStraightApostrophe(_ segment: StringSegmentSyntax) -> Bool {
		let characters = Array(segment.content.text)
		// After an interpolation, the token before the segment's text is the interpolation's closing parenthesis.
		let followsInterpolation = segment.content.previousToken(viewMode: .sourceAccurate)?.parent?.is(ExpressionSegmentSyntax.self) == true
		return characters.indices.contains { index in
			characters[index] == "'"
				&& index + 1 < characters.count
				&& characters[index + 1].isLetter
				&& (index == 0 ? followsInterpolation : characters[index - 1].isLetter || characters[index - 1].isNumber || characters[index - 1] == "`")
		}
	}

	private func record(_ rule: SourceRule, at node: some SyntaxProtocol, _ message: String) {
		guard rule.applies(toFileAt: path) else { return }
		violations.append((
			line: converter.location(for: node.positionAfterSkippingLeadingTrivia).line,
			rule: rule,
			message: message,
		))
	}

	/// The import declaration whose attributes hold `attribute`, directly or inside an `#if` among them, or `nil` when
	/// `attribute` belongs to another declaration.
	private static func importDeclaration(whoseAttributesHold attribute: AttributeSyntax) -> ImportDeclSyntax? {
		var ancestor = attribute.parent
		while let node = ancestor {
			if let importDeclaration = node.as(ImportDeclSyntax.self) {
				return importDeclaration
			} else if node.is(DeclSyntax.self), !node.is(IfConfigDeclSyntax.self) {
				return nil
			} else {
				ancestor = node.parent
			}
		}
		return nil
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
