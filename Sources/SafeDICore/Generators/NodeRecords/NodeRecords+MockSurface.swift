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
	/// What a mock root whose world is `world` declares of its nodes beside their statements (`MockLowering.RootSurface`),
	/// from its records: `nil` where a record does not say it yet.
	func mockRootSurface(in world: some NodeRecordSources, handWrittenMockDefaultParameters: [TypeDescription: [ScopeGenerator.DefaultParameter]]) -> MockLowering.RootSurface? {
		// `mock()`'s overrides hold a member for each child of the root as a configuration holds one for each child of its
		// node, outside any `@Sendable` function, the mocked type's own initializer taking an actor's arguments.
		guard let fieldSources = mockChildFieldSources(of: bodyEntries[0], requiresSendable: false, childrenAreBuiltForActorArgument: Self.childrenAreBuiltForActorArgument(of: 0, isBuiltForActorArgument: false, in: world), in: world),
		      let configurations = mockConfigurationRecords(in: world, handWrittenMockDefaultParameters: handWrittenMockDefaultParameters)
		else { return nil }
		return MockLowering.RootSurface(
			hasNodes: !bodyEntries[0].isEmpty,
			buildsPropertyNode: bodyEntries[0].contains { entry in
				switch entry {
				case let .place(variant): mockBuiltRecord(of: variant) != nil
				case .closer: true
				}
			},
			overridesFields: fieldSources.map(\.overridesField),
			configurations: configurations,
		)
	}

	/// The record of `variant`'s place where it builds a property, the call of another module's public mock included; `nil`
	/// for a rename and a property nothing fulfills, which build none.
	func mockBuiltRecord(of variant: VariantID) -> BuiltPlaceRecord? {
		switch records[Int(variant)] {
		case let .built(record): record
		case .alias, .closer, nil: nil
		}
	}

	/// The member of the configuration of a node of a mock root's world, or of `mock()`'s overrides, for each of
	/// `children`, the places its body holds, in order, as the walk spells it (`MockLowering.ConfigurationRecord.init(of:children:)`):
	/// a node it builds has its configuration where it is overridden by one (`isOverriddenByConfiguration(_:in:)`), else the
	/// closure that overrides it, `@Sendable` where the node is built in a `@Sendable` function, beneath one
	/// (`requiresSendable`), or for an actor's argument (`childrenAreBuiltForActorArgument`); a call of another module's
	/// public mock has its member (`mockPublicMockCallChildField(of:record:in:)`); a place that closes a cycle has the
	/// configuration of the type it repeats; a rename and a property nothing fulfills have none.
	func mockChildFieldSources(
		of children: [BodyEntry],
		requiresSendable: Bool,
		childrenAreBuiltForActorArgument: Bool,
		in world: some NodeRecordSources,
	) -> [MockLowering.ConfigurationRecord.ChildFieldSource]? {
		var sources = [MockLowering.ConfigurationRecord.ChildFieldSource]()
		for entry in children {
			switch entry {
			case let .place(child):
				guard let record = mockBuiltRecord(of: child) else { continue }
				let childDeclaration = declarationByVariant[Int(child)]
				if case .publicMockCall = record.target {
					guard let field = Self.mockPublicMockCallChildField(of: childDeclaration, in: world) else { return nil }
					sources.append(.spelled(field))
				} else {
					let childInstantiable = world.scope(of: childDeclaration).instantiable
					sources.append(.built(
						bindingName: record.property.label,
						hasConfiguration: Self.isOverriddenByConfiguration(childDeclaration, in: world),
						requiresSendable: requiresSendable || record.isSendable || childrenAreBuiltForActorArgument,
						concreteType: childInstantiable.concreteInstantiable,
						builderParameters: MockLowering.BuilderParameters(of: childInstantiable, usesMockInitializer: Self.usesHandWrittenMock(childDeclaration, in: world)),
						propertyType: (world.property(of: childDeclaration) ?? record.property).typeDescription,
					))
				}
			case let .closer(closingOn: child):
				let closedOn = declarationByVariant[Int(child)]
				guard let property = world.property(of: closedOn) else { return nil }
				let concreteType = world.scope(of: closedOn).instantiable.concreteInstantiable
				let field = MockLowering.cycleClosingOverridesField(boundAs: property.label, concreteType: concreteType)
				sources.append(.spelled(.init(name: field.name, typeSource: field.typeSource, defaultValue: field.defaultValue, sendableForm: .init(typeSource: field.typeSource, defaultValue: field.defaultValue, configuredTypeName: concreteType.asSource))))
			}
		}
		return sources
	}

	/// Whether a mock builds `declaration`'s node with its type's hand-written mock (`TypeFactsConstruction.handWrittenMock`).
	static func usesHandWrittenMock(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		world.construction(of: declaration) == .handWrittenMock && world.scope(of: declaration).instantiable.mockInitializer != nil
	}

	/// The member that configures `declaration`, a call of another module's public mock in a mock root's world, under its
	/// label: the called mock's own overrides where it takes them, else the closure that builds the called type
	/// (`publicMockCallOverrideType(of:calledType:calledFunction:builtAs:)`), as its own record reads it, never `@Sendable`;
	/// in a configuration `@Sendable`-typed, always a `@Sendable` closure (`MockLowering.PublicMockCallNode.sendableConfigurationFieldForm`).
	static func mockPublicMockCallChildField(of declaration: DeclarationID, in world: some NodeRecordSources) -> MockLowering.ConfigurationRecord.ChildField? {
		let scope = world.scope(of: declaration)
		guard let property = world.property(of: declaration), let call = scope.publicMockCall, let calledFunction = calledMockFunction(of: scope.instantiable, builtAs: property) else { return nil }
		let calledType = scope.instantiable.concreteInstantiable
		let type = publicMockCallOverrideType(of: call, calledType: calledType, calledFunction: calledFunction, builtAs: property)
		let sendableTypeSource = call.takesOverrides
			? "(@Sendable () -> \(calledType.asSource).\(ReservedName.mockOverridesTypeName))?"
			: "(@Sendable \(publicMockCallOverrideClosureType(of: call, calledFunction: calledFunction, builtAs: property)))?"
		return .init(
			name: property.label,
			typeSource: type.asSource,
			defaultValue: call.takesOverrides ? ".init()" : "nil",
			sendableForm: .init(typeSource: sendableTypeSource, defaultValue: "nil", configuredTypeName: nil),
		)
	}

	/// Whether the children of `declaration`, a node of a mock root's world built for an actor's argument where
	/// `isBuiltForActorArgument`, are built for one: an actor's initializer is sent each of its arguments, and a node built
	/// for one that is no wrapper builds its children for it too, where a wrapper's builder function does not. A child
	/// built for an argument an actor is sent reads its override inside the actor's isolation, as a `@Sendable` builder
	/// function does, so it is a `@Sendable` closure, as the walk spells it. A node two parents build is built for an
	/// actor's argument under one and not the other, so this follows the path, never a node's first parent.
	static func childrenAreBuiltForActorArgument(of declaration: DeclarationID, isBuiltForActorArgument: Bool, in world: some NodeRecordSources) -> Bool {
		guard declaration != 0 else { return world.scope(of: 0).instantiable.declarationType == .actorType }
		guard !isActorBuiltWithInitializer(declaration, in: world) else { return true }
		switch world.kind(of: declaration) {
		case .constant, .alias, .hole:
			return isBuiltForActorArgument
		case .instantiator, .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator, .lazy, .sendableLazy:
			return false
		}
	}
}

extension MockLowering.ConfigurationRecord.ChildFieldSource {
	/// The member of `mock()`'s `SafeDIOverrides` the field is at the root: its name, type and default, proven `Sendable`
	/// where it is a `@Sendable` closure or the configuration of a type whose configuration is `@Sendable`-typed.
	var overridesField: MockLowering.OverridesField {
		let field = childField
		let sendability: MockLowering.OverridesField.Sendability = switch self {
		case let .built(_, hasConfiguration, requiresSendable, concreteType, _, _):
			hasConfiguration ? .whenConfigurationIsTypedSendable(concreteType.asSource) : requiresSendable ? .always : .never
		case let .spelled(childField):
			childField.sendableForm?.configuredTypeName.map { .whenConfigurationIsTypedSendable($0) } ?? .never
		}
		return MockLowering.OverridesField(name: field.name, typeSource: field.typeSource, defaultValue: field.defaultValue, sendability: sendability)
	}
}
