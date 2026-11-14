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

/// The scope enums of holes the tool generates, nested by type, read from the syntax of the generated files: each enum a
/// seam's (or a public mock's) extension declares whose name begins `SafeDIScope_`, `SafeDISendableScope_` or a mock's
/// `SafeDIMockScope_` and `SafeDISendableMockScope_`, each enum nested in one (`<Stem>_Scope`), their cases, and the
/// structs nested in them (`<label>_Values`) with their stored properties.
///
/// The contract read is the design's section 2 ("Nest a hole's scope by type"): one root enum per hole type in the seam's
/// extension, one nested enum per type that holds a place, named after the type as the seam's module spells it with
/// `_Scope` appended (and `_` while a name collides), a case per property that leads to a place, named by the property's
/// label (`p_Sendable` for one that leads to a further `@Sendable` function, `<call>_<builder>` for a place inside a
/// fill), whose payload is the level's `<label>_Values` struct, then a forwarded value or the nested enum of the type the
/// property builds; an inner seam's wrapping case holds that seam's root enum alone. The oracles below read it only where
/// the generator nests every scope of the graph by type (`GraphFuzzerToolRuns.nestsEveryScopeByType`).
struct GraphFuzzerScopeDeclarations {
	/// The scope enums and value structs every file of `generatedFiles` declares, in the order of the files' names.
	init(generatedFiles: [String: String]) {
		var enums = [ScopeEnum]()
		var valuesStructs = [ValuesStruct]()
		for (_, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) {
			let collector = ScopeEnumCollector(viewMode: .sourceAccurate)
			collector.walk(Parser.parse(source: contents))
			enums += collector.enums
			valuesStructs += collector.valuesStructs
		}
		self.enums = enums
		self.valuesStructs = valuesStructs
	}

	/// A scope enum: a seam's root enum, or an enum nested in one.
	struct ScopeEnum: Equatable {
		/// The type whose extension declares the root enum: the seam, or the mocked type.
		let extendedType: String
		/// The enum's name and those of the enums it is nested in, from the root enum.
		let path: [String]
		let cases: [ScopeCase]

		var isRoot: Bool {
			path.count == 1
		}

		/// Whether the enum is a public mock's: its root enum is a `SafeDIMockScope_…` or `SafeDISendableMockScope_…`.
		var isMockScope: Bool {
			(path.first ?? "").contains("MockScope_")
		}

		var qualifiedName: String {
			([extendedType] + path).joined(separator: ".")
		}
	}

	/// A case of a scope enum.
	struct ScopeCase: Equatable {
		let label: String
		/// The type of each associated value, as written.
		let payload: [String]

		/// Whether the case holds a seam's root enum, which the type qualifies: an inner seam's wrapping case, the seam's own
		/// where its tree calls it again, or a place inside a fill, which holds the filled seam's enum.
		func wrapsAnotherSeamsEnum(extendedType: String) -> Bool {
			payload.contains { type in
				ScopeEnumReference(type, extendedType: extendedType)?.isOwn == false
			}
		}

		/// The path of the nested enum of the extended type the case holds, from the root enum, or `nil`.
		func nestedEnumPath(extendedType: String) -> [String]? {
			for type in payload {
				if let reference = ScopeEnumReference(type, extendedType: extendedType), reference.isOwn, reference.path.count > 1 {
					return reference.path
				}
			}
			return nil
		}
	}

	/// A struct nested in a scope enum, with its stored properties.
	struct ValuesStruct: Equatable {
		let extendedType: String
		let path: [String]
		/// Each stored property, as `<access> <label>: <type>`.
		let fields: [String]
	}

	let enums: [ScopeEnum]
	let valuesStructs: [ValuesStruct]

	/// The enums of seams' holes, which the case oracles judge: a public mock's enums (`SafeDIMockScope_…`) nest by type in
	/// a pull request of their own, after the seams', so they are left to the public mock corpus's oracles.
	private var seamEnums: [ScopeEnum] {
		enums.filter { !$0.isMockScope }
	}

	/// Every enum, case, struct and field, each one line, which a hand-written caller or helper can spell.
	var entries: Set<String> {
		var entries = Set<String>()
		for scopeEnum in enums {
			entries.insert("enum \(scopeEnum.qualifiedName)")
			for scopeCase in scopeEnum.cases {
				entries.insert("case \(scopeEnum.qualifiedName).\(scopeCase.label)" + (scopeCase.payload.isEmpty ? "" : "(\(scopeCase.payload.joined(separator: ", ")))"))
			}
		}
		for valuesStruct in valuesStructs {
			let qualifiedName = ([valuesStruct.extendedType] + valuesStruct.path).joined(separator: ".")
			entries.insert("struct \(qualifiedName)")
			for field in valuesStruct.fields {
				entries.insert("field \(qualifiedName): \(field)")
			}
		}
		return entries
	}

	// MARK: Oracles

	/// A description of each enum, case, struct or field that a second path to a shared type, `typeName`'s property
	/// `label`, adds to the scope enums of the graph without it, `withoutSecondPath`, or removes from them, besides the case
	/// for the property itself in `typeName`'s enum and its values struct: a second path to a type that holds a place adds
	/// nothing (the design's section 2.10), since every enum, case and level is a fact of a type.
	func secondPathChanges(comparedWith withoutSecondPath: GraphFuzzerScopeDeclarations, typeName: String, label: String) -> [String] {
		let entries = entries
		let entriesWithoutPath = withoutSecondPath.entries
		let ownEntry = Self.expression(#"\.\#(NSRegularExpression.escapedPattern(for: Self.stem(of: typeName)))_Scope_*\.\#(NSRegularExpression.escapedPattern(for: label))(?:\(|_Values(?:$|[.:])|$)"#)
		var changes = [String]()
		for entry in entriesWithoutPath.subtracting(entries).sorted() {
			changes.append("The second path removes `\(entry)`.")
		}
		for entry in entries.subtracting(entriesWithoutPath).sorted() where !Self.matches(ownEntry, entry) {
			changes.append("The second path adds `\(entry)`.")
		}
		return changes
	}

	/// A description of each case a place's path produces that no scope enum declares: the root enum of the place's seam
	/// for the seam root's property, and the enum of the type that binds a level for its property, a case for `p` being
	/// `p` or, in the `@Sendable` enum, `p_Sendable` (the design's section 2.1: every case any path can produce exists).
	/// The places of a public mock's tree, whose type's extension declares a mock's scope enums and none of a seam's, are
	/// left to the public mock corpus.
	func undeclaredProducedCases(of facts: GraphFuzzerPlaceFacts) -> [String] {
		let mockedTypes = Set(enums.filter(\.isMockScope).map(\.extendedType)).subtracting(seamEnums.map(\.extendedType))
		var descriptions = [String]()
		for producedCase in facts.producedCases.sorted() where !mockedTypes.contains(producedCase.holder.seamType) {
			let holder = producedCase.holder
			let isDeclared = enums(of: holder).contains { scopeEnum in
				scopeEnum.cases.contains { $0.label == producedCase.label || $0.label == producedCase.label + "_Sendable" }
			}
			if !isDeclared {
				descriptions.append("A place's path produces the case `\(producedCase.label)` of \(Self.description(of: holder)), which no scope enum declares.")
			}
		}
		return descriptions
	}

	/// A description of each enum no case holds, each enum no place's path builds the type of, and each case of the extended
	/// type's own that no
	/// place's path produces (the design's section 2.1: in a tree without a tangle of cycles, every case exists only where
	/// some path produces it). A case that holds another seam's enum, an inner seam's wrapping case or a place inside a
	/// fill, is not its own, and neither is a case whose nested enum holds no case of its own: the places an inner seam
	/// passes up have no levels (`GraphFuzzerPlaceFacts`), and the Seams PR decides whether a place passed up counts as
	/// holding one. Only the root enums, and the enums an own case of a judged enum holds, are judged: an enum only a place
	/// inside a fill reaches describes a type of the fill's tree, which has no levels here. Judge it only on a graph
	/// without a tangle of cycles, which can keep a case no run produces (question 3 of the design, ruled acceptable).
	func unproducedDeclaredCases(of facts: GraphFuzzerPlaceFacts) -> [String] {
		let ownCaseLabelsByEnum = ownCaseLabelsByEnum()
		// The enums reached from a root enum through own cases.
		var judgedEnumNames = Set(seamEnums.filter(\.isRoot).map(\.qualifiedName))
		var enumsToVisit = seamEnums.filter(\.isRoot)
		while let scopeEnum = enumsToVisit.popLast() {
			for scopeCase in scopeEnum.cases where ownCaseLabelsByEnum[scopeEnum.qualifiedName, default: []].contains(scopeCase.label) {
				guard let nestedPath = scopeCase.nestedEnumPath(extendedType: scopeEnum.extendedType) else { continue }
				let nestedName = ([scopeEnum.extendedType] + nestedPath).joined(separator: ".")
				if judgedEnumNames.insert(nestedName).inserted, let nestedEnum = seamEnums.first(where: { $0.qualifiedName == nestedName }) {
					enumsToVisit.append(nestedEnum)
				}
			}
		}
		// The enums some case holds, its own or not.
		let heldEnumNames = Set(seamEnums.flatMap { scopeEnum in
			scopeEnum.cases.compactMap { $0.nestedEnumPath(extendedType: scopeEnum.extendedType).map { ([scopeEnum.extendedType] + $0).joined(separator: ".") } }
		})
		var descriptions = [String]()
		for scopeEnum in seamEnums where (!scopeEnum.isRoot && !heldEnumNames.contains(scopeEnum.qualifiedName)) || judgedEnumNames.contains(scopeEnum.qualifiedName) {
			guard scopeEnum.isRoot || heldEnumNames.contains(scopeEnum.qualifiedName) else {
				descriptions.append("No case holds `\(scopeEnum.qualifiedName)`.")
				continue
			}
			guard let holder = holder(of: scopeEnum, in: facts) else {
				descriptions.append("`\(scopeEnum.qualifiedName)` is the scope enum of no type a place's path builds.")
				continue
			}
			for scopeCase in scopeEnum.cases where ownCaseLabelsByEnum[scopeEnum.qualifiedName, default: []].contains(scopeCase.label) {
				let label = scopeCase.label.hasSuffix("_Sendable") ? String(scopeCase.label.dropLast("_Sendable".count)) : scopeCase.label
				if !facts.producedCases.contains(GraphFuzzerPlaceFacts.ProducedCase(holder: holder, label: label)) {
					descriptions.append("`\(scopeEnum.qualifiedName)` declares the case `\(scopeCase.label)`, which no place's path produces.")
				}
			}
		}
		return descriptions
	}

	/// A description of each case of a scope enum whose label names no property of the type the enum describes – `p`,
	/// `p_Sendable`, or, for a place inside a fill, `p_<builder>` for a property `p` the type declares – so that no enum
	/// holds more cases than its type has properties, twice over with `@Sendable` functions, however many paths reach the
	/// type (the design's section 2.9: no generated switch grows with anything but the size of one declaration). An enum
	/// whose type no place's path builds is left to `unproducedDeclaredCases(of:)`.
	func casesNamingNoPropertyOfTheirType(of facts: GraphFuzzerPlaceFacts) -> [String] {
		var descriptions = [String]()
		for scopeEnum in seamEnums {
			guard let holder = holder(of: scopeEnum, in: facts) else { continue }
			let declaredLabels = facts.declaredLabels[holder, default: []]
			for scopeCase in scopeEnum.cases {
				let namesProperty = declaredLabels.contains(scopeCase.label)
					|| scopeCase.label.hasSuffix("_Sendable") && declaredLabels.contains(String(scopeCase.label.dropLast("_Sendable".count)))
					|| scopeCase.wrapsAnotherSeamsEnum(extendedType: scopeEnum.extendedType) && declaredLabels.contains { scopeCase.label.hasPrefix($0 + "_") }
				if !namesProperty {
					descriptions.append("`\(scopeEnum.qualifiedName)` declares the case `\(scopeCase.label)`, which names no property of \(Self.description(of: holder)).")
				}
			}
		}
		return descriptions
	}

	// MARK: Private

	/// The enums that describe `holder`: its seam's root enums for the seam root, else the enums nested in them named
	/// after the holder's type.
	private func enums(of holder: GraphFuzzerPlaceFacts.Holder) -> [ScopeEnum] {
		seamEnums.filter { scopeEnum in
			guard scopeEnum.extendedType == holder.seamType else { return false }
			return holder.isSeamRoot ? scopeEnum.isRoot : !scopeEnum.isRoot && Self.isEnumName(scopeEnum.path.last ?? "", ofTypeNamed: holder.typeName)
		}
	}

	/// The holder of the levels `scopeEnum` describes: its seam's root, or the type of a scope on some place's path whose
	/// enum's name it has.
	private func holder(of scopeEnum: ScopeEnum, in facts: GraphFuzzerPlaceFacts) -> GraphFuzzerPlaceFacts.Holder? {
		guard !scopeEnum.isRoot else {
			return GraphFuzzerPlaceFacts.Holder(seamType: scopeEnum.extendedType, typeName: scopeEnum.extendedType, isSeamRoot: true)
		}
		return facts.declaredLabels.keys.sorted().first { holder in
			!holder.isSeamRoot && holder.seamType == scopeEnum.extendedType && Self.isEnumName(scopeEnum.path.last ?? "", ofTypeNamed: holder.typeName)
		}
	}

	/// The labels of each enum's cases of its own, by the enum's qualified name: a case that holds no other seam's enum,
	/// and whose nested enum, if it holds one, has a case of its own. Found as a fixed point, since nested enums can hold
	/// each other in a cycle.
	private func ownCaseLabelsByEnum() -> [String: Set<String>] {
		var ownCaseLabelsByEnum = [String: Set<String>]()
		var changed = true
		while changed {
			changed = false
			for scopeEnum in seamEnums {
				for scopeCase in scopeEnum.cases where !ownCaseLabelsByEnum[scopeEnum.qualifiedName, default: []].contains(scopeCase.label) && !scopeCase.wrapsAnotherSeamsEnum(extendedType: scopeEnum.extendedType) {
					let isOwn = if let nestedPath = scopeCase.nestedEnumPath(extendedType: scopeEnum.extendedType) {
						!ownCaseLabelsByEnum[([scopeEnum.extendedType] + nestedPath).joined(separator: "."), default: []].isEmpty
					} else {
						true
					}
					if isOwn {
						ownCaseLabelsByEnum[scopeEnum.qualifiedName, default: []].insert(scopeCase.label)
						changed = true
					}
				}
			}
		}
		return ownCaseLabelsByEnum
	}

	/// Whether `enumName` is the nested enum of the type `typeName`: its stem with `_Scope` and any `_` a collision
	/// appends.
	private static func isEnumName(_ enumName: String, ofTypeNamed typeName: String) -> Bool {
		let stemmed = stem(of: typeName) + "_Scope"
		return enumName.hasPrefix(stemmed) && enumName.dropFirst(stemmed.count).allSatisfy { $0 == "_" }
	}

	/// The stem of a type's nested enum: the type as the seam's module spells it, its dots joined by `_`.
	private static func stem(of typeName: String) -> String {
		typeName.replacingOccurrences(of: ".", with: "_")
	}

	private static func description(of holder: GraphFuzzerPlaceFacts.Holder) -> String {
		holder.isSeamRoot ? "the seam `\(holder.seamType)`" : "`\(holder.typeName)` in the tree of `\(holder.seamType)`"
	}

	private static func expression(_ pattern: String) -> NSRegularExpression {
		// The patterns are this file's, built from escaped names.
		try! NSRegularExpression(pattern: pattern)
	}

	private static func matches(_ expression: NSRegularExpression, _ string: String) -> Bool {
		expression.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
	}
}

/// A reference to a scope enum in a case's payload: `SafeDIScope_X.U_Scope`, qualified or not by the seam whose
/// extension declares it, or `Inner.SafeDIScope_X`, another seam's root enum.
private struct ScopeEnumReference {
	init?(_ type: String, extendedType: String) {
		var components = type.trimmingCharacters(in: .whitespaces).split(separator: ".").map(String.init)
		guard let rootIndex = components.firstIndex(where: { GraphFuzzerScopeDeclarations.isRootEnumName($0) }) else { return nil }
		let qualifier = components[..<rootIndex].joined(separator: ".")
		components.removeFirst(rootIndex)
		// A root enum is a seam call's, even the extended type's own, which a call of the seam inside its own tree hands up.
		isOwn = (qualifier.isEmpty || qualifier == extendedType) && components.count > 1
		path = components
	}

	/// Whether the enum is one the extended type declares for its own levels: nested in its root enum. A case that holds a
	/// root enum, the extended type's own included, wraps the enum of a seam the tree calls.
	let isOwn: Bool
	/// The enum's path from its root enum.
	let path: [String]
}

extension GraphFuzzerScopeDeclarations {
	/// Whether `name` is the name of a root scope enum: `SafeDIScope_…`, `SafeDISendableScope_…`, or a public mock's.
	static func isRootEnumName(_ name: String) -> Bool {
		name.range(of: #"^SafeDI(?:Sendable)?(?:Mock)?Scope_"#, options: .regularExpression) != nil
	}
}

/// Collects the scope enums each extension of a generated file declares, wherever the extension is, in a conditional
/// block included.
private final class ScopeEnumCollector: SyntaxVisitor {
	private(set) var enums = [GraphFuzzerScopeDeclarations.ScopeEnum]()
	private(set) var valuesStructs = [GraphFuzzerScopeDeclarations.ValuesStruct]()

	override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
		let extendedType = node.extendedType.trimmedDescription
		for member in node.memberBlock.members {
			if let enumDeclaration = member.decl.as(EnumDeclSyntax.self), GraphFuzzerScopeDeclarations.isRootEnumName(enumDeclaration.name.text) {
				collect(enumDeclaration, extendedType: extendedType, enclosingPath: [])
			}
		}
		return .skipChildren
	}

	private func collect(_ enumDeclaration: EnumDeclSyntax, extendedType: String, enclosingPath: [String]) {
		let path = enclosingPath + [enumDeclaration.name.text]
		// Each enum before the enums nested in it, so that enums are listed in the order a reader meets them.
		let enumIndex = enums.count
		enums.append(GraphFuzzerScopeDeclarations.ScopeEnum(extendedType: extendedType, path: path, cases: []))
		var cases = [GraphFuzzerScopeDeclarations.ScopeCase]()
		var nestedEnums = [EnumDeclSyntax]()
		for member in enumDeclaration.memberBlock.members {
			if let caseDeclaration = member.decl.as(EnumCaseDeclSyntax.self) {
				for element in caseDeclaration.elements {
					cases.append(GraphFuzzerScopeDeclarations.ScopeCase(
						label: element.name.text,
						payload: element.parameterClause?.parameters.map(\.type.trimmedDescription) ?? [],
					))
				}
			} else if let nestedEnum = member.decl.as(EnumDeclSyntax.self) {
				nestedEnums.append(nestedEnum)
			} else if let structDeclaration = member.decl.as(StructDeclSyntax.self) {
				var fields = [String]()
				for structMember in structDeclaration.memberBlock.members {
					guard let variable = structMember.decl.as(VariableDeclSyntax.self) else { continue }
					let access = variable.modifiers.map(\.name.text).first { ["public", "package", "internal", "fileprivate", "private"].contains($0) } ?? "internal"
					for binding in variable.bindings {
						guard let typeAnnotation = binding.typeAnnotation else { continue }
						fields.append("\(access) \(binding.pattern.trimmedDescription): \(typeAnnotation.type.trimmedDescription)")
					}
				}
				valuesStructs.append(GraphFuzzerScopeDeclarations.ValuesStruct(extendedType: extendedType, path: path + [structDeclaration.name.text], fields: fields))
			}
		}
		enums[enumIndex] = GraphFuzzerScopeDeclarations.ScopeEnum(extendedType: extendedType, path: path, cases: cases)
		for nestedEnum in nestedEnums {
			collect(nestedEnum, extendedType: extendedType, enclosingPath: path)
		}
	}
}
