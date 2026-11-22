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

/// How a seam's carriers hand a level's values to their members: the one place that decides it, which the carrier's
/// declaration, the seam's tree and the caller's carrier all read, each computing it from the same enums.
///
/// A level's values are what its type binds before a case's property, so the values of one level's cases are prefixes
/// of one sequence. The values are cut into runs at the lengths the level's cases take (each plain carrier enum of the
/// level, across hole types), and each run is a struct, `__safeDI_<Level>Values<end>`, holding the run's fields and the
/// struct of the run before it as `previous`. The seam's tree forms each run's struct once, where it first binds a
/// case of that length, from the one before, and a member takes exactly the struct of its case's length. So a member
/// takes one argument however many values its level binds, a run's fields are spelled once per level, and every value
/// keeps the access its type proves: a struct field at its own access, never a positional argument of a wider member.
///
/// The internal switch `chainsEveryRun` keeps the single-struct form beside it for measurement: one struct per level,
/// of the shortest case's values, with every later value positional. Only one form ships; the other is deleted before
/// review.
struct SeamCarrierValues: Sendable {
	/// Whether every distinct length of a level's cases ends a run of its own (a member takes exactly its struct), or only
	/// the shortest does (a member takes that struct and the rest of its values positionally).
	static let chainsEveryRun = true

	/// Where each run of each level ends, by level, ascending.
	private let endsByLevel: [String: [Int]]

	/// No level: a tree whose seam declares no carrier with values.
	init() {
		endsByLevel = [:]
	}

	/// The runs of each level of `scopeEnums`' plain carriers of `seamType`'s enums. A level whose cases' values are not
	/// prefixes of one sequence takes no struct: its members take their values positionally.
	init(scopeEnums: [SeamSignature.ScopeEnum], ofSeam seamType: TypeDescription?) {
		var longestByLevel = [String: [SeamSignature.Hole.Field]]()
		var lengthsByLevel = [String: Set<Int>]()
		var inconsistentLevels = Set<String>()
		for scopeEnum in scopeEnums where seamType == nil || scopeEnum.key.seamType == seamType {
			guard let level = Self.level(ofEnum: scopeEnum.type) else { continue }
			for enumCase in scopeEnum.cases {
				guard let fields = enumCase.values?.fields, !fields.isEmpty else { continue }
				lengthsByLevel[level, default: []].insert(fields.count)
				let longest = longestByLevel[level] ?? []
				let shorter = longest.count < fields.count ? longest : fields
				let longer = longest.count < fields.count ? fields : longest
				if !zip(shorter, longer).allSatisfy({ $0.property == $1.property && $0.property.typeDescription.asSource == $1.property.typeDescription.asSource && $0.deferral == $1.deferral }) {
					inconsistentLevels.insert(level)
				}
				longestByLevel[level] = longer
			}
		}
		var endsByLevel = [String: [Int]]()
		for (level, lengths) in lengthsByLevel where !inconsistentLevels.contains(level) {
			let sorted = lengths.sorted()
			endsByLevel[level] = Self.chainsEveryRun ? sorted : Array(sorted.prefix(1))
		}
		self.endsByLevel = endsByLevel
	}

	/// The runs of each seam's levels among `scopeEnums`, by seam.
	static func bySeam(of scopeEnums: [SeamSignature.ScopeEnum]) -> [TypeDescription: SeamCarrierValues] {
		var seams = [TypeDescription]()
		for scopeEnum in scopeEnums where !seams.contains(scopeEnum.key.seamType) {
			seams.append(scopeEnum.key.seamType)
		}
		var bySeam = [TypeDescription: SeamCarrierValues]()
		for seam in seams {
			let values = SeamCarrierValues(scopeEnums: scopeEnums, ofSeam: seam)
			if !values.isEmpty {
				bySeam[seam] = values
			}
		}
		return bySeam
	}

	/// The level a seam's plain carrier enum describes, which names the level's structs whatever hole type the enum is of:
	/// `__safeDI_` and the type the enum is nested for, nothing for the seam's own root; `nil` for an enum that is no plain
	/// carrier.
	static func level(ofEnum enumType: TypeDescription) -> String? {
		guard let carrier = ReservedName.seamCarrier(ofEnum: enumType), !carrier.isSendable else { return nil }
		return ReservedName.builderFunctionNamePrefix + (carrier.describedTypeName ?? "")
	}

	/// Whether no level is cut into runs.
	var isEmpty: Bool {
		endsByLevel.isEmpty
	}

	/// How a member of `level` takes `count` values: the struct of the longest run that ends within them, if any, and the
	/// values after it, positionally.
	func use(ofLevel level: String, count: Int) -> Use {
		let ends = endsByLevel[level] ?? []
		let end = ends.last { $0 <= count }
		return Use(level: level, structEnd: end, extras: (end ?? 0)..<count, ends: ends)
	}

	/// The runs a level is cut into, by where each ends.
	func ends(ofLevel level: String) -> [Int] {
		endsByLevel[level] ?? []
	}

	/// The run of `level` before the one that ends at `end`.
	func previousEnd(ofLevel level: String, before end: Int) -> Int? {
		endsByLevel[level]?.last { $0 < end }
	}

	/// How a member takes its case's values.
	struct Use: Sendable {
		let level: String
		/// Where the run whose struct the member takes ends, or `nil` where it takes none.
		let structEnd: Int?
		/// The positions of the values the member takes positionally, after the struct's.
		let extras: Range<Int>
		/// Where each of the level's runs ends.
		let ends: [Int]

		/// The names a closure or function that takes the values names its parameters, for `fields`, its values, under
		/// `payloadName`: the struct under the payload's name, then each value after it under the payload's name joined with
		/// its label.
		func parameterNames(of fields: [SeamSignature.Hole.Field], inPayloadNamed payloadName: String) -> [String] {
			var names = structEnd == nil ? [String]() : [payloadName]
			for field in fields[extras.clamped(to: 0..<fields.count)] {
				names.append(SeamHoles.argumentName(of: field, inPayloadNamed: payloadName))
			}
			return names
		}

		/// The types of the parameters `parameterNames(of:inPayloadNamed:)` names, the struct's qualified by `seamType`.
		func parameterTypes(of fields: [SeamSignature.Hole.Field], qualifiedBy seamType: TypeDescription?, typesDeclaredEscaping: Set<TypeDescription>) -> [TypeDescription] {
			var types = structType(qualifiedBy: seamType).map { [$0] } ?? []
			for field in fields[extras.clamped(to: 0..<fields.count)] {
				types.append(field.memoType ?? field.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping))
			}
			return types
		}

		/// What reads the value at `index` of `fields` from the parameters `parameterNames(of:inPayloadNamed:)` names: the
		/// struct's field, through `previous` for a run before the struct's own, or the value's own parameter. A deferred
		/// parameter's field holds its memo, whose instance is the value, unless `bindingMemo`.
		func read(ofFieldAt index: Int, of fields: [SeamSignature.Hole.Field], inPayloadNamed payloadName: String, bindingMemo: Bool) -> String {
			let field = fields[index]
			guard let structEnd, index < structEnd else { return SeamHoles.argumentRead(of: field, inPayloadNamed: payloadName, bindingMemo: bindingMemo) }
			var hops = 0
			var runEnd = structEnd
			while let previous = ends.last(where: { $0 < runEnd }), index < previous {
				hops += 1
				runEnd = previous
			}
			let path = payloadName + String(repeating: ".\(SeamCarrierValues.previousName)", count: hops) + "." + field.property.label.spelledAsMemberReference
			return field.isDeferredParameter && !bindingMemo ? "\(path).\(Dependency.lazilyInstantiatedInstancePropertyName)" : path
		}

		/// The struct's type, as `qualifiedBy` (the seam, where a caller spells it) qualifies it.
		func structType(qualifiedBy seamType: TypeDescription?) -> TypeDescription? {
			structEnd.map { SeamCarrierValues.structType(ofLevel: level, end: $0, qualifiedBy: seamType) }
		}

		/// The name the seam's tree binds the struct under.
		var structBindingName: String? {
			structEnd.map { SeamCarrierValues.bindingName(ofLevel: level, end: $0) }
		}
	}

	/// The type of the struct of `level`'s run that ends at `end`.
	static func structType(ofLevel level: String, end: Int, qualifiedBy seamType: TypeDescription?) -> TypeDescription {
		let name = "\(level)Values\(end)"
		guard let seamType else { return .simple(name: name, generics: []) }
		return .nested(name: name, parentType: seamType, generics: [])
	}

	/// The name the seam's tree binds the struct of `level`'s run that ends at `end` under.
	static func bindingName(ofLevel level: String, end: Int) -> String {
		"\(level)_values\(end)"
	}

	/// The name of a run's struct's field that holds the run before it.
	static let previousName = "previous"

	/// The declarations of every level's structs, in level order then run order, each `nonisolated` and as visible as
	/// the carrier it is handed through, each field at its own access.
	func declarations(fieldsByLevel: [String: [SeamSignature.Hole.Field]], typesDeclaredEscaping: Set<TypeDescription>, indent: String) -> [String] {
		var declarations = [String]()
		let memberIndent = indent + ScopeGenerator.standardIndent
		let bodyIndent = memberIndent + ScopeGenerator.standardIndent
		for level in endsByLevel.keys.sorted() {
			guard let fields = fieldsByLevel[level] else { continue }
			var start = 0
			for end in ends(ofLevel: level) where end <= fields.count {
				let run = fields[start..<end]
				let previous = start == 0 ? nil : Self.structType(ofLevel: level, end: start, qualifiedBy: nil)
				var lines = [
					"\(indent)/// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.",
					"\(indent)nonisolated public struct \(Self.structType(ofLevel: level, end: end, qualifiedBy: nil).asSource) {",
				]
				var parameters = [String]()
				if let previous {
					lines.append("\(memberIndent)public let \(Self.previousName): \(previous.asSource)")
					parameters.append("\(Self.previousName): \(previous.asSource)")
				}
				for field in run {
					let type = field.memoType ?? field.property.typeDescription
					lines.append("\(memberIndent)\(AccessLevel.normalized(field.access).spelling) let \(field.property.label.spelledAsMemberDeclarationName): \(type.asSource)")
					parameters.append("\(field.property.label.spelledAsAssigningParameter(labeled: field.property.label)): \((field.memoType ?? field.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)).asSource)")
				}
				lines.append("")
				lines.append("\(memberIndent)init(\(parameters.joined(separator: ", "))) {")
				if previous != nil {
					lines.append("\(bodyIndent)self.\(Self.previousName) = \(Self.previousName)")
				}
				for field in run {
					lines.append("\(bodyIndent)self.\(field.property.label.spelledAsMemberDeclarationName) = \(field.property.label.spelledAsAssigningParameterName)")
				}
				lines.append("\(memberIndent)}")
				lines.append("\(indent)}")
				declarations.append(lines.joined(separator: "\n"))
				start = end
			}
		}
		return declarations
	}

	/// The longest values of each level of `scopeEnums`' plain carriers, which `declarations` declares the runs of.
	static func fieldsByLevel(of scopeEnums: [SeamSignature.ScopeEnum]) -> [String: [SeamSignature.Hole.Field]] {
		var fieldsByLevel = [String: [SeamSignature.Hole.Field]]()
		for scopeEnum in scopeEnums {
			guard let level = level(ofEnum: scopeEnum.type) else { continue }
			for enumCase in scopeEnum.cases {
				guard let fields = enumCase.values?.fields, fields.count > fieldsByLevel[level]?.count ?? 0 else { continue }
				fieldsByLevel[level] = fields
			}
		}
		return fieldsByLevel
	}
}
