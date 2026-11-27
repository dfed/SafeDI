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

/// What a mock root's lowering names that the records of its world read: values of the root's level, which no fact of
/// the world holds, so the world is made with them (`TypeFactsGraph.mockRootNames`). Empty for every production root's world.
struct MockRootNames: Sendable {
	/// - Parameters:
	///   - namesApart: The name the root's level gives each child it names apart, by the child's label and then its
	///     property's type (`MockLowering.Walk.rootRenames`).
	///   - unavailableDependencyOverrides: Each property instantiated only if available that nothing fulfills and that
	///     `mock()` takes an override of, with the override's name, in the order `SafeDIOverrides` declares the overrides
	///     (`MockLowering.RootSignature.unavailableDependencyOverrideNames`).
	init(namesApart: [String: [TypeDescription: String]] = [:], unavailableDependencyOverrides: [(property: Property, name: String)] = []) {
		self.namesApart = namesApart
		unavailableDependencyOverrideNamesInOrder = unavailableDependencyOverrides.map(\.name)
		unavailableDependencyOverrideNames = Dictionary(unavailableDependencyOverrides.map { ($0.property, $0.name) }) { first, _ in first }
	}

	/// The name the mock root binds `property` under where it names it apart from a sibling of its label, and `nil`
	/// where the root binds the property under its label or does not bind it.
	func nameApart(of property: Property) -> String? {
		namesApart[property.label]?[property.typeDescription]
	}

	/// Whether the root names apart a child labeled `label`.
	func namesApart(label: String) -> Bool {
		namesApart[label].map { !$0.isEmpty } ?? false
	}

	/// The name of the override `mock()` takes of `property`, one instantiated only if available that nothing fulfills,
	/// and `nil` where it takes none.
	func unavailableDependencyOverrideName(of property: Property) -> String? {
		unavailableDependencyOverrideNames[property]
	}

	/// The names of the overrides `mock()` takes of properties nothing fulfills, in the order `SafeDIOverrides` declares them.
	let unavailableDependencyOverrideNamesInOrder: [String]

	private let namesApart: [String: [TypeDescription: String]]
	private let unavailableDependencyOverrideNames: [Property: String]
}

extension NodeRecords {
	/// The refusal `declaration`, a node of a mock root's world, holds for a label the root names apart, or none.
	///
	/// A mock root promotes each form of a label its tree receives and names the forms apart
	/// (`ScopeGenerator.disambiguatePropertyLabels(forProperties:besideParametersKeepingTheirLabels:reservedNames:)`), so
	/// the override of such a child is the root's field under the name, and each type that receives the label binds the
	/// name again under the label at the top of its function. The records make that where every read of the label is a
	/// receive of a form the root names apart, with nothing between the root and the receive declaring the label again.
	/// Refused, and left to the walk: two children of one label under any other node, or under a root that was handed no
	/// name for one; a child named apart whose property is optional, which the walk binds as the value it builds; a node beneath the root that instantiates, forwards or renames such a label, which hides the name
	/// from what it builds; and a receive of the label in a form the root does not name apart, which reads the label by
	/// name where the walk hands the name on (`MockLowering.receiveReadsLabelByName`).
	static func refusalOfNamingApart(_ declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordRefusal? {
		let mockRootNames = world.mockRootNames
		var labels = Set<String>()
		for child in world.edges(from: declaration) {
			guard let property = world.property(of: child) else { continue }
			// The walk binds an optional form the root names apart without its type, so the binding is not optional; a
			// record's binding declares the property's type.
			guard mockRootNames.nameApart(of: property) == nil || !property.typeDescription.isOptional else { return .mockOverrideNotParentField }
			guard !labels.insert(property.label).inserted else { continue }
			// Both children of the label are named apart, or neither is.
			guard declaration == 0, mockRootNames.namesApart(label: property.label) else { return .mockOverrideNotParentField }
		}
		guard declaration != 0 else { return nil }
		for dependency in world.scope(of: declaration).instantiable.dependencies {
			switch dependency.source {
			case .received:
				guard mockRootNames.namesApart(label: dependency.property.label) else { continue }
				guard nameApartRead(by: dependency, mockRootNames: mockRootNames) != nil else { return .mockOverrideNotParentField }
			case .instantiated, .forwarded, .aliased:
				// A type that declares a rename is left unclaimed (`NodeRecordRefusal.renameOrHole`), so none is asked here.
				guard !mockRootNames.namesApart(label: dependency.property.label) else { return .mockOverrideNotParentField }
			}
		}
		return nil
	}

	/// The child of the mock root named apart that `dependency`, a receive, reads: the form of its own type, or of the
	/// type it wraps in an optional, as the walk resolves it. `nil` where the root names no such form apart.
	private static func nameApartRead(by dependency: Dependency, mockRootNames: MockRootNames) -> (property: Property, name: String)? {
		[dependency.property, dependency.property.asUnwrappedProperty].lazy.compactMap { property in
			mockRootNames.nameApart(of: property).map { (property, $0) }
		}.first
	}

	/// The places that bind again, under its label, each child of the mock root named apart that `declaration`'s type
	/// receives: the first statements of its function, in the order its type declares the receives, each written as the
	/// walk writes it and read as a rename of the name is, so the function is handed the name as it is any value it reads.
	static func placesBindingNamesApartAgain(in declaration: DeclarationID, of world: some NodeRecordSources) -> [GeneratedCode] {
		let mockRootNames = world.mockRootNames
		return world.scope(of: declaration).instantiable.dependencies.compactMap { dependency in
			guard case .received = dependency.source, let (property, name) = nameApartRead(by: dependency, mockRootNames: mockRootNames) else { return nil }
			let record = AliasPlaceRecord(
				property: dependency.property,
				fulfillingProperty: Property(label: name, typeDescription: property.typeDescription),
				text: "let \(dependency.property.label): \(dependency.property.typeDescription.asSource) = \(name)",
			)
			return .indented(.place(PlacePlan(code: .text(record.text), record: .alias(record))), by: ScopeGenerator.standardIndent)
		}
	}
}
