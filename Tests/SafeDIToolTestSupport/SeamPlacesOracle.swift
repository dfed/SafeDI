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

/// Deleted when places come from facts: the differential oracle of a seam's places by case. Today's per-site walk gives each
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
	/// The most passed-up cases one graph's report compares through the called seams' graphs (`checkPassedUpCase`), each
	/// in case order; the rest are counted (`Report.passedUpCasesCapped`), never compared. Each such case follows its chain of
	/// calls through every called seam's graph, and a seam is observed on each pass that settles its signature, so a graph of
	/// many such cases cost the long run more than a shard's step allows: seam corpus seed 1358 spent ten minutes here. The
	/// limit is the 96th percentile of the passed-up cases of the seam corpus's graphs (every fifth seed: 13,730 observed
	/// graphs, 3.7% with more), so at least 95% of graphs are compared whole, which the long run checks over the corpus
	/// (`placesOracleCappedGraphCount`).
	public static let passedUpCaseLimit = 8

	/// Told of each graph `mismatches(of:)` compares whether its report was capped, when a long run counts them.
	@TaskLocal public static var cappedGraphObserver: TaskLocalFunction<@Sendable (_ isCapped: Bool) -> Void>?

	/// The long run's problem when one graph in twenty or more of a corpus had its passed-up cases capped: the limit then
	/// leaves too much of the corpus uncompared, and is raised with the percentile it stands for.
	public static func cappedShareProblem(cappedGraphCount: Int, graphCount: Int, corpusName: String) -> String? {
		guard cappedGraphCount * 20 >= graphCount, cappedGraphCount > 0 else { return nil }
		return "The places oracle capped the passed-up cases of \(cappedGraphCount) of the \(graphCount) seam graphs of the \(corpusName) corpus, 5% or more: raise `SeamPlacesOracle.passedUpCaseLimit` (\(passedUpCaseLimit)) to the percentile of passed-up cases that compares 95% of graphs whole."
	}

	public struct Report: Sendable {
		public var seamType = ""
		public var sites = 0
		public var cases = 0
		/// Sites a call passes up, which no case holds yet.
		public var passedUpSites = 0
		/// Places a buildable tree holds that a call passes up, which no case holds yet.
		public var passedUpPlacesInTree = 0
		/// The cases of places a call presents that were compared through the called seam's graph, and those whose called
		/// graph, or one beneath it, was not in hand.
		public var passedUpCaseQuestions = 0
		public var passedUpCasesUnresolved = 0
		/// The cases whose chain of references ends at a case of another place (see `checkPassedUpCase`).
		public var passedUpCasesOfAnotherPass = 0
		/// The cases compared whose facts the references alone gave too, and those whose path through the calls was compared.
		public var passedUpCasesJoinedBothWays = 0
		/// The passed-up cases past `passedUpCaseLimit`, counted and not compared; a graph with any is capped.
		public var passedUpCasesCapped = 0
		public var isCapped: Bool {
			passedUpCasesCapped > 0
		}
		public var passedUpPathQuestions = 0
		/// The cases compared whose places, the first of each case the called seam hands, carry fewer fields than the case.
		public var passedUpCasesHandedFewerFields = 0
		/// The declarations bound by a seam that passes places up whose reason's place was looked for among the places the
		/// run hands, those a reference of another pass kept from being compared, and those found under another builder
		/// label or case name.
		public var passedUpReasonQuestions = 0
		public var passedUpReasonsOfAnotherPass = 0
		public var passedUpReasonNamesDiffering = 0
		/// The declarations today's places hold as bound by a seam that passes them up which the graph's answers leave out,
		/// because a seam nearer the place binds the label too, or because the holding seam's own tree declares it. The first
		/// are where a message that named the outer declaration names the nearer one.
		public var passedUpDeclarationsBehindNearerSeams = 0
		public var passedUpDeclarationsBehindHoldingSeams = 0
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
		let query = SeamSignature.Places.Query(of: places, calledPlaces: observation.calledPlaces(of:))

		// The sites of each case, in site order.
		var sitesByCase = [[Int]](repeating: [], count: places.cases.count)
		var caseIndexBySite = [SeamSignature.Hole.Site: Int]()
		// The sites a call passes up, by the case of the first call that presents each.
		var passedUpSitesByCase = [Int: [Int]]()
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
			guard places.cases[caseIndex].passedUp == nil else {
				report.passedUpSites += 1
				if hole.innerSeamType == nil {
					report.record("site \(spelled(hole.sitePath)) has the case of a call but no call passes it up")
				}
				passedUpSitesByCase[caseIndex, default: []].append(site)
				caseIndexBySite[hole.site] = caseIndex
				continue
			}
			sitesByCase[caseIndex].append(site)
			caseIndexBySite[hole.site] = caseIndex
		}
		for (caseIndex, sites) in sitesByCase.enumerated() where sites.isEmpty && places.cases[caseIndex].passedUp == nil {
			report.record("case \(caseIndex) holds no site")
		}
		checkCasePartition(of: observation, sitesByCase: sitesByCase, into: &report)

		// 1. Per site, along its route.
		var routeAnswersBySite = [Int: RouteAnswers]()
		let reentriesAlongRoutes = CycleReentriesAlongRoutes(of: places)
		var siteFacts = [Int: SiteFacts]()
		var casesInTreeByDeclaration = [String: Set<Int>]()
		var casesInTreePathByDeclaration = [String: (path: String, property: String)]()
		for (site, caseIndex) in observation.caseIndexBySite.enumerated() where caseIndex >= 0 && places.cases.indices.contains(caseIndex) && places.cases[caseIndex].passedUp == nil {
			let hole = holes[site]
			let route = observation.routeBySite[site]
			guard checkRoute(route, of: hole, caseIndex: caseIndex, places: places, into: &report) else { continue }
			report.siteQuestions += 1
			let answers = RouteAnswers(route: route, siteProperty: hole.property, siteOpensSendableFunction: places.cases[caseIndex].siteOpensSendableFunction, places: places, reentriesAlongRoutes: reentriesAlongRoutes)
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
				// The case records, of the declarations bound from the caller's argument, what the place holds in place of each
				// one a path to a call binds otherwise.
				if graphUncarried[index].isBoundFromCallersArgument, today[index] != graphJSON {
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
			// Compared as sets: the graph answers re-entries label by label (`Places.cycleReentries(ofLevel:beneath:context:)`),
			// and every reader takes a label's first.
			compare("cycle re-entries", at: path, today: hole.cycleReentryDeclarations.map { json($0) }.sorted(), graph: answers.cycleReentries.map { json($0) }.sorted(), into: &report)
			compare("declarations hidden by fields", at: path, today: hole.declarationsHiddenByFields.map { json($0) }, graph: answers.hiddenByFields.map { json($0) }, into: &report)
		}

		for (key, todayCases) in casesInTreeByDeclaration.sorted(by: { $0.key < $1.key }) {
			let parts = key.split(separator: ".").compactMap { Int($0) }
			let graphCases = places.declaration(level: parts[0], declaration: parts[1]).buildability.map { Set($0.placesInTree) }
			guard graphCases != todayCases, let (path, property) = casesInTreePathByDeclaration[key] else { continue }
			report.record("cases in the tree of \(property), first read at \(path): today \(todayCases.sorted()) graph \(graphCases.map { $0.sorted().map(String.init) } ?? ["no buildability"])")
		}

		// A place a call passes up, along the route to the first call that presents it: the route is one of the graph's to the
		// level that declares the call, whose types and declared properties begin the copy's, the call's property next, and
		// the case refers to the seam whose call presented the place.
		for (comparedCount, (caseIndex, sites)) in passedUpSitesByCase.sorted(by: { $0.key < $1.key }).enumerated() {
			guard comparedCount < passedUpCaseLimit else {
				report.passedUpCasesCapped += 1
				continue
			}
			for site in sites {
				let hole = holes[site]
				let route = observation.routeBySite[site]
				guard checkRoute(route, of: hole, caseIndex: caseIndex, places: places, into: &report) else { continue }
				report.siteQuestions += 1
				let path = spelled(hole.sitePath)
				compare("seam whose call presents the place", at: path, today: [hole.innerSeamType?.asSource ?? "none"], graph: [places.cases[caseIndex].passedUp?.seamType.asSource ?? "none"], into: &report)
				let typesToCall = query.typesToOwner(along: route)
				compare("types to the call", at: path, today: json(Array(hole.typesToOwner.prefix(typesToCall.count))), graph: json(typesToCall), into: &report)
				let declaredPathToCall = query.declaredPathToOwner(along: route)
				compare("declared path to the call", at: path, today: json(Array(hole.passedUpRoute.prefix(declaredPathToCall.count))), graph: json(declaredPathToCall), into: &report)
				compare("seam the call's level builds", at: path, today: [hole.innerSeamType?.asSource ?? "none"], graph: [places.levels[places.cases[caseIndex].ownerLevel].key.builtType?.asSource ?? "none"], into: &report)
			}
			checkPassedUpCase(caseIndex, sites: sites, of: observation, query: query, into: &report)
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
						json(places.declaration(level: level, declaration: declaration).field)
					case .callersOwn:
						"none"
					case .uncarried, .boundOutsideSendableFunction:
						query.uncarriedDeclaration(of: answer, at: caseIndex).map { uncarriedJSON($0) } ?? "none"
					}
				})
				compare("answers of \(label)", at: path, today: today.sorted(), graph: graph.sorted(), into: &report)
			}

			// The facts stored per case: the union over its sites, each equal entry once. Compared as sets: the graph adds a case's
			// sites in the order the seam's tree builds them, the observation lists them in builder order, and no reader of these
			// facts reads their order (a finding is ordered by source location). Seam corpus seeds 557 and 583 hold a case whose
			// sites add the same called copies in another interleaving.
			compare("called copy declarations", at: path, today: distinctSorted(sites.flatMap { siteFacts[$0]?.calledCopies ?? [] }), graph: places.cases[caseIndex].calledCopyDeclarations.map { uncarriedJSON($0) }.sorted(), into: &report)
			compare("declarations replaced on paths to calls", at: path, today: distinctSorted(sites.flatMap { siteFacts[$0]?.replaced ?? [] }), graph: places.cases[caseIndex].uncarriedReplacedOnPathsToCalls.map { uncarriedJSON($0) }.sorted(), into: &report)
			compare("re-entering call declarations", at: path, today: distinctSorted(siteHoles.flatMap { $0.reenteringCallDeclarations.map { json($0) } }), graph: places.cases[caseIndex].reenteringCallDeclarations.map { json($0) }.sorted(), into: &report)
			compare("re-entering place fields", at: path, today: distinctSorted(siteHoles.flatMap { $0.reenteringPlaceFields.map { json($0) } }), graph: places.cases[caseIndex].reenteringPlaceFields.map { json($0) }.sorted(), into: &report)
			compare("passed on @Sendable", at: path, today: String(siteHoles.contains(where: \.isSendable)), graph: String(places.cases[caseIndex].isPassedOnSendable), into: &report)

			var reentryLabels = Set(siteHoles.flatMap { $0.cycleReentryDeclarations.map(\.property.label) })
			for site in sites {
				let levels = observation.routeBySite[site].levels
				for (parent, level) in zip(levels, levels.dropFirst()) {
					reentryLabels.formUnion(reentriesAlongRoutes.reentries(ofLevel: level, beneath: parent).map(\.property.label))
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
		cappedGraphObserver?(report.isCapped)
		if report.passedUpDeclarationsBehindNearerSeams > 0 || report.passedUpDeclarationsBehindHoldingSeams > 0 {
			// Counted from a run's output, for the release note's line on the passed-up path.
			print("[SeamPlacesOracle] `\(report.seamType)`: \(report.passedUpDeclarationsBehindNearerSeams) declarations behind a nearer seam's, \(report.passedUpDeclarationsBehindHoldingSeams) behind the holding seam's own")
		}
		// The graph one walk of the tree builds must equal the one the per-site walk builds (`SeamPlacesWalkedOnceChecks`).
		let walkedOnceMismatches = SeamPlacesWalkedOnceChecks.mismatches(of: observation)
		guard report.mismatchCount > 0 else { return walkedOnceMismatches }
		return walkedOnceMismatches + ["The place graph of `\(report.seamType)` answers \(report.mismatchCount) questions otherwise than the per-site walk (\(report.sites) sites, \(report.cases) cases): " + report.mismatches.joined(separator: "; ")]
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

	private static func distinctSorted(_ entries: [String]) -> [String] {
		Set(entries).sorted()
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

	// MARK: Places a call presents

	/// The case of the seam whose tree holds the places of the case at `caseIndex` of `query`'s graph, as that seam and the
	/// case's index, or `nil` where a graph on the way is not in hand.
	private static func holdingCase(of caseIndex: Int, query: SeamSignature.Places.Query) -> String? {
		let chain = query.casesPresented(from: caseIndex)
		guard let last = chain.last, last.query.places.cases[last.caseIndex].passedUp == nil else { return nil }
		let seam = chain.dropLast().last.flatMap { $0.query.places.cases[$0.caseIndex].passedUp }.map { "\($0.seamType.asSource) \($0.isPublicMock)" } ?? "own"
		return "\(seam) \(last.caseIndex)"
	}

	/// The cases of `query`'s graph whose places are those of the case at `caseIndex`: one per call that presents them,
	/// whichever seam each call is of.
	private static func casesPresentingSamePlaces(as caseIndex: Int, query: SeamSignature.Places.Query) -> [Int]? {
		guard let holding = holdingCase(of: caseIndex, query: query) else { return nil }
		let cases = query.places.cases.indices.filter { holdingCase(of: $0, query: query) == holding }
		// Two seams that call each other can each present a place first through the other, so the chain of such a case
		// returns to its first case and never ends at the holding seam: the chains do not say which cases present the places
		// of a case then.
		guard query.casesPresentingSamePlaces(as: caseIndex).allSatisfy({ holdingCase(of: $0, query: query) == holding }) else { return nil }
		// On a pass before the last, references are indices into the graphs of the pass before, so the chain of a case can
		// end at the holding case of places its own links do not lead to. The chains say nothing of such a graph either.
		let holdersByLink = cases.map { query.holdingCase(of: $0) }
		guard let first = holdersByLink.first, let holdingByLink = first, holdersByLink.allSatisfy({ $0.map { $0.query === holdingByLink.query && $0.caseIndex == holdingByLink.caseIndex } ?? false }) else { return nil }
		return cases
	}

	/// An uncarried declaration without its reason and what follows from it, as a path to a call binds it.
	private static func boundKey(_ declaration: SeamSignature.Hole.UncarriedDeclaration) -> String {
		"\(declaration.property.asSource) of \(declaration.declaringType.asSource) taken by \(declaration.parameterTakingType?.asSource ?? "none")"
	}

	/// What the graph says the places of the case at `caseIndex` of `query`'s graph hold, through every seam that presents
	/// them in turn, or `nil` where a graph on the way is not in hand.
	private struct PresentedFacts {
		var fields = Set<String>()
		var uncarried = Set<String>()
		var boundOnPathsToCalls = Set<String>()
		var labelsBoundOnPathsToCalls = Set<String>()
		var isPassedOnSendable = false
		var typesToOwner = [SeamSignature.Hole.PathType]()
		var passedUpRoute = [SeamSignature.Hole.DeclaredProperty]()
	}

	private static func presentedFacts(of caseIndex: Int, query: SeamSignature.Places.Query) -> PresentedFacts? {
		var facts = PresentedFacts()
		var seen = Set<String>()
		return addPresentedFacts(of: caseIndex, query: query, depth: 0, seen: &seen, to: &facts) ? facts : nil
	}

	/// Adds what the graph says of the places of the case at `caseIndex` of `query`'s graph to `facts`, and returns whether
	/// every graph on the way was in hand. A seam's hole of a place several of its calls present holds what each adds.
	private static func addPresentedFacts(of caseIndex: Int, query: SeamSignature.Places.Query, depth: Int, seen: inout Set<String>, to facts: inout PresentedFacts) -> Bool {
		let places = query.places
		let placeCase = places.cases[caseIndex]
		let rootType = places.levels.first(where: \.key.isSeamRoot)?.key.builtType
		let presentingCases: [Int]
		if placeCase.passedUp == nil {
			for label in query.labels(reaching: caseIndex) {
				for answer in query.answers(ofLabel: label, at: caseIndex) {
					switch answer {
					case let .field(level, declaration):
						facts.fields.insert(json(places.declaration(level: level, declaration: declaration).field))
					case .callersOwn:
						break
					case .uncarried, .boundOutsideSendableFunction:
						if let uncarried = query.uncarriedDeclaration(of: answer, at: caseIndex) {
							facts.uncarried.insert(uncarriedJSON(uncarried))
						}
					}
				}
			}
			facts.uncarried.formUnion(placeCase.calledCopyDeclarations.map { uncarriedJSON($0) })
			facts.uncarried.formUnion(placeCase.uncarriedReplacedOnPathsToCalls.map { uncarriedJSON($0) })
			// The called seam's own place takes its builder `@Sendable` where it is built inside a `@Sendable` function, which
			// its seam settles with its builders, after its places.
			facts.isPassedOnSendable = facts.isPassedOnSendable || placeCase.isPassedOnSendable || placeCase.isBuiltInSendableFunction || placeCase.siteOpensSendableFunction
			// The calls of the seam's own tree that present its places back to it, through the seams they call: the cases
			// whose chains end at this case of this seam.
			presentingCases = places.cases.indices.filter { index in
				guard places.cases[index].passedUp != nil, let last = query.casesPresented(from: index).last else { return false }
				return last.caseIndex == caseIndex && last.query.places.cases[last.caseIndex].passedUp == nil && last.query.places.levels.first(where: \.key.isSeamRoot)?.key.builtType == rootType
			}
			// Where two seams the tree calls each present the places first through the other, the chain of such a call
			// never ends at this seam, and the chains do not say which calls present its places back.
			guard query.casesPresentingSamePlaces(as: caseIndex).allSatisfy({ $0 == caseIndex || presentingCases.contains($0) }) else { return false }
		} else {
			guard let cases = casesPresentingSamePlaces(as: caseIndex, query: query) else { return false }
			presentingCases = cases
		}
		guard depth < 64 else { return false }
		for presenting in presentingCases {
			guard let reference = places.cases[presenting].passedUp, let rootType else { return false }
			// Seams that call each other present one another's places: each case is read once.
			guard seen.insert("\(rootType.asSource) \(presenting) \(reference.seamType.asSource) \(reference.caseIndex)").inserted else { continue }
			let presentingCase = places.cases[presenting]
			facts.uncarried.formUnion(presentingCase.calledCopyDeclarations.map { uncarriedJSON($0) })
			facts.isPassedOnSendable = facts.isPassedOnSendable || presentingCase.isPassedOnSendable
			for declaration in query.declarationsBoundOnRoutes(to: presenting) {
				facts.boundOnPathsToCalls.insert(boundKey(declaration))
				// The labels of the seam asked: a holding seam's calls back are asked through the seams between.
				if depth == 0, placeCase.passedUp != nil {
					facts.labelsBoundOnPathsToCalls.insert(declaration.property.label)
				}
			}
			guard let called = query.calledCase(of: presenting), addPresentedFacts(of: called.caseIndex, query: called.query, depth: depth + 1, seen: &seen, to: &facts) else { return false }
		}
		return true
	}

	/// Compares the places of the case at `caseIndex`, which a call presents, with what the graph says of them through
	/// the called seam's graph: their fields are the called seam's case's, and each declaration they carry no field of is the
	/// called seam's case's, one a path to a call that presents them binds, or one the fills around such a call add.
	private static func checkPassedUpCase(_ caseIndex: Int, sites: [Int], of observation: SeamSignature.Places.Observation, query: SeamSignature.Places.Query, into report: inout Report) {
		let holes = observation.siteHoles
		let places = observation.places
		guard let firstSite = sites.first, let reference = places.cases[caseIndex].passedUp else { return }
		let path = spelled(holes[firstSite].sitePath) + (sites.count > 1 ? " (+\(sites.count - 1) sites)" : "")
		// A called seam whose graph the run does not hold (one read from a module info file that stores none yet) names no
		// case; one whose graph it holds names a case for every place.
		let calledGraphIsHeld = observation.calledPlaces.contains { $0.seamType == reference.seamType && $0.isPublicMock == reference.isPublicMock && !$0.places.cases.isEmpty }
		guard reference.caseIndex >= 0 || calledGraphIsHeld else {
			report.passedUpCasesUnresolved += 1
			return
		}
		guard reference.caseIndex >= 0 else {
			report.record("passed-up case \(caseIndex) at \(path) names no case of \(reference.seamType.asSource)")
			return
		}
		// The seam that holds the places, and what the seams on the way add, as the query finds them through every call that
		// presents the places (`Query.holdingCase(of:)`, `presentationAdditions(of:)`).
		guard let holding = query.holdingCase(of: caseIndex), let additions = query.presentationAdditions(of: caseIndex) else {
			report.passedUpCasesUnresolved += 1
			return
		}
		// Seams that call each other settle over several passes, each observed, and a pass's references are indices into
		// the graphs of the pass before, so the calls can lead to a case of another place on a pass before the last. Such a
		// case is counted, never compared.
		let holdingPlaces = holding.query.places
		let holdingSeam = holdingPlaces.levels.first(where: \.key.isSeamRoot)?.key.builtType
		let holdingProperty = holdingPlaces.levels[holdingPlaces.cases[holding.caseIndex].ownerLevel].key.nextProperty
		guard holdingSeam == holes[firstSite].site.seamType, holdingProperty == holes[firstSite].property else {
			report.passedUpCasesOfAnotherPass += 1
			return
		}
		var facts = PresentedFacts()
		var seen = Set<String>()
		_ = addPresentedFacts(of: holding.caseIndex, query: holding.query, depth: 0, seen: &seen, to: &facts)
		let calledCopies = Set(additions.calledCopyDeclarations.map { uncarriedJSON($0) })
		facts.uncarried.formUnion(calledCopies)
		facts.isPassedOnSendable = additions.isPassedOnSendable
		for bound in additions.boundOnPathsToCalls {
			facts.boundOnPathsToCalls.insert(boundKey(bound.declaration))
			if bound.presentingCase.query === query {
				facts.labelsBoundOnPathsToCalls.insert(bound.declaration.property.label)
			}
		}
		// The same facts by the references alone, each case's chain followed to its end (`casesPresented(from:)`): where
		// every chain ends at the holding seam, the cases whose chains end at one case are those the graph links
		// (`Case.firstCasePresentingSamePlaces`), and both joins give the same facts. On the last pass, two seams that call
		// each other can each present a site first through the other, so the chain of such a case returns to its first case
		// (`generate_settlesSignatures_whenFourSeamsFormSeveralCyclesOfInstantiators`: `S0`'s and `S1`'s cases of `S3`'s
		// `service`); only the linked cases reach the holding seam then.
		if let casesByChain = casesPresentingSamePlaces(as: caseIndex, query: query), let factsByChain = presentedFacts(of: caseIndex, query: query) {
			report.passedUpCasesJoinedBothWays += 1
			compare("cases presenting the places of case \(caseIndex), by chain and by link", at: path, today: casesByChain.map(String.init), graph: query.casesPresentingSamePlaces(as: caseIndex).map(String.init), into: &report)
			compare("fields of the presented places, by chain and by link", at: path, today: factsByChain.fields.sorted(), graph: facts.fields.sorted(), into: &report)
			compare("uncarried declarations of the presented places, by chain and by link", at: path, today: factsByChain.uncarried.sorted(), graph: facts.uncarried.sorted(), into: &report)
			compare("declarations bound on paths to calls, by chain and by link", at: path, today: factsByChain.boundOnPathsToCalls.sorted(), graph: facts.boundOnPathsToCalls.sorted(), into: &report)
			compare("labels this seam binds on paths to calls, by chain and by link", at: path, today: factsByChain.labelsBoundOnPathsToCalls.sorted(), graph: facts.labelsBoundOnPathsToCalls.sorted(), into: &report)
			compare("presented places passed on @Sendable, by chain and by link", at: path, today: String(factsByChain.isPassedOnSendable), graph: String(facts.isPassedOnSendable), into: &report)
		}
		report.passedUpCaseQuestions += 1
		// A seam that calls another holds one place per case of the called seam (`SeamSignature.placesHandedToCallers`), so
		// the places it passes up are the first of each case, whose fields lack one only another route to the case
		// carries. Such a case is counted; the holding seam's own observation compares the fields of every place.
		let fieldsToday = Set(sites.flatMap { holes[$0].fields.map { json($0) } })
		if fieldsToday.isStrictSubset(of: facts.fields) {
			report.passedUpCasesHandedFewerFields += 1
		} else {
			compare("fields of the presented places", at: path, today: fieldsToday.sorted(), graph: facts.fields.sorted(), into: &report)
		}
		compare("presented places passed on @Sendable", at: path, today: String(sites.contains { holes[$0].isSendable }), graph: String(facts.isPassedOnSendable), into: &report)
		for site in sites {
			let hole = holes[site]
			let sitePath = spelled(hole.sitePath)
			for declaration in hole.uncarriedDeclarations {
				var isKnown = facts.uncarried.contains(uncarriedJSON(declaration))
				if case .boundByPassingUpSeam = declaration.reason, facts.boundOnPathsToCalls.contains(boundKey(declaration)) {
					isKnown = true
				}
				if !isKnown {
					report.record("uncarried declaration of the presented place \(sitePath): today \(uncarriedJSON(declaration)), which the graph holds neither on a path to a call nor in the called seam's case")
				}
			}
			let labelsToday = Set(hole.uncarriedDeclarations.map(\.property.label))
			let missing = facts.labelsBoundOnPathsToCalls.subtracting(labelsToday)
			if !missing.isEmpty {
				report.record("presented place \(sitePath): the graph binds \(missing.sorted()) on the paths to its calls, which today's place does not list")
			}
			// The place today's reason of such a declaration names is the called seam's place of the case its call presents,
			// which the run hands beside that seam's graph (`Places.Called.hole(ofCaseAt:)`), unless the holding seam's case or
			// a presenting case stores the declaration with its reason. On a pass before the last a reference can lead to a
			// place of another site, or to a place the called seam labels otherwise; both are counted, and the tests of seams
			// that call each other compare the last pass's labels.
			for declaration in hole.uncarriedDeclarations {
				guard case let .boundByPassingUpSeam(seam, _, place) = declaration.reason, !facts.uncarried.contains(uncarriedJSON(declaration)) else { continue }
				report.passedUpReasonQuestions += 1
				var isHanded = false
				var isOfAnotherPass = false
				for bound in additions.boundOnPathsToCalls where boundKey(bound.declaration) == boundKey(declaration) {
					let presentingPlaces = bound.presentingCase.query.places
					guard presentingPlaces.levels.first(where: \.key.isSeamRoot)?.key.builtType == seam, let reference = presentingPlaces.cases[bound.presentingCase.caseIndex].passedUp else { continue }
					guard let calledHole = observation.called(of: reference)?.hole(ofCaseAt: reference.caseIndex),
					      calledHole.scopeSeamType == place.seamType, calledHole.ownerType == place.ownerType, calledHole.property == place.property
					else {
						isOfAnotherPass = true
						continue
					}
					isHanded = true
					if calledHole.builderLabel != place.builderLabel || calledHole.enumPlace?.caseName != place.caseName {
						report.passedUpReasonNamesDiffering += 1
					}
				}
				if !isHanded, isOfAnotherPass {
					report.passedUpReasonsOfAnotherPass += 1
				} else if !isHanded {
					report.record("presented place \(sitePath): today \(boundKey(declaration)) is bound by \(seam.asSource) on the path to a call that presents \(place.property.asSource) of \(place.ownerType.asSource), and no case that presents the places binds it or stores it")
				}
			}
			// A declaration today's place holds as bound by a seam that passes the place up is among those the query says
			// the place reads of its label above the holding seam.
			// A copy of a fill's hole that a seam called inside the fill takes, which a presenting case stores
			// (`presentationAdditions.calledCopyDeclarations`), is a case fact, as an own case's is, and no answer of a label.
			for declaration in hole.uncarriedDeclarations where !calledCopies.contains(uncarriedJSON(declaration)) {
				guard case .boundByPassingUpSeam = declaration.reason else { continue }
				let answers = query.presentedAnswers(ofLabel: declaration.property.label, at: caseIndex) ?? []
				let boundAbove = Set(answers.compactMap { answer -> String? in
					switch answer {
					case .ofHoldingSeam, .callersOwn:
						return nil
					case let .boundByPassingUpSeam(presentingCase, .field(level, index)),
					     let .boundByPassingUpSeam(presentingCase, .uncarried(level, index)),
					     let .boundByPassingUpSeam(presentingCase, .boundOutsideSendableFunction(level, index, _)):
						let field = presentingCase.query.places.declaration(level: level, declaration: index).field
						return "\(field.property.asSource) of \(field.declaringType.asSource) taken by \(field.parameterTakingType?.asSource ?? "none")"
					case .boundByPassingUpSeam(_, .callersOwn):
						return nil
					}
				})
				guard !boundAbove.contains(boundKey(declaration)) else { continue }
				// Today's place lists every declaration a path to a call binds. A fill reads the nearest declaration of a
				// label, so one a seam beneath also binds, or the holding seam's own tree declares, is never read.
				if !boundAbove.isEmpty {
					report.passedUpDeclarationsBehindNearerSeams += 1
				} else if answers.contains(where: {
					if case .ofHoldingSeam = $0 {
						true
					} else {
						false
					}
				}) {
					report.passedUpDeclarationsBehindHoldingSeams += 1
				} else {
					report.record("presented place \(sitePath): today \(boundKey(declaration)) is bound by a seam that passes the place up, and the graph says nothing declares its label on a way to the place")
				}
			}
		}
		// Where one call of each seam on the way presents the places, the path through the calls is the one today's place
		// holds.
		if let pathToHoldingSeam = query.pathToHoldingSeam(of: caseIndex), pathToHoldingSeam.calls.allSatisfy({ $0.presentingCase.query.casesPresentingSamePlaces(as: $0.presentingCase.caseIndex).count == 1 }) {
			report.passedUpPathQuestions += 1
			for site in sites {
				let hole = holes[site]
				let sitePath = spelled(hole.sitePath)
				compare("declared path through the calls", at: sitePath, today: json(hole.passedUpRoute), graph: json(pathToHoldingSeam.declaredPath), into: &report)
				let types = pathToHoldingSeam.types
				compare("types through the calls", at: sitePath, today: json(Array(hole.typesToOwner.prefix(types.count))), graph: json(types), into: &report)
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

		init(route: SeamSignature.Places.Route, siteProperty: Property, siteOpensSendableFunction: Bool, places: SeamSignature.Places, reentriesAlongRoutes: CycleReentriesAlongRoutes) {
			self.route = route
			// The nearest declaration of each label, by its position on the route, and the order the labels are bound in: a
			// label bound again moves to its later place.
			var nearest = [String: (position: Int, declaration: Int)]()
			var labelsInBindingOrder = [String]()
			for (position, level) in route.levels.enumerated() {
				for (index, declaration) in places.declarationsBeforeAnyNextProperty(ofLevel: level).enumerated() {
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
				for reentry in reentriesAlongRoutes.reentries(ofLevel: level, beneath: route.levels[position - 1])
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
						placeIsInFurtherSendableFunction: siteOpensSendableFunction || openingPositions.contains { $0 > position },
					))
				}
			}
		}

		/// The declaration of `label` the route binds last before the declaration at `index` of the level at `position`.
		private static func declaration(before index: Int, at position: Int, ofLabel label: String, along route: SeamSignature.Places.Route, places: SeamSignature.Places) -> SeamSignature.Places.Declaration? {
			for (candidatePosition, level) in route.levels.enumerated().prefix(position + 1).reversed() {
				let declarations = places.declarationsBeforeAnyNextProperty(ofLevel: level)
				let end = candidatePosition == position ? index : declarations.count
				if let earlier = declarations[..<end].lastIndex(where: { $0.field.property.label == label }) {
					return places.declaration(level: level, declaration: earlier)
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
