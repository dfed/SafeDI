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

extension ScopeGenerator {
	/// The empty enum a seam's or a public mock's module generates beside the code it generates for `typeName`, named for
	/// the signature that code was generated from, which every call of that code names on the line before it
	/// (`SeamCall.guardLine(for:)`, `PublicMockCall.guardLine(for:)`), so that a call generated from another signature
	/// fails to compile there.
	static func guardEnumDeclaration(extending typeName: String, named guardTypeName: String) -> String {
		"""
		extension \(typeName) {
		\(standardIndent)public enum \(guardTypeName) {}
		}
		"""
	}

	static func structDeclaration(named name: String, fields: [SeamSignature.Hole.Field], indent: String, typesDeclaredEscaping: Set<TypeDescription>, isNonisolated: Bool = false) -> String {
		let declarationPrefix = isNonisolated ? "\(indent)nonisolated public struct" : "\(indent)public struct"
		guard !fields.isEmpty else { return "\(declarationPrefix) \(name) {}" }
		let memberIndent = "\(indent)\(standardIndent)"
		let fieldDeclarations = fields.map { field in
			if field.isDeferredParameter {
				"\(memberIndent)\(field.access.spelledOnGeneratedDeclaration) var \(field.property.label.spelledAsMemberDeclarationName): \(field.property.typeDescription.asSource) { \(field.memoName).\(Dependency.lazilyInstantiatedInstancePropertyName) }"
			} else {
				"\(memberIndent)\(field.access.spelledOnGeneratedDeclaration) let \(field.property.label.spelledAsMemberDeclarationName): \(field.property.typeDescription.asSource)"
			}
		}
		let memoFields = fields.filter(\.isDeferredParameter)
		guard !memoFields.isEmpty else {
			return (["\(declarationPrefix) \(name) {"] + fieldDeclarations + ["\(indent)}"]).joined(separator: "\n")
		}
		let memoDeclarations = memoFields.compactMap { field in
			// The memo is as visible as its field, so a fill in another module binds it and reads its instance where its tree
			// reads the value.
			field.memoType.map { "\(memberIndent)\(field.access.spelledOnGeneratedDeclaration) let \(field.memoName): \($0.asSource)" }
		}
		let initializerParameters = fields.map { field in
			"\(field.property.label.spelledAsArgumentLabel): \((field.memoType ?? field.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)).asSource)"
		}
		let initializerAssignments = fields.map { field in
			if field.isDeferredParameter {
				"\(memberIndent)\(standardIndent)\(field.memoName) = \(field.property.label)"
			} else {
				"\(memberIndent)\(standardIndent)self.\(field.property.label.spelledAsMemberReference) = \(field.property.label)"
			}
		}
		// Appended part by part, for Swift 6.2: it cannot type-check one `+` chain of these arrays in reasonable time.
		var lines = ["\(declarationPrefix) \(name) {"]
		lines += fieldDeclarations
		lines += memoDeclarations
		lines.append("")
		lines.append("\(memberIndent)init(\(initializerParameters.joined(separator: ", "))) {")
		lines += initializerAssignments
		lines.append("\(memberIndent)}")
		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}

	/// The declarations of the scope types a seam's or a public mock's own `builders` are handed, in builder order: each own
	/// root enum, with the enums nested in it, the plain root of a hole type declared before its `@Sendable` root even where
	/// it takes no builder of its own. Each `public` declaration that names a type SafeDI reads no declaration of is marked
	/// for the file's comment (`unreadTypeComment`), by its `public` fields and, where `namesForwardedTypes`, the forwarded
	/// values its cases carry.
	static func ownScopeTypeDeclarations(
		builders: [SeamSignature.Builder],
		scopeEnums: [SeamSignature.ScopeEnum],
		holes: [SeamSignature.Hole],
		typesDeclaredEscaping: Set<TypeDescription>,
		unreadTypeComment: UnreadTypeComment?,
		namesForwardedTypes: Bool,
	) -> [String] {
		guard let ownType = builders.first?.enumKey.seamType else { return [] }
		let holesBySite = Dictionary(holes.map { ($0.site, $0) }, uniquingKeysWith: { first, _ in first })
		let calledRootsTakingValue = calledRootsTakingValue(amongEnumsOf: scopeEnums, filledBy: scopeEnums.filter { $0.key.seamType == ownType })
		// Each level's form is computed once per hole type: the builder structs ask for the form of a level once for every case
		// that holds it.
		var levelFormsByHoleType = [SeamSignature.HoleType: LevelBuilderForms]()
		let ownEnums = scopeEnums.filter { $0.key.seamType == ownType }
		let carrierValues = SeamCarrierValues(scopeEnums: ownEnums, ofSeam: nil)
		let valuesStructs = carrierValues.declarations(fieldsByLevel: SeamCarrierValues.fieldsByLevel(of: ownEnums), typesDeclaredEscaping: typesDeclaredEscaping, indent: standardIndent)
		return valuesStructs + scopeEnums.filter { $0.rootTypeName == nil && $0.key.seamType == ownType }.map { scopeEnum in
			let key = scopeEnum.key
			// A root enum declares the enums of its family's types other than the seam's own, nested inside it; a case spells the
			// enum it holds as its kind gives it, a root or a nested enum of either family.
			let nestedEnums = scopeEnums.filter { $0.key.describedType != nil && $0.key.seamType == key.seamType && $0.key.holeType == key.holeType && $0.key.isSendable == key.isSendable }
			var namedTypes = [TypeDescription]()
			for enumCase in ([scopeEnum] + nestedEnums).flatMap(\.cases) {
				namedTypes += enumCase.values?.fields.filter { $0.access == .public }.map(\.property.typeDescription) ?? []
				switch enumCase.kind {
				case let .place(sites):
					if namesForwardedTypes, let forwardedType = sites.first.flatMap({ holesBySite[$0] })?.forwardedType {
						namedTypes.append(forwardedType)
					}
				case .nested, .inner, .fill:
					break
				}
			}
			var levelForms = levelFormsByHoleType[key.holeType] ?? LevelBuilderForms(enumsOfHoleType: scopeEnums.filter { $0.key.holeType == key.holeType }, holesBySite: holesBySite)
			let declaration = scopeEnumDeclaration(of: scopeEnum, nestedEnums: nestedEnums, holesBySite: holesBySite, typesDeclaredEscaping: typesDeclaredEscaping, levelForms: &levelForms, calledRootsTakingValue: calledRootsTakingValue, carrierValues: carrierValues)
			levelFormsByHoleType[key.holeType] = levelForms
			guard let marker = unreadTypeComment?.markerLine(namedBy: namedTypes, indent: standardIndent) else { return declaration }
			return "\(marker)\n\(declaration)"
		}
	}

	/// The called seams' root enums, among `reachedEnums`, whose builder struct takes a builder that takes a value from its
	/// no-scope initializer, of those a case of `fillingEnums` for a builder the seam fills holds: every place such a root
	/// reaches is held in an instantiator that forwards a value (`DependencyTreeGenerator.builderForm(ofPlaces:)`), whose
	/// property ends the place's site path. Found once for the seam, never once for each case.
	private static func calledRootsTakingValue(amongEnumsOf reachedEnums: [SeamSignature.ScopeEnum], filledBy fillingEnums: [SeamSignature.ScopeEnum]) -> Set<SeamSignature.ScopeEnum.Key> {
		var innerKeys = Set<SeamSignature.ScopeEnum.Key>()
		for enumCase in fillingEnums.flatMap(\.cases) {
			if case let .fill(innerKey, _?, _, _, _) = enumCase.kind {
				innerKeys.insert(innerKey)
			}
		}
		var calledRootsTakingValue = Set<SeamSignature.ScopeEnum.Key>()
		var calledEnumsByHoleType = [SeamSignature.HoleType: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]]()
		for innerKey in innerKeys {
			if calledEnumsByHoleType[innerKey.holeType] == nil {
				calledEnumsByHoleType[innerKey.holeType] = Dictionary(reachedEnums.filter { $0.key.holeType == innerKey.holeType }.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
			}
			let places = SeamSignature.ScopeEnum.sitesReached(from: innerKey, in: calledEnumsByHoleType[innerKey.holeType] ?? [:]).compactMap(\.path.last)
			if DependencyTreeGenerator.builderForm(ofPlaceProperties: places).forwardedValue != nil {
				calledRootsTakingValue.insert(innerKey)
			}
		}
		return calledRootsTakingValue
	}

	/// The declaration of `scopeEnum`, nested in the seam or the public mock, a namespace no generated code builds or switches
	/// over a case of: each case's payload struct, in the order the generated code first reaches the cases, then, for a root
	/// enum nested by type, each of `nestedEnums`, then its builder struct. `public`, so its access is the seam's.
	/// - Parameters:
	///   - levelForms: The forms of the levels of every enum of the hole type of `scopeEnum`, both families', which decide
	///     the type each level's builder struct takes from the builder a person writes.
	///   - calledRootsTakingValue: The called seams' root enums whose struct takes a builder that takes a value from its
	///     no-scope initializer, which decide what the struct of such a root that a case for a builder the seam fills returns
	///     takes from its builder (`calledRootsTakingValue(amongEnumsOf:filledBy:)`).
	static func scopeEnumDeclaration(of scopeEnum: SeamSignature.ScopeEnum, nestedEnums: [SeamSignature.ScopeEnum] = [], holesBySite: [SeamSignature.Hole.Site: SeamSignature.Hole], typesDeclaredEscaping: Set<TypeDescription>, levelForms: inout LevelBuilderForms, calledRootsTakingValue: Set<SeamSignature.ScopeEnum.Key> = [], carrierValues: SeamCarrierValues = SeamCarrierValues(), indent: String = standardIndent) -> String {
		if ReservedName.seamCarrier(ofEnum: scopeEnum.type) != nil {
			// A seam's levels are carriers, declared side by side in the seam's extension: no namespace and no payload struct.
			var carriers = [String]()
			for level in [scopeEnum] + (scopeEnum.rootTypeName == nil ? nestedEnums : []) where !level.cases.isEmpty {
				carriers.append(builderStructDeclaration(of: level, holesBySite: holesBySite, levelForms: &levelForms, calledRootsTakingValue: calledRootsTakingValue, typesDeclaredEscaping: typesDeclaredEscaping, carrierValues: carrierValues, indent: indent))
			}
			return carriers.joined(separator: "\n\n")
		}
		let caseIndent = indent + standardIndent
		var payloadStructs = [String]()
		for enumCase in scopeEnum.cases {
			if let values = enumCase.values {
				payloadStructs.append(structDeclaration(named: values.typeName, fields: values.fields, indent: caseIndent, typesDeclaredEscaping: typesDeclaredEscaping, isNonisolated: true))
			} else if let memberValuesTypeName = enumCase.memberValuesTypeName {
				// A case that carries no values – every case of a `@Sendable` enum, and a call's case, which holds the called enum
				// alone – has a member that takes an empty `Sendable` struct.
				payloadStructs.append("\(caseIndent)nonisolated public struct \(memberValuesTypeName): Sendable {}")
			}
		}
		var body = payloadStructs.joined(separator: "\n\n")
		// Only the root declares the enums nested in it; a nested enum's cases spell them from the root.
		if scopeEnum.rootTypeName == nil {
			for nestedEnum in nestedEnums {
				body += (body.isEmpty ? "" : "\n\n") + scopeEnumDeclaration(of: nestedEnum, holesBySite: holesBySite, typesDeclaredEscaping: typesDeclaredEscaping, levelForms: &levelForms, calledRootsTakingValue: calledRootsTakingValue, indent: caseIndent)
			}
		}
		// A root of the plain family with no case of its own, a namespace for the enums its `@Sendable` root's cases hold,
		// declares no struct: no builder is handed one.
		if !scopeEnum.cases.isEmpty {
			body += (body.isEmpty ? "" : "\n\n") + builderStructDeclaration(of: scopeEnum, holesBySite: holesBySite, levelForms: &levelForms, calledRootsTakingValue: calledRootsTakingValue, typesDeclaredEscaping: typesDeclaredEscaping, carrierValues: carrierValues, indent: caseIndent)
		}
		return """
		\(indent)nonisolated public enum \(scopeEnum.typeName) {
		\(body)
		\(indent)}
		"""
	}

	/// The forms of the builders a person writes for the levels of one hole type's enums, each computed the first time a
	/// builder struct asks for it, since a level's form is asked for once for every case that holds the level.
	/// `DependencyTreeGenerator.builderForm(ofPlaces:)` reads of its places only the spellings of their wrappers and of the
	/// values they forward, never their order or how many share a spelling, so a level is handed one place per spelling its
	/// places have: reading every place of every level beneath, sorted, made the cost of a seam's enums grow with the
	/// square of its places.
	struct LevelBuilderForms {
		init(enumsOfHoleType: [SeamSignature.ScopeEnum], holesBySite: [SeamSignature.Hole.Site: SeamSignature.Hole]) {
			enumsByKey = Dictionary(enumsOfHoleType.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
			self.holesBySite = holesBySite
		}

		/// The form of the builder a person writes for the places at and beneath the level of `key`, in that level's family.
		mutating func form(ofLevel key: SeamSignature.ScopeEnum.Key) -> DependencyTreeGenerator.BuilderForm {
			if let form = formByKey[key] {
				return form
			} else {
				var placeBySpelling = [PlaceSpelling: SeamSignature.Hole]()
				var visitedKeys = Set<SeamSignature.ScopeEnum.Key>()
				var keysToVisit = [key]
				while let visitedKey = keysToVisit.popLast() {
					guard visitedKeys.insert(visitedKey).inserted, let scopeEnum = enumsByKey[visitedKey] else { continue }
					placeBySpelling.merge(ownPlaces(of: scopeEnum), uniquingKeysWith: { first, _ in first })
					for enumCase in scopeEnum.cases {
						switch enumCase.kind {
						case .place:
							break
						case let .nested(innerKey, _, _),
						     let .inner(innerKey, _, _),
						     let .fill(_, _, innerKey, _, _):
							keysToVisit.append(innerKey)
						}
					}
				}
				let form = DependencyTreeGenerator.builderForm(ofPlaces: placeBySpelling.sorted { $0.key < $1.key }.map(\.value))
				formByKey[key] = form
				return form
			}
		}

		/// Whether the no-scope initializer of the struct of the level of `key` takes a `@Sendable` builder: where the level
		/// is of the `@Sendable` family, or its initializer hands the builder to the no-scope initializer of a struct that
		/// takes one, a struct of the `@Sendable` family or a level that hands it on so. A level of the plain family whose
		/// call's case re-enters an enclosing call's fill through a builder held in a `Sendable` wrapper returns the called
		/// seam's struct of the `@Sendable` family (`SeamScopeEnumsByType.leadsToPlace(_:reenteringFills:)`), which no builder
		/// that is not `@Sendable` can make; the enclosing call's fill is then built in a `@Sendable` function, so the root
		/// that holds the level is of the `@Sendable` family and hands its own builder down.
		mutating func takesSendableBuilder(atLevel key: SeamSignature.ScopeEnum.Key) -> Bool {
			if let levelsTakingSendableBuilder {
				return levelsTakingSendableBuilder.contains(key)
			} else {
				// The levels that hold each level, from which a level that takes a `@Sendable` builder makes its holders take one.
				var holdersByKey = [SeamSignature.ScopeEnum.Key: [SeamSignature.ScopeEnum.Key]]()
				var takingKeys = Set<SeamSignature.ScopeEnum.Key>()
				for (holderKey, scopeEnum) in enumsByKey {
					// The structs the level's no-scope initializer makes: a call's case for a builder it fills makes the called
					// seam's struct around the fill's level, unless it carries no scope value.
					var heldKeys = [SeamSignature.ScopeEnum.Key]()
					for enumCase in scopeEnum.cases {
						switch enumCase.kind {
						case .place:
							break
						case let .fill(innerKey, _?, heldKey, _, _):
							heldKeys += [innerKey, heldKey]
						case let .nested(heldKey, _, _),
						     let .inner(heldKey, _, _),
						     let .fill(_, _, heldKey, _, _):
							heldKeys.append(heldKey)
						}
					}
					if holderKey.isSendable || heldKeys.contains(where: \.isSendable) {
						takingKeys.insert(holderKey)
					}
					for heldKey in heldKeys {
						holdersByKey[heldKey, default: []].append(holderKey)
					}
				}
				var keysToVisit = Array(takingKeys)
				while let visitedKey = keysToVisit.popLast() {
					for holderKey in holdersByKey[visitedKey, default: []] where takingKeys.insert(holderKey).inserted {
						keysToVisit.append(holderKey)
					}
				}
				levelsTakingSendableBuilder = takingKeys
				return takingKeys.contains(key)
			}
		}

		/// What `DependencyTreeGenerator.builderForm(ofPlaces:)` reads of a place: whether it is held in an instantiator, and
		/// then the wrapper's spelling and that of the value it forwards.
		private struct PlaceSpelling: Hashable, Comparable {
			init(of place: SeamSignature.Hole) {
				let isAnyInstantiator = place.property.propertyType.isAnyInstantiator
				self.isAnyInstantiator = isAnyInstantiator
				wrapper = isAnyInstantiator ? place.property.typeDescription.unwrapped.strippingEscaping.asSource : ""
				forwarded = isAnyInstantiator ? place.forwardedType?.strippingEscaping.asSource : nil
			}

			let isAnyInstantiator: Bool
			let wrapper: String
			let forwarded: String?

			static func < (lhs: PlaceSpelling, rhs: PlaceSpelling) -> Bool {
				(lhs.isAnyInstantiator ? 1 : 0, lhs.wrapper, lhs.forwarded ?? "") < (rhs.isAnyInstantiator ? 1 : 0, rhs.wrapper, rhs.forwarded ?? "")
			}
		}

		/// One place of each spelling among the places of `scopeEnum`'s own cases.
		private mutating func ownPlaces(of scopeEnum: SeamSignature.ScopeEnum) -> [PlaceSpelling: SeamSignature.Hole] {
			if let places = ownPlacesByKey[scopeEnum.key] {
				return places
			} else {
				var places = [PlaceSpelling: SeamSignature.Hole]()
				for enumCase in scopeEnum.cases {
					switch enumCase.kind {
					case let .place(sites):
						for place in sites.compactMap({ holesBySite[$0] }) {
							let spelling = PlaceSpelling(of: place)
							places[spelling] = places[spelling] ?? place
						}
					case .nested, .inner, .fill:
						break
					}
				}
				ownPlacesByKey[scopeEnum.key] = places
				return places
			}
		}

		private let enumsByKey: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]
		private let holesBySite: [SeamSignature.Hole.Site: SeamSignature.Hole]
		private var formByKey = [SeamSignature.ScopeEnum.Key: DependencyTreeGenerator.BuilderForm]()
		private var ownPlacesByKey = [SeamSignature.ScopeEnum.Key: [PlaceSpelling: SeamSignature.Hole]]()
		private var levelsTakingSendableBuilder: Set<SeamSignature.ScopeEnum.Key>?
	}

	/// The builder struct of `scopeEnum`, `__safeDI_Builder<Built>`, indented by `indent`: one stored function per case, its
	/// member, named as the case, which takes the struct the case's member takes (`ScopeEnum.Case.memberValuesTypeName`) and
	/// returns what the place builds – for a place held in an instantiator, the erased wrapper's `Builder` over what the place
	/// forwards, `()` for nothing, since the constrained wrappers cannot be spelled over `Built` – or the builder struct of
	/// the enum the case holds; the memberwise initializer; and `init(__safeDI_noScope:)`, which makes every member call one
	/// builder, as a seam's readable initializer passes it the builder a person wrote. That builder's type is the one a
	/// person writes for the places at and beneath the level, in the level's own family
	/// (`DependencyTreeGenerator.builderForm(ofPlaces:)`), over `Built`, or in the `@Sendable` family where the level hands
	/// it to a struct that takes a `@Sendable` one (`LevelBuilderForms.takesSendableBuilder(atLevel:)`). A member whose own
	/// type takes a value where the level's builder takes nothing – `()`, or `T.ForwardedProperties`, which is `Void` beside
	/// a place that forwards nothing – is handed the builder adapted to it. A `@Sendable` enum's struct is `Sendable`, with
	/// `@Sendable` members.
	private static func builderStructDeclaration(
		of scopeEnum: SeamSignature.ScopeEnum,
		holesBySite: [SeamSignature.Hole.Site: SeamSignature.Hole],
		levelForms: inout LevelBuilderForms,
		calledRootsTakingValue: Set<SeamSignature.ScopeEnum.Key>,
		typesDeclaredEscaping: Set<TypeDescription>,
		carrierValues: SeamCarrierValues,
		indent: String,
	) -> String {
		let carrierName = ReservedName.seamCarrier(ofEnum: scopeEnum.type)?.name
		let isSendable = scopeEnum.key.isSendable
		let memberIndent = indent + standardIndent
		let bodyIndent = memberIndent + standardIndent
		let sendableAttribute = isSendable ? "@Sendable " : ""
		let builtTypeName = ReservedName.builderStructGenericParameterName
		let builtType = TypeDescription.simple(name: builtTypeName, generics: [])
		let builderParameter = ReservedName.noScopeParameterName
		let levelForm = levelForms.form(ofLevel: scopeEnum.key)
		let takesSendableBuilder = levelForms.takesSendableBuilder(atLevel: scopeEnum.key)
		let noScopeType: TypeDescription = if let forwarded = levelForm.forwardedValue {
			DependencyTreeGenerator.erasedBuilderType(forwarding: forwarded, returning: builtType, isSendable: takesSendableBuilder)
		} else if takesSendableBuilder {
			TypeDescription.closure(arguments: [], isAsync: false, doesThrow: false, returnType: builtType).asSendableFunction
		} else {
			TypeDescription.closure(arguments: [], isAsync: false, doesThrow: false, returnType: builtType)
		}
		/// The builder, adapted to a member or a level beneath that takes `forwarded` where this level's takes nothing.
		func builder(adaptedTo forwarded: TypeDescription?) -> String {
			if levelForm.forwardedValue == nil, forwarded != nil {
				"{ _ in \(builderParameter)() }"
			} else {
				builderParameter
			}
		}
		var members = [(name: String, type: String, noScopeValue: String, isLetChild: Bool)]()
		var ignoredArguments = [String: String]()
		for enumCase in scopeEnum.cases {
			let returnType: String
			let noScopeValue: String
			switch enumCase.kind {
			case let .place(sites):
				if let place = sites.first.flatMap({ holesBySite[$0] }), place.property.propertyType.isAnyInstantiator {
					let forwarded = place.forwardedType?.strippingEscaping ?? .void(.tuple)
					returnType = DependencyTreeGenerator.erasedBuilderType(forwarding: forwarded, returning: builtType, isSendable: isSendable).asSource
					noScopeValue = builder(adaptedTo: forwarded)
				} else {
					returnType = builtTypeName
					noScopeValue = "\(builderParameter)()"
				}
			case let .fill(innerKey, innerEnumType?, enumKey, enumType, _):
				// A call's case for a builder it fills returns the called seam's struct over the struct of the fill's own level:
				// its places, wherever on the called seam's levels, build the level of what the fill builds.
				returnType = ReservedName.levelType(ofEnum: innerEnumType, built: ReservedName.levelType(ofEnum: enumType, built: builtType)).asSource
				noScopeValue = ".init(\(ReservedName.noScopeArgumentLabel): { \(calledRootsTakingValue.contains(innerKey) ? "_ in " : "").init(\(ReservedName.noScopeArgumentLabel): \(builder(adaptedTo: levelForms.form(ofLevel: enumKey).forwardedValue))) })"
			case let .nested(enumKey, enumType, _),
			     let .inner(enumKey, enumType, _),
			     let .fill(_, _, enumKey, enumType, _):
				returnType = ReservedName.levelType(ofEnum: enumType, built: builtType).asSource
				noScopeValue = ".init(\(ReservedName.noScopeArgumentLabel): \(builder(adaptedTo: levelForms.form(ofLevel: enumKey).forwardedValue)))"
			}
			if carrierName != nil {
				// A carrier's member takes the values its level binds before the case's property, in field order: a deferred
				// parameter's as its memo, which a fill reads the instance of where its tree reads the value.
				let fields = enumCase.values?.fields ?? []
				let use = SeamCarrierValues.level(ofEnum: scopeEnum.type).map { carrierValues.use(ofLevel: $0, count: fields.count) }
				var parameters = use?.structType(qualifiedBy: nil).map { [$0.asSource] } ?? []
				parameters += fields[(use?.extras ?? 0..<fields.count)].map { field in
					(field.memoType ?? field.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)).asSource
				}
				if enumCase.isLetChildOfCarrier(inSendableEnum: isSendable) {
					// A level the member hands no value, outside every loop of levels: the carrier holds the child carrier itself,
					// formed where this carrier is formed.
					members.append((enumCase.name, returnType, noScopeValue, true))
				} else {
					members.append((enumCase.name, "\(sendableAttribute)(\(parameters.joined(separator: ", "))) -> \(returnType)", noScopeValue, false))
				}
				ignoredArguments[enumCase.name] = parameters.isEmpty ? "" : "\(Array(repeating: "_", count: parameters.count).joined(separator: ", ")) in "
			} else {
				members.append((enumCase.name, "\(sendableAttribute)(\(enumCase.memberValuesTypeName ?? "")) -> \(returnType)", noScopeValue, false))
			}
		}
		var lines = [
			"\(indent)/// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.",
			carrierName.map { "\(indent)nonisolated public final class \($0)<\(builtTypeName)>\(isSendable ? ": Sendable" : "") {" }
				?? "\(indent)nonisolated public struct \(ReservedName.builderStructTypeName)<\(builtTypeName)>\(isSendable ? ": Sendable" : "") {",
		]
		// A member is named as its case, which is a label, so it is declared as a member's name is spelled: `Type` and
		// `Protocol` in backticks. No case is named `self`, which the memberwise initializer's parameter would hide the
		// instance behind: the macro requires an initializer parameter named as each dependency, and no initializer can
		// assign a property from a parameter named `self`.
		for member in members {
			lines.append("\(memberIndent)public let \(member.name.spelledAsMemberDeclarationName): \(member.type)")
		}
		lines.append("")
		lines.append("\(memberIndent)public init(\(members.map { "\($0.name): \($0.isLetChild ? "" : "@escaping ")\($0.type)" }.joined(separator: ", "))) {")
		for member in members {
			lines.append("\(bodyIndent)self.\(member.name) = \(member.name)")
		}
		lines.append("\(memberIndent)}")
		lines.append("")
		lines.append("\(memberIndent)public \(carrierName == nil ? "" : "convenience ")init(\(ReservedName.noScopeArgumentLabel) \(builderParameter): @escaping \(noScopeType.asSource)) {")
		if carrierName != nil {
			lines.append("\(bodyIndent)self.init(\(members.map { "\($0.name.spelledAsArgumentLabel): \($0.isLetChild ? $0.noScopeValue : "{ \(ignoredArguments[$0.name] ?? "")\($0.noScopeValue) }")" }.joined(separator: ", ")))")
		} else {
			for member in members {
				lines.append("\(bodyIndent)self.\(member.name) = { _ in \(member.noScopeValue) }")
			}
		}
		lines.append("\(memberIndent)}")
		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}

	/// The initializers a seam's module generates for the seam, followed by the enum every generated call refers to. Each
	/// tier has one only generated code calls, whose labels are prefixed, and which every generated call calls; when the
	/// seam's module sets `generatePlainDependencyTreeInitializers`, it is preceded by a plain one for people, whose
	/// parameters are values under readable labels and whose body forwards them. A tier's initializer only generated
	/// code calls passes `nil` for the parameters the tier omits and calls the next narrower tier's; the narrowest builds
	/// the tree and calls the seam's own initializer.
	func generateSeamRootCode(
		instantiable: Instantiable,
		seamRoot: SeamRoot,
		unavailableProperties: Set<Property>,
		propertiesGeneratedLater: Set<Property>,
		builderFunctionNames: BuilderFunctionNames,
		fillPlaceBindings: FillPlaceBindings,
	) async throws -> String {
		let signature = seamRoot.signature
		let typeName = instantiable.concreteInstantiable.asSource
		let initializerKeyword = "\(instantiable.declarationType == .classType ? "convenience " : "")init"
		let bodyIndent = "\(Self.standardIndent)\(Self.standardIndent)"
		// Every initializer carries the attributes a root's generated `init()` carries: a caller can reach any of them,
		// and each calls another.
		let attributesPrefix = instantiable.generatedInitializerAttributes.isEmpty ? "" : "\(instantiable.generatedInitializerAttributes) "
		// Every tier takes every builder, after its parameters: a hole is required. Each tier takes a builder under its own
		// label (`SeamSignature.Builder.narrowerTierLabels`). An initializer people call declares no underscored name, which
		// would keep it out of the module's symbol graph.
		func plainBuilderParameters(inTierAt tier: AccessLevel) -> [String] {
			signature.builders.map { "\($0.label(inTierAt: tier).spelledAsArgumentLabel): \($0.readableParameterType.asSource)" }
		}
		func generatedOnlyBuilderParameters(inTierAt tier: AccessLevel) -> [String] {
			signature.builders.map { builder in
				let label = builder.generatedOnlyArgumentLabel(inTierAt: tier)
				return "\(builder.internalName == label ? builder.internalName : "\(label) \(builder.internalName)"): \(builder.parameterType.asSource)"
			}
		}
		// No parameter has a default: every call writes every argument, so a hand-written call fails to compile when the
		// tree comes to take another parameter, rather than passing `nil` for it.
		func plainParameterList(of parameters: [SeamSignature.Parameter], inTierAt tier: AccessLevel) -> String {
			(parameters.map { $0.plainSpelling(amongTypesDeclaredEscaping: typesDeclaredEscaping) } + plainBuilderParameters(inTierAt: tier)).joined(separator: ", ")
		}
		func generatedOnlyParameterList(of parameters: [SeamSignature.Parameter], inTierAt tier: AccessLevel) -> String {
			(parameters.map { $0.generatedOnlySpelling(amongTypesDeclaredEscaping: typesDeclaredEscaping) } + generatedOnlyBuilderParameters(inTierAt: tier)).joined(separator: ", ")
		}
		// The narrowest tier holds each deferred parameter in a `LazilyInstantiated` under its label, which the tree reads
		// wherever it reads the label, in parameter order – except a parameter the seam's own alias of its label reads.
		let autoclosureCallByLabel = seamRoot.autoclosureCallByLabel(of: instantiable)
		let memoLines = signature.parameters.compactMap { parameter -> String? in
			guard case let .deferred(isSendable) = parameter.deferral, autoclosureCallByLabel[parameter.property.label] == nil else { return nil }
			let wrapperType = TypeDescription.simple(
				name: isSendable ? Dependency.sendableLazilyInstantiatedType : Dependency.lazilyInstantiatedType,
				generics: [parameter.property.typeDescription],
			)
			return "\(bodyIndent)let \(parameter.property.label) = \(wrapperType.asSource)(\(parameter.internalName))"
		}
		let tierParameters = signature.tiers.map(signature.parameters(ofTierAt:))
		var initializers = [String]()
		for (index, tier) in signature.tiers.enumerated() {
			let parameters = tierParameters[index]
			let body: String
			if index == signature.tiers.count - 1 {
				// The narrowest tier builds the tree, which reads each builder by its internal name, its parameter's name.
				let generatedProperties = try await generateProperties(
					propertiesGeneratedLater: propertiesGeneratedLater,
					enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
					leadingMemberWhitespace: bodyIndent,
					fillPlaceBindings: fillPlaceBindings,
				)
				let argumentList = try instantiable.generateArgumentList(
					unavailableProperties: unavailableProperties,
				)
				// A seam's root is hosted as its text until seam bodies are planned (`.claude/rules/emission-decisions.md`).
				var bodyLines = memoLines
				if !generatedProperties.isEmpty {
					bodyLines.append(GeneratedCode.lines(generatedProperties).spelled())
				}
				bodyLines.append("\(bodyIndent)self.init(\(argumentList))")
				body = bodyLines.joined(separator: "\n")
			} else {
				// A wider tier passes `nil` for each parameter it omits: one whose type the tier's callers cannot
				// see, which only a parameter received only if available can be. It passes a deferred parameter it takes
				// as its autoclosure's call, which the narrower tier's autoclosure defers in turn.
				let tierParameterSet = Set(parameters.map(\.property))
				let parameterArguments = tierParameters[index + 1].map { parameter in
					let value = if !tierParameterSet.contains(parameter.property) {
						"nil"
					} else if parameter.isDeferred {
						"\(parameter.internalName)()"
					} else {
						parameter.property.label
					}
					return "\(parameter.generatedOnlyArgumentLabel): \(value)"
				}
				let narrowerTier = signature.tiers[index + 1]
				let builderArguments = signature.builders.map { "\($0.generatedOnlyArgumentLabel(inTierAt: narrowerTier)): \($0.internalName)" }
				body = "\(bodyIndent)self.init(\((parameterArguments + builderArguments).joined(separator: ", ")))"
			}
			let marker = tier == .public
				? seamRoot.unreadTypeComment?.markerLine(namedBy: parameters.map(\.property.typeDescription) + signature.holes.map(\.property.typeDescription), indent: Self.standardIndent).map { "\($0)\n" }
				: nil
			// Each initializer has the type's isolation, or the one `generatedInitializerAttributes` spells, never the seam's own
			// initializer's: it builds the tree, whose isolation the own initializer, which only stores built values, does not
			// tell. A deliberate gap against the tree built in one module, where the caller's isolation builds it.
			let declarationPrefix = "\(Self.standardIndent)\(attributesPrefix)\(tier.spelledOnGeneratedDeclaration) \(initializerKeyword)"
			// A builder the caller passes can be held by a wrapper the seam builds, such as an instantiator, and called later.
			let plainDocumentation = if signature.builders.isEmpty {
				"\(Self.standardIndent)/// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained."
			} else {
				"\(Self.standardIndent)/// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns."
			}
			// A tier that takes no argument has one initializer, `init()`, which the two would both spell and which code of
			// either kind can call, whatever the setting. Otherwise the initializer only generated code calls points code
			// people write at the plain one above it where the module generates it, and at the setting where it does not.
			let takesNoArgument = parameters.isEmpty && signature.builders.isEmpty
			let generatedOnlyDocumentation = if takesNoArgument {
				"\(Self.standardIndent)/// Code you write and code SafeDI generates can both call this initializer."
			} else if seamRoot.generatesPlainInitializers {
				"""
				\(Self.standardIndent)/// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				\(Self.standardIndent)/// From code you write, call the initializer above instead.
				"""
			} else {
				"""
				\(Self.standardIndent)/// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				\(Self.standardIndent)/// To call this type from code you write, set `\(SafeDIConfigurationVisitor.generatePlainDependencyTreeInitializersArgumentLabel): true` in this module’s `#\(SafeDIConfigurationVisitor.macroName)`.
				"""
			}
			let generatedOnlyInitializer = """
			\(generatedOnlyDocumentation)
			\(declarationPrefix)(\(generatedOnlyParameterList(of: parameters, inTierAt: tier))) {
			\(body)
			\(Self.standardIndent)}
			"""
			if seamRoot.generatesPlainInitializers, !takesNoArgument {
				// The plain initializer forwards its values, so the closures the other one holds capture its own parameters
				// and never what its caller wrote.
				// A builder that takes nothing is handed to the generated-only initializer as a builder struct every member of which
				// calls it.
				let forwardedArguments = parameters.map { "\($0.generatedOnlyArgumentLabel): \($0.property.label)" }
					+ signature.builders.map { builder in
						let label = builder.label(inTierAt: tier)
						let argument = ".init(\(ReservedName.noScopeArgumentLabel): \(label))"
						return "\(builder.generatedOnlyArgumentLabel(inTierAt: tier)): \(argument)"
					}
				initializers.append("""
				\(marker ?? "")\(plainDocumentation)
				\(declarationPrefix)(\(plainParameterList(of: parameters, inTierAt: tier))) {
				\(bodyIndent)self.init(\(forwardedArguments.joined(separator: ", ")))
				\(Self.standardIndent)}
				""")
				initializers.append(generatedOnlyInitializer)
			} else {
				initializers.append((marker ?? "") + generatedOnlyInitializer)
			}
		}
		// The scope types of the seam's builders before the initializers that build them. A case's forwarded value is as
		// visible as the enum, which is spelled `public` but is no wider than the seam.
		let scopeTypes = Self.ownScopeTypeDeclarations(
			builders: signature.builders,
			scopeEnums: signature.scopeEnums,
			holes: signature.holes,
			typesDeclaredEscaping: typesDeclaredEscaping,
			unreadTypeComment: seamRoot.unreadTypeComment,
			namesForwardedTypes: signature.tiers.first == .public,
		)
		// The class each of the tree's boxes is, after the initializers, in the order of their names (`boxedLoops`).
		var members = scopeTypes + initializers
		for (_, declaration) in loopLevelsTypesInTree.sorted(by: { $0.key < $1.key }) {
			members.append(declaration)
		}
		return """
		extension \(typeName) {
		\(members.joined(separator: "\n\n"))
		}

		\(Self.guardEnumDeclaration(extending: typeName, named: signature.guardTypeName))
		"""
	}
}
