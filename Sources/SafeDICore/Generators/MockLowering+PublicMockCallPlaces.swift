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

// The place of a call of another module's public mock that passes builders, as the mock switch lays it out
// (`MockLowering+TypeKeyLayout.swift`): a built place whose function declares the call's fills and names its guard, each
// written as text whose reads are listed, and whose construction hands each argument the value the walk writes, spliced
// from the text it is written as (`ValuePath.spliced`).

extension MockLowering {
	/// An identifier in generated code, and how the code uses it.
	struct CodeToken {
		let name: String
		let range: Range<String.Index>
		/// Whether it follows a `.`: a member, which names nothing in scope.
		let isMember: Bool
		/// Whether a `:` follows it directly: an argument or parameter label, or a declaration's name before its type.
		let isLabel: Bool
		/// Whether a `(` follows it directly.
		let isCalled: Bool
	}

	/// The words of Swift that generated code uses and that name nothing in scope.
	static let keywords: Set<String> = [
		"_", "any", "as", "async", "await", "case", "default", "else", "false", "for", "func", "guard", "if", "in", "init",
		"inout", "is", "let", "nil", "nonisolated", "return", "rethrows", "self", "Self", "some", "switch", "throws", "true",
		"try", "var", "where", "while",
	]

	/// The identifiers of `text` in order, with each use.
	static func codeTokens(in text: String) -> [CodeToken] {
		var tokens = [CodeToken]()
		var index = text.startIndex
		var previous: Character?
		while index < text.endIndex {
			let character = text[index]
			guard character.isLetter || character == "_" || character == "$" else {
				if !character.isWhitespace {
					previous = character
				}
				index = text.index(after: index)
				continue
			}
			var end = text.index(after: index)
			while end < text.endIndex, text[end].isLetter || text[end].isNumber || text[end] == "_" {
				end = text.index(after: end)
			}
			let next = end < text.endIndex ? text[end] : nil
			let afterNext = next == nil ? nil : text.index(after: end) < text.endIndex ? text[text.index(after: end)] : nil
			tokens.append(CodeToken(
				name: String(text[index..<end]),
				range: index..<end,
				isMember: previous == ".",
				isLabel: next == ":" && afterNext != ":",
				isCalled: next == "(",
			))
			previous = text[text.index(before: end)]
			index = end
		}
		return tokens
	}

	/// The names `text` declares for the code after them: after `let`, `var` and `func`, the parameters of each function
	/// it declares, and the parameters of each closure.
	static func declaredNames(in text: String, tokens: [CodeToken]) -> Set<String> {
		var names = Set<String>()
		for (position, token) in tokens.enumerated() where position > 0 && ["let", "var", "func"].contains(tokens[position - 1].name) {
			names.insert(token.name)
		}
		// A function's parameters are the labels between its `(` and the `)` that closes it.
		for (position, token) in tokens.enumerated() where token.name == "func" && position + 1 < tokens.count {
			guard let open = text[tokens[position + 1].range.upperBound...].firstIndex(of: "(") else { continue }
			var depth = 0
			var close = open
			for index in text[open...].indices {
				if text[index] == "(" {
					depth += 1
				} else if text[index] == ")" {
					depth -= 1
				}
				close = index
				guard depth > 0 else { break }
			}
			for parameter in tokens where parameter.isLabel && parameter.range.lowerBound > open && parameter.range.lowerBound < close {
				names.insert(parameter.name)
			}
		}
		// A closure's parameter is the name between its `{` and its `in`: no closure a mock's text holds takes two.
		for open in text.indices where text[open] == "{" {
			var index = text.index(after: open)
			func nextWord() -> Substring {
				while index < text.endIndex, text[index] == " " {
					index = text.index(after: index)
				}
				let start = index
				while index < text.endIndex, text[index].isLetter || text[index].isNumber || text[index] == "_" {
					index = text.index(after: index)
				}
				return text[start..<index]
			}
			let parameter = nextWord()
			if nextWord() == "in" {
				names.insert(String(parameter))
			}
		}
		return names
	}

	/// Whether `name` can name a value in scope: a name that starts lowercase, or one `outerTypes` holds.
	static func namesAValue(_ name: String, outerTypes: [String: TypeDescription]) -> Bool {
		outerTypes[name] != nil || name.first.map { $0.isLowercase || $0 == "_" } == true
	}

	/// A read of the value `name`, of the type `outerTypes` holds for it, which cannot cross into a `@Sendable` function,
	/// unless the place's own function binds it, typed `typeDeclaredInFunction`, which the function never captures.
	static func valueRead(_ name: String, outerTypes: [String: TypeDescription], typeDeclaredInFunction: TypeDescription? = nil) -> PlaceRead {
		PlaceRead(
			argumentLabel: name,
			label: name,
			property: Property(label: name, typeDescription: typeDeclaredInFunction ?? outerTypes[name] ?? .simple(name: "Any")),
			source: .binding(label: name),
			staysOutsideSendableFunctions: typeDeclaredInFunction == nil,
		)
	}

	/// `text`, an argument's value, spliced into the values it reads, the functions of `declaredFunctionNames` it names,
	/// and text; `nil` where it calls a function it does not declare, which keeps the root one per path. A name of
	/// `rootNames`, a parameter of `mock()` no place binds, is read as a root declaration.
	/// A name of `passedArgumentNames` is a read of the parameter it maps to, which the call hands the place's function, and
	/// a name of `typesDeclaredInFunction` a read of a value the place's function binds before its call, of the type it maps to.
	static func splicedValue(of text: String, declaredFunctionNames: Set<String>, rootNames: Set<String>, outerTypes: [String: TypeDescription], passedArgumentNames: [String: String] = [:], typesDeclaredInFunction: [String: TypeDescription] = [:]) -> ValuePath? {
		let tokens = codeTokens(in: text)
		let localNames = declaredNames(in: text, tokens: tokens)
		var segments = [ValueSegment]()
		var cursor = text.startIndex
		// Each call but the last is followed by a segment that is no text, so no two texts are neighbors.
		func appendText(upTo end: String.Index) {
			guard cursor < end else { return }
			segments.append(.text(String(text[cursor..<end])))
		}
		for token in tokens where !token.isMember && !token.isLabel && !keywords.contains(token.name) && !token.name.hasPrefix("$") && !localNames.contains(token.name) {
			if declaredFunctionNames.contains(token.name) {
				appendText(upTo: token.range.lowerBound)
				segments.append(.declaredFunction(token.name))
				cursor = token.range.upperBound
			} else if let parameterName = passedArgumentNames[token.name] {
				appendText(upTo: token.range.lowerBound)
				segments.append(.value(.passedArgument(parameterName)))
				cursor = token.range.upperBound
			} else if rootNames.contains(token.name) {
				appendText(upTo: token.range.lowerBound)
				segments.append(.value(.rootDeclaration(token.name)))
				cursor = token.range.upperBound
			} else if namesAValue(token.name, outerTypes: outerTypes) {
				guard !token.isCalled || outerTypes[token.name] != nil else { return nil }
				appendText(upTo: token.range.lowerBound)
				// A read of a lazy wrapper's instance is one read, which the type key spells from the wrapper it resolves to.
				let rest = text[token.range.upperBound...]
				let instanceSuffixes = [(".\(Dependency.lazilyInstantiatedInstancePropertyName)", false), ("?.\(Dependency.lazilyInstantiatedInstancePropertyName)", true)]
				if let (suffix, throughOptional) = instanceSuffixes.first(where: { suffix, _ in
					rest.hasPrefix(suffix) && !(rest.dropFirst(suffix.count).first.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false)
				}) {
					let declaredType = outerTypes[token.name] ?? .simple(name: "Any")
					let instanceType = declaredType.lazilyInstantiatedInstanceType ?? declaredType
					segments.append(.value(.read(PlaceRead(
						argumentLabel: token.name,
						label: token.name,
						property: Property(label: token.name, typeDescription: throughOptional ? .optional(instanceType.unwrapped) : instanceType),
						source: .lazyInstance(label: token.name, throughOptional: throughOptional),
						staysOutsideSendableFunctions: true,
					))))
					cursor = text.index(token.range.upperBound, offsetBy: suffix.count)
				} else {
					segments.append(.value(.read(valueRead(token.name, outerTypes: outerTypes, typeDeclaredInFunction: typesDeclaredInFunction[token.name]))))
					cursor = token.range.upperBound
				}
			}
		}
		appendText(upTo: text.endIndex)
		return .spliced(segments)
	}

	/// What a place written as `text` reads, and the functions it declares at its top, or `nil` where it binds a value at
	/// its top or calls a function of SafeDI’s it does not declare. Every name it uses that is not a member, a label, or a name it
	/// declares is a read, as is every name `outerTypes` holds, even one it declares too: a read too many is only a
	/// declaration the type key must resolve as the walk does.
	static func textPlace(_ text: String, outerTypes: [String: TypeDescription]) -> (reads: [PlaceRead], declaredFunctionNames: [String])? {
		let lines = text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).map(Substring.init)
		var declaredFunctionNames = [String]()
		for line in lines where !(line.first?.isWhitespace ?? true) {
			let words = line.utf8.split(separator: UInt8(ascii: " ")).map(Substring.init)
			guard !words.contains(where: { $0 == "let" || $0 == "var" }) else { return nil }
			if let funcIndex = words.firstIndex(of: "func"), funcIndex + 1 < words.count {
				declaredFunctionNames.append(String(words[funcIndex + 1].prefix { $0 != "(" }))
			}
		}
		// Comments read nothing.
		let code = lines.map { line in line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? String(line) }.joined(separator: "\n")
		let tokens = codeTokens(in: code)
		let localNames = declaredNames(in: code, tokens: tokens)
		var reads = [PlaceRead]()
		var readNames = Set<String>()
		for token in tokens where !token.isMember && !token.isLabel && !keywords.contains(token.name) && !token.name.hasPrefix("$") && !declaredFunctionNames.contains(token.name) {
			let isOuter = outerTypes[token.name] != nil
			guard isOuter || !localNames.contains(token.name), namesAValue(token.name, outerTypes: outerTypes) else { continue }
			// A function the walk declares is named with SafeDI’s reserved prefix; any other name called is a closure the
			// text reads, such as a builder `mock()` takes.
			guard !token.isCalled || isOuter || !token.name.hasPrefix(ReservedName.builderFunctionNamePrefix) else { return nil }
			if readNames.insert(token.name).inserted {
				reads.append(valueRead(token.name, outerTypes: outerTypes))
			}
		}
		return (reads, declaredFunctionNames)
	}
}

extension MockLowering {
	/// The override a call of another module's public mock reads in its own `@Sendable` builder function, which the walk
	/// reads into `localName` before the function, from `read`, of `type`.
	struct BoundOverride {
		let localName: String
		let read: ValuePath
		let type: TypeDescription
	}

	/// The plan node of a call of another module's public mock the mock switch lays out: one per generator and text, so
	/// places that share a node are written alike.
	struct PublicMockCallPlanNodeKey: Hashable {
		let generator: ObjectIdentifier
		let text: String
	}
}

extension MockLowering.Walk {
	/// The names a call of another module's public mock at `generator` and its fills may read from around the call, with
	/// their types: what its tree receives, the names the mock binds them apart under, the wrappers it binds, and the
	/// builders `mock()` takes.
	/// The parameters of `mock()` a call of another module's public mock may read that no place binds: its overrides, and
	/// the builders it takes.
	var publicMockCallRootNames: Set<String> {
		let holeBuilders = filledCallBuilders.fillPlaceBindings.holeBuildersByCall.values.flatMap(\.values) + filledCallBuilders.fillPlaceBindings.holeBuildersByInlinePlace.values
		return Set([ReservedName.mockOverridesParameterName] + holeBuilders.map(\.name) + filledCallBuilders.passedUpBuilderNames.values)
	}

	/// Where the tree receives one label as two types, or the mock binds one name under two types, as its forms of one
	/// label seen from two receivers can, the name takes the type spelled first in sorted order, never the one a set's or
	/// dictionary's order lists last; the type key checks each read against the declaration it resolves to, and keeps the
	/// walk's body where the type is not the declaration's.
	func publicMockCallOuterTypes(of generator: ScopeGenerator) -> [String: TypeDescription] {
		var outerTypes = [String: TypeDescription]()
		func declare(_ name: String, as type: TypeDescription) {
			guard let existing = outerTypes[name], existing.asSource < type.asSource else {
				outerTypes[name] = type
				return
			}
		}
		for property in generator.receivedProperties {
			declare(property.label, as: property.typeDescription)
		}
		var boundTypes = [String: TypeDescription]()
		for namesByType in [renames, lazilyInstantiatedNames].flatMap(\.values) {
			for (type, name) in namesByType {
				guard let existing = boundTypes[name], existing.asSource < type.asSource else {
					boundTypes[name] = type
					continue
				}
			}
		}
		outerTypes.merge(boundTypes) { _, bound in bound }
		for (property, name) in filledCallBuilders.passedUpBuilderNames {
			outerTypes[name] = property.typeDescription.strippingEscaping
		}
		let holeBuilders = filledCallBuilders.fillPlaceBindings.holeBuildersByCall.values.flatMap(\.values) + filledCallBuilders.fillPlaceBindings.holeBuildersByInlinePlace.values
		for holeBuilder in holeBuilders where outerTypes[holeBuilder.name] == nil {
			outerTypes[holeBuilder.name] = .simple(name: "Any")
		}
		return outerTypes
	}

	/// Records the call of another module's public mock the walk lowered at the current path as a built place with a
	/// function of its own: `bodyLines`, the function's statements before its call, unindented, are its fills, then
	/// `guardLine`, then the values it binds again (`let <label>: <type> = <name>`), each written as text; the call hands
	/// each argument the value `argumentTexts` writes, spliced, or is `constructionText`, spliced, where set. Returns why the
	/// call keeps the walk's body instead, or `nil`.
	mutating func recordPublicMockCallPlace(
		of generator: ScopeGenerator,
		property: Property,
		instantiable: Instantiable,
		erasedToConcreteExistential: Bool,
		forwardedProperties: [Property],
		functionName: String,
		calledFunctionName: String,
		constructionText: String?,
		boundOverride: MockLowering.BoundOverride?,
		argumentTexts: [(argument: Initializer.Argument, value: String)],
		overridesValue: String?,
		bodyLines: [String],
		guardLine: String,
	) -> String? {
		guard generator.cycleParameters.isEmpty else { return "publicMockCall:cycleParameters" }
		// An erased call's text erases it, where the type key would erase it again.
		guard constructionText == nil || !erasedToConcreteExistential else { return "publicMockCall:erasedOverrideBuilders" }
		guard let guardIndex = bodyLines.lastIndex(of: guardLine) else { return "publicMockCall:noGuard" }
		let outerTypes = publicMockCallOuterTypes(of: generator)
		let rootNames = publicMockCallRootNames
		let passedArgumentNames = boundOverride.map { [$0.localName: ReservedName.configurationBuilderPropertyName] } ?? [:]
		func alias(_ text: String, label: String, type: TypeDescription, reads: [PlaceRead], declaredFunctionNames: [String] = []) -> GeneratedCode {
			.place(PlacePlan(code: .text(text), record: .alias(AliasPlaceRecord(property: Property(label: label, typeDescription: type), fulfillingProperty: nil, text: text, reads: reads, declaredFunctionNames: declaredFunctionNames))))
		}
		var children = [GeneratedCode]()
		var declaredFunctionNames = Set<String>()
		let fillText = bodyLines[..<guardIndex].joined(separator: "\n")
		if !fillText.isEmpty {
			guard let place = MockLowering.textPlace(fillText, outerTypes: outerTypes) else { return "publicMockCall:fillText" }
			declaredFunctionNames.formUnion(place.declaredFunctionNames)
			children.append(alias(fillText, label: "\(functionName)_fills", type: .simple(name: "Void"), reads: place.reads, declaredFunctionNames: place.declaredFunctionNames))
		}
		children.append(alias(guardLine, label: "\(functionName)_guard", type: .simple(name: "Void"), reads: []))
		var typesDeclaredInFunction = [String: TypeDescription]()
		for line in bodyLines[(guardIndex + 1)...] {
			guard line.hasPrefix("let "),
			      let colon = line.range(of: ": "),
			      let equals = line.range(of: " = ", range: colon.upperBound..<line.endIndex),
			      let place = MockLowering.textPlace(String(line[equals.upperBound...]), outerTypes: outerTypes)
			else { return "publicMockCall:rebinding" }
			let label = String(line[line.index(line.startIndex, offsetBy: 4)..<colon.lowerBound])
			let type = TypeDescription.simple(name: String(line[colon.upperBound..<equals.lowerBound]))
			children.append(alias(line, label: label, type: type, reads: place.reads))
			typesDeclaredInFunction[label] = type
		}
		var arguments = [PlaceRead]()
		var argumentValues = [Int: ValuePath]()
		var constructionValue: ValuePath?
		if let constructionText {
			guard let spliced = MockLowering.splicedValue(of: constructionText, declaredFunctionNames: declaredFunctionNames, rootNames: rootNames, outerTypes: outerTypes, passedArgumentNames: passedArgumentNames, typesDeclaredInFunction: typesDeclaredInFunction) else { return "publicMockCall:constructionCallsFunction" }
			constructionValue = spliced
		}
		var values = argumentTexts.map { (label: $0.argument.label, innerLabel: $0.argument.innerLabel, type: $0.argument.typeDescription, value: $0.value) }
		if let overridesValue {
			values.append((label: ReservedName.mockOverridesParameterName, innerLabel: ReservedName.mockOverridesParameterName, type: .simple(name: "Any"), value: overridesValue))
		}
		for value in values where constructionValue == nil {
			guard value.label != "_" else { return "publicMockCall:unlabeledArgument" }
			guard let spliced = MockLowering.splicedValue(of: value.value, declaredFunctionNames: declaredFunctionNames, rootNames: rootNames, outerTypes: outerTypes, passedArgumentNames: passedArgumentNames, typesDeclaredInFunction: typesDeclaredInFunction) else { return "publicMockCall:argumentCallsFunction" }
			argumentValues[arguments.count] = spliced
			arguments.append(PlaceRead(argumentLabel: value.label, label: value.innerLabel, property: Property(label: value.innerLabel, typeDescription: value.type), source: .binding(label: value.innerLabel)))
		}
		let nodeKey = MockLowering.PublicMockCallPlanNodeKey(generator: ObjectIdentifier(generator), text: (bodyLines + values.map { "\($0.label): \($0.value)" } + [constructionText ?? ""]).joined(separator: "\n"))
		let node = publicMockCallPlanNodes[nodeKey] ?? PlanNode()
		publicMockCallPlanNodes[nodeKey] = node
		var record = BuiltPlaceRecord(
			property: property,
			isErased: erasedToConcreteExistential,
			concreteType: instantiable.concreteInstantiable,
			isExtension: false,
			target: .mock(instantiable.concreteInstantiable, name: calledFunctionName),
			arguments: arguments,
			forwardedProperties: forwardedProperties,
			cycleParameters: [],
			callCycleArguments: [],
			functionName: functionName,
			isSendable: generator.buildsInSendableFunction,
			typesDeclaredEscaping: generator.typesDeclaredEscaping,
			lineEnd: "",
			hasFunction: true,
			children: children,
			node: node,
		)
		record.argumentValues = argumentValues
		record.constructionValue = constructionValue.map { ConstructionValue(value: $0, resultWrapper: nil) }
		if let boundOverride {
			// `mock()`'s overrides stay outside `@Sendable` functions; the local bound from them holds a `@Sendable` closure.
			record.passedArguments = [PassedArgument(parameterName: ReservedName.configurationBuilderPropertyName, type: boundOverride.type, value: boundOverride.read, staysOutsideSendableFunctions: true, bindsBeforeCall: true)]
		}
		builtRecords[childIndexPath] = .built(record)
		return nil
	}
}
