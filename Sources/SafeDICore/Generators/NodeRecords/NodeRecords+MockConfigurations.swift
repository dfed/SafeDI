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
extension NodeRecords {
	/// The configuration records of a mock root's world, as the walk records them (`MockLowering.Walk.configurationRecords`):
	/// in the order its tree finishes its configured nodes, one per configured node of a type that repeats no configured
	/// node around it and is beneath none that does, and one per such node beneath a node that does, which the module's
	/// choice among those reads. A variant two parents build is visited under each, as the tree builds it twice. `nil`
	/// where the world holds a node no record says the configuration of yet.
	/// - Parameter handWrittenMockDefaultParameters: The defaults of each type's hand-written mock, which a configuration's
	///   default-valued fields default to.
	func mockConfigurationRecords(
		in world: some NodeRecordSources,
		handWrittenMockDefaultParameters: [TypeDescription: [ScopeGenerator.DefaultParameter]],
	) -> [MockLowering.ConfigurationRecord]? {
		let edgesLeftOut = world.mockRootNames.edgesConfigurationsLeaveOut
		func isLeftOut(_ child: DeclarationID, beneath parentConcreteType: String?) -> Bool {
			guard !edgesLeftOut.isEmpty, let parentConcreteType else { return false }
			return edgesLeftOut.contains(ScopeGenerator.CycleEdge(parent: parentConcreteType, child: world.scope(of: child).instantiable.concreteInstantiable.asSource))
		}
		var configurationRecords = [MockLowering.ConfigurationRecord]()
		var configuredAncestorTypes = Set<String>()
		var isBeneathRepeatedAncestor = false
		var walkOrder = 0
		var stack = [MockConfigurationFrame(variant: 0, parentConcreteType: nil, requiresSendable: false, childrenAreBuiltForActorArgument: Self.childrenAreBuiltForActorArgument(of: 0, isBuiltForActorArgument: false, in: world), isReachable: true, insertedType: nil, wasBeneathRepeatedAncestor: false, recordsConfiguration: false, walkOrder: -1)]
		while let top = stack.last {
			let entries = bodyEntries[Int(top.variant)]
			if top.next < entries.count {
				stack[stack.count - 1].next += 1
				guard case let .place(child) = entries[top.next] else { continue }
				let childDeclaration = declarationByVariant[Int(child)]
				switch kinds[Int(childDeclaration)] {
				case .mockConstruction:
					guard case let .built(record) = records[Int(child)] else { return nil }
					let concreteType = record.concreteType.asSource
					let ownConcreteType = top.variant == 0 ? nil : world.scope(of: declarationByVariant[Int(top.variant)]).instantiable.concreteInstantiable.asSource
					let repeatsAncestor = !configuredAncestorTypes.insert(concreteType).inserted
					stack.append(MockConfigurationFrame(
						variant: child,
						parentConcreteType: ownConcreteType,
						requiresSendable: top.requiresSendable || record.isSendable || top.childrenAreBuiltForActorArgument,
						childrenAreBuiltForActorArgument: Self.childrenAreBuiltForActorArgument(of: childDeclaration, isBuiltForActorArgument: top.childrenAreBuiltForActorArgument, in: world),
						isReachable: top.isReachable && !isLeftOut(childDeclaration, beneath: ownConcreteType),
						insertedType: repeatsAncestor ? nil : concreteType,
						wasBeneathRepeatedAncestor: isBeneathRepeatedAncestor,
						recordsConfiguration: !repeatsAncestor && !isBeneathRepeatedAncestor,
						walkOrder: walkOrder,
					))
					walkOrder += 1
					isBeneathRepeatedAncestor = isBeneathRepeatedAncestor || repeatsAncestor
				case .rename, .mockUnavailableDependency, .publicMockCall:
					break
				case .builtByInitializer, .inlineSeam, .seamCall, .unavailableDependency, .receivesOnlyIfAvailable, .erased, .lazy, .sendable, .seamHole, .cycle:
					return nil
				}
				continue
			}
			stack.removeLast()
			guard !stack.isEmpty else { break }
			if let insertedType = top.insertedType {
				configuredAncestorTypes.remove(insertedType)
			}
			isBeneathRepeatedAncestor = top.wasBeneathRepeatedAncestor
			let declaration = declarationByVariant[Int(top.variant)]
			guard Self.isOverriddenByConfiguration(declaration, in: world) else { continue }
			let instantiable = world.scope(of: declaration).instantiable
			let concreteType = instantiable.concreteInstantiable.asSource
			let recordIndex: Int?
			if top.recordsConfiguration || top.wasBeneathRepeatedAncestor && top.insertedType != nil {
				let recorded = entries.filter { entry in
					switch entry {
					case let .place(child): !isLeftOut(declarationByVariant[Int(child)], beneath: concreteType)
					case let .closer(closingOn: child): !isLeftOut(declarationByVariant[Int(child)], beneath: concreteType)
					}
				}
				guard var configurationRecord = mockConfigurationRecord(of: declaration, children: recorded, requiresSendable: top.requiresSendable, childrenAreBuiltForActorArgument: top.childrenAreBuiltForActorArgument, in: world, handWrittenMockDefaultParameters: handWrittenMockDefaultParameters) else { return nil }
				configurationRecord.fulfillers = FulfillerImports.Fulfiller.fulfillers(
					building: instantiable,
					forPropertyOfType: (world.property(of: declaration)?.typeDescription ?? instantiable.concreteInstantiable).asInstantiatedType,
					callingHandWrittenMock: !handWrittenMockDefaultParameters[instantiable.concreteInstantiable, default: []].isEmpty,
				)
				if top.recordsConfiguration {
					configurationRecord.oneWayConstruction = mockOneWayConstruction(of: declaration, children: entries, parentConcreteType: top.parentConcreteType, isBeneathCycleEdge: !top.isReachable, walkOrder: top.walkOrder, in: world)
				} else {
					let readsConfiguration = !ScopeGenerator.MockConstruction(instantiable: instantiable, useMockInitializer: configurationRecord.usesMockInitializer, builderTypesDeclaredEscaping: []).defaultParameters.isEmpty
						|| !Self.mockConfigurationFieldArguments(of: declaration, in: world).isEmpty
					configurationRecord.beneathRepeatedAncestor = MockLowering.ConfigurationRecord.BeneathRepeatedAncestor(
						readsConfiguration: readsConfiguration,
						isPublicMock: false,
						nestedChildren: recorded.compactMap { entry in
							switch entry {
							case let .place(child):
								let childDeclaration = declarationByVariant[Int(child)]
								guard kinds[Int(childDeclaration)] == .mockConstruction, Self.isOverriddenByConfiguration(childDeclaration, in: world), let property = world.property(of: childDeclaration) else { return nil }
								return MockLowering.ConfigurationRecord.NestedChild(
									concreteType: world.scope(of: childDeclaration).instantiable.concreteInstantiable,
									recordIndex: top.finishedChildren.first(where: { $0.property == property })?.recordIndex,
								)
							case let .closer(closingOn: child):
								return MockLowering.ConfigurationRecord.NestedChild(concreteType: world.scope(of: declarationByVariant[Int(child)]).instantiable.concreteInstantiable, recordIndex: nil)
							}
						},
					)
				}
				configurationRecords.append(configurationRecord)
				recordIndex = configurationRecords.count - 1
			} else {
				recordIndex = nil
			}
			if let property = world.property(of: declaration) {
				stack[stack.count - 1].finishedChildren.append(MockLowering.FinishedConfiguredChild(property: property, recordIndex: recordIndex))
			}
		}
		return configurationRecords
	}

	/// The configuration record of `declaration`, a configured node of a mock root's world whose configuration holds a
	/// field for each of `children`, as the walk records it (`MockLowering.ConfigurationRecord.init(of:children:)`).
	private func mockConfigurationRecord(
		of declaration: DeclarationID,
		children: [BodyEntry],
		requiresSendable: Bool,
		childrenAreBuiltForActorArgument: Bool,
		in world: some NodeRecordSources,
		handWrittenMockDefaultParameters: [TypeDescription: [ScopeGenerator.DefaultParameter]],
	) -> MockLowering.ConfigurationRecord? {
		let instantiable = world.scope(of: declaration).instantiable
		let usesMockInitializer = world.construction(of: declaration) == .handWrittenMock && instantiable.mockInitializer != nil
		var childFieldSources = [MockLowering.ConfigurationRecord.ChildFieldSource]()
		for entry in children {
			switch entry {
			case let .place(child):
				let childDeclaration = declarationByVariant[Int(child)]
				switch kinds[Int(childDeclaration)] {
				case .mockConstruction:
					guard case let .built(record) = records[Int(child)], let property = world.property(of: childDeclaration) else { return nil }
					let childInstantiable = world.scope(of: childDeclaration).instantiable
					childFieldSources.append(.built(
						bindingName: record.property.label,
						hasConfiguration: Self.isOverriddenByConfiguration(childDeclaration, in: world),
						requiresSendable: requiresSendable || record.isSendable || childrenAreBuiltForActorArgument,
						concreteType: childInstantiable.concreteInstantiable,
						builderParameters: MockLowering.BuilderParameters(of: childInstantiable, usesMockInitializer: world.construction(of: childDeclaration) == .handWrittenMock && childInstantiable.mockInitializer != nil),
						propertyType: property.typeDescription,
					))
				case .publicMockCall:
					guard let field = Self.mockPublicMockCallOverridesField(of: childDeclaration, in: world) else { return nil }
					childFieldSources.append(.spelled(.init(name: field.name, typeSource: field.typeSource, defaultValue: field.defaultValue, sendableForm: Self.mockPublicMockCallSendableFieldForm(of: childDeclaration, in: world))))
				case .rename, .mockUnavailableDependency:
					break
				case .builtByInitializer, .inlineSeam, .seamCall, .unavailableDependency, .receivesOnlyIfAvailable, .erased, .lazy, .sendable, .seamHole, .cycle:
					return nil
				}
			case let .closer(closingOn: child):
				let closedOn = declarationByVariant[Int(child)]
				guard let property = world.property(of: closedOn) else { return nil }
				let concreteType = world.scope(of: closedOn).instantiable.concreteInstantiable
				let field = MockLowering.cycleClosingOverridesField(boundAs: property.label, concreteType: concreteType)
				childFieldSources.append(.spelled(.init(name: field.name, typeSource: field.typeSource, defaultValue: field.defaultValue, sendableForm: .init(typeSource: field.typeSource, defaultValue: field.defaultValue, configuredTypeName: concreteType.asSource))))
			}
		}
		let construction = ScopeGenerator.MockConstruction(instantiable: instantiable, useMockInitializer: usesMockInitializer, builderTypesDeclaredEscaping: [])
		let handWrittenDefaults = handWrittenMockDefaultParameters[instantiable.concreteInstantiable, default: []]
		// The configuration's default-valued fields are those its construction reads (`mockConfigurationFieldArguments(of:in:)`).
		let fieldLabels = Set(Self.mockConfigurationFieldArguments(of: declaration, in: world).map(\.argument.label))
		return MockLowering.ConfigurationRecord(
			concreteType: instantiable.concreteInstantiable,
			usesMockInitializer: usesMockInitializer,
			childFieldSources: childFieldSources,
			builderParameters: MockLowering.BuilderParameters(of: instantiable, usesMockInitializer: usesMockInitializer),
			defaultFields: construction.defaultParameters.filter { fieldLabels.contains($0.label) }.map { MockLowering.DefaultField(of: $0, handWrittenMockDefaultParameters: handWrittenDefaults) },
		)
	}

	/// What the one-way check reads of `declaration`, a configured node of a mock root's world whose children are
	/// `children`, every one of them (`MockLowering.OneWayConstruction.init(of:construction:children:parentConcreteType:isBeneathCycleEdge:walkOrder:)`).
	private func mockOneWayConstruction(
		of declaration: DeclarationID,
		children: [BodyEntry],
		parentConcreteType: String?,
		isBeneathCycleEdge: Bool,
		walkOrder: Int,
		in world: some NodeRecordSources,
	) -> MockLowering.OneWayConstruction? {
		let instantiable = world.scope(of: declaration).instantiable
		guard let property = world.property(of: declaration) else { return nil }
		let usesMockInitializer = world.construction(of: declaration) == .handWrittenMock && instantiable.mockInitializer != nil
		let childProperties = children.compactMap { entry -> Property? in
			switch entry {
			case let .place(child):
				let childDeclaration = declarationByVariant[Int(child)]
				switch kinds[Int(childDeclaration)] {
				case .mockConstruction, .publicMockCall:
					return world.property(of: childDeclaration)
				case .rename, .mockUnavailableDependency, .builtByInitializer, .inlineSeam, .seamCall, .unavailableDependency, .receivesOnlyIfAvailable, .erased, .lazy, .sendable, .seamHole, .cycle:
					return nil
				}
			case let .closer(closingOn: child):
				return world.property(of: declarationByVariant[Int(child)])
			}
		}
		return MockLowering.OneWayConstruction(
			property: property,
			construction: ScopeGenerator.MockConstruction(instantiable: instantiable, useMockInitializer: usesMockInitializer, builderTypesDeclaredEscaping: []),
			childProperties: childProperties,
			parentConcreteType: parentConcreteType,
			isBeneathCycleEdge: isBeneathCycleEdge,
			walkOrder: walkOrder,
		)
	}

	/// A configured node the walk of `mockConfigurationRecords(in:handWrittenMockDefaultParameters:)` is in.
	private struct MockConfigurationFrame {
		let variant: VariantID
		/// The concrete type of the node around it, `nil` beneath the root.
		let parentConcreteType: String?
		let requiresSendable: Bool
		/// Whether its children are built for an actor's argument (`childrenAreBuiltForActorArgument(of:isBuiltForActorArgument:in:)`).
		let childrenAreBuiltForActorArgument: Bool
		let isReachable: Bool
		let insertedType: String?
		let wasBeneathRepeatedAncestor: Bool
		let recordsConfiguration: Bool
		let walkOrder: Int
		var next = 0
		var finishedChildren = [MockLowering.FinishedConfiguredChild]()
	}
}
