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

/// A loop of builders as one place of the type key's layout: the unit the level emits (every member's function, then every
/// binding, `MockLowering+Loops.swift`), copied as written, binding each member the level binds, declaring each member's
/// function, and reading what its text names from around it. Its first member's path holds it; the other members, and every
/// place beneath a member, are its text.
extension MockLowering.Walk {
	/// Notes the member at `path`, bound under `bindingName`, of the loop being emitted.
	mutating func noteLoopMember(_ generator: ScopeGenerator, path: [Int], bindingName: String?) {
		loopUnit?.members.append((generator, path, bindingName))
	}

	/// Records `unit` as one text place at its first member's path, where its text lists its reads; otherwise its places keep
	/// the reason they have.
	mutating func recordLoopUnit(_ unit: MockLowering.LoopUnit) {
		guard let first = unit.members.first else { return }
		for member in unit.members {
			for path in placePathsInWalkOrder where path.count > member.path.count && Array(path.prefix(member.path.count)) == member.path {
				pathsCoveredByLoopUnits.insert(path)
			}
			if member.path != first.path {
				pathsCoveredByLoopUnits.insert(member.path)
			}
		}
		// Override locals before the functions bind values the text place would have to list.
		guard unit.prelude.isEmpty else {
			unrecordedReasons[first.path] = "loop:prelude"
			return
		}
		// In `.v3Unstable`, the bindings of the members `mock()` is passed a `SafeDIReceived` for, which the level writes before
		// the loop and the loop's text reads.
		let preludes = unit.members.compactMap { member -> MockLowering.PromotedLoopMemberPrelude? in
			guard case let .property(_, property, _, _, _, _) = member.generator.scopeData else { return nil }
			return v3PromotedLoopMemberPreludes[property]
		}
		let preludeNames = preludes.reduce(into: Set<String>()) { $0.formUnion($1.boundNames) }
		for prelude in preludes where !v3PromotedParameterDeclarations.contains(where: { $0.label == prelude.parameter.label }) {
			v3PromotedParameterDeclarations.append(prelude.parameter)
		}
		let lines = preludes.flatMap(\.lines) + unit.lines
		guard let firstLine = lines.first(where: { !$0.allSatisfy(\.isWhitespace) }) else { return }
		let indent = String(firstLine.prefix { $0 == " " || $0 == "\t" })
		let unindented = Self.unindenting(lines, by: indent)
		// The bindings the unit makes at its top, by name, with their types.
		var bindings = [Property]()
		for line in unit.bindings {
			let trimmed = line.drop { $0 == " " || $0 == "\t" }
			guard trimmed.hasPrefix("let ") else { continue }
			let afterLet = trimmed.dropFirst(4)
			let name = String(afterLet.prefix { $0 != ":" && $0 != " " })
			let member = loopMembers.values.first { $0.bindingName == name }
			let type = member.map { $0.rename?.typeDescription ?? $0.typeDescription } ?? .simple(name: "Any")
			bindings.append(Property(label: name, typeDescription: type))
		}
		var outerTypes = [String: TypeDescription]()
		for member in unit.members {
			for (name, type) in publicMockCallOuterTypes(of: member.generator) {
				outerTypes[name] = type
			}
		}
		let boundNames = Set(bindings.map(\.label))
		for name in boundNames {
			outerTypes[name] = nil
		}
		let functionText = Self.unindenting(unit.functions, by: indent).joined(separator: "\n")
		guard let place = MockLowering.textPlace(functionText, outerTypes: outerTypes) else {
			unrecordedReasons[first.path] = "loop:functionText"
			return
		}
		// A name of SafeDI's the text does not declare is a function around it, which the type key may rename or give
		// parameters, or a local a `@Sendable` function around it reads its overrides into, which it may not declare: no
		// read tells either apart, so the loop keeps the walk's body.
		guard !place.reads.contains(where: { $0.label.hasPrefix(ReservedName.builderFunctionNamePrefix) && !preludeNames.contains($0.label) }) else {
			unrecordedReasons[first.path] = "loop:namesFunctionOrLocalAround"
			return
		}
		// The bindings read the functions the unit declares, and the members the unit binds before them.
		let bindingText = Self.unindenting(unit.bindings, by: indent).joined(separator: "\n")
		let bindingTokens = MockLowering.codeTokens(in: bindingText)
		guard !bindingTokens.contains(where: { !$0.isMember && $0.name.hasPrefix(ReservedName.builderFunctionNamePrefix) && !place.declaredFunctionNames.contains($0.name) && !preludeNames.contains($0.name) }) else {
			unrecordedReasons[first.path] = "loop:namesFunctionOrLocalAround"
			return
		}
		var reads = place.reads.filter { !boundNames.contains($0.label) && !preludeNames.contains($0.label) }
		var readNames = Set(reads.map(\.label))
		for prelude in preludes where readNames.insert(prelude.parameter.label).inserted {
			reads.append(MockLowering.valueRead(prelude.parameter.label, outerTypes: [prelude.parameter.label: prelude.parameter.typeDescription]))
		}
		for token in bindingTokens where !token.isMember && !token.isLabel && !MockLowering.keywords.contains(token.name) && !place.declaredFunctionNames.contains(token.name) && !boundNames.contains(token.name) && !preludeNames.contains(token.name) {
			guard MockLowering.namesAValue(token.name, outerTypes: outerTypes), outerTypes[token.name] != nil || token.name.first?.isLowercase == true else { continue }
			if readNames.insert(token.name).inserted {
				reads.append(MockLowering.valueRead(token.name, outerTypes: outerTypes))
			}
		}
		guard let property = bindings.first else {
			unrecordedReasons[first.path] = "loop:noBinding"
			return
		}
		loopUnitRecords[first.path] = .alias(AliasPlaceRecord(
			property: property,
			fulfillingProperty: nil,
			text: unindented.joined(separator: "\n"),
			reads: reads,
			otherBindings: Array(bindings.dropFirst()),
			declaredFunctionNames: place.declaredFunctionNames,
		))
	}

	/// The unit's text, each line without the unit's indent. An element can hold several lines, such as a rebinding
	/// wrapped in `#sourceLocation` directives, so each of its lines is unindented, never only its first.
	private static func unindenting(_ elements: [String], by indent: String) -> [String] {
		elements.map { element in
			element
				.split(separator: "\n", omittingEmptySubsequences: false)
				.map { line in line.hasPrefix(indent) ? String(line.dropFirst(indent.count)) : String(line) }
				.joined(separator: "\n")
		}
	}
}
