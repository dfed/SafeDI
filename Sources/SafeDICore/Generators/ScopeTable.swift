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
		case instantiated(Property, ScopeID, erasedToConcreteExistential: Bool)
		case hole(Property, erasedToConcreteExistential: Bool)
		case aliased(
			Property,
			fulfilledBy: Property,
			erasedToConcreteExistential: Bool,
			onlyIfAvailable: Bool,
			declarationReference: AliasDeclarationReferences.Reference?,
		)

		/// The property this scope declares.
		var property: Property {
			switch self {
			case let .instantiated(property, _, _),
			     let .hole(property, _),
			     let .aliased(property, _, _, _, _):
				property
			}
		}
	}

	/// How a call passes the builder for one place, as `Scope.HoleArgument` holds it, with the scope of a fill named by its
	/// position.
	enum HoleArgument: Sendable {
		case fill(SeamSignature.Hole, ScopeID)
		case passUp(SeamSignature.Hole)

		/// The hole the argument is passed for.
		var hole: SeamSignature.Hole {
			switch self {
			case let .fill(hole, _), let .passUp(hole):
				hole
			}
		}
	}

	/// See `Scope.instantiable`.
	let instantiable: Instantiable
	/// See `Scope.builtInlineSeamComment`.
	let builtInlineSeamComment: String?
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

	/// See `Scope.createdBinding(of:)`.
	func createdBinding(of property: Property) -> Property? {
		for form in property.formsReadByOnlyIfAvailableReceive {
			if let binding = createdBindings[form] {
				return binding
			}
		}
		return nil
	}

	fileprivate init(freezing scope: Scope, propertiesToGenerate: [PropertyToGenerate], holeArguments: [HoleArgument]) {
		instantiable = scope.instantiable
		builtInlineSeamComment = scope.builtInlineSeamComment
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
	/// The record at `id`, which this table gave.
	subscript(id: ScopeID) -> ScopeRecord {
		records[Int(id.index)]
	}

	/// The position of the scope the map held under `key`, or `nil` when it held none.
	func id(forKey key: TypeDescription) -> ScopeID? {
		idByKey[key]
	}

	/// The records, in `ScopeID` order.
	fileprivate(set) var records = [ScopeRecord]()
	/// The map's keys, each with the position of its scope. For lookup only: never iterated.
	fileprivate(set) var idByKey = [TypeDescription: ScopeID]()
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
	init(freezing entries: some Sequence<(key: TypeDescription, scope: Scope)>) {
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
		let keyedScopes = firstKeyByScope.values.sorted { lhs, rhs in
			let lhsConcreteType = lhs.scope.instantiable.concreteInstantiable
			let rhsConcreteType = rhs.scope.instantiable.concreteInstantiable
			return if lhsConcreteType == rhsConcreteType {
				TypeDescription.precedesInScopeOrder(lhs.key, rhs.key)
			} else {
				TypeDescription.precedesInScopeOrder(lhsConcreteType, rhsConcreteType)
			}
		}
		for (_, scope) in keyedScopes {
			_ = id(of: scope)
		}
		for (key, scope) in entries {
			table.idByKey[key] = id(of: scope)
		}
		freezePendingScopes()
		if let observer = ScopeTableObservation.observer {
			observer(table.projection)
		}
	}

	/// The frozen table.
	private(set) var table = ScopeTable()

	/// The record of `scope` – a mock root's or a seam's root, which is in no map, or a root the map holds – frozen against
	/// the table, and the table its children are found in: this one, with a record appended for each scope it refers to
	/// that the map did not hold.
	func freezing(rootScope scope: Scope) -> (table: ScopeTable, record: ScopeRecord) {
		var frozenScopeMap = self
		let record = frozenScopeMap.record(freezing: scope)
		frozenScopeMap.freezePendingScopes()
		return (frozenScopeMap.table, record)
	}

	/// The scopes, in `ScopeID` order. Holding them keeps each identifier in `idByScope` naming its own scope.
	private var scopes = [Scope]()
	private var idByScope = [ObjectIdentifier: ScopeID]()

	/// The position of `scope`, given to it now when it has none.
	private mutating func id(of scope: Scope) -> ScopeID {
		let identifier = ObjectIdentifier(scope)
		if let id = idByScope[identifier] {
			return id
		} else {
			let id = ScopeID(scopes.count)
			scopes.append(scope)
			idByScope[identifier] = id
			return id
		}
	}

	/// Makes the record of every scope given a position but no record yet, in `ScopeID` order; each can give more positions.
	private mutating func freezePendingScopes() {
		while table.records.count < scopes.count {
			table.records.append(record(freezing: scopes[table.records.count]))
		}
	}

	/// The record of `scope`, giving a position to each scope it refers to.
	private mutating func record(freezing scope: Scope) -> ScopeRecord {
		var propertiesToGenerate = [ScopeRecord.PropertyToGenerate]()
		propertiesToGenerate.reserveCapacity(scope.propertiesToGenerate.count)
		for propertyToGenerate in scope.propertiesToGenerate {
			switch propertyToGenerate {
			case let .instantiated(property, childScope, erasedToConcreteExistential):
				propertiesToGenerate.append(.instantiated(property, id(of: childScope), erasedToConcreteExistential: erasedToConcreteExistential))
			case let .hole(property, erasedToConcreteExistential, _):
				propertiesToGenerate.append(.hole(property, erasedToConcreteExistential: erasedToConcreteExistential))
			case let .aliased(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference):
				propertiesToGenerate.append(.aliased(property, fulfilledBy: fulfillingProperty, erasedToConcreteExistential: erasedToConcreteExistential, onlyIfAvailable: onlyIfAvailable, declarationReference: declarationReference))
			}
		}
		let holeArguments = scope.holeArguments.map { holeArgument -> ScopeRecord.HoleArgument in
			switch holeArgument {
			case let .fill(hole, fillScope):
				.fill(hole, id(of: fillScope))
			case let .passUp(hole):
				.passUp(hole)
			}
		}
		return ScopeRecord(freezing: scope, propertiesToGenerate: propertiesToGenerate, holeArguments: holeArguments)
	}
}

extension ScopeTable {
	/// The table as text: each record in `ScopeID` order, by its concrete type, the keys that reach it, and the positions of
	/// the scopes it builds and fills. Two freezes of one map give the same text exactly when they give the same table.
	fileprivate var projection: String {
		var keysByID = [ScopeID: [TypeDescription]]()
		for (key, id) in idByKey {
			keysByID[id, default: []].append(key)
		}
		var lines = [String]()
		for (index, record) in records.enumerated() {
			var line = "\(index): \(record.instantiable.concreteInstantiable.asSource)"
			let keys = (keysByID[ScopeID(index)] ?? []).sorted(by: TypeDescription.precedesInScopeOrder)
			line.append(" keys [\(keys.map(\.asSource).joined(separator: ", "))]")
			for propertyToGenerate in record.propertiesToGenerate {
				switch propertyToGenerate {
				case let .instantiated(property, id, _):
					line.append(" \(property.label) -> \(id.index)")
				case let .hole(property, _):
					line.append(" \(property.label) -> hole")
				case let .aliased(property, fulfillingProperty, _, _, _):
					line.append(" \(property.label) = \(fulfillingProperty.label)")
				}
			}
			for case let .fill(hole, id) in record.holeArguments {
				line.append(" fill \(hole.property.label) -> \(id.index)")
			}
			lines.append(line)
		}
		return lines.joined(separator: "\n")
	}
}

/// What the tests read of each freeze, and how they order its entries: set by the tests, never by the tool.
public enum ScopeTableObservation {
	/// When set, each freeze takes its map's entries in the order this returns, a permutation of the positions of as many
	/// entries as it is passed, so that a test can show the table does not depend on the order entries arrive in.
	@TaskLocal public static var entryOrder: (@Sendable (_ entryCount: Int) -> [Int])?
	/// Called with each table a map freezes, as text (`ScopeTable.projection`).
	@TaskLocal public static var observer: (@Sendable (_ projection: String) -> Void)?
}

extension TypeDescription {
	/// Whether `lhs` comes before `rhs` in the order of a `ScopeTable`'s records: by `<`, which compares spellings, and, for
	/// two unequal types of one spelling, which `<` leaves unordered, by their structure as `String(reflecting:)` spells it.
	/// A total order on unequal types, so no arrival order breaks a tie.
	static func precedesInScopeOrder(_ lhs: TypeDescription, _ rhs: TypeDescription) -> Bool {
		lhs < rhs || (!(rhs < lhs) && String(reflecting: lhs) < String(reflecting: rhs))
	}
}
