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
/// are inert: no receive only if available, and no cycle, so nothing is still being built where it is read. The first
/// stage that admits either reads what each call hands its callee (`TypeFactsWorld.sources(ofCall:of:)`), never a
/// variant's keys. Records still carry today's `functionName`, which the engine's allocator names apart; the allocation
/// moves to node records last, at stage 4.
struct NodeRecords: Sendable {
	/// - Parameter world: A production root's world.
	/// - Throws: A `NodeRecordRefusal` where the world holds a kind stage 1 does not make, or what an initializer's
	///   arguments throw.
	init(world: some NodeRecordSources) throws {
		let declarationCount = world.declarationCount
		var kinds = [NodeRecordKind]()
		kinds.reserveCapacity(declarationCount)
		for declaration in 0..<Int32(declarationCount) {
			try kinds.append(Self.kind(of: declaration, in: world))
		}
		var variantByDeclaration = [VariantID](repeating: -1, count: declarationCount)
		for variant in 0..<Int32(world.variantCount) {
			let declaration = Int(world.declaration(of: variant))
			guard variantByDeclaration[declaration] < 0 else { throw NodeRecordRefusal.nodeHasSeveralVariants }
			variantByDeclaration[declaration] = variant
		}
		let order = try NodeBuildOrder(world: world)
		// A node's place holds its children's places, so each is made after its children: a post-order walk from the root,
		// with a stack, since a tree can be as deep as the module has types.
		var places = [GeneratedCode?](repeating: nil, count: world.variantCount)
		var records = [BuiltPlaceRecord?](repeating: nil, count: world.variantCount)
		var typesDeclaredEscaping = [Set<TypeDescription>?](repeating: nil, count: world.variantCount)
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
			let instantiable = world.scope(of: declaration).instantiable
			var escaping = Set(instantiable.initializer?.typesDeclaredEscaping ?? [])
			escaping.formUnion(instantiable.mockInitializer?.typesDeclaredEscaping ?? [])
			var children = [GeneratedCode]()
			for edgeIndex in order.edgeIndices(of: declaration) {
				let callee = Int(calls[calls.startIndex + edgeIndex])
				escaping.formUnion(typesDeclaredEscaping[callee] ?? [])
				children.append(.indented(places[callee] ?? .empty, by: ScopeGenerator.standardIndent))
			}
			let record = switch kinds[Int(declaration)] {
			case .builtByInitializer:
				try Self.builtByInitializerRecord(of: declaration, variant: variant, in: world, typesDeclaredEscaping: escaping, children: children)
			}
			typesDeclaredEscaping[Int(variant)] = escaping
			records[Int(variant)] = record
			places[Int(variant)] = .place(PlacePlan(code: .empty, record: .built(record)))
		}
		let rootCalls = world.calls(of: 0)
		rootBody = order.edgeIndices(of: 0).map { edgeIndex in
			.indented(places[Int(rootCalls[rootCalls.startIndex + edgeIndex])] ?? .empty, by: TypeKeyBody.rootStatementIndentation)
		}
		self.records = records
		declarationByVariant = (0..<Int32(world.variantCount)).map(world.declaration(of:))
	}

	/// The record of `declaration`'s place in `variant`'s body. The root, variant 0, has none.
	func record(of _: DeclarationID, variant: VariantID) -> BuiltPlaceRecord? {
		records[Int(variant)]
	}

	/// The root's body: a place for each of the root's children, in the order the root builds them, indented as a root's
	/// statements are.
	let rootBody: [GeneratedCode]

	/// How many variants have a record, which is every variant but the root's.
	var recordCount: Int {
		declarationByVariant.indices.dropFirst().count { record(of: declarationByVariant[$0], variant: VariantID($0)) != nil }
	}

	/// Each variant's declaration.
	private let declarationByVariant: [DeclarationID]

	/// By variant.
	private let records: [BuiltPlaceRecord?]

	/// Every refusal `world` holds, each once, in the order of `NodeRecordRefusal`'s cases: what a test reports of a world, so
	/// that each stage counts the worlds it frees.
	static func refusals(in world: some NodeRecordSources) -> [NodeRecordRefusal] {
		var refusals = Set<NodeRecordRefusal>()
		for declaration in 0..<Int32(world.declarationCount) {
			refusals.formUnion(kindAndRefusals(of: declaration, in: world).refusals)
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
		return NodeRecordRefusal.allCases.filter(refusals.contains)
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
		// A test claims a node by its type's name (`NodeRecordsObservation.claimsForTesting`).
		NodeRecordsObservation.claimsForTesting[world.scope(of: declaration).instantiable.concreteInstantiable.asSource].map { discharged in
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
}
