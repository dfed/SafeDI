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

// The cases of a seam's place graph assembled from its facts drafts: the seam's own cases, then the cases its calls pass
// up, each naming its owner level and naming route by the assembled levels. Test only, until the assembled graph replaces
// the walk's under a test switch.

/// A seam's assembled cases, with the index of each by what drafted it.
struct SeamPlacesCaseAssembly {
	/// An own case by one of its sites' owner declaration and hole edge, and its family.
	struct OwnKey: Hashable {
		let declaration: DeclarationID
		let edge: Int32
		let isSendable: Bool
	}

	/// A passed-up case by the level of its call, its family and the called case it refers to.
	struct PassedUpKey: Hashable {
		let owner: SeamPlacesLevelID
		let isSendable: Bool
		let calledCase: SeamSignature.Places.CalledCase
	}

	let cases: [SeamSignature.Places.Case]
	let unassembled: [String]
	let ownCaseByKey: [OwnKey: Int]
	let passedUpCaseByKey: [PassedUpKey: Int]
}

extension SeamPlacesLevelAssembly {
	/// The assembled levels of a drafted route, root first: each drafted level as it is built in line, and after a call
	/// whose next edge is a fill, the fill's entry level. `nil` where a level of the route was not assembled.
	func assembledRoute(_ route: [SeamPlacesLevelID]) -> [Int]? {
		var assembledRoute = [Int]()
		for level in route {
			guard let index = inLineLevelByDraft[level] else { return nil }
			assembledRoute.append(index)
			if let entryLevel = entryLevelByCall[level] {
				assembledRoute.append(entryLevel)
			}
		}
		return assembledRoute
	}

	/// The cases of `drafts`, whose levels these are: its own cases in builder-label order, then the cases its calls pass
	/// up, in the order of the calls. A passed-up case is owned by the level of the called seam its call encloses. Cases
	/// that present the same places, those whose references lead to one own case of one seam (`origin(of:through:)`),
	/// name the first of them, and only that first one has a naming route: the least route to its owner. The cases whose
	/// levels were not assembled are left out, and named in `unassembled`. With `access`, each case holds the narrowest
	/// access of its places' builders, with the cause of the first place in site order that has it.
	func cases(of drafts: SeamPlacesDrafts, access: SeamPlacesFieldAccess? = nil) -> SeamPlacesCaseAssembly {
		var cases = [SeamSignature.Places.Case]()
		var unassembled = [String]()
		var ownCaseByKey = [SeamPlacesCaseAssembly.OwnKey: Int]()
		var passedUpCaseByKey = [SeamPlacesCaseAssembly.PassedUpKey: Int]()
		for draftCase in drafts.cases {
			guard let owner = inLineLevelByDraft[draftCase.owner], let namingRoute = assembledRoute(draftCase.namingRoute) else {
				unassembled.append("own case of level \(draftCase.owner.variant).\(draftCase.owner.edge)")
				continue
			}
			var narrowestAccess: SeamSignature.Places.Case.Access?
			for site in draftCase.sites {
				let declaration = drafts.world.declaration(of: site.owner.variant)
				ownCaseByKey[SeamPlacesCaseAssembly.OwnKey(declaration: declaration, edge: site.owner.edge, isSendable: draftCase.isBuiltInSendableFunction)] = cases.count
				let targets = drafts.world.edges(from: declaration)
				let ownerNode = drafts.world.graph.nodes[Int(declaration)]
				if let access, let property = drafts.world.graph.nodes[Int(targets[targets.startIndex + Int(site.owner.edge)])].property {
					let placeAccess = access.builderAccess(ofPlace: property, ownedBy: ownerNode.scope.instantiable.concreteInstantiable)
					if narrowestAccess.map({ placeAccess.level < $0.level }) ?? true {
						narrowestAccess = placeAccess
					}
				}
			}
			cases.append(SeamSignature.Places.Case(
				ownerLevel: owner,
				isBuiltInSendableFunction: draftCase.isBuiltInSendableFunction,
				siteOpensSendableFunction: draftCase.siteOpensSendableFunction,
				passedUp: nil,
				namingRoute: namingRoute,
				narrowestAccess: narrowestAccess,
			))
		}
		let passedUp = drafts.passedUpCases()
		let naming = SeamPlacesDrafts.namingRoutes(
			to: passedUp.map { draftCase in ([draftCase.owner], draftCase.siteOpensSendableFunction ? .either : draftCase.isBuiltInSendableFunction ? .opensSendableFunction : .plain) },
			in: drafts.world,
			buildsInLine: drafts.buildsInLine,
			holdsPlace: drafts.holdsPlace,
		)
		let world = drafts.world
		let seamType = world.graph.nodes[Int(world.declaration(of: world.rootVariant(0)))].scope.instantiable.concreteInstantiable
		// The builders each passed-up case's call passes, by the case's index: where its reference leads.
		var calledBuildersByCase = [Int: CalledBuilders]()
		for (draftCase, route) in zip(passedUp, naming.routes) {
			let targets = world.edges(from: world.declaration(of: draftCase.owner.variant))
			let call = world.graph.nodes[Int(targets[targets.startIndex + Int(draftCase.owner.edge)])]
			guard let owner = passingUpLevelByCall[draftCase.owner], let callRoute = assembledRoute(route), let calledCase = draftCase.passedUp, let calledBuilders = call.scope.calledBuilders else {
				unassembled.append("passed-up case of level \(draftCase.owner.variant).\(draftCase.owner.edge)")
				continue
			}
			calledBuildersByCase[cases.count] = calledBuilders
			passedUpCaseByKey[SeamPlacesCaseAssembly.PassedUpKey(owner: draftCase.owner, isSendable: draftCase.isBuiltInSendableFunction, calledCase: calledCase)] = cases.count
			var narrowestAccess: SeamSignature.Places.Case.Access?
			if let access {
				for (hole, caseIndex) in zip(calledBuilders.holes, calledBuilders.caseIndexByHole) where caseIndex == calledCase.caseIndex {
					let placeAccess = access.builderAccess(passingUp: hole)
					if narrowestAccess.map({ placeAccess.level < $0.level }) ?? true {
						narrowestAccess = placeAccess
					}
				}
			}
			cases.append(SeamSignature.Places.Case(
				ownerLevel: owner,
				isBuiltInSendableFunction: draftCase.isBuiltInSendableFunction,
				siteOpensSendableFunction: draftCase.siteOpensSendableFunction,
				passedUp: calledCase,
				namingRoute: callRoute + [owner],
				narrowestAccess: narrowestAccess,
			))
		}
		// The cases that present the same places name the first of them, and only that first one keeps its naming route:
		// cases that share a place, by the sites of the called case's holes, or by the own case of this seam a ring of seams
		// leads back to (`origin(ofCaseAt:in:calledBuildersByCase:seamType:)`), are one set, named by its least case.
		enum PlaceKey: Hashable {
			case own(Int)
			case site(SeamSignature.Hole.Site)
		}
		var leastCaseByKey = [PlaceKey: Int]()
		var parent = Array(cases.indices)
		func root(of index: Int) -> Int {
			var root = index
			while parent[root] != root {
				root = parent[root]
			}
			parent[index] = root
			return root
		}
		for index in cases.indices {
			var keys = [PlaceKey]()
			if let calledCase = cases[index].passedUp, let calledBuilders = calledBuildersByCase[index] {
				for (hole, caseIndex) in zip(calledBuilders.holes, calledBuilders.caseIndexByHole) where caseIndex == calledCase.caseIndex {
					keys.append(hole.scopeSeamType == seamType ? .own(Self.origin(ofCaseAt: index, in: cases, calledBuildersByCase: calledBuildersByCase, seamType: seamType).caseIndex) : .site(hole.site))
				}
				if keys.isEmpty {
					keys.append(.own(Self.origin(ofCaseAt: index, in: cases, calledBuildersByCase: calledBuildersByCase, seamType: seamType).caseIndex))
				}
			} else {
				keys.append(.own(index))
			}
			for key in keys {
				guard let earlier = leastCaseByKey[key] else {
					leastCaseByKey[key] = index
					continue
				}
				let (first, other) = (root(of: earlier), root(of: index))
				parent[max(first, other)] = min(first, other)
			}
		}
		// A call takes the builder of the places it presents `@Sendable` where it is made inside a `@Sendable` function; a call
		// that presents a place of this seam's own, which a ring of seams passes back, also where the called seam's place is
		// taken `@Sendable`.
		var isPassedOnSendable = cases.map { $0.passedUp != nil && $0.isBuiltInSendableFunction }
		for index in cases.indices {
			guard let calledCase = cases[index].passedUp, let calledBuilders = calledBuildersByCase[index] else { continue }
			let passesOwnPlaceOnSendable = zip(calledBuilders.holes, calledBuilders.caseIndexByHole).contains { hole, caseIndex in
				caseIndex == calledCase.caseIndex && hole.site.seamType == seamType && (cases[index].isBuiltInSendableFunction || hole.isSendable)
			}
			if passesOwnPlaceOnSendable {
				let origin = Self.origin(ofCaseAt: index, in: cases, calledBuildersByCase: calledBuildersByCase, seamType: seamType)
				if origin.seamType == seamType, cases.indices.contains(origin.caseIndex) {
					isPassedOnSendable[origin.caseIndex] = true
				}
			}
		}
		for index in cases.indices where root(of: index) != index || isPassedOnSendable[index] {
			let placeCase = cases[index]
			cases[index] = SeamSignature.Places.Case(
				ownerLevel: placeCase.ownerLevel,
				isBuiltInSendableFunction: placeCase.isBuiltInSendableFunction,
				siteOpensSendableFunction: placeCase.siteOpensSendableFunction,
				passedUp: placeCase.passedUp,
				firstCasePresentingSamePlaces: root(of: index) == index ? nil : root(of: index),
				isPassedOnSendable: isPassedOnSendable[index],
				namingRoute: root(of: index) == index ? placeCase.namingRoute : [],
				narrowestAccess: placeCase.narrowestAccess,
			)
		}
		return SeamPlacesCaseAssembly(cases: cases, unassembled: unassembled, ownCaseByKey: ownCaseByKey, passedUpCaseByKey: passedUpCaseByKey)
	}

	/// The own case of the seam that holds the places the case at `index` of `cases`, a seam's graph, presents: the case
	/// itself where it is the seam's own, else the called seam's case its reference names, or the first case presenting the
	/// same places there, followed through the references of the seams beneath, and of the seam's own graph where a ring of
	/// seams leads back to it, until a case of a seam's own places. Each step is a lookup, and a case seen twice ends the
	/// walk, so it is bounded by the cases of the seams beneath.
	static func origin(ofCaseAt index: Int, in cases: [SeamSignature.Places.Case], calledBuildersByCase: [Int: CalledBuilders], seamType: TypeDescription) -> SeamSignature.Places.CalledCase {
		var current = SeamSignature.Places.CalledCase(seamType: seamType, isPublicMock: false, caseIndex: index)
		var seen = Set<SeamSignature.Places.CalledCase>()
		// The graph `current` is a case of, and how its seams beneath are found: `nil` for the seam's own.
		var calledBuilders: CalledBuilders?
		var places: SeamSignature.Places?
		while seen.insert(current).inserted {
			let next: SeamSignature.Places.CalledCase
			if current.seamType == seamType, !current.isPublicMock {
				guard cases.indices.contains(current.caseIndex), let passedUp = cases[current.caseIndex].passedUp, let builders = calledBuildersByCase[current.caseIndex] else { return current }
				next = passedUp
				calledBuilders = builders
				places = builders.places
			} else {
				guard let calledPlaces = places, calledPlaces.cases.indices.contains(current.caseIndex) else { return current }
				let firstIndex = calledPlaces.cases[current.caseIndex].firstCasePresentingSamePlaces ?? current.caseIndex
				guard calledPlaces.cases.indices.contains(firstIndex), let passedUp = calledPlaces.cases[firstIndex].passedUp else {
					return SeamSignature.Places.CalledCase(seamType: current.seamType, isPublicMock: current.isPublicMock, caseIndex: firstIndex)
				}
				next = passedUp
				places = calledBuilders?.placesOfSeamsBeneath(passedUp)?.places
			}
			current = next
		}
		return current
	}

	/// Each case of a graph spelled by its kind, family and owner level's key, its naming route's keys, and the first case
	/// presenting the same places: what tells cases of two graphs of one seam apart, whatever their levels' indices.
	static func spellings(of cases: [SeamSignature.Places.Case], levels: [SeamSignature.Places.Level]) -> [String] {
		func spelledKey(_ key: SeamSignature.Places.LevelKey) -> String {
			"\(key.builtType?.asSource ?? "fill") before \(key.nextProperty?.label ?? "none")"
		}
		func head(of placeCase: SeamSignature.Places.Case) -> String {
			let kind = placeCase.passedUp.map { "passed up \($0.seamType.asSource)\($0.isPublicMock ? " (public mock)" : "") case \($0.caseIndex)" } ?? "own"
			let family = "\(placeCase.isBuiltInSendableFunction ? "sendable" : "plain")\(placeCase.siteOpensSendableFunction ? ", site opening" : "")"
			return "\(kind), \(family), owner \(levels.indices.contains(placeCase.ownerLevel) ? spelledKey(levels[placeCase.ownerLevel].key) : "out of range")"
		}
		return cases.map { placeCase in
			let route = placeCase.namingRoute.map { levels.indices.contains($0) ? spelledKey(levels[$0].key) : "out of range" }.joined(separator: " / ")
			let first = placeCase.firstCasePresentingSamePlaces.map { cases.indices.contains($0) ? head(of: cases[$0]) : "out of range" } ?? "none"
			return "\(head(of: placeCase)); route \(route); first presenting \(first)"
		}
	}

	/// How the assembled cases differ from the cases of `places`, a seam's stored graph: each case's kind, family, owner
	/// level and naming route, spelled by the levels' keys, and the first case presenting the same places by its spelling;
	/// then whether the order agrees. The first line is a count report. Test only.
	func caseDifferences(of drafts: SeamPlacesDrafts, from places: SeamSignature.Places) -> [String] {
		let caseAssembly = cases(of: drafts)
		let (assembledCases, unassembled) = (caseAssembly.cases, caseAssembly.unassembled)
		let stored = Self.spellings(of: places.cases, levels: places.levels)
		let assembled = Self.spellings(of: assembledCases, levels: levels)
		var storedCounts = [String: Int]()
		for spelling in stored {
			storedCounts[spelling, default: 0] += 1
		}
		var assembledCounts = [String: Int]()
		for spelling in assembled {
			assembledCounts[spelling, default: 0] += 1
		}
		let alike = storedCounts.reduce(0) { $0 + min($1.value, assembledCounts[$1.key] ?? 0) }
		// What the stored cases carry beyond these fields, which the assembly does not give yet.
		let withAdditions = places.cases.count { placeCase in
			placeCase.isPassedOnSendable || !placeCase.calledCopyDeclarations.isEmpty || !placeCase.uncarriedReplacedOnPathsToCalls.isEmpty || !placeCase.reenteringCallDeclarations.isEmpty || !placeCase.reenteringPlaceFields.isEmpty
		}
		let order = stored == assembled ? "same order" : Set(stored) == Set(assembled) && stored.count == assembled.count ? "order differs" : "cases differ"
		var differences = ["report: assembled cases: \(places.cases.count) stored, \(assembledCases.count) assembled, \(alike) alike, \(unassembled.count) unassembled, \(withAdditions) stored with additions, \(order)"]
		differences += unassembled.map { "assembled cases: unassembled: \($0)" }
		differences += storedCounts.keys.filter { storedCounts[$0] != assembledCounts[$0] }.sorted().map { "assembled cases: stored \(storedCounts[$0] ?? 0), assembled \(assembledCounts[$0] ?? 0): \($0)" }
		differences += assembledCounts.keys.filter { storedCounts[$0] == nil }.sorted().map { "assembled cases: only assembled \(assembledCounts[$0] ?? 0): \($0)" }
		return differences
	}
}
