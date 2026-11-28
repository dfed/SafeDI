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

/// The position of a record in one `ScopeTable`. It means nothing outside its table.
struct ScopeID: Hashable, Sendable {
	fileprivate let index: Int32

	fileprivate init(_ index: Int) {
		self.index = Int32(truncatingIfNeeded: index)
	}
}

/// What construction reads of a `Scope`, frozen once its map is complete: the scopes it builds are named by their position
/// in the table that holds it, and every value `Scope` computes on first read is computed when the record is made. Nothing
/// in it changes, so a task that builds a tree from it shares it with every other.
final class ScopeRecord: Sendable {
	/// A property the scope builds, as `Scope.PropertyToGenerate` holds it, with the scope it builds named by its position.
	enum PropertyToGenerate: Sendable {
		/// A property the scope instantiates, with its ID in the table's interner.
		case instantiated(Property, ScopeID, erasedToConcreteExistential: Bool, id: PropertyID)
		case hole(Property, erasedToConcreteExistential: Bool)
		case aliased(
			Property,
			fulfilledBy: Property,
			erasedToConcreteExistential: Bool,
			onlyIfAvailable: Bool,
			declarationReference: String,
		)
	}

	/// How a call passes the builder for one place, as `Scope.HoleArgument` holds it, with the scope of a fill named by its
	/// position and the IDs its tree is built with.
	enum HoleArgument: Sendable {
		case fill(SeamSignature.Hole, ScopeID, FillContext)
		case passUp(SeamSignature.Hole)
	}

	/// What a fill's tree is built with, interned when the call's record is made: the ID of the hole's property, which the
	/// fill builds, and the stack of the seam path the fill is built beneath (`SeamSignature.Hole.fillPropertyStack`).
	struct FillContext: Sendable {
		let propertyID: PropertyID
		let contextStack: ContextStack
	}

	/// The ID of `instantiable`'s concrete type in the table's interner.
	let concreteTypeID: TypeID

	/// See `Scope.instantiable`.
	let instantiable: Instantiable
	/// See `Scope.builtInlineSeamComment`.
	let builtInlineSeamComment: String?
	/// See `Scope.isUnavailableDependency`.
	let isUnavailableDependency: Bool
	/// See `Scope.seamCall`.
	let seamCall: SeamCall?
	/// See `Scope.publicMockCall`.
	let publicMockCall: PublicMockCall?
	/// See `Scope.propertiesToGenerate`.
	let propertiesToGenerate: [PropertyToGenerate]
	/// See `Scope.holeArguments`.
	let holeArguments: [HoleArgument]
	/// See `Scope.fillReceivedProperties`.
	let fillReceivedProperties: [SeamSignature.Hole.Site: Set<Property>]
	/// See `Scope.fillLabelsReadOnlyIfAvailable`.
	let fillLabelsReadOnlyIfAvailable: [SeamSignature.Hole.Site: Set<String>]
	/// See `Scope.propertiesToDeclare`.
	let propertiesToDeclare: Set<Property>
	/// See `Scope.instantiatedDependenciesNotGenerated`.
	let instantiatedDependenciesNotGenerated: [Dependency]
	/// See `Scope.forwardedLazilyInstantiatedInstanceProperties`.
	let forwardedLazilyInstantiatedInstanceProperties: [Property]
	/// See `Scope.declaredLabels`.
	let declaredLabels: Set<String>
	/// See `Scope.sortedDeclaredPropertyForms`.
	let sortedDeclaredPropertyForms: [(property: Property, forms: Set<Property>)]
	/// See `Scope.declaredLazilyInstantiatedInstanceProperties`.
	let declaredLazilyInstantiatedInstanceProperties: Set<Property>
	/// See `Scope.createdBindings`.
	private let createdBindings: [Property: Property]

	/// See `Scope.calledBuilders`.
	var calledBuilders: CalledBuilders? {
		seamCall?.calledBuilders ?? publicMockCall?.calledBuilders
	}

	/// The property this scope's type creates – instantiates, is forwarded, or declares by an alias – that a dependency
	/// of the type reads for `property`, which it receives only if available: the first form of `property` (see
	/// `Property.formsReadByOnlyIfAvailableReceive`) that a created property provides (see
	/// `CycleParameter.forms(providedBy:)`). `nil` when the type creates none, and the dependency reads the nearest
	/// declaration above the scope.
	func createdBinding(of property: Property) -> Property? {
		for form in property.formsReadByOnlyIfAvailableReceive {
			if let binding = createdBindings[form] {
				return binding
			}
		}
		return nil
	}

	fileprivate init(freezing scope: Scope, concreteTypeID: TypeID, propertiesToGenerate: [PropertyToGenerate], holeArguments: [HoleArgument]) {
		instantiable = scope.instantiable
		self.concreteTypeID = concreteTypeID
		builtInlineSeamComment = scope.builtInlineSeamComment
		isUnavailableDependency = scope.isUnavailableDependency
		seamCall = scope.seamCall
		publicMockCall = scope.publicMockCall
		self.propertiesToGenerate = propertiesToGenerate
		self.holeArguments = holeArguments
		fillReceivedProperties = scope.fillReceivedProperties
		fillLabelsReadOnlyIfAvailable = scope.fillLabelsReadOnlyIfAvailable
		propertiesToDeclare = scope.propertiesToDeclare
		instantiatedDependenciesNotGenerated = scope.instantiatedDependenciesNotGenerated
		forwardedLazilyInstantiatedInstanceProperties = scope.forwardedLazilyInstantiatedInstanceProperties
		declaredLabels = scope.declaredLabels
		sortedDeclaredPropertyForms = scope.sortedDeclaredPropertyForms
		declaredLazilyInstantiatedInstanceProperties = scope.declaredLazilyInstantiatedInstanceProperties
		createdBindings = scope.createdBindings
	}
}

/// One scope map, frozen: a record per scope, found by its `ScopeID`, and the map's keys. Built once, serially, from a
/// complete map (`FrozenScopeMap`), and read by every tree built from that map.
struct ScopeTable: Sendable {
	fileprivate init(interner: ConstructionInterner) {
		self.interner = interner
	}

	/// The IDs the records hold, and what each projects: the snapshot published once the table was made, which holds every
	/// ID its records hold.
	fileprivate(set) var interner: ConstructionInterner

	/// The record at `id`, which this table gave.
	subscript(id: ScopeID) -> ScopeRecord {
		let index = Int(id.index)
		if !overlaidRecords.isEmpty, let record = overlaidRecords[index] {
			return record
		} else {
			return storage.records[index]
		}
	}

	/// How many records the table holds: `storage`'s, then those `overlaidRecords` holds after them.
	fileprivate(set) var count = 0

	/// The position of the scope the map held under `key`, or `nil` when it held none: for a signature pass's table, when
	/// the pass's map holds no `key`, whatever the base holds.
	func id(forKey key: TypeDescription) -> ScopeID? {
		if let reachableKeys, !reachableKeys.contains(key) {
			nil
		} else {
			storage.idByKey[key]
		}
	}

	/// The records of the map a table was frozen from, and that map's keys, each with the position of its scope: shared,
	/// never copied, by every table made from it (a signature pass's, a root's), each of which holds only what it adds.
	fileprivate final class Storage: Sendable {
		init(records: [ScopeRecord], idByKey: [TypeDescription: ScopeID]) {
			self.records = records
			self.idByKey = idByKey
		}

		/// The records, in `ScopeID` order.
		let records: [ScopeRecord]
		/// For lookup only: never iterated, but by the tests' projection.
		let idByKey: [TypeDescription: ScopeID]
	}

	fileprivate var storage = Storage(records: [], idByKey: [:])
	/// The records a table holds beyond `storage`, by position: those a signature pass puts in place of the base's
	/// (`FrozenScopeMap.overlaying`), and those of the scopes given positions after `storage`'s, which a freeze makes here
	/// first (`FrozenScopeMap.freezePendingScopes`) and a map's freeze then moves into `storage`.
	fileprivate var overlaidRecords = [Int: ScopeRecord]()
	/// For a signature pass's table, the keys the pass's map holds, which its reachable types fulfill
	/// (`FrozenScopeMap.overlaying`): a key outside them names no record. `nil` for a table frozen from a map, whose keys are its own.
	fileprivate(set) var reachableKeys: Set<TypeDescription>?
}

/// A complete scope map frozen into a `ScopeTable`, with what names each of its scopes there: used where the map lives, to
/// freeze a root's scope, which is in no map, against the table.
///
/// The order of the records decides nothing a tree built from them holds, but it is fixed all the same, so that a table is
/// the same however the map's entries arrive:
/// 1. every scope a key of the map reaches, ordered by its concrete type, then by the first of the keys that reach it – one key
///    reaches one scope, so two scopes never share it, and the order is total (`precedesInScopeOrder`);
/// 2. then every scope a record refers to that no key reaches, in the order the records, taken in `ScopeID` order, first refer
///    to it: in `propertiesToGenerate`'s order, then in `holeArguments`'. Every map today builds its scopes' children from its
///    own entries, so this adds none; the rule makes the order total either way.
struct FrozenScopeMap {
	/// Freezes the map whose entries are `entries`, in whatever order they arrive.
	/// - Parameter internerSpace: The generator's ID space, in which the records' values are interned.
	init(freezing entries: some Sequence<(key: TypeDescription, scope: Scope)>, interningIn internerSpace: ConstructionInternerSpace) {
		self.internerSpace = internerSpace
		table = ScopeTable(interner: internerSpace.snapshot())
		var entries = Array(entries)
		if let entryOrder = ScopeTableObservation.entryOrder {
			entries = entryOrder(entries.count).map { entries[$0] }
		}
		var firstKeyByScope = [ObjectIdentifier: (key: TypeDescription, scope: Scope)]()
		for entry in entries {
			let identifier = ObjectIdentifier(entry.scope)
			if let firstKey = firstKeyByScope[identifier]?.key, !TypeDescription.precedesInScopeOrder(entry.key, firstKey) {
				continue
			}
			firstKeyByScope[identifier] = entry
		}
		let keyedScopes = firstKeyByScope.values.map { entry in
			let concreteType = entry.scope.instantiable.concreteInstantiable
			return (concreteType: concreteType, concreteTypeOrder: TypeDescription.ScopeOrderKey(concreteType), keyOrder: TypeDescription.ScopeOrderKey(entry.key), scope: entry.scope)
		}.sorted { lhs, rhs in
			if lhs.concreteType == rhs.concreteType {
				lhs.keyOrder.precedes(rhs.keyOrder)
			} else {
				lhs.concreteTypeOrder.precedes(rhs.concreteTypeOrder)
			}
		}
		for (_, _, _, scope) in keyedScopes {
			_ = id(of: scope)
		}
		var idByKey = [TypeDescription: ScopeID]()
		for (key, scope) in entries {
			idByKey[key] = id(of: scope)
		}
		freezePendingScopes()
		// Every table made from this one shares what it holds now.
		table.storage = ScopeTable.Storage(records: (0..<table.count).compactMap { table.overlaidRecords[$0] }, idByKey: idByKey)
		table.overlaidRecords = [:]
		table.interner = internerSpace.snapshot()
		scopeStorage = ScopeStorage(scopes: addedScopes, idByScope: addedIDByScope)
		baseScopeCount = addedScopes.count
		addedScopes = []
		addedIDByScope = [:]
		if let observer = ScopeTableObservation.observer {
			observer(table.projection)
		}
	}

	/// What a task of a parallel signature computation makes this map again from, in an ID space of its own: the table,
	/// and a copy of the space's IDs as they are now. The map's own scopes are not carried: a signature pass's map builds
	/// scopes of its own, which name the base's positions by key (`overlaying`), never by identity.
	struct Base: Sendable {
		fileprivate let table: ScopeTable
		fileprivate let scopeCount: Int
		fileprivate let builder: ConstructionInterner.Builder
	}

	/// This map as a `Base`.
	var base: Base {
		Base(table: table, scopeCount: baseScopeCount, builder: internerSpace.copyOfBuilder())
	}

	/// The map `base` was taken of, in an ID space of its own whose IDs start as the base's did.
	init(base: Base) {
		internerSpace = ConstructionInternerSpace(copying: base.builder)
		table = base.table
		baseScopeCount = base.scopeCount
	}

	/// The ID space this map interns in.
	var space: ConstructionInternerSpace {
		internerSpace
	}

	/// The frozen table.
	private(set) var table: ScopeTable
	/// The generator's ID space, in which every freeze of this map and of the tables made from it interns its records' values.
	private let internerSpace: ConstructionInternerSpace

	/// The table of one signature pass, from this base, frozen once from a seam world in which every seam of the declaration
	/// map is built and not called: each record of a type that is no seam depends on the declarations alone, so it is the
	/// base's; the record of each seam call the pass's seams reach from `rootScopes` is the pass's own, made from
	/// `passScopeMap`'s scope that calls it, its fills found by `fulfillingKey`, then looked up among the pass map's keys
	/// alone (`ScopeTable.reachableKeys`), since a place whose fulfilling type the pass does not reach is passed up. A key
	/// the pass map lacks names no record. Construction reaches a record only through the identifiers of the records above
	/// it, from a seam's root down its instantiated children and the fills of its calls (`scopesReached(from:…)`), so a
	/// call the pass's seams do not reach keeps the base's record, which nothing of the pass reads: the pass map of a seam
	/// that calls a chain of seams holds the call of every seam down the chain, and recording each again made a chain's
	/// passes grow with the cube of its length.
	/// The overlay oracle checks, over the seam corpus, that each reached key's record equals the record frozen from the
	/// pass's map.
	func overlaying(
		passScopeMap: [TypeDescription: Scope],
		rootScopes: [Scope],
		fulfillingKey: (SeamSignature.Hole) -> TypeDescription?,
	) -> FrozenScopeMap {
		var frozenScopeMap = self
		frozenScopeMap.table.reachableKeys = Set(passScopeMap.keys)
		var passEntries = Array(passScopeMap)
		if let entryOrder = ScopeTableObservation.entryOrder {
			passEntries = entryOrder(passEntries.count).map { passEntries[$0] }
		}
		// A scope the pass's map holds under several keys names the base's position of the first of them in
		// `precedesInScopeOrder`, as a freeze orders a scope by its first key, so no order the entries arrive in decides it.
		var firstKeyByScope = [ObjectIdentifier: TypeDescription]()
		for (key, scope) in passEntries {
			guard let id = table.storage.idByKey[key] else { continue }
			let identifier = ObjectIdentifier(scope)
			if let firstKey = firstKeyByScope[identifier], !TypeDescription.precedesInScopeOrder(key, firstKey) {
				continue
			}
			firstKeyByScope[identifier] = key
			frozenScopeMap.addedIDByScope[identifier] = id
		}
		var callScopeByID = [ScopeID: Scope]()
		for scope in Self.scopesReached(from: rootScopes, passScopeMap: passScopeMap, fulfillingKey: fulfillingKey) where scope.seamCall != nil {
			if let id = frozenScopeMap.addedIDByScope[ObjectIdentifier(scope)] {
				callScopeByID[id] = scope
			}
		}
		// The pass's scopes are held for as long as their identifiers name positions.
		frozenScopeMap.overlaidScopes = Array(passScopeMap.values)
		for (id, scope) in callScopeByID.sorted(by: { $0.key.index < $1.key.index }) {
			let holeArguments = (scope.seamCall?.holes ?? []).map { hole -> ScopeRecord.HoleArgument in
				if let key = fulfillingKey(hole), let fillID = frozenScopeMap.table.id(forKey: key) {
					.fill(hole, fillID, frozenScopeMap.fillContext(of: hole))
				} else {
					.passUp(hole)
				}
			}
			frozenScopeMap.table.overlaidRecords[Int(id.index)] = frozenScopeMap.recordCountingMisses(freezing: scope, holeArguments: holeArguments)
		}
		if let overlaidCallRecords = ScopeTableObservation.overlaidCallRecords {
			overlaidCallRecords(callScopeByID.values.map(\.instantiable.concreteInstantiable.asSource).sorted())
		}
		frozenScopeMap.freezePendingScopes()
		frozenScopeMap.table.interner = internerSpace.snapshot()
		if let observer = ScopeTableObservation.observer {
			observer(frozenScopeMap.table.projection)
		}
		return frozenScopeMap
	}

	/// Every scope construction can reach from `rootScopes` in a pass: each instantiated child, and, from a seam call, the
	/// pass map's scope of each place's fulfilling type, which the call's record names as a fill. Walked with an explicit
	/// stack, since a tree can be as deep as the module has types; each scope once.
	static func scopesReached(
		from rootScopes: [Scope],
		passScopeMap: [TypeDescription: Scope],
		fulfillingKey: (SeamSignature.Hole) -> TypeDescription?,
	) -> [Scope] {
		var reached = [Scope]()
		var visited = Set<ObjectIdentifier>()
		var stack = rootScopes
		while let scope = stack.popLast() {
			guard visited.insert(ObjectIdentifier(scope)).inserted else { continue }
			reached.append(scope)
			for propertyToGenerate in scope.propertiesToGenerate {
				switch propertyToGenerate {
				case let .instantiated(_, childScope, _):
					stack.append(childScope)
				case .hole, .aliased:
					break
				}
			}
			for hole in scope.seamCall?.holes ?? [] {
				if let key = fulfillingKey(hole), let fillScope = passScopeMap[key] {
					stack.append(fillScope)
				}
			}
		}
		return reached
	}

	/// The record of `scope` – a mock root's or a seam's root, which is in no map, or a root the map holds – frozen against
	/// the table, and the table its children are found in: this one, with a record appended for each scope it refers to
	/// that the map did not hold.
	func freezing(rootScope scope: Scope) -> (table: ScopeTable, record: ScopeRecord) {
		var frozenScopeMap = self
		// What a root's promotion respells is interned with its record, before any tree is built from the table.
		let record = internerSpace.interning(countingMissesIn: .internedAtFreeze) { frozenScopeMap.record(freezing: scope) }
		frozenScopeMap.freezePendingScopes()
		frozenScopeMap.table.interner = internerSpace.snapshot()
		return (frozenScopeMap.table, record)
	}

	/// The scopes of the map this one was frozen from, in `ScopeID` order, with the position of each: shared, as
	/// `ScopeTable.Storage` is. Holding them keeps each identifier naming its own scope.
	private final class ScopeStorage {
		init(scopes: [Scope], idByScope: [ObjectIdentifier: ScopeID]) {
			self.scopes = scopes
			self.idByScope = idByScope
		}

		let scopes: [Scope]
		let idByScope: [ObjectIdentifier: ScopeID]
	}

	private var scopeStorage = ScopeStorage(scopes: [], idByScope: [:])
	/// The number of positions `scopeStorage` names, which a map made from a `Base` names without holding the scopes.
	private var baseScopeCount = 0
	/// The scopes given positions after `scopeStorage`'s, in `ScopeID` order.
	private var addedScopes = [Scope]()
	/// The positions of `addedScopes`, and of a signature pass's scopes, which name the base's (`overlaying`).
	private var addedIDByScope = [ObjectIdentifier: ScopeID]()
	/// A signature pass's scopes, held for as long as their identifiers name positions (`overlaying`).
	private var overlaidScopes = [Scope]()

	/// The position of `scope`, given to it now when it has none.
	private mutating func id(of scope: Scope) -> ScopeID {
		let identifier = ObjectIdentifier(scope)
		if let id = addedIDByScope[identifier] ?? scopeStorage.idByScope[identifier] {
			return id
		} else {
			let id = ScopeID(baseScopeCount + addedScopes.count)
			addedScopes.append(scope)
			addedIDByScope[identifier] = id
			return id
		}
	}

	/// Makes the record of every scope given a position but no record yet, in `ScopeID` order; each can give more positions.
	private mutating func freezePendingScopes() {
		while table.count < baseScopeCount + addedScopes.count {
			table.overlaidRecords[table.count] = recordCountingMisses(freezing: addedScopes[table.count - baseScopeCount])
			table.count += 1
		}
	}

	/// The record of `scope`, giving a position to each scope it refers to: with `holeArguments` where they are given.
	private mutating func record(freezing scope: Scope, holeArguments givenHoleArguments: [ScopeRecord.HoleArgument]? = nil) -> ScopeRecord {
		var propertiesToGenerate = [ScopeRecord.PropertyToGenerate]()
		propertiesToGenerate.reserveCapacity(scope.propertiesToGenerate.count)
		for propertyToGenerate in scope.propertiesToGenerate {
			switch propertyToGenerate {
			case let .instantiated(property, childScope, erasedToConcreteExistential):
				propertiesToGenerate.append(.instantiated(property, id(of: childScope), erasedToConcreteExistential: erasedToConcreteExistential, id: internerSpace.intern(property)))
			case let .hole(property, erasedToConcreteExistential, _):
				propertiesToGenerate.append(.hole(property, erasedToConcreteExistential: erasedToConcreteExistential))
			case let .aliased(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference):
				propertiesToGenerate.append(.aliased(property, fulfilledBy: fulfillingProperty, erasedToConcreteExistential: erasedToConcreteExistential, onlyIfAvailable: onlyIfAvailable, declarationReference: declarationReference))
			}
		}
		let holeArguments = givenHoleArguments ?? scope.holeArguments.map { holeArgument -> ScopeRecord.HoleArgument in
			switch holeArgument {
			case let .fill(hole, fillScope):
				.fill(hole, id(of: fillScope), fillContext(of: hole))
			case let .passUp(hole):
				.passUp(hole)
			}
		}
		return ScopeRecord(freezing: scope, concreteTypeID: internerSpace.intern(scope.instantiable.concreteInstantiable), propertiesToGenerate: propertiesToGenerate, holeArguments: holeArguments)
	}

	/// The record of `scope`, as `record(freezing:holeArguments:)` makes it, counting what a leaf that calls a seam or
	/// another module's public mock interns as interned at freeze: its instantiable is the call's signature.
	private mutating func recordCountingMisses(freezing scope: Scope, holeArguments givenHoleArguments: [ScopeRecord.HoleArgument]? = nil) -> ScopeRecord {
		if scope.seamCall != nil || scope.publicMockCall != nil {
			internerSpace.interning(countingMissesIn: .internedAtFreeze) { record(freezing: scope, holeArguments: givenHoleArguments) }
		} else {
			record(freezing: scope, holeArguments: givenHoleArguments)
		}
	}

	/// What the tree of a fill of `hole` is built with, interned now.
	private func fillContext(of hole: SeamSignature.Hole) -> ScopeRecord.FillContext {
		internerSpace.interning(countingMissesIn: .excluded) { fillContextInterned(of: hole) }
	}

	private func fillContextInterned(of hole: SeamSignature.Hole) -> ScopeRecord.FillContext {
		ScopeRecord.FillContext(
			propertyID: internerSpace.intern(hole.property),
			contextStack: ContextStack(fillPropertyStack: hole.fillPropertyStack, concreteTypeStack: hole.fillConcreteTypeStack, interningIn: internerSpace),
		)
	}
}

extension ScopeTable {
	/// The record each of `keys` names, as text in which each scope it refers to is named by the smallest of `keys` that
	/// names it, never by its position, so that two tables of one pass that number their records differently compare
	/// (the overlay oracle). A key that names no record is left out.
	func projectionByKey(_ keys: some Collection<TypeDescription>) -> [TypeDescription: String] {
		var smallestKeyByID = [ScopeID: TypeDescription]()
		for key in keys {
			if let id = id(forKey: key), smallestKeyByID[id].map({ TypeDescription.precedesInScopeOrder(key, $0) }) ?? true {
				smallestKeyByID[id] = key
			}
		}
		func name(_ id: ScopeID) -> String {
			smallestKeyByID[id]?.asSource ?? "unkeyed \(self[id].instantiable.concreteInstantiable.asSource)"
		}
		var projectionByKey = [TypeDescription: String]()
		for key in keys {
			guard let id = id(forKey: key) else { continue }
			let record = self[id]
			var text = "\(record.instantiable.concreteInstantiable.asSource)"
			if let seamCall = record.seamCall {
				text.append(" calls \(seamCall.guardTypeName)")
			}
			for propertyToGenerate in record.propertiesToGenerate {
				switch propertyToGenerate {
				case let .instantiated(property, childID, _, _):
					text.append(" \(property.asSource) -> \(name(childID))")
				case let .hole(property, _):
					text.append(" \(property.asSource) -> hole")
				case let .aliased(property, fulfillingProperty, _, _, _):
					text.append(" \(property.asSource) = \(fulfillingProperty.asSource)")
				}
			}
			for holeArgument in record.holeArguments {
				switch holeArgument {
				case let .fill(hole, fillID, _):
					text.append(" fill \(hole.property.asSource) -> \(name(fillID))")
				case let .passUp(hole):
					text.append(" pass up \(hole.property.asSource)")
				}
			}
			for line in record.fillLabelsReadOnlyIfAvailable.map({ " \($0.key) reads only if available \($0.value.sorted())" }).sorted() {
				text.append(line)
			}
			projectionByKey[key] = text
		}
		return projectionByKey
	}
}

extension ScopeTable {
	/// The table as text: each record in `ScopeID` order, by its concrete type, the keys that reach it, and the positions of
	/// the scopes it builds and fills. Two freezes of one map give the same text exactly when they give the same table.
	fileprivate var projection: String {
		var keysByID = [ScopeID: [TypeDescription]]()
		for (key, id) in storage.idByKey {
			keysByID[id, default: []].append(key)
		}
		var lines = [String]()
		for index in 0..<count {
			let record = self[ScopeID(index)]
			var line = "\(index): \(record.instantiable.concreteInstantiable.asSource)"
			let keys = (keysByID[ScopeID(index)] ?? []).sorted(by: TypeDescription.precedesInScopeOrder)
			line.append(" keys [\(keys.map(\.asSource).joined(separator: ", "))]")
			for propertyToGenerate in record.propertiesToGenerate {
				switch propertyToGenerate {
				case let .instantiated(property, id, _, _):
					line.append(" \(property.label) -> \(id.index)")
				case let .hole(property, _):
					line.append(" \(property.label) -> hole")
				case let .aliased(property, fulfillingProperty, _, _, _):
					line.append(" \(property.label) = \(fulfillingProperty.label)")
				}
			}
			for case let .fill(hole, id, _) in record.holeArguments {
				line.append(" fill \(hole.property.label) -> \(id.index)")
			}
			lines.append(line)
		}
		return lines.joined(separator: "\n")
	}
}

/// What the tests read of each freeze, and how they order its entries: set by the tests, never by the tool.
public enum ScopeTableObservation {
	/// When set, each freeze takes its map's entries, and each signature pass's overlay its pass map's, in the order this
	/// returns, a permutation of the positions of as many entries as it is passed, so that a test can show a table does not
	/// depend on the order entries arrive in.
	@TaskLocal public static var entryOrder: (@Sendable (_ entryCount: Int) -> [Int])?
	/// Called with each table a map freezes, and each table a signature pass assembles (`FrozenScopeMap.overlaying`), as text
	/// (`ScopeTable.projection`).
	@TaskLocal public static var observer: (@Sendable (_ projection: String) -> Void)?
	/// When set, called once per seam signature pass with each key whose record in the pass's table, assembled from the base
	/// and the pass's overlay, differs from the record frozen from the pass's own map (by `ScopeTable.projectionByKey`), and
	/// each key outside the pass's map that names a record: the overlay oracle. Empty when the two agree.
	@TaskLocal public static var overlayOracle: (@Sendable (_ mismatches: [String]) -> Void)?
	/// Called once per seam signature pass with the types, by `asSource` in sorted order, of the seam calls whose records
	/// the pass's table takes from the pass's map rather than the base's (`FrozenScopeMap.overlaying`).
	@TaskLocal public static var overlaidCallRecords: (@Sendable (_ calledTypes: [String]) -> Void)?
}

extension TypeDescription {
	/// Whether `lhs` comes before `rhs` in the order of a `ScopeTable`'s records: by `<`, which compares spellings, and, for
	/// two unequal types of one spelling, which `<` leaves unordered, by their structure as `String(reflecting:)` spells it.
	/// A total order on unequal types, so no arrival order breaks a tie.
	static func precedesInScopeOrder(_ lhs: TypeDescription, _ rhs: TypeDescription) -> Bool {
		ScopeOrderKey(lhs).precedes(ScopeOrderKey(rhs))
	}

	/// A type with the spellings `precedesInScopeOrder` compares, spelled once, so that a sort of many types spells each
	/// once rather than at every comparison. Held only for the sort that makes it.
	struct ScopeOrderKey {
		init(_ type: TypeDescription) {
			self.type = type
			spellings = (withoutAny: type.withoutAny.asSource, asSource: type.asSource)
		}

		/// Whether this key's type comes before `other`'s in `precedesInScopeOrder`'s order: by `<`'s spellings, then, for
		/// two unequal types of one spelling, by their structure as `String(reflecting:)` spells it.
		func precedes(_ other: ScopeOrderKey) -> Bool {
			spellings < other.spellings || (spellings == other.spellings && String(reflecting: type) < String(reflecting: other.type))
		}

		private let type: TypeDescription
		private let spellings: (withoutAny: String, asSource: String)
	}
}
