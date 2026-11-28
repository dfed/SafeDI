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

// Where a seam's calls that close cycles re-enter its place graph, read off its facts world: the entry each closing call
// closes on, where a route to it builds that entry in this graph.

extension SeamPlacesDrafts {
	/// Each call that closes a cycle on a build of a route to it (`closesCycle(_:)`), as the level before its edge, with
	/// the entry it closes on: the call's property, built as its type. In facts order: the variants in order, each one's
	/// edges in order.
	func closedOnEntries() -> [(level: SeamPlacesLevelID, entry: SeamSignature.Places.StackEntry)] {
		var entries = [(level: SeamPlacesLevelID, entry: SeamSignature.Places.StackEntry)]()
		for variant in 0..<VariantID(world.variantCount) {
			for (index, target) in world.edges(from: world.declaration(of: variant)).enumerated() {
				let level = SeamPlacesLevelID(variant: variant, edge: Int32(index))
				guard closesCycle(level), let property = world.graph.nodes[Int(target)].property else { continue }
				entries.append((level, SeamSignature.Places.StackEntry(property: property, concreteType: world.typeTable[Int(world.builtTypes[Int(target)])])))
			}
		}
		return entries
	}

	/// How the closing calls of `closedOnEntries()` differ from the levels of `places`, a seam's stored graph, that close
	/// on an entry: each by the type its scope builds, its next property's label and the entry. The first line is a count
	/// report.
	func closedOnDifferences(from places: SeamSignature.Places) -> [String] {
		func spelled(builtType: TypeDescription?, label: String, entry: SeamSignature.Places.StackEntry) -> String {
			"\(builtType?.asSource ?? "fill") before \(label) closes on \(entry.property.label): \(entry.property.typeDescription.asSource) as \(entry.concreteType.asSource)"
		}
		let entries = closedOnEntries()
		let fromFacts = Set(entries.map { level, entry in
			let node = world.graph.nodes[Int(world.declaration(of: level.variant))]
			return spelled(builtType: node.key.isFill ? nil : node.scope.instantiable.concreteInstantiable, label: entry.property.label, entry: entry)
		})
		let stored = places.levels.compactMap { level in
			level.closesOn.map { spelled(builtType: level.key.builtType, label: level.key.nextProperty?.label ?? "fill", entry: $0) }
		}
		let fromStored = Set(stored)
		return ["report: closes on: \(entries.count) facts levels over \(fromFacts.count) distinct, \(stored.count) stored over \(fromStored.count)"]
			+ fromFacts.subtracting(fromStored).sorted().map { "closes on: only from facts: \($0)" }
			+ fromStored.subtracting(fromFacts).sorted().map { "closes on: only stored: \($0)" }
	}
}

extension SeamPlacesDrafts {
	/// How the declarations each drafted level's scope binds differ from those of the stored levels of `places` with the
	/// same type and next property: each as the key, then the labels in binding order, a cycle parameter marked `(cycle)`,
	/// a loop's rebinding `(rebound)` and a forwarded one `(forwarded)`. The facts' list is the scope's bindings
	/// (`TypeFactsGraph.worldBindings(of:)`), after the seam's `parameters` at its root; a passed-up case's owner a level of the
	/// called seam with no next property, and a fill's entry a level `fill before` its hole's property. The first line is a count report.
	/// Test only, until the assembler builds the declaration lists.
	func declarationListDifferences(from places: SeamSignature.Places, parameters: [SeamSignature.Parameter]) -> [String] {
		func spelled(label: String, isCycleParameter: Bool, isRebound: Bool, isForwarded: Bool) -> String {
			label + (isCycleParameter ? " (cycle)" : "") + (isRebound ? " (rebound)" : "") + (isForwarded ? " (forwarded)" : "")
		}
		let rootVariant = world.rootVariant(0)
		func list(of variant: VariantID) -> String {
			let declaration = world.declaration(of: variant)
			// The root's forwarded properties are among its parameters. A loop's rebindings are its members', not those of
			// the scope that declares it (`ScopeGenerator.reboundProperties`), which the facts do not hold yet.
			let bindings = world.worldBindings(of: Int(declaration)).filter { variant != rootVariant || !$0.isForwarded }.map { binding in
				spelled(label: world.labelTexts[Int(binding.label)], isCycleParameter: binding.isCycleParameter, isRebound: false, isForwarded: binding.isForwarded)
			}
			let parameterLabels = variant == rootVariant ? parameters.map { spelled(label: $0.property.label, isCycleParameter: false, isRebound: false, isForwarded: false) } : []
			return (parameterLabels + bindings).joined(separator: ", ")
		}
		func builtType(of variant: VariantID) -> String {
			world.graph.nodes[Int(world.declaration(of: variant))].scope.instantiable.concreteInstantiable.asSource
		}
		var fromFacts = Set<String>()
		for level in levels + closingLevels {
			let declaration = world.declaration(of: level.id.variant)
			let targets = world.edges(from: declaration)
			let next = world.graph.nodes[Int(targets[targets.startIndex + Int(level.id.edge)])]
			fromFacts.insert("\(builtType(of: level.id.variant)) before \(next.key.isFill ? "fill" : next.property?.label ?? "fill"): \(list(of: level.id.variant))")
		}
		// A fill's entry level, beneath the call level whose edge passes it: the declarations on the paths of the places it
		// stands for that their structs do not carry, each label once, then the fields it binds from the struct, which are
		// those no such declaration's label hides, and of a deferred parameter only where the place is passed up
		// (`ScopeGenerator.fillUncarriedDeclarations`, `fillFields`).
		for level in levels + closingLevels {
			guard let fill = level.fill, let calledBuilders = world.graph.nodes[Int(world.declaration(of: level.id.variant))].scope.calledBuilders else { continue }
			let holes = calledBuilders.holes
			guard Int(fill.holeIndex) < holes.count else { continue }
			let hole = holes[Int(fill.holeIndex)]
			var labels = [String]()
			for declaration in hole.uncarriedDeclarations where !labels.contains(declaration.property.label) {
				labels.append(declaration.property.label)
			}
			let fieldLabels = Set(hole.fields.map(\.property.label))
			let uncarriedOnSomeRoute = Set(hole.uncarriedDeclarations.map(\.property.label).filter { !fieldLabels.contains($0) })
			let readsDeferredFieldsFromStruct = hole.innerSeamType != nil && world.constructions[Int(world.declaration(of: level.id.variant))] != .publicMockCall
			for field in hole.fields where (!field.isDeferredParameter || readsDeferredFieldsFromStruct) && !uncarriedOnSomeRoute.contains(field.property.label) {
				labels.append(field.property.label)
			}
			fromFacts.insert("fill before \(hole.property.label): \(labels.joined(separator: ", "))")
		}
		// A passed-up case's owner is a level of the called seam with no next property, which holds no declarations.
		for level in levels {
			let targets = world.edges(from: world.declaration(of: level.id.variant))
			let call = Int(targets[targets.startIndex + Int(level.id.edge)])
			if !world.passUps(of: call).isEmpty {
				fromFacts.insert("\(world.typeTable[Int(world.builtTypes[call])].asSource) before fill: ")
			}
		}
		let fromStored = Set(places.levels.map { level -> String in
			let declarations = places.declarationLists[level.declarationList].map { declaration in
				spelled(label: declaration.field.property.label, isCycleParameter: declaration.isCycleParameter, isRebound: declaration.isReboundByBuilderFunction, isForwarded: declaration.isForwarded)
			}
			return "\(level.key.builtType?.asSource ?? "fill") before \(level.key.nextProperty?.label ?? "fill"): \(declarations.joined(separator: ", "))"
		})
		// Each declaration's field where a level's list is alike, projected to what the facts give it: its property with its
		// type, its declaring type and location, and whether it is received only if available. The root's parameters are
		// the signature's, so its lists are left out.
		func projected(property: Property, declaringType: TypeDescription, location: Dependency.DeclarationLocation?, isReceivedOnlyIfAvailable: Bool) -> String {
			"\(property.label): \(property.typeDescription.asSource) declared by \(declaringType.asSource) at \(location.map { "\($0.order) \($0.placement)" } ?? "none")\(isReceivedOnlyIfAvailable ? " only if available" : "")"
		}
		var factsFieldsByList = [String: Set<[String]>]()
		for level in levels + closingLevels where level.id.variant != rootVariant {
			let declaration = world.declaration(of: level.id.variant)
			let targets = world.edges(from: declaration)
			let next = world.graph.nodes[Int(targets[targets.startIndex + Int(level.id.edge)])]
			let key = "\(builtType(of: level.id.variant)) before \(next.key.isFill ? "fill" : next.property?.label ?? "fill"): \(list(of: level.id.variant))"
			let fields = world.worldBindings(of: Int(declaration)).map { binding in
				projected(property: world.propertyTable[Int(binding.property)], declaringType: world.typeTable[Int(binding.declaringType)], location: binding.declarationLocation < 0 ? nil : world.declarationLocations[Int(binding.declarationLocation)], isReceivedOnlyIfAvailable: binding.isReceivedOnlyIfAvailable)
			}
			factsFieldsByList[key, default: []].insert(fields)
		}
		var fieldDifferences = Set<String>()
		var comparedFieldCount = 0
		for level in places.levels where !level.key.isSeamRoot {
			let list = places.declarationLists[level.declarationList]
			let key = "\(level.key.builtType?.asSource ?? "fill") before \(level.key.nextProperty?.label ?? "fill"): \(list.map { spelled(label: $0.field.property.label, isCycleParameter: $0.isCycleParameter, isRebound: $0.isReboundByBuilderFunction, isForwarded: $0.isForwarded) }.joined(separator: ", "))"
			guard let factsFields = factsFieldsByList[key] else { continue }
			let storedFields = list.map { projected(property: $0.field.property, declaringType: $0.field.declaringType, location: $0.field.declarationLocation, isReceivedOnlyIfAvailable: $0.field.isReceivedOnlyIfAvailable) }
			comparedFieldCount += storedFields.count
			guard !factsFields.contains(storedFields) else { continue }
			let nearest = factsFields.sorted { $0.lexicographicallyPrecedes($1) }[0]
			for (factsField, storedField) in zip(nearest, storedFields) where factsField != storedField {
				fieldDifferences.insert("fields: \(key): facts \(factsField), stored \(storedField)")
			}
		}
		// The rows the facts hold no column for yet, left out of the second count: rebindings and cycle parameters.
		func withoutRowsToCome(_ entry: String) -> String {
			let parts = entry.components(separatedBy: ": ")
			let labels = parts[1...].joined(separator: ": ").components(separatedBy: ", ").filter { !$0.hasSuffix(" (cycle)") && !$0.hasSuffix(" (rebound)") }
			return "\(parts[0]): \(labels.joined(separator: ", "))"
		}
		let storedWithoutRowsToCome = Set(fromStored.map(withoutRowsToCome))
		let alikeWithoutRowsToCome = fromFacts.count(where: { storedWithoutRowsToCome.contains(withoutRowsToCome($0)) })
		return ["report: declaration lists: \(fromFacts.count) facts, \(fromStored.count) stored, \(fromFacts.intersection(fromStored).count) alike, \(alikeWithoutRowsToCome) alike but rebindings and cycle parameters", "report: declaration fields: \(comparedFieldCount) compared, \(fieldDifferences.count) differences"] + fieldDifferences.sorted()
			+ fromFacts.subtracting(fromStored).sorted().map { "declarations: only from facts: \($0)" }
			+ fromStored.subtracting(fromFacts).sorted().map { "declarations: only stored: \($0)" }
	}
}
