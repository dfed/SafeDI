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
import Testing

/// Test only, deleted with the per-site walk: whether the observer compares the place graph's answers along each route
/// with the per-site walk's (`placesOracleMismatches`, `placeVariantMismatches`). The query answers over every route of
/// the graph, and the way down from a scope a cycle closes on is read from the graph alone, so on a tangle of cycles no
/// type always encloses, where which member a call closes on depends on the members above it, the graph answers routes
/// no tree builds and the walk's answers along a tree's route can differ. Only such a tangle's tests turn it off; the
/// values a fill reads on a tangle are asserted against the inline build (`SafeDIToolSeamHoleOnCycleTests`, "Laps
/// around a ring").
enum SeamPlaceTreeRoutes {
	@TaskLocal static var areCompared = true
}

extension SeamPlaceLevels {
	/// A description of each place whose levels, read nearest first, do not hold exactly the fields of its scope struct and
	/// the declarations it carries no field of: each label is decided by the nearest level that declares it, a field where
	/// that level binds it before the next property on the path, and the labels are in the order the levels bind them.
	var pathStructMismatches: [String] {
		places.compactMap { place in
			struct Decision {
				let outerLevelIndex: Int
				let position: Int
				let declaration: Level.Declaration
			}
			var decisionsByLabel = [String: Decision]()
			for (nearestLevelIndex, level) in place.levels.enumerated() {
				// Within a level, a later declaration of a label is the nearer one.
				for (position, declaration) in level.declarations.enumerated().reversed() where decisionsByLabel[declaration.property.label] == nil {
					decisionsByLabel[declaration.property.label] = Decision(outerLevelIndex: place.levels.count - 1 - nearestLevelIndex, position: position, declaration: declaration)
				}
			}
			let decisions = decisionsByLabel.values.sorted { ($0.outerLevelIndex, $0.position) < ($1.outerLevelIndex, $1.position) }
			let fields = decisions.filter(\.declaration.isBoundBeforeNextProperty).map(\.declaration.property)
			let uncarriedProperties = decisions.filter { !$0.declaration.isBoundBeforeNextProperty }.map(\.declaration.property)
			guard fields != place.fields || uncarriedProperties != place.uncarriedProperties else { return nil }
			return "The levels of the place `\(Self.pathDescription(of: place))` of `\(seamType.asSource)` hold the fields \(Self.listDescription(of: fields)) and leave \(Self.listDescription(of: uncarriedProperties)) uncarried, but its scope struct holds \(Self.listDescription(of: place.fields)) and leaves \(Self.listDescription(of: place.uncarriedProperties)) uncarried."
		}
	}

	/// A description of each level that one build of its type gives with other fields than another build of the same type
	/// does: the level a type holds before a property, or the seam's root's level, is the same on every path, inside a fill
	/// too, whose tree starts its children in the order of its types as any other. The parameters of a builder function a
	/// lazy cycle closes on, and the instantiators a loop member's builder function wraps again, are left out
	/// (`Level.fieldsOfType`): facts of the function, which another build of the type need not take or make.
	func levelDisagreements() -> [String] {
		struct Key: Hashable {
			let builtType: TypeDescription
			let nextProperty: Property
			let isSeamRoot: Bool
		}
		var firstFieldsByKey = [Key: (fields: [Property], place: Place)]()
		var disagreements = [String]()
		for place in places {
			for (index, level) in place.levels.enumerated() {
				guard let builtType = level.builtType, let nextProperty = level.nextProperty else { continue }
				let key = Key(builtType: builtType, nextProperty: nextProperty, isSeamRoot: index == place.levels.count - 1)
				if let (firstFields, firstPlace) = firstFieldsByKey[key] {
					guard firstFields != level.fieldsOfType else { continue }
					disagreements.append("`\(builtType.asSource)` holds \(Self.listDescription(of: firstFields)) before `\(nextProperty.asSource)` on the path to the place `\(Self.pathDescription(of: firstPlace))` of `\(seamType.asSource)`, but \(Self.listDescription(of: level.fieldsOfType)) on the path to the place `\(Self.pathDescription(of: place))`.")
				} else {
					firstFieldsByKey[key] = (level.fieldsOfType, place)
				}
			}
		}
		return disagreements
	}

	/// Shadow only: a description of each answer the per-type route query (`SeamRouteQueryShadow`) gives otherwise than
	/// today's per-site walk, so that the graph fuzzer's corpora fail a graph on which the two differ.
	var routeQueryShadowMismatches: [String] {
		let report = SeamRouteQueryShadow.report(of: self)
		guard report.mismatches > 0 else { return [] }
		return ["The route query answers \(report.mismatches) questions of `\(seamType.asSource)` otherwise than the per-site walk: " + report.mismatchSamples.joined(separator: "; ")]
	}

	/// The place graph's test read, deleted when places come from facts: each way the seam's place graph answers otherwise
	/// than its per-site walk (`SeamPlacesOracle`).
	var placesOracleMismatches: [String] {
		placesObservation.map(SeamPlacesOracle.mismatches(of:)) ?? []
	}

	/// An observer that records an issue for each place whose levels do not hold its fields (`pathStructMismatches`), then
	/// hands the levels to `enclosingObserver`, the observer the caller set, if any.
	static func checkingPathStructs(handingOn enclosingObserver: (@Sendable (SeamPlaceLevels) -> Void)?) -> @Sendable (SeamPlaceLevels) -> Void {
		{ placeLevels in
			// The place graph must answer as the per-site walk (`SeamPlacesOracle`) until places come from facts.
			let routeAnswerMismatches = SeamPlaceTreeRoutes.areCompared ? placeLevels.placesOracleMismatches + placeLevels.placeVariantMismatches : []
			for mismatch in placeLevels.pathStructMismatches + routeAnswerMismatches + placeLevels.routeStepMismatches + placeLevels.placeCaseFactMismatches {
				Issue.record(Comment(rawValue: mismatch))
			}
			enclosingObserver?(placeLevels)
		}
	}

	private static func pathDescription(of place: Place) -> String {
		place.sitePath.map(\.label).joined(separator: ".")
	}

	private static func listDescription(of properties: [Property]) -> String {
		"[" + properties.map(\.asSource).joined(separator: ", ") + "]"
	}
}

/// What `operation` returns, with each distinct level disagreement (`SeamPlaceLevels.levelDisagreements`) of the holes
/// of every seam the tool computes while it runs, in the order the tool first computes them.
func collectingPlaceLevelDisagreements<Result>(during operation: () async throws -> Result) async rethrows -> (result: Result, disagreements: [String]) {
	let (stream, continuation) = AsyncStream.makeStream(of: [String].self)
	let enclosingObserver = SeamPlaceLevels.observer
	let result = try await SeamPlaceLevels.$observer.withValue({ placeLevels in
		continuation.yield(placeLevels.levelDisagreements() + placeLevels.routeQueryShadowMismatches + placeLevels.placesOracleMismatches + placeLevels.routeStepMismatches + placeLevels.placeVariantMismatches + placeLevels.placeCaseFactMismatches)
		enclosingObserver?(placeLevels)
	}) {
		try await operation()
	}
	continuation.finish()
	var disagreements = [String]()
	for await computedDisagreements in stream {
		for disagreement in computedDisagreements where !disagreements.contains(disagreement) {
			disagreements.append(disagreement)
		}
	}
	return (result, disagreements)
}

/// What `operation` returns, with each key a root reaches root functions of with two texts
/// (`RootFunctionHoisting.observer`), in the order the tool first reaches them: each root's functions of one key must have
/// one text, which the generator never compares.
func collectingRootFunctionKeyDisagreements<Result>(during operation: () async throws -> Result) async rethrows -> (result: Result, disagreements: [String]) {
	let (stream, continuation) = AsyncStream.makeStream(of: [RootFunctionHoisting.Occurrence].self)
	let enclosingObserver = RootFunctionHoisting.observer
	let result = try await RootFunctionHoisting.$observer.withValue({ occurrences in
		continuation.yield(occurrences)
		enclosingObserver?(occurrences)
	}) {
		try await operation()
	}
	continuation.finish()
	var disagreements = [String]()
	for await occurrences in stream {
		var textByKey = [RootFunctionKey: RootFunctionHoisting.Occurrence]()
		for occurrence in occurrences {
			guard let first = textByKey[occurrence.key] else {
				textByKey[occurrence.key] = occurrence
				continue
			}
			let disagreement = "Root functions \(first.name) and \(occurrence.name) share a key with different text:\n\(first.text)\n---\n\(occurrence.text)"
			if first.text != occurrence.text, !disagreements.contains(disagreement) {
				disagreements.append(disagreement)
			}
		}
	}
	return (result, disagreements)
}
