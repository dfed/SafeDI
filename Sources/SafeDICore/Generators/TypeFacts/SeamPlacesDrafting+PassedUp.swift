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

// The cases a seam's place graph holds for the places its calls pass up, read off its facts world: one per call edge of a
// variant and case of the called signature, a reference to that case, never a copy of its levels.

extension SeamPlacesDrafts {
	/// One case per (call level, family, called case) the seam's drafts pass up, in the order of the levels, each call's
	/// cases in the order of the called signature's holes, a called case once per call. The owner is the level before
	/// the call's edge. The case is built in each family the caller's body is built in, or only in the `@Sendable` one
	/// where the call's edge opens a `@Sendable` function, as a call made there captures the builder; its site opens one
	/// where the call's edge does.
	func passedUpCases() -> [SeamPlacesCaseDraft] {
		var drafts = [SeamPlacesCaseDraft]()
		var firstDraftByCalledCase = [SeamSignature.Places.CalledCase: Int]()
		for level in levels {
			let targets = world.edges(from: world.declaration(of: level.id.variant))
			let call = Int(targets[targets.startIndex + Int(level.id.edge)])
			let opensSendableFunction = level.opens.opensSendableFunction
			let callFamilies = opensSendableFunction ? .sendable : families[Int(level.id.variant)]
			var casesOfCall = Set<Int32>()
			for passUp in world.passUps(of: call) where casesOfCall.insert(passUp.calledCaseIndex).inserted {
				let calledCase = SeamSignature.Places.CalledCase(
					seamType: world.typeTable[Int(world.builtTypes[call])],
					isPublicMock: world.constructions[call] == .publicMockCall,
					caseIndex: Int(passUp.calledCaseIndex),
				)
				for (family, isSendable) in [(SeamPlacesFamilies.plain, false), (.sendable, true)] where callFamilies.contains(family) {
					let first = firstDraftByCalledCase[calledCase]
					if first == nil {
						firstDraftByCalledCase[calledCase] = drafts.count
					}
					drafts.append(SeamPlacesCaseDraft(
						owner: level.id,
						isBuiltInSendableFunction: isSendable,
						siteOpensSendableFunction: opensSendableFunction,
						sites: [],
						passedUp: calledCase,
						firstCasePresentingSamePlaces: first,
						namingRoute: [],
					))
				}
			}
		}
		return drafts
	}
}

extension [SeamPlacesCaseDraft] {
	/// Each passed-up case among `self` that `places`, a seam's stored graph, does not hold, and each it holds that `self`
	/// does not: the called case it refers to and the family it is built in. The first line is a count report.
	func passedUpDifferences(from places: SeamSignature.Places) -> [String] {
		func spelled(_ calledCase: SeamSignature.Places.CalledCase, isBuiltInSendableFunction: Bool, siteOpensSendableFunction: Bool) -> String {
			"\(calledCase.seamType.asSource)\(calledCase.isPublicMock ? " (public mock)" : "") case \(calledCase.caseIndex), \(isBuiltInSendableFunction ? "sendable" : "plain")\(siteOpensSendableFunction ? ", site opening" : "")"
		}
		let fromFacts = Set(compactMap { draft in
			draft.passedUp.map { spelled($0, isBuiltInSendableFunction: draft.isBuiltInSendableFunction, siteOpensSendableFunction: draft.siteOpensSendableFunction) }
		})
		let stored = places.cases.compactMap { placeCase in
			placeCase.passedUp.map { spelled($0, isBuiltInSendableFunction: placeCase.isBuiltInSendableFunction, siteOpensSendableFunction: placeCase.siteOpensSendableFunction) }
		}
		let fromStored = Set(stored)
		// The order: the stored graph adds every own case before the passed-up ones, and these by call, in the order of the
		// called signature's cases.
		let factsOrder = compactMap { draft in
			draft.passedUp.map { spelled($0, isBuiltInSendableFunction: draft.isBuiltInSendableFunction, siteOpensSendableFunction: draft.siteOpensSendableFunction) }
		}
		let firstPassedUp = places.cases.firstIndex { $0.passedUp != nil } ?? places.cases.count
		let ownAfterPassedUp = places.cases[firstPassedUp...].contains { $0.passedUp == nil }
		let order = factsOrder == stored ? "same order" : "order differs: facts \(factsOrder.joined(separator: " / ")); stored \(stored.joined(separator: " / "))"
		return ["report: passed-up: \(count { $0.passedUp != nil }) facts cases over \(fromFacts.count) distinct, \(stored.count) stored over \(fromStored.count)", "report: passed-up order: \(order)\(ownAfterPassedUp ? ", an own case stored after a passed-up one" : "")"]
			+ fromFacts.subtracting(fromStored).sorted().map { "passed-up: only from facts: \($0)" }
			+ fromStored.subtracting(fromFacts).sorted().map { "passed-up: only stored: \($0)" }
	}
}
