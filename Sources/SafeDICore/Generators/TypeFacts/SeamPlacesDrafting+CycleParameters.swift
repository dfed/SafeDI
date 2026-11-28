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

// The parameters of the functions lazy cycles close on, as a seam's place graph lists them at each level of a function's
// declaration: read from the per-type facts (`TypeFactsGraph.cycleFunctionParameters()`), with the receive of each
// parameter's label a walk of the function's body meets first, as the tree finds it
// (`ScopeGenerator.inOrderTheBodyFirstReceives`).

/// The cycle parameters each variant's function takes, as the declarations its levels list.
struct SeamPlacesCycleParameters {
	init(world: TypeFactsGraph) {
		let solved = world.cycleFunctionParameters()
		/// Whether a call of `declaration` closes a cycle on `other`: one of its cycle identity being built above it.
		func closes(_ declaration: DeclarationID, on other: DeclarationID) -> Bool {
			declaration == other || world.cycle(of: declaration) == world.cycle(of: other)
		}
		func componentMembers(of declaration: DeclarationID, in path: [DeclarationID]) -> [DeclarationID] {
			let group = solved.cycleGroups[Int(declaration)]
			guard group >= 0 else { return [] }
			return path.filter { solved.cycleGroups[Int($0)] == group }
		}
		// A call inside a fill of a declaration being built above the fill hands on the fills it was handed: it enters no
		// body, as the fold finds it.
		func reenters(_ child: DeclarationID, in path: [DeclarationID]) -> Bool {
			guard let position = path.lastIndex(where: { closes(child, on: $0) }) else { return false }
			return world.graph.nodes[Int(child)].key.isFill || path[(position + 1)...].contains { world.graph.nodes[Int($0)].key.isFill }
		}

		// Each parameter's receiver: the type whose own receive of its label the body's walk meets first, depth first in
		// edge order, each declaration once, and where the declaration is received. A call that closes a cycle on a function
		// above this one receives what that function's parameter receives.
		typealias Receiver = (type: TypeDescription, declarationLocation: Dependency.DeclarationLocation?)
		var receiversByPlace = [TypeFactsCycleFunctionParameters.Place: [String: Receiver]]()
		var parametersByPlace = [TypeFactsCycleFunctionParameters.Place: [TypeFactsCycleFunctionParameters.Parameter]]()
		for (place, parameters) in solved.places where !parameters.isEmpty {
			parametersByPlace[place] = parameters
			var unmetLabels = Set(parameters.map(\.property.label))
			var receivers = [String: Receiver]()
			var visited = Set<DeclarationID>()
			var declarationsToVisit = [(declaration: place.declaration, path: place.componentMembersAbove)]
			while !unmetLabels.isEmpty, let (declaration, path) = declarationsToVisit.popLast() {
				guard visited.insert(declaration).inserted else { continue }
				let node = world.graph.nodes[Int(declaration)]
				if node.key.leaf == .none {
					let instantiable = node.scope.instantiable
					for (property, dependency) in ScopeGenerator.receivesFromAbove(ofOwnDependencies: instantiable.dependencies) where unmetLabels.remove(property.label) != nil {
						receivers[property.label] = (instantiable.concreteInstantiable, dependency.declarationLocation)
					}
				}
				let pathBeneath = path + [declaration]
				var children = [(declaration: DeclarationID, path: [DeclarationID])]()
				for child in world.edges(from: declaration) where !reenters(child, in: pathBeneath) {
					if let position = pathBeneath.firstIndex(where: { closes(child, on: $0) }) {
						// This function's own closing calls receive what its body meets elsewhere.
						guard position < place.componentMembersAbove.count else { continue }
						let closedOn = TypeFactsCycleFunctionParameters.Place(declaration: pathBeneath[position], componentMembersAbove: componentMembers(of: pathBeneath[position], in: Array(pathBeneath[..<position])))
						for (label, receiver) in receiversByPlace[closedOn, default: [:]].sorted(by: { $0.key < $1.key }) where unmetLabels.remove(label) != nil {
							receivers[label] = receiver
						}
					} else {
						children.append((child, pathBeneath))
					}
				}
				// The declaration visited next is the last one on the stack, so the first child goes last.
				declarationsToVisit.append(contentsOf: children.reversed())
			}
			receiversByPlace[place] = receivers
		}

		// Each variant's place: its declaration beneath the declarations of its group built above it on the first route
		// that reaches it, as the fold's walk from the root meets each place.
		var parametersByVariant = [VariantID: [(parameter: TypeFactsCycleFunctionParameters.Parameter, receiver: Receiver)]]()
		if !parametersByPlace.isEmpty {
			var visitedVariants = Set<VariantID>()
			var variantsToVisit = [(variant: world.rootVariant(0), path: [DeclarationID]())]
			while let (variant, path) = variantsToVisit.popLast() {
				guard visitedVariants.insert(variant).inserted else { continue }
				let declaration = world.declaration(of: variant)
				let place = TypeFactsCycleFunctionParameters.Place(declaration: declaration, componentMembersAbove: componentMembers(of: declaration, in: path))
				if let parameters = parametersByPlace[place], let receivers = receiversByPlace[place] {
					parametersByVariant[variant] = parameters.compactMap { parameter in
						receivers[parameter.property.label].map { (parameter, $0) }
					}
				}
				let pathBeneath = path + [declaration]
				var callees = [(variant: VariantID, path: [DeclarationID])]()
				for (child, callee) in zip(world.edges(from: declaration), world.calls(of: variant)) where !pathBeneath.contains(where: { closes(child, on: $0) }) {
					callees.append((callee, pathBeneath))
				}
				variantsToVisit.append(contentsOf: callees.reversed())
			}
		}
		self.parametersByVariant = parametersByVariant
	}

	/// The declarations of the cycle parameters `variant`'s function takes, in the order the function takes them, each
	/// declared where the body first receives its label and noting the label's declaration it passes on; empty for a
	/// variant whose function takes none.
	func declarations(atVariant variant: VariantID, drafter: SeamPlacesDeclarationDrafter) -> [SeamSignature.Places.Declaration] {
		guard let parameters = parametersByVariant[variant] else { return [] }
		let world = drafter.world
		let takingType = world.graph.nodes[Int(world.declaration(of: variant))].scope.instantiable.concreteInstantiable
		return parameters.map { parameter, receiver in
			let fieldAccess = drafter.access?.access(of: parameter.property, declaredBy: receiver.type)
			return SeamSignature.Places.Declaration(
				field: SeamSignature.Hole.Field(
					property: parameter.property,
					access: fieldAccess?.level ?? .internal,
					accessCause: fieldAccess?.cause,
					declaringType: receiver.type,
					declarationLocation: receiver.declarationLocation,
					isReceivedOnlyIfAvailable: false,
					parameterTakingType: takingType,
					isSeamParameter: false,
				),
				isBoundBeforeNextProperty: true,
				builtAfter: nil,
				reason: .other,
				isForwarded: false,
				cycleParameterOrigin: SeamSignature.Hole.UncarriedDeclaration.CycleParameterOrigin(
					takingType: takingType,
					property: parameter.redeclaration.property,
					declaringType: parameter.redeclaration.declaringType,
					declarationLocation: parameter.redeclaration.declarationLocation,
					isForwarded: parameter.isForwarded,
				),
				alias: nil,
				isBoundFromCallersArgument: false,
				isCycleParameter: true,
				isReboundByBuilderFunction: false,
				isFieldOfSeamParameter: false,
				fillFieldHiding: nil,
				buildability: nil,
			)
		}
	}

	/// The declarations of the members of loops of builders `variant`'s function makes again at its top, in the order its
	/// body rebinds them (`TypeFactsWorld.madeAgain(from:)`), each declared by the loop's parent where it declares the
	/// member, but for a label the function takes as a parameter or its type forwards, which its body reads instead. Empty
	/// for the seam's root and for a declaration that makes nothing again.
	func reboundDeclarations(atVariant variant: VariantID, drafter: SeamPlacesDeclarationDrafter) -> [SeamSignature.Places.Declaration] {
		let world = drafter.world
		guard variant != drafter.rootVariant, let madeAgain = world.madeAgain else { return [] }
		let declaration = Int(world.declaration(of: variant))
		let node = world.graph.nodes[declaration]
		var parameterLabels = Set(node.scope.instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property.label))
		for (parameter, _) in parametersByVariant[variant] ?? [] {
			parameterLabels.insert(parameter.property.label)
		}
		return zip(madeAgain.targets(of: declaration), madeAgain.parentEdges(of: declaration)).compactMap { target, parentEdge in
			guard let property = world.graph.nodes[Int(target)].property, !parameterLabels.contains(property.label) else { return nil }
			let parent = world.graph.nodes[TypeFactsGraph.source(ofEdge: Int(parentEdge), in: world.graph)].scope.instantiable
			let declaringType = parent.concreteInstantiable
			let fieldAccess = drafter.access?.access(of: property, declaredBy: declaringType)
			return SeamSignature.Places.Declaration(
				field: SeamSignature.Hole.Field(
					property: property,
					access: fieldAccess?.level ?? .internal,
					accessCause: fieldAccess?.cause,
					declaringType: declaringType,
					declarationLocation: parent.dependencies.first { $0.property == property }?.declarationLocation,
					isReceivedOnlyIfAvailable: false,
					parameterTakingType: nil,
					isSeamParameter: false,
				),
				isBoundBeforeNextProperty: true,
				builtAfter: nil,
				reason: .other,
				isForwarded: false,
				cycleParameterOrigin: nil,
				alias: nil,
				isBoundFromCallersArgument: false,
				isCycleParameter: false,
				isReboundByBuilderFunction: true,
				isFieldOfSeamParameter: false,
				fillFieldHiding: nil,
				buildability: nil,
			)
		}
	}

	private let parametersByVariant: [VariantID: [(parameter: TypeFactsCycleFunctionParameters.Parameter, receiver: (type: TypeDescription, declarationLocation: Dependency.DeclarationLocation?))]]
}
