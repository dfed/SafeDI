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

extension ScopeGenerator {
	/// The levels of a seam's builder, built from one builder with no scope, by the code that needs them: every member of
	/// every level calls the one builder, as a seam's plain initializer hands it the builder a person wrote, and a call that
	/// passes up nothing hands a builder that returns `nil` for places only if available that nothing fulfills.
	///
	/// A seam's levels declare only their memberwise initializer: a fallback on every level cost every seam module 3 to 9%
	/// of its compile, though almost nothing calls it. So the code that needs such a level declares, where it needs it, one
	/// local function per level its builder reaches, the levels of another module's seam included, each building its level
	/// memberwise and calling the functions of the levels it holds; a level in a loop of levels calls itself. Being local,
	/// no other code sees the functions, and nothing resolves an overload. A public mock's structs keep their
	/// `init(__safeDI_noScope:)`, which every call of the mock reads, and which `memberArgumentsWithoutScope` spells too.
	///
	/// Holds the enums it was made from, by key, and the forms of their levels, for as long as the code that builds the
	/// levels is generated.
	struct LevelsWithoutScope {
		/// The levels of `scopeEnums`: every enum a seam's builders reach, its own and those of the seams it calls.
		init(scopeEnums: [SeamSignature.ScopeEnum]) {
			self.scopeEnums = scopeEnums
			enumsByKey = Dictionary(scopeEnums.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
			calledRootsTakingValue = Self.calledRootsTakingValue(amongEnumsOf: scopeEnums, filledBy: scopeEnums)
			carrierValuesBySeam = SeamCarrierValues.bySeam(of: scopeEnums)
		}

		/// The local functions that build the levels reached from `roots`, each level once, in the order a walk from the roots
		/// first reaches them, indented by `indent`.
		mutating func functionDeclarations(reachedFrom roots: [SeamSignature.ScopeEnum.Key], indent: String) -> [String] {
			var declarations = [String]()
			var visitedKeys = Set<SeamSignature.ScopeEnum.Key>()
			var keysToVisit = Array(roots.reversed())
			while let key = keysToVisit.popLast() {
				guard visitedKeys.insert(key).inserted, let scopeEnum = enumsByKey[key] else { continue }
				declarations.append(functionDeclaration(of: scopeEnum, indent: indent))
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
				keysToVisit += heldKeys.reversed()
			}
			return declarations
		}

		/// The call of the function that builds the level of `key` from `builder`.
		func call(ofLevel key: SeamSignature.ScopeEnum.Key, handing builder: String) -> String {
			Self.call(ofLevel: key, in: enumsByKey, handing: builder)
		}

		/// The local function that builds `scopeEnum`'s level memberwise from one builder. It is `@Sendable` and
		/// `nonisolated`, since a member of a `@Sendable` level calls the function of the level it holds, and a level is
		/// `nonisolated`.
		private mutating func functionDeclaration(of scopeEnum: SeamSignature.ScopeEnum, indent: String) -> String {
			let builtTypeName = ReservedName.builderStructGenericParameterName
			let builderParameter = ReservedName.noScopeParameterName
			let holeType = scopeEnum.key.holeType
			var forms = levelForms[holeType] ?? LevelBuilderForms(enumsOfHoleType: scopeEnums.filter { $0.key.holeType == holeType })
			let builderType = Self.builderType(ofLevel: scopeEnum.key, levelForms: &forms)
			let levelType = ReservedName.levelType(ofEnum: scopeEnum.type, built: .simple(name: builtTypeName, generics: []))
			let enumsByKey = enumsByKey
			let arguments = Self.memberArgumentsWithoutScope(
				of: scopeEnum,
				levelForms: &forms,
				calledRootsTakingValue: calledRootsTakingValue,
				carrierValues: carrierValuesBySeam[scopeEnum.key.seamType] ?? SeamCarrierValues(),
				builder: builderParameter,
				building: { key, builder in Self.call(ofLevel: key, in: enumsByKey, handing: builder) },
				buildingCalledRoot: { innerKey, takesValue, fillLevel in Self.call(ofLevel: innerKey, in: enumsByKey, handing: "{ \(takesValue ? "_ in " : "")\(fillLevel) }") },
			)
			levelForms[holeType] = forms
			return """
			\(indent)@Sendable nonisolated func \(Self.functionName(ofLevel: scopeEnum.key, in: enumsByKey))<\(builtTypeName)>(_ \(builderParameter): @escaping \(builderType.asSource)) -> \(levelType.asSource) {
			\(indent)\(standardIndent).init(\(arguments.joined(separator: ", ")))
			\(indent)}
			"""
		}

		private static func call(ofLevel key: SeamSignature.ScopeEnum.Key, in enumsByKey: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum], handing builder: String) -> String {
			"\(functionName(ofLevel: key, in: enumsByKey))(\(builder))"
		}

		private static func functionName(ofLevel key: SeamSignature.ScopeEnum.Key, in enumsByKey: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]) -> String {
			ReservedName.levelWithoutScopeFunctionName(ofEnum: enumsByKey[key]?.type ?? key.seamType)
		}

		private let scopeEnums: [SeamSignature.ScopeEnum]
		private let enumsByKey: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]
		private let calledRootsTakingValue: Set<SeamSignature.ScopeEnum.Key>
		private let carrierValuesBySeam: [TypeDescription: SeamCarrierValues]
		private var levelForms = [SeamSignature.HoleType: LevelBuilderForms]()

		/// The type of the builder a level of `key` is built from: the one a person writes for the places at and beneath the
		/// level, in the level's own family (`DependencyTreeGenerator.builderForm(ofPlaces:)`), over `Built`, or in the
		/// `@Sendable` family where the level hands it to a level that takes a `@Sendable` one
		/// (`LevelBuilderForms.takesSendableBuilder(atLevel:)`).
		static func builderType(ofLevel key: SeamSignature.ScopeEnum.Key, levelForms: inout LevelBuilderForms) -> TypeDescription {
			let builtType = TypeDescription.simple(name: ReservedName.builderStructGenericParameterName, generics: [])
			let takesSendableBuilder = levelForms.takesSendableBuilder(atLevel: key)
			if let forwarded = levelForms.form(ofLevel: key).forwardedValue {
				return DependencyTreeGenerator.erasedBuilderType(forwarding: forwarded, returning: builtType, isSendable: takesSendableBuilder)
			} else if takesSendableBuilder {
				return TypeDescription.closure(arguments: [], isAsync: false, doesThrow: false, returnType: builtType).asSendableFunction
			} else {
				return TypeDescription.closure(arguments: [], isAsync: false, doesThrow: false, returnType: builtType)
			}
		}

		/// The type a member of `enumCase`'s level returns, over `built`: what the place builds – for a place held in an
		/// instantiator, the erased wrapper's `Builder` over what the place forwards, `()` for nothing, since the constrained
		/// wrappers cannot be spelled over `Built` – or the level of the enum the case holds, which for a call's case for a
		/// builder it fills is the called seam's level over the level of what the fill builds.
		static func memberReturnType(of enumCase: SeamSignature.ScopeEnum.Case, inSendableEnum isSendable: Bool, built builtType: TypeDescription) -> TypeDescription {
			switch enumCase.kind {
			case let .place(sites):
				if let place = sites.first?.path.last, place.propertyType.isAnyInstantiator {
					let forwarded = place.typeDescription.forwardedTypeOfWrapper?.strippingEscaping ?? .void(.tuple)
					return DependencyTreeGenerator.erasedBuilderType(forwarding: forwarded, returning: builtType, isSendable: isSendable)
				} else {
					return builtType
				}
			case let .fill(_, innerEnumType?, _, enumType, _):
				return ReservedName.levelType(ofEnum: innerEnumType, built: ReservedName.levelType(ofEnum: enumType, built: builtType))
			case let .nested(_, enumType, _),
			     let .inner(_, enumType, _),
			     let .fill(_, _, _, enumType, _):
				return ReservedName.levelType(ofEnum: enumType, built: builtType)
			}
		}

		/// The arguments of the memberwise initializer of `scopeEnum`'s level that make every member call `builder`: a place's
		/// member calls it, or hands it to the instantiator, adapted to take what the place forwards where the level's builder
		/// takes nothing; a member that holds a level hands that level, `building` it from the builder adapted so, or, for a
		/// call's case for a builder it fills, the called seam's root built by `buildingCalledRoot` from a builder that builds
		/// the fill's level (taking the value the called root's builder is handed where it takes one). A member that is a
		/// closure ignores what it is handed.
		static func memberArgumentsWithoutScope(
			of scopeEnum: SeamSignature.ScopeEnum,
			levelForms: inout LevelBuilderForms,
			calledRootsTakingValue: Set<SeamSignature.ScopeEnum.Key>,
			carrierValues: SeamCarrierValues,
			builder builderParameter: String,
			building: (SeamSignature.ScopeEnum.Key, String) -> String,
			buildingCalledRoot: (SeamSignature.ScopeEnum.Key, Bool, String) -> String,
		) -> [String] {
			let isSendable = scopeEnum.key.isSendable
			let isCarrier = ReservedName.seamCarrier(ofEnum: scopeEnum.type) != nil
			let levelForwardsValue = levelForms.form(ofLevel: scopeEnum.key).forwardedValue != nil
			/// The builder, adapted to a member or a level beneath that takes a value where this level's takes nothing.
			func builder(adaptedToForwarding forwards: Bool) -> String {
				!levelForwardsValue && forwards ? "{ _ in \(builderParameter)() }" : builderParameter
			}
			var arguments = [String]()
			for enumCase in scopeEnum.cases {
				let value: String
				switch enumCase.kind {
				case let .place(sites):
					if let place = sites.first?.path.last, place.propertyType.isAnyInstantiator {
						value = builder(adaptedToForwarding: true)
					} else {
						value = "\(builderParameter)()"
					}
				case let .fill(innerKey, _?, enumKey, _, _):
					let fillLevel = building(enumKey, builder(adaptedToForwarding: levelForms.form(ofLevel: enumKey).forwardedValue != nil))
					value = buildingCalledRoot(innerKey, calledRootsTakingValue.contains(innerKey), fillLevel)
				case let .nested(enumKey, _, _),
				     let .inner(enumKey, _, _),
				     let .fill(_, _, enumKey, _, _):
					value = building(enumKey, builder(adaptedToForwarding: levelForms.form(ofLevel: enumKey).forwardedValue != nil))
				}
				let ignoredArguments: String
				if isCarrier {
					if enumCase.isLetChildOfCarrier(inSendableEnum: isSendable) {
						arguments.append("\(enumCase.name.spelledAsArgumentLabel): \(value)")
						continue
					}
					let count = enumCase.values?.fields.count ?? 0
					let use = SeamCarrierValues.level(ofEnum: scopeEnum.type).map { carrierValues.use(ofLevel: $0, count: count) }
					let parameterCount = (use?.structEnd == nil ? 0 : 1) + (use?.extras ?? 0..<count).count
					ignoredArguments = parameterCount == 0 ? "" : "\(Array(repeating: "_", count: parameterCount).joined(separator: ", ")) in "
				} else {
					ignoredArguments = "_ in "
				}
				arguments.append("\(enumCase.name.spelledAsArgumentLabel): { \(ignoredArguments)\(value) }")
			}
			return arguments
		}

		/// The called seams' root enums, among `reachedEnums`, whose level takes a builder that takes a value, of those a case of
		/// `fillingEnums` for a builder it fills holds: every place such a root reaches is held in an instantiator that forwards
		/// a value (`DependencyTreeGenerator.builderForm(ofPlaces:)`), whose property ends the place's site path. Found once,
		/// never once for each case.
		static func calledRootsTakingValue(amongEnumsOf reachedEnums: [SeamSignature.ScopeEnum], filledBy fillingEnums: [SeamSignature.ScopeEnum]) -> Set<SeamSignature.ScopeEnum.Key> {
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
	}
}
