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

// MARK: - Readers of an inner seam's levels

/// What the levels of an inner seam's or public mock's enums hold on its routes, read for a place inside a fill: a place
/// inside the fill is a case of the outer enum (`SeamSignature.ScopeEnum.Case.Kind.fill`) whose route leads through the
/// inner enum's levels, and a fill the caller generates for the place reads a value those levels hold, as inline the
/// place's tree reads the nearest declaration on the path through the inner tree.
struct InnerScopeReaders: Sendable {
	init(enumsByKey: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]) {
		self.enumsByKey = enumsByKey
	}

	/// The labels of `fields`, a place's, that a level of an inner seam's enum the place's route carries holds on some route
	/// of that enum and on none of its others, where no level of the place's own seam on the route holds them either: on
	/// such a route inline reads the declaration enclosing the call, so a fill reads it from the caller's scope there.
	func labelsSomeInnerRouteLacks(of place: SeamSignature.Hole) -> Set<String> {
		guard let enumPlace = place.enumPlace else { return [] }
		var heldByOwnLevels = Set(enumPlace.values.filter { !$0.isDeferredParameter }.map(\.property.label))
		var heldByInnerLevels = Set<String>()
		var heldOnEveryInnerRoute = Set<String>()
		for step in enumPlace.route {
			heldByOwnLevels.formUnion((step.values?.fields ?? []).filter { !$0.isDeferredParameter }.map(\.property.label))
			if let innerKey = step.innerScope?.innerKey {
				heldByInnerLevels.formUnion(labelsHeld(from: innerKey))
				heldOnEveryInnerRoute.formUnion(labelsEveryRouteHolds(from: innerKey))
			}
		}
		let placeLabels = Set(place.fields.filter { !$0.isDeferredParameter }.map(\.property.label))
		return heldByInnerLevels.subtracting(heldOnEveryInnerRoute).subtracting(heldByOwnLevels).intersection(placeLabels)
	}

	/// The labels a reader finds a value of on every route of the enum of `key`.
	func labelsEveryRouteHolds(from key: SeamSignature.ScopeEnum.Key) -> Set<String> {
		labelsHeld(from: key).filter { totalEnums(of: $0, from: key).contains(key) }
	}

	// MARK: Private

	private let enumsByKey: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]

	/// The labels a level the enum of `key` leads to holds, every field but one bound from a deferred parameter, whose memo
	/// inline never reads where the caller's own declaration is in scope.
	private func labelsHeld(from key: SeamSignature.ScopeEnum.Key) -> Set<String> {
		Set(fieldsHeld(from: key).map(\.property.label))
	}

	/// The fields of the levels the enum of `key` leads to, the enums its cases hold or carry included, found with an
	/// explicit stack: the enums can recurse.
	private func fieldsHeld(from key: SeamSignature.ScopeEnum.Key) -> [SeamSignature.Hole.Field] {
		var fields = [SeamSignature.Hole.Field]()
		var visited = Set<SeamSignature.ScopeEnum.Key>()
		var keysToVisit = [key]
		while let visitedKey = keysToVisit.popLast() {
			guard visited.insert(visitedKey).inserted, let scopeEnum = enumsByKey[visitedKey] else { continue }
			for enumCase in scopeEnum.cases {
				fields += (enumCase.values?.fields ?? []).filter { !$0.isDeferredParameter }
				keysToVisit += [SeamSignature.ScopeEnum.carriedInnerKey(of: enumCase), SeamSignature.ScopeEnum.heldKey(of: enumCase)].compactMap(\.self)
			}
		}
		return fields
	}

	/// The enums, among those the enum of `key` leads to, on every route of which a level holds `label`: the greatest set in
	/// which every case of each enum holds the label in its payload or holds or carries an enum of the set, since a value of a
	/// recursive enum ends at a case that holds none.
	private func totalEnums(of label: String, from key: SeamSignature.ScopeEnum.Key) -> Set<SeamSignature.ScopeEnum.Key> {
		var total = Set<SeamSignature.ScopeEnum.Key>()
		var keysToVisit = [key]
		while let visitedKey = keysToVisit.popLast() {
			guard !total.contains(visitedKey), let scopeEnum = enumsByKey[visitedKey] else { continue }
			total.insert(visitedKey)
			for enumCase in scopeEnum.cases {
				keysToVisit += [SeamSignature.ScopeEnum.carriedInnerKey(of: enumCase), SeamSignature.ScopeEnum.heldKey(of: enumCase)].compactMap(\.self)
			}
		}
		var changed = true
		while changed {
			changed = false
			for enumKey in total {
				let coversEveryCase = enumsByKey[enumKey]?.cases.allSatisfy { enumCase in
					Self.holds(label, in: enumCase) || [SeamSignature.ScopeEnum.carriedInnerKey(of: enumCase), SeamSignature.ScopeEnum.heldKey(of: enumCase)].contains { $0.map(total.contains) ?? false }
				} ?? false
				if !coversEveryCase {
					total.remove(enumKey)
					changed = true
				}
			}
		}
		return total
	}

	/// Whether `enumCase`'s own payload holds `label`, in a field not bound from a deferred parameter.
	private static func holds(_ label: String, in enumCase: SeamSignature.ScopeEnum.Case) -> Bool {
		(enumCase.values?.fields ?? []).contains { !$0.isDeferredParameter && $0.property.label == label }
	}
}
