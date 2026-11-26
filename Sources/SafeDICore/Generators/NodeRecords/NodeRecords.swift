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
	/// The node is built as a lazily instantiated or `@Sendable` property, or erased.
	case kind
	/// The node's type declares a rename, a hole, or an instantiated dependency its scope does not build.
	case renameOrHole
	/// The node's call passes fills.
	case fill
	/// The node is on a cycle.
	case cycle
	/// The node's type receives a property only if available, or holds a lazily instantiated instance.
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
		for declaration in 0..<Int32(declarationCount) {
			try Self.checkStageOneKind(of: declaration, in: world)
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
			let record = try Self.record(of: declaration, in: world, typesDeclaredEscaping: escaping, children: children)
			typesDeclaredEscaping[Int(variant)] = escaping
			records[Int(variant)] = record
			places[Int(variant)] = .place(PlacePlan(code: .empty, record: .built(record)))
		}
		let rootCalls = world.calls(of: 0)
		rootBody = order.edgeIndices(of: 0).map { edgeIndex in
			.indented(places[Int(rootCalls[rootCalls.startIndex + edgeIndex])] ?? .empty, by: TypeKeyBody.rootStatementIndentation)
		}
		self.records = records
	}

	/// The record of `declaration`'s place in `variant`'s body. The root, variant 0, has none.
	func record(of _: DeclarationID, variant: VariantID) -> BuiltPlaceRecord? {
		records[Int(variant)]
	}

	/// The root's body: a place for each of the root's children, in the order the root builds them, indented as a root's
	/// statements are.
	let rootBody: [GeneratedCode]

	/// How many records were made: one per variant but the root's.
	var recordCount: Int {
		records.count - 1
	}

	/// By variant.
	private let records: [BuiltPlaceRecord?]

	private static func checkStageOneKind(of declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) {
		switch world.construction(of: declaration) {
		case .initializer:
			break
		case .handWrittenMock, .seamCall, .publicMockCall, .constructionFunction, .fill:
			throw .construction
		}
		switch world.kind(of: declaration) {
		case .constant, .instantiator:
			break
		case .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator, .lazy, .sendableLazy, .alias, .hole:
			throw .kind
		}
		guard !world.isOnCycle(declaration) else { throw .cycle }
		let scope = world.scope(of: declaration)
		guard !scope.isUnavailableDependency, scope.builtInlineSeamComment == nil else { throw .unavailableOrInlineSeam }
		guard scope.holeArguments.isEmpty else { throw .fill }
		guard scope.instantiatedDependenciesNotGenerated.isEmpty else { throw .renameOrHole }
		for propertyToGenerate in scope.propertiesToGenerate {
			switch propertyToGenerate {
			case let .instantiated(_, _, erasedToConcreteExistential, _):
				guard !erasedToConcreteExistential else { throw .kind }
			case .hole, .aliased:
				throw .renameOrHole
			}
		}
		guard scope.declaredLazilyInstantiatedInstanceProperties.isEmpty, scope.forwardedLazilyInstantiatedInstanceProperties.isEmpty else { throw .onlyIfAvailable }
		for dependency in scope.instantiable.dependencies {
			switch dependency.source {
			case .instantiated, .forwarded, .received(onlyIfAvailable: false):
				break
			case .received(onlyIfAvailable: true):
				throw .onlyIfAvailable
			case .aliased:
				throw .renameOrHole
			}
		}
		guard declaration == 0 || scope.instantiable.initializer != nil else { throw .noInitializer }
	}

	private static func record(
		of declaration: DeclarationID,
		in world: some NodeRecordSources,
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
	) throws -> BuiltPlaceRecord {
		let instantiable = world.scope(of: declaration).instantiable
		// Every node but the root is built as a property, and has an initializer (`checkStageOneKind(of:in:)`).
		guard let property = world.property(of: declaration), let initializer = instantiable.initializer else { throw NodeRecordRefusal.noInitializer }
		// Throws what the tree's construction of the same place throws, which the `@Instantiable` macro rejects first.
		let arguments = try initializer.createInitializerArguments(given: instantiable.dependencies)
		let isExtension = instantiable.declarationType.isExtension
		let isInstantiator = switch world.kind(of: declaration) {
		case .instantiator, .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator:
			true
		case .constant, .lazy, .sendableLazy, .alias, .hole:
			false
		}
		return BuiltPlaceRecord(
			property: property,
			isErased: false,
			concreteType: instantiable.concreteInstantiable,
			isExtension: isExtension,
			target: isExtension ? .instantiate(instantiable.concreteInstantiable) : .initializer(instantiable.concreteInstantiable),
			arguments: arguments.map {
				PlaceRead(argumentLabel: $0.argument.label, label: $0.dependency.property.label, property: $0.dependency.property, source: $0.argument.source)
			},
			forwardedProperties: instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted(),
			cycleParameters: [],
			callCycleArguments: [],
			functionName: ScopeGenerator.functionName(toBuildPropertyNamed: property.label),
			isSendable: false,
			typesDeclaredEscaping: typesDeclaredEscaping,
			lineEnd: "",
			// An `Instantiator` always declares its builder function; a constant only where its body has a statement.
			hasFunction: isInstantiator || !children.isEmpty,
			children: children,
			node: PlanNode(),
		)
	}
}
