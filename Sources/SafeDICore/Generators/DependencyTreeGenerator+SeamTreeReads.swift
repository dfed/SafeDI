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
	/// What `seamRoot(of:reads:generator:…)` reads of a seam's tree for the seam's parameters, the builder function names
	/// it names them apart from, and the escaping types of its signature. Two producers make it: the seam's root generator
	/// (`init(tree:of:instantiables:)`), which every run reads, and the per-type facts of the pass's root
	/// (`init(facts:answeringOtherFieldsFrom:)`), which only a test observing or selecting it makes (`SeamTreeReadsObservation`), beside
	/// the tree's, so that the two can be compared on every seam of every test and fuzzer graph. Which producer answers
	/// each field of the facts' value is `SeamTreeReadsObservation.FactsField` and `TreeField`: a field moves from the second
	/// to the first in the change that produces it from facts, and once every field has moved, `seamRoot` run on the facts'
	/// value must give the signature it gives on the tree's. Holds what it reads for as long as `seamRoot` runs.
	struct SeamTreeReads {
		/// The properties the tree requires of the seam's caller (`ScopeGenerator.requiredReceivedProperties`), the
		/// receives inside the fills of its seam calls among them.
		let requiredReceivedProperties: Set<Property>
		/// The properties the tree requires through `onlyIfAvailable` aliases
		/// (`ScopeGenerator.requiredAliasFulfillingProperties`).
		var requiredAliasFulfillingProperties: Set<Property>
		/// Every receive that leaves the seam (`receivers(in:of:instantiables:)`).
		let receivers: [SeamReceiver]
		/// The reads of the seam's parameters its tree makes, which decide a by-value pass-through's deferral and whether
		/// it is `@Sendable` (`receivers(in:of:instantiables:)`).
		let parameterReads: ParameterReads
		/// The names the tree's declarations declare `@escaping` (`ScopeGenerator.typesDeclaredEscaping`).
		var typesDeclaredEscaping: Set<TypeDescription>
		/// Where the builder function names come from: the tree, walked when `seamRoot` asks for them (a seam that throws,
		/// or equals its own initializer, never asks, so a run walks the tree for them only where it would without this
		/// value), or the facts, which name them once.
		private var builderFunctionNameSource: BuilderFunctionNameSource

		/// Where `builderFunctionNames(includingHoleSites:)` reads its names.
		private enum BuilderFunctionNameSource {
			/// The tree the names are read from (`builderFunctionNamesOfProperties(in:includingHoleSites:)`).
			case tree(ScopeGenerator)
			/// The names the facts give, with and without the hole sites' wrappers.
			case facts(includingHoleSites: Set<String>, excludingHoleSites: Set<String>)
		}

		/// What `generator`, the root generator of `seam`'s tree, holds.
		init(tree generator: ScopeGenerator, of seam: Instantiable, instantiables: [TypeDescription: Instantiable]) {
			requiredReceivedProperties = generator.requiredReceivedProperties
			requiredAliasFulfillingProperties = generator.requiredAliasFulfillingProperties
			(receivers, parameterReads) = DependencyTreeGenerator.receivers(in: generator, of: seam, instantiables: instantiables)
			typesDeclaredEscaping = generator.typesDeclaredEscaping
			builderFunctionNameSource = .tree(generator)
		}

		/// What the facts of the seam's tree, `graph`, hold at its root, for each `FactsField`; every `TreeField` is
		/// `treeReads`'.
		init(facts graph: TypeFactsGraph, answeringOtherFieldsFrom treeReads: SeamTreeReads) {
			// The root is the graph's first node.
			func properties(in rows: BitRows) -> Set<Property> {
				Set(rows.columns(inRow: 0).map { graph.propertyTable[Int($0)] })
			}
			requiredReceivedProperties = treeReads.requiredReceivedProperties
			requiredAliasFulfillingProperties = properties(in: graph.receives.requiredAliasFulfilling)
			typesDeclaredEscaping = Set(graph.typesDeclaredEscaping.columns(inRow: 0).map { graph.typeTable[Int($0)] })
			receivers = treeReads.receivers
			parameterReads = treeReads.parameterReads
			let names = Self.builderFunctionNames(in: graph)
			builderFunctionNameSource = .facts(includingHoleSites: names.includingHoleSites, excludingHoleSites: names.excludingHoleSites)
		}

		/// The name of every builder function the tree declares, the functions that build its hole sites' wrappers among
		/// them where `includingHoleSites` holds (`builderFunctionNamesOfProperties(in:includingHoleSites:)`).
		func builderFunctionNames(includingHoleSites: Bool) -> Set<String> {
			switch builderFunctionNameSource {
			case let .tree(generator):
				DependencyTreeGenerator.builderFunctionNamesOfProperties(in: generator, includingHoleSites: includingHoleSites)
			case let .facts(namesIncludingHoleSites, namesExcludingHoleSites):
				includingHoleSites ? namesIncludingHoleSites : namesExcludingHoleSites
			}
		}

		/// The builder function names of the declarations `graph`'s root reaches, as the tree's walk names them: every
		/// declaration built as a property, a fill's among them, since a call's fills are its generator's children, and its
		/// hole sites only where they are counted. The set of declarations visited dies with the walk.
		private static func builderFunctionNames(in graph: TypeFactsGraph) -> (includingHoleSites: Set<String>, excludingHoleSites: Set<String>) {
			var includingHoleSites = Set<String>()
			var excludingHoleSites = Set<String>()
			let nodes = graph.graph.nodes
			var visited = [Bool](repeating: false, count: nodes.count)
			visited[0] = true
			var nodesToVisit = [0]
			while let node = nodesToVisit.popLast() {
				if let property = nodes[node].property {
					let name = ScopeGenerator.functionName(toBuildPropertyNamed: property.label)
					includingHoleSites.insert(name)
					switch nodes[node].key.leaf {
					case .none, .alias:
						excludingHoleSites.insert(name)
					case .hole:
						break
					}
				}
				for edge in graph.graph.edgeIndices(from: node) where !visited[Int(graph.edgeFacts[edge].child)] {
					let child = Int(graph.edgeFacts[edge].child)
					visited[child] = true
					nodesToVisit.append(child)
				}
			}
			return (includingHoleSites, excludingHoleSites)
		}

		/// The field as the comparison reads it, sorted. The required sets are spelled as `==` reads them, `any P` as `P`:
		/// `seamRoot` asks them only whether they hold a property, and spells each parameter from its receivers. The escaping
		/// types are spelled as declared, since the signature keeps the ones it holds.
		func spelling(of field: SeamTreeReadsObservation.FactsField) -> [String] {
			switch field {
			case .requiredAliasFulfillingProperties:
				requiredAliasFulfillingProperties.map(\.spelledAsEqualityReadsIt).sorted()
			case .typesDeclaredEscaping:
				typesDeclaredEscaping.map(\.asSource).sorted()
			case .builderFunctionNames:
				builderFunctionNamesSpelled()
			}
		}

		/// Both sets of builder function names, each sorted: with the hole sites' wrappers, then without them.
		private func builderFunctionNamesSpelled() -> [String] {
			var spelling = builderFunctionNames(includingHoleSites: true).sorted().map { "with hole sites: \($0)" }
			spelling.append(contentsOf: builderFunctionNames(includingHoleSites: false).sorted().map { "without hole sites: \($0)" })
			return spelling
		}

		/// `field` emptied, so a test can see the comparison report a difference (`SeamTreeReadsObservation.perturbsFactsField`).
		func emptying(_ field: SeamTreeReadsObservation.FactsField) -> SeamTreeReads {
			var reads = self
			switch field {
			case .requiredAliasFulfillingProperties:
				reads.requiredAliasFulfillingProperties = []
			case .typesDeclaredEscaping:
				reads.typesDeclaredEscaping = []
			case .builderFunctionNames:
				reads.builderFunctionNameSource = .facts(includingHoleSites: [], excludingHoleSites: [])
			}
			return reads
		}
	}

	/// The reads a signature pass proceeds with for `seam`, whose tree it built rooted at `rootScope`, with `generator`
	/// at its root: the tree's, or, where a test selects `SeamTreeReadsObservation.Producer.facts`, the facts'. The facts'
	/// value is made only where a test selects it or observes the comparison, which is then made with it.
	static func seamTreeReads(of seam: Instantiable, generator: ScopeGenerator, rootScope: ConstructionScope, instantiables: [TypeDescription: Instantiable]) -> SeamTreeReads {
		let treeReads = SeamTreeReads(tree: generator, of: seam, instantiables: instantiables)
		let observer = SeamTreeReadsObservation.comparesFacts
		let producer = SeamTreeReadsObservation.producer
		guard observer != nil || producer == .facts else {
			return treeReads
		}
		// The facts, and the comparison, which reads the tree again, are made only for a test, so they count no work of the
		// run's.
		let factsReads = GenerationWork.$observer.withValue(nil) {
			let factsReads = SeamTreeReads(facts: TypeFactsGraph(root: rootScope, forMockGeneration: false), answeringOtherFieldsFrom: treeReads)
			if let observer {
				observer(comparison(of: seam, treeReads: treeReads, factsReads: factsReads))
			}
			return factsReads
		}
		switch producer {
		case .tree:
			return treeReads
		case .facts:
			return factsReads
		}
	}

	/// The facts' `SeamTreeReads` of `seam`'s tree, `factsReads`, compared with the tree's, `treeReads`.
	private static func comparison(of seam: Instantiable, treeReads: SeamTreeReads, factsReads: SeamTreeReads) -> SeamTreeReadsComparison {
		var factsReads = factsReads
		if let perturbedField = SeamTreeReadsObservation.perturbsFactsField {
			factsReads = factsReads.emptying(perturbedField)
		}
		var differences = [SeamTreeReadsComparison.Difference]()
		for field in SeamTreeReadsObservation.FactsField.allCases {
			let tree = treeReads.spelling(of: field)
			let facts = factsReads.spelling(of: field)
			if tree != facts {
				differences.append(SeamTreeReadsComparison.Difference(field: field.rawValue, tree: tree, facts: facts))
			}
		}
		return SeamTreeReadsComparison(seam: seam.concreteInstantiable.asSource, differences: differences)
	}
}

/// What a test observes of a seam's `SeamTreeReads`: on every signature pass of every seam, the fields the facts produce,
/// compared with the tree's.
public enum SeamTreeReadsObservation {
	/// The fields the facts of a seam's tree produce at its root, which the comparison compares.
	public enum FactsField: String, CaseIterable, Sendable {
		case requiredAliasFulfillingProperties
		case typesDeclaredEscaping
		/// The builder function names, with and without the hole sites' wrappers.
		case builderFunctionNames
	}

	/// The fields still read from the tree in both values, which the comparison cannot tell apart yet. What the facts lack
	/// for each is said in the pull request that moves it to `FactsField`.
	public enum TreeField: String, CaseIterable, Sendable {
		/// What the tree requires of the caller, the receives inside the fills of the seam calls it makes among them. The
		/// facts' `requiredIncludingFills` row lacks two of a fill's per-route facts: the instance a memo the fill is handed
		/// serves, which its struct-bound row does not hide, and the caller's memo a carried route hands, which it hides.
		case requiredReceivedProperties
		/// Each receive's declaring type, alias, module, and the tier facts of the nested seam call that omits it.
		case receivers
		/// For each label, whether the tree reads it where a parameter is its nearest declaration, and whether inside a
		/// `@Sendable` function. The facts lack, of the labels a fill binds from its struct, those some route of the inner
		/// seam's enum lacks (`boundFromScopeStruct(atEdge:)` leaves them out), a fill the sendable-fill worklist makes
		/// `@Sendable`, and a builder function a cycle makes `@Sendable`.
		case parameterReads
	}

	/// Which value a signature pass proceeds with.
	public enum Producer: Sendable {
		/// The tree's, as every run reads it.
		case tree
		/// The facts' for each `FactsField`, the tree's for each `TreeField`.
		case facts
	}

	/// The value every signature pass proceeds with. Only a test sets it to anything but `.tree`.
	@TaskLocal public static var producer: Producer = .tree

	/// Handed each comparison, where set. Only a test sets it.
	@TaskLocal public static var comparesFacts: (@Sendable (SeamTreeReadsComparison) -> Void)?

	/// A field the facts' value is handed emptied, so a test sees the comparison fail. Only a test sets it.
	@TaskLocal public static var perturbsFactsField: FactsField?
}

/// One signature pass's `SeamTreeReads` of one seam, from its tree and from its facts.
public struct SeamTreeReadsComparison: Sendable {
	/// A field whose two values differ, each spelled as `SeamTreeReads.spelling(of:)` spells it.
	public struct Difference: Sendable, Equatable {
		public let field: String
		public let tree: [String]
		public let facts: [String]
	}

	/// The seam's concrete type.
	public let seam: String
	/// The fields that differ, in `FactsField` order.
	public let differences: [Difference]
}

extension Property {
	/// The property as `TypeDescription`'s `==` reads it: `any P` as `P`.
	fileprivate var spelledAsEqualityReadsIt: String {
		Property(label: label, typeDescription: typeDescription.withoutAny).asSource
	}
}
