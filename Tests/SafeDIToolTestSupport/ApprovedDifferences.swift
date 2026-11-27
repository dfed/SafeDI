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
	/// The records' text with the entry's difference written as the tree writes it, and each choice the rewrite took from
	/// the tree's text, or `nil` where the text holds none. The tree's text is read only to choose among the candidates
	/// the records' text itself holds, and each such choice is named, so that a run counts how often each was taken.
	let rewrite: @Sendable (_ nodeRecordsText: String, _ treeText: String) -> (text: String, choices: [String])?
}

enum ApprovedDifferences {
	/// Every approved difference the check of node records applies, in the order it applies them. An entry is listed
	/// with the first root that differs by it, never before: `Scripts/node-records-approved-differences.py` fails a run
	/// in which a listed entry was used on no root. `optionalChannel` waits for the first root laid out under rule A.
	static let all: [ApprovedDifference] = []

	/// Entry 13 (`OptionalChannelRewrite`).
	static let optionalChannel = ApprovedDifference(entry: 13, name: "optional channel, rule A", rewrite: OptionalChannelRewrite.rewritten)

	/// The records' text after each approved difference that it holds is rewritten as the tree writes it, and the entries
	/// rewritten, each as its number and the choices it took (`13[LazilyInstantiated]`), where the result is the tree's
	/// text; `nil` where the texts still differ, or were equal to begin with.
	static func normalized(nodeRecordsText: String, treeText: String, by differences: [ApprovedDifference] = all) -> (text: String, entries: [String])? {
		guard nodeRecordsText != treeText else { return nil }
		var text = nodeRecordsText
		var entries = [String]()
		for difference in differences {
			guard let rewritten = difference.rewrite(text, treeText) else { continue }
			text = rewritten.text
			entries.append("\(difference.entry)[\(rewritten.choices.joined(separator: "+"))]")
		}
		guard text == treeText else { return nil }
		return (text, entries)
	}
}

/// Entry 13, the optional channel under rule A: one read of the unwrapped form, received only if available, that one
/// world answers with a declared-form value, a wrapper and nothing, or with a lazy and a Sendable lazy wrapper and
/// nothing. Laid out from the facts, the call that passes `nil` goes to the function the value answers, `theme: Theme?`,
/// and each wrapper's function takes the wrapper itself, `theme: LazilyInstantiated<Theme>`; with two wrappers and no
/// value it goes to the lazy wrapper's, `theme: LazilyInstantiated<Theme>?`. The tree gives the `nil` to the function of
/// the first place in declaration order, which may be another wrapper's, typed optional and read as `theme?.instance`.
/// The rewrite moves each such call to the wrapper's function the tree declares optional, makes the parameter optional
/// in it and in every function it hands the wrapper to, makes a wrapper's function that no longer takes `nil`
/// non-optional, removes each function nothing references any more, declares a function that lost its first call where
/// its first remaining caller is, and names the functions that remain of a removed one's name as the tree numbers them
/// (`FunctionText.renumberFunctions(sharingNameWith:)`). A value and `nil`, or one wrapper and `nil`, are one function in both texts and no difference.
enum OptionalChannelRewrite {
	static func rewritten(_ nodeRecordsText: String, treeText: String) -> (text: String, choices: [String])? {
		var code = FunctionText(nodeRecordsText)
		let treeFunctions = FunctionText(treeText).functions
		var sources = [String]()
		var choices = [String]()
		// A label of one name moves once, and no more calls move than the text declares functions, so the loop ends
		// whatever the two texts hold.
		var moved = Set<String>()
		for _ in code.functions {
			guard let move = code.nextMove(treeFunctions: treeFunctions, besides: moved) else { break }
			moved.insert(move.key)
			code.makeOptional(move.label, wrapperType: move.wrapperType, inFunctionNamed: move.target)
			code.retargetCalls(of: move.source, passingNilFor: move.label, to: move.target)
			if let sourceWrapperType = move.sourceWrapperType {
				code.makeNonOptional(move.label, wrapperType: sourceWrapperType, inFunctionNamed: move.source)
			}
			sources.append(move.source)
			choices.append(String(move.wrapperType.prefix { $0 != "<" }))
		}
		guard !sources.isEmpty else { return nil }
		let removedNames = code.removeFunctionsNothingReferences(startingFrom: sources)
		code.moveFunctionsBeforeFirstReference(sources.filter { !removedNames.contains($0) })
		code.renumberFunctions(sharingNameWith: removedNames)
		return (code.text, choices)
	}

	/// A call of `source` that passes `nil` for `label`, to move to `target`, which takes `label` as `wrapperType`.
	struct Move {
		let source: String
		let target: String
		let label: String
		let wrapperType: String
		/// The wrapper `source` takes `label` as, optional, where it takes a wrapper and not the declared form.
		let sourceWrapperType: String?
		/// The name the functions share and the label: what moves once.
		let key: String
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
	/// beside a function of its name that takes a wrapper of the type, which the tree declares optional in a function of
	/// that name, `treeFunctions` being the functions the tree's text declares. A name and label among `moved` moved
	/// already.
	func nextMove(treeFunctions: [Function], besides moved: Set<String>) -> OptionalChannelRewrite.Move? {
		let functions = functions
		for source in functions {
			for (position, parameter) in source.parameters.enumerated() where parameter.type.hasSuffix("?") {
				let key = "\(Self.stem(of: source.name)) \(parameter.label)"
				guard !moved.contains(key), callsPassNil(for: parameter.label, to: source) else { continue }
				// The source takes the declared form, or a wrapper of it.
				let sourceType = String(parameter.type.dropLast())
				let sourceWrapperName = OptionalChannelRewrite.wrapperNames.first { sourceType.hasPrefix("\($0)<") && sourceType.hasSuffix(">") }
				let declaredType = sourceWrapperName.map { String(sourceType.dropFirst($0.count + 1).dropLast()) } ?? sourceType
				let wrapperTypes = OptionalChannelRewrite.wrapperNames.filter { $0 != sourceWrapperName }.map { "\($0)<\(declaredType)>" }
				let target = functions.first { candidate in
					candidate.name != source.name
						&& Self.stem(of: candidate.name) == Self.stem(of: source.name)
						&& candidate.returnType == source.returnType
						&& candidate.parameters.map(\.label) == source.parameters.map(\.label)
						&& wrapperTypes.contains(candidate.parameters[position].type)
						&& treeFunctions.contains { treeFunction in
							Self.stem(of: treeFunction.name) == Self.stem(of: source.name)
								&& treeFunction.returnType == source.returnType
								&& treeFunction.parameters.map(\.label) == source.parameters.map(\.label)
								&& treeFunction.parameters[position].type == candidate.parameters[position].type + "?"
						}
				}
				guard let target else { continue }
				return OptionalChannelRewrite.Move(source: source.name, target: target.name, label: parameter.label, wrapperType: target.parameters[position].type, sourceWrapperType: sourceWrapperName == nil ? nil : sourceType, key: key)
			}
		}
		return nil
	}

	/// Makes `label`, a parameter of type `wrapperType`, optional in the function named `name` and in every function its
	/// body hands the parameter to under the same label, and reads the wrapper's instance through the optional. A function
	/// that takes the wrapper under another label is not followed: such a text stays different from the tree's, and its
	/// root fails, where following it would be a guess.
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

	/// Makes `label`, an optional parameter of type `wrapperType`, non-optional in the function named `name` and in every
	/// function its body hands the parameter to under the same label, and reads the wrapper's instance directly.
	mutating func makeNonOptional(_ label: String, wrapperType: String, inFunctionNamed name: String) {
		var pending = [name]
		var visited = Set<String>()
		while let name = pending.popLast() {
			guard visited.insert(name).inserted, let function = functions.first(where: { $0.name == name }) else { continue }
			lines[function.range.lowerBound] = lines[function.range.lowerBound].replacingOccurrences(of: "\(label): \(wrapperType)?", with: "\(label): \(wrapperType)")
			for index in function.range.dropFirst() {
				lines[index] = lines[index].replacingOccurrences(of: "\(label)?.instance", with: "\(label).instance")
			}
			let body = lines[function.range.dropFirst()].joined(separator: "\n")
			for callee in functions where callee.parameters.contains(where: { $0.label == label && $0.type == wrapperType + "?" }) && Self.arguments(ofCallsTo: callee.name, in: body).contains(where: { $0.contains("\(label): \(label)") }) {
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

	/// Renames each call of `source` that passes `nil` for `label` to a call of `target`, and no other call on its line.
	mutating func retargetCalls(of source: String, passingNilFor label: String, to target: String) {
		for index in lines.indices {
			var line = lines[index]
			for call in Self.calls(to: source, in: line).reversed() where call.arguments.contains(where: { $0.contains("\(label): nil") }) {
				line.replaceSubrange(call.name, with: target)
			}
			lines[index] = line
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
	/// the text declares them: the name, then the name with one more underscore each. This assumes what holds today: the
	/// tree claims a function's name where the root's body first declares it, so the functions of one name are numbered
	/// in the order of their declarations. A body that names functions apart another way stays different, and fails.
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

	/// The calls of `name` in `text`: where each names the function, and its arguments, split at their top-level commas.
	private static func calls(to name: String, in text: String) -> [(name: Range<String.Index>, arguments: [String])] {
		referenceRanges(of: name, in: text).compactMap { range in
			guard range.upperBound < text.endIndex, text[range.upperBound] == "(",
			      let close = matchingParenthesis(in: text[...], openedAt: range.upperBound)
			else { return nil }
			return (range, topLevelParts(of: text[text.index(after: range.upperBound)..<close]))
		}
	}

	/// The arguments of every call of `name` in `text`.
	private static func arguments(ofCallsTo name: String, in text: String) -> [String] {
		calls(to: name, in: text).flatMap(\.arguments)
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
