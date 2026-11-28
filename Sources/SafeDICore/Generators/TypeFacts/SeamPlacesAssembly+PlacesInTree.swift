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

// The places in each child's tree (`Places.Buildability.placesInTree`) as the assembled graph's case indices, folded once
// per variant and family from the cases beneath each edge: never a walk per declaration. Test only, until the assembled
// graph replaces the walk's under a test switch.

extension SeamPlacesCaseAssembly {
	/// The cases of the places in the tree of each edge's child, by the edge's level and the family its variant's body is
	/// built in there: the edge's own hole, the places its call passes up, and the cases beneath a child it builds in line,
	/// each case once. A passed-up place is listed under the first case presenting it. The variants a loop of in-line calls
	/// joins (where one variant's call builds in line on some routes and closes a cycle on others) reach the same places,
	/// so each strongly connected set of them is folded once, after the sets it reaches.
	struct PlacesInTreeFold {
		init(drafts: SeamPlacesDrafts, cases: SeamPlacesCaseAssembly) {
			self.drafts = drafts
			self.cases = cases
		}

		let drafts: SeamPlacesDrafts
		let cases: SeamPlacesCaseAssembly
		private var casesByVariant = [VariantKey: [Int]]()
		private var discoveryIndex = [VariantKey: Int]()
		private var lowLink = [VariantKey: Int]()
		private var stack = [VariantKey]()
		private var onStack = Set<VariantKey>()

		private struct VariantKey: Hashable {
			let variant: VariantID
			let isSendable: Bool
		}

		/// The cases beneath the edge of `level`, in a body built in the `@Sendable` family where `isSendable`.
		mutating func cases(beneath level: SeamPlacesLevelID, isSendable: Bool) -> [Int] {
			let (local, successor) = edge(level, isSendable: isSendable)
			guard let successor else { return local }
			return (local + cases(in: successor)).uniqued()
		}

		/// The cases of the edge of `level` itself, its hole and the places its call passes up, and the body it builds in
		/// line, if any.
		private func edge(_ level: SeamPlacesLevelID, isSendable: Bool) -> (cases: [Int], successor: VariantKey?) {
			let world = drafts.world
			let declaration = world.declaration(of: level.variant)
			let targets = world.edges(from: declaration)
			let target = targets[targets.startIndex + Int(level.edge)]
			let edgeFacts = world.edgeFacts(from: declaration)
			let childIsSendable = isSendable || edgeFacts[edgeFacts.startIndex + Int(level.edge)].opens.opensSendableFunction
			let node = world.graph.nodes[Int(target)]
			var found = [Int]()
			if node.scope.calledBuilders != nil {
				for passUp in world.passUps(of: Int(target)) where passUp.calledCaseIndex >= 0 {
					let calledCase = SeamSignature.Places.CalledCase(
						seamType: world.typeTable[Int(world.builtTypes[Int(target)])],
						isPublicMock: world.constructions[Int(target)] == .publicMockCall,
						caseIndex: Int(passUp.calledCaseIndex),
					)
					if let index = cases.passedUpCaseByKey[PassedUpKey(owner: level, isSendable: childIsSendable, calledCase: calledCase)] {
						found.append(cases.cases[index].firstCasePresentingSamePlaces ?? index)
					}
				}
			}
			switch node.key.leaf {
			case .hole:
				let isSendableHole = node.property?.propertyType.isSendable ?? false
				if let index = cases.ownCaseByKey[OwnKey(declaration: declaration, edge: level.edge, isSendable: isSendable || isSendableHole)] {
					found.append(index)
				}
				return (found, nil)
			case .alias:
				return (found, nil)
			case .none:
				guard drafts.buildsInLine(level) else { return (found, nil) }
				let callees = world.calls(of: level.variant)
				return (found, VariantKey(variant: callees[callees.startIndex + Int(level.edge)], isSendable: childIsSendable))
			}
		}

		/// The levels of every edge of `key`'s variant's body.
		private func levels(of key: VariantKey) -> [SeamPlacesLevelID] {
			(0..<Int32(drafts.world.edges(from: drafts.world.declaration(of: key.variant)).count)).map { SeamPlacesLevelID(variant: key.variant, edge: $0) }
		}

		/// The cases beneath every edge of a variant's body, folded once per strongly connected set of variants and family.
		private mutating func cases(in key: VariantKey) -> [Int] {
			if let known = casesByVariant[key] {
				return known
			}
			connect(key)
			return casesByVariant[key] ?? []
		}

		/// Tarjan's step from `key`: numbers it, follows its in-line calls, and folds the set it closes, if any.
		private mutating func connect(_ key: VariantKey) {
			discoveryIndex[key] = discoveryIndex.count
			lowLink[key] = discoveryIndex[key]
			stack.append(key)
			onStack.insert(key)
			for level in levels(of: key) {
				guard let successor = edge(level, isSendable: key.isSendable).successor else { continue }
				if let successorIndex = discoveryIndex[successor] {
					if onStack.contains(successor) {
						lowLink[key] = min(lowLink[key] ?? successorIndex, successorIndex)
					}
				} else {
					connect(successor)
					lowLink[key] = min(lowLink[key] ?? 0, lowLink[successor] ?? 0)
				}
			}
			guard lowLink[key] == discoveryIndex[key], let start = stack.lastIndex(of: key) else { return }
			let members = Array(stack[start...])
			stack.removeSubrange(start...)
			onStack.subtract(members)
			let memberSet = Set(members)
			var found = [Int]()
			for member in members {
				for level in levels(of: member) {
					let (local, successor) = edge(level, isSendable: member.isSendable)
					found += local
					if let successor, !memberSet.contains(successor) {
						found += casesByVariant[successor] ?? []
					}
				}
			}
			let unique = found.uniqued()
			for member in members {
				casesByVariant[member] = unique
			}
		}
	}
}

extension SeamPlacesLevelAssembly {
	/// How the places in each child's tree, as assembled case indices, differ from the stored graph's: per level key and
	/// child label, the union over the levels of that key of the cases' spellings. The first line is a count report.
	/// Test only.
	func placesInTreeDifferences(of drafts: SeamPlacesDrafts, from places: SeamSignature.Places) -> [String] {
		let caseAssembly = cases(of: drafts)
		var fold = SeamPlacesCaseAssembly.PlacesInTreeFold(drafts: drafts, cases: caseAssembly)
		let world = drafts.world
		func spelledKey(_ key: SeamSignature.Places.LevelKey) -> String {
			"\(key.builtType?.asSource ?? "fill") before \(key.nextProperty?.label ?? "none")"
		}
		func spelledCase(_ index: Int, in cases: [SeamSignature.Places.Case], levels: [SeamSignature.Places.Level]) -> String {
			guard cases.indices.contains(index) else { return "out of range" }
			let placeCase = cases[index]
			let kind = placeCase.passedUp.map { "passed up \($0.seamType.asSource) case \($0.caseIndex)" } ?? "own"
			let owner = levels.indices.contains(placeCase.ownerLevel) ? spelledKey(levels[placeCase.ownerLevel].key) : "out of range"
			return "\(kind) \(placeCase.isBuiltInSendableFunction ? "sendable" : "plain") at \(owner)"
		}
		var stored = [String: Set<String>]()
		for level in places.levels {
			for declaration in places.declarationLists[level.declarationList] {
				guard let buildability = declaration.buildability else { continue }
				stored["\(spelledKey(level.key)) | \(declaration.field.property.label)", default: []].formUnion(buildability.placesInTree.map { spelledCase($0, in: places.cases, levels: places.levels) })
			}
		}
		var assembled = [String: Set<String>]()
		for (level, draft) in zip(levels, draftedLevels) where level.key.builtType != nil {
			let declaration = world.declaration(of: draft.variant)
			let targets = world.edges(from: declaration)
			let families = drafts.families[Int(draft.variant)]
			let familyFlags = [(SeamPlacesFamilies.plain, false), (.sendable, true)].filter { families.contains($0.0) }.map(\.1)
			for listed in declarationLists[level.declarationList] where listed.buildability != nil {
				guard let edge = targets.firstIndex(where: { !world.graph.nodes[Int($0)].key.isFill && world.graph.nodes[Int($0)].property == listed.field.property }) else { continue }
				let edgeLevel = SeamPlacesLevelID(variant: draft.variant, edge: Int32(edge - targets.startIndex))
				let found = (familyFlags.isEmpty ? [false] : familyFlags).flatMap { fold.cases(beneath: edgeLevel, isSendable: $0) }
				assembled["\(spelledKey(level.key)) | \(listed.field.property.label)", default: []].formUnion(found.map { spelledCase($0, in: caseAssembly.cases, levels: levels) })
			}
		}
		var alike = 0
		var differences = [String]()
		for (key, storedCases) in stored.sorted(by: { $0.key < $1.key }) {
			guard let assembledCases = assembled[key] else {
				differences.append("places in tree: \(key): stored \(storedCases.sorted().joined(separator: "; ")), none assembled")
				continue
			}
			guard storedCases != assembledCases else {
				alike += 1
				continue
			}
			differences.append("places in tree: \(key): only stored \(storedCases.subtracting(assembledCases).sorted().joined(separator: "; ")); only assembled \(assembledCases.subtracting(storedCases).sorted().joined(separator: "; "))")
		}
		return ["report: places in tree: \(stored.count) stored children, \(alike) alike, \(stored.values.count { !$0.isEmpty }) stored with places"] + differences
	}
}
