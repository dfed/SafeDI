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
	/// The node calls another module's public mock and fills a builder of it: its fills, dispatchers and level functions
	/// are declared in a builder function of the call's own.
	case publicMockCallFills
	/// The node calls another module's public mock and passes a builder up to it, which is bound again under the label the
	/// leaf receives it as.
	case publicMockCallPassesUp
	/// A mock root's node's type takes, in its initializer or its hand-written mock, a value no dependency fulfills, as a
	/// parameter with a default value is, which a mock holds in the type's configuration.
	case mockDefaultValuedParameter
	/// A mock root's node whose override is not its parent's field under the node's own label: two children of one node
	/// share a label, which a mock root names apart.
	case mockOverrideNotParentField
	/// A mock root binds a value that is no node of its world before its tree, or names one apart: a parameter of
	/// `mock()`, an override of a value its tree receives only if available, a builder, a wrapper around an instance.
	case mockRootBindsOtherThanNodes
	/// The node is built in a `@Sendable` function of its own: a `SendableInstantiator`, erased or not, or a
	/// `SendableLazilyInstantiated`, which `sendableClaim(of:in:)` discharges: its record is `NodeRecordKind.sendable`'s.
	case sendable
	/// A `@Sendable` function of the world reads, from outside it, a wrapper that is not `Sendable`
	/// (`DeclarationsAnsweringReads.sendableFunctionCapturesWrapper`): an error the tree reports, which the records
	/// cannot, so the world keeps its tree.
	case sendableFunctionCapturesWrapper
	/// The node is built as an `ErasedInstantiator`, or as a constant or an `Instantiator` erased to its property's type,
	/// which `erasedClaim(of:in:)` discharges: its record is `NodeRecordKind.erased`'s.
	case erased
	/// The node's type declares a rename or a hole.
	case renameOrHole
	/// The node's type instantiates a dependency its scope does not build, which a mock takes as a parameter of `mock()`
	/// (`Scope.instantiatedDependenciesNotGenerated`): in a mock root's world `mockUncoveredDependencyDischarges(of:in:)`
	/// discharges it where `mock()` takes each such dependency as a plain value. A production root's world never holds one.
	case uncoveredDependency
	/// The node's call passes fills.
	case fill
	/// The node is on a cycle.
	case cycle
	/// The node is built as a `LazilyInstantiated`, which `lazyClaim(of:in:)` discharges: its record is
	/// `NodeRecordKind.lazy`'s, and in a mock root's world `mockLazyDischarges(of:in:)` discharges it. Also a world whose
	/// records read a wrapper's instance where no record does yet: a rename fulfilled by one
	/// (`DeclarationsAnsweringReads.renameReadsWrappersInstance`) and a seam's own root handed one.
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
	/// A declaration whose answers a producer of the facts still owes (`TypeFactsWorld.owedFacts(of:)`): two places of one
	/// of its variants can answer a read apart, which one record per variant cannot write. The whole world is refused,
	/// whatever its kinds, until each producer lands and clears its bit.
	case readAnsweredTwoWays
	/// The engine could not lay the root out from the records.
	case notLaidOut
}

/// What a world's records read of a node beside the frozen interface (`TypeFactsWorld`): the scope it builds and the
/// property it builds as, from which a node's construction facts come until the facts' columns hold them.
protocol NodeRecordSources: TypeFactsWorld {
	func scope(of declaration: DeclarationID) -> ConstructionScope
	/// The property the declaration is built as, `nil` for the root.
	func property(of declaration: DeclarationID) -> Property?
	/// Whether the declaration's built value is erased to its property's type (`erasedToConcreteExistential`).
	func isErased(_ declaration: DeclarationID) -> Bool
	/// The text of a label a read asks about (`Read.label`).
	func text(ofLabel label: WorldLabelID) -> String
	/// Whether the world is a mock root's, each of whose nodes reads its override.
	var isMockWorld: Bool { get }
	/// What a mock root's lowering names that the records of its world read; empty for a production root's world.
	var mockRootNames: MockRootNames { get }
}

extension TypeFactsGraph: NodeRecordSources {
	func scope(of declaration: DeclarationID) -> ConstructionScope {
		graph.nodes[Int(declaration)].scope
	}

	func property(of declaration: DeclarationID) -> Property? {
		graph.nodes[Int(declaration)].property
	}

	func isErased(_ declaration: DeclarationID) -> Bool {
		graph.nodes[Int(declaration)].key.erasedToConcreteExistential
	}

	func text(ofLabel label: WorldLabelID) -> String {
		labelTexts[Int(label)]
	}
}

/// The records of one world's places, made from its per-type facts (`TypeFactsWorld`) with no `ScopeGenerator`: one
/// `BuiltPlaceRecord` per variant, and the root's body as the places it builds, in order. A variant's place is made once
/// and shared by every call of it, so the engine reads it once per view (`TypeKeyLayout.read(_:)`).
///
/// Records are made only for a world each of whose nodes is built by its type's initializer, off every cycle, with one
/// variant, as a constant or in any of SafeDI's wrappers, erased or not (`NodeRecordKind`); any other world is refused
/// with the first kind it holds, and so is a world the tree reports an error of that the records cannot: a `@Sendable`
/// function that captures a wrapper that is not `Sendable` (`NodeRecordRefusal.sendableFunctionCapturesWrapper`).
///
/// One variant per node is enough here because a record reads only answers every call into a variant gives alike. Each
/// `PlaceRead.source` is the label `createInitializerArguments` names, which the engine resolves per view, or the
/// instance of a lazily instantiated property declared above the node, which a receive by value reads
/// (`DeclarationsAnsweringReads`). That holds only while both key projections are inert: no receive only if available,
/// and no cycle, so nothing is still being built where it is read. A node that receives a property only if available
/// (`receivesOnlyIfAvailable`) reads what each call of its variant finds (`OnlyIfAvailableAnswers`, from the calls and
/// `TypeFactsEdge.buildPosition`, since the world's answers do not model sibling order), never a variant's keys, and a
/// world whose calls of one variant find different answers is refused. Records still carry today's `functionName`, which
/// the engine's allocator names apart.
struct NodeRecords: Sendable {
	/// - Parameters:
	///   - world: A production root's world.
	///   - seamTree: What a seam's own root is handed: its parameters, the nearest declarations of their labels, and the
	///     instances of `LazilyInstantiated` properties among them, a deferred parameter's memo included, which its tree
	///     reads through their wrappers. `nil` for any other root.
	///   - outerDeclarations: What a mock root's body is declared inside, the nearest declarations of their labels: the
	///     parameters of `mock()` and the overrides it binds before its nodes, which a node's receive only if available
	///     reads as a seam's tree reads the seam's parameters. Empty for any other root.
	///   - declaredTypeNames: The names the modules SafeDI read declare types by at file scope, which the check of an erased
	///     instantiator's first generic argument reads (`checkForwardsBuiltTypesProperties(_:in:declaredTypeNames:)`).
	///     `nil` for a mock root's world, where no kind claims an erased instantiator and the mock's own tree reports it.
	/// - Throws: A `NodeRecordRefusal` where the world holds a kind node records do not make, or what an initializer's
	///   arguments throw.
	init(world: some NodeRecordSources, seamTree: DependencyTreeGenerator.RootScopeInfo.SeamTree? = nil, outerDeclarations: [Property] = [], declaredTypeNames: DeclaredTypeNames?) throws {
		let declarationCount = world.declarationCount
		var kinds = [NodeRecordKind]()
		kinds.reserveCapacity(declarationCount)
		for declaration in 0..<Int32(declarationCount) {
			try kinds.append(Self.kind(of: declaration, in: world))
			try Self.checkReadsNoSeamRootValue(of: seamTree, declaration, in: world)
			try Self.checkForwardsBuiltTypesProperties(declaration, in: world, declaredTypeNames: declaredTypeNames)
		}
		var variantByDeclaration = [VariantID](repeating: -1, count: declarationCount)
		for variant in 0..<Int32(world.variantCount) {
			let declaration = Int(world.declaration(of: variant))
			guard variantByDeclaration[declaration] < 0 else { throw NodeRecordRefusal.nodeHasSeveralVariants }
			variantByDeclaration[declaration] = variant
		}
		let order = try NodeBuildOrder(world: world)
		let onlyIfAvailableAnswers = try OnlyIfAvailableAnswers(world: world, rootParameters: seamTree?.parameters ?? outerDeclarations)
		let mockReceivesBoundAgain = Self.mockReceivesBoundAgain(in: world)
		let answeringDeclarations = DeclarationsAnsweringReads(world: world)
		// The tree reports the capture as an error, which the records cannot.
		guard !answeringDeclarations.sendableFunctionCapturesWrapper else { throw NodeRecordRefusal.sendableFunctionCapturesWrapper }
		// A rename's record binds it from its fulfilling property's label, never from a wrapper's instance.
		guard !answeringDeclarations.renameReadsWrappersInstance else { throw NodeRecordRefusal.lazy }
		// A node's place holds its children's places, so each is made after its children: a post-order walk from the root,
		// with a stack, since a tree can be as deep as the module has types.
		var places = [GeneratedCode?](repeating: nil, count: world.variantCount)
		var records = [PlaceRecord?](repeating: nil, count: world.variantCount)
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
			// A place of a seam's own mock is bound from its builder before the node's children, which read it.
			children.insert(contentsOf: Self.mockPlaceBuilderBindings(of: declaration, in: world).map(\.place), at: 0)
			// What a receive by value reads as a wrapper's instance, which every record of a construction passes its arguments.
			let instanceProperties = answeringDeclarations.lazilyInstantiatedInstanceProperties(readBy: variant)
			let record: PlaceRecord = switch kinds[Int(declaration)] {
			case .builtByInitializer, .erased, .lazy, .sendable:
				// One record serves the four: what tells them apart, it reads of the node.
				try .built(Self.builtByInitializerRecord(of: declaration, variant: variant, in: world, lazilyInstantiatedInstanceProperties: instanceProperties, typesDeclaredEscaping: escaping, children: children))
			case .inlineSeam:
				try .built(Self.inlineSeamRecord(of: declaration, variant: variant, in: world, lazilyInstantiatedInstanceProperties: instanceProperties, typesDeclaredEscaping: escaping, children: children))
			case .receivesOnlyIfAvailable:
				try .built(Self.receivesOnlyIfAvailableRecord(
					of: declaration,
					variant: variant,
					in: world,
					answers: onlyIfAvailableAnswers,
					lazilyInstantiatedInstanceProperties: instanceProperties,
					typesDeclaredEscaping: escaping,
					children: children,
				))
			case .unavailableDependency:
				try .alias(Self.unavailableDependencyRecord(of: declaration, in: world))
			case .rename:
				try .alias(Self.renameRecord(of: declaration, variant: variant, in: world, answers: onlyIfAvailableAnswers))
			case .mockRename:
				try .alias(Self.mockRenameRecord(of: declaration, variant: variant, in: world, answers: onlyIfAvailableAnswers))
			case .mockConstruction:
				try .built(Self.mockConstructionRecord(of: declaration, variant: variant, in: world, unavailableProperties: onlyIfAvailableAnswers.unavailableProperties(of: variant), lazilyInstantiatedInstanceProperties: instanceProperties, receivesBoundAgain: mockReceivesBoundAgain[Int(variant)], typesDeclaredEscaping: escaping, children: children))
			case .mockUnavailableDependency:
				try .alias(Self.mockUnavailableDependencyRecord(of: declaration, in: world))
			case .mockErased:
				try .built(Self.mockErasedRecord(of: declaration, variant: variant, in: world, unavailableProperties: onlyIfAvailableAnswers.unavailableProperties(of: variant), lazilyInstantiatedInstanceProperties: instanceProperties, receivesBoundAgain: mockReceivesBoundAgain[Int(variant)], typesDeclaredEscaping: escaping, children: children))
			case .publicMockCall:
				try .built(Self.publicMockCallRecord(of: declaration, variant: variant, in: world, receivesBoundAgain: mockReceivesBoundAgain[Int(variant)], typesDeclaredEscaping: escaping, children: children))
			}
			typesDeclaredEscaping[Int(variant)] = escaping
			records[Int(variant)] = record
			let place: GeneratedCode = switch record {
			case let .alias(aliasRecord):
				// A place written as text: the engine copies it as written.
				.place(PlacePlan(code: .text(aliasRecord.text), record: record))
			case .built, .closer:
				.place(PlacePlan(code: .empty, record: record))
			}
			// A mock's `@Sendable` function captures its override from a local its parent's body binds just before it.
			places[Int(variant)] = if let binding = Self.mockOverridesBindingPlace(of: declaration, record: record, in: world) {
				.sequence([.place(PlacePlan(code: .empty, record: .built(binding))), place])
			} else {
				place
			}
		}
		// Last, so that a world refused for a kind reports that kind first.
		for declaration in 0..<Int32(declarationCount) where Self.owesFacts(declaration, in: world) {
			throw NodeRecordRefusal.readAnsweredTwoWays
		}
		let rootCalls = world.calls(of: 0)
		rootBody = order.edgeIndices(of: 0).map { edgeIndex in
			.indented(places[Int(rootCalls[rootCalls.startIndex + edgeIndex])] ?? .empty, by: TypeKeyBody.rootStatementIndentation)
		}
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

	/// Every refusal `world` holds, each once, in the order of `NodeRecordRefusal`'s cases: what a test reports of a world, so
	/// that each stage counts the worlds it frees.
	static func refusals(in world: some NodeRecordSources, seamTree: DependencyTreeGenerator.RootScopeInfo.SeamTree? = nil, outerDeclarations: [Property] = [], declaredTypeNames: DeclaredTypeNames?) -> [NodeRecordRefusal] {
		var refusals = Set<NodeRecordRefusal>()
		for declaration in 0..<Int32(world.declarationCount) {
			refusals.formUnion(kindAndRefusals(of: declaration, in: world).refusals)
			if owesFacts(declaration, in: world) {
				refusals.insert(.readAnsweredTwoWays)
			}
			do {
				try checkReadsNoSeamRootValue(of: seamTree, declaration, in: world)
			} catch {
				refusals.insert(error)
			}
			do {
				try checkForwardsBuiltTypesProperties(declaration, in: world, declaredTypeNames: declaredTypeNames)
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
			_ = try OnlyIfAvailableAnswers(world: world, rootParameters: seamTree?.parameters ?? outerDeclarations)
		} catch {
			refusals.insert(error)
		}
		let answeringDeclarations = DeclarationsAnsweringReads(world: world)
		if answeringDeclarations.sendableFunctionCapturesWrapper {
			refusals.insert(.sendableFunctionCapturesWrapper)
		}
		if answeringDeclarations.renameReadsWrappersInstance {
			refusals.insert(.lazy)
		}
		return NodeRecordRefusal.allCases.filter(refusals.contains)
	}

	/// Whether a producer of the facts still owes `declaration`'s answers (`TypeFactsWorld.owedFacts(of:)`), which refuses
	/// its world as `readAnsweredTwoWays`. The mock root's bits are not owed where a test lays mock roots out from their
	/// records (`NodeRecordsObservation.laysOutMockRoots`), a mode no run of `generate` turns on; every run of it refuses
	/// every mock world.
	private static func owesFacts(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		let owedOnlyOutsideTests: TypeFactsOwedFacts = NodeRecordsObservation.laysOutMockRoots ? [.mockRootPin, .mockRootRecord, .mockRootBinding] : []
		return !world.owedFacts(of: declaration).subtracting(owedOnlyOutsideTests).isEmpty
	}

	/// Refuses `declaration`'s world where its type reads what a seam's root is handed in a way node records do not write:
	/// as `lazy`, a receive or a rename of one of the instances of `LazilyInstantiated` properties the root is handed,
	/// which its tree reads through the wrapper and the records would read as a binding of the label; as `renameOrHole`,
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

	/// Refuses `declaration`'s world where it is an `ErasedInstantiator` or a `SendableErasedInstantiator` whose first
	/// generic argument is not the `@Forwarded` properties of the type it builds: an error the tree reports where it builds
	/// the place (`ErasedInstantiatorForwardedPropertiesMismatchError`), which the records cannot, so the world keeps its
	/// tree, in a run no test observes too, which builds no tree beside a root's records. A fill's place, which the tree
	/// checks seeing through its hole's modules, is checked here without them: its world is refused as a fill's already.
	private static func checkForwardsBuiltTypesProperties(_ declaration: DeclarationID, in world: some NodeRecordSources, declaredTypeNames: DeclaredTypeNames?) throws(NodeRecordRefusal) {
		switch world.kind(of: declaration) {
		case .erasedInstantiator, .sendableErasedInstantiator:
			guard let declaredTypeNames, let property = world.property(of: declaration) else { return }
			let forwardsBuiltTypesProperties = property.firstGenericMatchesForwardedProperties(of: world.scope(of: declaration).instantiable, declaringModuleNames: [], declaredTypeNames: declaredTypeNames)
			guard forwardsBuiltTypesProperties else { throw .erased }
		case .constant, .instantiator, .sendableInstantiator, .lazy, .sendableLazy, .alias, .hole:
			break
		}
	}

	/// The kind of record `declaration` is made as, or the first refusal it holds (`kindAndRefusals(of:in:)`).
	private static func kind(of declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) -> NodeRecordKind {
		let (kind, refusals) = kindAndRefusals(of: declaration, in: world)
		if let refusal = refusals.first {
			throw refusal
		}
		return kind
	}

	/// The kind `declaration` is made as, and every refusal it holds: those of the claim a kind makes of it, and
	/// every check of `builtByInitializer` the claim does not discharge (`refusalsOfBuiltByInitializer(_:in:)`). A node of two kinds,
	/// one claimed, is still refused for the other.
	private static func kindAndRefusals(of declaration: DeclarationID, in world: some NodeRecordSources) -> (kind: NodeRecordKind, refusals: [NodeRecordRefusal]) {
		let claim = claim(of: declaration, in: world)
		let discharged = claim?.discharges ?? []
		let refusals = (claim?.refusals ?? []) + refusalsOfBuiltByInitializer(declaration, in: world).filter { !discharged.contains($0) }
		return (claim?.kind ?? .builtByInitializer, refusals)
	}

	/// What a kind claims of `declaration`, or `nil` where none does. Each production kind is one term of the production
	/// chain, after the test's, in the order of `NodeRecordKind`'s cases, calling its file's classifier, which returns
	/// `nil` for a node not of its kind: `?? <kind>Claim(of: declaration, in: world)`. A mock world's nodes are the
	/// mock writer's alone, so no production kind's record, which reads no override, is made of one.
	private static func claim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		// A test's claim comes first, so that it can claim a node another kind would.
		guard !world.isMockWorld else {
			return publicMockCallClaim(of: declaration, in: world)
				?? testClaim(of: declaration, in: world)
				// Asked last: it claims every node of a mock root's world that no kind before it claimed.
				?? mockConstructionClaim(of: declaration, in: world)
		}
		return testClaim(of: declaration, in: world)
			?? inlineSeamClaim(of: declaration, in: world)
			?? unavailableDependencyClaim(of: declaration, in: world)
			?? receivesOnlyIfAvailableClaim(of: declaration, in: world)
			?? renameClaim(of: declaration, in: world)
			?? erasedClaim(of: declaration, in: world)
			?? lazyClaim(of: declaration, in: world)
			?? sendableClaim(of: declaration, in: world)
	}

	/// The claim a test makes of `declaration` by its type's name (`NodeRecordsObservation.claimsForTesting`).
	private static func testClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		NodeRecordsObservation.claimsForTesting[world.scope(of: declaration).instantiable.concreteInstantiable.asSource].map { discharged in
			NodeRecordClaim(kind: .builtByInitializer, discharges: Set(discharged.compactMap(NodeRecordRefusal.init(rawValue:))))
		}
	}
}

/// What a kind claims of a node (`NodeRecords.claim(of:in:)`): the kind its record is made as, the refusals of
/// `refusalsOfBuiltByInitializer(_:in:)` the kind discharges, which are the kinds it makes, and any refusal of its own the node holds, of its
/// kind but a shape it does not make yet.
struct NodeRecordClaim: Sendable {
	let kind: NodeRecordKind
	let discharges: Set<NodeRecordRefusal>
	var refusals = [NodeRecordRefusal]()
}

/// The kinds of node `NodeRecords` makes a record of. Each is made by one file of this folder, `NodeRecords+<Kind>.swift`,
/// which holds its classifier (whether a node is of the kind) and its record. A world holding a node of no kind is
/// refused whole.
enum NodeRecordKind: Sendable {
	/// A constant or an `Instantiator` built by its type's initializer or `instantiate()`, off every cycle, with nothing
	/// received only if available, renamed or filled in its scope.
	case builtByInitializer
	/// A seam of another module built inline, because no module SafeDI knows generates its initializer, and otherwise a
	/// node `builtByInitializer` makes: its line ends with the comment that says why (`NodeRecords+InlineSeam.swift`).
	case inlineSeam
	/// A property instantiated only if available that no declaration fulfills, bound to `nil` and written as text
	/// (`NodeRecords+UnavailableDependency.swift`).
	case unavailableDependency
	/// A node that would be of kind `builtByInitializer` but that its type receives a property only if available, which its
	/// construction is passed where the variant's calls find it available, and `nil` where not (`OnlyIfAvailableAnswers`).
	case receivesOnlyIfAvailable
	/// A rename a scope declares (`@Received(fulfilledByDependencyNamed:ofType:)`), written as text: bound from its fulfilling
	/// property, or, only if available, to `nil` where no declaration it reads is available (`NodeRecords+Rename.swift`).
	case rename
	/// An `ErasedInstantiator`, or a constant or an `Instantiator` erased to its property's type (`NodeRecords+Erased.swift`).
	case erased
	/// A `LazilyInstantiated`, erased or not (`NodeRecords+Lazy.swift`).
	case lazy
	/// A `SendableInstantiator`, erased or not, or a `SendableLazilyInstantiated` (`NodeRecords+Sendable.swift`).
	case sendable
	/// A node of a mock root's world that `builtByInitializer` would make in a production root's, which reads its override before it
	/// calls its type's initializer (`NodeRecords+MockConstruction.swift`).
	case mockConstruction
	/// A node of a mock root's world that would be of kind `mockConstruction` but that it is erased: an `ErasedInstantiator`,
	/// or a constant, an `Instantiator` or a `LazilyInstantiated` erased to its property's type, whose override returns the property's type
	/// (`NodeRecords+MockErased.swift`).
	case mockErased
	/// A constant or an `Instantiator` built by a call of another module's public mock, which passes the called mock its own
	/// `SafeDIOverrides` and fills no builder (`NodeRecords+PublicMockCall.swift`).
	case publicMockCall
	/// A property instantiated only if available that no declaration fulfills, in a mock root's world: bound to the
	/// override `mock()` takes of it, or to `nil` where it takes none (`NodeRecords+MockUnavailableDependency.swift`).
	case mockUnavailableDependency
	/// A rename of a mock root's world, which reads no override: `rename`'s record, mapped as the mock's walk maps an erased
	/// rename only if available (`NodeRecords+MockRename.swift`).
	case mockRename
}
