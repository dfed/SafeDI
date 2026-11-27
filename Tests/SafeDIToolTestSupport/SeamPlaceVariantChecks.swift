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

extension SeamPlaceLevels {
	/// Test only, deleted before merge: where the place graph's joint label variants (`Places.Query.labelVariants`) and a
	/// stacked declaration's depths below a case's owner (`Places.Query.depthsBelowOwner`) differ from what each place's own
	/// route reads, evaluated route by route. The routes are the per-site walk's, one per place; a seam with more places
	/// than `SeamPlaceVariantChecks.siteLimit` is left to the other checks, since this one evaluates every label on every
	/// route.
	var placeVariantMismatches: [String] {
		guard let observation = placesObservation, observation.siteHoles.count <= SeamPlaceVariantChecks.siteLimit else { return [] }
		return SeamPlaceVariantChecks.mismatches(of: observation)
	}
}

/// What a cycle re-entering a level beneath a parent hands, each asked once
/// (`Places.cycleReentries(ofLevel:beneath:context:)`), for the checks that evaluate every route.
final class CycleReentriesAlongRoutes {
	init(of places: SeamSignature.Places) {
		self.places = places
		context = places.cycleContext()
	}

	func reentries(ofLevel level: Int, beneath parent: Int) -> [SeamSignature.Places.CycleReentry] {
		let key = Key(level: level, parent: parent)
		if let known = reentriesByKey[key] {
			return known
		}
		let reentries = places.cycleReentries(ofLevel: level, beneath: parent, context: context)
		reentriesByKey[key] = reentries
		return reentries
	}

	private struct Key: Hashable {
		let level: Int
		let parent: Int
	}

	private let places: SeamSignature.Places
	private let context: SeamSignature.Places.CycleContext
	private var reentriesByKey = [Key: [SeamSignature.Places.CycleReentry]]()
}

enum SeamPlaceVariantChecks {
	static let siteLimit = 256

	static func mismatches(of observation: SeamSignature.Places.Observation) -> [String] {
		let places = observation.places
		let query = SeamSignature.Places.Query(of: places)
		let reentriesAlongRoutes = CycleReentriesAlongRoutes(of: places)
		var routesByCase = [Int: [SeamSignature.Places.Route]]()
		for (caseIndex, route) in zip(observation.caseIndexBySite, observation.routeBySite) where caseIndex >= 0 {
			routesByCase[caseIndex, default: []].append(route)
		}
		// A place several calls present is held by one site, at the first call's route; each other call's route reads too.
		for (caseIndex, route) in observation.laterRoutesOfPassedUpCases where !(routesByCase[caseIndex] ?? []).contains(route) {
			routesByCase[caseIndex, default: []].append(route)
		}
		var mismatches = [String]()
		for caseIndex in routesByCase.keys.sorted() {
			let routes = routesByCase[caseIndex] ?? []
			mismatches += self.mismatches(of: caseIndex, routes: routes, query: query, observation: observation, excluding: [], reentriesAlongRoutes: reentriesAlongRoutes)
			// The routes whose stack holds none of a few of the entries the case's routes stack.
			var entries = [SeamSignature.Places.StackEntry]()
			for route in routes {
				for entry in query.stack(along: route) where !entries.contains(entry) {
					entries.append(entry)
				}
			}
			for entry in entries.prefix(4) {
				let kept = routes.filter { !query.stack(along: $0).contains(entry) }
				let excludingQuery = SeamSignature.Places.Query(of: places, excludingRoutesWhoseStackHolds: [entry])
				mismatches += self.mismatches(of: caseIndex, routes: kept, query: excludingQuery, observation: observation, excluding: [entry], reentriesAlongRoutes: reentriesAlongRoutes)
			}
		}
		return mismatches
	}

	static func mismatches(of caseIndex: Int, routes: [SeamSignature.Places.Route], query: SeamSignature.Places.Query, observation: SeamSignature.Places.Observation, excluding excluded: [SeamSignature.Places.StackEntry], reentriesAlongRoutes: CycleReentriesAlongRoutes) -> [String] {
		let places = observation.places
		var mismatches = [String]()
		do {
			let excluding = excluded.isEmpty ? "" : " excluding \(excluded.map { "\($0.property.asSource)@\($0.concreteType.asSource)" })"
			let naming = (query.representativeRoute(of: caseIndex).map { query.sitePath(along: $0).map(\.label).joined(separator: ".") } ?? "?") + excluding
			guard !routes.isEmpty else {
				let variants = query.labels(reaching: caseIndex).flatMap { query.labelVariants(ofLabel: $0, at: caseIndex) }
				return variants.isEmpty ? [] : ["The label variants at \(naming) in \(observation.seamType.asSource) list \(variants.count) values where every route is excluded"]
			}
			for label in query.labels(reaching: caseIndex) {
				let variants = query.labelVariants(ofLabel: label, at: caseIndex)
				let valueByRoute = routes.map { (route: $0, value: value(ofLabel: label, along: $0, at: caseIndex, in: places, reentriesAlongRoutes: reentriesAlongRoutes)) }
				let distinctValues = Set(valueByRoute.map(\.value))
				let variantValues = variants.map { value(ofLabel: label, along: $0.leastRoute, at: caseIndex, in: places, reentriesAlongRoutes: reentriesAlongRoutes) }
				if Set(variantValues).count != variants.count || Set(variantValues) != distinctValues {
					mismatches.append("The label variants of \(label) at \(naming) in \(observation.seamType.asSource) are \(variants.count) over \(Set(variantValues).count) values; its places' routes read \(distinctValues.count)")
					continue
				}
				for (variant, value) in zip(variants, variantValues) {
					let least = valueByRoute.filter { $0.value == value }.map(\.route).min { precedes($0, $1, query) }
					if variant.answer != value.answer || least.map({ sortKeys(of: $0, query) }) != sortKeys(of: variant.leastRoute, query) {
						mismatches.append("The label variant of \(label) at \(naming) in \(observation.seamType.asSource) reading \(value.answer) names another route than the least of its places’ routes")
					}
				}
			}
			// Every entry any route of the case stacks, at each depth it is stacked at.
			var depthsByEntry = [SeamSignature.Places.StackEntry: [Int: [SeamSignature.Places.Route]]]()
			var entries = [SeamSignature.Places.StackEntry]()
			for route in routes {
				let stack = query.stack(along: route)
				for entry in stack {
					guard let depth = depthBeneath(entry, in: stack) else { continue }
					if depthsByEntry[entry] == nil {
						entries.append(entry)
					}
					depthsByEntry[entry, default: [:]][depth, default: []].append(route)
				}
			}
			for entry in entries {
				let expected = depthsByEntry[entry] ?? [:]
				let depths = query.depthsBelowOwner(ofProperty: entry.property, builtAs: entry.concreteType, at: caseIndex)
				let leastByDepth = expected.mapValues { $0.min { precedes($0, $1, query) } }
				let matches = Set(depths.map(\.depth)) == Set(expected.keys) && depths.count == expected.count && depths.allSatisfy { depth in
					leastByDepth[depth.depth].flatMap(\.self).map { sortKeys(of: $0, query) } == sortKeys(of: depth.leastRoute, query)
				}
				if !matches {
					mismatches.append("The depths of \(entry.property.asSource) below \(naming) in \(observation.seamType.asSource) are \(depths.map(\.depth)); its places’ stacks hold it at \(expected.keys.sorted())")
				}
			}
		}
		return mismatches
	}

	/// What a place at the end of `route` reads of `label`, evaluated along the route alone.
	struct Value: Hashable {
		let answer: SeamSignature.Places.Answer
		/// The outermost re-entry below the label's declaration: its level, its parent and what it hands the type built
		/// again, which the route's stack decides.
		let reentry: Reentry?
		/// The field and the declaration it hides.
		let hidden: [Int]

		struct Reentry: Hashable {
			let level: Int
			let parent: Int
			let reentry: SeamSignature.Places.CycleReentry
		}
	}

	static func value(ofLabel label: String, along route: SeamSignature.Places.Route, at caseIndex: Int, in places: SeamSignature.Places, reentriesAlongRoutes: CycleReentriesAlongRoutes) -> Value {
		let placeCase = places.cases[caseIndex]
		let tracksReentry = places.levels[placeCase.ownerLevel].key.nextProperty?.label != label
		var function: Int? = placeCase.siteOpensSendableFunction ? SeamSignature.Places.Answer.siteFunction : nil
		var reentry: Value.Reentry?
		let levels = Array(route.levels.reversed())
		for (position, level) in levels.enumerated() {
			let declarations = places.declarations(ofLevel: level)
			if let index = declarations.lastIndex(where: { $0.field.property.label == label }) {
				let declaration = declarations[index]
				let answer: SeamSignature.Places.Answer = if !declaration.isBoundBeforeNextProperty {
					.uncarried(level: level, declaration: index)
				} else if let function {
					declaration.isSeamParameter ? .callersOwn : .boundOutsideSendableFunction(level: level, declaration: index, functionLevel: function)
				} else {
					.field(level: level, declaration: index)
				}
				var hidden = [Int]()
				if case .field = answer, declaration.fillFieldHiding != nil {
					// The nearest declaration of the label before the field: earlier at its level, or above.
					let nearest: (level: Int, index: Int)? = if let earlier = declarations[..<index].lastIndex(where: { $0.field.property.label == label }) {
						(level, earlier)
					} else {
						levels[(position + 1)...].lazy.compactMap { above in
							places.declarationsBeforeAnyNextProperty(ofLevel: above).lastIndex { $0.field.property.label == label }.map { (above, $0) }
						}.first
					}
					if let nearest, places.declaration(level: nearest.level, declaration: nearest.index).field.property != declaration.field.property {
						hidden = [level, index, nearest.level, nearest.index]
					}
				}
				return Value(answer: answer, reentry: reentry, hidden: hidden)
			}
			guard position + 1 < levels.count else { break }
			if tracksReentry, let own = reentriesAlongRoutes.reentries(ofLevel: level, beneath: levels[position + 1]).first(where: { $0.property.label == label }) {
				reentry = Value.Reentry(level: level, parent: levels[position + 1], reentry: own)
			}
			if function == nil, places.levels[level].opensSendableFunction != nil {
				function = level
			}
		}
		return Value(answer: .callersOwn, reentry: reentry, hidden: [])
	}

	/// The declarations beneath the innermost `entry` of `stack`, as `Hole.fillPathDeclarationsBeneath` counts them.
	static func depthBeneath(_ entry: SeamSignature.Places.StackEntry, in stack: [SeamSignature.Places.StackEntry]) -> Int? {
		stack.firstIndex(of: entry).map { index in
			stack[..<index].indices.count { stack[$0 + 1].property.asLazilyInstantiatedInstanceProperty != stack[$0].property }
		}
	}

	/// Whether `lhs` precedes `rhs` by the properties declared along each, root first: by location, then, where the locations
	/// are equal, by label; a route whose properties are a prefix of the other's first.
	static func precedes(_ lhs: SeamSignature.Places.Route, _ rhs: SeamSignature.Places.Route, _ query: SeamSignature.Places.Query) -> Bool {
		let lhsKeys = sortKeys(of: lhs, query)
		let rhsKeys = sortKeys(of: rhs, query)
		for (lhsKey, rhsKey) in zip(lhsKeys, rhsKeys) where lhsKey.location != rhsKey.location || lhsKey.label != rhsKey.label {
			guard lhsKey.location == rhsKey.location else {
				return Dependency.DeclarationLocation.precedesInSourceOrder(lhsKey.location, rhsKey.location)
			}
			return lhsKey.label < rhsKey.label
		}
		return lhsKeys.count < rhsKeys.count
	}

	/// What orders `route`: each declared property's location and label, root first.
	static func sortKeys(of route: SeamSignature.Places.Route, _ query: SeamSignature.Places.Query) -> [SortKey] {
		query.declaredPathToOwner(along: route).map { SortKey(location: $0.declarationLocation, label: $0.property.label) }
	}

	struct SortKey: Equatable {
		let location: Dependency.DeclarationLocation?
		let label: String
	}
}
