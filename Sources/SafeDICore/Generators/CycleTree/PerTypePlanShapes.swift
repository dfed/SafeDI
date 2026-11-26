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

extension DependencyTreeGenerator {
	/// What `shapeOutsidePerTypePlan(inTreeOf:)` finds in the tree of a root that reaches a cycle.
	struct ShapeOutsidePerTypePlan {
		/// The first shape found that keeps the root on today's tree, or `nil` where the root's code is laid out from its
		/// per-type plan.
		let reason: RootTreeChoiceObservation.PerPathReason?
		/// How many scopes the root's tree reaches, the root among them, each counted once however many places build it.
		let scopeCount: Int
	}

	/// Whether the tree of `root`, which reaches a cycle, holds a shape the per-type plan does not lay out yet, decided
	/// from the declarations alone, before any plan or tree is built; `nil` where `root` reaches no cycle.
	///
	/// The plan lays out a root only if its whole tree holds none of the shapes this names: what remains is types that
	/// instantiate one another, by value or through instantiators, with forwarded values and required receives of values
	/// their own cycle declares. Every
	/// other root is built per path, as today, so its code and its errors are today's. The first shape found names the
	/// reason, in the order the walk reaches the types (each type's dependencies in declaration order), which no test or
	/// output but a test's count reads.
	static func shapeOutsidePerTypePlan(inTreeOf root: Scope, cache: inout ReceivedPropertiesCache) -> ShapeOutsidePerTypePlan? {
		var scopeByIdentifier = [ObjectIdentifier(root): root]
		let graph = OrderedGraph(root: ObjectIdentifier(root)) { identifier in
			var targets = [ObjectIdentifier]()
			for case let .instantiated(_, scope, _) in scopeByIdentifier[identifier]?.propertiesToGenerate ?? [] {
				scopeByIdentifier[ObjectIdentifier(scope)] = scope
				targets.append(ObjectIdentifier(scope))
			}
			return targets
		}
		guard graph.nodes.indices.contains(where: { graph.isOnCycle($0) }) else { return nil }
		// Every node is a scope the walk met, in the graph's order.
		let scopes = graph.nodes.compactMap { scopeByIdentifier[$0] }
		var reason: RootTreeChoiceObservation.PerPathReason?
		for scope in scopes where reason == nil {
			// A call of a seam's generated initializer that passes no builder is a leaf, which receives the tier's
			// parameters, and a seam built by its own initializer is built as any type is. A call that passes a builder
			// keeps the root on today's tree.
			if !scope.holeArguments.isEmpty {
				reason = .buildsSeam
			}
			// One label may be declared and received in several forms across the tree: each read takes the form its nearest
			// declaration provides, on every path, or validation rejects the tree, and a function's body is keyed by the
			// declarations that answer it, so no body reads a form another path's declaration gives.
			for dependency in scope.instantiable.dependencies where reason == nil {
				reason = Self.shapeOutsidePerTypePlan(of: dependency)
			}
		}
		if reason == nil {
			// Today's function captures each label its tree receives that no scope of its cycle declares. A function of the
			// plan, declared in the root's body, captures a statement of the root's body that every call passes
			// (`TypeKeyLayout.rootStatementsCapturedByVariants()`), so a label only the root declares is captured as today;
			// a label another scope declares too could reach a call from that scope, where the plan would take it as a
			// parameter, which is other code than today's.
			var labelsDeclaredByComponent = [Int: Set<String>]()
			var labelsDeclaredOutsideRoot = Set<String>()
			for (index, scope) in scopes.enumerated() {
				if graph.isOnCycle(index) {
					labelsDeclaredByComponent[graph.componentByNode[index], default: []].formUnion(scope.declaredLabels)
				}
				if index > 0 {
					labelsDeclaredOutsideRoot.formUnion(scope.declaredLabels)
				}
			}
			for (index, scope) in scopes.enumerated() where reason == nil && graph.isOnCycle(index) {
				let labelsDeclaredInComponent = labelsDeclaredByComponent[graph.componentByNode[index], default: []]
				let receivesLabelOnlyAnotherScopeDeclares = collectReceivedProperties(from: scope, cache: &cache).received.contains { receivedProperty in
					!labelsDeclaredInComponent.contains(receivedProperty.label)
						&& (labelsDeclaredOutsideRoot.contains(receivedProperty.label) || !scopes[0].declaredLabels.contains(receivedProperty.label))
				}
				if receivesLabelOnlyAnotherScopeDeclares {
					reason = .receivesLabelDeclaredOutsideItsCycle
				}
			}
		}
		return ShapeOutsidePerTypePlan(reason: reason, scopeCount: scopes.count)
	}

	/// The shape of one dependency that keeps a root on today's tree, or `nil`.
	private static func shapeOutsidePerTypePlan(of dependency: Dependency) -> RootTreeChoiceObservation.PerPathReason? {
		let property = dependency.property
		switch dependency.source {
		case let .aliased(fulfillingProperty, _, onlyIfAvailable):
			// A rename reads the property it renames, whose form may differ from its own: a builder renamed as `Any` is
			// a receive of the builder. Only the wrapper kinds are read of the fulfilling property here, since a scope of
			// the same tree declares it, and that declaration refuses the root where it is optional or `Sendable`. A
			// lift that admits such a declaration reads that form of the fulfilling property here in the same change.
			if onlyIfAvailable {
				return .holdsValueOnlyIfAvailable
			} else if !property.propertyType.isConstant || !fulfillingProperty.propertyType.isConstant {
				return .receivesInstantiator
			}
		case let .received(onlyIfAvailable):
			if onlyIfAvailable {
				return .holdsValueOnlyIfAvailable
			} else if !property.propertyType.isConstant {
				return .receivesInstantiator
			}
		case .forwarded,
		     .instantiated:
			break
		}
		switch property.propertyType {
		case .sendableLazilyInstantiated:
			return .holdsLazilyInstantiated
		case .sendableErasedInstantiator,
		     .sendableInstantiator:
			return .holdsSendableWrapperOrFunction
		case .constant,
		     .erasedInstantiator,
		     .instantiator,
		     .lazilyInstantiated:
			break
		}
		if property.typeDescription.isOptional {
			return .holdsValueOnlyIfAvailable
		} else if property.typeDescription.isSendableFunction {
			// Read from the type's structure, never from its spelling: a type whose name holds the word is no such value.
			return .holdsSendableWrapperOrFunction
		} else {
			return nil
		}
	}
}
