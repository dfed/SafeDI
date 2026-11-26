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
	}

	/// Whether the tree of `root`, which reaches a cycle, holds a shape the per-type plan does not lay out yet, decided
	/// from the declarations alone, before any plan or tree is built; `nil` where `root` reaches no cycle.
	///
	/// The plan lays out a root only if its whole tree holds none of the shapes this names: what remains is types that
	/// instantiate one another, by value or through instantiators, with required receives and forwarded values. Every
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
		var formsByLabel = [String: Property]()
		var timesInstantiated = [Int](repeating: 0, count: scopes.count)
		for (index, scope) in scopes.enumerated() where reason == nil {
			if scope.instantiable.generatesDependencyTree {
				reason = .buildsSeam
			} else if scope.instantiable.initializer?.typesDeclaredEscaping.isEmpty == false {
				reason = .declaresEscapingName
			}
			for dependency in scope.instantiable.dependencies where reason == nil {
				reason = Self.shapeOutsidePerTypePlan(of: dependency)
				if reason == nil, let otherForm = formsByLabel.updateValue(dependency.property, forKey: dependency.property.label), otherForm != dependency.property {
					reason = .holdsLabelInSeveralForms
				}
			}
			for (edge, propertyToGenerate) in scope.propertiesToGenerate.filter({ $0.builtScope != nil }).enumerated() where reason == nil {
				let target = graph.edges(from: index)[edge]
				timesInstantiated[target] += 1
				switch propertyToGenerate {
				case let .instantiated(property, _, erasedToConcreteExistential):
					if graph.isOnCycle(target) {
						if erasedToConcreteExistential || property.propertyType == .erasedInstantiator {
							reason = .erasesCycleMember
						}
					} else if timesInstantiated[target] > 1, !scopes[target].propertiesToGenerate.isEmpty {
						reason = .buildsTreeOutsideCyclesTwice
					}
				case .hole:
					reason = .buildsSeam
				case .aliased:
					reason = .renames
				}
			}
		}
		if reason == nil {
			// A function of the plan is declared in the root's body, and captures each label its tree receives that no scope
			// of its cycle declares, so the root's declaration must be the only one such a label has.
			var labelsDeclaredByComponent = [Int: Set<String>]()
			var labelsDeclaredBeneathRoot = Set<String>()
			for (index, scope) in scopes.enumerated() {
				if index > 0 {
					labelsDeclaredBeneathRoot.formUnion(scope.declaredLabels)
				}
				if graph.isOnCycle(index) {
					labelsDeclaredByComponent[graph.componentByNode[index], default: []].formUnion(scope.declaredLabels)
				}
			}
			for (index, scope) in scopes.enumerated() where reason == nil && graph.isOnCycle(index) {
				let labelsDeclaredInComponent = labelsDeclaredByComponent[graph.componentByNode[index], default: []]
				for receivedProperty in collectReceivedProperties(from: scope, cache: &cache).received
					where !labelsDeclaredInComponent.contains(receivedProperty.label) && labelsDeclaredBeneathRoot.contains(receivedProperty.label)
				{
					reason = .receivesLabelDeclaredBetweenRootAndCycle
				}
			}
		}
		return ShapeOutsidePerTypePlan(reason: reason)
	}

	/// The shape of one dependency that keeps a root on today's tree, or `nil`.
	private static func shapeOutsidePerTypePlan(of dependency: Dependency) -> RootTreeChoiceObservation.PerPathReason? {
		let property = dependency.property
		switch dependency.source {
		case .aliased:
			return .renames
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
		case .lazilyInstantiated,
		     .sendableLazilyInstantiated:
			return .holdsLazilyInstantiated
		case .sendableErasedInstantiator,
		     .sendableInstantiator:
			return .holdsSendableWrapperOrFunction
		case .constant,
		     .erasedInstantiator,
		     .instantiator:
			break
		}
		if property.typeDescription.isOptional {
			return .holdsValueOnlyIfAvailable
		} else if property.typeDescription.asSource.contains("Sendable") {
			// Stricter than the shape: a type whose name holds the word stays on today's tree too, whose code is the same.
			return .holdsSendableWrapperOrFunction
		} else {
			return nil
		}
	}
}
