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

/// One approved difference between the code laid out from node records and the code a root's tree spells: an entry of
/// the list of approved byte differences, as a rewrite of the records' text into the text the tree writes for the same
/// root. A rewrite is the entry's own change of structure and nothing else: a root whose rewritten text is not the
/// tree's, byte for byte, still differs (`ApprovedDifferences.normalized(nodeRecordsText:treeText:)`).
struct ApprovedDifference: Sendable {
	/// The entry's number in the list of approved differences.
	let entry: Int
	/// What the entry is, in a few words.
	let name: String
	/// The records' text with the entry's difference written as the tree writes it, or `nil` where the text holds none.
	/// The tree's text is read only to choose among the candidates the records' text itself holds, or, for an entry that
	/// only moves code, to be returned where the two texts are equal once what the entry moves is taken out of both.
	let rewrite: @Sendable (_ nodeRecordsText: String, _ treeText: String) -> String?
}

enum ApprovedDifferences {
	/// Every approved difference the check of node records knows, in the order it applies them.
	static let all: [ApprovedDifference] = [
		ApprovedDifference(entry: 13, name: "optional channel, rule A", rewrite: OptionalChannelRewrite.rewritten),
		ApprovedDifference(entry: 24, name: "a filled call’s root laid out by the type key", rewrite: FilledCallFunctionsRewrite.rewritten),
	]

	/// The records' text after each approved difference that it holds is rewritten as the tree writes it, and the entries
	/// rewritten, where the result is the tree's text; `nil` where the texts still differ, or were equal to begin with.
	static func normalized(nodeRecordsText: String, treeText: String, by differences: [ApprovedDifference] = all) -> (text: String, entries: [Int])? {
		guard nodeRecordsText != treeText else { return nil }
		var text = nodeRecordsText
		var entries = [Int]()
		for difference in differences {
			guard let rewritten = difference.rewrite(text, treeText) else { continue }
			text = rewritten
			entries.append(difference.entry)
		}
		guard text == treeText else { return nil }
		return (text, entries)
	}
}

/// Entry 13, the optional channel under rule A. Laid out from the facts, a call that passes `nil` for a read received
/// only if available goes to the function that takes the read in its declared form, `theme: Theme?`, and a function a
/// wrapper answers takes the wrapper itself, `theme: LazilyInstantiated<Theme>`, and reads its instance. The tree gives
/// the `nil` to the function of a place a wrapper answers instead, whose parameter it makes optional,
/// `theme: LazilyInstantiated<Theme>?`, read as `theme?.instance`. The rewrite moves each such call to that function,
/// makes the parameter optional in it and in every function it hands the wrapper to, removes each function nothing
/// calls any more, and names the functions that remain of a removed one's name as the tree numbers them.
enum OptionalChannelRewrite {
	static func rewritten(_ nodeRecordsText: String, treeText: String) -> String? {
		var code = FunctionText(nodeRecordsText)
		var removedCalls = [String]()
		while let move = code.nextMove(treeText: treeText) {
			code.makeOptional(move.label, wrapperType: move.wrapperType, inFunctionNamed: move.target)
			code.retargetCalls(of: move.source, passingNilFor: move.label, to: move.target)
			removedCalls.append(move.source)
		}
		guard !removedCalls.isEmpty else { return nil }
		let removedNames = code.removeFunctionsNothingReferences(startingFrom: removedCalls)
		code.moveFunctionsBeforeFirstReference(removedCalls.filter { !removedNames.contains($0) })
		code.renumberFunctions(sharingNameWith: removedNames)
		return code.text
	}

	/// A call of `source` that passes `nil` for `label`, to move to `target`, which takes `label` as `wrapperType`.
	struct Move {
		let source: String
		let target: String
		let label: String
		let wrapperType: String
	}

	/// The wrappers whose instance answers a read of the unwrapped form.
	static let wrapperNames = ["LazilyInstantiated", "SendableLazilyInstantiated"]
}

/// Generated code as lines, read as the builder functions it declares.
struct FunctionText {
	init(_ text: String) {
		lines = text.components(separatedBy: "\n")
	}

	var text: String {
		lines.joined(separator: "\n")
	}

	private var lines: [String]

	struct Function {
		let name: String
		let parameters: [(label: String, type: String)]
		let returnType: String
		/// The lines of the declaration: its signature, its body and its closing brace.
		let range: Range<Int>
	}

	/// The functions the text declares, in order.
	var functions: [Function] {
		var functions = [Function]()
		for (index, line) in lines.enumerated() {
			let indentation = line.prefix { $0 == " " }
			var declaration = line.dropFirst(indentation.count)
			if declaration.hasPrefix("@Sendable nonisolated ") {
				declaration = declaration.dropFirst("@Sendable nonisolated ".count)
			}
			guard declaration.hasPrefix("func "), declaration.hasSuffix(" {"),
			      let open = declaration.firstIndex(of: "("),
			      let close = Self.matchingParenthesis(in: declaration, openedAt: open),
			      declaration[declaration.index(after: close)...].hasPrefix(" -> "),
			      let end = lines[index...].firstIndex(of: indentation + "}")
			else { continue }
			let returnType = declaration[declaration.index(after: close)...].dropFirst(" -> ".count).dropLast(" {".count)
			let parameters = Self.topLevelParts(of: declaration[declaration.index(after: open)..<close]).compactMap { part -> (label: String, type: String)? in
				guard let colon = part.range(of: ": ") else { return nil }
				return (String(part[..<colon.lowerBound]), String(part[colon.upperBound...]))
			}
			functions.append(Function(
				name: String(declaration[declaration.index(declaration.startIndex, offsetBy: "func ".count)..<open]),
				parameters: parameters,
				returnType: String(returnType),
				range: index..<(end + 1),
			))
		}
		return functions
	}

	/// The next call to move: a function that takes a label as an optional of a type and is called with `nil` for it,
	/// beside a function of its name that takes a wrapper of the type, which the tree's text declares optional.
	func nextMove(treeText: String) -> OptionalChannelRewrite.Move? {
		let functions = functions
		for source in functions {
			for (position, parameter) in source.parameters.enumerated() where parameter.type.hasSuffix("?") {
				guard callsPassNil(for: parameter.label, to: source) else { continue }
				let declaredType = String(parameter.type.dropLast())
				let wrapperTypes = OptionalChannelRewrite.wrapperNames.map { "\($0)<\(declaredType)>" }
				let target = functions.first { candidate in
					candidate.name != source.name
						&& Self.stem(of: candidate.name) == Self.stem(of: source.name)
						&& candidate.returnType == source.returnType
						&& candidate.parameters.map(\.label) == source.parameters.map(\.label)
						&& wrapperTypes.contains(candidate.parameters[position].type)
						&& treeText.contains("\(parameter.label): \(candidate.parameters[position].type)?")
				}
				guard let target else { continue }
				return OptionalChannelRewrite.Move(source: source.name, target: target.name, label: parameter.label, wrapperType: target.parameters[position].type)
			}
		}
		return nil
	}

	/// Makes `label`, a parameter of type `wrapperType`, optional in the function named `name` and in every function its
	/// body hands the parameter to under the same label, and reads the wrapper's instance through the optional.
	mutating func makeOptional(_ label: String, wrapperType: String, inFunctionNamed name: String) {
		var pending = [name]
		var visited = Set<String>()
		while let name = pending.popLast() {
			guard visited.insert(name).inserted, let function = functions.first(where: { $0.name == name }) else { continue }
			lines[function.range.lowerBound] = lines[function.range.lowerBound].replacingOccurrences(of: "\(label): \(wrapperType),", with: "\(label): \(wrapperType)?,")
				.replacingOccurrences(of: "\(label): \(wrapperType))", with: "\(label): \(wrapperType)?)")
			for index in function.range.dropFirst() {
				lines[index] = Self.replacingReferences(to: "\(label).instance", with: "\(label)?.instance", in: lines[index])
			}
			let body = lines[function.range.dropFirst()].joined(separator: "\n")
			for callee in functions where callee.parameters.contains(where: { $0.label == label && $0.type == wrapperType }) && body.contains("\(callee.name)(") && Self.arguments(ofCallsTo: callee.name, in: body).contains(where: { $0.contains("\(label): \(label)") }) {
				pending.append(callee.name)
			}
		}
	}

	/// Whether a call of `function` outside its own body passes `nil` for `label`.
	private func callsPassNil(for label: String, to function: Function) -> Bool {
		lines.indices.contains { index in
			!function.range.contains(index) && Self.arguments(ofCallsTo: function.name, in: lines[index]).contains { $0.contains("\(label): nil") }
		}
	}

	/// Renames each call of `source` that passes `nil` for `label` to a call of `target`.
	mutating func retargetCalls(of source: String, passingNilFor label: String, to target: String) {
		for index in lines.indices where Self.arguments(ofCallsTo: source, in: lines[index]).contains(where: { $0.contains("\(label): nil") }) {
			lines[index] = Self.replacingReferences(to: source, with: target, in: lines[index])
		}
	}

	/// Removes each function among `names` that nothing outside its own declaration references, then each function only
	/// a removed one referenced, and returns the names removed.
	mutating func removeFunctionsNothingReferences(startingFrom names: [String]) -> [String] {
		var pending = names
		var removed = [String]()
		while let name = pending.popLast() {
			let functions = functions
			guard let function = functions.first(where: { $0.name == name }),
			      !lines.indices.contains(where: { !function.range.contains($0) && Self.references(name, in: lines[$0]) })
			else { continue }
			let body = lines[function.range]
			pending += functions.map(\.name).filter { other in other != name && body.contains { Self.references(other, in: $0) } }
			lines.removeSubrange(function.range)
			removed.append(name)
		}
		return removed
	}

	/// Moves each function among `names`, which lost its first call, to just before the function that now references it
	/// first: a builder function is declared where its first caller is.
	mutating func moveFunctionsBeforeFirstReference(_ names: [String]) {
		for name in names {
			guard let function = functions.first(where: { $0.name == name }) else { continue }
			let declaration = Array(lines[function.range])
			lines.removeSubrange(function.range)
			guard let reference = lines.indices.first(where: { Self.references(name, in: lines[$0]) }),
			      let caller = functions.last(where: { $0.range.contains(reference) })
			else {
				lines.insert(contentsOf: declaration, at: function.range.lowerBound)
				continue
			}
			lines.insert(contentsOf: declaration, at: caller.range.lowerBound)
		}
	}

	/// Names the functions that share a name with one of `removedNames`, apart from its trailing underscores, in the order
	/// the text declares them: the name, then the name with one more underscore each, as names are claimed.
	mutating func renumberFunctions(sharingNameWith removedNames: [String]) {
		var renames = [String: String]()
		for stem in Set(removedNames.map(Self.stem)) {
			for (position, function) in functions.filter({ Self.stem(of: $0.name) == stem }).enumerated() {
				let name = stem + String(repeating: "_", count: position)
				guard name != function.name else { continue }
				renames[function.name] = name
			}
		}
		guard !renames.isEmpty else { return }
		for index in lines.indices {
			lines[index] = Self.renaming(renames, in: lines[index])
		}
	}

	// MARK: Reading a line

	/// `name` without the underscores a claim of a taken name appends.
	static func stem(of name: String) -> String {
		var stem = Substring(name)
		while stem.hasSuffix("_"), !stem.hasSuffix("__safeDI_") {
			stem = stem.dropLast()
		}
		return String(stem)
	}

	private static func isIdentifierCharacter(_ character: Character) -> Bool {
		character.isLetter || character.isNumber || character == "_"
	}

	/// The ranges of `name` in `line` where no identifier character is beside it.
	private static func referenceRanges(of name: String, in line: String) -> [Range<String.Index>] {
		var ranges = [Range<String.Index>]()
		var searchStart = line.startIndex
		while let range = line.range(of: name, range: searchStart..<line.endIndex) {
			let isBoundedBefore = range.lowerBound == line.startIndex || !isIdentifierCharacter(line[line.index(before: range.lowerBound)])
			let isBoundedAfter = range.upperBound == line.endIndex || !isIdentifierCharacter(line[range.upperBound])
			if isBoundedBefore, isBoundedAfter {
				ranges.append(range)
			}
			searchStart = range.upperBound
		}
		return ranges
	}

	private static func references(_ name: String, in line: String) -> Bool {
		!referenceRanges(of: name, in: line).isEmpty
	}

	private static func replacingReferences(to name: String, with replacement: String, in line: String) -> String {
		var line = line
		for range in referenceRanges(of: name, in: line).reversed() {
			line.replaceSubrange(range, with: replacement)
		}
		return line
	}

	/// `line` with every reference to a key of `renames` replaced by its value, each read from the line as it was.
	private static func renaming(_ renames: [String: String], in line: String) -> String {
		var replacements = [(range: Range<String.Index>, name: String)]()
		for (old, new) in renames {
			replacements += referenceRanges(of: old, in: line).map { ($0, new) }
		}
		var line = line
		for replacement in replacements.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
			line.replaceSubrange(replacement.range, with: replacement.name)
		}
		return line
	}

	/// The argument lists of the calls of `name` in `text`, each split at its top-level commas.
	private static func arguments(ofCallsTo name: String, in text: String) -> [String] {
		referenceRanges(of: name, in: text).flatMap { range -> [String] in
			guard range.upperBound < text.endIndex, text[range.upperBound] == "(",
			      let close = matchingParenthesis(in: text[...], openedAt: range.upperBound)
			else { return [] }
			return topLevelParts(of: text[text.index(after: range.upperBound)..<close])
		}
	}

	private static func matchingParenthesis(in text: Substring, openedAt open: String.Index) -> String.Index? {
		var depth = 0
		for index in text[open...].indices {
			switch text[index] {
			case "(": depth += 1
			case ")":
				depth -= 1
				if depth == 0 {
					return index
				}
			default: break
			}
		}
		return nil
	}

	/// `list` split at the commas outside every bracket.
	private static func topLevelParts(of list: Substring) -> [String] {
		var parts = [String]()
		var depth = 0
		var part = ""
		for character in list {
			switch character {
			case "(", "<", "[": depth += 1
			// The `>` of a function type's arrow closes nothing.
			case ">" where part.hasSuffix("-"): break
			case ")", ">", "]": depth -= 1
			default: break
			}
			if character == ",", depth == 0 {
				parts.append(part.trimmingCharacters(in: .whitespaces))
				part = ""
			} else {
				part.append(character)
			}
		}
		if !part.isEmpty {
			parts.append(part.trimmingCharacters(in: .whitespaces))
		}
		return parts
	}
}

/// Entry 24, a filled call's root laid out by the type key. Node records lay out a root that calls a seam it fills as the
/// type key lays out every root it lays out (entry 7): each builder function is declared once, where the tree declares
/// it again in each parent that builds it, at the top of the body that holds what it reads, a fill's functions at the top of the fill's body, each taking as parameters what the tree's
/// function, nested where it is built, captures. The rewrite takes every function out of both texts, innermost first
/// (`FlattenedFunctionText`): where the two leave the same text and take out the same distinct functions, the records' text is
/// the tree's but for where it declares its functions and what they take, and the rewrite returns the tree's text. A
/// text that declares no fill's dispatcher is never rewritten.
enum FilledCallFunctionsRewrite {
	static func rewritten(_ nodeRecordsText: String, treeText: String) -> String? {
		guard holdsAFilledCall(nodeRecordsText), FlattenedFunctionText(nodeRecordsText) == FlattenedFunctionText(treeText) else { return nil }
		return treeText
	}

	/// Whether `text` declares a fill's dispatcher: a function whose result is the carrier of a seam's hole.
	static func holdsAFilledCall(_ text: String) -> Bool {
		text.components(separatedBy: "\n").contains { line in
			FlattenedFunctionText.declaredName(in: line) != nil && line.range(of: #"-> [A-Za-z0-9_.]*\.__safeDI_[A-Za-z0-9_]*Carrier[A-Za-z0-9_]*<"#, options: .regularExpression) != nil
		}
	}
}

/// Generated code with every function it declares taken out, innermost first: what remains, and the distinct functions,
/// sorted, each without the functions it declared and without its indentation. Every call of a function taken out, its declaration's
/// parameter list among them, takes no arguments, and a wrapper made of a closure that only calls one, `Instantiator<T> {`
/// with the call on the next line, is the wrapper made of the function, `Instantiator<T>(name)`.
struct FlattenedFunctionText: Equatable {
	let remainder: [String]
	let functions: [[String]]

	init(_ text: String) {
		var lines = text.components(separatedBy: "\n")
		var functions = [[String]]()
		var names = Set<String>()
		while let function = Self.innermostFunction(in: lines) {
			names.insert(function.name)
			var declaration = lines[function.range].map { $0.hasPrefix(function.indentation) ? String($0.dropFirst(function.indentation.count)) : $0 }
			// A function declared inside a `@Sendable` function is spelled as the `@Sendable` one the type key declares outside
			// it, which that function calls (entry 24, lead 11-28 05:07Z).
			if !declaration[0].hasPrefix(Self.sendablePrefix), Self.isInsideSendableFunction(function.range, in: lines) {
				declaration[0] = Self.sendablePrefix + declaration[0]
			}
			functions.append(declaration)
			lines.removeSubrange(function.range)
		}
		remainder = Self.erasingArguments(ofCallsTo: names, in: lines)
		// The tree declares a function again in each parent that builds it, where the type key declares it once.
		var distinct = [[String]]()
		for function in functions.map({ Self.erasingArguments(ofCallsTo: names, in: $0) }).sorted(by: { $0.lexicographicallyPrecedes($1) }) where distinct.last != function {
			distinct.append(function)
		}
		self.functions = distinct
	}

	/// The name of the function `line` declares, after its attributes and modifiers, or `nil`.
	static func declaredName(in line: String) -> String? {
		var declaration = line.drop { $0 == " " }
		while declaration.hasPrefix("@") || declaration.hasPrefix("nonisolated ") {
			guard let space = declaration.firstIndex(of: " ") else { return nil }
			declaration = declaration[declaration.index(after: space)...]
		}
		guard declaration.hasPrefix("func "), declaration.hasSuffix(" {"), let open = declaration.firstIndex(of: "(") else { return nil }
		return String(declaration[declaration.index(declaration.startIndex, offsetBy: "func ".count)..<open])
	}

	private static let sendablePrefix = "@Sendable nonisolated "

	/// Whether a `@Sendable` function `lines` declare holds `range`.
	private static func isInsideSendableFunction(_ range: Range<Int>, in lines: [String]) -> Bool {
		lines[..<range.lowerBound].indices.contains { index in
			let line = lines[index]
			let indentation = String(line.prefix { $0 == " " })
			guard line.dropFirst(indentation.count).hasPrefix(sendablePrefix), declaredName(in: line) != nil,
			      let end = lines[(index + 1)...].firstIndex(of: indentation + "}")
			else { return false }
			return end >= range.upperBound
		}
	}

	/// The first function `lines` declare whose body declares none.
	private static func innermostFunction(in lines: [String]) -> (name: String, indentation: String, range: Range<Int>)? {
		let declarations = lines.indices.compactMap { index in declaredName(in: lines[index]).map { (index: index, name: $0) } }
		for declaration in declarations {
			let indentation = String(lines[declaration.index].prefix { $0 == " " })
			guard let end = lines[(declaration.index + 1)...].firstIndex(of: indentation + "}"),
			      !declarations.contains(where: { declaration.index < $0.index && $0.index < end })
			else { continue }
			return (declaration.name, indentation, declaration.index..<(end + 1))
		}
		return nil
	}

	private static func erasingArguments(ofCallsTo names: Set<String>, in lines: [String]) -> [String] {
		let erased = lines.map { line in names.reduce(line) { line, name in erasingArguments(ofCallsTo: name, in: line) } }
		var result = [String]()
		var index = 0
		while index < erased.count {
			let line = erased[index]
			if line.hasSuffix("> {"), index + 2 < erased.count,
			   erased[index + 2] == String(line.prefix { $0 == " " }) + "}",
			   let called = names.first(where: { erased[index + 1].drop { $0 == " " } == "\($0)()" })
			{
				result.append(String(line.dropLast(" {".count)) + "(\(called))")
				index += 3
			} else {
				result.append(line)
				index += 1
			}
		}
		return result
	}

	/// `line` with the argument list of each call of `name` emptied.
	private static func erasingArguments(ofCallsTo name: String, in line: String) -> String {
		var line = line
		var searchStart = line.startIndex
		while let range = line.range(of: name + "(", range: searchStart..<line.endIndex) {
			let isBoundedBefore = range.lowerBound == line.startIndex || !isIdentifierCharacter(line[line.index(before: range.lowerBound)])
			let open = line.index(before: range.upperBound)
			guard isBoundedBefore, let close = matchingParenthesis(in: line, openedAt: open) else {
				searchStart = range.upperBound
				continue
			}
			line.removeSubrange(line.index(after: open)..<close)
			searchStart = line.index(after: open)
		}
		return line
	}

	private static func isIdentifierCharacter(_ character: Character) -> Bool {
		character.isLetter || character.isNumber || character == "_"
	}

	private static func matchingParenthesis(in line: String, openedAt open: String.Index) -> String.Index? {
		var depth = 0
		for index in line[open...].indices {
			if line[index] == "(" {
				depth += 1
			} else if line[index] == ")" {
				depth -= 1
				if depth == 0 {
					return index
				}
			}
		}
		return nil
	}
}
