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

/// Test only, deleted before merge: the differential oracle of a seam's places by case. Today's per-site walk gives each
/// place's lists in full records (`SeamSignature.Hole`); the place graph (`SeamSignature.Places`) gives them per case, through
/// its query. Every test and every fuzzer graph compares the two, so a step that moves a reader from the per-site lists to
/// the graph moves onto answers already proven equal.
///
/// Three comparisons, each over full records:
/// 1. Per site, along the route the graph's builder took to it: the path, the types to the owner, the declared path and
///    the stack read off the route's levels equal the hole's, and the fields, the uncarried declarations (with the cases of
///    the places a buildable tree holds), the cycle re-entries and the declarations hidden by fields that a plain walk of the
///    route's levels finds equal the hole's lists, in order.
/// 2. Per case, each answer of the query, for each label, equals the union of its sites' answers; the case's representative
///    route is its first site's, which names are made from; and its sites are the places of one case of the generated enums.
/// 3. (Callers' findings, with step 2: not yet.)
public enum SeamPlacesOracle {
	public struct Report: Sendable {
		public var seamType = ""
		public var sites = 0
		public var cases = 0
		/// Sites a call passes up, which no case holds yet.
		public var passedUpSites = 0
		/// Places a buildable tree holds that a call passes up, which no case holds yet.
		public var passedUpPlacesInTree = 0
		public var siteQuestions = 0
		public var caseQuestions = 0
		public var mismatchCount = 0
		/// The first few mismatches, spelled.
		public var mismatches = [String]()

		mutating func record(_ mismatch: @autoclosure () -> String) {
			mismatchCount += 1
			if mismatches.count < 8 {
				mismatches.append(mismatch())
			}
		}
	}

	public static func report(of observation: SeamSignature.Places.Observation) -> Report {
		var report = Report()
		report.seamType = observation.seamType.asSource
		report.sites = observation.siteHoles.count
		report.cases = observation.places.cases.count
		let places = observation.places
		let holes = observation.siteHoles
		guard holes.count == observation.caseIndexBySite.count, holes.count == observation.routeBySite.count else {
			report.record("\(holes.count) sites but \(observation.caseIndexBySite.count) case indices and \(observation.routeBySite.count) routes")
			return report
		}
		let query = SeamSignature.Places.Query(of: places)

		// The sites of each case, in site order.
		var sitesByCase = [[Int]](repeating: [], count: places.cases.count)
		var caseIndexBySite = [SeamSignature.Hole.Site: Int]()
		for (site, caseIndex) in observation.caseIndexBySite.enumerated() {
			let hole = holes[site]
			guard caseIndex >= 0 else {
				report.passedUpSites += 1
				if hole.innerSeamType == nil {
					report.record("site \(spelled(hole.sitePath)) has no case but no call passes it up")
				}
				continue
			}
			guard places.cases.indices.contains(caseIndex) else {
				report.record("site \(spelled(hole.sitePath)) names case \(caseIndex) of \(places.cases.count)")
				continue
			}
			sitesByCase[caseIndex].append(site)
			caseIndexBySite[hole.site] = caseIndex
		}
		for (caseIndex, sites) in sitesByCase.enumerated() where sites.isEmpty {
			report.record("case \(caseIndex) holds no site")
		}
		checkCasePartition(of: observation, sitesByCase: sitesByCase, into: &report)

		// 1. Per site, along its route.
		var routeAnswersBySite = [Int: RouteAnswers]()
		var siteFacts = [Int: SiteFacts]()
		var casesInTreeByDeclaration = [String: Set<Int>]()
		var casesInTreePathByDeclaration = [String: (path: String, property: String)]()
		for (site, caseIndex) in observation.caseIndexBySite.enumerated() where caseIndex >= 0 && places.cases.indices.contains(caseIndex) {
			let hole = holes[site]
			let route = observation.routeBySite[site]
			guard checkRoute(route, of: hole, caseIndex: caseIndex, places: places, into: &report) else { continue }
			report.siteQuestions += 1
			let answers = RouteAnswers(route: route, siteProperty: hole.property, siteOpensSendableFunction: places.cases[caseIndex].siteOpensSendableFunction, places: places)
			routeAnswersBySite[site] = answers
			let path = spelled(hole.sitePath)

			compare("site path", at: path, today: hole.sitePath.map(\.asSource), graph: query.sitePath(along: route).map(\.asSource), into: &report)
			compare("types to owner", at: path, today: json(hole.typesToOwner), graph: json(query.typesToOwner(along: route)), into: &report)
			compare("declared path to owner", at: path, today: json(Array(hole.declaredSitePath.dropLast())), graph: json(query.declaredPathToOwner(along: route)), into: &report)
			let todayStack = zip(hole.fillPropertyStack, hole.fillConcreteTypeStack).map { "\($0.asSource)@\($1.asSource)" }
			compare("stack", at: path, today: todayStack, graph: query.stack(along: route).map { "\($0.property.asSource)@\($0.concreteType.asSource)" }, into: &report)

			compare("fields", at: path, today: hole.fields.map { json($0) }, graph: answers.fields.map { json($0) }, into: &report)
			// The place's own uncarried declarations come first, a public mock's root declaration bound from its caller's
			// argument replaced where a path to a call that presents the place binds its label; then those the calls and the
			// called copies add (`SeamSignature.Places.Case`'s stored facts).
			let placeCase = places.cases[caseIndex]
			let graphUncarried = answers.uncarried.compactMap { query.uncarriedDeclaration(of: $0, at: caseIndex) }
			let ownGraph = graphUncarried.map { uncarriedJSON($0) }
			let today = hole.uncarriedDeclarations.map { uncarriedJSON($0) }
			let replacedOfCase = Set(placeCase.uncarriedReplacedOnPathsToCalls.map { uncarriedJSON($0) })
			let calledCopiesOfCase = Set(placeCase.calledCopyDeclarations.map { uncarriedJSON($0) })
			var ownToday = [(label: String, json: String)]()
			var replaced = [String]()
			var ownMatches = today.count >= ownGraph.count
			for (index, graphJSON) in ownGraph.enumerated() where index < today.count {
				let label = hole.uncarriedDeclarations[index].property.label
				// The case records, for each declaration bound from the caller's argument, what the place holds in its place,
				// replaced or not.
				if graphUncarried[index].isBoundFromCallersArgument {
					replaced.append(today[index])
				}
				if today[index] == graphJSON || graphUncarried[index].isBoundFromCallersArgument && replacedOfCase.contains(today[index]) {
					ownToday.append((label, graphJSON))
				} else {
					ownMatches = false
				}
			}
			let added = Array(today.dropFirst(ownGraph.count))
			if !ownMatches || !added.allSatisfy(calledCopiesOfCase.contains) {
				report.record("uncarried declarations at \(path): today \(today) graph \(ownGraph) then of the case's called copies \(placeCase.calledCopyDeclarations.map { uncarriedJSON($0) })")
			}
			siteFacts[site] = SiteFacts(ownUncarried: ownToday, calledCopies: added, replaced: replaced)
			// The cases of the places a tree the seam's caller could build holds: a level variant is shared by routes whose places
			// in the tree fall in different cases, so the graph holds, per declaration, the union over every site that reads it.
			for (uncarried, answer) in zip(hole.uncarriedDeclarations, answers.uncarried) where uncarried.isBuildableAboveSeam {
				guard let located = answer.located else { continue }
				let key = "\(located.level).\(located.declaration)"
				for placeInTree in uncarried.placesInTree {
					if let caseIndex = caseIndexBySite[placeInTree] {
						casesInTreeByDeclaration[key, default: []].insert(caseIndex)
					} else {
						// A place a call passes up, its site in the inner seam's tree, has no case yet.
						report.passedUpPlacesInTree += 1
					}
				}
				casesInTreePathByDeclaration[key] = casesInTreePathByDeclaration[key] ?? (path, uncarried.property.asSource)
			}
			compare("cycle re-entries", at: path, today: hole.cycleReentryDeclarations.map { json($0) }, graph: answers.cycleReentries.map { json($0) }, into: &report)
			compare("declarations hidden by fields", at: path, today: hole.declarationsHiddenByFields.map { json($0) }, graph: answers.hiddenByFields.map { json($0) }, into: &report)
		}

		for (key, todayCases) in casesInTreeByDeclaration.sorted(by: { $0.key < $1.key }) {
			let parts = key.split(separator: ".").compactMap { Int($0) }
			let graphCases = places.declaration(level: parts[0], declaration: parts[1]).buildability.map { Set($0.placesInTree) }
			guard graphCases != todayCases, let (path, property) = casesInTreePathByDeclaration[key] else { continue }
			report.record("cases in the tree of \(property), first read at \(path): today \(todayCases.sorted()) graph \(graphCases.map { $0.sorted().map(String.init) } ?? ["no buildability"])")
		}

		// 2. Per case, the query against the union over its sites.
		for (caseIndex, sites) in sitesByCase.enumerated() where !sites.isEmpty {
			let siteHoles = sites.map { holes[$0] }
			let path = spelled(siteHoles[0].sitePath) + (sites.count > 1 ? " (+\(sites.count - 1) sites)" : "")
			report.caseQuestions += 1

			if let first = routeAnswersBySite[sites[0]] {
				compare("representative route", at: path, today: first.route.levels.map(String.init), graph: query.representativeRoute(of: caseIndex)?.levels.map(String.init) ?? ["none"], into: &report)
			}
			let routeLabels = sites.compactMap { routeAnswersBySite[$0] }.reduce(into: Set<String>()) { $0.formUnion($1.labels) }
			compare("labels reaching the case", at: path, today: routeLabels.sorted(), graph: Set(query.labels(reaching: caseIndex)).sorted(), into: &report)

			for label in routeLabels.sorted() {
				let today = Set(zip(sites, siteHoles).map { site, hole -> String in
					if let field = hole.fields.first(where: { $0.property.label == label }) {
						return json(field)
					}
					if let uncarried = siteFacts[site]?.ownUncarried.first(where: { $0.label == label }) {
						return uncarried.json
					}
					return "none"
				})
				let graph = Set(query.answers(ofLabel: label, at: caseIndex).map { answer -> String in
					switch answer {
					case let .field(level, declaration):
						return json(places.declaration(level: level, declaration: declaration).field)
					case .callersOwn:
						return "none"
					case .uncarried, .boundOutsideSendableFunction:
						return query.uncarriedDeclaration(of: answer, at: caseIndex).map { uncarriedJSON($0) } ?? "none"
					}
				})
				compare("answers of \(label)", at: path, today: today.sorted(), graph: graph.sorted(), into: &report)
			}

			// The facts stored per case: the union over its sites in site order, the first of each equal entry.
			compare("called copy declarations", at: path, today: firstOfEach(sites.flatMap { siteFacts[$0]?.calledCopies ?? [] }), graph: places.cases[caseIndex].calledCopyDeclarations.map { uncarriedJSON($0) }, into: &report)
			compare("declarations replaced on paths to calls", at: path, today: firstOfEach(sites.flatMap { siteFacts[$0]?.replaced ?? [] }), graph: places.cases[caseIndex].uncarriedReplacedOnPathsToCalls.map { uncarriedJSON($0) }, into: &report)
			compare("re-entering call declarations", at: path, today: firstOfEach(siteHoles.flatMap { $0.reenteringCallDeclarations.map { json($0) } }), graph: places.cases[caseIndex].reenteringCallDeclarations.map { json($0) }, into: &report)
			compare("re-entering place fields", at: path, today: firstOfEach(siteHoles.flatMap { $0.reenteringPlaceFields.map { json($0) } }), graph: places.cases[caseIndex].reenteringPlaceFields.map { json($0) }, into: &report)
			compare("passed on @Sendable", at: path, today: String(siteHoles.contains(where: \.isSendable)), graph: String(places.cases[caseIndex].isPassedOnSendable), into: &report)

			var reentryLabels = Set(siteHoles.flatMap { $0.cycleReentryDeclarations.map(\.property.label) })
			for site in sites {
				for level in observation.routeBySite[site].levels {
					reentryLabels.formUnion(places.levels[level].cycleReentries.map(\.property.label))
				}
			}
			for label in reentryLabels.sorted() {
				let today = Set(siteHoles.map { hole in hole.cycleReentryDeclarations.first { $0.property.label == label }.map { json($0) } ?? "none" })
				let graph = Set(query.cycleReentryDeclarations(ofLabel: label, at: caseIndex).map { $0.map { json($0) } ?? "none" })
				compare("cycle re-entries of \(label)", at: path, today: today.sorted(), graph: graph.sorted(), into: &report)
			}

			var hiddenLabels = Set(siteHoles.flatMap { $0.declarationsHiddenByFields.map(\.property.label) })
			for site in sites {
				hiddenLabels.formUnion(routeAnswersBySite[site]?.labelsOfFillFieldsHiding ?? [])
			}
			for label in hiddenLabels.sorted() {
				let today = Set(siteHoles.compactMap { hole in hole.declarationsHiddenByFields.first { $0.property.label == label }.map { json($0) } })
				let graph = Set(query.declarationsHiddenByFields(ofLabel: label, at: caseIndex).map { json($0) })
				compare("declarations hidden by fields of \(label)", at: path, today: today.sorted(), graph: graph.sorted(), into: &report)
			}
		}
		return report
	}

	/// The issues `report(of:)` finds, one per observation that has any.
	public static func mismatches(of observation: SeamSignature.Places.Observation) -> [String] {
		let report = report(of: observation)
		guard report.mismatchCount > 0 else { return [] }
		return ["The place graph of `\(report.seamType)` answers \(report.mismatchCount) questions otherwise than the per-site walk (\(report.sites) sites, \(report.cases) cases): " + report.mismatches.joined(separator: "; ")]
	}

	/// What the per-site comparison found of a site's uncarried declarations, for the per-case one.
	private struct SiteFacts {
		/// The place's own uncarried declarations, each replaced one as the route declares it.
		let ownUncarried: [(label: String, json: String)]
		/// Those the calls and called copies added after them.
		let calledCopies: [String]
		/// The declarations that stand in place of one the route declares.
		let replaced: [String]
	}

	private static func firstOfEach(_ entries: [String]) -> [String] {
		var seen = Set<String>()
		return entries.filter { seen.insert($0).inserted }
	}

	// MARK: Cases

	/// The sites of a case are the places of one case of the seam's enums nested by type, and the places of one such case are
	/// one case's: the generated code is keyed by it. Every site of a case has the case's owner level and family.
	private static func checkCasePartition(of observation: SeamSignature.Places.Observation, sitesByCase: [[Int]], into report: inout Report) {
		var caseByEnumCase = [String: Int]()
		for (caseIndex, sites) in sitesByCase.enumerated() {
			let placeCase = observation.places.cases[caseIndex]
			var enumCasesOfCase = Set<String>()
			for site in sites {
				let hole = observation.siteHoles[site]
				let path = spelled(hole.sitePath)
				// Whether the place is held in a `Sendable` wrapper decides every crossing the site comparisons check.
				guard let enumPlace = hole.enumPlace else { continue }
				if placeCase.isBuiltInSendableFunction != enumPlace.isBuiltBySendableBuilder {
					report.record("site \(path): case \(caseIndex) is\(placeCase.isBuiltInSendableFunction ? "" : " not") of the `@Sendable` family, its enum place is\(enumPlace.isBuiltBySendableBuilder ? "" : " not")")
				}
				let enumCase = "\(enumPlace.enumTypeName).\(enumPlace.caseName)"
				enumCasesOfCase.insert(enumCase)
				if let other = caseByEnumCase.updateValue(caseIndex, forKey: enumCase), other != caseIndex {
					report.record("enum case \(enumCase) holds places of cases \(other) and \(caseIndex)")
				}
			}
			if enumCasesOfCase.count > 1 {
				report.record("case \(caseIndex) holds places of enum cases \(enumCasesOfCase.sorted())")
			}
		}
	}

	// MARK: Routes

	/// Whether `route` is a route of the graph from the seam's root to the owner of `caseIndex`, recording why not.
	private static func checkRoute(_ route: SeamSignature.Places.Route, of hole: SeamSignature.Hole, caseIndex: Int, places: SeamSignature.Places, into report: inout Report) -> Bool {
		let path = spelled(hole.sitePath)
		guard let first = route.levels.first, route.levels.allSatisfy(places.levels.indices.contains) else {
			report.record("site \(path): route \(route.levels) is not one of the graph's levels")
			return false
		}
		guard places.levels[first].parents.isEmpty else {
			report.record("site \(path): route \(route.levels) starts at a level with parents")
			return false
		}
		for (parent, level) in zip(route.levels, route.levels.dropFirst()) where !places.levels[level].parents.contains(parent) {
			report.record("site \(path): route \(route.levels) steps from \(parent) to \(level), which is no edge")
			return false
		}
		guard route.levels.last == places.cases[caseIndex].ownerLevel else {
			report.record("site \(path): route ends at \(route.levels.last ?? -1), its case's owner is \(places.cases[caseIndex].ownerLevel)")
			return false
		}
		return true
	}

	/// What a plain walk of one route's levels finds for its place: each label's nearest declaration, judged as today's
	/// per-site walk judges it, with no memo and no other route.
	private struct RouteAnswers {
		struct Located {
			let level: Int
			let declaration: Int
		}

		let route: SeamSignature.Places.Route
		/// The labels the route's levels declare.
		var labels = Set<String>()
		var fields = [SeamSignature.Hole.Field]()
		/// The answers of the labels whose nearest declaration is no field of the place, in binding order.
		var uncarried = [SeamSignature.Places.Answer]()
		var cycleReentries = [SeamSignature.Hole.CycleReentryDeclaration]()
		var hiddenByFields = [SeamSignature.Hole.DeclarationHiddenByField]()
		/// The labels whose nearest declaration is a fill's field bound from a parameter of the filled seam.
		var labelsOfFillFieldsHiding = Set<String>()

		init(route: SeamSignature.Places.Route, siteProperty: Property, siteOpensSendableFunction: Bool, places: SeamSignature.Places) {
			self.route = route
			// The nearest declaration of each label, by its position on the route, and the order the labels are bound in: a
			// label bound again moves to its later place.
			var nearest = [String: (position: Int, declaration: Int)]()
			var labelsInBindingOrder = [String]()
			for (position, level) in route.levels.enumerated() {
				for (index, declaration) in places.levels[level].declarations.enumerated() {
					let label = declaration.field.property.label
					if nearest.updateValue((position, index), forKey: label) != nil {
						labelsInBindingOrder.removeAll { $0 == label }
					}
					labelsInBindingOrder.append(label)
				}
			}
			labels = Set(labelsInBindingOrder)
			// The innermost `@Sendable` function the route opens below each position: a level's own declarations are inside the
			// function it opens.
			let openingPositions = route.levels.indices.filter { places.levels[route.levels[$0]].opensSendableFunction != nil }
			for label in labelsInBindingOrder {
				guard let (position, index) = nearest[label] else { continue }
				let level = route.levels[position]
				let declaration = places.declaration(level: level, declaration: index)
				guard declaration.isBoundBeforeNextProperty else {
					uncarried.append(.uncarried(level: level, declaration: index))
					continue
				}
				let innermostFunction: Int? = if siteOpensSendableFunction {
					SeamSignature.Places.Answer.siteFunction
				} else {
					openingPositions.last { $0 > position }.map { route.levels[$0] }
				}
				guard let innermostFunction else {
					fields.append(declaration.field)
					if let hiding = declaration.fillFieldHiding {
						labelsOfFillFieldsHiding.insert(label)
						if let hidden = Self.declaration(before: index, at: position, ofLabel: label, along: route, places: places),
						   hidden.field.property != declaration.field.property
						{
							let calledSeam = if case let .boundByPassingUpSeam(_, _, place) = hidden.reason {
								place.seamType
							} else {
								hiding.calledSeam
							}
							hiddenByFields.append(SeamSignature.Hole.DeclarationHiddenByField(
								property: hidden.field.property,
								declaringType: hidden.field.declaringType,
								declarationLocation: hidden.field.declarationLocation,
								calledSeam: calledSeam,
								receivingSeam: hiding.receivingSeam,
							))
						}
					}
					continue
				}
				// A parameter of the seam is the caller's own, which a fill reads from its own scope.
				guard !declaration.isSeamParameter else { continue }
				uncarried.append(.boundOutsideSendableFunction(level: level, declaration: index, functionLevel: innermostFunction))
			}
			// A cycle that closes on a level below the root hands its type, built again, what a scope between declares, the
			// outermost such level first per label, where the place's nearest declaration of the label is outside the level.
			var reenteredLabels = Set<String>()
			for (position, level) in route.levels.enumerated() where position > 0 {
				for reentry in places.levels[level].cycleReentries
					where reentry.property.label != siteProperty.label
					&& !reenteredLabels.contains(reentry.property.label)
					&& !(nearest[reentry.property.label].map { $0.position >= position } ?? false)
				{
					reenteredLabels.insert(reentry.property.label)
					let declaringLevel = places.levels[route.levels[position - 1]]
					cycleReentries.append(SeamSignature.Hole.CycleReentryDeclaration(
						property: reentry.property,
						declaringType: reentry.declaringType,
						declarationLocation: reentry.declarationLocation,
						parameterTakingType: reentry.parameterTakingType,
						closedOnProperty: reentry.closedOnProperty,
						closedOnBuiltType: reentry.closedOnBuiltType,
						closedOnDeclaringType: declaringLevel.key.builtType ?? declaringLevel.fillOwnerType ?? .void(.tuple),
						reenteringType: reentry.reenteringType,
					))
				}
			}
		}

		/// The declaration of `label` the route binds last before the declaration at `index` of the level at `position`.
		private static func declaration(before index: Int, at position: Int, ofLabel label: String, along route: SeamSignature.Places.Route, places: SeamSignature.Places) -> SeamSignature.Places.Declaration? {
			for (candidatePosition, level) in route.levels.enumerated().prefix(position + 1).reversed() {
				let declarations = places.levels[level].declarations
				let end = candidatePosition == position ? index : declarations.count
				if let earlier = declarations[..<end].lastIndex(where: { $0.field.property.label == label }) {
					return declarations[earlier]
				}
			}
			return nil
		}
	}

	// MARK: Spelling

	private static func compare(_ what: String, at path: String, today: [String], graph: [String], into report: inout Report) {
		guard today != graph else { return }
		report.record("\(what) at \(path): today \(today) graph \(graph)")
	}

	private static func compare(_ what: String, at path: String, today: String, graph: String, into report: inout Report) {
		guard today != graph else { return }
		report.record("\(what) at \(path): today \(today) graph \(graph)")
	}

	private static func spelled(_ path: [Property]) -> String {
		path.map(\.label).joined(separator: ".")
	}

	private static func json(_ value: some Encodable) -> String {
		normalizedJSON(value, droppingKeys: [])
	}

	/// An uncarried declaration's record without the sites of the places its tree holds, which the graph holds as cases and
	/// the oracle compares apart.
	private static func uncarriedJSON(_ value: SeamSignature.Hole.UncarriedDeclaration) -> String {
		normalizedJSON(value, droppingKeys: ["placesInTree"])
	}

	/// `value` encoded with sorted keys, every array of labels held above the seam sorted (a set today), and `droppingKeys`
	/// left out at the top level.
	private static func normalizedJSON(_ value: some Encodable, droppingKeys: Set<String>) -> String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		guard let data = try? encoder.encode(value), var object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
			return "<unencodable \(type(of: value))>"
		}
		if var dictionary = object as? [String: Any] {
			for key in droppingKeys {
				dictionary.removeValue(forKey: key)
			}
			object = dictionary
		}
		object = sortingLabelSets(in: object)
		guard let normalized = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]) else {
			return "<unencodable \(type(of: value))>"
		}
		return String(decoding: normalized, as: UTF8.self)
	}

	private static func sortingLabelSets(in object: Any) -> Any {
		if let dictionary = object as? [String: Any] {
			var sorted = [String: Any]()
			for (key, value) in dictionary {
				if key == "labelsHeldAboveSeam", let labels = value as? [String] {
					sorted[key] = labels.sorted()
				} else {
					sorted[key] = sortingLabelSets(in: value)
				}
			}
			return sorted
		}
		if let array = object as? [Any] {
			return array.map(sortingLabelSets(in:))
		}
		return object
	}
}

extension SeamSignature.Places.Answer {
	/// The declaration an uncarried answer names, or `nil` for a field or the caller's own.
	fileprivate var located: (level: Int, declaration: Int)? {
		switch self {
		case let .uncarried(level, declaration), let .boundOutsideSendableFunction(level, declaration, _):
			(level, declaration)
		case .field, .callersOwn:
			nil
		}
	}
}
