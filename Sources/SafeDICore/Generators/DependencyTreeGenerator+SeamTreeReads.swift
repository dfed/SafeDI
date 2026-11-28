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
		var requiredReceivedProperties: Set<Property>
		/// The properties the tree requires through `onlyIfAvailable` aliases
		/// (`ScopeGenerator.requiredAliasFulfillingProperties`).
		var requiredAliasFulfillingProperties: Set<Property>
		/// Every receive that leaves the seam (`receivers(in:of:instantiables:)`).
		var receivers: [SeamReceiver]
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
		init(facts graph: TypeFactsGraph, instantiables: [TypeDescription: Instantiable], answeringOtherFieldsFrom treeReads: SeamTreeReads) {
			// The root is the graph's first node.
			func properties(in rows: BitRows) -> Set<Property> {
				Set(rows.columns(inRow: 0).map { graph.propertyTable[Int($0)] })
			}
			requiredReceivedProperties = properties(in: graph.receives.requiredIncludingFills)
			requiredAliasFulfillingProperties = properties(in: graph.receives.requiredAliasFulfilling)
			typesDeclaredEscaping = Set(graph.typesDeclaredEscaping.columns(inRow: 0).map { graph.typeTable[Int($0)] })
			receivers = FactsReceiversWalk(graph: graph, instantiables: instantiables).receivers
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
			case .requiredReceivedProperties:
				requiredReceivedProperties.map(\.spelledAsEqualityReadsIt).sorted()
			case .requiredAliasFulfillingProperties:
				requiredAliasFulfillingProperties.map(\.spelledAsEqualityReadsIt).sorted()
			case .typesDeclaredEscaping:
				typesDeclaredEscaping.map(\.asSource).sorted()
			case .builderFunctionNames:
				builderFunctionNamesSpelled()
			case .receivers:
				// In the order the walk first reaches each declaration, which reaches the signature: a parameter's receivers keep
				// it, and its errors note them in it. Both walks reach declarations depth first, each scope's children in the
				// order its scope lists them, which is its type's declaration order and never a set's, so the order is the same
				// on every run.
				receivers.map(\.spelledForComparison)
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
			case .requiredReceivedProperties:
				reads.requiredReceivedProperties = []
			case .requiredAliasFulfillingProperties:
				reads.requiredAliasFulfillingProperties = []
			case .typesDeclaredEscaping:
				reads.typesDeclaredEscaping = []
			case .builderFunctionNames:
				reads.builderFunctionNameSource = .facts(includingHoleSites: [], excludingHoleSites: [])
			case .receivers:
				reads.receivers = []
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
			let factsReads = SeamTreeReads(facts: TypeFactsGraph(root: rootScope, forMockGeneration: false), instantiables: instantiables, answeringOtherFieldsFrom: treeReads)
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

	/// The receives that leave a seam, read from the per-type facts of its tree as `receivers(in:of:instantiables:)` reads
	/// them from the tree: each `@Received` dependency and each alias's fulfilling property that no declaration above the
	/// receiver provides on some path from the root, each declaration once, where the walk first reaches it. The graph has a
	/// node per declaration, not per path, so the walk goes by path, as the tree's does, threading what the declarations
	/// above provide. What a node provides, the receives it declares, and a nested seam call's tier, parameters and
	/// omissions are read from the node's own scope (`ConstructionScope`); a fill provides what the facts say it binds from
	/// its site's struct and does not read of the caller's scope on some route (`TypeFactsReceives.hiddenFromCaller(atEdge:)`,
	/// "A label a fill's case binds on only some routes leaves the seam" in `seam-hole-fills.md`). A path stops at a
	/// declaration of the cycle identity of one above it since the root or its fill (`TypeFactsGraph.cycleIDs`), as the
	/// tree closes a cycle there: the declaration's own receives are judged, and nothing beneath it. Lives only while the
	/// facts' `SeamTreeReads` is made.
	private struct FactsReceiversWalk {
		init(graph: TypeFactsGraph, instantiables: [TypeDescription: Instantiable]) {
			let nodes = graph.graph.nodes
			let readsFromAbove = Self.readsFromAbove(of: graph)
			// The visits made, each projected to what its node's subtree reads from above, as the tree's walk projects its
			// frames (`ReceiversVisit`): two visits of one node that agree on those reads find the same receivers. The
			// projections are read once per node; both die with the walk.
			var visitsMade = Set<Visit>()
			var formsProvidingReadsByNode = [Int: (labels: Set<String>, forms: Set<Property>)]()
			var keptDeclarationIndices = [Declaration: Int]()
			var framesToVisit = [Frame(node: 0, providedProperties: [], fillMemos: [:], cycleIdentitiesAbove: [], closesCycle: false)]
			while let frame = framesToVisit.popLast() {
				let node = nodes[frame.node]
				guard node.key.leaf == .none else { continue }
				let reads: (labels: Set<String>, forms: Set<Property>)
				if let cachedReads = formsProvidingReadsByNode[frame.node] {
					reads = cachedReads
				} else {
					reads = readsFromAbove.formsProvidingReads(of: frame.node)
					formsProvidingReadsByNode[frame.node] = reads
				}
				let visit = Visit(
					node: frame.node,
					closesCycle: frame.closesCycle,
					providedProperties: frame.providedProperties.filter(reads.forms.contains),
					fillMemos: frame.fillMemos.filter { reads.labels.contains($0.key) }.mapValues(\.edge),
				)
				guard visitsMade.insert(visit).inserted else { continue }
				let scope = node.scope
				let instantiable = scope.instantiable
				// A scope that closes a cycle declares nothing for scopes beneath it, and has none.
				let ownProvidedProperties = (frame.closesCycle ? [] : scope.propertiesToDeclare).union(instantiable.forwardedReceivableProperties)
				func isProvided(_ property: Property, by providedProperties: Set<Property>) -> Bool {
					providedProperties.contains(property)
						|| (property.typeDescription.isOptional && providedProperties.contains(property.asUnwrappedProperty))
						|| frame.fillMemos[property.label]?.serves(property, reading: readsFromAbove) == true
				}
				func keep(_ receiver: SeamReceiver) {
					let declaration = Declaration(declaringType: receiver.declaringType, declarationLocation: receiver.declarationLocation, property: receiver.property)
					if let keptIndex = keptDeclarationIndices[declaration] {
						receivers[keptIndex].isFromReportedSeamCall = receivers[keptIndex].isFromReportedSeamCall && receiver.isFromReportedSeamCall
					} else {
						keptDeclarationIndices[declaration] = receivers.endIndex
						receivers.append(receiver)
					}
				}
				let seamCall = scope.seamCall
				let callsReportedSeam = seamCall?.unreachableTierIsReported ?? false
				let omittedByCall = seamCall.map { seamCall in
					Dictionary(grouping: seamCall.omittedParameters + seamCall.noTierParameters, by: \.property.label).compactMapValues(\.first)
				} ?? [:]
				let initializerAccess = DependencyTreeGenerator.parameterAccess(instantiable.effectiveInitializerAccess)
				let ownProvidedLabels = Set(ownProvidedProperties.map(\.label))
				for dependency in instantiable.dependencies {
					switch dependency.source {
					case .received:
						guard !isProvided(dependency.property, by: frame.providedProperties) else { continue }
						if let omitted = omittedByCall[dependency.property.label] {
							let noTierReceivers = omitted.receivers.isEmpty
								? [SeamReceiver(property: dependency.property, instantiable: instantiable, declarationLocation: dependency.declarationLocation, access: omitted.access, isFromReportedSeamCall: callsReportedSeam)]
								: omitted.receivers.map { SeamReceiver($0, moduleName: instantiables[$0.declaringType]?.moduleName, isFromReportedSeamCall: callsReportedSeam) }
							let nestedSeamCall = seamCall.map { seamCall in
								SeamSignature.NestedSeamCall(
									seamType: instantiable.concreteInstantiable,
									seamModuleName: seamCall.seamModuleName,
									tier: seamCall.tier,
									requirement: seamCall.requirement,
									callerModuleName: seamCall.callerModuleName,
									parameterTierAccess: seamCall.omittedParameters.contains { $0.property.label == dependency.property.label } ? omitted.tierAccess : nil,
									receivingTypes: noTierReceivers.map(\.declaringType).uniqued(),
								)
							}
							for var receiver in noTierReceivers {
								receiver.isNoTier = true
								receiver.noTierCallTier = seamCall?.tier
								receiver.nestedSeamCall = nestedSeamCall
								keep(receiver)
							}
						} else if let parameter = seamCall?.parameters.first(where: { $0.property == dependency.property }) {
							if parameter.receivers.isEmpty {
								keep(SeamReceiver(property: dependency.property, instantiable: instantiable, declarationLocation: dependency.declarationLocation, access: parameter.access, isFromReportedSeamCall: callsReportedSeam))
							} else {
								parameter.receivers.map { SeamReceiver($0, moduleName: instantiables[$0.declaringType]?.moduleName, isFromReportedSeamCall: callsReportedSeam) }.forEach(keep)
							}
						} else {
							keep(SeamReceiver(property: dependency.property, instantiable: instantiable, declarationLocation: dependency.declarationLocation, access: initializerAccess))
						}
					case let .aliased(fulfillingProperty, _, _):
						guard !isProvided(fulfillingProperty, by: frame.providedProperties.union(ownProvidedProperties)) else { continue }
						keep(SeamReceiver(property: fulfillingProperty, instantiable: instantiable, declarationLocation: dependency.declarationLocation, access: initializerAccess, aliasProperty: dependency.property))
					case .instantiated, .forwarded:
						continue
					}
				}
				guard !frame.closesCycle else { continue }
				let childProvidedProperties = frame.providedProperties.union(ownProvidedProperties)
				// A declaration of a label hides an enclosing fill's memo of it.
				let childFillMemos = frame.fillMemos.filter { !ownProvidedLabels.contains($0.key) }
				let childCycleIdentities = frame.cycleIdentitiesAbove.union([graph.cycleIDs[frame.node]])
				var fillHoles = scope.holeArguments.compactMap { holeArgument -> SeamSignature.Hole? in
					switch holeArgument {
					case let .fill(hole, _, _):
						hole
					case .passUp:
						nil
					}
				}.makeIterator()
				let firstFrameIndex = framesToVisit.endIndex
				for edge in graph.graph.edgeIndices(from: frame.node) {
					let child = Int(graph.graph.edgeTargets[edge])
					if graph.edgeFacts[edge].isFill, let hole = fillHoles.next() {
						// A fill's tree is a function of its own, whose stack starts at its root, and its child receives what the fill
						// binds from the site's struct beside what encloses the call.
						let fillProvidedProperties = graph.receives.hiddenFromCaller(atEdge: edge).map { graph.propertyTable[Int($0)] }
						var fillMemos = childFillMemos
						let boundLabels = Set(fillProvidedProperties.map(\.label))
						for property in fillProvidedProperties {
							fillMemos[property.label] = nil
						}
						// A `LazilyInstantiated` memo whose label the fill's tree reads inside a `@Sendable` function is bound by value
						// (`ScopeGenerator.fillDeferredLabelsReadInsideSendableFunction`), so it serves no wrapper's read.
						let labelsBoundByValue = Self.labels(
							among: Set(hole.fields.filter { $0.deferral == .deferred(isSendable: false) && boundLabels.contains($0.property.label) }.map(\.property.label)),
							readInsideSendableFunctionBeneath: edge,
							of: graph,
						)
						for field in hole.fields where boundLabels.contains(field.property.label) && (field.bindsMemo || (field.isDeferredParameter && hole.innerSeamType != nil)) && !(labelsBoundByValue.contains(field.property.label) && field.deferral != .deferred(isSendable: true)) {
							fillMemos[field.property.label, default: FillMemo(edge: edge, fulfiller: child, fields: [])].fields.append(field)
						}
						// A memo some route hands the fill through the levels on a carried route (`Scope.Fill.labelsHandedAsMemo`) is bound
						// in place of the place's field, so the facts' row holds the memo's value forms, and not the place's field, of a
						// label the hole carries in a field no deferred parameter's.
						let fillProvidedSet = Set(fillProvidedProperties)
						for field in hole.fields where !field.isDeferredParameter && !fillProvidedSet.contains(field.property) {
							for value in fillProvidedProperties where value.label == field.property.label && !value.typeDescription.isOptional {
								fillMemos[value.label, default: FillMemo(edge: edge, fulfiller: child, fields: [])].handedMemoValues.append(value)
							}
						}
						framesToVisit.append(Frame(node: child, providedProperties: childProvidedProperties.union(fillProvidedProperties), fillMemos: fillMemos, cycleIdentitiesAbove: [], closesCycle: false))
					} else {
						framesToVisit.append(Frame(node: child, providedProperties: childProvidedProperties, fillMemos: childFillMemos, cycleIdentitiesAbove: childCycleIdentities, closesCycle: childCycleIdentities.contains(graph.cycleIDs[child])))
					}
				}
				framesToVisit.reverseElements(from: firstFrameIndex)
			}
		}

		/// The receives that leave the seam, in the order the walk first reaches each declaration.
		private(set) var receivers = [SeamReceiver]()

		/// A node to visit on one path, with what the declarations above it on the path provide, the memos the nearest fills
		/// above it bind by label, where no declaration between hides them, the cycle identities of the declarations above
		/// it since the root or its fill, and whether it repeats one of them.
		private struct Frame {
			let node: Int
			let providedProperties: Set<Property>
			let fillMemos: [String: FillMemo]
			let cycleIdentitiesAbove: Set<Int32>
			let closesCycle: Bool
		}

		/// A visit made: a node, with its frame projected to what the node's subtree reads from above it.
		private struct Visit: Hashable {
			let node: Int
			let closesCycle: Bool
			let providedProperties: Set<Property>
			let fillMemos: [String: Int]
		}

		/// A receive's declaration: one type's receive of one property, at one location.
		private struct Declaration: Hashable {
			let declaringType: TypeDescription
			let declarationLocation: Dependency.DeclarationLocation?
			let property: Property
		}

		/// The fields of one label a fill binds from its site's struct as the memo of a deferred parameter, along the fill's
		/// edge, whose child is the fill's built type. The facts hold no row of what else makes a fill bind a memo, so the
		/// fields are the hole's, not a case's (`ScopeGenerator.caseFields(of:)`), and none is bound for a label hidden by a
		/// call that re-enters the seam (`fillDeferredLabelsHiddenByReenteringCalls`); no seam test tells those apart yet. A
		/// memo handed on a carried route is read from the fill edge's row (`handedMemoValues`).
		private struct FillMemo {
			let edge: Int
			let fulfiller: Int
			var fields: [SeamSignature.Hole.Field]
			/// The values of the memos the fill is handed on a carried route, of the label. The facts hold no memo's deferral,
			/// which the tree decides from what the fill's tree reads (`ScopeGenerator.fillSendableWrapperReads`), so a handed
			/// memo serves a read of either wrapper kind; a fill reading the other kind than its memo is rejected
			/// (`sendableWrapperReadBesidePlainMemo`).
			var handedMemoValues = [Property]()

			/// Whether one of the memos serves a read of `property`, a `LazilyInstantiated` or `SendableLazilyInstantiated`,
			/// as `ScopeGenerator.fillBoundMemo(servingWrapperRead:)` decides: a memo of the read's own kind, of its instance,
			/// whose value the fill's tree reads.
			func serves(_ property: Property, reading readsFromAbove: ReadsOfSubtrees) -> Bool {
				guard let instance = property.asLazilyInstantiatedInstanceProperty else { return false }
				let deferral = SeamSignature.Parameter.Deferral.deferred(isSendable: property.propertyType == .sendableLazilyInstantiated)
				return fields.contains { field in
					field.deferral == deferral
						&& field.property.asUnwrappedProperty == instance.asUnwrappedProperty
						&& readsFromAbove.reads(field.property, beneath: fulfiller)
				} || handedMemoValues.contains { value in
					value.asUnwrappedProperty == instance.asUnwrappedProperty && readsFromAbove.reads(value, beneath: fulfiller)
				}
			}
		}

		/// What each node's subtree receives from above it, along every edge, fills' included: the received properties and
		/// aliases' fulfilling properties of its declarations, less what each declaration provides to those beneath it and
		/// what a fill binds from its struct. It holds at least what the walk finds beneath the node on any path, which is
		/// what a visit's projection needs. Its rows live while the walk does.
		private struct ReadsOfSubtrees {
			let rows: BitRows
			let requests: [Property]
			let requestIDs: [Property: Int32]

			/// The labels the node's subtree reads from above it, and each form that would provide one of those reads.
			func formsProvidingReads(of node: Int) -> (labels: Set<String>, forms: Set<Property>) {
				var labels = Set<String>()
				var forms = Set<Property>()
				for request in rows.columns(inRow: node).map({ requests[Int($0)] }) {
					labels.insert(request.label)
					forms.insert(request)
					if request.typeDescription.isOptional {
						forms.insert(request.asUnwrappedProperty)
					}
				}
				return (labels, forms)
			}

			/// Whether the subtree of `node` receives `field` from above it, its optional form, or its instance.
			func reads(_ field: Property, beneath node: Int) -> Bool {
				var forms = [field, field.asOptionalProperty]
				if let instance = field.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
					forms.append(instance)
					forms.append(instance.asOptionalProperty)
				}
				return forms.contains { form in
					requestIDs[form].map { rows.contains($0, inRow: node) } == true
				}
			}
		}

		/// The labels among `labels` that the tree of the fill along `fillEdge` reads inside a `@Sendable` function, where no
		/// declaration inside the tree hides them, as `ScopeGenerator.labelsReadInsideSendableFunction(among:)` finds them:
		/// a received dependency, or an alias's fulfilling property its own scope does not declare, beneath an edge that opens
		/// a `@Sendable` function (`TypeFactsEdge.opens`). The fill's own function is not one of those: what it binds is a
		/// local of it. The visits made die with the call.
		private static func labels(among labels: Set<String>, readInsideSendableFunctionBeneath fillEdge: Int, of graph: TypeFactsGraph) -> Set<String> {
			guard !labels.isEmpty else { return [] }
			struct Visit: Hashable {
				let node: Int
				let isInsideSendableFunction: Bool
				let declaredLabels: Set<String>
			}
			func opensSendableFunction(_ opened: TypeFactsFunctionOpened) -> Bool {
				switch opened {
				case .sendableInstantiatorBuilder, .sendableLazyWrapper, .otherSendableFunction:
					true
				case .none, .instantiatorBuilder:
					false
				}
			}
			let fillOpens = graph.edgeFacts[fillEdge].opens
			var labelsRead = Set<String>()
			var visitsMade = Set<Visit>()
			var visitsToMake = [Visit(
				node: Int(graph.graph.edgeTargets[fillEdge]),
				isInsideSendableFunction: fillOpens == .sendableInstantiatorBuilder || fillOpens == .sendableLazyWrapper,
				declaredLabels: [],
			)]
			while let visit = visitsToMake.popLast() {
				guard visitsMade.insert(visit).inserted else { continue }
				let node = graph.graph.nodes[visit.node]
				guard node.key.leaf == .none else { continue }
				let instantiable = node.scope.instantiable
				let ownLabels = Set(node.scope.propertiesToDeclare.union(instantiable.forwardedReceivableProperties).map(\.label)).intersection(labels)
				func recordRead(of label: String) {
					if visit.isInsideSendableFunction, labels.contains(label), !visit.declaredLabels.contains(label) {
						labelsRead.insert(label)
					}
				}
				for dependency in instantiable.dependencies {
					switch dependency.source {
					case .received:
						recordRead(of: dependency.property.label)
					case let .aliased(fulfillingProperty, _, _):
						// An alias that keeps its fulfilling property's label is not in scope where that property is read.
						if fulfillingProperty.label == dependency.property.label || !ownLabels.contains(fulfillingProperty.label) {
							recordRead(of: fulfillingProperty.label)
						}
					case .instantiated, .forwarded:
						continue
					}
				}
				let childDeclaredLabels = visit.declaredLabels.union(ownLabels)
				for edge in graph.graph.edgeIndices(from: visit.node) {
					let fillBoundLabels = graph.edgeFacts[edge].isFill ? Set(graph.receives.hiddenFromCaller(atEdge: edge).map { graph.propertyTable[Int($0)].label }).intersection(labels) : []
					visitsToMake.append(Visit(
						node: Int(graph.graph.edgeTargets[edge]),
						isInsideSendableFunction: visit.isInsideSendableFunction || opensSendableFunction(graph.edgeFacts[edge].opens),
						declaredLabels: childDeclaredLabels.union(fillBoundLabels),
					))
				}
			}
			return labelsRead
		}

		private static func readsFromAbove(of graph: TypeFactsGraph) -> ReadsOfSubtrees {
			let nodes = graph.graph.nodes
			var requests = [Property]()
			var requestIDs = [Property: Int32]()
			func id(of property: Property) -> Int32 {
				if let id = requestIDs[property] {
					return id
				}
				let id = Int32(requests.count)
				requests.append(property)
				requestIDs[property] = id
				return id
			}
			let ownRequests = nodes.map { node -> [Int32] in
				guard node.key.leaf == .none else { return [] }
				return node.scope.instantiable.dependencies.compactMap { dependency in
					switch dependency.source {
					case .received:
						id(of: dependency.property)
					case let .aliased(fulfillingProperty, _, _):
						id(of: fulfillingProperty)
					case .instantiated, .forwarded:
						nil
					}
				}
			}
			/// Inserts the requests `properties` provide, each by itself or as the unwrapped form of an optional request.
			func insertRequests(providedBy properties: some Sequence<Property>, _ insert: (Int32) -> Void) {
				for property in properties {
					if let id = requestIDs[property] {
						insert(id)
					}
					if let id = requestIDs[property.asOptionalProperty] {
						insert(id)
					}
				}
			}
			let own = BitRows(rowCount: nodes.count, columnCount: requests.count) { node, insert in ownRequests[node].forEach(insert) }
			let hidden = BitRows(rowCount: nodes.count, columnCount: requests.count) { node, insert in
				guard nodes[node].key.leaf == .none else { return }
				insertRequests(providedBy: nodes[node].scope.propertiesToDeclare.union(nodes[node].scope.instantiable.forwardedReceivableProperties), insert)
			}
			let hiddenAtEdge = BitRows(rowCount: graph.graph.edgeCount, columnCount: requests.count) { edge, insert in
				insertRequests(providedBy: graph.receives.hiddenFromCaller(atEdge: edge).map { graph.propertyTable[Int($0)] }, insert)
			}
			let rows = ReadsFromAbove(graph: graph.graph, own: own, hidden: hidden, hiddenAtEdge: hiddenAtEdge).rows
			return ReadsOfSubtrees(rows: rows, requests: requests, requestIDs: requestIDs)
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
		/// What the tree requires of the caller, the receives inside the fills of the seam calls it makes among them
		/// (`TypeFactsReceives.requiredIncludingFills`).
		case requiredReceivedProperties
		case requiredAliasFulfillingProperties
		case typesDeclaredEscaping
		/// The builder function names, with and without the hole sites' wrappers.
		case builderFunctionNames
		/// Every receive that leaves the seam, each with every stored property, in the order the walk reaches them.
		case receivers
	}

	/// The fields still read from the tree in both values, which the comparison cannot tell apart yet. What the facts lack
	/// for each is said in the pull request that moves it to `FactsField`.
	public enum TreeField: String, CaseIterable, Sendable {
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

extension DependencyTreeGenerator.SeamReceiver {
	/// Every stored property of the receive, as the comparison reads it, a `key=value` part each, joined by `; `. Types are
	/// spelled as declared, since a parameter is spelled from its receivers.
	fileprivate var spelledForComparison: String {
		var parts = [String]()
		parts.append("property=\(property.asSource)")
		parts.append("declaringType=\(declaringType.asSource)")
		parts.append("location=\(declarationLocation.map { "\($0.filePath) \($0.order) \($0.placement)" } ?? "none")")
		parts.append("access=\(access)")
		parts.append("module=\(moduleName ?? "none")")
		parts.append("instantiateMethodParameter=\(isInstantiateMethodParameter)")
		parts.append("noTier=\(isNoTier)")
		parts.append("noTierCallTier=\(noTierCallTier.map { "\($0)" } ?? "none")")
		parts.append("nestedSeamCall=\(nestedSeamCall.map(\.spelledForComparison) ?? "none")")
		parts.append("alias=\(aliasProperty?.asSource ?? "none")")
		parts.append("fromReportedSeamCall=\(isFromReportedSeamCall)")
		return parts.joined(separator: "; ")
	}
}

extension SeamSignature.NestedSeamCall {
	/// Every stored property of the call, as the comparison of receivers reads it.
	fileprivate var spelledForComparison: String {
		"\(seamType.asSource) of \(seamModuleName ?? "none") at \(tier) for \(requirement) from \(callerModuleName ?? "none"), parameter tier \(parameterTierAccess.map { "\($0)" } ?? "none"), receiving \(receivingTypes.map(\.asSource))"
	}
}

extension Property {
	/// The property as `TypeDescription`'s `==` reads it: `any P` as `P`.
	fileprivate var spelledAsEqualityReadsIt: String {
		Property(label: label, typeDescription: typeDescription.withoutAny).asSource
	}
}
