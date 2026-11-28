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
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable (_ root: String, _ detectorFires: Bool, _ todaysTreeReports: Bool) -> Void>?
	/// Called for each production root with the root's type, the labels the per-type facts find no one parameter can
	/// pass (`TypeFactsGraph.cycleFunctionParameters()`) and those today's tree reports, each as `<built type>.<label>`,
	/// sorted; then the parameters of each function a lazy cycle closes on as the facts find them and as today's tree
	/// declares them, one line per place that takes one, sorted. Called for each mock root too.
	@TaskLocal public static var factsObserver: TaskLocalFunction<@Sendable (_ root: String, _ factsLabels: [String], _ todaysTreeLabels: [String], _ factsParameterLines: [String], _ todaysTreeParameterLines: [String]) -> Void>?
}

extension TypeFactsGraph {
	/// Hands `observer` what the facts of this world find of the functions lazy cycles close on beside what `tree`, the
	/// tree of `root`, holds. Test only.
	func compareCycleFunctionParameters(of root: String, with tree: ScopeGenerator, observer: (_ root: String, _ factsLabels: [String], _ todaysTreeLabels: [String], _ factsParameterLines: [String], _ todaysTreeParameterLines: [String]) -> Void) {
		let solved = cycleFunctionParameters()
		let lines = cycleFunctionParameterLines(of: solved, comparedWith: tree)
		observer(
			root,
			Set(solved.unpassableLabels.map { "\(graph.nodes[Int($0.declaration)].scope.instantiable.concreteInstantiable.asSource).\($0.label)" }).sorted(),
			Set(tree.unpassableCycleLabelsInTree.map { "\($0.builtType.asSource).\($0.forms.first?.label ?? "")" }).sorted(),
			lines.facts,
			lines.tree,
		)
	}

	/// One line per place whose function takes a parameter, from `solved` and from `tree`, each sorted.
	private func cycleFunctionParameterLines(of solved: TypeFactsCycleFunctionParameters, comparedWith tree: ScopeGenerator) -> (facts: [String], tree: [String]) {
		func typeName(_ declaration: DeclarationID) -> String {
			graph.nodes[Int(declaration)].scope.instantiable.concreteInstantiable.asSource
		}
		// A declaration is a type built for a property: one type built for two properties is two declarations.
		func name(_ declaration: DeclarationID) -> String {
			"\(typeName(declaration)) for \(graph.nodes[Int(declaration)].property?.asSource ?? "the root")"
		}
		func line(type: String, beneath membersAbove: [String], parameters: [(property: Property, redeclaration: CycleParameter.Redeclaration, isForwarded: Bool)]) -> String {
			let takes = parameters.map { parameter in
				"\(parameter.property.asSource) from \(parameter.isForwarded ? "forwarded " : "")\(parameter.redeclaration.declaringType.asSource).\(parameter.redeclaration.property.asSource) at \(String(describing: parameter.redeclaration.declarationLocation))"
			}
			return "\(type) beneath [\(membersAbove.joined(separator: ", "))] takes \(takes.joined(separator: "; "))"
		}
		var typeDependencies = [String: [Dependency]]()
		for declaration in 0..<DeclarationID(declarationCount) {
			typeDependencies[typeName(declaration)] = graph.nodes[Int(declaration)].scope.instantiable.dependencies
		}
		var typesOfComponent = [String: Set<String>]()
		var factsLines = Set<String>()
		for (place, parameters) in solved.places {
			typesOfComponent[name(place.declaration), default: []].formUnion(
				(0..<DeclarationID(declarationCount)).filter { solved.cycleGroups[Int($0)] == solved.cycleGroups[Int(place.declaration)] }.map(name),
			)
			guard !parameters.isEmpty else { continue }
			factsLines.insert(line(
				type: name(place.declaration),
				beneath: place.componentMembersAbove.map(name),
				parameters: parameters.map { ($0.property, $0.redeclaration, $0.isForwarded) },
			))
		}
		var treeLines = Set<String>()
		var visited = Set<[AnyHashable]>()
		var generatorsToVisit = [(generator: tree, path: [String]())]
		while let (generator, path) = generatorsToVisit.popLast() {
			guard !generator.closesPropertyCycle else { continue }
			var pathBeneath = path
			if let instantiable = generator.builtInstantiable {
				let name = "\(instantiable.concreteInstantiable.asSource) for \(generator.declaration?.property.asSource ?? "the root")"
				let membersAbove = path.filter { typesOfComponent[name, default: []].contains($0) }
				guard visited.insert([ObjectIdentifier(generator), membersAbove]).inserted else { continue }
				if generator.declaresCycleParameters {
					treeLines.insert(line(
						type: name,
						beneath: membersAbove,
						parameters: generator.cycleParameters.map { parameter in
							(
								parameter.property,
								parameter.redeclaration,
								typeDependencies[parameter.redeclaration.declaringType.asSource, default: []].contains { $0.source == .forwarded && $0.property == parameter.redeclaration.property },
							)
						},
					))
				}
				pathBeneath.append(name)
			}
			generatorsToVisit.append(contentsOf: generator.children.map { ($0, pathBeneath) })
		}
		return (factsLines.sorted(), treeLines.sorted())
	}
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
