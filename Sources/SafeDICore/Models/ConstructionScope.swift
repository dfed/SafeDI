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

	private let table: ScopeTable
	private let record: ScopeRecord
}
