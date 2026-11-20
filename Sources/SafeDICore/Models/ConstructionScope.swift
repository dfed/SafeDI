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

/// A scope as construction reads it: a record of a frozen `ScopeTable`, with the table that names the scopes it builds and
/// fills. Construction reads nothing of a `Scope` itself, so a tree can be built from it on any task.
struct ConstructionScope: Sendable {
	init(table: ScopeTable, record: ScopeRecord) {
		self.table = table
		self.record = record
	}

	/// What a construction memo keys and keeps alive for this scope: its record, which every table made from one frozen
	/// map shares, and which names one scope in each.
	var identity: ScopeRecord {
		record
	}

	var instantiable: Instantiable {
		record.instantiable
	}

	var builtInlineSeamComment: String? {
		record.builtInlineSeamComment
	}

	var seamCall: SeamCall? {
		record.seamCall
	}

	var publicMockCall: PublicMockCall? {
		record.publicMockCall
	}

	var calledBuilders: CalledBuilders? {
		record.calledBuilders
	}

	var fillReceivedProperties: [SeamSignature.Hole.Site: Set<Property>] {
		record.fillReceivedProperties
	}

	var fillLabelsReadOnlyIfAvailable: [SeamSignature.Hole.Site: Set<String>] {
		record.fillLabelsReadOnlyIfAvailable
	}

	var propertiesToDeclare: Set<Property> {
		record.propertiesToDeclare
	}

	var instantiatedDependenciesNotGenerated: [Dependency] {
		record.instantiatedDependenciesNotGenerated
	}

	var declaredLabels: Set<String> {
		record.declaredLabels
	}

	var sortedDeclaredPropertyForms: [(property: Property, forms: Set<Property>)] {
		record.sortedDeclaredPropertyForms
	}

	var declaredLazilyInstantiatedInstanceProperties: Set<Property> {
		record.declaredLazilyInstantiatedInstanceProperties
	}

	var forwardedLazilyInstantiatedInstanceProperties: [Property] {
		record.forwardedLazilyInstantiatedInstanceProperties
	}

	/// `Scope.createdBinding(of:)`.
	func createdBinding(of property: Property) -> Property? {
		record.createdBinding(of: property)
	}

	/// `Scope.PropertyToGenerate`, with the scope built read from the table.
	enum PropertyToGenerate: Sendable {
		case instantiated(Property, ConstructionScope, erasedToConcreteExistential: Bool)
		case hole(Property, erasedToConcreteExistential: Bool)
		case aliased(
			Property,
			fulfilledBy: Property,
			erasedToConcreteExistential: Bool,
			onlyIfAvailable: Bool,
			declarationReference: AliasDeclarationReferences.Reference?,
		)
	}

	var propertiesToGenerate: [PropertyToGenerate] {
		record.propertiesToGenerate.map { propertyToGenerate in
			switch propertyToGenerate {
			case let .instantiated(property, id, erasedToConcreteExistential):
				.instantiated(property, ConstructionScope(table: table, record: table[id]), erasedToConcreteExistential: erasedToConcreteExistential)
			case let .hole(property, erasedToConcreteExistential):
				.hole(property, erasedToConcreteExistential: erasedToConcreteExistential)
			case let .aliased(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference):
				.aliased(property, fulfilledBy: fulfillingProperty, erasedToConcreteExistential: erasedToConcreteExistential, onlyIfAvailable: onlyIfAvailable, declarationReference: declarationReference)
			}
		}
	}

	/// `Scope.HoleArgument`, with the fulfilling scope read from the table.
	enum HoleArgument: Sendable {
		case fill(SeamSignature.Hole, ConstructionScope)
		case passUp(SeamSignature.Hole)
	}

	var holeArguments: [HoleArgument] {
		record.holeArguments.map { argument in
			switch argument {
			case let .fill(hole, id):
				.fill(hole, ConstructionScope(table: table, record: table[id]))
			case let .passUp(hole):
				.passUp(hole)
			}
		}
	}

	fileprivate let table: ScopeTable
	fileprivate let record: ScopeRecord
}

/// The scopes one tree builds at one place only: one reference reaches each, from a scope at one place, or it is the root
/// and nothing references it. Within one pass of the tree, no other place has a construction memo key that names such a
/// scope, so its place's generator is never reused there (see `ConstructionMemo`). A place a pass does not build (inside a
/// cycle it closes, say) only leaves a scope out where it could be in. Records are shared by every table of one frozen
/// map, and so by every tree built from it, so this is decided once per tree, from the tree's root.
struct ScopesBuiltAtOnePlace: Sendable {
	init(treeRootedAt root: ConstructionScope) {
		// The records the root reaches through the scopes it builds and the fills of its calls, each appended when it is
		// first referenced, after the record that references it, so the record that references a record referenced once
		// precedes it, and one pass in that order decides every record. A record on a cycle is referenced by the cycle as
		// well as from outside it, or descends from such a record, so no record on a cycle is at one place.
		var records = [root.record]
		var indexByRecord = [ObjectIdentifier(root.record): 0]
		var referenceCounts = [1]
		var lastReferrers = [0]
		var referrer = 0
		while referrer < records.count {
			func reference(_ id: ScopeID) {
				let record = root.table[id]
				if let index = indexByRecord[ObjectIdentifier(record)] {
					referenceCounts[index] += 1
					lastReferrers[index] = referrer
				} else {
					indexByRecord[ObjectIdentifier(record)] = records.count
					records.append(record)
					referenceCounts.append(1)
					lastReferrers.append(referrer)
				}
			}
			for case let .instantiated(_, id, _) in records[referrer].propertiesToGenerate {
				reference(id)
			}
			// A fill place has no key and stores nothing, so counting its reference only keys, with nothing to hit, a scope the
			// tree otherwise builds at one place. The count is kept so that one place means one reference of any kind.
			for case let .fill(_, id) in records[referrer].holeArguments {
				reference(id)
			}
			referrer += 1
		}
		var isAtOnePlace = [Bool]()
		isAtOnePlace.reserveCapacity(records.count)
		var recordsAtOnePlace = Set<ObjectIdentifier>()
		for index in records.indices {
			let atOnePlace = referenceCounts[index] == 1 && (index == 0 || isAtOnePlace[lastReferrers[index]])
			isAtOnePlace.append(atOnePlace)
			if atOnePlace {
				recordsAtOnePlace.insert(ObjectIdentifier(records[index]))
			}
		}
		self.recordsAtOnePlace = recordsAtOnePlace
		self.records = records
	}

	/// Whether the tree builds `scope` at one place only.
	func contains(_ scope: ConstructionScope) -> Bool {
		recordsAtOnePlace.contains(ObjectIdentifier(scope.record))
	}

	private let recordsAtOnePlace: Set<ObjectIdentifier>
	/// Every record the tree reaches, held so that no other record takes the address of one `recordsAtOnePlace` names.
	private let records: [ScopeRecord]
}
