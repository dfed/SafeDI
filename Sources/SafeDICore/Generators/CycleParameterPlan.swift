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

/// What the search for the parameters of the builder functions lazy cycles close on reads of a scope's child
/// (`ScopeGenerator.receives`, `aliasRequirements`, `onlyIfAvailableUnwrappedReceivedProperties` and
/// `cycleParameterSearch`): a generator, as it reads while a tree is built, or a place of a `CycleParameterPlan`, which
/// runs the same search over what a tree's first pass built.
protocol CycleParameterSearchNode {
	var searchProperty: Property? { get }
	var searchReceivedProperties: Set<Property> { get }
	var searchRequiredReceivedProperties: Set<Property> { get }
	var searchRequiredAliasFulfillingProperties: Set<Property> { get }
	var searchOnlyIfAvailableAliasFulfillingProperty: Property? { get }
	var searchOnlyIfAvailableUnwrappedReceivedProperties: Set<Property> { get }
	var searchUnpassableCycleLabelsInTree: [UnpassableCycleLabel] { get }
	var searchBuiltInstantiable: Instantiable? { get }
	/// For a scope that closes a lazy cycle, the parameters of the function it refers to; for a scope a lazy cycle closes
	/// on, its own.
	var searchCycleParameters: [CycleParameter] { get }
	var searchClosesPropertyCycle: Bool { get }
	var searchClosedOnDeclaration: ScopeGenerator.BuiltDeclaration? { get }
	var searchChildren: [Self] { get }
	/// The node's identity: two nodes of one identity have the same subtree.
	var searchIdentity: ObjectIdentifier { get }
}

/// What the cycle parameter search reads of a scope that is the same in every pass of a tree: the type and what the scope
/// declares, forwards and is passed `nil` for. A generator keeps it only where `CycleParameterPlan` can read it.
struct CycleParameterSearchInputs: Sendable {
	let instantiable: Instantiable
	/// The scope's forwarded properties, with the instance of each that is lazily instantiated.
	let forwardedProperties: Set<Property>
	/// The properties an alias of the scope's type is bound against without being received.
	let aliasBindingDeclaredProperties: Set<Property>
	let receivesPassedNil: Set<Property>
	let seamCallRequiredThroughAliasProperties: Set<Property>
}

/// The cycle parameters a pass after a tree's first reads at each place, in place of what the pass before found, with the
/// seeds of the place's children by index. A place whose seed is `nil` reads the pass before's generator, as without a seed.
/// Places with equal generators of the first pass and seeds that find alike share one seed, so that the memo, which keys
/// a place by its seed, shares their generators.
///
/// Holds the parameters of the places beneath it that `CycleParameterPlan` settled, for one pass; nothing keeps it after.
final class CycleParameterSeed: Sendable {
	let foundCycleParameters: [CycleParameter]
	let children: [CycleParameterSeed?]

	init(foundCycleParameters: [CycleParameter], children: [CycleParameterSeed?]) {
		self.foundCycleParameters = foundCycleParameters
		self.children = children
	}

	/// The seed of the child at `index`, or `nil` where the child has none.
	func child(at index: Int) -> CycleParameterSeed? {
		children.indices.contains(index) ? children[index] : nil
	}
}

/// Settles the parameters of the builder functions lazy cycles close on over the generators a tree's first pass built.
///
/// A tree is built again while a scope a lazy cycle closes on finds other parameters than it was built with
/// (`ScopeRecord.createdTree`): each pass reads the parameters the pass before found, so each settles one more depth of
/// nested functions, and every pass builds the generators of every place a changed parameter reaches. The parameters
/// depend only on what the places receive and declare, which a later pass changes only through the parameters themselves:
/// a cycle-closing scope receives the parameters of the function it refers to, and a scope a cycle closes on declares its
/// own for the cycles nested in its function. So this runs the searches each later pass would run, over one place per
/// place of the first pass's tree, reading each pass's parameters from the round before, until a round finds what the
/// round before found: the parameters today's passes end on. The pass after reads them (`CycleParameterSeed`) and so is the
/// last, or finds other loops of builders or fill findings and takes the passes those need, as before.
///
/// A place whose subtree holds no cycle-closing scope finds no parameter and receives what the first pass found in every
/// pass, so only places whose subtree holds one (`ScopeGenerator.holdsCycleClosingScope`) are searched again.
///
/// Holds one place per such place of the tree while it settles, and nothing once `settledSeed(ofTreeRootedAt:)` returns.
enum CycleParameterPlan {
	/// Whether a tree's later passes read the parameters this plan settles. Test only: the construction memo oracle builds
	/// its reference tree without it, so that every test and fuzzer graph compares the two (`ConstructionMemoOracle`).
	@TaskLocal static var isEnabled = true

	/// The seed of the tree rooted at `root`, built by a first pass, or `nil` where every place reads the pass before's
	/// generator.
	static func settledSeed(ofTreeRootedAt root: ScopeGenerator) -> CycleParameterSeed? {
		guard let rootPlace = Place(planning: root) else { return nil }
		var searches = Searches()
		while settleOneRound(from: rootPlace, searches: &searches) {}
		return seeds(from: rootPlace)
	}

	/// What a search found at a place. A search's results are a function of its generator, the parameters it is passed and
	/// its children's results, so places that share all three share one result (`SearchKey`): a tree reaches one generator
	/// by many paths, and the places of those paths search once between them. Never changed once made, so a place's result
	/// stands for every result beneath it.
	private final class SearchResult {
		let foundCycleParameters: [CycleParameter]
		let receivedProperties: Set<Property>
		let requiredReceivedProperties: Set<Property>
		let requiredAliasFulfillingProperties: Set<Property>
		let onlyIfAvailableUnwrappedReceivedProperties: Set<Property>
		let unpassableCycleLabelsInTree: [UnpassableCycleLabel]
		let cycleClosingRedeclaredLabels: CycleClosingRedeclaredLabels

		init(
			foundCycleParameters: [CycleParameter],
			receivedProperties: Set<Property>,
			requiredReceivedProperties: Set<Property>,
			requiredAliasFulfillingProperties: Set<Property>,
			onlyIfAvailableUnwrappedReceivedProperties: Set<Property>,
			unpassableCycleLabelsInTree: [UnpassableCycleLabel],
			cycleClosingRedeclaredLabels: CycleClosingRedeclaredLabels,
		) {
			self.foundCycleParameters = foundCycleParameters
			self.receivedProperties = receivedProperties
			self.requiredReceivedProperties = requiredReceivedProperties
			self.requiredAliasFulfillingProperties = requiredAliasFulfillingProperties
			self.onlyIfAvailableUnwrappedReceivedProperties = onlyIfAvailableUnwrappedReceivedProperties
			self.unpassableCycleLabelsInTree = unpassableCycleLabelsInTree
			self.cycleClosingRedeclaredLabels = cycleClosingRedeclaredLabels
		}

		/// Whether the two hold the same results, counting maps of redeclared labels built of other layers as other results.
		func findsWhat(_ other: SearchResult) -> Bool {
			self === other || (
				foundCycleParameters == other.foundCycleParameters
					&& receivedProperties == other.receivedProperties
					&& requiredReceivedProperties == other.requiredReceivedProperties
					&& requiredAliasFulfillingProperties == other.requiredAliasFulfillingProperties
					&& onlyIfAvailableUnwrappedReceivedProperties == other.onlyIfAvailableUnwrappedReceivedProperties
					&& unpassableCycleLabelsInTree == other.unpassableCycleLabelsInTree
					&& cycleClosingRedeclaredLabels.holdsSameLayers(as: other.cycleClosingRedeclaredLabels)
			)
		}
	}

	/// What a search reads: the generator, the parameters the place is passed, and each child, a generator of the first
	/// pass or the result a place found. A result is made once per key and never changed, so its identity stands for the
	/// parameters and results beneath it.
	private struct SearchKey: Hashable {
		let generator: ObjectIdentifier
		/// The parameters, by `Searches.identifier(of:from:)`.
		let cycleParameters: Int
		let children: [ObjectIdentifier]
	}

	/// The results of one tree's searches, by what each read, while the tree settles.
	private struct Searches {
		var resultsByKey = [SearchKey: SearchResult]()
		/// Each distinct list of parameters a place was passed, by its identifier, the position here; none is first.
		private(set) var distinctCycleParameters: [[CycleParameter]] = [[]]
		private var cycleParameterIdentifiersBySource = [CycleParameterSource.none: 0]

		/// The identifier of `cycleParameters`, which `source` found: one per distinct list, so that places passed equal
		/// parameters from different sources share their searches, while a key hashes an integer rather than the
		/// parameters, each list being compared with the others once, where its source is first met.
		mutating func identifier(of cycleParameters: [CycleParameter], from source: CycleParameterSource) -> Int {
			if let identifier = cycleParameterIdentifiersBySource[source] {
				return identifier
			}
			let identifier = distinctCycleParameters.firstIndex(of: cycleParameters) ?? distinctCycleParameters.count
			if identifier == distinctCycleParameters.count {
				distinctCycleParameters.append(cycleParameters)
			}
			cycleParameterIdentifiersBySource[source] = identifier
			return identifier
		}
	}

	/// What a place's parameters are: none, or those a generator or a search found, whose identity stands for them.
	private enum CycleParameterSource: Hashable {
		case none
		case foundByGenerator(ObjectIdentifier)
		case foundBySearch(ObjectIdentifier)
	}

	/// A place of the tree whose subtree holds a cycle-closing scope, with what the search found there in the last round.
	private final class Place {
		let generator: ScopeGenerator
		let inputs: CycleParameterSearchInputs
		var children = [Node]()
		/// For a cycle-closing scope, the parameters of the function it refers to, as the round's pass passes them; for a
		/// scope a cycle closes on, its own.
		var cycleParameters: [CycleParameter]
		/// What `cycleParameters` are, for the search's key.
		var cycleParameterSource = CycleParameterSource.none
		/// What the last search here found, or, before the first, a result that holds nothing, which nothing reads: every
		/// place searches in the first round, each after its children.
		var result: SearchResult
		/// The parameters the last search here found, or, before the first, those the generator found.
		var foundCycleParameters: [CycleParameter] {
			hasSearched ? result.foundCycleParameters : generator.foundCycleParameters
		}

		/// What `foundCycleParameters` are.
		var foundCycleParameterSource: CycleParameterSource {
			hasSearched ? .foundBySearch(ObjectIdentifier(result)) : .foundByGenerator(ObjectIdentifier(generator))
		}

		/// Whether the round must run the search here again: its parameters changed this round, or it has not searched yet.
		/// A place whose parameters and children's results are those of its last search finds what it found then. The
		/// generator does not keep its map of redeclared labels, so no place starts from its generator's results.
		var needsSearch = true
		/// Whether the place has searched, so that `result` is what a search found.
		var hasSearched = false
		/// Whether the last search here found other results than the search before it, so the place above searches again.
		var searchFoundOtherResults = false

		/// The place of `root`'s tree, built with its places beneath, or `nil` where its subtree holds no cycle-closing scope.
		convenience init?(planning root: ScopeGenerator) {
			guard let inputs = root.cycleParameterSearchInputs else { return nil }
			let resultBeforeFirstSearch = SearchResult(
				foundCycleParameters: [],
				receivedProperties: [],
				requiredReceivedProperties: [],
				requiredAliasFulfillingProperties: [],
				onlyIfAvailableUnwrappedReceivedProperties: [],
				unpassableCycleLabelsInTree: [],
				cycleClosingRedeclaredLabels: .init(),
			)
			self.init(generator: root, inputs: inputs, result: resultBeforeFirstSearch)
			// Built with an explicit stack: a tree can be as deep as its module has types.
			var placesToFill = [self]
			while let place = placesToFill.popLast() {
				place.children = place.generator.children.map { child in
					guard let inputs = child.cycleParameterSearchInputs else { return .generator(child) }
					let childPlace = Place(generator: child, inputs: inputs, result: resultBeforeFirstSearch)
					placesToFill.append(childPlace)
					return .place(childPlace)
				}
			}
		}

		private init(generator: ScopeGenerator, inputs: CycleParameterSearchInputs, result: SearchResult) {
			self.generator = generator
			self.inputs = inputs
			self.result = result
			cycleParameters = generator.cycleParameters
		}
	}

	/// A child of a place: a place of its own, or a generator of the first pass whose subtree holds no cycle-closing scope,
	/// which every pass builds alike.
	private enum Node: CycleParameterSearchNode {
		case generator(ScopeGenerator)
		case place(Place)

		var searchProperty: Property? {
			switch self {
			case let .generator(generator): generator.searchProperty
			case let .place(place): place.generator.searchProperty
			}
		}

		var searchReceivedProperties: Set<Property> {
			switch self {
			case let .generator(generator): generator.searchReceivedProperties
			case let .place(place): place.result.receivedProperties
			}
		}

		var searchRequiredReceivedProperties: Set<Property> {
			switch self {
			case let .generator(generator): generator.searchRequiredReceivedProperties
			case let .place(place): place.result.requiredReceivedProperties
			}
		}

		var searchRequiredAliasFulfillingProperties: Set<Property> {
			switch self {
			case let .generator(generator): generator.searchRequiredAliasFulfillingProperties
			case let .place(place): place.result.requiredAliasFulfillingProperties
			}
		}

		var searchOnlyIfAvailableAliasFulfillingProperty: Property? {
			switch self {
			case let .generator(generator): generator.searchOnlyIfAvailableAliasFulfillingProperty
			case let .place(place): place.generator.searchOnlyIfAvailableAliasFulfillingProperty
			}
		}

		var searchOnlyIfAvailableUnwrappedReceivedProperties: Set<Property> {
			switch self {
			case let .generator(generator): generator.searchOnlyIfAvailableUnwrappedReceivedProperties
			case let .place(place): place.result.onlyIfAvailableUnwrappedReceivedProperties
			}
		}

		var searchUnpassableCycleLabelsInTree: [UnpassableCycleLabel] {
			switch self {
			case let .generator(generator): generator.searchUnpassableCycleLabelsInTree
			case let .place(place): place.result.unpassableCycleLabelsInTree
			}
		}

		var searchBuiltInstantiable: Instantiable? {
			switch self {
			case let .generator(generator): generator.searchBuiltInstantiable
			case let .place(place): place.generator.searchBuiltInstantiable
			}
		}

		var searchCycleParameters: [CycleParameter] {
			switch self {
			case let .generator(generator): generator.searchCycleParameters
			case let .place(place): place.cycleParameters
			}
		}

		var searchClosesPropertyCycle: Bool {
			switch self {
			case let .generator(generator): generator.searchClosesPropertyCycle
			case let .place(place): place.generator.searchClosesPropertyCycle
			}
		}

		var searchClosedOnDeclaration: ScopeGenerator.BuiltDeclaration? {
			switch self {
			case let .generator(generator): generator.searchClosedOnDeclaration
			case let .place(place): place.generator.searchClosedOnDeclaration
			}
		}

		var searchChildren: [Node] {
			switch self {
			case let .generator(generator): generator.searchChildren.map { .generator($0) }
			case let .place(place): place.children
			}
		}

		var searchIdentity: ObjectIdentifier {
			switch self {
			case let .generator(generator): ObjectIdentifier(generator)
			case let .place(place): ObjectIdentifier(place)
			}
		}
	}

	/// Runs the search each place's build runs in the pass after the round before, reading the parameters the round before
	/// found as that pass reads those its pass before found, and returns whether a place found other results. A place whose
	/// parameters and children's results did not change this round keeps what it found, without searching again.
	private static func settleOneRound(from rootPlace: Place, searches: inout Searches) -> Bool {
		enum Step {
			/// Sets what the place is passed: the parameters the round before found of the functions enclosing it, by the
			/// declaration each is built for, as `ScopeGeneratorUnderConstruction` reads them.
			case enter(Place, cycleParameterContexts: [ScopeGenerator.BuiltDeclaration: (parameters: [CycleParameter], source: CycleParameterSource)])
			case exit(Place)
		}
		var foundOtherResults = false
		var steps = [Step.enter(rootPlace, cycleParameterContexts: [:])]
		while let step = steps.popLast() {
			switch step {
			case let .enter(place, cycleParameterContexts):
				let generator = place.generator
				let previousCycleParameters = place.cycleParameters
				var childCycleParameterContexts = cycleParameterContexts
				if generator.closesPropertyCycle {
					let context = generator.closedOnDeclaration.flatMap { cycleParameterContexts[$0] }
					place.cycleParameters = context?.parameters ?? []
					place.cycleParameterSource = context?.source ?? .none
					childCycleParameterContexts = [:]
				} else if let declaration = generator.declaration {
					place.cycleParameters = place.foundCycleParameters
					place.cycleParameterSource = place.foundCycleParameterSource
					if !place.foundCycleParameters.isEmpty {
						childCycleParameterContexts[declaration] = (place.foundCycleParameters, place.foundCycleParameterSource)
					}
				} else {
					place.cycleParameters = []
					place.cycleParameterSource = .none
				}
				if place.cycleParameters != previousCycleParameters {
					place.needsSearch = true
				}
				steps.append(.exit(place))
				for case let .place(childPlace) in place.children.reversed() {
					steps.append(.enter(childPlace, cycleParameterContexts: childCycleParameterContexts))
				}
			case let .exit(place):
				var childFoundOtherResults = false
				for case let .place(childPlace) in place.children where childPlace.searchFoundOtherResults {
					childFoundOtherResults = true
				}
				guard place.needsSearch || childFoundOtherResults else {
					place.searchFoundOtherResults = false
					continue
				}
				place.needsSearch = false
				place.searchFoundOtherResults = search(at: place, searches: &searches)
				if place.searchFoundOtherResults {
					foundOtherResults = true
				}
			}
		}
		return foundOtherResults
	}

	/// Runs at `place` the searches `ScopeGenerator`'s initializer runs, over its children's results of this round, or takes
	/// the result of a place that read the same (`SearchKey`), and keeps it; returns whether it differs from what the place
	/// held.
	private static func search(at place: Place, searches: inout Searches) -> Bool {
		let generator = place.generator
		let key = SearchKey(
			generator: ObjectIdentifier(generator),
			cycleParameters: searches.identifier(of: place.cycleParameters, from: place.cycleParameterSource),
			children: place.children.map { child in
				switch child {
				case let .generator(childGenerator): ObjectIdentifier(childGenerator)
				case let .place(childPlace): ObjectIdentifier(childPlace.result)
				}
			},
		)
		let result: SearchResult
		if let sharedResult = searches.resultsByKey[key] {
			result = sharedResult
		} else {
			result = searchResult(at: place)
			searches.resultsByKey[key] = result
		}
		let foundOtherResults = !place.hasSearched || !result.findsWhat(place.result)
		place.hasSearched = true
		place.result = result
		return foundOtherResults
	}

	/// What the searches `ScopeGenerator`'s initializer runs find at `place`, over its children's results of this round.
	private static func searchResult(at place: Place) -> SearchResult {
		let generator = place.generator
		let inputs = place.inputs
		let isPropertyCycle = generator.closesPropertyCycle
		let closedOnFunctionParameters = isPropertyCycle ? place.cycleParameters : []
		let receives = ScopeGenerator.receives(
			children: place.children,
			ownDependencies: inputs.instantiable.dependencies,
			receivesPassedNil: inputs.receivesPassedNil,
			propertiesToDeclare: generator.propertiesToDeclare,
			forwardedProperties: inputs.forwardedProperties,
			aliasBindingDeclaredProperties: inputs.aliasBindingDeclaredProperties,
			cycleParameters: closedOnFunctionParameters,
		)
		let aliasRequirements = ScopeGenerator.aliasRequirements(
			children: place.children,
			propertiesToDeclare: generator.propertiesToDeclare,
			forwardedProperties: inputs.forwardedProperties,
			cycleParameters: closedOnFunctionParameters,
			seamCallRequiredThroughAliasProperties: inputs.seamCallRequiredThroughAliasProperties,
		)
		let onlyIfAvailableUnwrappedReceivedProperties = ScopeGenerator.onlyIfAvailableUnwrappedReceivedProperties(
			children: place.children,
			ownDependencies: inputs.instantiable.dependencies,
			receivesPassedNil: inputs.receivesPassedNil,
			propertiesToDeclare: generator.propertiesToDeclare,
			forwardedProperties: inputs.forwardedProperties,
			aliasBindingDeclaredProperties: inputs.aliasBindingDeclaredProperties,
			cycleParameters: closedOnFunctionParameters,
			requiredReceivedProperties: receives.requiredReceivedProperties,
		)
		// The children's maps, merged in their order, as `ScopeGeneratorUnderConstruction` merges them. A generator child's
		// subtree closes no cycle, so its map is empty.
		var childrenCycleClosingRedeclaredLabels = CycleClosingRedeclaredLabels()
		for case let .place(childPlace) in place.children {
			childrenCycleClosingRedeclaredLabels.merge(childPlace.result.cycleClosingRedeclaredLabels)
		}
		let cycleParameterSearch = ScopeGenerator.cycleParameterSearch(
			instantiable: inputs.instantiable,
			property: generator.property,
			declaration: generator.declaration,
			closedOnDeclaration: generator.closedOnDeclaration,
			isPropertyCycle: isPropertyCycle,
			childrenTakePartInCycle: generator.searchChildrenTakePartInCycle,
			childrenCycleClosingRedeclaredLabels: childrenCycleClosingRedeclaredLabels,
			children: place.children,
			propertiesToDeclare: generator.propertiesToDeclare,
			forwardedProperties: inputs.forwardedProperties,
			cycleParameters: place.cycleParameters,
			receivedProperties: receives.receivedProperties,
			requiredReceivedProperties: receives.requiredReceivedProperties,
			requiredAliasFulfillingProperties: aliasRequirements.requiredAliasFulfillingProperties,
			onlyIfAvailableUnwrappedReceivedProperties: onlyIfAvailableUnwrappedReceivedProperties,
		)
		return SearchResult(
			foundCycleParameters: cycleParameterSearch.foundCycleParameters,
			receivedProperties: receives.receivedProperties,
			requiredReceivedProperties: receives.requiredReceivedProperties,
			requiredAliasFulfillingProperties: aliasRequirements.requiredAliasFulfillingProperties,
			onlyIfAvailableUnwrappedReceivedProperties: onlyIfAvailableUnwrappedReceivedProperties,
			unpassableCycleLabelsInTree: cycleParameterSearch.unpassableCycleLabelsInTree,
			cycleClosingRedeclaredLabels: cycleParameterSearch.cycleClosingRedeclaredLabels,
		)
	}

	/// The seed of each place, from the leaves up, one per generator, children's seeds and parameters found alike. A place
	/// whose parameters, and whose children's, are those its generator found keeps none: the pass after reads its generator.
	private static func seeds(from rootPlace: Place) -> CycleParameterSeed? {
		struct SeedKey: Hashable {
			let generator: ObjectIdentifier
			let children: [ObjectIdentifier?]
		}
		var seedsByKey = [SeedKey: [CycleParameterSeed]]()
		var seedByPlace = [ObjectIdentifier: CycleParameterSeed]()
		// Post-order, with an explicit stack: each place is visited once its children are.
		var steps: [(place: Place, childrenVisited: Bool)] = [(rootPlace, false)]
		while let (place, childrenVisited) = steps.popLast() {
			guard childrenVisited else {
				steps.append((place, true))
				for case let .place(childPlace) in place.children.reversed() {
					steps.append((childPlace, false))
				}
				continue
			}
			let childSeeds = place.children.map { child -> CycleParameterSeed? in
				guard case let .place(childPlace) = child else { return nil }
				return seedByPlace[ObjectIdentifier(childPlace)]
			}
			let foundAlikeByGenerator = ConstructionLog.Answer.cycleParameterContext(place.foundCycleParameters)
				.isAlike(.cycleParameterContext(place.generator.foundCycleParameters))
			guard !foundAlikeByGenerator || childSeeds.contains(where: { $0 != nil }) else { continue }
			let key = SeedKey(generator: ObjectIdentifier(place.generator), children: childSeeds.map { $0.map(ObjectIdentifier.init) })
			let seed: CycleParameterSeed
			if let existingSeed = seedsByKey[key]?.first(where: {
				ConstructionLog.Answer.cycleParameterContext($0.foundCycleParameters).isAlike(.cycleParameterContext(place.foundCycleParameters))
			}) {
				seed = existingSeed
			} else {
				seed = CycleParameterSeed(foundCycleParameters: place.foundCycleParameters, children: childSeeds)
				seedsByKey[key, default: []].append(seed)
			}
			seedByPlace[ObjectIdentifier(place)] = seed
		}
		return seedByPlace[ObjectIdentifier(rootPlace)]
	}
}
