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

/// Stage D1, lane D: the check that a type generated mocks build both with its hand-written mock and without it needs one
/// `SafeDIMockConfiguration` either way, read from the configuration records of every root's lowering, as
/// `DependencyTreeGenerator.validateConfigurationsAreBuiltOneWay` reads the emitter's nodes.
extension MockLowering {
	/// What the one-way check reads of a configured node: the construction it builds its type with, what that construction
	/// reads from the type's configuration, and where the node is, which the diagnostic names.
	struct OneWayConstruction: Sendable, Equatable {
		/// The property the node builds.
		let property: Property
		/// The concrete type of the node around it, as the generated code spells it, or `nil` at the mock's root.
		let parentConcreteType: String?
		/// The name of the hand-written mock the construction calls, where it calls one under another name than `mock`.
		let customMockName: String?
		/// Whether the type is declared by an extension, whose construction is its `instantiate(…)` method.
		let isExtensionBased: Bool
		/// What the construction reads from the configuration.
		let requirements: Requirements
		/// Whether an edge in `cycleEdges` is above the node, which then reads no override from its configuration.
		let isBeneathCycleEdge: Bool
		/// The order in which the walk entered the node's children: a node before the nodes beneath it, in declaration order.
		private(set) var walkOrder: Int

		/// The construction with `walkOrder` in place of its own.
		func entered(at walkOrder: Int) -> OneWayConstruction {
			var construction = self
			construction.walkOrder = walkOrder
			return construction
		}

		/// What a construction reads from its type's configuration: the child properties, the default-valued parameters by
		/// label and type, the types the builder takes, and the labels of the values it is handed, in order, so that two
		/// dependencies of one type in other orders are told apart.
		struct Requirements: Sendable, Equatable {
			let childProperties: [Property]
			let defaultParameters: [Property]
			let builderParameterTypes: [TypeDescription]
			let builderArgumentLabels: [String]
		}

		init(
			of node: ConstantNode,
			construction: ScopeGenerator.MockConstruction,
			children: [TreeNode],
			parentConcreteType: String?,
			isBeneathCycleEdge: Bool,
			walkOrder: Int,
		) {
			self.init(
				property: node.property,
				construction: construction,
				childProperties: children.filter(\.isPropertyNode).map(\.property),
				parentConcreteType: parentConcreteType,
				isBeneathCycleEdge: isBeneathCycleEdge,
				walkOrder: walkOrder,
			)
		}

		/// The construction of a node built as `property` whose children build `childProperties`, in order, each but an
		/// alias.
		init(
			property: Property,
			construction: ScopeGenerator.MockConstruction,
			childProperties: [Property],
			parentConcreteType: String?,
			isBeneathCycleEdge: Bool,
			walkOrder: Int,
		) {
			self.property = property
			self.parentConcreteType = parentConcreteType
			customMockName = construction.customMockName
			isExtensionBased = construction.isExtensionBased
			requirements = Requirements(
				childProperties: childProperties,
				defaultParameters: construction.defaultParameters.map { Property(label: $0.label, typeDescription: $0.typeDescription) },
				builderParameterTypes: construction.builderParameterTypes,
				builderArgumentLabels: construction.callSiteArguments.map(\.innerLabel),
			)
			self.isBeneathCycleEdge = isBeneathCycleEdge
			self.walkOrder = walkOrder
		}
	}

	/// The types of `mockDeclarationLocations` that `roots`, in concrete type order, build both with the type's hand-written
	/// mock and without it, where the first record of each construction in root order reads a configuration the other's does
	/// not.
	static func configurationsBuiltTwoWays(
		of roots: [(mockedType: TypeDescription, lowered: Result)],
		mockDeclarationLocations: [TypeDescription: Set<Dependency.DeclarationLocation?>],
	) -> [DependencyTreeGenerator.DependencyTreeGeneratorError.ConfigurationBuiltTwoWays] {
		guard !mockDeclarationLocations.isEmpty else { return [] }
		var firstConstructions = [ScopeGenerator.ConstructedType: (mockedType: TypeDescription, construction: OneWayConstruction)]()
		for root in roots {
			// The records are in the order the walk finished the nodes; the check reads them in the order it entered them.
			let constructions = root.lowered.configurations.compactMap { record in record.oneWayConstruction.map { (record: record, construction: $0) } }
				.sorted { $0.construction.walkOrder < $1.construction.walkOrder }
			for (record, construction) in constructions where !construction.isBeneathCycleEdge {
				let constructedType = ScopeGenerator.ConstructedType(concreteType: record.concreteType, usesMockInitializer: record.usesMockInitializer)
				firstConstructions[constructedType] = firstConstructions[constructedType] ?? (mockedType: root.mockedType, construction: construction)
			}
		}
		return mockDeclarationLocations.keys.compactMap { concreteType in
			guard let builtByMock = firstConstructions[ScopeGenerator.ConstructedType(concreteType: concreteType, usesMockInitializer: true)],
			      let builtWithoutMock = firstConstructions[ScopeGenerator.ConstructedType(concreteType: concreteType, usesMockInitializer: false)],
			      builtByMock.construction.requirements != builtWithoutMock.construction.requirements
			else { return nil }
			return DependencyTreeGenerator.DependencyTreeGeneratorError.ConfigurationBuiltTwoWays(
				concreteType: concreteType,
				mockDeclarationLocations: Array(mockDeclarationLocations[concreteType, default: []]),
				builtByMock: .init(of: builtByMock.construction, inMockOf: builtByMock.mockedType),
				builtWithoutMock: .init(of: builtWithoutMock.construction, inMockOf: builtWithoutMock.mockedType),
			)
		}
	}
}

extension DependencyTreeGenerator.DependencyTreeGeneratorError.ConfigurationBuiltTwoWays.BuiltConstruction {
	/// The construction `construction` describes, in the mock of `mockedType`.
	init(of construction: MockLowering.OneWayConstruction, inMockOf mockedType: TypeDescription) {
		self.init(
			property: construction.property,
			parent: construction.parentConcreteType ?? mockedType.asSource,
			mockRoot: mockedType,
			customMockName: construction.customMockName,
			isExtensionBased: construction.isExtensionBased,
		)
	}
}
