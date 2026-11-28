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
		// Everything a declaration of a level's list holds but the access of its field, which needs the access proof at
		// signature time, and its places in the tree, spelled apart since they name cases.
		func projected(_ declaration: SeamSignature.Places.Declaration, placesInTree: [String]) -> String {
			let field = declaration.field
			let location = field.declarationLocation.map { "\($0.order) \($0.placement)" } ?? "none"
			let buildable = declaration.buildability.map { ($0.labelsHeldAboveSeam + ["in tree:"] + placesInTree).joined(separator: " ") } ?? "none"
			let rows = [
				"\(field.property.label): \(field.property.typeDescription.asSource) declared by \(field.declaringType.asSource) at \(location)\(field.isReceivedOnlyIfAvailable ? " only if available" : "")",
				"taken by \(field.parameterTakingType?.asSource ?? "none")",
				"deferral \(field.deferral)",
				field.isSeamParameter ? "seam parameter" : "",
				field.isBoundByPublicMockRoot ? "bound by public mock root" : "",
				declaration.isBoundBeforeNextProperty ? "bound before" : "bound later",
				"built after \(declaration.builtAfter?.label ?? "none")",
				"reason \(declaration.reason)",
				declaration.isForwarded ? "forwarded" : "",
				"cycle parameter origin \(declaration.cycleParameterOrigin.map { "\($0)" } ?? "none")",
				"alias \(declaration.alias.map { "\($0.fulfillingProperty.label) seams \($0.isSeams)" } ?? "none")",
				declaration.isBoundFromCallersArgument ? "from caller" : "",
				declaration.isFieldOfSeamParameter ? "field of seam parameter" : "",
				"hiding \(declaration.fillFieldHiding.map { "\($0)" } ?? "none")",
				"buildable \(buildable)",
				declaration.child.map(spelled(childFacts:)) ?? "no child",
			]
			return rows.filter { !$0.isEmpty }.joined(separator: "; ")
		}
		// The labels the seam's caller holds: its parameters but the ones the seam forwards. A child that is no alias is
		// buildable above the seam where its tree receives only those labels or its own.
		let rootForwardedLabels = world.worldBindings(of: Int(world.declaration(of: rootVariant))).filter(\.isForwarded).map { world.propertyTable[Int($0.property)].label }
		let receivedLabels = Set(parameters.map(\.property.label)).subtracting(rootForwardedLabels)
		func labelsHeldAboveSeam(ofBinding property: Property, atVariant variant: VariantID) -> [String]? {
			let targets = world.edges(from: world.declaration(of: variant))
			guard let edge = targets.firstIndex(where: { world.graph.nodes[Int($0)].property == property }) else { return nil }
			let child = targets[edge]
			let node = world.graph.nodes[Int(child)]
			guard node.alias == nil, !node.key.isFill else { return nil }
			let receivedByTree = world.receives.received.columns(inRow: Int(child)).map { world.propertyTable[Int($0)].label }
			guard receivedByTree.allSatisfy({ receivedLabels.contains($0) || $0 == property.label }) else { return nil }
			return receivedLabels.union([property.label]).sorted() + ["in tree:"] + placesInTree(of: SeamPlacesLevelID(variant: variant, edge: Int32(edge - targets.startIndex)))
		}
		// The places the tree a level's next edge builds holds or passes up, in the order a last-in-first-out walk of it
		// reaches them: each hole as its declaring type and label, each passed-up hole as the call's type. The walk follows
		// the calls that build in line, so a call that closes a cycle adds nothing.
		func placesInTree(of start: SeamPlacesLevelID) -> [String] {
			var places = [String]()
			var levelsToVisit = [start]
			var visitedVariants = Set<VariantID>()
			while let visited = levelsToVisit.popLast() {
				let targets = world.edges(from: world.declaration(of: visited.variant))
				let target = targets[targets.startIndex + Int(visited.edge)]
				let node = world.graph.nodes[Int(target)]
				for passUp in world.passUps(of: Int(target)) where passUp.calledCaseIndex >= 0 {
					places.append("passed up by \(world.typeTable[Int(world.builtTypes[Int(target)])].asSource)")
				}
				if node.key.leaf == .hole {
					places.append("\(world.graph.nodes[Int(world.declaration(of: visited.variant))].scope.instantiable.concreteInstantiable.asSource) \(node.property?.label ?? "fill")")
				}
				guard node.key.leaf == .none, buildsInLine(visited) else { continue }
				let callee = world.calls(of: visited.variant)[world.calls(of: visited.variant).startIndex + Int(visited.edge)]
				guard visitedVariants.insert(callee).inserted else { continue }
				for edge in 0..<Int32(world.edges(from: world.declaration(of: callee)).count) {
					levelsToVisit.append(SeamPlacesLevelID(variant: callee, edge: edge))
				}
			}
			return places.uniqued()
		}
		// A child's facts as the stored graph keeps them.
		func spelled(childFacts: SeamSignature.Places.ChildFacts) -> String {
			"child at \(childFacts.position)\(childFacts.isBuilder ? " builder" : "") loop \(childFacts.loop.map(String.init) ?? "none") builds \(childFacts.builtType?.asSource ?? "none")\(childFacts.isPlace ? " place" : "") only if available [\(childFacts.receivesOnlyIfAvailable.map(\.label).joined(separator: " "))] carriers [\(childFacts.carriers.map(\.label).joined(separator: " "))]"
		}
		func childFacts(ofBinding property: Property, atVariant variant: VariantID) -> SeamSignature.Places.ChildFacts? {
			let declaration = world.declaration(of: variant)
			let targets = world.edges(from: declaration)
			let edgeFacts = world.edgeFacts(from: Int(declaration))
			guard let edge = targets.firstIndex(where: { world.graph.nodes[Int($0)].property == property }) else { return nil }
			let child = targets[edge]
			let node = world.graph.nodes[Int(child)]
			let facts = edgeFacts[edgeFacts.startIndex + (edge - targets.startIndex)]
			guard !facts.isFill else { return nil }
			let receivedOnlyIfAvailable = Set(world.receives.onlyIfAvailableUnwrapped.columns(inRow: Int(child)).map { world.propertyTable[Int($0)] })
			let siblings = zip(targets, edgeFacts).compactMap { target, siblingFacts -> (position: Int32, property: Property)? in
				guard !siblingFacts.isFill, let siblingProperty = world.graph.nodes[Int(target)].property, receivedOnlyIfAvailable.contains(siblingProperty.asUnwrappedProperty) else { return nil }
				return (siblingFacts.buildPosition, siblingProperty)
			}
			// The siblings that start as carriers and that the child's tree requires, the first two in build order.
			let required = Set(world.receives.required.columns(inRow: Int(child)).map { world.propertyTable[Int($0)] })
			let carriers = zip(targets, edgeFacts).compactMap { target, siblingFacts -> (position: Int32, property: Property)? in
				guard siblingFacts.isCarrier, let siblingProperty = world.graph.nodes[Int(target)].property, required.contains(siblingProperty) else { return nil }
				return (siblingFacts.buildPosition, siblingProperty)
			}
			return SeamSignature.Places.ChildFacts(
				position: Int(facts.buildPosition),
				isBuilder: ScopeGenerator.isBuilder(property),
				loop: facts.loop < 0 ? nil : Int(facts.loop),
				builtType: node.key.leaf == .none ? world.typeTable[Int(world.builtTypes[Int(child)])] : nil,
				isPlace: node.key.leaf == .hole,
				receivesOnlyIfAvailable: siblings.sorted { $0.position < $1.position }.map(\.property),
				carriers: Array(carriers.sorted { $0.position < $1.position }.prefix(2).map(\.property)),
			)
		}
		// A binding of a level's scope as the place graph's list holds it, before any next property: what the facts give,
		// and the defaults of the rows they do not give yet.
		func draftedDeclaration(of binding: TypeFactsWorldBinding, atVariant variant: VariantID, labelsHeldAboveSeam: [String]?, child: SeamSignature.Places.ChildFacts?) -> SeamSignature.Places.Declaration {
			let property = world.propertyTable[Int(binding.property)]
			let targets = world.edges(from: world.declaration(of: variant))
			let aliasNode = targets.lazy.map { world.graph.nodes[Int($0)] }.first { $0.property == property && $0.alias != nil }
			let declaration = SeamSignature.Places.Declaration(
				field: SeamSignature.Hole.Field(
					property: property,
					access: .internal,
					declaringType: world.typeTable[Int(binding.declaringType)],
					declarationLocation: binding.declarationLocation < 0 ? nil : world.declarationLocations[Int(binding.declarationLocation)],
					isReceivedOnlyIfAvailable: binding.isReceivedOnlyIfAvailable,
					parameterTakingType: binding.parameterTakingType < 0 ? nil : world.typeTable[Int(binding.parameterTakingType)],
					isSeamParameter: binding.isSeamParameter,
				),
				isBoundBeforeNextProperty: child == nil,
				builtAfter: nil,
				reason: .other,
				isForwarded: binding.isForwarded,
				cycleParameterOrigin: nil,
				alias: aliasNode?.aliasFulfillingProperty.map { .init(fulfillingProperty: $0, isSeams: variant == rootVariant) },
				isBoundFromCallersArgument: false,
				isCycleParameter: binding.isCycleParameter,
				isReboundByBuilderFunction: binding.isReboundByBuilderFunction,
				isFieldOfSeamParameter: false,
				fillFieldHiding: nil,
				buildability: labelsHeldAboveSeam.map { .init(labelsHeldAboveSeam: $0, placesInTree: []) },
			)
			return child.map(declaration.asChild) ?? declaration
		}
		func spelledPlaces(inTree cases: [Int]) -> [String] {
			cases.map { index in
				let level = places.levels[places.cases[index].ownerLevel]
				return places.cases[index].passedUp == nil ? "\(level.key.builtType?.asSource ?? "fill") \(level.key.nextProperty?.label ?? "fill")" : "passed up by \(level.key.builtType?.asSource ?? "fill")"
			}.uniqued()
		}
		var factsFieldsByList = [String: Set<[String]>]()
		for level in levels + closingLevels where level.id.variant != rootVariant {
			let declaration = world.declaration(of: level.id.variant)
			let targets = world.edges(from: declaration)
			let next = world.graph.nodes[Int(targets[targets.startIndex + Int(level.id.edge)])]
			let key = "\(builtType(of: level.id.variant)) before \(next.key.isFill ? "fill" : next.property?.label ?? "fill"): \(list(of: level.id.variant))"
			let fields = world.worldBindings(of: Int(declaration)).map { binding in
				let property = world.propertyTable[Int(binding.property)]
				let held = labelsHeldAboveSeam(ofBinding: property, atVariant: level.id.variant)
				let split = held.flatMap { $0.firstIndex(of: "in tree:") }
				return projected(
					draftedDeclaration(of: binding, atVariant: level.id.variant, labelsHeldAboveSeam: split.map { Array(held![..<$0]) }, child: childFacts(ofBinding: property, atVariant: level.id.variant)),
					placesInTree: split.map { Array(held![($0 + 1)...]) } ?? [],
				)
			}
			factsFieldsByList[key, default: []].insert(fields)
		}
		var fieldDifferences = Set<String>()
		var comparedFieldCount = 0
		for level in places.levels where !level.key.isSeamRoot {
			let list = places.declarationLists[level.declarationList]
			let key = "\(level.key.builtType?.asSource ?? "fill") before \(level.key.nextProperty?.label ?? "fill"): \(list.map { spelled(label: $0.field.property.label, isCycleParameter: $0.isCycleParameter, isRebound: $0.isReboundByBuilderFunction, isForwarded: $0.isForwarded) }.joined(separator: ", "))"
			guard let factsFields = factsFieldsByList[key] else { continue }
			let storedFields = list.map { projected($0, placesInTree: $0.buildability.map { spelledPlaces(inTree: $0.placesInTree) } ?? []) }
			comparedFieldCount += storedFields.count
			guard !factsFields.contains(storedFields) else { continue }
			let nearest = factsFields.sorted { $0.lexicographicallyPrecedes($1) }[0]
			for (factsField, storedField) in zip(nearest, storedFields) where factsField != storedField {
				fieldDifferences.insert("fields: \(key): facts \(factsField), stored \(storedField)")
			}
		}
		// How many stored declarations carry each fact the facts do not yet give, so the rows to do go by count.
		let storedDeclarations = places.declarationLists.flatMap(\.self)
		let rowCounts = [
			("alias", storedDeclarations.count { $0.alias != nil }),
			("callersArgument", storedDeclarations.count(where: \.isBoundFromCallersArgument)),
			("fieldOfSeamParameter", storedDeclarations.count(where: \.isFieldOfSeamParameter)),
			("fillFieldHiding", storedDeclarations.count { $0.fillFieldHiding != nil }),
			("buildability", storedDeclarations.count { $0.buildability != nil }),
			("builtAfter", storedDeclarations.count { $0.builtAfter != nil }),
			("cycleParameterOrigin", storedDeclarations.count { $0.cycleParameterOrigin != nil }),
			("child", storedDeclarations.count { $0.child != nil }),
			("childCarriers", storedDeclarations.count { !($0.child?.carriers.isEmpty ?? true) }),
			("childLoop", storedDeclarations.count { $0.child?.loop != nil }),
			("childOnlyIfAvailable", storedDeclarations.count { !($0.child?.receivesOnlyIfAvailable.isEmpty ?? true) }),
			("placesInTree", storedDeclarations.count { !($0.buildability?.placesInTree.isEmpty ?? true) }),
			("boundLater", storedDeclarations.count { !$0.isBoundBeforeNextProperty }),
			("all", storedDeclarations.count),
		]
		// The rows the facts hold no column for yet, left out of the second count: rebindings and cycle parameters.
		func withoutRowsToCome(_ entry: String) -> String {
			let parts = entry.components(separatedBy: ": ")
			let labels = parts[1...].joined(separator: ": ").components(separatedBy: ", ").filter { !$0.hasSuffix(" (cycle)") && !$0.hasSuffix(" (rebound)") }
			return "\(parts[0]): \(labels.joined(separator: ", "))"
		}
		let storedWithoutRowsToCome = Set(fromStored.map(withoutRowsToCome))
		let alikeWithoutRowsToCome = fromFacts.count(where: { storedWithoutRowsToCome.contains(withoutRowsToCome($0)) })
		return ["report: declaration lists: \(fromFacts.count) facts, \(fromStored.count) stored, \(fromFacts.intersection(fromStored).count) alike, \(alikeWithoutRowsToCome) alike but rebindings and cycle parameters", "report: declaration fields: \(comparedFieldCount) compared, \(fieldDifferences.count) differences", "report: stored declaration rows: \(rowCounts.map { "\($0.0) \($0.1)" }.joined(separator: ", "))"] + fieldDifferences.sorted()
			+ fromFacts.subtracting(fromStored).sorted().map { "declarations: only from facts: \($0)" }
			+ fromStored.subtracting(fromFacts).sorted().map { "declarations: only stored: \($0)" }
	}
}
