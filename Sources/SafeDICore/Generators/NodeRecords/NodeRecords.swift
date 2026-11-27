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

/// Why a world's records are not made from its per-type facts at this stage: the first node, in declaration order, that is
/// of a kind a later stage adds. A refusal is of the whole world, which keeps the tree's path.
enum NodeRecordRefusal: String, Error, CaseIterable {
	/// The node is built by anything but its type's initializer or `instantiate()`: a seam's or a public mock's call, a
	/// hand-written mock, a construction function or a fill.
	case construction
	/// A mock root's node takes a parameter with a default value, which a mock holds in the type's configuration, or its
	/// type has a hand-written mock, whose defaults that configuration takes too.
	case mockDefaultValuedParameter
	/// A mock root's node is an actor, whose arguments a mock sends it.
	case mockActor
	/// A mock root's node whose override is not its parent's field under the node's own label: two children of one node
	/// share a label, which a mock root names apart.
	case mockOverrideNotParentField
	/// A mock root binds a value that is no node of its world before its tree, or names one apart: a parameter of
	/// `mock()`, an override of a value its tree receives only if available, a builder, a wrapper around an instance.
	case mockRootBindsOtherThanNodes
	/// The node is built in a `@Sendable` function of its own: a `SendableInstantiator`, erased or not, or a
	/// `SendableLazilyInstantiated`.
	case sendable
	/// The node is built as an `ErasedInstantiator`, or as a constant erased to its property's type.
	case erased
	/// The node's type declares a rename, a hole, or an instantiated dependency its scope does not build.
	case renameOrHole
	/// The node's call passes fills.
	case fill
	/// The node is on a cycle.
	case cycle
	/// The node is built as a `LazilyInstantiated`, or its scope declares or forwards one.
	case lazy
	/// The node's type receives a property only if available.
	case onlyIfAvailable
	/// The node stands for an unavailable dependency, or a seam built inline.
	case unavailableOrInlineSeam
	/// The node's type has no initializer to build it with.
	case noInitializer
	/// Two of a node's children wait on each other, or a child's tree receives the child's own property: a loop of builders.
	case builderLoop
	/// A node has more than one variant, so its record would not be a function of the node alone.
	case nodeHasSeveralVariants
	/// The engine could not lay the root out from the records.
	case notLaidOut
}

/// What a world's records read of a node beside the frozen interface (`TypeFactsWorld`): the scope it builds and the
/// property it builds as, from which a node's construction facts come until the table lane's columns hold them.
protocol NodeRecordSources: TypeFactsWorld {
	func scope(of declaration: DeclarationID) -> ConstructionScope
	/// The property the declaration is built as, `nil` for the root.
	func property(of declaration: DeclarationID) -> Property?
	/// Whether the world is a mock root's, each of whose nodes reads its override.
	var isMockWorld: Bool { get }
}

extension TypeFactsGraph: NodeRecordSources {
	func scope(of declaration: DeclarationID) -> ConstructionScope {
		graph.nodes[Int(declaration)].scope
	}

	func property(of declaration: DeclarationID) -> Property? {
		graph.nodes[Int(declaration)].property
	}
}

/// The records of one world's places, made from its per-type facts (`TypeFactsWorld`) with no `ScopeGenerator`: one
/// `BuiltPlaceRecord` per variant, and the root's body as the places it builds, in order. A variant's place is made once
/// and shared by every call of it, so the engine reads it once per view (`TypeKeyLayout.read(_:)`).
///
/// Stage 1 makes records only for a world each of whose nodes is a constant or an `Instantiator`, built by its type's
/// initializer, off every cycle, with one variant; any other world is refused with the first kind it holds.
///
/// One variant per node is enough here because a stage-1 record reads no answer: each `PlaceRead.source` is the label
/// `createInitializerArguments` names, and the engine resolves it per view. That holds only while both key projections
/// are inert: no receive only if available, and no cycle, so nothing is still being built where it is read. A node that
/// receives a property only if available (`receivesOnlyIfAvailable`) reads what each call of its variant finds
/// (`OnlyIfAvailableAnswers`, from the calls and `TypeFactsEdge.buildPosition`, since the world's answers do not model
/// sibling order), never a variant's keys, and a world whose calls of one variant find different answers is refused.
/// Records still carry today's `functionName`, which the engine's allocator names apart; the allocation moves to node
/// records last, at stage 4.
struct NodeRecords: Sendable {
	/// - Parameters:
	///   - world: A production root's world.
	///   - seamTree: What a seam's own root is handed: its parameters, the nearest declarations of their labels, and the
	///     instances of `LazilyInstantiated` properties among them, a deferred parameter's memo included, which its tree
	///     reads through their wrappers. `nil` for any other root.
	/// - Throws: A `NodeRecordRefusal` where the world holds a kind stage 1 does not make, or what an initializer's
	///   arguments throw.
	init(world: some NodeRecordSources, seamTree: DependencyTreeGenerator.RootScopeInfo.SeamTree? = nil) throws {
		let declarationCount = world.declarationCount
		var kinds = [NodeRecordKind]()
		kinds.reserveCapacity(declarationCount)
		for declaration in 0..<Int32(declarationCount) {
			try kinds.append(Self.kind(of: declaration, in: world))
			try Self.checkReadsNoSeamRootValue(of: seamTree, declaration, in: world)
		}
		var variantByDeclaration = [VariantID](repeating: -1, count: declarationCount)
		for variant in 0..<Int32(world.variantCount) {
			let declaration = Int(world.declaration(of: variant))
			guard variantByDeclaration[declaration] < 0 else { throw NodeRecordRefusal.nodeHasSeveralVariants }
			variantByDeclaration[declaration] = variant
		}
		let order = try NodeBuildOrder(world: world)
		let onlyIfAvailableAnswers = try OnlyIfAvailableAnswers(world: world, rootParameters: seamTree?.parameters ?? [])
		// A node's place holds its children's places, so each is made after its children: a post-order walk from the root,
		// with a stack, since a tree can be as deep as the module has types.
		var places = [GeneratedCode?](repeating: nil, count: world.variantCount)
		var records = [PlaceRecord?](repeating: nil, count: world.variantCount)
		var typesDeclaredEscaping = [Set<TypeDescription>?](repeating: nil, count: world.variantCount)
		var holdsCallFields = false
		var stack: [(variant: VariantID, childrenPushed: Bool)] = [(0, false)]
		while let (variant, childrenPushed) = stack.popLast() {
			let calls = world.calls(of: variant)
			guard childrenPushed else {
				stack.append((variant, true))
				for callee in calls.reversed() where places[Int(callee)] == nil {
					stack.append((callee, false))
				}
				continue
			}
			guard variant != 0, places[Int(variant)] == nil else { continue }
			let declaration = world.declaration(of: variant)
			let scope = world.scope(of: declaration)
			let instantiable = scope.instantiable
			var escaping = Set(instantiable.initializer?.typesDeclaredEscaping ?? [])
			escaping.formUnion(instantiable.mockInitializer?.typesDeclaredEscaping ?? [])
			// A call of a seam spells the builder types its signature declares `@escaping` so, as its tree does.
			escaping.formUnion(scope.seamCall?.typesDeclaredEscaping ?? [])
			var children = [GeneratedCode]()
			for edgeIndex in order.edgeIndices(of: declaration) {
				let callee = Int(calls[calls.startIndex + edgeIndex])
				escaping.formUnion(typesDeclaredEscaping[callee] ?? [])
				children.append(.indented(places[callee] ?? .empty, by: ScopeGenerator.standardIndent))
			}
			let record: PlaceRecord = switch kinds[Int(declaration)] {
			case .builtByInitializer:
				try .built(Self.builtByInitializerRecord(of: declaration, variant: variant, in: world, typesDeclaredEscaping: escaping, children: children))
			case .inlineSeam:
				try .built(Self.inlineSeamRecord(of: declaration, variant: variant, in: world, typesDeclaredEscaping: escaping, children: children))
			case .seamCall:
				try .built(Self.seamCallRecord(of: declaration, variant: variant, in: world, typesDeclaredEscaping: escaping, children: children))
			case .receivesOnlyIfAvailable:
				try .built(Self.receivesOnlyIfAvailableRecord(of: declaration, variant: variant, in: world, answers: onlyIfAvailableAnswers, typesDeclaredEscaping: escaping, children: children))
			case .unavailableDependency:
				try .alias(Self.unavailableDependencyRecord(of: declaration, in: world))
			case .rename:
				try .alias(Self.renameRecord(of: declaration, variant: variant, in: world, answers: onlyIfAvailableAnswers))
			case .mockConstruction:
				try .built(Self.mockConstructionRecord(of: declaration, variant: variant, in: world, typesDeclaredEscaping: escaping, children: children))
			}
			typesDeclaredEscaping[Int(variant)] = escaping
			records[Int(variant)] = record
			if case let .built(builtRecord) = record, builtRecord.callFields != nil {
				holdsCallFields = true
			}
			places[Int(variant)] = switch record {
			case let .alias(aliasRecord):
				// A place written as text: the engine copies it as written.
				.place(PlacePlan(code: .text(aliasRecord.text), record: record))
			case .built, .closer:
				.place(PlacePlan(code: .empty, record: record))
			}
		}
		let rootCalls = world.calls(of: 0)
		rootBody = order.edgeIndices(of: 0).map { edgeIndex in
			.indented(places[Int(rootCalls[rootCalls.startIndex + edgeIndex])] ?? .empty, by: TypeKeyBody.rootStatementIndentation)
		}
		self.records = records
		self.holdsCallFields = holdsCallFields
		declarationByVariant = (0..<Int32(world.variantCount)).map(world.declaration(of:))
	}

	/// The record of `declaration`'s place in `variant`'s body. The root, variant 0, has none.
	func record(of _: DeclarationID, variant: VariantID) -> PlaceRecord? {
		records[Int(variant)]
	}

	/// The root's body: a place for each of the root's children, in the order the root builds them, indented as a root's
	/// statements are.
	let rootBody: [GeneratedCode]

	/// Whether a record holds fields of a call of another module's code (`CallFields`), which the engine does not spell yet:
	/// such a root's records are compared with its tree's, and its code is not laid out from them.
	let holdsCallFields: Bool

	/// How many variants have a record, which is every variant but the root's.
	var recordCount: Int {
		declarationByVariant.indices.dropFirst().count { record(of: declarationByVariant[$0], variant: VariantID($0)) != nil }
	}

	/// Each variant's declaration.
	private let declarationByVariant: [DeclarationID]

	/// By variant.
	private let records: [PlaceRecord?]

	/// Every refusal `world` holds, each once, in the order of `NodeRecordRefusal`'s cases: what a test reports of a world, so
	/// that each stage counts the worlds it frees.
	static func refusals(in world: some NodeRecordSources, seamTree: DependencyTreeGenerator.RootScopeInfo.SeamTree? = nil) -> [NodeRecordRefusal] {
		var refusals = Set<NodeRecordRefusal>()
		for declaration in 0..<Int32(world.declarationCount) {
			refusals.formUnion(kindAndRefusals(of: declaration, in: world).refusals)
			do {
				try checkReadsNoSeamRootValue(of: seamTree, declaration, in: world)
			} catch {
				refusals.insert(error)
			}
		}
		var declarationsWithAVariant = Set<DeclarationID>()
		for variant in 0..<Int32(world.variantCount) where !declarationsWithAVariant.insert(world.declaration(of: variant)).inserted {
			refusals.insert(.nodeHasSeveralVariants)
		}
		do {
			_ = try NodeBuildOrder(world: world)
		} catch {
			refusals.insert(error)
		}
		do {
			_ = try OnlyIfAvailableAnswers(world: world, rootParameters: seamTree?.parameters ?? [])
		} catch {
			refusals.insert(error)
		}
		return NodeRecordRefusal.allCases.filter(refusals.contains)
	}

	/// Refuses `declaration`'s world where its type reads what a seam's root is handed as stage 1 does not write it: as
	/// the lazy stage's, a receive or a rename of one of the instances of `LazilyInstantiated` properties the root is
	/// handed, which its tree reads through the wrapper and stage 1 would read as a binding of the label; as a rename's,
	/// the seam's own rename that keeps a deferred parameter's label, which the tree binds from the parameter's
	/// autoclosure and writes no record of.
	private static func checkReadsNoSeamRootValue(of seamTree: DependencyTreeGenerator.RootScopeInfo.SeamTree?, _ declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) {
		guard let seamTree else { return }
		let readsAnInstance = world.scope(of: declaration).instantiable.dependencies.contains { dependency in
			switch dependency.source {
			case .received:
				seamTree.rootLazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty)
			case let .aliased(fulfillingProperty, _, _):
				seamTree.rootLazilyInstantiatedInstanceProperties.contains(fulfillingProperty.asUnwrappedProperty)
			case .instantiated, .forwarded:
				false
			}
		}
		guard !readsAnInstance else { throw .lazy }
		// The root declares no rename through a variant of its own, so it is the scope of each rename among its edges.
		guard declaration == 0 else { return }
		let readsAnAutoclosure = world.edges(from: declaration).contains { edge in
			world.kind(of: edge) == .alias && world.property(of: edge).map { seamTree.autoclosureLabels.contains($0.label) } == true
		}
		guard !readsAnAutoclosure else { throw .renameOrHole }
	}

	/// The kind of record `declaration` is made as, or the first refusal it holds (`kindAndRefusals(of:in:)`).
	private static func kind(of declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) -> NodeRecordKind {
		let (kind, refusals) = kindAndRefusals(of: declaration, in: world)
		if let refusal = refusals.first {
			throw refusal
		}
		return kind
	}

	/// The kind `declaration` is made as, and every refusal it holds: those of the claim a lane's kind makes of it, and
	/// every check of stage 1 the claim does not discharge (`refusalsOfBuiltByInitializer(_:in:)`). A node of two kinds,
	/// one claimed, is still refused for the other.
	private static func kindAndRefusals(of declaration: DeclarationID, in world: some NodeRecordSources) -> (kind: NodeRecordKind, refusals: [NodeRecordRefusal]) {
		let claim = claim(of: declaration, in: world)
		let discharged = claim?.discharges ?? []
		let refusals = (claim?.refusals ?? []) + refusalsOfBuiltByInitializer(declaration, in: world).filter { !discharged.contains($0) }
		return (claim?.kind ?? .builtByInitializer, refusals)
	}

	/// What a lane's kind claims of `declaration`, or `nil` where none does. Each lane adds one line here, above the test's,
	/// in the order of `NodeRecordKind`'s cases, calling its file's classifier, which returns `nil` for a node not of its
	/// kind: `if let claim = <kind>Claim(of: declaration, in: world) { return claim }`.
	private static func claim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		if let claim = inlineSeamClaim(of: declaration, in: world) {
			return claim
		}
		if let claim = seamCallClaim(of: declaration, in: world) {
			return claim
		}
		if let claim = unavailableDependencyClaim(of: declaration, in: world) {
			return claim
		}
		if let claim = receivesOnlyIfAvailableClaim(of: declaration, in: world) {
			return claim
		}
		if let claim = renameClaim(of: declaration, in: world) {
			return claim
		}
		// Asked after every other kind: it claims every node of a mock root's world that stage 1 makes.
		if let claim = mockConstructionClaim(of: declaration, in: world) {
			return claim
		}
		// A test claims a node by its type's name (`NodeRecordsObservation.claimsForTesting`).
		return NodeRecordsObservation.claimsForTesting[world.scope(of: declaration).instantiable.concreteInstantiable.asSource].map { discharged in
			NodeRecordClaim(kind: .builtByInitializer, discharges: Set(discharged.compactMap(NodeRecordRefusal.init(rawValue:))))
		}
	}
}

/// What a lane's kind claims of a node (`NodeRecords.claim(of:in:)`): the kind its record is made as, the refusals of
/// stage 1's checks the kind discharges, which are the kinds it makes, and any refusal of its own the node holds, of its
/// kind but a shape it does not make yet.
struct NodeRecordClaim: Sendable {
	let kind: NodeRecordKind
	let discharges: Set<NodeRecordRefusal>
	var refusals = [NodeRecordRefusal]()
}

/// The kinds of node `NodeRecords` makes a record of. Each is made by one file of this folder, `NodeRecords+<Kind>.swift`,
/// which the lane that adds the kind owns: its classifier (whether a node is of the kind) and its record. A world holding
/// a node of no kind is refused whole. The stages of `lanes/per-type-facts/node-records-interface.md` add the kinds in
/// order; loops of received builders and mock construction kinds are other lanes', handed to this folder.
enum NodeRecordKind: Sendable {
	/// A constant or an `Instantiator` built by its type's initializer or `instantiate()`, off every cycle, with nothing
	/// erased, lazy, `@Sendable`, received only if available, renamed or filled in its scope (stage 1).
	case builtByInitializer
	/// A seam of another module built inline, because no module SafeDI knows generates its initializer, and otherwise a
	/// node `builtByInitializer` makes: its line ends with the comment that says why (`NodeRecords+InlineSeam.swift`).
	case inlineSeam
	/// A call of another module's seam that passes it no builder, made as a node `builtByInitializer` makes the seam's leaf,
	/// whose builder function begins with the call's guard line (`NodeRecords+SeamCall.swift`).
	case seamCall
	/// A property instantiated only if available that no declaration fulfills, bound to `nil` and written as text
	/// (`NodeRecords+UnavailableDependency.swift`).
	case unavailableDependency
	/// A node that would be of kind `builtByInitializer` but that its type receives a property only if available, which its
	/// construction is passed where the variant's calls find it available, and `nil` where not (`OnlyIfAvailableAnswers`).
	case receivesOnlyIfAvailable
	/// A rename a scope declares (`@Received(fulfilledByDependencyNamed:ofType:)`), written as text: bound from its fulfilling
	/// property, or, only if available, to `nil` where no declaration it reads is available (`NodeRecords+Rename.swift`).
	case rename
	/// A node of a mock root's world that stage 1 would make in a production root's, which reads its override before it
	/// calls its type's initializer (`NodeRecords+MockConstruction.swift`).
	case mockConstruction
}
