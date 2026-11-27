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
	///   - passedUpBuilderNames: The name `mock()` binds each builder under that a call of another module's public mock passes
	///     up, by the property the call's leaf receives it as (`MockLowering.RootSignature.passedUpBuilderNames`).
	init(namesApart: [String: [TypeDescription: String]] = [:], unavailableDependencyOverrides: [(property: Property, name: String)] = [], passedUpBuilderNames: [Property: String] = [:]) {
		self.namesApart = namesApart
		self.passedUpBuilderNames = passedUpBuilderNames
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

	/// The name `mock()` binds the builder under that a call's leaf receives as `property`, and `nil` where `mock()` takes no
	/// builder the leaf receives so.
	func passedUpBuilderName(of property: Property) -> String? {
		passedUpBuilderNames[property]
	}

	/// The name of each value of the root's level a node binds again under its label where it receives it, by label and
	/// then type: each value the root names apart, and each builder a call passes up that `mock()` binds under another name
	/// (`NodeRecords.mockReceivesBoundAgain(in:)`).
	var namesBoundAgain: [String: [TypeDescription: String]] {
		var names = namesApart
		for (property, name) in passedUpBuilderNames where name != property.label {
			names[property.label, default: [:]][property.typeDescription] = name
		}
		return names
	}

	/// The name the root gives each value of its level it names apart, by label and then type.
	let namesApart: [String: [TypeDescription: String]]

	private let passedUpBuilderNames: [Property: String]
	private let unavailableDependencyOverrideNames: [Property: String]
}

extension NodeRecords {
	/// The refusal `declaration`, a node of a mock root's world, holds for a label the root names apart, or none.
	///
	/// A mock root promotes each form of a label its tree receives and names the forms apart
	/// (`ScopeGenerator.disambiguatePropertyLabels(forProperties:besideParametersKeepingTheirLabels:reservedNames:)`), and
	/// names apart a parameter of `mock()` or an override beside another form of its label, so the override of such a child
	/// is the root's field under the name, and each type that receives the label where no declaration between hides it binds
	/// the name again under the label at the top of its function (`mockReceivesBoundAgain(in:)`). Refused, and left to the
	/// walk: two children of one label under any other node, or under a root that was handed no name for one; a child of the
	/// root named apart whose property is optional, which the walk binds as the value it builds; a rename of such a label
	/// or from one, whose binding the walk reads otherwise; and a receive of the label only if available, which reads the name or `nil`
	/// by its place, since a required receive of another form above a place pins the label there
	/// (`MockLowering.receiveReadsLabelByName`), and one function serves every place.
	static func refusalOfNamingApart(_ declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordRefusal? {
		let mockRootNames = world.mockRootNames
		var labels = Set<String>()
		for child in world.edges(from: declaration) {
			guard let property = world.property(of: child) else { continue }
			// The walk binds an optional form the root names apart without its type, so the binding is not optional; a
			// record's binding declares the property's type.
			guard declaration != 0 || mockRootNames.nameApart(of: property) == nil || !property.typeDescription.isOptional else { return .mockOverrideNotParentField }
			guard !labels.insert(property.label).inserted else { continue }
			// Both children of the label are named apart, or neither is.
			guard declaration == 0, mockRootNames.namesApart(label: property.label) else { return .mockOverrideNotParentField }
		}
		guard declaration != 0 else { return nil }
		for dependency in world.scope(of: declaration).instantiable.dependencies {
			switch dependency.source {
			case let .received(onlyIfAvailable):
				guard !onlyIfAvailable || !mockRootNames.namesApart(label: dependency.property.label) else { return .mockOverrideNotParentField }
			case let .aliased(fulfillingProperty, _, _):
				// A rename reads its fulfilling label by name, which the walk resolves past a receive bound again.
				guard !mockRootNames.namesApart(label: dependency.property.label), !mockRootNames.namesApart(label: fulfillingProperty.label) else { return .mockOverrideNotParentField }
			case .instantiated, .forwarded:
				// A declaration of the label hides the name from what the node builds (`mockReceivesBoundAgain(in:)`).
				break
			}
		}
		return nil
	}

	/// Whether `declaration`, a call of another module's public mock, takes a parameter under a label the mock root names
	/// apart. The walk hands such a call the name (`MockLowering.Walk.publicMockCallNode`), while a call's record reads each
	/// argument under its label and binds no name again, so the call's world keeps the walk.
	static func callTakesLabelNamedApart(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		let mockRootNames = world.mockRootNames
		return world.scope(of: declaration).instantiable.dependencies.contains { mockRootNames.namesApart(label: $0.property.label) }
	}
}
