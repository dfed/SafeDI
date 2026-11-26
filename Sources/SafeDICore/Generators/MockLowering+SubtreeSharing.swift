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

/// An internal mock's walk shares a built node's subtree between the places that build one generator in one context.
///
/// The generators of a mock's tree form a graph that shares a type's generator between the places that build it in one
/// context, while the walk reaches every place on every path: a tree whose screens each build the next layer's screens
/// has as many paths as screens to the power of its layers, and the walk's time grew threefold with each layer. Every
/// record a built place's subtree makes is relative to the configuration its own call hands it
/// (`relateConfiguration(ofBuiltPlaceAt:of:)`), so two places of one generator whose subtrees read the same walk state make
/// the same records but for what each place's own call hands, which `SharedRecordKey` already lets differ. The walk meets
/// such a subtree once: at a later meeting of its key it takes the first meeting's tree nodes and child records, and
/// writes no text for it.
///
/// What a subtree reads of the walk state around it is its key (`SubtreeKey`), each part restricted to what the subtree
/// can read (`SubtreeFacts`). A subtree is shared only where nothing in it reads state the key does not hold (`isClosed`):
/// a closer, a loop of builders, a hole, a fill, a call of another module's public mock, a `@Sendable` builder function, an
/// actor's argument, or a payload or member call bound by path keep the walk's per-path descent. A root with a closer or a
/// loop anywhere is walked on every path, since their records read every path's place (`nearestConfigurations`,
/// `loopUnitRecords`).
///
/// Shared subtrees write no text, so the walk's body is whole only where nothing was shared. A root whose type-key layout
/// falls back to that body is lowered again with sharing off (`lowerMockRootWithTree(of:context:)`), which writes the
/// body it always did.
extension MockLowering {
	/// Whether an internal mock's walk shares work a repeated subtree would repeat. The comparison
	/// `sharingComparisonObserver` reports turns it off to walk every path; the tool never does.
	@TaskLocal static var sharesSubtrees = true

	/// Called, where set, with what a traversal that shares repeated subtrees found and what the same traversal finds with
	/// the switch off, which walks every path: each internal mock root's mock and configurations
	/// (`lowerMockRootWithTree(of:context:)`). Set by the tests and the graph fuzzer, which fail on any difference; never by
	/// the tool.
	@TaskLocal public static var sharingComparisonObserver: (@Sendable (_ subject: String, _ shared: String, _ unshared: String) -> Void)?

	/// Called, where set, for each internal mock root the type key lays out, with how many meetings its walk took a subtree
	/// met before and how its layout ended, and, where the layout of the walk that shared fell back, how the layout of the
	/// walk of every path ends. Set by the tests and the graph fuzzer, which fail a root that falls back only where it
	/// shares, and read the counts; never by the tool.
	@TaskLocal public static var subtreeSharingObserver: (@Sendable (SubtreeSharingOutcome) -> Void)?

	/// What `subtreeSharingObserver` is told of one root.
	public struct SubtreeSharingOutcome: Equatable, Sendable {
		public let mockedType: String
		public let sharedMeetings: Int
		/// `laidOut`, or why the layout of the walk that shared fell back (`typeKeyLayoutObserver`).
		public let layoutOutcome: String
		/// Where the walk that shared fell back after sharing, the outcome of the layout of the walk of every path, which
		/// lowers the root instead.
		public let unsharedLayoutOutcome: String?
		/// How many generators' subtree facts the walk held, and the words of label bits they held, which grow with the
		/// generators the root's tree reaches on several paths and the labels beneath each.
		public let heldFacts: HeldFacts

		public struct HeldFacts: Equatable, Sendable {
			public let generators: Int
			public let labelWords: Int
		}
	}

	/// What of a mock root's result the observer compares: its code, and the first configuration record of each concrete
	/// type and construction, which the module's configurations and its one-way check read (`configurationCode`,
	/// `configurationsBuiltTwoWays`). A shared subtree records no configuration again, and the walk order of the records
	/// after it moves, which neither reads.
	static func sharingComparison(of result: Result, sendableConfigurationTypeNames: Set<String>) -> String {
		var text = result.code
		var seen = Set<String>()
		for record in result.configurations {
			let key = "\(record.concreteType.asSource) \(record.usesMockInitializer)"
			guard seen.insert(key).inserted else { continue }
			text += "\n// \(key)\n\(record.configurationStruct(amongConfigurationsTypedSendable: sendableConfigurationTypeNames))"
			if let oneWay = record.oneWayConstruction {
				text += "\n// \(oneWay.property) \(oneWay.parentConcreteType ?? "") \(oneWay.customMockName ?? "") \(oneWay.isExtensionBased) \(oneWay.isBeneathCycleEdge) \(oneWay.requirements)"
			}
			if let beneathRepeatedAncestor = record.beneathRepeatedAncestor {
				text += "\n// \(beneathRepeatedAncestor)"
			}
		}
		return text
	}

	/// What the walk knows of a generator's subtree, worked out from the generators beneath it up, for the generators the
	/// root's tree reaches on several paths.
	struct SubtreeFacts {
		/// Whether nothing in the subtree, its own node included, reads walk state its key does not hold.
		let isClosed: Bool
		/// Every label a node of the subtree declares, depends on or renames, which bounds what it reads of the names around
		/// it, as indices into the root's labels (`SubtreeSharing.labelIndices`).
		let readLabels: LabelSet
	}

	/// A set of a root's labels, by their indices, one bit each, so that a generator's labels and its children's cost a word
	/// per sixty-four labels rather than a copy of every label beneath it.
	struct LabelSet {
		private var words = [UInt64]()

		func contains(_ index: Int) -> Bool {
			let word = index / 64
			return word < words.count && words[word] & (1 << UInt64(index % 64)) != 0
		}

		mutating func insert(_ index: Int) {
			let word = index / 64
			if word >= words.count {
				words.append(contentsOf: repeatElement(0, count: word - words.count + 1))
			}
			words[word] |= 1 << UInt64(index % 64)
		}

		var wordCount: Int {
			words.count
		}

		mutating func formUnion(_ other: LabelSet) {
			if other.words.count > words.count {
				words.append(contentsOf: repeatElement(0, count: other.words.count - words.count))
			}
			for (index, word) in other.words.enumerated() {
				words[index] |= word
			}
		}
	}

	/// A built node's subtree in one context: its generator, and what of the walk state its children are walked in the
	/// subtree can read (`SubtreeFacts.readLabels`). Every other part of that state is either the same wherever the
	/// generator is met, or keeps the subtree from being shared (`Walk.sharedSubtreeKey(of:…)`).
	struct SubtreeKey: Hashable {
		let generator: ObjectIdentifier
		/// The node's children in generation order, with what each is built before and without: the descent beneath them
		/// follows from these.
		let children: [ChildContext]
		/// Whether the node's override reaches its children's.
		let overridePathReachable: Bool
		/// Whether the children are built inside a `@Sendable` builder function.
		let isInsideSendableFunction: Bool
		/// The names a receive is handed in place of its label, the wrappers `mock()` binds, and the bindings the node is
		/// passed by name, each for the labels the subtree reads.
		let renames: [String: [TypeDescription: String]]
		let lazilyInstantiatedNames: [String: [TypeDescription: String]]
		let bindingNamesPassedByName: [String: String]
		/// The declarations in scope of the children, of the labels the subtree reads.
		let scope: Set<Property>

		struct ChildContext: Hashable {
			let index: Int
			let unavailableProperties: Set<Property>
			let propertiesGeneratedLater: Set<Property>
		}
	}

	/// A subtree the walk met first, which later meetings of its key take: its tree nodes, and the path of the place that
	/// holds its records.
	struct SharedSubtree {
		let children: [TreeNode]
		let sourcePath: [Int]
	}

	/// One root's sharing of subtrees: the generators its tree reaches on several paths, their facts, the subtrees its walk
	/// met, and where it took one.
	///
	/// The table of subtrees met is a set of the nodes one building walk has already seen, which dies with that walk: the
	/// deliberate exception to "Share work by construction" (`generator-design.md`). A later meeting takes what the first
	/// made exactly where its key says the subtree reads the same state. Every test's and every fuzzer graph's mock roots
	/// are lowered again with `sharesSubtrees` off and compared (`sharingComparisonObserver`, which `executeSafeDIToolTest`
	/// sets).
	///
	/// Memory: one identifier per generator the root's tree reaches on several paths, with the facts of those the walk
	/// forms a key at (a bit per label of the root's tree), the tree nodes and child records of each subtree met first, and
	/// the path each later meeting reads its records from, held by the root's walk until the root's lowering returns.
	final class SubtreeSharing {
		/// The sharing of the walk of `root`'s tree, or `nil` where it can share nothing: a node in the tree closes a cycle or
		/// a level holds a loop of builders, whose records read every path's place (`nearestConfigurations`,
		/// `loopUnitRecords`), or no generator is reached on more than one path.
		init?(sharingBeneath root: ScopeGenerator, inlinePlacePaths: some Sequence<[Int]>) {
			// The generators of the tree, each after every generator that builds it, from a depth-first walk on a stack of
			// its own, since a mock tree can be as deep as the module has types.
			var postorder = [ScopeGenerator]()
			var visited = Set<ObjectIdentifier>()
			var stack: [(generator: ScopeGenerator, childrenPushed: Bool)] = [(root, false)]
			while let entry = stack.popLast() {
				let generator = entry.generator
				if entry.childrenPushed {
					postorder.append(generator)
					continue
				}
				guard visited.insert(ObjectIdentifier(generator)).inserted else { continue }
				guard generator.receivedBuilderLoops.loopByChildIndex.isEmpty else { return nil }
				if case let .property(_, _, _, _, isPropertyCycle, _) = generator.scopeData, isPropertyCycle {
					return nil
				}
				stack.append((generator, true))
				for child in generator.orderedChildGenerators where !visited.contains(ObjectIdentifier(child)) {
					stack.append((child, false))
				}
			}
			// How many paths reach each generator, counted up to two.
			var pathCounts = [ObjectIdentifier(root): 1]
			for generator in postorder.reversed() {
				let count = pathCounts[ObjectIdentifier(generator), default: 0]
				for child in generator.orderedChildGenerators {
					pathCounts[ObjectIdentifier(child), default: 0] = min(2, pathCounts[ObjectIdentifier(child), default: 0] + count)
				}
			}
			let generatorsOnSeveralPaths = Set(pathCounts.lazy.filter { $0.value > 1 }.map(\.key))
			guard !generatorsOnSeveralPaths.isEmpty else { return nil }
			self.generatorsOnSeveralPaths = generatorsOnSeveralPaths
			var pathsHoldingInlinePlace = Set<[Int]>()
			for path in inlinePlacePaths {
				for depth in 1...max(path.count, 1) {
					pathsHoldingInlinePlace.insert(Array(path.prefix(depth)))
				}
			}
			self.pathsHoldingInlinePlace = pathsHoldingInlinePlace
		}

		/// The generators the root's tree reaches on more than one path, the only ones a later meeting can take.
		let generatorsOnSeveralPaths: Set<ObjectIdentifier>
		/// The index of each label the facts hold, in the order they first met it.
		private(set) var labelIndices = [String: Int]()
		/// The facts of each generator the walk formed a key at, and of those beneath it.
		private var factsByGenerator = [ObjectIdentifier: SubtreeFacts]()
		/// The subtree each key was first met with.
		var subtrees = [SubtreeKey: SharedSubtree]()
		/// The places whose subtrees later meetings take, each inserted at its first later meeting.
		var sourcePaths = Set<[Int]>()
		/// The place each later meeting takes its subtree's records from, by the meeting's path.
		var sourcePathByPath = [[Int]: [Int]]()
		/// The child records of each place later meetings take, kept once the place is recorded.
		var childCodesBySourcePath = [[Int]: [GeneratedCode]]()
		/// How many meetings took a subtree met before.
		var sharedMeetings = 0
		/// The paths at or above a place of another module's public mock the tree builds inline, which reads the builder
		/// `mock()` takes for it by its path (`FilledCallBuilders.holeBuildersByInlinePlace`).
		let pathsHoldingInlinePlace: Set<[Int]>

		/// Lets go of every table but the count of shared meetings, once the root's places are laid out: the assembly of the
		/// mock reads only the count.
		func releaseTables() {
			factsByGenerator = [:]
			subtrees = [:]
			sourcePaths = []
			sourcePathByPath = [:]
			childCodesBySourcePath = [:]
		}

		/// The facts the walk holds, which the observer reports.
		var heldFacts: SubtreeSharingOutcome.HeldFacts {
			.init(generators: factsByGenerator.count, labelWords: factsByGenerator.values.reduce(0) { $0 + $1.readLabels.wordCount })
		}

		/// Whether a subtree whose facts are `facts` can read `label`.
		func reads(_ label: String, in facts: SubtreeFacts) -> Bool {
			labelIndices[label].map(facts.readLabels.contains) ?? false
		}

		/// The facts of `generator`'s subtree, each generator's worked out once, from the generators beneath it up, on an
		/// explicit stack rather than the thread's.
		func facts(of generator: ScopeGenerator) -> SubtreeFacts {
			if let facts = factsByGenerator[ObjectIdentifier(generator)] {
				return facts
			}
			var stack: [(generator: ScopeGenerator, childrenPushed: Bool)] = [(generator, false)]
			while let entry = stack.popLast() {
				let current = entry.generator
				guard factsByGenerator[ObjectIdentifier(current)] == nil else { continue }
				let children = current.orderedChildGenerators
				if entry.childrenPushed {
					factsByGenerator[ObjectIdentifier(current)] = facts(of: current, children: children.compactMap { factsByGenerator[ObjectIdentifier($0)] })
				} else {
					stack.append((current, true))
					for child in children where factsByGenerator[ObjectIdentifier(child)] == nil {
						stack.append((child, false))
					}
				}
			}
			return factsByGenerator[ObjectIdentifier(generator)] ?? facts(of: generator, children: [])
		}

		/// The facts of `generator`'s subtree, given its children's.
		private func facts(of generator: ScopeGenerator, children: [SubtreeFacts]) -> SubtreeFacts {
			var isClosed = Self.isClosed(atNode: generator)
			var readLabels = LabelSet()
			switch generator.scopeData {
			case let .alias(property, fulfillingProperty, _, _, _):
				readLabels.insert(labelIndex(of: property.label))
				readLabels.insert(labelIndex(of: fulfillingProperty.label))
			case let .property(instantiable, property, _, _, _, _):
				readLabels.insert(labelIndex(of: property.label))
				for dependency in instantiable.dependencies {
					readLabels.insert(labelIndex(of: dependency.property.label))
				}
			case .root, .hole, .fill:
				break
			}
			for child in children {
				isClosed = isClosed && child.isClosed
				readLabels.formUnion(child.readLabels)
			}
			return SubtreeFacts(isClosed: isClosed, readLabels: readLabels)
		}

		/// Whether `generator`'s own node reads nothing but its place's walk state and the declarations around it: no seam
		/// or public mock call, no override of a value nothing fulfills, no cycle parameter or loop of builders, no
		/// `@Sendable` function, no payload or member call, and no actor. A subtree each node of which is closed is built
		/// alike wherever its walk state is alike, which a shared builder relies on too (`MockLowering+SharedBuilders.swift`).
		static func isClosed(atNode generator: ScopeGenerator) -> Bool {
			switch generator.scopeData {
			case .alias:
				true
			case let .property(instantiable, _, _, _, _, seamCall):
				seamCall == nil
					&& generator.publicMockCall == nil
					&& !generator.isUnavailableDependency
					&& generator.cycleParameters.isEmpty
					&& generator.reboundProperties.isEmpty
					&& !generator.buildsInSendableFunction
					&& generator.valuesBindingsBeforeBuilderFunction.isEmpty
					&& generator.memberCallsInsideBuilderFunction.isEmpty
					&& instantiable.declarationType != .actorType
			case .root, .hole, .fill:
				false
			}
		}

		private func labelIndex(of label: String) -> Int {
			if let index = labelIndices[label] {
				return index
			}
			let index = labelIndices.count
			labelIndices[label] = index
			return index
		}
	}
}

extension MockLowering.Walk {
	/// The key of the subtree of the built node at `childIndexPath`, whose start set the walk state its children are walked
	/// in, or `nil` where the subtree is not shared.
	func sharedSubtreeKey(of generator: ScopeGenerator, orderedChildren: [ScopeGenerator.OrderedChild], childrenScope: Set<Property>, ownLoopMembership: MockLowering.LoopMembership?) -> MockLowering.SubtreeKey? {
		guard let subtreeSharing,
		      subtreeSharing.generatorsOnSeveralPaths.contains(ObjectIdentifier(generator)),
		      !orderedChildren.isEmpty,
		      ownLoopMembership == nil,
		      sendableOverrideExtractor == nil,
		      !isInsideActorArgument,
		      !isBeneathRepeatedConfiguredAncestor,
		      !subtreeSharing.pathsHoldingInlinePlace.contains(childIndexPath)
		else { return nil }
		let facts = subtreeSharing.facts(of: generator)
		// No node beneath repeats a type around it, whose configuration and override path the node would read: a tree
		// builds a type beneath itself only through a cycle-closing node or a loop of builders, and a root that holds
		// either shares nothing (`SubtreeSharing.init(sharingBeneath:inlinePlacePaths:)`).
		guard facts.isClosed else { return nil }
		return MockLowering.SubtreeKey(
			generator: ObjectIdentifier(generator),
			children: orderedChildren.map { child in
				MockLowering.SubtreeKey.ChildContext(index: child.index, unavailableProperties: child.unavailableProperties, propertiesGeneratedLater: child.propertiesGeneratedLater)
			},
			overridePathReachable: overridePathReachable,
			isInsideSendableFunction: isInsideSendableFunction,
			renames: renames.filter { subtreeSharing.reads($0.key, in: facts) },
			lazilyInstantiatedNames: lazilyInstantiatedNames.filter { subtreeSharing.reads($0.key, in: facts) },
			bindingNamesPassedByName: enclosingBindingNamesPassedByName.filter { subtreeSharing.reads($0.key, in: facts) },
			scope: childrenScope.filter { subtreeSharing.reads($0.label, in: facts) },
		)
	}

	/// The paths of the walk's places in an order that records each place after the places beneath it and every place a
	/// later meeting of its subtree takes the records of before that meeting: depth first, each place after its children,
	/// siblings in walk order.
	func placePathsRecordingSharedSubtreesFirst() -> [[Int]] {
		var childPathsByParent = [[Int]: [[Int]]]()
		for path in placePathsInWalkOrder {
			childPathsByParent[Array(path.dropLast()), default: []].append(path)
		}
		var order = [[Int]]()
		order.reserveCapacity(placePathsInWalkOrder.count)
		var stack: [(path: [Int], childrenPushed: Bool)] = (childPathsByParent[[]] ?? []).reversed().map { ($0, false) }
		while let entry = stack.popLast() {
			if entry.childrenPushed {
				order.append(entry.path)
			} else {
				stack.append((entry.path, true))
				for child in (childPathsByParent[entry.path] ?? []).reversed() {
					stack.append((child, false))
				}
			}
		}
		return order
	}
}
