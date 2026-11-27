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
	/// The node is built as a `LazilyInstantiated`, or its scope declares or forwards one.
	/// The node's type declares a rename, a hole, or an instantiated dependency its scope does not build.
	case renameOrHole
	/// The node's call passes fills.
	case fill
	/// The node is on a cycle.
	case cycle
	/// A node on a cycle is built at two places whose trees close the cycle on different places above them, so that one
	/// place of its variant cannot stand for both.
	case cycleMemberBuiltTwoWays
	/// A world with a cycle in which a type receives a builder, whose call today's tree makes through a function it
	/// declares for the loop of builders it closes.
	case cycleReceivesBuilder
	/// A place between a place on a cycle and the call that closes the cycle on it declares a label some type receives, so
	/// that the function the call refers to may take that label's value as a parameter.
	case cycleTakesParameters
	/// Two places of a world with a cycle are bound to one label, and one of them is on a cycle or a builder, so that today's
	/// tree may name one's function apart.
	case cycleBuilderNameShared
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
		// A world whose edges close a cycle builds each node's children in the order step 0's sibling-order fixed point gives
		// them (`TypeFactsEdge.buildPosition`), which `NodeBuildOrder` stands in for only off every cycle.
		let holdsCycle = (0..<Int32(declarationCount)).contains(where: world.isOnCycle)
		let order: NodeBuildOrder? = holdsCycle ? nil : try NodeBuildOrder(world: world)
		let labelsReceived = holdsCycle ? try Self.labelsReceived(inWorldWithCycle: world) : []
		var bindingOfLabel = [String: (variant: VariantID, namesFunction: Bool)]()
		func edgeIndices(of declaration: DeclarationID) -> [Int] {
			order?.edgeIndices(of: declaration) ?? world.edgeFacts(from: declaration).enumerated().sorted { $0.element.buildPosition < $1.element.buildPosition }.map(\.offset)
		}
		// A node's place holds its children's places, so each is made after its children: a walk from the root, with a
		// stack, since a tree can be as deep as the module has types. A call of a variant whose place is being built above
		// it closes the cycle there (`closingRecord(closingOn:in:)`). A variant's place is made once and shared, which holds
		// only where every place that reads it closes on the same places above: each place notes the variants on a cycle
		// its tree closes on above it and those it builds, and a second place of the variant must have the first on its
		// path and none of the second.
		var places = [GeneratedCode?](repeating: nil, count: world.variantCount)
		var records = [PlaceRecord?](repeating: nil, count: world.variantCount)
		var typesDeclaredEscaping = [Set<TypeDescription>](repeating: [], count: world.variantCount)
		var variantsClosedOn = [Set<VariantID>](repeating: [], count: world.variantCount)
		var cycleVariantsBuilt = [Set<VariantID>](repeating: [], count: world.variantCount)
		var isOnPath = [Bool](repeating: false, count: world.variantCount)
		func frame(of variant: VariantID) -> PlaceFrame {
			let declaration = world.declaration(of: variant)
			let instantiable = world.scope(of: declaration).instantiable
			var escaping = Set(instantiable.initializer?.typesDeclaredEscaping ?? [])
			escaping.formUnion(instantiable.mockInitializer?.typesDeclaredEscaping ?? [])
			return PlaceFrame(variant: variant, edgeIndices: edgeIndices(of: declaration), typesDeclaredEscaping: escaping)
		}
		var stack = [frame(of: 0)]
		isOnPath[0] = true
		var rootBody = [GeneratedCode]()
		while let top = stack.last {
			let indentation = top.variant == 0 ? TypeKeyBody.rootStatementIndentation : ScopeGenerator.standardIndent
			if top.next < top.edgeIndices.count {
				stack[stack.count - 1].next += 1
				let calls = world.calls(of: top.variant)
				let callee = calls[calls.startIndex + top.edgeIndices[top.next]]
				if isOnPath[Int(callee)] {
					if let closedOn = stack.lastIndex(where: { $0.variant == callee }),
					   stack[(closedOn + 1)...].contains(where: { !labelsReceived.isDisjoint(with: Self.labelsDeclared(by: world.declaration(of: $0.variant), in: world)) })
					{
						throw NodeRecordRefusal.cycleTakesParameters
					}
					let closer = try Self.closingRecord(closingOn: world.declaration(of: callee), in: world)
					stack[stack.count - 1].children.append(.indented(.place(PlacePlan(code: .empty, record: closer)), by: indentation))
					stack[stack.count - 1].variantsClosedOn.insert(callee)
				} else if let place = places[Int(callee)] {
					guard variantsClosedOn[Int(callee)].allSatisfy({ isOnPath[Int($0)] }), !cycleVariantsBuilt[Int(callee)].contains(where: { isOnPath[Int($0)] }) else {
						throw NodeRecordRefusal.cycleMemberBuiltTwoWays
					}
					stack[stack.count - 1].children.append(.indented(place, by: indentation))
					stack[stack.count - 1].typesDeclaredEscaping.formUnion(typesDeclaredEscaping[Int(callee)])
					stack[stack.count - 1].variantsClosedOn.formUnion(variantsClosedOn[Int(callee)])
					stack[stack.count - 1].cycleVariantsBuilt.formUnion(cycleVariantsBuilt[Int(callee)])
				} else {
					if holdsCycle, let property = world.property(of: world.declaration(of: callee)) {
						let namesFunction = world.isOnCycle(world.declaration(of: callee)) || !property.propertyType.isConstant
						if let binding = bindingOfLabel[property.label] {
							guard binding.variant == callee || !(binding.namesFunction || namesFunction) else {
								throw NodeRecordRefusal.cycleBuilderNameShared
							}
						} else {
							bindingOfLabel[property.label] = (callee, namesFunction)
						}
					}
					isOnPath[Int(callee)] = true
					stack.append(frame(of: callee))
				}
				continue
			}
			stack.removeLast()
			isOnPath[Int(top.variant)] = false
			guard let parent = stack.indices.last else {
				rootBody = top.children
				continue
			}
			let declaration = world.declaration(of: top.variant)
			let record = switch kinds[Int(declaration)] {
			case .builtByInitializer:
				try PlaceRecord.built(Self.builtByInitializerRecord(of: declaration, variant: top.variant, in: world, typesDeclaredEscaping: top.typesDeclaredEscaping, children: top.children))
			case .cycle:
				try Self.cycleRecord(of: declaration, variant: top.variant, in: world, typesDeclaredEscaping: top.typesDeclaredEscaping, children: top.children)
			}
			let place = GeneratedCode.place(PlacePlan(code: .empty, record: record))
			records[Int(top.variant)] = record
			places[Int(top.variant)] = place
			typesDeclaredEscaping[Int(top.variant)] = top.typesDeclaredEscaping
			var closedOn = top.variantsClosedOn
			closedOn.remove(top.variant)
			variantsClosedOn[Int(top.variant)] = closedOn
			var built = top.cycleVariantsBuilt
			if world.isOnCycle(declaration) {
				built.insert(top.variant)
			}
			cycleVariantsBuilt[Int(top.variant)] = built
			stack[parent].children.append(.indented(place, by: parent == 0 ? TypeKeyBody.rootStatementIndentation : ScopeGenerator.standardIndent))
			stack[parent].typesDeclaredEscaping.formUnion(top.typesDeclaredEscaping)
			stack[parent].variantsClosedOn.formUnion(closedOn)
			stack[parent].cycleVariantsBuilt.formUnion(built)
		}
		self.rootBody = rootBody
		self.records = records
		declarationByVariant = (0..<Int32(world.variantCount)).map(world.declaration(of:))
	}

	/// The record of `declaration`'s place in `variant`'s body. The root, variant 0, has none.
	func record(of _: DeclarationID, variant: VariantID) -> PlaceRecord? {
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
	private let records: [PlaceRecord?]

	/// A place `init(world:)`'s walk is making: its variant, its node's edges in build order and the next to walk, and
	/// what the places made beneath it so far hand it.
	private struct PlaceFrame {
		let variant: VariantID
		let edgeIndices: [Int]
		var next = 0
		var children = [GeneratedCode]()
		var typesDeclaredEscaping: Set<TypeDescription>
		/// The variants on a cycle above the place that its tree closes on.
		var variantsClosedOn = Set<VariantID>()
		/// The variants on a cycle the place's tree builds.
		var cycleVariantsBuilt = Set<VariantID>()
	}

	/// Every refusal `world` holds, each once, in the order of `NodeRecordRefusal`'s cases: what a test reports of a world, so
	/// that each stage counts the worlds it frees.
	static func refusals(in world: some NodeRecordSources) -> [NodeRecordRefusal] {
		var refusals = Set<NodeRecordRefusal>()
		for declaration in 0..<Int32(world.declarationCount) {
			do {
				// A node a lane's kind claims holds no refusal of the kinds no lane makes yet.
				if try claimedKind(of: declaration, in: world) == nil {
					refusals.formUnion(refusalsOfBuiltByInitializer(declaration, in: world))
				}
			} catch {
				refusals.insert(error)
			}
		}
		var declarationsWithAVariant = Set<DeclarationID>()
		for variant in 0..<Int32(world.variantCount) where !declarationsWithAVariant.insert(world.declaration(of: variant)).inserted {
			refusals.insert(.nodeHasSeveralVariants)
		}
		if (0..<Int32(world.declarationCount)).contains(where: world.isOnCycle) {
			// A world with a cycle is built in step 0's order, and its walk refuses what its places' closing needs.
			if refusals.isEmpty, case let .failure(refusal as NodeRecordRefusal) = Result(catching: { try NodeRecords(world: world) }) {
				refusals.insert(refusal)
			}
		} else {
			do {
				_ = try NodeBuildOrder(world: world)
			} catch {
				refusals.insert(error)
			}
		}
		return NodeRecordRefusal.allCases.filter(refusals.contains)
	}

	/// The kind of record `declaration` is made as, or the refusal of its world: the kind a lane's classifier claims it as,
	/// and otherwise a node built by its initializer, where it holds none of the kinds no lane makes yet
	/// (`checkBuiltByInitializer(_:in:)`).
	private static func kind(of declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) -> NodeRecordKind {
		guard let kind = try claimedKind(of: declaration, in: world) else {
			try checkBuiltByInitializer(declaration, in: world)
			return .builtByInitializer
		}
		return kind
	}

	/// The kind a lane's classifier claims `declaration` as, or `nil` where none does. Each lane adds one line here, in
	/// the order of `NodeRecordKind`'s cases, calling its file's classifier, `<kind>Kind(of:in:)`, which returns `nil` for
	/// a node not of its kind and throws a refusal for a node of its kind it cannot make:
	/// `if let kind = try <kind>Kind(of: declaration, in: world) { return kind }`.
	private static func claimedKind(of declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) -> NodeRecordKind? {
		if let kind = try cycleKind(of: declaration, in: world) { return kind }
		return nil
	}
}

/// The kinds of node `NodeRecords` makes a record of. Each is made by one file of this folder, `NodeRecords+<Kind>.swift`,
/// which the lane that adds the kind owns: its classifier (whether a node is of the kind) and its record. A world holding
/// a node of no kind is refused whole. The stages of `lanes/per-type-facts/node-records-interface.md` add the kinds in
/// order; loops of received builders and mock construction kinds are other lanes', handed to this folder.
enum NodeRecordKind: Sendable {
	/// A constant or an `Instantiator` built by its type's initializer or `instantiate()`, off every cycle, with nothing
	/// erased, lazy, `@Sendable`, received only if available, renamed or filled in its scope (stage 1).
	case builtByInitializer
	/// A node on a cycle, otherwise of stage 1's kinds, whose children's places include the closing place of each call back
	/// to a place being built above it (`NodeRecords+Cycle.swift`).
	case cycle
}
