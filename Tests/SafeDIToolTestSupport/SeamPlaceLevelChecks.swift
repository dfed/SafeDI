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
import SafeDICore
import Testing

extension SeamPlaceLevels {
	/// A description of each place whose levels, read nearest first, do not hold exactly the fields of its scope struct and
	/// the declarations it carries no field of: each label is decided by the nearest level that declares it, a field where
	/// that level binds it before the next property on the path, and the labels are in the order the levels bind them.
	var pathStructMismatches: [String] {
		places.compactMap { place in
			struct Decision {
				let outerLevelIndex: Int
				let position: Int
				let declaration: Level.Declaration
			}
			var decisionsByLabel = [String: Decision]()
			for (nearestLevelIndex, level) in place.levels.enumerated() {
				// Within a level, a later declaration of a label is the nearer one.
				for (position, declaration) in level.declarations.enumerated().reversed() where decisionsByLabel[declaration.property.label] == nil {
					decisionsByLabel[declaration.property.label] = Decision(outerLevelIndex: place.levels.count - 1 - nearestLevelIndex, position: position, declaration: declaration)
				}
			}
			let decisions = decisionsByLabel.values.sorted { ($0.outerLevelIndex, $0.position) < ($1.outerLevelIndex, $1.position) }
			let fields = decisions.filter(\.declaration.isBoundBeforeNextProperty).map(\.declaration.property)
			let uncarriedProperties = decisions.filter { !$0.declaration.isBoundBeforeNextProperty }.map(\.declaration.property)
			guard fields != place.fields || uncarriedProperties != place.uncarriedProperties else { return nil }
			return "The levels of the place `\(Self.pathDescription(of: place))` of `\(seamType.asSource)` hold the fields \(Self.listDescription(of: fields)) and leave \(Self.listDescription(of: uncarriedProperties)) uncarried, but its scope struct holds \(Self.listDescription(of: place.fields)) and leaves \(Self.listDescription(of: place.uncarriedProperties)) uncarried."
		}
	}

	/// A description of each level that one build of its type gives with other fields than another build of the same type
	/// does: the level a type holds before a property, or the seam's root's level, is the same on every path, inside a fill
	/// too, whose tree starts its children in the order of its types as any other. The parameters of a builder function a
	/// lazy cycle closes on, and the instantiators a loop member's builder function wraps again, are left out
	/// (`Level.fieldsOfType`): facts of the function, which another build of the type need not take or make.
	func levelDisagreements() -> [String] {
		struct Key: Hashable {
			let builtType: TypeDescription
			let nextProperty: Property
			let isSeamRoot: Bool
		}
		var firstFieldsByKey = [Key: (fields: [Property], place: Place)]()
		var disagreements = [String]()
		for place in places {
			for (index, level) in place.levels.enumerated() {
				guard let builtType = level.builtType, let nextProperty = level.nextProperty else { continue }
				let key = Key(builtType: builtType, nextProperty: nextProperty, isSeamRoot: index == place.levels.count - 1)
				if let (firstFields, firstPlace) = firstFieldsByKey[key] {
					guard firstFields != level.fieldsOfType else { continue }
					disagreements.append("`\(builtType.asSource)` holds \(Self.listDescription(of: firstFields)) before `\(nextProperty.asSource)` on the path to the place `\(Self.pathDescription(of: firstPlace))` of `\(seamType.asSource)`, but \(Self.listDescription(of: level.fieldsOfType)) on the path to the place `\(Self.pathDescription(of: place))`.")
				} else {
					firstFieldsByKey[key] = (level.fieldsOfType, place)
				}
			}
		}
		return disagreements
	}

	/// An observer that records an issue for each place whose levels do not hold its fields (`pathStructMismatches`), then
	/// hands the levels to `enclosingObserver`, the observer the caller set, if any.
	static func checkingPathStructs(handingOn enclosingObserver: (@Sendable (SeamPlaceLevels) -> Void)?) -> @Sendable (SeamPlaceLevels) -> Void {
		{ placeLevels in
			for mismatch in placeLevels.pathStructMismatches {
				Issue.record(Comment(rawValue: mismatch))
			}
			enclosingObserver?(placeLevels)
		}
	}

	private static func pathDescription(of place: Place) -> String {
		place.sitePath.map(\.label).joined(separator: ".")
	}

	private static func listDescription(of properties: [Property]) -> String {
		"[" + properties.map(\.asSource).joined(separator: ", ") + "]"
	}
}

/// What `operation` returns, with each distinct level disagreement (`SeamPlaceLevels.levelDisagreements`) of the holes
/// of every seam the tool computes while it runs, in the order the tool first computes them.
func collectingPlaceLevelDisagreements<Result>(during operation: () async throws -> Result) async rethrows -> (result: Result, disagreements: [String]) {
	let (stream, continuation) = AsyncStream.makeStream(of: [String].self)
	let enclosingObserver = SeamPlaceLevels.observer
	let result = try await SeamPlaceLevels.$observer.withValue({ placeLevels in
		continuation.yield(placeLevels.levelDisagreements())
		enclosingObserver?(placeLevels)
	}) {
		try await operation()
	}
	continuation.finish()
	var disagreements = [String]()
	for await computedDisagreements in stream {
		for disagreement in computedDisagreements where !disagreements.contains(disagreement) {
			disagreements.append(disagreement)
		}
	}
	return (result, disagreements)
}

/// What `operation` returns, with each key a root reaches root functions of with two texts
/// (`RootFunctionHoisting.observer`), in the order the tool first reaches them: each root's functions of one key must have
/// one text, which the generator never compares.
func collectingRootFunctionKeyDisagreements<Result>(during operation: () async throws -> Result) async rethrows -> (result: Result, disagreements: [String]) {
	let (stream, continuation) = AsyncStream.makeStream(of: [RootFunctionHoisting.Occurrence].self)
	let enclosingObserver = RootFunctionHoisting.observer
	let result = try await RootFunctionHoisting.$observer.withValue({ occurrences in
		continuation.yield(occurrences)
		enclosingObserver?(occurrences)
	}) {
		try await operation()
	}
	continuation.finish()
	var disagreements = [String]()
	for await occurrences in stream {
		var textByKey = [RootFunctionKey: RootFunctionHoisting.Occurrence]()
		for occurrence in occurrences {
			guard let first = textByKey[occurrence.key] else {
				textByKey[occurrence.key] = occurrence
				continue
			}
			let disagreement = "Root functions \(first.name) and \(occurrence.name) share a key with different text:\n\(first.text)\n---\n\(occurrence.text)"
			if first.text != occurrence.text, !disagreements.contains(disagreement) {
				disagreements.append(disagreement)
			}
		}
	}
	return (result, disagreements)
}

/// What `operation` returns, with each root function a root declares at its top that reads a name of the root's code
/// (`RootFunctionHoisting.hoistedDeclarationsObserver`), in the order the tool declares them: a function declared at the
/// root's top captures nothing of the code around the call that wrote it, so every name it reads is its own, another root
/// function the root declares there, or a type's. A name of the root's code read there resolves to the root's
/// declaration, which can be another declaration or another form of the label than the one at the call.
func collectingHoistedRootFunctionCaptures<Result>(during operation: () async throws -> Result) async rethrows -> (result: Result, captures: [String]) {
	let (stream, continuation) = AsyncStream.makeStream(of: (declarations: [String], declaredNames: Set<String>).self)
	let enclosingObserver = RootFunctionHoisting.hoistedDeclarationsObserver
	let result = try await RootFunctionHoisting.$hoistedDeclarationsObserver.withValue({ declarations, declaredNames in
		continuation.yield((declarations, declaredNames))
		enclosingObserver?(declarations, declaredNames)
	}) {
		try await operation()
	}
	continuation.finish()
	var captures = [String]()
	for await (declarations, declaredNames) in stream {
		for declaration in declarations {
			let captured = HoistedDeclarationNames(declaration).freeValueNames.subtracting(declaredNames).sorted()
			let capture = "A root function the root declares at its top reads \(captured.joined(separator: ", ")) of the root's code:\n\(declaration)"
			if !captured.isEmpty, !captures.contains(capture) {
				captures.append(capture)
			}
		}
	}
	return (result, captures)
}

/// The names a function's text reads and the names it declares, read from its tokens: what the generator writes of a root
/// function. A name read is an identifier that starts with a lowercase letter or an underscore, is no keyword, follows no
/// `.`, `@` or `#`, and precedes no `:` (an argument label, or a parameter's name). A name declared is one a `let`, `var`
/// or `func` introduces, a parameter of a function it declares, or a parameter of a closure it writes. Where a name is
/// declared is not tracked, so a name declared anywhere in the text is never read as the root's.
struct HoistedDeclarationNames {
	init(_ text: String) {
		let tokens = Self.tokens(of: text)
		var read = Set<String>()
		var declared = Set<String>()
		var index = 0
		while index < tokens.count {
			let token = tokens[index]
			let previous = index > 0 ? tokens[index - 1] : ""
			let next = index + 1 < tokens.count ? tokens[index + 1] : ""
			if token == "let" || token == "var" || token == "func", Self.isIdentifier(next) {
				declared.insert(next)
				if token == "func" {
					declared.formUnion(Self.parameterNames(in: tokens, afterNameAt: index + 1))
				}
			} else if token == "{" {
				declared.formUnion(Self.closureParameterNames(in: tokens, afterBraceAt: index))
			} else if Self.isIdentifier(token),
			          let first = token.unicodeScalars.first,
			          first == "_" || CharacterSet.lowercaseLetters.contains(first),
			          !Self.keywords.contains(token),
			          previous != ".", previous != "@", previous != "#",
			          next != ":"
			{
				read.insert(token)
			}
			index += 1
		}
		freeValueNames = read.subtracting(declared)
	}

	/// The names the text reads that it does not declare.
	let freeValueNames: Set<String>

	private static let keywords: Set<String> = ["_", "any", "as", "async", "await", "case", "catch", "default", "do", "else", "false", "for", "func", "guard", "if", "in", "init", "inout", "is", "let", "nil", "nonisolated", "repeat", "return", "rethrows", "self", "some", "super", "switch", "throw", "throws", "true", "try", "var", "where", "while"]

	/// The text's tokens, without its string literals and comments: identifiers, `$0`-style names, and each other
	/// character that is not whitespace.
	private static func tokens(of text: String) -> [String] {
		let withoutLiterals = text
			.replacingOccurrences(of: #""(?:[^"\\\n]|\\.)*""#, with: "\"\"", options: .regularExpression)
			.replacingOccurrences(of: #"//[^\n]*"#, with: "", options: .regularExpression)
		var tokens = [String]()
		var current = ""
		for character in withoutLiterals {
			if character.isLetter || character.isNumber || character == "_" || character == "$" {
				current.append(character)
				continue
			}
			if !current.isEmpty {
				tokens.append(current)
				current = ""
			}
			if !character.isWhitespace {
				tokens.append(String(character))
			}
		}
		if !current.isEmpty {
			tokens.append(current)
		}
		return tokens
	}

	private static func isIdentifier(_ token: String) -> Bool {
		guard let first = token.first else { return false }
		return (first.isLetter || first == "_") && !keywords.contains(token)
	}

	/// The names of the parameters of the function whose name is at `nameIndex`: in each parameter of its list, the
	/// identifier before the `:`.
	private static func parameterNames(in tokens: [String], afterNameAt nameIndex: Int) -> Set<String> {
		var names = Set<String>()
		var index = nameIndex + 1
		guard index < tokens.count, tokens[index] == "(" else { return names }
		var depth = 0
		var lastIdentifier: String?
		var expectsName = true
		while index < tokens.count {
			let token = tokens[index]
			switch token {
			case "(", "<", "[":
				depth += 1
			case ")", ">", "]":
				depth -= 1
				if depth == 0 {
					return names
				}
			case ",":
				if depth == 1 {
					expectsName = true
				}
			case ":":
				if depth == 1, expectsName, let lastIdentifier {
					names.insert(lastIdentifier)
					expectsName = false
				}
			default:
				lastIdentifier = token
			}
			index += 1
		}
		return names
	}

	/// The names a closure whose `{` is at `braceIndex` binds before its `in`: those of its capture list, written
	/// `[a = b, weak c]`, and its parameters, written `a, b`; or none.
	private static func closureParameterNames(in tokens: [String], afterBraceAt braceIndex: Int) -> Set<String> {
		var names = Set<String>()
		var parametersStart = braceIndex + 1
		if parametersStart < tokens.count, tokens[parametersStart] == "[" {
			var depth = 0
			var index = parametersStart
			while index < tokens.count {
				let token = tokens[index]
				if token == "[" || token == "(" {
					depth += 1
				} else if token == "]" || token == ")" {
					depth -= 1
				} else if depth == 1, isIdentifier(token), index + 1 < tokens.count, ["=", ",", "]"].contains(tokens[index + 1]), index == parametersStart + 1 || [",", "weak", "unowned"].contains(tokens[index - 1]) {
					names.insert(token)
				}
				index += 1
				if depth == 0 {
					break
				}
			}
			parametersStart = index
		}
		guard parametersStart < tokens.count else { return [] }
		for token in tokens[parametersStart...] {
			switch token {
			case "in":
				return names
			case ",":
				break
			default:
				guard isIdentifier(token) || token == "_" else { return [] }
				names.insert(token)
			}
		}
		return []
	}
}
