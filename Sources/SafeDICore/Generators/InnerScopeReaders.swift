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

/// The functions a seam's caller generates to read a value from the scope value an inner seam handed a fill: a place
/// inside the fill is a case of the outer seam's enum (`SeamSignature.ScopeEnum.Case.Kind.fill`) that carries that value,
/// and a fill the caller generates for the place reads a value the inner seam's levels hold through it, as inline the
/// place's tree reads the nearest declaration on the path through the inner seam's tree.
///
/// One reader per enum of the inner seam's that leads to a level that holds the label, a one-level switch: each case
/// returns the nearest value its route holds – the enum it holds, then the inner seam's enum it carries, then its own
/// payload – or `nil` where its route holds none, so the caller passes the value the outer seam's levels, or its own
/// scope, hold instead (`call(of:handing:fallback:)`). A reader is linear in the enums it reads, restates none of the inner
/// seam's paths, and recurses as the enums do.
struct InnerScopeReaders: Sendable {
	/// What a reader reads: the label, from the enum of `enumKey`.
	struct Key: Hashable, Sendable {
		let enumKey: SeamSignature.ScopeEnum.Key
		let label: String
	}

	init(enumsByKey: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum], nameByKey: [Key: String]) {
		self.enumsByKey = enumsByKey
		self.nameByKey = nameByKey
	}

	/// The names of every reader the dispatchers of a call could need, claimed in a fixed order: for each enum an inner
	/// seam's value one of `scopeEnums`' cases carries leads to, each label a level it leads to holds.
	static func claimNames(
		forValuesCarriedBy cases: [SeamSignature.ScopeEnum.Case],
		enumsByKey: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum],
		names: inout GeneratedNameAllocator,
	) -> [Key: String] {
		var nameByKey = [Key: String]()
		var visited = Set<SeamSignature.ScopeEnum.Key>()
		var orderedKeys = [SeamSignature.ScopeEnum.Key]()
		for innerKey in cases.compactMap(SeamSignature.ScopeEnum.carriedInnerKey(of:)) {
			var keysToVisit = [innerKey]
			while let key = keysToVisit.popLast() {
				guard visited.insert(key).inserted, let scopeEnum = enumsByKey[key] else { continue }
				orderedKeys.append(key)
				for enumCase in scopeEnum.cases.reversed() {
					keysToVisit += [SeamSignature.ScopeEnum.carriedInnerKey(of: enumCase), SeamSignature.ScopeEnum.heldKey(of: enumCase)].compactMap(\.self)
				}
			}
		}
		let readers = InnerScopeReaders(enumsByKey: enumsByKey, nameByKey: [:])
		for key in orderedKeys {
			guard let scopeEnum = enumsByKey[key] else { continue }
			for label in readers.labelsHeld(from: key).sorted() {
				nameByKey[Key(enumKey: key, label: label)] = names.claim(ScopeGenerator.functionName(toBuildPropertyNamed: "\(label)_\(DependencyTreeGenerator.seamStem(of: key.seamType))_\(scopeEnum.typeName)".spelledAsIdentifier))
			}
		}
		return nameByKey
	}

	/// The expression a dispatcher passes for `label` from `innerScope`, a value of the enum of `innerKey`, and whether it
	/// reads `fallback`: what the reader finds, or else `fallback` where some route holds none; `nil` where no level the enum
	/// leads to holds the label, so the dispatcher passes `fallback`.
	func call(of label: String, from innerKey: SeamSignature.ScopeEnum.Key, handing innerScope: String, fallback: String) -> (expression: String, readsFallback: Bool)? {
		guard let name = nameByKey[Key(enumKey: innerKey, label: label)], let form = form(of: label, from: innerKey) else { return nil }
		// A reader that finds a value on every route returns its form, and any other its form made optional, which is the
		// parameter's type where it takes no fallback.
		if totalEnums(of: label, from: innerKey).contains(innerKey) || (fallback == "nil" && !form.typeDescription.isOptional) {
			return ("\(name)(\(innerScope))", false)
		} else {
			return ("\(name)(\(innerScope)) ?? \(fallback)", true)
		}
	}

	/// The labels of `fields`, a place's, that a level of an inner seam's enum the place's route carries holds on some route
	/// of that enum and on none of its others, where no level of the place's own seam on the route holds them either: on
	/// such a route inline reads the declaration enclosing the call, so a fill reads it from the caller's scope there.
	func labelsSomeInnerRouteLacks(of place: SeamSignature.Hole) -> Set<String> {
		guard let enumPlace = place.enumPlace, enumPlace.isNestedByType else { return [] }
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

	/// The readers `requested` call, and those they call, declared in the order they are first requested, each `@Sendable`
	/// where `sendableRequests` holds a reader that calls it or it is among them.
	func declarations(of requested: [Key], sendableRequests: Set<Key>, indent: String) -> [String] {
		var ordered = [Key]()
		var seen = Set<Key>()
		var calleesByKey = [Key: [Key]]()
		var keysToVisit = Array(requested.reversed())
		while let key = keysToVisit.popLast() {
			guard seen.insert(key).inserted, nameByKey[key] != nil else { continue }
			ordered.append(key)
			let callees = callees(of: key)
			calleesByKey[key] = callees
			keysToVisit += callees.reversed()
		}
		var sendableKeys = Set<Key>()
		var sendableKeysToVisit = Array(sendableRequests)
		while let key = sendableKeysToVisit.popLast() {
			guard sendableKeys.insert(key).inserted else { continue }
			sendableKeysToVisit += calleesByKey[key, default: []]
		}
		return ordered.compactMap { declaration(of: $0, isSendable: sendableKeys.contains($0), indent: indent) }
	}

	// MARK: Private

	private let enumsByKey: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]
	private let nameByKey: [Key: String]

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

	/// The form a reader of `label` from the enum of `key` returns, made optional where some route holds none: the
	/// optional form where a level holds the label optionally, else the form that sorts first, which per-place validation
	/// leaves alone (`irreconcilableFields`).
	private func form(of label: String, from key: SeamSignature.ScopeEnum.Key) -> Property? {
		let forms = Set(fieldsHeld(from: key).filter { $0.property.label == label }.map(\.property)).sorted()
		return forms.first(where: \.typeDescription.isOptional) ?? forms.first
	}

	/// The readers the reader of `key` calls, in case order: of the enum each case holds, then, unless that one finds a value
	/// on every route, of the inner seam's enum it carries, where each leads to the label.
	private func callees(of key: Key) -> [Key] {
		guard let scopeEnum = enumsByKey[key.enumKey] else { return [] }
		let enumsHoldingOnEveryRoute = totalEnums(of: key.label, from: key.enumKey)
		var callees = [Key]()
		for enumCase in scopeEnum.cases {
			for calleeEnumKey in [SeamSignature.ScopeEnum.heldKey(of: enumCase), SeamSignature.ScopeEnum.carriedInnerKey(of: enumCase)].compactMap(\.self) {
				let callee = Key(enumKey: calleeEnumKey, label: key.label)
				guard nameByKey[callee] != nil, labelsHeld(from: calleeEnumKey).contains(key.label) else { continue }
				callees.append(callee)
				if enumsHoldingOnEveryRoute.contains(calleeEnumKey) {
					break
				}
			}
		}
		return callees
	}

	/// The reader of `key`: a one-level switch over its enum, each case returning the nearest value on its route.
	private func declaration(of key: Key, isSendable: Bool, indent: String) -> String? {
		guard let name = nameByKey[key], let scopeEnum = enumsByKey[key.enumKey], let form = form(of: key.label, from: key.enumKey) else { return nil }
		let label = key.label
		let caseIndent = indent + ScopeGenerator.standardIndent
		// The names the cases bind, apart from one another.
		let valuesName = "values"
		let innerScopeName = "innerScope"
		let scopeName = "scope"
		func reader(of enumKey: SeamSignature.ScopeEnum.Key?) -> String? {
			guard let enumKey else { return nil }
			let calleeKey = Key(enumKey: enumKey, label: label)
			guard labelsHeld(from: enumKey).contains(label) else { return nil }
			return nameByKey[calleeKey]
		}
		var caseLines = [String]()
		let enumsHoldingOnEveryRoute = totalEnums(of: label, from: key.enumKey)
		for enumCase in scopeEnum.cases {
			let ownValue = Self.holds(label, in: enumCase) ? "\(valuesName).\(label.spelledAsMemberReference)" : nil
			let heldKey = SeamSignature.ScopeEnum.heldKey(of: enumCase)
			let carriedKey = SeamSignature.ScopeEnum.carriedInnerKey(of: enumCase)
			// The nearest first, up to the first that finds a value on every route: the enum the case holds, then the inner
			// seam's it carries, then its own payload.
			var chain = [String]()
			var heldReader: String?
			var carriedReader: String?
			var isCovered = false
			if let name = reader(of: heldKey), let heldKey {
				heldReader = name
				chain.append("\(name)(\(scopeName))")
				isCovered = enumsHoldingOnEveryRoute.contains(heldKey)
			}
			if !isCovered, let name = reader(of: carriedKey), let carriedKey {
				carriedReader = name
				chain.append("\(name)(\(innerScopeName))")
				isCovered = enumsHoldingOnEveryRoute.contains(carriedKey)
			}
			if !isCovered, let ownValue {
				chain.append(ownValue)
			}
			let readsOwnValue = !isCovered && ownValue != nil
			// The case's payload, in the order the case declares it, each bound only where read.
			var bindings = [String]()
			switch enumCase.kind {
			case .own:
				// A case per path holds no level nested by type.
				break
			case let .place(sites):
				// A place's own case: its payload struct, then any value an instantiator forwards, which no reader reads.
				if enumCase.values != nil {
					bindings.append(readsOwnValue ? valuesName : "_")
				}
				// Every site of a place builds one property, which the site's path ends with: an instantiator's case carries the
				// value it forwards, in whichever seam's tree the place is, the inner seam's or one it passes the place up from.
				if sites.first?.path.last?.typeDescription.forwardedTypeOfWrapper != nil {
					bindings.append("_")
				}
			case .nested, .inner:
				if enumCase.values != nil {
					bindings.append(readsOwnValue ? valuesName : "_")
				}
				bindings.append(heldReader == nil ? "_" : scopeName)
			case let .fill(_, innerEnumType, _, _):
				if enumCase.values != nil {
					bindings.append(readsOwnValue ? valuesName : "_")
				}
				if innerEnumType != nil {
					bindings.append(carriedReader == nil ? "_" : innerScopeName)
				}
				bindings.append(heldReader == nil ? "_" : scopeName)
			}
			let value = chain.isEmpty ? "nil" : chain.joined(separator: " ?? ")
			// A case none of whose payload is read binds nothing.
			let pattern = bindings.allSatisfy { $0 == "_" } ? ".\(enumCase.name)" : "let .\(enumCase.name)(\(bindings.joined(separator: ", ")))"
			caseLines.append("\(caseIndent)case \(pattern): return \(value)")
		}
		let returnType = enumsHoldingOnEveryRoute.contains(key.enumKey) ? form.typeDescription : .optional(form.typeDescription)
		var lines = ["\(indent)\(isSendable ? "@Sendable " : "")func \(name)(_ \(scopeName): \(scopeEnum.type.asSource)) -> \(returnType.asSource) {", "\(caseIndent)switch \(scopeName) {"]
		lines += caseLines
		lines += ["\(caseIndent)}", "\(indent)}"]
		return lines.joined(separator: "\n")
	}
}
