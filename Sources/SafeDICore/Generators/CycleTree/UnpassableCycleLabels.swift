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

/// Lets a test check, for each production root, that a root whose tree today reports a label no one parameter can pass
/// (`validateCycleLabelsArePassable`) is one `DependencyTreeGenerator.mayHaveUnpassableCycleLabel(inTreeOf:cache:)` keeps
/// on today's tree. Test only.
public enum UnpassableCycleLabelObservation {
	/// Called for each production root with the root's type, whether the detector keeps it on today's tree, and whether
	/// today's tree reports a label no one parameter can pass.
	@TaskLocal public static var observer: (@Sendable (_ root: String, _ detectorFires: Bool, _ todaysTreeReports: Bool) -> Void)?
}

extension DependencyTreeGenerator {
	/// Whether the tree of `root` may hold a label no one parameter of a cycle's builder function can pass
	/// (`UnpassableCycleLabel`), decided from the declarations alone, before any tree is built. A plan has no
	/// cycle-closing scope, so it cannot find such a label itself: a root this answers `true` for is built per path, as
	/// today, and today's walk reports what it finds.
	///
	/// It never answers `false` where today's tree reports a label, which a test checks for every root
	/// (`UnpassableCycleLabelObservation`). Today's tree reports a label of a scope on a cycle that its tree receives in
	/// forms no one parameter carries, where a scope between it and a scope that closes a cycle on it declares the label.
	/// Each scope between is on that cycle, so in the scope's strongly connected component. One received form is always
	/// carried by a parameter of that form, so an unpassable label is received in two forms or more. The forms a place of
	/// today's tree receives are among those its scope's tree receives (`collectReceivedProperties`), the least sets over
	/// the scopes' graph, which every tree a path unfolds from it satisfies. Counting forms, rather than judging them as
	/// `CycleParameter.parameters` does, keeps the answer right where a place receives fewer forms than its scope: more
	/// forms can make a label passable (a required `LazilyInstantiated<X>` beside `X?` and `LazilyInstantiated<X>?`).
	static func mayHaveUnpassableCycleLabel(inTreeOf root: Scope, cache: inout ReceivedPropertiesCache) -> Bool {
		var scopeByIdentifier = [ObjectIdentifier(root): root]
		let graph = OrderedGraph(root: ObjectIdentifier(root)) { identifier in
			var targets = [ObjectIdentifier]()
			for case let .instantiated(_, scope, _) in scopeByIdentifier[identifier]?.propertiesToGenerate ?? [] {
				scopeByIdentifier[ObjectIdentifier(scope)] = scope
				targets.append(ObjectIdentifier(scope))
			}
			return targets
		}
		// Every node is a scope the walk met, in the graph's order.
		let scopes = graph.nodes.compactMap { scopeByIdentifier[$0] }
		// The labels the scopes of each component on a cycle declare or forward.
		var declaredLabelsByComponent = [Int: Set<String>]()
		for (index, scope) in scopes.enumerated() where graph.isOnCycle(index) {
			var declaredLabels = declaredLabelsByComponent[graph.component(of: index), default: []]
			for propertyToGenerate in scope.propertiesToGenerate {
				declaredLabels.insert(propertyToGenerate.property.label)
			}
			for dependency in scope.instantiable.dependencies where dependency.source == .forwarded {
				declaredLabels.insert(dependency.property.label)
			}
			declaredLabelsByComponent[graph.component(of: index)] = declaredLabels
		}
		var mayHaveUnpassableCycleLabel = false
		for (index, scope) in scopes.enumerated() where !mayHaveUnpassableCycleLabel && graph.isOnCycle(index) {
			let declaredLabels = declaredLabelsByComponent[graph.component(of: index), default: []]
			var formCountByLabel = [String: Int]()
			for receivedProperty in collectReceivedProperties(from: scope, cache: &cache).received where declaredLabels.contains(receivedProperty.label) {
				formCountByLabel[receivedProperty.label, default: 0] += 1
			}
			mayHaveUnpassableCycleLabel = formCountByLabel.values.contains { $0 > 1 }
		}
		return mayHaveUnpassableCycleLabel
	}
}
