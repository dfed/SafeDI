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

extension NodeRecords {
	/// The claim of `declaration` where it is a node whose type receives a property only if available or declares a rename:
	/// of kind `receivesOnlyIfAvailable`, discharging `onlyIfAvailable` and `renameOrHole` (a hole its scope declares is a
	/// node of its own, `seamHoleClaim(of:in:)`), and the refusal of the wrapper it is built in, which its record reads of
	/// the node (`wrapperRefusalsDischarged(of:in:)`); `nil` for any other node.
	static func receivesOnlyIfAvailableClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard world.kind(of: declaration) != .alias, world.kind(of: declaration) != .hole else { return nil }
		let scope = world.scope(of: declaration)
		let declaresRename = scope.propertiesToGenerate.contains {
			if case .aliased = $0 {
				true
			} else {
				false
			}
		}
		guard declaresRename || scope.instantiable.dependencies.contains(where: { $0.source == .received(onlyIfAvailable: true) }) else { return nil }
		return NodeRecordClaim(kind: .receivesOnlyIfAvailable, discharges: wrapperRefusalsDischarged(of: declaration, in: world).union([.onlyIfAvailable, .renameOrHole]), refusals: [])
	}

	/// The record of `declaration`'s place in `variant`, a node of kind `receivesOnlyIfAvailable`: a `builtByInitializer`
	/// record whose construction is passed `nil` for each receive only if available `answers` finds unavailable there, and
	/// the instance of each of `lazilyInstantiatedInstanceProperties`, those the variant's key says a lazy wrapper answers
	/// (`lazilyInstantiatedInstanceProperties(of:variant:in:)`).
	static func receivesOnlyIfAvailableRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordVariantFacts,
		answers: OnlyIfAvailableAnswers,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
	) throws -> BuiltPlaceRecord {
		try builtByInitializerRecord(
			of: declaration,
			variant: variant,
			in: world,
			unavailableProperties: answers.unavailableProperties(of: variant),
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			typesDeclaredEscaping: typesDeclaredEscaping,
			children: children,
		)
	}
}

/// Which receives only if available each variant of a world is passed `nil` for: those whose label's nearest declaration
/// on the variant's path provides no form the receive reads, is still being built there, or is built after the branch
/// that leads to the variant (`TypeFactsEdge.buildPosition`), as `NearestDeclarations.resolvingBinding(of:)` and the
/// `propertiesGeneratedLater` a scope's children are generated with find them for today's tree.
///
/// Rule 1 of the per-type facts keys a read only if available alike whether it is `nil` or a value, so one variant can be
/// called where the read is `nil` and where it is a value. Off every cycle, such a variant reads the value: its function
/// takes the label as one optional parameter, and the call that finds no declaration passes `nil`
/// (`context(merging:with:)`). A world in which two calls of one variant see different declarations of one label, or in
/// which a member of a cycle is called both ways, is refused (`onlyIfAvailableAnsweredApart`). Only the labels some receive
/// only if available reads are followed, so a world without one costs nothing.
///
/// Holds, per variant, the set of the properties it is passed `nil` for, for as long as the world's records are made.
///
/// A bridge: a private copy of the facts' rule of which declaration answers a read (the nearest above, bound before the
/// edge), which the facts already apply but do not hand on for a read only if available, whose answer rule 1 keys alike
/// whether it is `nil` or a value. It goes in the change that has the facts hand each call whether a read only if
/// available finds a value there, beside the call's sources (`TypeFactsWorld.sources(ofCall:of:)`), which records then
/// read instead.
struct OnlyIfAvailableAnswers: Sendable {
	/// - Parameters:
	///   - world: A world each of whose nodes is of a kind `NodeRecords` makes, off every cycle.
	///   - rootParameters: A seam's parameters, which its root is handed as the nearest declarations of their labels
	///     (`DependencyTreeGenerator.seamRootDeclarations(of:seamRoot:)`), or what a mock root's body is declared inside,
	///     the parameters of `mock()` and the overrides it binds before its nodes; empty for any other root.
	init(world: some NodeRecordSources, rootParameters: [Property] = []) throws(NodeRecordRefusal) {
		var labels = Set<String>()
		// The labels a rename only if available is fulfilled by.
		var renamedLabels = Set<String>()
		for declaration in 0..<Int32(world.declarationCount) where world.kind(of: declaration) != .alias && world.kind(of: declaration) != .hole {
			for dependency in world.scope(of: declaration).instantiable.dependencies {
				switch dependency.source {
				case .received(onlyIfAvailable: true):
					labels.insert(dependency.property.label)
				case let .aliased(fulfillingProperty, _, onlyIfAvailable: true):
					labels.insert(fulfillingProperty.label)
					renamedLabels.insert(fulfillingProperty.label)
				case .instantiated, .forwarded, .received(onlyIfAvailable: false), .aliased(_, _, onlyIfAvailable: false):
					break
				}
			}
		}
		var unavailablePropertiesByVariant = [Set<Property>](repeating: [], count: world.variantCount)
		var renameBindingByVariant = [RenameBinding?](repeating: nil, count: world.variantCount)
		guard !labels.isEmpty else {
			self.unavailablePropertiesByVariant = unavailablePropertiesByVariant
			self.renameBindingByVariant = renameBindingByVariant
			return
		}
		// What each variant's construction sees of each followed label: what the call that reaches it sees, with the
		// declarations of the node that calls it, in the order that node builds its children.
		var contextByVariant = [[String: [Binding]]?](repeating: nil, count: world.variantCount)
		// A seam's parameters, and what a mock root binds before its nodes, are available throughout the tree, each the
		// nearest declaration of its label.
		var rootContext = [String: [Binding]]()
		for parameter in rootParameters where labels.contains(parameter.label) {
			rootContext[parameter.label, default: []].append(Binding(property: parameter, state: .available))
		}
		contextByVariant[0] = rootContext
		var variantsToVisit: [VariantID] = [0]
		while let variant = variantsToVisit.popLast() {
			let declaration = world.declaration(of: variant)
			// A rename or a hole is a leaf of the scope that declares it, which reads for it (below).
			guard let callContext = contextByVariant[Int(variant)], world.kind(of: declaration) != .alias, world.kind(of: declaration) != .hole else { continue }
			let scope = world.scope(of: declaration)
			// A member of a loop of builders begins its builder function by binding each member it makes again
			// (`NodeRecords.loopRebindings(of:in:mockLoopLevels:)`), so its construction and everything inside it read those bindings.
			var context = callContext
			for member in world.madeAgain(from: declaration) {
				if let property = world.property(of: member), labels.contains(property.label) {
					context[property.label] = [Binding(property: property, state: .available)]
				}
			}
			// Inside the node's builder function, its forwarded properties are the nearest declarations of their labels.
			var contextInside = context
			for dependency in scope.instantiable.dependencies where dependency.source == .forwarded && labels.contains(dependency.property.label) {
				contextInside[dependency.property.label] = [Binding(property: dependency.property, state: .available)]
			}
			// So is each dependency its type instantiates that its scope does not build, which a mock is passed as a parameter
			// of `mock()` before any node is built (`Scope.propertiesToDeclare`); a production root's world holds none.
			for dependency in scope.instantiatedDependenciesNotGenerated where labels.contains(dependency.property.label) {
				contextInside[dependency.property.label] = [Binding(property: dependency.property, state: .available)]
			}
			// A variant is read again where a later call answers a label its first call did not.
			unavailablePropertiesByVariant[Int(variant)] = []
			let calls = world.calls(of: variant)
			let edges = world.edges(from: declaration)
			let positionByEdgeIndex = world.edgeFacts(from: declaration).map(\.buildPosition)
			for (edgeIndex, callee) in calls.enumerated() {
				var calleeContext = contextInside
				// The node's children are the nearest declarations of their labels, each built before, during or after the
				// call's branch.
				var childBindingsByLabel = [String: [Binding]]()
				for (siblingEdgeIndex, sibling) in edges.enumerated() {
					guard let property = world.property(of: sibling), labels.contains(property.label) else { continue }
					let state: Binding.State = if siblingEdgeIndex == edgeIndex {
						.beingBuilt
					} else if positionByEdgeIndex[siblingEdgeIndex] < positionByEdgeIndex[edgeIndex] {
						.available
					} else {
						.builtLater
					}
					childBindingsByLabel[property.label, default: []].append(Binding(property: property, state: state))
				}
				for (label, bindings) in childBindingsByLabel {
					calleeContext[label] = Self.nearestBindings(bindings, shadowing: contextInside[label])
				}
				// A fill's body is a function of its own, which declares what the fill binds, takes and captures around it
				// (`FilledCallRecords.Fill.outerDeclarations`).
				if NodeRecordsObservation.recordsFilledCalls, world.construction(of: world.declaration(of: callee)) == .fill, case let .success(records) = world.filledCallRecords(of: declaration),
				   let fill = records.fills.first(where: { $0.facts.declaration == world.declaration(of: callee) })
				{
					for property in fill.outerDeclarations where labels.contains(property.label) {
						calleeContext[property.label] = [Binding(property: property, state: .available)]
					}
				}
				if let existingContext = contextByVariant[Int(callee)] {
					let labelsOneCallAnswers = Set(existingContext.keys).symmetricDifference(calleeContext.keys)
					// A member of a cycle takes what its calls answer as its cycle parameters, whose rows are made per call. A
					// rename only if available is bound where its scope is built, to the declaration or to `nil`, by one
					// statement for every call, so a label one fulfills is not taken as a parameter.
					guard labelsOneCallAnswers.isEmpty || (!world.isOnCycle(world.declaration(of: callee)) && renamedLabels.isDisjoint(with: labelsOneCallAnswers)) else {
						throw .onlyIfAvailableAnsweredApart
					}
					let mergedContext = try Self.context(merging: existingContext, with: calleeContext)
					// A call that answers a label another call does not: the variant, and everything it calls, is read again.
					guard mergedContext != existingContext else { continue }
					contextByVariant[Int(callee)] = mergedContext
					variantsToVisit.append(callee)
				} else {
					contextByVariant[Int(callee)] = calleeContext
					variantsToVisit.append(callee)
				}
			}
			for dependency in scope.instantiable.dependencies where dependency.source == .received(onlyIfAvailable: true) {
				if try Self.binding(reading: dependency.property, in: context) == nil {
					unavailablePropertiesByVariant[Int(variant)].insert(dependency.property)
				}
			}
			// A rename only if available is bound from a property its scope creates, whatever order it is built in, else from
			// a child its node builds that its scope does not create, a dependency a mock root promotes, where that child is
			// built before the rename, else from the nearest declaration above the scope, or to `nil` (`Scope`'s
			// `aliasBindings`).
			for (edgeIndex, (callee, renameDeclaration)) in zip(calls, edges).enumerated() where world.kind(of: renameDeclaration) == .alias {
				for dependency in scope.instantiable.dependencies where dependency.property == world.property(of: renameDeclaration) {
					guard case let .aliased(fulfillingProperty, _, onlyIfAvailable: true) = dependency.source else { continue }
					let binding: Property?
					if let createdBinding = scope.createdBinding(of: fulfillingProperty) {
						binding = createdBinding
					} else {
						// A rename that keeps its label is no declaration of it where its own value is read.
						let childBindings = edges.indices.compactMap { siblingEdgeIndex -> Binding? in
							guard world.kind(of: edges[siblingEdgeIndex]) != .alias, let property = world.property(of: edges[siblingEdgeIndex]), property.label == fulfillingProperty.label else { return nil }
							return Binding(property: property, state: positionByEdgeIndex[siblingEdgeIndex] < positionByEdgeIndex[edgeIndex] ? .available : .builtLater)
						}
						var renameContext = context
						if !childBindings.isEmpty {
							renameContext[fulfillingProperty.label] = childBindings
						}
						binding = try Self.binding(reading: fulfillingProperty, in: renameContext)
					}
					if let binding {
						renameBindingByVariant[Int(callee)] = .bound(fulfillingBindingIsOptional: binding.typeDescription.isOptional)
					} else {
						renameBindingByVariant[Int(callee)] = .boundToNil
						unavailablePropertiesByVariant[Int(variant)].insert(fulfillingProperty)
					}
				}
			}
		}
		self.unavailablePropertiesByVariant = unavailablePropertiesByVariant
		self.renameBindingByVariant = renameBindingByVariant
	}

	/// How a rename only if available is bound where its scope is built.
	enum RenameBinding: Equatable {
		/// To `nil`: no declaration it reads is available.
		case boundToNil
		/// From the declaration it reads, which may be optional.
		case bound(fulfillingBindingIsOptional: Bool)
	}

	/// How `variant`, a rename, is bound: `nil` for a required rename, bound from its fulfilling property.
	func renameBinding(of variant: VariantID) -> RenameBinding? {
		renameBindingByVariant[Int(variant)]
	}

	/// What a call sees of a label its caller's children declare as `bindings`, which are nearer than `shadowed`, what the
	/// caller sees of the label: the children built before the call, and each `Instantiator` not built yet, which a loop
	/// of builders may give the read (`binding(reading:in:)`). A child not built yet gives a read nothing, so it is left
	/// out, and a call that sees only such children sees no declaration (`nil`), as a call does whose caller declares none;
	/// where a declaration above is available, though, the children hide it, which the mark `hiddenAvailable` keeps.
	private static func nearestBindings(_ bindings: [Binding], shadowing shadowed: [Binding]?) -> [Binding]? {
		var nearest = bindings.filter { $0.state == .available || $0.property.propertyType.isInstantiator }
		if !nearest.contains(where: { $0.state == .available }), let hidden = shadowed?.first(where: { $0.state == .available || $0.state == .hiddenAvailable }) {
			nearest.append(Binding(property: hidden.property, state: .hiddenAvailable))
		}
		return nearest.isEmpty ? nil : nearest
	}

	/// What a variant sees of each followed label, where one call of it sees `existing` and another `other`. A label one
	/// call sees no declaration of takes what the other call sees: the variant's function takes the label as one optional
	/// parameter, which the call that sees nothing passes `nil` (the engine's `TypeKeyBody.spelledArgument`), so one
	/// variant serves a call that answers a read only if available and a call that does not. Each merge only adds a
	/// label, so the result does not depend on the order the calls are met in.
	/// - Throws: `onlyIfAvailableAnsweredApart` where the two calls see different declarations of one label.
	private static func context(merging existing: [String: [Binding]], with other: [String: [Binding]]) throws(NodeRecordRefusal) -> [String: [Binding]] {
		var merged = existing
		for (label, bindings) in other {
			if let existingBindings = existing[label] {
				guard existingBindings == bindings else { throw .onlyIfAvailableAnsweredApart }
			} else {
				merged[label] = bindings
			}
		}
		return merged
	}

	/// The declaration in `context` a read only if available of `property` is passed, or `nil` where none is available.
	private static func binding(reading property: Property, in context: [String: [Binding]]) throws(NodeRecordRefusal) -> Property? {
		let providingBindings = (context[property.label] ?? []).filter { binding in
			binding.state != .hiddenAvailable && ScopeGenerator.provides(binding.property, aFormReadBy: property)
		}
		if let available = providingBindings.first(where: { $0.state == .available }) {
			return available.property
		}
		// An `Instantiator` still being built, or built after the branch, is given to the read where its loop of builders
		// holds only builders (`ReceivedBuilderLoops`), which rebinds it: a loop of builders, refused.
		guard !providingBindings.contains(where: \.property.propertyType.isInstantiator) else { throw .builderLoop }
		return nil
	}

	/// The properties `variant`'s construction is passed `nil` for.
	func unavailableProperties(of variant: VariantID) -> Set<Property> {
		unavailablePropertiesByVariant[Int(variant)]
	}

	/// A declaration of a followed label that a call sees, and whether it is built where the call reads it.
	private struct Binding: Hashable {
		enum State: Hashable {
			/// Built before the call's branch, or forwarded.
			case available
			/// The property the call's branch builds, or a property of a scope it is built inside.
			case beingBuilt
			/// Built after the call's branch.
			case builtLater
			/// Available above the node whose children hide it: no read is given it, and the engine's look-up would find it.
			case hiddenAvailable
		}

		let property: Property
		let state: State
	}

	/// By variant.
	private let unavailablePropertiesByVariant: [Set<Property>]
	/// By variant: set for a rename only if available.
	private let renameBindingByVariant: [RenameBinding?]
}
