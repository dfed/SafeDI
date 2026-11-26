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
/// the same records but for what each place's own call hands, which `SharedRecordKey` already lets differ. The walk
/// descends into such a subtree once: at a later meeting of its key it takes the first meeting's tree nodes and child
/// records, and writes no text for it. One scan still runs at every meeting, before the key is looked up: a receive named
/// apart asks whether a receive beneath reads its label by name (`MockLowering.receiveReadsLabelByName`), which visits
/// each node beneath the meeting once per context it is built in.
///
/// What a subtree reads of the walk state around it is its key (`SubtreeKey`), each part restricted to the labels its
/// readers read (`SubtreeFacts`). A subtree is shared only where nothing in it reads state the key does not hold
/// (`isClosed`): an unfulfilled receive only if available, a call of another module's seam or public mock, a hole or a
/// fill, a `@Sendable` builder function, an actor, or a payload or member call bound by path keep the walk's per-path
/// descent. A root shares nothing where its tree holds a cycle-closing scope anywhere, a loop of builders, a type built
/// both with its hand-written mock and with its initializer, a place of another module's public mock built inline, or a
/// property of its own level named apart from its label (`SubtreeSharing.init(sharingBeneath:)`,
/// `MockLowering.Walk.sharesSubtrees(of:)`).
///
/// The walk that shares writes no text, as every walk of a root the type key lays out writes none. A root whose layout
/// falls back is walked again from the copy of the walk taken before its children (`lowerMockRootWithTree(of:context:)`),
/// which shares nothing, since the copy predates the sharing, and writes every statement.
extension MockLowering {
	/// Whether an internal mock's walk shares work a repeated subtree would repeat. The comparison
	/// `sharingComparisonObserver` reports turns it off to walk every path; the tool never does.
	@TaskLocal static var sharesSubtrees = true

	/// Called, where set, with what a traversal that shares repeated subtrees found and what the same traversal finds with
	/// the switch off, which walks every path: each internal mock root whose walk took a subtree met before, its mock and
	/// configurations (`lowerMockRootWithTree(of:context:)`). Set by the tests and the graph fuzzer, which fail on any
	/// difference; never by the tool.
	@TaskLocal public static var sharingComparisonObserver: (@Sendable (_ subject: String, _ shared: String, _ unshared: String) -> Void)?

	/// Called, where set, for each internal mock root the type key lays out, with how many meetings its walk took a subtree
	/// met before and how its layout ended. Set by the tests and the graph fuzzer, which read the counts; never by the tool.
	@TaskLocal public static var subtreeSharingObserver: (@Sendable (SubtreeSharingOutcome) -> Void)?

	/// What `subtreeSharingObserver` is told of one root.
	public struct SubtreeSharingOutcome: Equatable, Sendable {
		public let mockedType: String
		public let sharedMeetings: Int
		/// `laidOut`, or why the layout of the walk that shared fell back (`typeKeyLayoutObserver`).
		public let layoutOutcome: String
		/// How many generators' subtree facts the walk held, and the words of label bits they held, which grow with the
		/// generators the root's tree reaches on several paths and the labels their readers read.
		public let heldFacts: HeldFacts

		public struct HeldFacts: Equatable, Sendable {
			public let generators: Int
			public let labelWords: Int
		}
	}

	/// What of a mock root's result the observer compares: its code, and of its configuration records what the module's
	/// configurations and its one-way check read (`configurationCode`, `configurationsBuiltTwoWays`,
	/// `recordsReadingConfiguration`): for each concrete type and construction, the first record in walk order not beneath a
	/// cycle edge, with its struct, its construction's requirements and the modules its fulfillers name. No record is
	/// beneath a repeated ancestor: a root that shares holds no closer and builds no type two ways
	/// (`SubtreeSharing.init(sharingBeneath:)`). A shared subtree records no configuration again, and the walk order of the
	/// records after it moves, which neither reads. Its `publicConstruction` is never set: a public mock shares nothing.
	static func sharingComparison(of result: Result, sendableConfigurationTypeNames: Set<String>) -> String {
		var text = result.code
		var seen = Set<String>()
		let records = result.configurations
			.compactMap { record in record.oneWayConstruction.map { (record: record, construction: $0) } }
			.filter { !$0.construction.isBeneathCycleEdge }
			.sorted { $0.construction.walkOrder < $1.construction.walkOrder }
		for (record, oneWay) in records {
			let key = "\(record.concreteType.asSource) \(record.usesMockInitializer)"
			guard seen.insert(key).inserted else { continue }
			text += "\n// \(key)\n\(record.configurationStruct(amongConfigurationsTypedSendable: sendableConfigurationTypeNames))"
			text += "\n// \(oneWay.property) \(oneWay.parentConcreteType ?? "") \(oneWay.customMockName ?? "") \(oneWay.isExtensionBased) \(oneWay.requirements)"
			text += "\n// fulfillers: \(record.fulfillers.map { String(describing: $0) }.sorted())"
		}
		return text
	}

	/// What the walk knows of a generator's subtree, worked out from the generators beneath it up, for the generators the
	/// root's tree reaches on several paths.
	struct SubtreeFacts {
		/// Whether nothing in the subtree, its own node included, reads walk state its key does not hold. A closer and a loop
		/// of builders read such state too, and keep their root from sharing at all (`SubtreeSharing.init(sharingBeneath:)`).
		let isClosed: Bool
		/// The labels an alias of the subtree fulfills from, the only labels the walk reads the declarations in scope by
		/// (`aliasNode`'s `scope.contains`), as indices into the root's labels (`SubtreeSharing.labelIndices`).
		let aliasFulfillingLabels: LabelSet
		/// The labels a node of the subtree receives, or an alias renames or fulfills from, which bound what it reads of the
		/// names a receive is handed and the wrappers `mock()` binds (`renames`, `lazilyInstantiatedNames`).
		let receivedLabels: LabelSet
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
	/// subtree's readers read. Every other part of that state is either the same wherever the generator is met, or keeps the
	/// subtree from being shared (`Walk.sharedSubtreeKey(of:…)`):
	/// - `overridePathReachable` is true wherever a key is formed, which requires it.
	/// - `isInsideSendableFunction` is false: every `@Sendable` builder function above holds an override extractor, which
	///   refuses a key.
	/// - The bindings a receive beneath is passed by name (`enclosingBindingNamesPassedByName`) are read only where a node
	///   of the subtree renames a receive apart, which reads a flat parameter or override the key's `renames` hold.
	/// - A child's index and the properties it is built without follow from the generator and the properties generated
	///   after it (`ScopeGenerator.orderedChildren(propertiesGeneratedLater:)`).
	struct SubtreeKey: Hashable {
		let generator: ObjectIdentifier
		/// The properties each child, in generation order, is built before
		/// (`SafeDIToolMockSubtreeSharingTests`' `mock_sharesNothing_whenChildrenAreBuiltBeforeOtherSiblings`).
		let childrenPropertiesGeneratedLater: [Set<Property>]
		/// The names a receive is handed in place of its label, for the labels the subtree receives
		/// (`mock_sharesNothing_whenRepeatedSubtreeReceivesRenamedParameter`).
		let renames: [String: [TypeDescription: String]]
		/// The wrappers `mock()` binds, for the labels the subtree receives. The construction memo builds the places a
		/// declaration of such a wrapper tells apart with generators of their own (its key's
		/// `lazilyInstantiatedInstanceProperties`), so no graph tried reaches two meetings of one generator that differ here
		/// (`mock_sharesNothing_whenRepeatedSubtreeReceivesWrapperBoundApart`); the part keeps the key from relying on that.
		let lazilyInstantiatedNames: [String: [TypeDescription: String]]
		/// The declarations in scope of the children, of the labels an alias of the subtree fulfills from. As for
		/// `lazilyInstantiatedNames`, the construction memo tells apart the places tried whose aliases read different
		/// declarations (`mock_sharesNothing_whenRepeatedSubtreeAliasesDeclarationOnePathHolds`); the part keeps the key from
		/// relying on that.
		let scope: Set<Property>
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
	/// that share are lowered again with `sharesSubtrees` off and compared (`sharingComparisonObserver`, which
	/// `executeSafeDIToolTest` sets).
	///
	/// Memory: one identifier per generator the root's tree reaches on several paths, with the facts of those the walk
	/// forms a key at (two bits per label of the root's tree), the tree nodes and child records of each subtree met first, and
	/// the path each later meeting reads its records from, held by the root's walk until the root's places are laid out.
	final class SubtreeSharing {
		/// The sharing of the walk of `root`'s tree, or `nil` where it can share nothing: a node in the tree closes a cycle or
		/// a level holds a loop of builders, whose records read every path's place (`nearestConfigurations`,
		/// `loopMemberConfigurations`); the tree builds one concrete type both with its hand-written mock and with its initializer,
		/// whose configuration the first node of each construction decides (`configurationsBuiltTwoWays`), a type built
		/// beneath itself among them; or no generator is reached on more than one path.
		init?(sharingBeneath root: ScopeGenerator) {
			guard !root.holdsCycleClosingScope else { return nil }
			// The generators of the tree, each after every generator that builds it, from a depth-first walk on a stack of
			// its own, since a mock tree can be as deep as the module has types.
			var postorder = [ScopeGenerator]()
			var visited = Set<ObjectIdentifier>()
			var usesMockInitializerByConcreteType = [String: Bool]()
			var stack: [(generator: ScopeGenerator, childrenPushed: Bool)] = [(root, false)]
			while let entry = stack.popLast() {
				let generator = entry.generator
				if entry.childrenPushed {
					postorder.append(generator)
					continue
				}
				guard visited.insert(ObjectIdentifier(generator)).inserted else { continue }
				guard generator.receivedBuilderLoops.loopByChildIndex.isEmpty else { return nil }
				if case let .property(instantiable, property, _, _, _, _) = generator.scopeData {
					let concreteType = instantiable.concreteInstantiable.asSource
					let usesMockInitializer = instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType)
					guard usesMockInitializerByConcreteType.updateValue(usesMockInitializer, forKey: concreteType).map({ $0 == usesMockInitializer }) ?? true else { return nil }
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
			.init(generators: factsByGenerator.count, labelWords: factsByGenerator.values.reduce(0) { $0 + $1.aliasFulfillingLabels.wordCount + $1.receivedLabels.wordCount })
		}

		/// Whether `label` is among `labels`.
		func holds(_ label: String, in labels: LabelSet) -> Bool {
			labelIndices[label].map(labels.contains) ?? false
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
			var isClosed = true
			var aliasFulfillingLabels = LabelSet()
			var receivedLabels = LabelSet()
			switch generator.scopeData {
			case let .alias(property, fulfillingProperty, _, _, _):
				aliasFulfillingLabels.insert(labelIndex(of: fulfillingProperty.label))
				receivedLabels.insert(labelIndex(of: property.label))
				receivedLabels.insert(labelIndex(of: fulfillingProperty.label))
			case let .property(instantiable, _, _, _, _, seamCall):
				// A cycle parameter and a wrapper made again exist only beneath a closer or a loop of builders, whose root
				// shares nothing.
				isClosed = seamCall == nil
					&& generator.publicMockCall == nil
					&& !generator.isUnavailableDependency
					&& !generator.buildsInSendableFunction
					&& generator.valuesBindingsBeforeBuilderFunction.isEmpty
					&& generator.memberCallsInsideBuilderFunction.isEmpty
					&& instantiable.declarationType != .actorType
				for dependency in instantiable.dependencies where dependency.source.isReceived {
					receivedLabels.insert(labelIndex(of: dependency.property.label))
				}
			case .root, .hole, .fill:
				// No test reaches this arm. The root is never beneath a generator on several paths; a hole is only in a public
				// mock's tree, which shares nothing (`Walk.sharesSubtrees(of:)`); and a fill is beneath the call of another
				// module's public mock that passes it, which one tree holds at most once (`ConstructionMemo.reuse(of:in:
				// besideCallGenerators:drawing:)` refuses an entry holding a call generator the tree holds), so no generator
				// above a fill is on several paths. A mock builds another module's seam inline, with no call.
				isClosed = false
			}
			for child in children {
				isClosed = isClosed && child.isClosed
				aliasFulfillingLabels.formUnion(child.aliasFulfillingLabels)
				receivedLabels.formUnion(child.receivedLabels)
			}
			return SubtreeFacts(isClosed: isClosed, aliasFulfillingLabels: aliasFulfillingLabels, receivedLabels: receivedLabels)
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
	///
	/// The guards the walk's state needs no more of: a node's own loop membership, a repeated configured ancestor and a
	/// cycle edge arise only beneath a closer or a loop of builders, whose root shares nothing; an actor's argument starts
	/// an override extractor, which refuses a key; and a root with a place of another module's public mock built inline
	/// shares nothing (`MockLowering.Walk.sharesSubtrees(of:)`).
	func sharedSubtreeKey(of generator: ScopeGenerator, orderedChildren: [ScopeGenerator.OrderedChild], childrenScope: Set<Property>) -> MockLowering.SubtreeKey? {
		guard let subtreeSharing,
		      subtreeSharing.generatorsOnSeveralPaths.contains(ObjectIdentifier(generator)),
		      !orderedChildren.isEmpty,
		      sendableOverrideExtractor == nil,
		      overridePathReachable
		else { return nil }
		let facts = subtreeSharing.facts(of: generator)
		// No node beneath repeats a type around it, whose configuration and override path the node would read: a tree
		// builds a type beneath itself only through a closer or a loop of builders, or built two ways, and a root that holds
		// any of these shares nothing (`SubtreeSharing.init(sharingBeneath:)`).
		guard facts.isClosed else { return nil }
		return MockLowering.SubtreeKey(
			generator: ObjectIdentifier(generator),
			childrenPropertiesGeneratedLater: orderedChildren.map(\.propertiesGeneratedLater),
			renames: renames.filter { subtreeSharing.holds($0.key, in: facts.receivedLabels) },
			lazilyInstantiatedNames: lazilyInstantiatedNames.filter { subtreeSharing.holds($0.key, in: facts.receivedLabels) },
			scope: childrenScope.filter { subtreeSharing.holds($0.label, in: facts.aliasFulfillingLabels) },
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

extension MockLowering.Walk {
	/// Whether an internal mock root's walk can share subtrees, decided before the walk from what would make its layout fall
	/// back: a place of another module's public mock built inline outside every fill (each is recorded as an inline place,
	/// `filledCallBuilders.holeBuildersByInlinePlace`, which the type key does not lay out), or a property node of the root's
	/// level bound under a name apart from its label (the walk's `pathsNamedApart`, which arises only at the root's level,
	/// where `mock()`'s parameters and promoted siblings can share a label). A root that holds either lays out as before.
	///
	/// A public mock's root shares nothing: its places' records read their overrides by the path from the root, since
	/// `relateConfiguration(ofBuiltPlaceAt:of:)` relates only an internal mock's to the place's own configuration, so a later
	/// meeting would take the first meeting's path, another place's override.
	func sharesSubtrees(of orderedChildren: [ScopeGenerator.OrderedChild]) -> Bool {
		guard !buildsPublicMock, filledCallBuilders.holeBuildersByInlinePlace.isEmpty else { return false }
		let bindingNames = rootLevelBindingNames(of: orderedChildren.map(\.generator))
		return !zip(orderedChildren, bindingNames).contains { child, bindingName in
			guard let bindingName, case let .property(_, property, _, _, _, _) = child.generator.scopeData else { return false }
			return bindingName != property.label
		}
	}
}
