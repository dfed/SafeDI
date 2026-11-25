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

extension PerTypePlan {
	/// Whether the tree this plan is of can hold a label no one parameter of a builder function a lazy cycle closes on can
	/// pass (`UnpassableCycleLabel`), read from the declarations alone, before any path is built. A plan has no cycle-closing
	/// scope, which is where today's tree finds such a label (`CycleParameter.parameters`), so a root where this holds is
	/// built per path, and the label is reported as today.
	///
	/// Never `false` where today's tree holds such a label. The label is one a scope between the function and one of its
	/// cycle-closing scopes declares, and one the function's body receives in two or more forms (one form is always the
	/// parameter's, as `DependencyTreeGenerator.canHoldUnpassableCycleLabel(inTreeRootedAt:)` argues for a whole tree).
	/// The scope between reaches the closer, whose record is the function's, so it reaches every declaration the function's
	/// body reaches, and is reached from the function: it is a declaration of the function's component, every declaration it
	/// reaches is one the component reaches, and the body is among them. So some component on a cycle has a declaration
	/// that declares a label that the declarations the component reaches, its own included, receive in two or more forms.
	/// Counting forms, never asking whether one parameter carries them, keeps the test monotone: a set of forms one
	/// parameter carries can grow into one it cannot, and back (a required wrapper carries `x: X?` beside
	/// `LazilyInstantiated<X>?`), but never from two forms to fewer.
	///
	/// May be `true` where no such label is: the forms can be received on branches no one function's body holds, or
	/// declared where no cycle closes around them.
	var mayHoldUnpassableCycleLabel: Bool {
		let nodes = graph.nodes
		// What each component declares on a cycle, and what each receives: built in the order components are numbered, so
		// a component's targets, numbered lower, are complete when it is reached.
		var componentCount = 0
		for component in graph.componentByNode {
			componentCount = max(componentCount, component + 1)
		}
		var nodesByComponent = [[Int]](repeating: [], count: componentCount)
		for (index, component) in graph.componentByNode.enumerated() {
			nodesByComponent[component].append(index)
		}
		var receivedFormsByComponent = [[String: Set<Property>]](repeating: [:], count: componentCount)
		for component in nodesByComponent.indices {
			var receivedFormsByLabel = [String: Set<Property>]()
			var declaredLabels = Set<String>()
			var isOnCycle = false
			for index in nodesByComponent[component] {
				let record = nodes[index].record
				for dependency in record.instantiable.dependencies {
					switch dependency.source {
					case .received:
						receivedFormsByLabel[dependency.property.label, default: []].insert(dependency.property)
					case let .aliased(fulfillingProperty, _, _):
						receivedFormsByLabel[fulfillingProperty.label, default: []].insert(fulfillingProperty)
					case .instantiated,
					     .forwarded:
						break
					}
				}
				for target in graph.edges(from: index) where graph.componentByNode[target] != component {
					receivedFormsByLabel.merge(receivedFormsByComponent[graph.componentByNode[target]]) { $0.union($1) }
				}
				if graph.isOnCycle(index) {
					isOnCycle = true
					declaredLabels.formUnion(record.declaredLabels)
				}
			}
			if isOnCycle, declaredLabels.contains(where: { (receivedFormsByLabel[$0]?.count ?? 0) > 1 }) {
				return true
			}
			receivedFormsByComponent[component] = receivedFormsByLabel
		}
		return false
	}
}

/// What the tests read of a plan's detectors: set by the tests, never by the tool.
public enum PerTypePlanDetectorObservation {
	/// What the detectors of one production tree's plan answer, beside what today's tree finds of what each stands for. A
	/// detector that answers `false` where today's tree finds something would lose a diagnostic once the plan builds the
	/// root, so the tests fail on it.
	public struct Answers: Sendable {
		/// The type the tree's root builds.
		public let rootType: String
		public let mayHoldUnpassableCycleLabel: Bool
		/// The labels of the unpassable cycle labels today's tree holds, in its order.
		public let unpassableCycleLabelsInTree: [String]
	}

	/// Called with the answers of each production tree that reaches a cycle.
	@TaskLocal public static var observer: (@Sendable (Answers) -> Void)?

	/// Hands `observer` what the detectors of `root`'s plan answer beside what `tree`, today's tree of `root`, finds.
	static func observeDetectors(of root: ConstructionScope, against tree: ScopeGenerator) {
		guard let observer, let plan = PerTypePlan(root: root) else { return }
		observer(Answers(
			rootType: root.identity.instantiable.concreteInstantiable.asSource,
			mayHoldUnpassableCycleLabel: plan.mayHoldUnpassableCycleLabel,
			unpassableCycleLabelsInTree: tree.unpassableCycleLabelsInTree.map(\.receiver.property.label),
		))
	}
}
