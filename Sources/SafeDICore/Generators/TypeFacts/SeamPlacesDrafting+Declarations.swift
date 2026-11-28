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

// The declarations of a seam's place graph, drafted from its facts world: each binding of a level's scope as the graph's
// list holds it, before any next property, and each signature parameter as the root's list holds it.

struct SeamPlacesDeclarationDrafter {
	init(drafts: SeamPlacesDrafts, parameters: [SeamSignature.Parameter], access: SeamPlacesFieldAccess? = nil) {
		self.drafts = drafts
		self.access = access
		let world = drafts.world
		rootVariant = world.rootVariant(0)
		let rootForwardedLabels = world.worldBindings(of: Int(world.declaration(of: rootVariant))).filter(\.isForwarded).map { world.propertyTable[Int($0.property)].label }
		// The labels the seam's caller holds: its parameters but the ones the seam forwards.
		receivedLabels = Set(parameters.map(\.property.label)).subtracting(rootForwardedLabels)
		seam = world.graph.nodes[Int(world.declaration(of: rootVariant))].scope.instantiable
		var seamDependencyByProperty = [Property: Dependency]()
		for dependency in seam.dependencies where seamDependencyByProperty[dependency.property] == nil {
			seamDependencyByProperty[dependency.property] = dependency
		}
		self.seamDependencyByProperty = seamDependencyByProperty
	}

	let drafts: SeamPlacesDrafts
	/// What proves each field's access, where the drafts are assembled into a signature's graph; `nil` for a report, whose
	/// fields keep `internal`.
	let access: SeamPlacesFieldAccess?
	let rootVariant: VariantID
	let receivedLabels: Set<String>
	let seam: Instantiable
	let seamDependencyByProperty: [Property: Dependency]

	var world: TypeFactsGraph {
		drafts.world
	}

	/// What decides, for the child a binding of `variant`'s scope builds, whether a type above the seam can build it: the
	/// labels the seam's caller would hold, sorted, and the places its tree holds or passes up. `nil` for an alias, a fill
	/// and a child whose tree receives a label the caller does not hold other than its own.
	func buildability(ofBinding property: Property, atVariant variant: VariantID) -> SeamPlacesDraftedBuildability? {
		let targets = world.edges(from: world.declaration(of: variant))
		guard let edge = targets.firstIndex(where: { world.graph.nodes[Int($0)].property == property }) else { return nil }
		let child = targets[edge]
		let node = world.graph.nodes[Int(child)]
		guard node.alias == nil, !node.key.isFill else { return nil }
		let receivedByTree = world.receives.received.columns(inRow: Int(child)).map { world.propertyTable[Int($0)].label }
		guard receivedByTree.allSatisfy({ receivedLabels.contains($0) || $0 == property.label }) else { return nil }
		return SeamPlacesDraftedBuildability(
			labelsHeldAboveSeam: receivedLabels.union([property.label]).sorted(),
			placesInTree: placesInTree(of: SeamPlacesLevelID(variant: variant, edge: Int32(edge - targets.startIndex))),
		)
	}

	/// The places the tree a level's next edge builds holds or passes up, each once, in the order a last-in-first-out walk
	/// of it reaches them. The walk follows the calls that build in line, so a call that closes a cycle adds nothing.
	func placesInTree(of start: SeamPlacesLevelID) -> [SeamPlacesPlaceInTree] {
		var places = [SeamPlacesPlaceInTree]()
		var levelsToVisit = [start]
		var visitedVariants = Set<VariantID>()
		while let visited = levelsToVisit.popLast() {
			let targets = world.edges(from: world.declaration(of: visited.variant))
			let target = targets[targets.startIndex + Int(visited.edge)]
			let node = world.graph.nodes[Int(target)]
			for (holeIndex, passUp) in world.passUps(of: Int(target)).enumerated() where passUp.calledCaseIndex >= 0 {
				places.append(.passedUp(call: target, passUpIndex: Int32(holeIndex)))
			}
			if node.key.leaf == .hole {
				places.append(.hole(owner: visited.variant, hole: target))
			}
			guard node.key.leaf == .none, drafts.buildsInLine(visited) else { continue }
			let callee = world.calls(of: visited.variant)[world.calls(of: visited.variant).startIndex + Int(visited.edge)]
			guard visitedVariants.insert(callee).inserted else { continue }
			for edge in 0..<Int32(world.edges(from: world.declaration(of: callee)).count) {
				levelsToVisit.append(SeamPlacesLevelID(variant: callee, edge: edge))
			}
		}
		return places.uniqued()
	}

	/// The facts of the child a binding of `variant`'s scope builds that decide its declaration before each next property
	/// (`Places.Declaration.beforeNextProperty(of:)`). `nil` for a binding that is no child, and a fill.
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

	/// A binding of `variant`'s scope as the place graph's list holds it, before any next property, with the places of its
	/// buildability, which the cases the graph assembles name. The rows the facts do not give yet keep the walk's defaults.
	func declaration(of binding: TypeFactsWorldBinding, atVariant variant: VariantID) -> (declaration: SeamSignature.Places.Declaration, placesInTree: [SeamPlacesPlaceInTree]) {
		let property = world.propertyTable[Int(binding.property)]
		let buildability = buildability(ofBinding: property, atVariant: variant)
		let child = childFacts(ofBinding: property, atVariant: variant)
		let targets = world.edges(from: world.declaration(of: variant))
		let aliasNode = targets.lazy.map { world.graph.nodes[Int($0)] }.first { $0.property == property && $0.alias != nil }
		let declaringType = world.typeTable[Int(binding.declaringType)]
		let fieldAccess = access?.access(of: property, declaredBy: declaringType)
		let declaration = SeamSignature.Places.Declaration(
			field: SeamSignature.Hole.Field(
				property: property,
				access: fieldAccess?.level ?? .internal,
				accessCause: fieldAccess?.cause,
				declaringType: declaringType,
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
			isReboundByBuilderFunction: binding.isReboundByBuilderFunction && variant != rootVariant,
			isFieldOfSeamParameter: false,
			fillFieldHiding: nil,
			buildability: buildability.map { .init(labelsHeldAboveSeam: $0.labelsHeldAboveSeam, placesInTree: []) },
		)
		return (child.map(declaration.asChild) ?? declaration, buildability?.placesInTree ?? [])
	}

	/// A signature parameter as the root's list holds it: bound before any child, declared where its first receiver
	/// declares it.
	func parameterDeclaration(of parameter: SeamSignature.Parameter) -> SeamSignature.Places.Declaration {
		let firstReceiver = parameter.receivers.first
		let declaringType = firstReceiver?.declaringType ?? seam.concreteInstantiable
		let location = firstReceiver?.declarationLocation ?? seamDependencyByProperty[parameter.property]?.declarationLocation ?? seam.declarationLocation
		return SeamSignature.Places.Declaration(
			field: SeamSignature.Hole.Field(
				property: parameter.property,
				access: parameter.tierAccess,
				accessCause: parameter.accessCause,
				declaringType: declaringType,
				declarationLocation: location,
				isReceivedOnlyIfAvailable: parameter.isOnlyIfAvailable,
				deferral: parameter.deferral,
				isSeamParameter: true,
				seamParameterOrigin: .init(of: parameter, of: seam, declaringType: declaringType, declarationLocation: location),
			),
			isBoundBeforeNextProperty: true,
			builtAfter: nil,
			reason: .other,
			isForwarded: false,
			cycleParameterOrigin: nil,
			alias: nil,
			isBoundFromCallersArgument: false,
			isCycleParameter: false,
			isReboundByBuilderFunction: false,
			isFieldOfSeamParameter: false,
			fillFieldHiding: nil,
			buildability: nil,
		)
	}
}

/// What decides whether a type above the seam can build a declaration's tree (`Places.Buildability`), with its places as
/// the facts name them.
struct SeamPlacesDraftedBuildability: Equatable, Sendable {
	let labelsHeldAboveSeam: [String]
	let placesInTree: [SeamPlacesPlaceInTree]
}

/// A place a declaration's tree holds or passes up.
enum SeamPlacesPlaceInTree: Hashable, Sendable {
	/// A hole, by the variant of the scope that declares it and its node.
	case hole(owner: VariantID, hole: DeclarationID)
	/// A hole of a called seam the call passes up, by the call's node and the hole's position among its pass-ups.
	case passedUp(call: DeclarationID, passUpIndex: Int32)
}

/// What proves the access of the fields a seam's graph lists: the type access proof of the seam's module, capped at the
/// access of the seam's generated initializer, as the walk proves it (`SeamBuilderParameters.holes(of:)`).
struct SeamPlacesFieldAccess {
	let proof: TypeAccessProof
	let seam: Instantiable
	let instantiables: [TypeDescription: Instantiable]

	/// The access of the seam's generated initializer, which caps every field's.
	var seamTypeAccess: AccessLevel {
		DependencyTreeGenerator.parameterAccess(seam.effectiveTypeAccess)
	}

	/// The access of a field of `property` that `declaringType` declares, and what proves it.
	func access(of property: Property, declaredBy declaringType: TypeDescription?) -> (level: AccessLevel, cause: TypeAccessProof.Cause?) {
		let declaringModuleName = declaringType.flatMap { instantiables[$0]?.moduleName }
		let access = proof.access(ofParameterTyped: property.typeDescription, mentionedFrom: .declaration(seam), admittedModules: Set([seam.moduleName, declaringModuleName]))
		return (min(access.level, seamTypeAccess), access.cause)
	}
}
