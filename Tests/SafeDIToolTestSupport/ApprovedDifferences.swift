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
	/// The tree's text is read only to choose among the candidates the records' text itself holds.
	let rewrite: @Sendable (_ nodeRecordsText: String, _ treeText: String) -> String?
}

enum ApprovedDifferences {
	/// Every approved difference the check of node records knows, in the order it applies them.
	static let all: [ApprovedDifference] = [
		ApprovedDifference(entry: 13, name: "optional channel, rule A", rewrite: OptionalChannelRewrite.rewritten),
		ApprovedDifference(entry: 28, name: "one function for properties of one type", rewrite: SharedFunctionRewrite.rewritten),
		ApprovedDifference(entry: 29, name: "a function named apart from another body's", rewrite: NameKeptApartRewrite.rewritten),
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

/// Entry 28, one function for several properties of one type (lead, 2026-11-28). Laid out by type, the properties of one
/// type whose bodies are alike share one builder function, named for the first of them in the order the walk builds
/// them, never by label; the tree writes a copy for each property, under the property's own name. The rewrite gives each
/// later property's statement a copy of the shared function, declared just before the statement as the tree declares
/// it, and calls the copy there. A copy is the shared function with only its name changed, so the rewritten text equals
/// the tree's only where the tree's copies differ by name alone and every reader captures the same declarations; where
/// the first property's statement does not call the function under its own name, nothing is rewritten.
enum SharedFunctionRewrite {
	static func rewritten(_ nodeRecordsText: String, treeText: String) -> String? {
		var code = FunctionText(nodeRecordsText)
		var copied = false
		while code.copyNextSharedFunction(treeText: treeText) {
			copied = true
		}
		return copied ? code.text : nil
	}
}

extension FunctionText {
	/// Gives the next statement that calls a function named for an earlier property a copy of that function named for its
	/// own property, which the tree's text declares, and returns whether it found one.
	mutating func copyNextSharedFunction(treeText: String) -> Bool {
		for function in functions {
			let indentation = String(lines[function.range.lowerBound].prefix { $0 == " " })
			guard let property = Self.property(namedBy: function.name),
			      let scopeEnd = lines[function.range.upperBound...].firstIndex(where: { Self.closesScope(at: indentation, $0) })
			else { continue }
			let statements = Self.statementStarts(in: function.range.upperBound..<scopeEnd, indentation: indentation, of: lines)
			var callers = [(start: Int, property: String)]()
			for (position, start) in statements.enumerated() {
				let end = position + 1 < statements.count ? statements[position + 1] : scopeEnd
				guard lines[start..<end].contains(where: { Self.references(function.name, in: $0) }),
				      let statementProperty = Self.boundProperty(of: lines[start], indentation: indentation)
				else { continue }
				callers.append((start, statementProperty))
			}
			guard callers.first?.property == property else { continue }
			for caller in callers.dropFirst().reversed() {
				let copyName = "__safeDI_" + caller.property
				guard copyName != function.name, treeText.contains("func \(copyName)("),
				      !functions.contains(where: { $0.name == copyName })
				else { continue }
				let end = statements.first { $0 > caller.start } ?? scopeEnd
				for index in caller.start..<end {
					lines[index] = Self.replacingReferences(to: function.name, with: copyName, in: lines[index])
				}
				let copy = lines[function.range].enumerated().map { offset, line in
					offset == 0 ? Self.replacingReferences(to: function.name, with: copyName, in: line) : line
				}
				lines.insert(contentsOf: copy, at: caller.start)
				return true
			}
		}
		return false
	}

	/// The property a builder function named `__safeDI_<label>` builds.
	private static func property(namedBy functionName: String) -> String? {
		guard functionName.hasPrefix("__safeDI_") else { return nil }
		return String(functionName.dropFirst("__safeDI_".count))
	}

	/// Whether `line` closes the scope whose statements are at `indentation`.
	private static func closesScope(at indentation: String, _ line: String) -> Bool {
		let lineIndentation = line.prefix { $0 == " " }
		return lineIndentation.count < indentation.count && !line.dropFirst(lineIndentation.count).isEmpty
	}

	/// The first line of each statement in `range` whose indentation is `indentation`, a function declaration's included.
	private static func statementStarts(in range: Range<Int>, indentation: String, of lines: [String]) -> [Int] {
		range.filter { index in
			let line = lines[index]
			return line.hasPrefix(indentation) && line.dropFirst(indentation.count).first.map { $0 != " " && $0 != "}" } == true
		}
	}

	/// The label a statement's first line binds, `let <label>` or `let <label>: <type>`.
	private static func boundProperty(of line: String, indentation: String) -> String? {
		let statement = line.dropFirst(indentation.count)
		guard statement.hasPrefix("let ") else { return nil }
		let label = statement.dropFirst("let ".count).prefix { isIdentifierCharacter($0) }
		return label.isEmpty ? nil : String(label)
	}
}

/// Entry 29, a function named apart from another body's function of its name. The type key names every builder function
/// it lays out apart from every other, whatever body declares it, so a function whose name a function of another body
/// already has takes underscores; the tree names each `__safeDI_<label>` and relies on Swift's scopes, where a nested
/// function hides an outer one of its name. The rewrite gives such a function the tree's name back only where no
/// reference to it lies inside a body that declares that name, so the name it takes back hides nothing it reads.
enum NameKeptApartRewrite {
	static func rewritten(_ nodeRecordsText: String, treeText: String) -> String? {
		var code = FunctionText(nodeRecordsText)
		let treeLines = Set(treeText.components(separatedBy: "\n"))
		var renamed = false
		while code.restoreNextNameKeptApart(treeLines: treeLines) {
			renamed = true
		}
		return renamed ? code.text : nil
	}
}

extension FunctionText {
	/// Gives the next function whose name ends in underscores the tree's name without them, where the tree declares a
	/// function of that name at the same line and no reference to the function lies inside a body declaring that name,
	/// and returns whether it found one.
	mutating func restoreNextNameKeptApart(treeLines: Set<String>) -> Bool {
		let functions = functions
		for function in functions {
			let name = String(function.name.reversed().drop { $0 == "_" }.reversed())
			guard name != function.name, name.hasPrefix("__safeDI_"),
			      treeLines.contains(Self.replacingReferences(to: function.name, with: name, in: lines[function.range.lowerBound]))
			else { continue }
			let hidingBodies = functions.filter { $0.name == name }.map(\.range)
			guard !lines.indices.contains(where: { index in
				hidingBodies.contains { $0.contains(index) } && Self.references(function.name, in: lines[index])
			})
			else { continue }
			lines = lines.map { Self.replacingReferences(to: function.name, with: name, in: $0) }
			return true
		}
		return false
	}
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
