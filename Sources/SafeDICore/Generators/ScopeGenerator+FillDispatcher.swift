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
	/// A level of a seam's or a public mock's tree a caller generates a function for, which returns the level's builder
	/// struct: each member hands its case to the fill of its place or the function of the level it leads to. A cycle of
	/// levels is ordinary mutual recursion. A public mock's caller declares its level functions through
	/// `PublicMockLevelFunctions`, which fills some places of a level and passes the others up.
	///
	/// Over an enum nested by type, a case carries what its type binds before the case's property, and the fill or
	/// dispatcher it hands its value to may read a value a type further out binds: that one takes it as a parameter, which
	/// each case that leads to it passes from its own payload, or, where its payload does not hold it, from the dispatcher's
	/// own parameter, so the value read is the one the nearest type on the actual route binds, as inline. The root
	/// dispatcher, which the builder is, takes none: a value no type on the route binds is the caller's own declaration of
	/// it, in scope where the dispatchers are declared. The parameters are found when the code is generated, from what the
	/// fills read (`dispatcherParameters(of:fillReads:)`), a fixed point over the enums, which can recurse.
	///
	/// A public mock's caller decides per route (`decidesPerRoute`) when its code is generated: each route hands a fill the
	/// value nearest the place, or the caller's where no level on the route binds one (`PublicMockLevelFunctions`), so
	/// every route of a filled place fills it.
	struct FillDispatcher: Sendable {
		struct Case: Sendable {
			let name: String
			/// Whether a place's case carries a payload struct, which every case does but one of a `@Sendable` enum nested by
			/// type, whose place is held in a `Sendable` wrapper.
			var carriesPayload = true
			let hasForwardedValue: Bool
			/// For a place's case of a level on a carried route, whether the place is held in an instantiator, so the case's member
			/// returns the builder the wrapper keeps over the struct of the fill's level, which takes the forwarded value.
			var returnsWrapperBuilder = false
			/// The fill or dispatcher the case is handed to, or `nil` when every place it reaches is passed up: in a seam's call,
			/// whose dispatcher then hands the case to `passUp`. A call of another module's public mock passes no place up by
			/// route: it declares level functions only for the builders it fills, every place of each (`PublicMockLevelFunctions`).
			let target: Target?
			/// What the case carries before the value it hands on, in an enum nested by type: the fields of its payload.
			var values: [SeamSignature.Hole.Field]?
			/// For a call's case for a builder it fills (`SeamSignature.ScopeEnum.Case.Kind.fill`), whether the case carries the
			/// scope value the inner seam handed the fill, before the value it hands on, and the key of that value's enum, which a
			/// reader reads a value its target takes from (`InnerScopeReaders`).
			var isFillCase = false
			var carriedInnerKey: SeamSignature.ScopeEnum.Key?
			/// The labels the case's type binds from the case's property on, in an enum nested by type, which hide every value
			/// of the label a type further out binds (`SeamSignature.ScopeEnum.Values.labelsBoundLater`).
			let labelsBoundLater: Set<String>
			/// Whether the case's level is a carrier's `let` child (`SeamSignature.ScopeEnum.Case.isLetChildOfCarrier`), which the
			/// caller's carrier is formed with, not a closure that forms it.
			var isLetChild = false
			/// How a member of a seam's carrier takes the case's values (`SeamCarrierValues`): the struct of the run they end,
			/// then each value after it; `nil` where the case's values travel positionally or as a payload struct.
			var carrierUse: SeamCarrierValues.Use?

			/// Whether the case's enum is of a seam the called seam calls, which binds the case's deferred parameters from a
			/// call of its own: their memo holds what that call passed, which no declaration of the caller's is.
			var carriesDeferredFields = false

			/// The labels the case hands on from its payload: every field but one bound from a deferred parameter of the
			/// called seam, whose memo inline never reads where the caller's own declaration is in scope.
			var carriedLabels: Set<String> {
				Set((values ?? []).filter { carriesDeferredFields || !$0.isDeferredParameter }.map(\.property.label))
			}

			/// Whether the case hands on, from its payload, `field`, a form a target takes of a label of `carriedLabels`: every
			/// form but, for a deferred parameter's field, which holds the value and its memo, a wrapper a type further out
			/// declares of the label, which a target that reads only that wrapper takes as the place's field
			/// (`ScopeGenerator.fillLabelsReadOnlyAsPlaceField`), handed on from further out, as inline reads that declaration.
			func handsOn(_ field: SeamSignature.Hole.Field) -> Bool {
				guard let carried = values?.first(where: { $0.property.label == field.property.label }), carried.isDeferredParameter else { return true }
				return field.bindsMemo || field.property.asUnwrappedProperty == carried.property.asUnwrappedProperty
			}

			struct Target: Sendable {
				let name: String
				let key: String
				/// Whether the target is a dispatcher that takes `passUp`.
				let takesPassUp: Bool
				/// For a level function an enclosing call declares, which a call inside its fill reuses by name, the structs it
				/// takes (`FillDispatcher.carriedInnerScopes`): this call's level function hands it its own struct of each type
				/// under the reused function's name for it. Empty for every other target.
				var reusedCarriedInnerScopes = [CarriedInnerScope]()
			}
		}

		let key: String
		let functionName: String
		let enumType: TypeDescription
		let returnType: TypeDescription
		let isSendableFamily: Bool
		/// Whether a place the enum reaches is passed up, which the dispatcher hands to `passUp`.
		let takesPassUp: Bool
		var cases: [Case]
		/// Whether the enum is nested in a root enum, so the dispatcher can take what the types further out bind.
		var takesValuesOfOuterTypes = false
		/// The seam whose extension declares the enum.
		var seamType: TypeDescription?
		/// For the dispatcher of a seam's root enum, the name of the scope value it is handed where a fill it leads to takes
		/// that value (`SeamHoles.innerScope(at:innerKey:)`): the dispatcher's parameter is named so, and every dispatcher and
		/// fill it leads to takes the value under it.
		var innerScopeName: String?
		/// Whether the call is of a public mock, whose caller declares a level function per level and per set of values its
		/// routes bind (`PublicMockLevelFunctions`).
		var decidesPerRoute = false
		/// Whether the enum declares a builder struct the dispatcher returns, as one function per level of the seam's tree
		/// (`structDeclaration`), rather than switching over the enum: where the called seam takes the builder struct and no
		/// case of the calling seam carries the scope value the call hands its fills (`SeamHoles.innerScope(at:innerKey:)`),
		/// which its dispatchers, in their enum form, pass on.
		var returnsBuilderStruct = false
		/// For a level function of a seam's builder struct on the route to a place inside a fill of the call, one per hole type
		/// and family of the calling seam whose places the fill holds, in the order of their names
		/// (`SeamHoles.innerScopes(at:innerKey:)`): the name and type of the parameter each fill there takes the struct of its
		/// own level under, and the name the function takes the struct of its level that the caller's member for the call's case
		/// returns under, claimed by the call's allocator apart from every name in scope there. The function hands each level
		/// beneath it, and each fill, what that struct's member returns.
		var carriedInnerScopes = [CarriedInnerScope]()

		struct CarriedInnerScope: Sendable {
			let name: String
			let type: TypeDescription
			let upName: String
		}

		/// The parameters each dispatcher of `dispatchers` takes, by key, labeled and typed as the fields they pass on, in the
		/// order of their labels, given the fields each fill reads that its case's payload may not carry, by the fill's key.
		/// Found as a fixed point: a dispatcher takes each value a case's target reads that the case's payload does not
		/// carry, and a root dispatcher takes none.
		///
		/// A dispatcher takes a label once per form its targets take of it, transitively, so each target is handed the label in
		/// its own form, as the root dispatcher hands it (`ScopeGenerator.FillCallerReads`): two places of one hole type, one
		/// beneath a type that binds the label lazily and one beneath a type that binds it by value, each take their own form
		/// of a level that binds none above them. An optional form whose unwrapped form a target takes too is taken as that
		/// form, since every route that reaches such a target hands it a value that is no optional. Nothing is chosen among
		/// forms, so none depends on the order the enums are met in. A form some target takes as a deferred parameter's memo
		/// (`Field.bindsMemo`) is taken as the memo (`handsForm(_:inPlaceOf:)`), which the dispatcher hands a target that takes
		/// the value as its instance (`structDeclaration`). Two forms of one label are named apart (`parameterNames(of:)`).
		static func dispatcherParameters(of dispatchers: [FillDispatcher], fillReads: [String: [SeamSignature.Hole.Field]]) -> [String: [SeamSignature.Hole.Field]] {
			var formsByLabelByKey = [String: [String: [Property: SeamSignature.Hole.Field]]]()
			for (key, fields) in fillReads {
				for field in fields {
					formsByLabelByKey[key, default: [:]][field.property.label, default: [:]][field.property] = field
				}
			}
			var changed = true
			while changed {
				changed = false
				for dispatcher in dispatchers where dispatcher.takesValuesOfOuterTypes {
					for dispatcherCase in dispatcher.cases {
						guard let target = dispatcherCase.target else { continue }
						let carried = dispatcherCase.carriedLabels
						for (label, forms) in formsByLabelByKey[target.key, default: [:]] {
							for (property, field) in forms where !carried.contains(label) || !dispatcherCase.handsOn(field) {
								guard Self.handsForm(field, inPlaceOf: formsByLabelByKey[dispatcher.key]?[label]?[property]) else { continue }
								formsByLabelByKey[dispatcher.key, default: [:]][label, default: [:]][property] = field
								changed = true
							}
						}
					}
				}
			}
			var parametersByKey = [String: [SeamSignature.Hole.Field]]()
			for dispatcher in dispatchers where dispatcher.takesValuesOfOuterTypes {
				guard let formsByLabel = formsByLabelByKey[dispatcher.key] else { continue }
				parametersByKey[dispatcher.key] = formsByLabel.keys.sorted().flatMap { label in
					let forms = formsByLabel[label, default: [:]]
					return forms.keys.sorted().compactMap { property in
						Self.unwrappedForm(of: property, among: forms) == nil ? forms[property] : nil
					}
				}
			}
			return parametersByKey
		}

		/// The form of `property`'s label among `forms` that a dispatcher takes in its place: the unwrapped form of an optional
		/// `property`, where `forms` holds it, else `nil`.
		private static func unwrappedForm(of property: Property, among forms: [Property: some Any]) -> Property? {
			guard property.typeDescription.isOptional else { return nil }
			let unwrapped = Property(label: property.label, typeDescription: property.typeDescription.unwrapped)
			return forms[unwrapped] == nil ? nil : unwrapped
		}

		/// The parameter of `parameters`, a dispatcher's, that hands `parameter`, a target's: the one of its form, or of its
		/// unwrapped form, which the dispatcher takes in place of an optional one (`dispatcherParameters(of:fillReads:)`).
		static func parameter(handing parameter: SeamSignature.Hole.Field, among parameters: [SeamSignature.Hole.Field]) -> SeamSignature.Hole.Field? {
			let formsOfLabel = Dictionary(parameters.filter { $0.property.label == parameter.property.label }.map { ($0.property, $0) }) { first, _ in first }
			return formsOfLabel[Self.unwrappedForm(of: parameter.property, among: formsOfLabel) ?? parameter.property]
		}

		/// The name each of `parameters`, a function's, is declared and passed under, by its property: its label, where no
		/// other parameter has that label, else the label and its type (`token_LazilyInstantiated__Token`), with `_` appended
		/// while another parameter has that name.
		static func parameterNames(of parameters: [SeamSignature.Hole.Field]) -> [Property: String] {
			let labelCounts = Dictionary(parameters.map { ($0.property.label, 1) }, uniquingKeysWith: +)
			var names = [Property: String]()
			var usedNames = Set(parameters.map(\.property.label).filter { labelCounts[$0] == 1 })
			for parameter in parameters {
				if labelCounts[parameter.property.label] == 1 {
					names[parameter.property] = parameter.property.label
				} else {
					var name = "\(parameter.property.label)_\(parameter.property.typeDescription.asIdentifier)"
					while usedNames.contains(name) {
						name += "_"
					}
					usedNames.insert(name)
					names[parameter.property] = name
				}
			}
			return names
		}

		/// Whether a dispatcher takes `field`, a form a target takes, in place of `existing`, the field of the same property it
		/// takes so far: a memo in place of the value, and a `SendableLazilyInstantiated` in place of a `LazilyInstantiated`. A
		/// target takes a `SendableLazilyInstantiated` only where every route that hands a memo hands it one, and another route
		/// a value only where its tree reads that wrapper too (`memosHanded(toFillOf:labels:readingSendableWrapper:among:)`), so
		/// a dispatcher on its routes is handed one too, or a value it makes one of, which it hands a target that takes the other
		/// as a memo of its own (`structDeclaration`). The order makes the form independent of the order the targets are met in.
		private static func handsForm(_ field: SeamSignature.Hole.Field, inPlaceOf existing: SeamSignature.Hole.Field?) -> Bool {
			guard let existing else { return true }
			return field.bindsMemo && (!existing.bindsMemo || (field.deferral == .deferred(isSendable: true) && existing.deferral != .deferred(isSendable: true)))
		}

		/// The memo a fill takes of a label some route hands it as the memo of a deferred parameter a level on a carried route
		/// holds (see `memosHanded(toFillOf:labels:readingSendableWrapper:among:)`): the form of that parameter, and its deferral.
		struct HandedMemo: Hashable {
			let property: Property
			let deferral: SeamSignature.Parameter.Deferral
		}

		/// A route that hands a fill the `LazilyInstantiated` memo of a seam's deferred parameter: the seam whose enum's case
		/// carries it, and the type in that seam's tree that receives the parameter, which reads it outside a `@Sendable`
		/// function, with its property and where it receives it.
		struct PlainMemoRoute: Hashable, Sendable {
			let seamType: TypeDescription
			let receivingType: TypeDescription
			let receivedProperty: Property
			let receivedAt: Dependency.DeclarationLocation?
		}

		/// What `memosHanded(toFillOf:labels:readingSendableWrapper:among:)` finds: the memo the fill takes of each label, and,
		/// for each label it takes a `LazilyInstantiated` of while its tree reads the label as a `SendableLazilyInstantiated`
		/// of the memo's form too, the routes that hand a seam's `LazilyInstantiated`, in the order of their seams' names, then
		/// where each receives the value.
		struct HandedMemos {
			var memoByLabel = [String: HandedMemo]()
			var plainMemoRoutesOfSendableWrapperReads = [String: [PlainMemoRoute]]()
			/// By each label of `memoByLabel`, the deferred parameters whose memos the routes hand, in the order the routes are
			/// met: which seam's error validation reports first is decided by where the seam is declared.
			var memoOriginsByLabel = [String: [SeamSignature.Hole.Field.SeamParameterOrigin]]()
		}

		/// What the routes to a fill or dispatcher hand of one label: the memos of deferred parameters levels on carried routes
		/// hold, the routes among them that hand a `LazilyInstantiated`, and whether a route hands the value instead.
		private struct HandedForms: Equatable {
			var memos = Set<HandedMemo>()
			var plainMemoRoutes = Set<PlainMemoRoute>()
			/// The seams whose deferred parameters the memos are, in the order the routes are first met, which only grows.
			var memoSeamTypes = [TypeDescription]()
			var handsValue = false

			mutating func formUnion(_ other: HandedForms) {
				memos.formUnion(other.memos)
				plainMemoRoutes.formUnion(other.plainMemoRoutes)
				memoSeamTypes += other.memoSeamTypes.filter { !memoSeamTypes.contains($0) }
				handsValue = handsValue || other.handsValue
			}
		}

		/// The memo the fill of `fillKey` takes, by each label among `labels` some route of `dispatchers` hands it as a memo: on
		/// a route, the nearest case that carries the label hands the memo where it is a case of a level on a carried route
		/// (`Case.carriesDeferredFields`) whose field of it is a deferred parameter's, and the value where it carries the label
		/// by value; a route on which no case carries it hands the value too, the caller's declaration, which the root
		/// dispatcher reads. Where every route hands one memo, the fill takes it; where routes hand memos that differ in
		/// deferral or optionality, or a route hands the value, the fill takes a `LazilyInstantiated`, of the optional form
		/// where the memos' forms differ in optionality, which each route makes of what it hands where that is another form
		/// (`structDeclaration`), so the value is created where the fill's tree reads it on every route, as inline. A label no
		/// route hands as a memo is left out, and so is one whose memos differ in more than optionality, which no one memo
		/// type holds: the fill takes the value. Found as a fixed point over the dispatchers, which can recurse: a route that comes back to a dispatcher already
		/// on it hands what that dispatcher's other routes hand.
		///
		/// Where the fill's tree also reads the label as a `SendableLazilyInstantiated` of the memo's form
		/// (`readingSendableWrapper`, by that wrapper's instance property) and every route that hands a memo hands that one, the
		/// fill takes it although another route hands the value, which that route makes the memo of: the caller's declaration of
		/// the wrapper itself at the root dispatcher (`FillCallerReads.memoArgumentByMemo`). So the tree reads the wrapper where
		/// it reads the wrapper and its instance where it reads the value, as inline reads one declaration both ways; a
		/// `LazilyInstantiated` it would take instead is no `SendableLazilyInstantiated`. Where a route hands a seam's
		/// `LazilyInstantiated` instead, which no `@Sendable` function can capture, the fill takes a `LazilyInstantiated`, and those
		/// routes are found too (`HandedMemos.plainMemoRoutesOfSendableWrapperReads`), which validation reports.
		static func memosHanded(toFillOf fillKey: String, labels: Set<String>, readingSendableWrapper: [String: Property], among dispatchers: [FillDispatcher]) -> HandedMemos {
			var casesByTargetKey = [String: [(dispatcher: FillDispatcher, dispatcherCase: Case)]]()
			for dispatcher in dispatchers {
				for dispatcherCase in dispatcher.cases {
					if let target = dispatcherCase.target {
						casesByTargetKey[target.key, default: []].append((dispatcher, dispatcherCase))
					}
				}
			}
			let keys = [fillKey] + dispatchers.map(\.key)
			var handedMemos = HandedMemos()
			// A seam has one parameter of a label, so its seam names each memo's parameter.
			var memoOriginBySeamType = [TypeDescription: SeamSignature.Hole.Field.SeamParameterOrigin]()
			for label in labels {
				// What the routes to each node hand so far, which only grows.
				var handedByKey = [String: HandedForms]()
				var changed = true
				while changed {
					changed = false
					for key in keys {
						// A node no case leads to is handed nothing this call's dispatchers carry.
						var handed = HandedForms(handsValue: casesByTargetKey[key] == nil)
						for (dispatcher, dispatcherCase) in casesByTargetKey[key] ?? [] {
							if dispatcherCase.carriedLabels.contains(label) {
								if dispatcherCase.carriesDeferredFields, let field = dispatcherCase.values?.first(where: { $0.property.label == label && $0.isDeferredParameter }) {
									handed.memos.insert(HandedMemo(property: field.property, deferral: field.deferral))
									if let origin = field.seamParameterOrigin, !handed.memoSeamTypes.contains(origin.seamType) {
										handed.memoSeamTypes.append(origin.seamType)
										memoOriginBySeamType[origin.seamType] = origin
									}
									if field.deferral == .deferred(isSendable: false), let seamType = dispatcher.seamType {
										handed.plainMemoRoutes.insert(PlainMemoRoute(seamType: seamType, receivingType: field.declaringType, receivedProperty: field.property, receivedAt: field.declarationLocation))
									}
								} else {
									handed.handsValue = true
								}
							} else if dispatcher.takesValuesOfOuterTypes {
								handed.formUnion(handedByKey[dispatcher.key] ?? HandedForms())
							} else {
								// The root dispatcher hands the caller's declaration.
								handed.handsValue = true
							}
						}
						if handedByKey[key] != handed {
							handedByKey[key] = handed
							changed = true
						}
					}
				}
				// Memos whose forms differ only in optionality are taken in the optional form, which each of them provides.
				guard let handed = handedByKey[fillKey],
				      let memo = handed.memos.first,
				      handed.memos.allSatisfy({ $0.property.asUnwrappedProperty == memo.property.asUnwrappedProperty }),
				      let property = handed.memos.allSatisfy({ $0.property == memo.property }) ? memo.property : handed.memos.first(where: { $0.property.typeDescription.isOptional })?.property
				else { continue }
				let takesSendableWrapperReadToo = readingSendableWrapper[label] == memo.property && memo.deferral == .deferred(isSendable: true)
				let takenMemo = handed.memos.count == 1 && (!handed.handsValue || takesSendableWrapperReadToo) ? memo : HandedMemo(property: property, deferral: .deferred(isSendable: false))
				handedMemos.memoByLabel[label] = takenMemo
				handedMemos.memoOriginsByLabel[label] = handed.memoSeamTypes.compactMap { memoOriginBySeamType[$0] }
				if takenMemo.deferral == .deferred(isSendable: false), readingSendableWrapper[label] == takenMemo.property.asUnwrappedProperty, !handed.plainMemoRoutes.isEmpty {
					handedMemos.plainMemoRoutesOfSendableWrapperReads[label] = handed.plainMemoRoutes.sorted { lhs, rhs in
						lhs.seamType.asSource < rhs.seamType.asSource || (lhs.seamType.asSource == rhs.seamType.asSource && [lhs.receivedAt].lexicographicallyPrecedes([rhs.receivedAt], by: Dependency.DeclarationLocation.precedesInSourceOrder))
					}
				}
			}
			return handedMemos
		}

		/// What identifies a dispatcher among the fills and dispatchers enclosing a call.
		/// - Parameter returnsBuilderStruct: Whether the dispatcher is one that returns the enum's builder struct
		///   (`returnsBuilderStruct`), which a call passes by calling it, and which is never one a call that hands the enum's
		///   cases on shares: each is declared apart.
		static func key(of enumKey: SeamSignature.ScopeEnum.Key, returnsBuilderStruct: Bool = false) -> String {
			"dispatcher \(enumKey.spelling)\(returnsBuilderStruct ? " returning its builder struct" : "")"
		}

		/// A dispatcher of an enum, for the routes of one family's root enum, or `nil` for one that serves every route that
		/// reaches the enum (see `dispatchers(of:filledSites:enclosingDispatchers:builderKeysDispatchedOverTheEnum:fillNames:names:innerScopeNameByKey:carriedInnerScopesByKey:decidesPerRoute:)`).
		struct Instance: Hashable {
			let enumKey: SeamSignature.ScopeEnum.Key
			/// Whether the routes are the `@Sendable` root enum's, where the instance serves one family.
			let family: Bool?
			/// Whether the dispatcher returns the enum's builder struct (`FillDispatcher.returnsBuilderStruct`).
			let returnsBuilderStruct: Bool

			/// The key that identifies the dispatcher: the enum's.
			var dispatcherKey: String {
				FillDispatcher.key(of: enumKey, returnsBuilderStruct: returnsBuilderStruct)
			}
		}

		/// The dispatchers a call that passes `calledBuilders` and fills the places of `filledSites` declares, in the order
		/// its arguments first reach them with an explicit stack: one for each enum that reaches a filled place, which no
		/// enclosing call declares.
		///
		/// A public mock's caller passes up a place it does not fill, so a dispatcher that reaches one takes `passUp`. The plain
		/// and the `@Sendable` root enum of a hole type hold the same enums nested by type, but each one's routes reach only its
		/// own places (`CalledBuilders.sitesReachedOnItsRoutes(by:in:)`). A caller fills every place of a hole type of a call or
		/// none (`DependencyTreeGenerator.holesFilled(byCallsOf:in:)`), so an enum both roots reach is filled on both roots'
		/// routes alike, and one dispatcher serves both.
		/// - Parameters:
		///   - enclosingCarriedInnerScopes: The structs each level function of `enclosingDispatchers` takes, by its key.
		///   - decidesPerRoute: Whether the call is of a public mock (see `FillDispatcher.decidesPerRoute`).
		static func dispatchers(
			of calledBuilders: CalledBuilders,
			filledSites: Set<SeamSignature.Hole.Site>,
			enclosingDispatchers: [String: String],
			fillNames: [String: String],
			names: inout GeneratedNameAllocator,
			innerScopeNameByKey: [SeamSignature.ScopeEnum.Key: String] = [:],
			carriedInnerScopesByKey: [SeamSignature.ScopeEnum.Key: [(name: String, type: TypeDescription)]] = [:],
			enclosingCarriedInnerScopes: [String: [CarriedInnerScope]] = [:],
			decidesPerRoute: Bool = false,
		) -> [FillDispatcher] {
			let enumsByKey = calledBuilders.enumsByKey
			let holesBySite = calledBuilders.holeBySite
			let builtTypeByHoleType = calledBuilders.holes.builtTypeByHoleType
			let calledSeamTypes = Set(calledBuilders.builders.map(\.enumKey.seamType))
			var sitesReachedByKey = [SeamSignature.ScopeEnum.Key: Set<SeamSignature.Hole.Site>]()
			func sitesReached(from key: SeamSignature.ScopeEnum.Key) -> Set<SeamSignature.Hole.Site> {
				if let sites = sitesReachedByKey[key] {
					return sites
				}
				let sites = SeamSignature.ScopeEnum.sitesReached(from: key, in: enumsByKey)
				sitesReachedByKey[key] = sites
				return sites
			}
			/// The sites the routes of `family`'s root enum reach from the enum of `key`: every site the enum reaches, where the
			/// call is not of a public mock or the dispatcher serves both families.
			func sitesReached(from key: SeamSignature.ScopeEnum.Key, onRoutesOf family: Bool?) -> Set<SeamSignature.Hole.Site> {
				guard decidesPerRoute, let family, let rootKey = rootKey(ofFamily: family, holeType: key.holeType) else { return sitesReached(from: key) }
				return CalledBuilders.sites(sitesReached(from: key), onRoutesOf: rootKey, holeBySite: holesBySite)
			}
			/// The key of the called seam's root enum of `holeType` of `family`.
			func rootKey(ofFamily family: Bool, holeType: SeamSignature.HoleType) -> SeamSignature.ScopeEnum.Key? {
				calledBuilders.builders.first { $0.enumKey.holeType == holeType && $0.enumKey.isSendable == family }?.enumKey
			}
			// The enums a builder the call passes a builder struct for reaches: an enum the call reaches only as the value a case
			// of another seam's enum carries keeps its dispatcher over the enum, which that case's dispatcher hands it.
			var builderStructKeys = Set<SeamSignature.ScopeEnum.Key>()
			var builderStructKeysToVisit = calledBuilders.builders.filter(\.takesBuilderStruct).map(\.enumKey)
			while let key = builderStructKeysToVisit.popLast() {
				guard builderStructKeys.insert(key).inserted else { continue }
				builderStructKeysToVisit += enumsByKey[key]?.cases.compactMap(SeamSignature.ScopeEnum.heldKey(of:)) ?? []
			}
			/// Whether the dispatcher of the enum of `key` returns its builder struct (`FillDispatcher.returnsBuilderStruct`).
			/// An enclosing call that declares its dispatchers over the enum, which this call reuses, keeps it from declaring
			/// any of its own of the hole type. A public mock's caller's dispatchers are the struct's levels by other means
			/// (`PublicMockLevelFunctions`).
			func returnsBuilderStruct(_ key: SeamSignature.ScopeEnum.Key) -> Bool {
				!decidesPerRoute
					&& builderStructKeys.contains(key)
					&& !innerScopeNameByKey.keys.contains { $0.seamType == key.seamType && $0.holeType == key.holeType && carriedInnerScopesByKey[$0] == nil }
					&& !calledBuilders.builders.contains { builder in
						builder.enumKey.holeType == key.holeType && enclosingDispatchers[Self.key(of: builder.enumKey)] != nil
					}
			}
			// The enums each family's routes reach that lead to a filled place, in the order the builders first reach them.
			var reachedKeys = [SeamSignature.ScopeEnum.Key]()
			var familiesByKey = [SeamSignature.ScopeEnum.Key: [Bool]]()
			for builder in calledBuilders.builders {
				let family = builder.enumKey.isSendable
				var visited = Set<SeamSignature.ScopeEnum.Key>()
				var keysToVisit = [builder.enumKey]
				while let key = keysToVisit.popLast() {
					guard !sitesReached(from: key, onRoutesOf: family).isDisjoint(with: filledSites),
					      visited.insert(key).inserted,
					      enclosingDispatchers[Self.key(of: key, returnsBuilderStruct: returnsBuilderStruct(key))] == nil,
					      let scopeEnum = enumsByKey[key]
					else { continue }
					if familiesByKey[key] == nil {
						reachedKeys.append(key)
					}
					if familiesByKey[key]?.contains(family) != true {
						familiesByKey[key, default: []].append(family)
					}
					keysToVisit.append(contentsOf: scopeEnum.cases.reversed().compactMap(SeamSignature.ScopeEnum.heldKey(of:)))
				}
			}
			/// Whether a dispatcher of the enum of `key` for `family`'s routes takes `passUp`.
			func takesPassUp(_ key: SeamSignature.ScopeEnum.Key, onRoutesOf family: Bool?) -> Bool {
				!sitesReached(from: key, onRoutesOf: family).isSubset(of: filledSites)
			}
			/// The instance that dispatches the enum of `key`: one serves every family that reaches the enum, which a caller
			/// fills on every family's routes alike.
			func dispatcherInstance(of key: SeamSignature.ScopeEnum.Key) -> Instance {
				Instance(enumKey: key, family: familiesByKey[key]?.count == 1 ? familiesByKey[key]?.first : nil, returnsBuilderStruct: returnsBuilderStruct(key))
			}
			let instancesToDeclare = reachedKeys.map(dispatcherInstance(of:))
			var dispatcherNames = enclosingDispatchers
			for instance in instancesToDeclare {
				guard let scopeEnum = enumsByKey[instance.enumKey] else { continue }
				// An enum nested by type is named after its own enum too.
				let enumName = scopeEnum.rootTypeName == nil ? "" : "_\(scopeEnum.typeName)"
				dispatcherNames[instance.dispatcherKey] = names.claim(ScopeGenerator.functionName(toBuildPropertyNamed: "\(scopeEnum.builderLabel.spelledWithoutBackticks)_\(DependencyTreeGenerator.seamStem(of: instance.enumKey.seamType))\(enumName)".spelledAsIdentifier))
			}
			// The places a case nested by type stands for are filled by the fill of the first that the builders reach.
			let holeIndexBySite = Dictionary(calledBuilders.holes.enumerated().map { ($0.element.site, $0.offset) }, uniquingKeysWith: { first, _ in first })
			var dispatcherKeys = [String: SeamSignature.ScopeEnum.Key]()
			for instance in instancesToDeclare {
				dispatcherKeys[instance.dispatcherKey] = instance.enumKey
			}
			var dispatchers = instancesToDeclare.compactMap { instance -> FillDispatcher? in
				let key = instance.enumKey
				let family = instance.family
				guard let scopeEnum = enumsByKey[key] else { return nil }
				let cases = scopeEnum.cases.compactMap { enumCase -> Case? in
					switch enumCase.kind {
					case let .place(sites):
						let rootKey = decidesPerRoute ? family.flatMap { rootKey(ofFamily: $0, holeType: key.holeType) } : nil
						let sitesOnRoutes = rootKey.map { CalledBuilders.sites(Set(sites), onRoutesOf: $0, holeBySite: holesBySite) } ?? Set(sites)
						// A dispatcher is declared for an enum only where its routes reach a filled place, and a caller fills every
						// place of a hole type of a call or none, so some site of every place case is filled on the routes it serves.
						guard let site = sites.filter({ filledSites.contains($0) && sitesOnRoutes.contains($0) }).min(by: { holeIndexBySite[$0, default: .max] < holeIndexBySite[$1, default: .max] }), let hole = holesBySite[site] else { return nil }
						let targetKey = ScopeGenerator.fillKey(of: hole)
						return Case(name: enumCase.name, carriesPayload: enumCase.values != nil, hasForwardedValue: hole.forwardedType != nil, target: Case.Target(name: fillNames[targetKey] ?? "", key: targetKey, takesPassUp: false), values: enumCase.values?.fields, labelsBoundLater: enumCase.values?.labelsBoundLater ?? [])
					case let .nested(innerKey, _, _),
					     let .inner(innerKey, _, _),
					     let .fill(_, _, innerKey, _, _):
						// The routes this dispatcher serves reach the places of the enum the case holds that are on them.
						let reachedSites = sitesReached(from: innerKey, onRoutesOf: family)
						let target = dispatcherInstance(of: innerKey)
						var dispatcherCase = Case(name: enumCase.name, hasForwardedValue: false, target: nil, values: enumCase.values?.fields, labelsBoundLater: enumCase.values?.labelsBoundLater ?? [])
						dispatcherCase.isLetChild = enumCase.isLetChildOfCarrier(inSendableEnum: scopeEnum.key.isSendable) && ReservedName.seamCarrier(ofEnum: scopeEnum.type) != nil
						if case .fill = enumCase.kind {
							dispatcherCase.isFillCase = true
							dispatcherCase.carriedInnerKey = SeamSignature.ScopeEnum.carriedInnerKey(of: enumCase)
						}
						guard !reachedSites.isDisjoint(with: filledSites) else { return dispatcherCase }
						let targetKey = target.dispatcherKey
						return Case(
							name: dispatcherCase.name,
							hasForwardedValue: false,
							target: Case.Target(name: dispatcherNames[targetKey] ?? "", key: targetKey, takesPassUp: takesPassUp(innerKey, onRoutesOf: target.family), reusedCarriedInnerScopes: enclosingCarriedInnerScopes[targetKey] ?? []),
							values: dispatcherCase.values,
							isFillCase: dispatcherCase.isFillCase,
							carriedInnerKey: dispatcherCase.carriedInnerKey,
							labelsBoundLater: dispatcherCase.labelsBoundLater,
							isLetChild: dispatcherCase.isLetChild,
						)
					}
				}
				let dispatcherKey = instance.dispatcherKey
				// A seam's enum of a seam the called seam calls carries the deferred parameters that call passed.
				let carriesDeferredFields = !decidesPerRoute && !calledSeamTypes.contains(key.seamType)
				var dispatcher = FillDispatcher(
					key: dispatcherKey,
					functionName: dispatcherNames[dispatcherKey] ?? "",
					enumType: scopeEnum.type,
					// The most explicit of the places' spellings, as the called seam's builder spells it (`builtTypeByHoleType`).
					returnType: builtTypeByHoleType[key.holeType] ?? key.holeType.builtType,
					isSendableFamily: key.isSendable,
					takesPassUp: takesPassUp(key, onRoutesOf: family),
					cases: cases.map { dispatcherCase in
						var dispatcherCase = dispatcherCase
						dispatcherCase.carriesDeferredFields = carriesDeferredFields
						dispatcherCase.carrierUse = calledBuilders.carrierUse(ofEnum: scopeEnum, count: dispatcherCase.values?.count ?? 0)
						return dispatcherCase
					},
				)
				dispatcher.takesValuesOfOuterTypes = key.describedType != nil
				dispatcher.seamType = key.seamType
				dispatcher.innerScopeName = key.describedType == nil ? innerScopeNameByKey[key] : nil
				dispatcher.decidesPerRoute = decidesPerRoute
				dispatcher.returnsBuilderStruct = instance.returnsBuilderStruct
				return dispatcher
			}
			// A seam's case for a builder the call's caller fills with a type whose tree leads to a place returns the called seam's
			// struct over the struct of the fill's own level: a level function for each level of the called seam, and of each seam it
			// passes a place up from, carrying that struct, whose places return the fill's own level's struct.
			// The fill's level each level function of a seam the called seam calls on the way to a fill leads to, by the function's
			// key: where this call's own caller carries a struct to that level, the function carries it too.
			var fillLevelKeyByCarriedDispatcherKey = [String: SeamSignature.ScopeEnum.Key]()
			// A public mock's caller's dispatchers are each a level function that returns the level's struct, as one that returns
			// its builder struct is (`PublicMockLevelFunctions`).
			func returnsLevelStruct(_ dispatcher: FillDispatcher) -> Bool {
				dispatcher.returnsBuilderStruct || decidesPerRoute
			}
			do {
				/// A level of a seam on a carried route, and the fills' levels its places lead to, nearest first: the last is a level
				/// of the called seam's own enums, which the call's dispatchers return; each before it is a level of a seam whose
				/// fill of a deeper seam's place the route passes through, itself carried by the levels after it.
				struct CarriedLevel: Hashable {
					let key: SeamSignature.ScopeEnum.Key
					let fillLevelKeys: [SeamSignature.ScopeEnum.Key]
				}
				func carriedDispatcherKey(of level: CarriedLevel) -> String {
					"\(Self.key(of: level.key, returnsBuilderStruct: true)) carrying \(level.fillLevelKeys.map(\.spelling).joined(separator: " carrying "))"
				}
				var carriedDispatchers = [FillDispatcher]()
				var declaredLevels = Set<CarriedLevel>()
				/// What a level's struct whose places lead to `fillLevelKeys` is generic over: the struct of the nearest fill's level,
				/// over what the levels after it make of the built type.
				func carriedReturnType(of fillLevelKeys: ArraySlice<SeamSignature.ScopeEnum.Key>, builtType: TypeDescription) -> TypeDescription? {
					guard let nearestFillLevelKey = fillLevelKeys.first, let fillLevelEnum = enumsByKey[nearestFillLevelKey] else { return nil }
					let generic = fillLevelKeys.count == 1 ? builtType : carriedReturnType(of: fillLevelKeys.dropFirst(), builtType: builtType)
					return generic.map { ReservedName.levelType(ofEnum: fillLevelEnum.type, built: $0) }
				}
				/// What declaring `level`'s function needs, or `nil` where it declares none.
				func parts(of level: CarriedLevel) -> (nearestFillLevelKey: SeamSignature.ScopeEnum.Key, ownFillLevelKey: SeamSignature.ScopeEnum.Key, fillLevelDispatcher: FillDispatcher, fillLevelEnum: SeamSignature.ScopeEnum, scopeEnum: SeamSignature.ScopeEnum, returnType: TypeDescription)? {
					guard let nearestFillLevelKey = level.fillLevelKeys.first,
					      let ownFillLevelKey = level.fillLevelKeys.last,
					      let fillLevelDispatcher = dispatchers.first(where: { dispatcherKeys[$0.key] == ownFillLevelKey && returnsLevelStruct($0) }),
					      let fillLevelEnum = enumsByKey[nearestFillLevelKey],
					      let scopeEnum = enumsByKey[level.key],
					      let returnType = carriedReturnType(of: level.fillLevelKeys[...], builtType: fillLevelDispatcher.returnType)
					else { return nil }
					return (nearestFillLevelKey, ownFillLevelKey, fillLevelDispatcher, fillLevelEnum, scopeEnum, returnType)
				}
				/// The level a case of `level` leads on to: `nil` for a place's case where the places are the fill's own level's,
				/// and for a fill's case that leads no further.
				func nextLevel(after enumCase: SeamSignature.ScopeEnum.Case, of level: CarriedLevel) -> CarriedLevel? {
					switch enumCase.kind {
					case .place:
						// A place of a seam further out on the route leads to that seam's level, itself carried.
						level.fillLevelKeys.count == 1 ? nil : level.fillLevelKeys.first.map { CarriedLevel(key: $0, fillLevelKeys: Array(level.fillLevelKeys.dropFirst())) }
					case let .nested(heldKey, _, _),
					     let .inner(heldKey, _, _):
						CarriedLevel(key: heldKey, fillLevelKeys: level.fillLevelKeys)
					case let .fill(innerKey, innerEnumType, fillLevelKey, _, _):
						// A fill of a deeper seam's place that leads on: its levels lead to the fill's level, then on as this level does.
						innerEnumType == nil ? nil : CarriedLevel(key: innerKey, fillLevelKeys: [fillLevelKey] + level.fillLevelKeys)
					}
				}
				/// The name of `level`'s function before it is claimed: the builder label of the nearest fill's level, the stems of
				/// that level's seam and `level`'s, and, for a nested enum or where `qualifiesEnum`, the enum's name.
				func unclaimedFunctionName(of level: CarriedLevel, nearestFillLevelKey: SeamSignature.ScopeEnum.Key, fillLevelEnum: SeamSignature.ScopeEnum, scopeEnum: SeamSignature.ScopeEnum, qualifiesEnum: Bool) -> String {
					let enumName = if qualifiesEnum {
						"_" + [scopeEnum.rootTypeName, scopeEnum.typeName].compactMap(\.self).joined(separator: "_")
					} else {
						scopeEnum.rootTypeName == nil ? "" : "_\(scopeEnum.typeName)"
					}
					return "\(fillLevelEnum.builderLabel.spelledWithoutBackticks)_\(DependencyTreeGenerator.seamStem(of: nearestFillLevelKey.seamType))_\(DependencyTreeGenerator.seamStem(of: level.key.seamType))\(enumName)"
				}
				// The levels the cases below lead to, each with the case it carries.
				var carriedFillCases = [(index: Int, caseIndex: Int, level: CarriedLevel)]()
				for index in dispatchers.indices where returnsLevelStruct(dispatchers[index]) {
					guard let enumKey = dispatcherKeys[dispatchers[index].key], let scopeEnum = enumsByKey[enumKey] else { continue }
					for (caseIndex, enumCase) in scopeEnum.cases.enumerated() {
						guard case let .fill(innerKey, _?, fillLevelKey, _, _) = enumCase.kind,
						      caseIndex < dispatchers[index].cases.count,
						      dispatchers[index].cases[caseIndex].target != nil
						else { continue }
						carriedFillCases.append((index, caseIndex, CarriedLevel(key: innerKey, fillLevelKeys: [fillLevelKey])))
					}
				}
				// The enums of the levels that declare a function, by the name each would take: two levels of one builder label and
				// seam pair whose enums are roots, as a seam's plain and `@Sendable` root enums or two root enums under one fill's
				// builder are, would take one name, which the allocator would name apart in the order it meets them, the builder
				// labels' order. Each such level takes its enum's name instead, and none keeps the bare one.
				var enumKeysByUnclaimedFunctionName = [String: Set<SeamSignature.ScopeEnum.Key>]()
				var levelsToReach = carriedFillCases.map(\.level)
				var reachedLevels = Set<CarriedLevel>()
				while let level = levelsToReach.popLast() {
					guard reachedLevels.insert(level).inserted, let levelParts = parts(of: level) else { continue }
					enumKeysByUnclaimedFunctionName[unclaimedFunctionName(of: level, nearestFillLevelKey: levelParts.nearestFillLevelKey, fillLevelEnum: levelParts.fillLevelEnum, scopeEnum: levelParts.scopeEnum, qualifiesEnum: false), default: []].insert(level.key)
					levelsToReach += levelParts.scopeEnum.cases.compactMap { nextLevel(after: $0, of: level) }
				}
				/// The target of a case that leads to `level`, declaring its function and those of the levels beneath it first.
				func carriedTarget(_ level: CarriedLevel) -> Case.Target? {
					guard case let (nearestFillLevelKey, ownFillLevelKey, fillLevelDispatcher, fillLevelEnum, scopeEnum, returnType)? = parts(of: level) else { return nil }
					let key = carriedDispatcherKey(of: level)
					if declaredLevels.insert(level).inserted {
						let unclaimedName = unclaimedFunctionName(of: level, nearestFillLevelKey: nearestFillLevelKey, fillLevelEnum: fillLevelEnum, scopeEnum: scopeEnum, qualifiesEnum: false)
						let qualifiesEnum = enumKeysByUnclaimedFunctionName[unclaimedName, default: []].count > 1
						let functionName = names.claim(ScopeGenerator.functionName(toBuildPropertyNamed: unclaimedFunctionName(of: level, nearestFillLevelKey: nearestFillLevelKey, fillLevelEnum: fillLevelEnum, scopeEnum: scopeEnum, qualifiesEnum: qualifiesEnum).spelledAsIdentifier))
						let index = carriedDispatchers.count
						carriedDispatchers.append(FillDispatcher(
							key: key,
							functionName: functionName,
							enumType: scopeEnum.type,
							returnType: returnType,
							isSendableFamily: level.key.isSendable,
							takesPassUp: false,
							cases: [],
						))
						carriedDispatchers[index].seamType = level.key.seamType
						let cases = scopeEnum.cases.map { enumCase -> Case in
							// Every place of the called seam's builder is filled with the one fulfilling type, whose own level the fill's
							// struct is: the call's, or a seam's further out on the route, itself carried.
							let target: Case.Target? = if case .place = enumCase.kind, level.fillLevelKeys.count == 1 {
								Case.Target(name: fillLevelDispatcher.functionName, key: fillLevelDispatcher.key, takesPassUp: false)
							} else {
								nextLevel(after: enumCase, of: level).flatMap(carriedTarget)
							}
							var dispatcherCase = Case(name: enumCase.name, carriesPayload: enumCase.values != nil, hasForwardedValue: false, target: target, values: enumCase.values?.fields, labelsBoundLater: enumCase.values?.labelsBoundLater ?? [])
							// The called seam's levels are bound by calls the caller's seam makes.
							dispatcherCase.carriesDeferredFields = true
							dispatcherCase.isLetChild = enumCase.isLetChildOfCarrier(inSendableEnum: scopeEnum.key.isSendable) && ReservedName.seamCarrier(ofEnum: scopeEnum.type) != nil
							dispatcherCase.carrierUse = calledBuilders.carrierUse(ofEnum: scopeEnum, count: enumCase.values?.fields.count ?? 0)
							// A place's site path ends at its property.
							if case let .place(sites) = enumCase.kind {
								dispatcherCase.returnsWrapperBuilder = sites.first?.path.last?.propertyType.isAnyInstantiator ?? false
							}
							return dispatcherCase
						}
						carriedDispatchers[index].cases = cases
						carriedDispatchers[index].takesValuesOfOuterTypes = true
						carriedDispatchers[index].returnsBuilderStruct = true
						fillLevelKeyByCarriedDispatcherKey[key] = ownFillLevelKey
					}
					return Case.Target(name: carriedDispatchers.first { $0.key == key }?.functionName ?? "", key: key, takesPassUp: false)
				}
				for (index, caseIndex, level) in carriedFillCases {
					guard let target = carriedTarget(level) else { continue }
					var carriedCase = Case(
						name: dispatchers[index].cases[caseIndex].name,
						hasForwardedValue: false,
						target: target,
						values: dispatchers[index].cases[caseIndex].values,
						labelsBoundLater: dispatchers[index].cases[caseIndex].labelsBoundLater,
					)
					// The case hands on the memo of a deferred parameter its payload carries, as the case it replaces does: the seam the
					// called seam calls bound it from what its call passed, which no declaration of the caller's is.
					carriedCase.carriesDeferredFields = dispatchers[index].cases[caseIndex].carriesDeferredFields
					dispatchers[index].cases[caseIndex] = carriedCase
				}
				dispatchers += carriedDispatchers
			}
			// The level functions on the route from the called seam's root to a place inside a fill take the struct of their level.
			// A fill that holds places of several hole types or families of the calling seam is handed a struct for each, so its
			// level functions take each under a name of its own, after the fill's parameter it leads to, which names the builder
			// whose route leads there: never a position, which would move to another type when the types are renamed.
			// A level reached from two roots takes the list of the root whose key spells first. Every root here is the called
			// seam's root of a hole type and family, and a level a root reaches has its hole type, so two roots that share a level
			// differ only in family, and the `@Sendable` root's list comes first, whatever the names. That is the list the level
			// needs: the `@Sendable` root reaches it from inside a `@Sendable` function, so each place beneath it is built in one on
			// that route, and a case whose places are built in one on one route and not on another, with a fill that holds a place,
			// is rejected (`placeInsideFillOfCaseOfBothRootEnums`); each fill beneath the level that the list reaches is a fill of a
			// `@Sendable` place, which takes the `@Sendable` family's structs.
			var carriedInnerScopesByLevel = [SeamSignature.ScopeEnum.Key: [(name: String, type: TypeDescription)]]()
			for (rootKey, carried) in carriedInnerScopesByKey.sorted(by: { $0.key.spelling < $1.key.spelling }) {
				var keysToVisit = [rootKey]
				while let key = keysToVisit.popLast() {
					guard carriedInnerScopesByLevel[key] == nil else { continue }
					carriedInnerScopesByLevel[key] = carried
					keysToVisit += enumsByKey[key]?.cases.compactMap(SeamSignature.ScopeEnum.heldKey(of:)) ?? []
				}
			}
			if !carriedInnerScopesByLevel.isEmpty {
				// A level function takes the values its cases' targets read under their labels beside the struct of its level, so
				// that struct's name is claimed apart from every label a carried level's cases hold too, which stay unclaimed: no
				// other name moves for them.
				var labelsOfCarriedLevels = Set<String>()
				for key in carriedInnerScopesByLevel.keys {
					for enumCase in enumsByKey[key]?.cases ?? [] {
						labelsOfCarriedLevels.formUnion((enumCase.values?.fields ?? []).map(\.property.label))
					}
				}
				func claimUpName(_ base: String) -> String {
					var name = base
					while labelsOfCarriedLevels.contains(name) || names.taken.contains(name) {
						name = "\(name)_".spelledAsJoinedIdentifier
					}
					return names.claim(name)
				}
				var upNameByCarriedName = [String: String]()
				var singleUpName: String?
				for (_, carried) in carriedInnerScopesByKey.sorted(by: { $0.key.spelling < $1.key.spelling }) {
					if carried.count == 1 {
						singleUpName = singleUpName ?? claimUpName("up")
					} else {
						for carriedInnerScope in carried where upNameByCarriedName[carriedInnerScope.name] == nil {
							upNameByCarriedName[carriedInnerScope.name] = claimUpName("up_\(carriedInnerScope.name.dropFirst(ReservedName.builderFunctionNamePrefix.count))")
						}
					}
				}
				dispatchers = dispatchers.map { dispatcher in
					var dispatcher = dispatcher
					guard returnsLevelStruct(dispatcher), let key = dispatcherKeys[dispatcher.key] ?? fillLevelKeyByCarriedDispatcherKey[dispatcher.key], let carried = carriedInnerScopesByLevel[key] else { return dispatcher }
					dispatcher.carriedInnerScopes = carried.map { CarriedInnerScope(name: $0.name, type: $0.type, upName: (carried.count == 1 ? singleUpName : upNameByCarriedName[$0.name]) ?? "") }
					// A deeper seam's root on the route takes the struct of its level as a level nested by type does; the called seam's
					// root is handed it by the call.
					if carriedInnerScopesByKey[key] == nil {
						dispatcher.takesValuesOfOuterTypes = true
					}
					return dispatcher
				}
			}
			return dispatchers
		}

		/// The body of a fill generated in the one case of a dispatcher that calls it, in place of a function of its own
		/// (see `ScopeGenerator.inlinableFillKeys`): what the case binds, and the fill's body, indented for the case.
		struct InlinedFill {
			/// Whether the case carries a payload struct, which the fill is handed as its scope.
			let carriesPayload: Bool
			/// Whether the body reads the scope; a case that binds a value it never reads draws a warning.
			let readsScope: Bool
			/// The name the fill's function gives the value an instantiator forwards, or `nil` for a place that forwards none.
			let forwardedValueName: String?
			/// Whether the body reads the forwarded value: a fill never reads a forwarded `Void`.
			let readsForwardedValue: Bool
			let body: [String]
		}

		/// The function of the dispatcher's level, indented by `indent`, `@Sendable` as `isSendable` says, which returns the
		/// level's builder struct (`structDeclaration`). A case whose fill is in `inlinedFills`, by key, holds the fill's body.
		/// - Parameter parametersByKey: What each dispatcher of the call takes beside its enum
		///   (`dispatcherParameters(of:fillReads:)`), and each fill nested by type beside its case's payload, by key.
		func declaration(
			isSendable: Bool,
			indent: String,
			inlinedFills: [String: InlinedFill],
			parametersByKey: [String: [SeamSignature.Hole.Field]] = [:],
			callerArgumentByParameter: [Property: String] = [:],
			callerMemoArgumentByMemo: [Property: String] = [:],
			typesDeclaredEscaping: Set<TypeDescription> = [],
			fillsTakingPayloadFields: Set<String> = [],
			labelsHiddenByReenteringCalls: Set<String> = [],
		) -> String {
			let parameters = parametersByKey[key] ?? []
			let parameterNames = Self.parameterNames(of: parameters)
			// What this function hands on of a value no case carries to a target that takes it as `parameter`: its own parameter
			// of that form (`parameter(handing:among:)`), or, for the root dispatcher, which takes none, the caller's declaration
			// in the form that target takes (`ScopeGenerator.FillCallerReads`), whatever form another target of the call takes it
			// in.
			func ownValue(for parameter: SeamSignature.Hole.Field) -> String {
				takesValuesOfOuterTypes ? parameterNames[parameter.property] ?? parameter.property.label : callerArgumentByParameter[parameter.property] ?? parameter.property.label
			}
			// The names this function binds, apart from the names of what it takes and passes on.
			let labels = Set(parameterNames.values).union(cases.flatMap { dispatcherCase in
				dispatcherCase.target.map { Self.parameterNames(of: parametersByKey[$0.key] ?? []).values.map(\.self) } ?? []
			})
			func name(_ base: String) -> String {
				var name = base
				while labels.contains(name) {
					name += "_"
				}
				return name
			}
			return structDeclaration(
				isSendable: isSendable,
				indent: indent,
				inlinedFills: inlinedFills,
				fillsTakingPayloadFields: fillsTakingPayloadFields,
				parameters: parameters,
				parametersByKey: parametersByKey,
				ownValue: ownValue(for:),
				callerMemoArgument: { callerMemoArgumentByMemo[$0.memoProperty] },
				valuesName: name("values"),
				scopeName: name("scope"),
				typesDeclaredEscaping: typesDeclaredEscaping,
				labelsHiddenByReenteringCalls: labelsHiddenByReenteringCalls,
			)
		}

		/// The function of one level of a seam's tree that returns its enum's builder struct (`returnsBuilderStruct`): it takes
		/// the values the members' targets read that the cases do not carry, as the enum's dispatcher takes them, and returns a
		/// struct whose member for each case calls the function of the next level, handing it what it reads of the values the
		/// member is handed, or holds the fill of the case's place, which reads them. No member's closure captures the values
		/// it is handed: it reads what it needs out of them. A seam's caller fills every place of an enum, so every case has a
		/// target, and no place forwards a value.
		private func structDeclaration(
			isSendable: Bool,
			indent: String,
			inlinedFills: [String: InlinedFill],
			fillsTakingPayloadFields: Set<String>,
			parameters: [SeamSignature.Hole.Field],
			parametersByKey: [String: [SeamSignature.Hole.Field]],
			ownValue: (SeamSignature.Hole.Field) -> String,
			callerMemoArgument: (SeamSignature.Hole.Field) -> String?,
			valuesName: String,
			scopeName: String,
			typesDeclaredEscaping: Set<TypeDescription>,
			labelsHiddenByReenteringCalls: Set<String>,
		) -> String {
			let memberIndent = indent + ScopeGenerator.standardIndent
			/// The names a carrier's member takes `dispatcherCase`'s values under, given the payload's name: the struct of the run
			/// they end, then each value after it (`SeamCarrierValues.Use`), or every value, each under the payload's name joined
			/// with its label.
			func carrierParameterNames(of dispatcherCase: Case, payloadName: String) -> [String] {
				let values = dispatcherCase.values ?? []
				return dispatcherCase.carrierUse?.parameterNames(of: values, inPayloadNamed: payloadName) ?? values.map { SeamHoles.argumentName(of: $0, inPayloadNamed: payloadName) }
			}
			/// What reads `field` of `dispatcherCase`'s values from the names `carrierParameterNames` gives them.
			func carrierRead(of field: SeamSignature.Hole.Field, in dispatcherCase: Case, payloadName: String, bindingMemo: Bool) -> String {
				let values = dispatcherCase.values ?? []
				guard let use = dispatcherCase.carrierUse, let index = values.firstIndex(where: { $0.property == field.property }) else { return SeamHoles.argumentRead(of: field, inPayloadNamed: payloadName, bindingMemo: bindingMemo) }
				return use.read(ofFieldAt: index, of: values, inPayloadNamed: payloadName, bindingMemo: bindingMemo)
			}
			/// The argument `target`, the target of `dispatcherCase`, takes for `parameter`, reading the case's payload bound as
			/// `payloadName`, and whether it reads the payload: the struct the caller's member of this level returns for the case,
			/// for the struct of a level on a carried route; else the case's payload's field, or this function's own value.
			func argument(_ parameter: SeamSignature.Hole.Field, named argumentLabel: String, of target: Case.Target, for dispatcherCase: Case, payloadName: String, readsOwnPayload: Bool) -> (text: String, readsPayload: Bool) {
				let label = parameter.property.label
				if let carriedInnerScope = carriedInnerScopes.first(where: { $0.name == label }) {
					// A level function an enclosing call declares takes the struct under its own name for it.
					let argumentLabel = Self.isFill(target) ? label : target.reusedCarriedInnerScopes.first { $0.type == carriedInnerScope.type }?.upName ?? carriedInnerScope.upName
					// A carrier's member takes the case's values as arguments, which the closure binds under the payload's name.
					let memberArguments = takesValuesAsArguments ? carrierParameterNames(of: dispatcherCase, payloadName: payloadName).joined(separator: ", ") : payloadName
					let member = "\(carriedInnerScope.upName).\(dispatcherCase.name.spelledAsMemberReference)"
					return ("\(argumentLabel.spelledAsArgumentLabel): \(dispatcherCase.isLetChild ? member : "\(member)(\(memberArguments))")", true)
				} else if readsOwnPayload, (dispatcherCase.carriedLabels.contains(label) && dispatcherCase.handsOn(parameter)) || (parameter.bindsMemo && labelsHiddenByReenteringCalls.contains(label) && dispatcherCase.values?.contains { $0.property.label == label } == true), let field = dispatcherCase.values?.first(where: { $0.property.label == label }) {
					// A target that binds a deferred parameter's memo is handed the memo, whose instance it reads where it reads the
					// value: also a deferred field `carriedLabels` leaves out where a call inside a fill passes a fill of this call on
					// beneath another declaration of the label (`fillDeferredLabelsHiddenByReenteringCalls`), which builds the seam
					// again (`Scope.fillUnderConstruction`): the target binds the memo of the seam whose struct it is handed, where the
					// enclosing value is another declaration's. Elsewhere the caller's declaration is the one inline reads, which the
					// branches below hand. The payload is read before the member returns, so no memo made of it captures the payload.
					let source = HandedSource(field, readsMemo: parameter.bindsMemo, expression: takesValuesAsArguments ? carrierRead(of: field, in: dispatcherCase, payloadName: payloadName, bindingMemo: parameter.bindsMemo) : "\(payloadName).\(field.memberName(bindingMemo: parameter.bindsMemo))")
					return ("\(argumentLabel.spelledAsArgumentLabel): \(source.handed(to: parameter, capturingExpression: true))", true)
				} else if let ownParameter = Self.parameter(handing: parameter, among: parameters) {
					// This function's own parameter of the target's form: a target of another form is handed its own.
					let source = HandedSource(ownParameter, readsMemo: ownParameter.bindsMemo, expression: ownValue(ownParameter))
					return ("\(argumentLabel.spelledAsArgumentLabel): \(source.handed(to: parameter, capturingExpression: false))", false)
				} else if parameter.bindsMemo, parameter.deferral == .deferred(isSendable: true), let memoArgument = callerMemoArgument(parameter) {
					// The root dispatcher hands a target that takes a `SendableLazilyInstantiated` the caller's declaration of it, or
					// one made of the caller's value (`ScopeGenerator.FillCallerReads.memoArgumentByMemo`).
					return ("\(argumentLabel.spelledAsArgumentLabel): \(memoArgument)", false)
				} else {
					// The root dispatcher hands the caller's declaration, in the form a target that takes the value takes it
					// (`ScopeGenerator.FillCallerReads`).
					let source = HandedSource(expression: ownValue(parameter), type: parameter.property.typeDescription, isMemo: false)
					return ("\(argumentLabel.spelledAsArgumentLabel): \(source.handed(to: parameter, capturingExpression: false))", false)
				}
			}
			/// The parameters of `target`, in the order it declares them: a fill's in their own order; a level function's with
			/// the structs of carried levels first, in the order this function takes them, and the rest in their order; a level
			/// function an enclosing call declares takes only structs, in its own order.
			func orderedCarriedFirst(_ parameters: [SeamSignature.Hole.Field], of target: Case.Target) -> [SeamSignature.Hole.Field] {
				guard !Self.isFill(target), target.reusedCarriedInnerScopes.isEmpty else { return parameters }
				let carriedNames = carriedInnerScopes.map(\.name)
				let carried = carriedNames.compactMap { name in parameters.first { $0.property.label == name } }
				return carried + parameters.filter { !carriedNames.contains($0.property.label) }
			}
			// A seam's carrier hands each member the case's values as arguments, not as a payload struct; the member's closure
			// takes each under the payload's name joined with its label.
			let takesValuesAsArguments = ReservedName.seamCarrier(ofEnum: enumType) != nil
			func closureHead(of dispatcherCase: Case, payloadName: String, readsPayload: Bool) -> String {
				guard takesValuesAsArguments else { return "{ \(readsPayload ? payloadName : "_") in" }
				let names = carrierParameterNames(of: dispatcherCase, payloadName: payloadName)
				return names.isEmpty ? "{" : "{ \(names.joined(separator: ", ")) in"
			}
			var members = [(name: String, lines: [String])]()
			for (dispatcherCase, target) in cases.compactMap({ dispatcherCase in dispatcherCase.target.map { (dispatcherCase, $0) } }) {
				let targetParameters = parametersByKey[target.key] ?? []
				let targetParameterNames = Self.parameterNames(of: targetParameters)
				if let inlinedFill = inlinedFills[target.key] {
					// The fill's body, which declares no function: a fill that does is called by name, so no function is declared
					// inside the closure the struct stores (`ScopeGenerator.declaresFunction(inFillBody:)`).
					let head = closureHead(of: dispatcherCase, payloadName: "scope", readsPayload: inlinedFill.carriesPayload && inlinedFill.readsScope)
					members.append((dispatcherCase.name, ["\(dispatcherCase.name.spelledAsArgumentLabel): \(head)"] + inlinedFill.body.map { String($0.dropFirst(memberIndent.count)) } + ["}"]))
				} else if fillsTakingPayloadFields.contains(target.key) || !Self.isFill(target) {
					// A fill that returns a wrapper's builder takes each field of the payload it reads, from the payload, and each
					// value it reads that the payload does not carry, under its label: the builder it returns captures no payload.
					// The next level's function likewise takes what it reads from this case's payload where it carries one.
					let arguments = orderedCarriedFirst(targetParameters, of: target).map { argument($0, named: targetParameterNames[$0.property] ?? $0.property.label, of: target, for: dispatcherCase, payloadName: valuesName, readsOwnPayload: true) }
					let readsValues = arguments.contains(where: \.readsPayload)
					var call = "\(target.name)(\(arguments.map(\.text).joined(separator: ", ")))"
					if dispatcherCase.returnsWrapperBuilder, !Self.isFill(target) {
						// The member of an instantiator's place on a carried route returns the builder the wrapper keeps, which ignores the
						// forwarded value: the fill's level reads it from its own payload. A level that reads the payload is called before
						// the builder is returned, so the builder captures the level's struct, never the payload.
						call = readsValues ? "{ [level = \(call)] _ in level }" : "{ _ in \(call) }"
					}
					if dispatcherCase.isLetChild, !Self.isFill(target) {
						// A carrier's `let` child is formed with its parent, by the next level's function.
						members.append((dispatcherCase.name, ["\(dispatcherCase.name.spelledAsArgumentLabel): \(call)"]))
					} else {
						members.append((dispatcherCase.name, ["\(dispatcherCase.name.spelledAsArgumentLabel): \(closureHead(of: dispatcherCase, payloadName: valuesName, readsPayload: readsValues)) \(call) }"]))
					}
				} else {
					// A fill nested by type takes the case's payload, and each value it reads that the payload does not carry, under
					// its label: this function's own, or the caller's.
					let bound = if !dispatcherCase.carriesPayload {
						[String]()
					} else if takesValuesAsArguments {
						carrierParameterNames(of: dispatcherCase, payloadName: scopeName)
					} else {
						[scopeName]
					}
					let arguments = orderedCarriedFirst(targetParameters, of: target).map { argument($0, named: targetParameterNames[$0.property] ?? $0.property.label, of: target, for: dispatcherCase, payloadName: scopeName, readsOwnPayload: false) }
					let readsPayload = !bound.isEmpty || arguments.contains(where: \.readsPayload)
					members.append((dispatcherCase.name, ["\(dispatcherCase.name.spelledAsArgumentLabel): \(closureHead(of: dispatcherCase, payloadName: scopeName, readsPayload: readsPayload)) \(target.name)(\((bound + arguments.map(\.text)).joined(separator: ", "))) }"]))
				}
			}
			// The struct of this level the caller's member returns, on a carried route, before the values the members' targets
			// read.
			var valueParameterList = [String]()
			for carriedInnerScope in carriedInnerScopes where parameters.contains(where: { $0.property.label == carriedInnerScope.name }) || (innerScopeName != nil && cases.contains { dispatcherCase in
				dispatcherCase.target.map { (parametersByKey[$0.key] ?? []).contains { $0.property.label == carriedInnerScope.name } } ?? false
			}) {
				valueParameterList.append("\(carriedInnerScope.upName.spelledAsArgumentLabel): \(ReservedName.levelType(ofEnum: enumType, built: Self.carried(carriedInnerScope.type, through: returnType)).asSource)")
			}
			let carriedNames = Set(carriedInnerScopes.map(\.name))
			let parameterNames = Self.parameterNames(of: parameters)
			valueParameterList += parameters.filter { !carriedNames.contains($0.property.label) }.map { "\((parameterNames[$0.property] ?? $0.property.label).spelledAsArgumentLabel): \($0.boundTypeAsFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
			let valueParameters = valueParameterList.joined(separator: ", ")
			let builderType = ReservedName.levelType(ofEnum: enumType, built: returnType)
			var lines = ["\(indent)\(ScopeGenerator.localFunctionPrefix(isSendable: isSendable))func \(functionName)(\(valueParameters)) -> \(builderType.asSource) {"]
			if members.allSatisfy({ $0.lines.count == 1 }) {
				lines.append("\(memberIndent).init(\(members.map { $0.lines[0] }.joined(separator: ", ")))")
			} else if members.count == 1 {
				// One member over several lines opens on the initializer's line and closes the call on its last.
				let memberLines = members[0].lines
				lines.append("\(memberIndent).init(\(memberLines[0])")
				lines += memberLines.dropFirst().dropLast().map { "\(memberIndent)\($0)" }
				lines.append("\(memberIndent)\(memberLines[memberLines.count - 1]))")
			} else {
				// Several members, one of them over several lines: one member per line, each indented once more.
				lines.append("\(memberIndent).init(")
				for (index, member) in members.enumerated() {
					let separator = index == members.count - 1 ? "" : ","
					let memberLines = member.lines
					lines += memberLines.dropLast().map { "\(memberIndent)\(ScopeGenerator.standardIndent)\($0)" }
					lines.append("\(memberIndent)\(ScopeGenerator.standardIndent)\(memberLines[memberLines.count - 1])\(separator)")
				}
				lines.append("\(memberIndent))")
			}
			lines.append("\(indent)}")
			return lines.joined(separator: "\n")
		}

		/// What a level function hands a target of one label: `expression`, of `type`, a deferred parameter's memo where
		/// `isMemo`, else the value, which can be a `LazilyInstantiated` or its `Sendable` twin a type declares.
		struct HandedSource {
			let expression: String
			let type: TypeDescription?
			let isMemo: Bool

			init(expression: String, type: TypeDescription?, isMemo: Bool) {
				self.expression = expression
				self.type = type
				self.isMemo = isMemo
			}

			/// `field` read as `expression`: its memo where `readsMemo` and it is a deferred parameter's, else its value.
			init(_ field: SeamSignature.Hole.Field, readsMemo: Bool, expression: String) {
				let isMemo = readsMemo && field.isDeferredParameter
				self.init(expression: expression, type: isMemo ? field.memoType : field.property.typeDescription, isMemo: isMemo)
			}

			/// The expression `parameter` is handed: the memo's instance where it takes the value, the memo where it takes a memo
			/// of the same type, and else a `LazilyInstantiated` of the parameter's memo type made of what is handed, which reads
			/// the instance of a memo or of a type's `LazilyInstantiated` when its own instance is read, so the value is created
			/// where the target's tree reads it. Where `capturingExpression`, the expression reads the payload, which the closure
			/// of a memo made of it reads first, so it captures no payload.
			func handed(to parameter: SeamSignature.Hole.Field, capturingExpression: Bool) -> String {
				guard parameter.bindsMemo, let memoType = parameter.memoType else {
					return isMemo ? "\(expression).\(Dependency.lazilyInstantiatedInstancePropertyName)" : expression
				}
				guard type != memoType else { return expression }
				let readsInstance = isMemo || type.map { $0.propertyType.isLazilyInstantiated && !$0.isOptional } == true
				let read = readsInstance ? ".\(Dependency.lazilyInstantiatedInstancePropertyName)" : ""
				return capturingExpression
					? "\(memoType.asSource)({ [handed = \(expression)] in handed\(read) })"
					: "\(memoType.asSource)({ \(expression)\(read) })"
			}
		}

		/// The type a level's struct is generic over on a carried route, given `returnType`, what the level's function returns
		/// its struct over: `carriedType`, the caller's struct of the fill's own level, in place of the built type, inside the
		/// structs of the fills' levels a deeper seam's level returns its struct over.
		static func carried(_ carriedType: TypeDescription, through returnType: TypeDescription) -> TypeDescription {
			switch returnType {
			case let .nested(name, parentType, generics) where ReservedName.namesLevelType(name) && generics.count == 1:
				.nested(name: name, parentType: parentType, generics: [carried(carriedType, through: generics[0])])
			// A level a route carries is always spelled qualified: a carrier by its seam, which another module fills, and a
			// builder struct by its enum.
			case .void, .simple, .nested, .composition, .optional, .implicitlyUnwrappedOptional, .some, .any, .metatype, .attributed, .array, .dictionary, .tuple, .closure, .variadic, .unknown:
				carriedType
			}
		}

		/// Whether `target` is a fill rather than a dispatcher.
		private static func isFill(_ target: Case.Target) -> Bool {
			!target.key.hasPrefix("dispatcher ")
		}
	}
}
