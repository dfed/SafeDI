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

/// The bodies a plan's declarations are built as: each declaration under each set of answers some path to it gives the
/// labels it reads from above. Two paths that give a declaration equal answers, by value, share one body, whichever
/// declarations the answers came from.
///
/// A first model, compared with today's tree by tests only. An answer is the nearest declaration of the label among the
/// scopes above the body, by label alone: it does not yet judge the order a scope builds its children in, the form a
/// reader takes a declaration in, or whether a body is built inside a `@Sendable` function.
///
/// Holds one entry per body, and for each the bodies its declaration's edges lead to, for as long as its owner keeps it.
struct PlanVariants: Sendable {
	/// One body: a declaration's position in the plan's graph, what each label it reads from above resolves to, in the
	/// order of `LabelsReadFromAbove.labels(of:)`, and the position among the variants of the body each edge of the
	/// declaration leads to, in edge order.
	struct Body: Sendable {
		let declaration: Int
		let answers: [Answer]
		var targets: [Int]
	}

	init(plan: PerTypePlan) {
		let graph = plan.graph
		let labels = LabelsReadFromAbove(
			graph: graph,
			own: { Self.labelsReadFromAbove(byDependenciesOf: graph.nodes[$0].record) },
			bound: { graph.nodes[$0].record.declaredLabels },
		)
		var bodies = [Body(declaration: 0, answers: labels.labels(of: 0).map { _ in .none }, targets: [])]
		var positionByKey = [Key(declaration: 0, answers: bodies[0].answers): 0]
		// Bodies are numbered in the order they are first asked for and their edges followed in that order, so the
		// numbering follows the graph's order alone.
		var next = 0
		while next < bodies.count {
			let declaration = graph.nodes[bodies[next].declaration]
			// A label a target reads from above that this declaration does not declare is one this declaration reads from
			// above too, so its own answer stands.
			var ownAnswerByLabel = [String: Answer]()
			for (label, answer) in zip(labels.labels(of: bodies[next].declaration), bodies[next].answers) {
				ownAnswerByLabel[label] = answer
			}
			var declaredPropertyByLabel = [String: Property]()
			for (property, _) in declaration.record.sortedDeclaredPropertyForms where declaredPropertyByLabel[property.label] == nil {
				declaredPropertyByLabel[property.label] = property
			}
			for target in graph.edges(from: bodies[next].declaration) {
				let builtLabel = graph.nodes[target].built?.property.label
				let answers: [Answer] = labels.labels(of: target).map { label in
					if let property = declaredPropertyByLabel[label] {
						.declared(property, isBeingBuilt: label == builtLabel)
					} else {
						ownAnswerByLabel[label] ?? .none
					}
				}
				let key = Key(declaration: target, answers: answers)
				if let position = positionByKey[key] {
					bodies[next].targets.append(position)
				} else {
					positionByKey[key] = bodies.count
					bodies[next].targets.append(bodies.count)
					bodies.append(Body(declaration: target, answers: answers, targets: []))
				}
			}
			next += 1
		}
		self.bodies = bodies
		self.labels = labels
		nodeDescriptions = graph.nodes.map { declaration in
			if let built = declaration.built {
				"\(declaration.record.instantiable.concreteInstantiable.asSource) as \(built.property.asSource)"
			} else {
				declaration.record.instantiable.concreteInstantiable.asSource
			}
		}
	}

	let bodies: [Body]

	/// One line per body: its position, its declaration, each label it reads from above with its answer, and the
	/// positions of the bodies its edges lead to.
	var projection: String {
		var lines = [String]()
		for (position, body) in bodies.enumerated() {
			var line = "\(position): \(nodeDescriptions[body.declaration])"
			for (label, answer) in zip(labels.labels(of: body.declaration), body.answers) {
				switch answer {
				case .none:
					line.append(" [\(label) = nil]")
				case let .declared(property, isBeingBuilt):
					line.append(" [\(label) = \(property.asSource)\(isBeingBuilt ? " being built" : "")]")
				case let .instance(property):
					line.append(" [\(label) = instance of \(property.asSource)]")
				}
			}
			for target in body.targets {
				line.append(" -> \(target)")
			}
			lines.append(line)
		}
		return lines.joined(separator: "\n")
	}

	/// The labels a scope's own dependencies read from above it: each received property's, and the label an alias is
	/// fulfilled by unless the scope instantiates or forwards a property of that label, which the alias then renames.
	private static func labelsReadFromAbove(byDependenciesOf record: ScopeRecord) -> [String] {
		var createdLabels = Set<String>()
		for dependency in record.instantiable.dependencies {
			switch dependency.source {
			case .instantiated, .forwarded:
				createdLabels.insert(dependency.property.label)
			case .received, .aliased:
				break
			}
		}
		var labels = [String]()
		for dependency in record.instantiable.dependencies {
			switch dependency.source {
			case .instantiated, .forwarded:
				break
			case .received:
				labels.append(dependency.property.label)
			case let .aliased(fulfillingProperty, _, _):
				if !createdLabels.contains(fulfillingProperty.label) {
					labels.append(fulfillingProperty.label)
				}
			}
		}
		return labels
	}

	private struct Key: Hashable {
		let declaration: Int
		let answers: [Answer]
	}

	private let labels: LabelsReadFromAbove
	private let nodeDescriptions: [String]
}
