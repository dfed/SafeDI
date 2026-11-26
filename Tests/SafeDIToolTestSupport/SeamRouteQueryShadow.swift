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

import SafeDICore

/// A check of the tests, which no shipped code holds: asks `SeamPlaceGraph` every question the per-site lists answer today — the nearest
/// declaration of each label, the declaration a cycle re-entry hands the type built again, the declaration a fill's
/// field of a seam parameter hides, and the stack the place is built with — and compares the answers with the lists
/// the per-site walk computed. Nothing generated reads it.
///
/// The comparison is per case: today's answer is the union over the case's places, since one emitted fill per case
/// binds what every route hands it (`SeamPlaceGraph`'s note on cases). Every test runs it, so a place the graph
/// answers otherwise fails that test (`SeamPlaceLevelChecks`).
public enum SeamRouteQueryShadow {
	public struct Report: Sendable {
		public var seamType = ""
		public var places = 0
		public var nodes = 0
		public var edges = 0
		public var levelConflicts = 0
		public var levelConflictsOnlyInFunctionFacts = 0
		public var fillLevelVariants = 0
		public var sendableOnlyVariants = 0
		public var otherVariants = 0
		public var types = 0
		public var cases = 0
		public var queries = 0
		public var graphCycles = 0
		public var mismatches = 0
		public var labelSetMismatches = 0
		public var reentryQuestions = 0
		public var reentryMismatches = 0
		public var hiddenQuestions = 0
		public var hiddenMismatches = 0
		public var stackSiteMismatches = 0
		public var stackCaseMismatches = 0
		public var stackRouteDependentCases = 0
		public var routeDependentAnswers = 0
		public var mismatchSamples = [String]()
		public var conflictSamples = [String]()
	}

	public static func report(of placeLevels: SeamPlaceLevels) -> Report {
		var report = Report()
		report.seamType = placeLevels.seamType.asSource
		report.places = placeLevels.places.count

		let graph = SeamPlaceGraph(places: placeLevels.places)
		report.nodes = graph.nodes.count
		report.edges = graph.nodes.reduce(0) { $0 + $1.parents.count }
		report.cases = graph.cases.count
		countVariants(of: graph, into: &report)

		// The places of each case, which hold today's answers.
		var placeIndicesByCase = [[Int]](repeating: [], count: graph.cases.count)
		for (placeIndex, caseIndex) in graph.caseIndexByPlace.enumerated() where caseIndex >= 0 {
			placeIndicesByCase[caseIndex].append(placeIndex)
		}

		var query = SeamPlaceGraph.Query(of: graph)
		for (caseIndex, placeCase) in graph.cases.enumerated() {
			let placeIndices = placeIndicesByCase[caseIndex]
			let places = placeIndices.map { placeLevels.places[$0] }
			let paths = places.prefix(3).map { $0.sitePath.map(\.label).joined(separator: ".") }.joined(separator: " | ")

			// The labels today's lists can hold: every label a level of the case's places binds. The graph's own
			// enumeration walks up from the owner instead, and the two must agree, since a case is its owner level.
			var labels = [String]()
			var seenLabels = Set<String>()
			for place in places {
				for level in place.levels {
					for declaration in level.declarations where seenLabels.insert(declaration.property.label).inserted {
						labels.append(declaration.property.label)
					}
				}
			}
			if Set(graph.labels(reaching: placeCase)) != seenLabels {
				report.labelSetMismatches += 1
				report.mismatches += 1
				appendSample("labels at \(paths): today \(labels.sorted()) graph \(graph.labels(reaching: placeCase).sorted())", to: &report)
			}

			// The nearest declaration of each label.
			let answersByLabelByPlace = places.map { place in
				var answerByLabel = [String: SeamPlaceGraph.Answer]()
				for uncarried in place.carriedUncarriedProperties {
					answerByLabel[uncarried.label] = SeamPlaceGraph.Answer(property: uncarried, kind: .uncarried)
				}
				for field in place.carriedFields {
					answerByLabel[field.label] = SeamPlaceGraph.Answer(property: field, kind: .field)
				}
				return answerByLabel
			}
			for label in labels {
				var today = Set<SeamPlaceGraph.Answer>()
				for answerByLabel in answersByLabelByPlace {
					today.insert(answerByLabel[label] ?? SeamPlaceGraph.Answer(property: nil, kind: .none))
				}
				let answers = query.answers(ofLabel: label, at: placeCase)
				report.queries += 1
				if answers.count > 1 {
					report.routeDependentAnswers += 1
				}
				guard today != answers else { continue }
				report.mismatches += 1
				appendSample("label \(label) at \(paths) (\(placeIndices.count) sites): today \(today.map(\.description).sorted()) query \(answers.map(\.description).sorted())", to: &report)
			}

			// The declarations a cycle re-entry hands the type built again.
			for label in labelsAsked(of: places, \.carriedCycleReentryProperties, \.reentryDeclarations) {
				let today = Set(places.map { place in place.carriedCycleReentryProperties.first { $0.label == label } })
				let answers = query.reentryDeclaration(ofLabel: label, at: placeCase)
				report.reentryQuestions += 1
				guard today != answers else { continue }
				report.reentryMismatches += 1
				report.mismatches += 1
				appendSample("re-entry label \(label) at \(paths) (\(placeIndices.count) sites): today \(spelled(today)) query \(spelled(answers))", to: &report)
			}

			// The declarations a fill's field of a seam parameter hides.
			var hiddenLabels = [String]()
			var seenHiddenLabels = Set<String>()
			for place in places {
				for property in place.carriedHiddenByFieldProperties where seenHiddenLabels.insert(property.label).inserted {
					hiddenLabels.append(property.label)
				}
				for level in place.levels {
					for declaration in level.declarations where declaration.isFieldOfSeamParameter && seenHiddenLabels.insert(declaration.property.label).inserted {
						hiddenLabels.append(declaration.property.label)
					}
				}
			}
			for label in hiddenLabels {
				let today = Set(places.map { place in place.carriedHiddenByFieldProperties.first { $0.label == label } })
				let answers = query.declarationHiddenByField(ofLabel: label, at: placeCase)
				report.hiddenQuestions += 1
				guard today != answers else { continue }
				report.hiddenMismatches += 1
				report.mismatches += 1
				appendSample("hidden label \(label) at \(paths): today \(spelled(today)) query \(spelled(answers))", to: &report)
			}

			// The stack each place is built with, per place from its own levels and per case from the graph.
			var today = Set<SeamPlaceGraph.StackEntry>()
			var distinctStacks = Set<[SeamPlaceGraph.StackEntry]>()
			for place in places {
				let carried = zip(place.carriedStack, place.carriedStackConcreteTypes).map { SeamPlaceGraph.StackEntry(property: $0, concreteType: $1) }
				today.formUnion(carried)
				distinctStacks.insert(carried)
				let derived = derivedStack(of: place)
				guard derived != carried else { continue }
				report.stackSiteMismatches += 1
				report.mismatches += 1
				appendSample("stack at \(place.sitePath.map(\.label).joined(separator: ".")): today \(spelled(carried)) derived \(spelled(derived))", to: &report)
			}
			if distinctStacks.count > 1 {
				report.stackRouteDependentCases += 1
			}
			let entries = query.stackEntries(at: placeCase)
			if today != entries {
				report.stackCaseMismatches += 1
				report.mismatches += 1
				appendSample("stack entries of case at \(paths): today \(today.count) query \(entries.count)", to: &report)
			}
		}
		report.graphCycles = query.graphCycles
		return report
	}

	/// The labels to ask about: those today's lists hold for the case's places, and those any level on their paths
	/// records, so a label the graph records and no place carries is asked too.
	private static func labelsAsked(
		of places: [SeamPlaceLevels.Place],
		_ carried: KeyPath<SeamPlaceLevels.Place, [Property]>,
		_ recorded: KeyPath<SeamPlaceLevels.Level, [Property]>,
	) -> [String] {
		var labels = [String]()
		var seenLabels = Set<String>()
		for place in places {
			for property in place[keyPath: carried] where seenLabels.insert(property.label).inserted {
				labels.append(property.label)
			}
			for level in place.levels {
				for property in level[keyPath: recorded] where seenLabels.insert(property.label).inserted {
					labels.append(property.label)
				}
			}
		}
		return labels
	}

	/// The stack `place`'s owner is built with, read from the place's own levels: each level's built type with the next
	/// level's property, down to a fill, whose tree is built beneath the filled seam's path.
	private static func derivedStack(of place: SeamPlaceLevels.Place) -> [SeamPlaceGraph.StackEntry] {
		var derived = [SeamPlaceGraph.StackEntry]()
		for (index, level) in place.levels.enumerated() {
			guard let builtType = level.builtType else {
				derived += zip(level.fillBaseStack, level.fillBaseConcreteTypes).map { SeamPlaceGraph.StackEntry(property: $0, concreteType: $1) }
				break
			}
			guard index + 1 < place.levels.count else { break }
			if let property = place.levels[index + 1].nextProperty {
				derived += SeamPlaceGraph.Query.entries(of: property, builtAs: builtType)
			}
		}
		return derived
	}

	/// How many nodes of one key the graph holds, and in what they differ.
	private static func countVariants(of graph: SeamPlaceGraph, into report: inout Report) {
		var firstByKey = [SeamPlaceGraph.NodeKey: SeamPlaceGraph.Node]()
		for node in graph.nodes {
			guard let first = firstByKey[node.key] else {
				firstByKey[node.key] = node
				continue
			}
			report.levelConflicts += 1
			let functionFacts = { (declarations: [SeamPlaceLevels.Level.Declaration]) in
				declarations.filter { !$0.isCycleParameter && !$0.isReboundByBuilderFunction }
			}
			if node.key.builtType == nil {
				report.fillLevelVariants += 1
			} else if first.declarations == node.declarations {
				report.sendableOnlyVariants += 1
			} else if functionFacts(first.declarations) == functionFacts(node.declarations) {
				report.levelConflictsOnlyInFunctionFacts += 1
			} else {
				report.otherVariants += 1
				if report.conflictSamples.count < 3 {
					report.conflictSamples.append("level \(node.key.builtType?.asSource ?? "fill") before \(node.key.nextProperty?.asSource ?? "-"): \(describe(first)) vs \(describe(node))")
				}
			}
		}
		report.types = firstByKey.count
	}

	private static func appendSample(_ sample: String, to report: inout Report) {
		guard report.mismatchSamples.count < 5 else { return }
		report.mismatchSamples.append(sample)
	}

	private static func spelled(_ properties: Set<Property?>) -> [String] {
		properties.map { $0?.asSource ?? "none" }.sorted()
	}

	private static func spelled(_ entries: [SeamPlaceGraph.StackEntry]) -> [String] {
		entries.map { "\($0.property.asSource)@\($0.concreteType.asSource)" }
	}

	static func describe(_ node: SeamPlaceGraph.Node) -> String {
		let declarations = node.declarations.map { declaration in
			var text = declaration.property.asSource
			if !declaration.isBoundBeforeNextProperty {
				text += "(after)"
			}
			if declaration.isCycleParameter {
				text += "(cycle)"
			}
			if declaration.isReboundByBuilderFunction {
				text += "(rebound)"
			}
			return text
		}
		return "[\(declarations.joined(separator: ", "))]\(node.opensSendableFunction ? " @Sendable" : "")"
	}
}
