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
		guard let overridesFields = Self.mockRootOverridesFields(rootEntries: bodyEntries[0], kinds: kinds, records: records, in: world),
		      let configurations = mockConfigurationRecords(in: world, handWrittenMockDefaultParameters: handWrittenMockDefaultParameters)
		else { return nil }
		let rootChildren = bodyEntries[0].map { entry in
			switch entry {
			case let .place(variant): declarationByVariant[Int(variant)]
			case let .closer(closingOn: variant): declarationByVariant[Int(variant)]
			}
		}
		return MockLowering.RootSurface(
			hasNodes: !rootChildren.isEmpty,
			buildsPropertyNode: rootChildren.contains { kinds[Int($0)] != .rename && kinds[Int($0)] != .mockUnavailableDependency },
			overridesFields: overridesFields,
			configurations: configurations,
		)
	}

	/// The members of `mock()`'s `SafeDIOverrides` that configure the root's children, in the order the root builds
	/// them, as the walk lists them (`MockLowering.TreeNode.overridesField`): `nil` where the root's body holds a child
	/// whose member no record says yet, a call of another module's public mock or a node on a cycle.
	static func mockRootOverridesFields(
		rootEntries: [BodyEntry],
		kinds: [NodeRecordKind],
		records: [PlaceRecord?],
		in world: some NodeRecordSources,
	) -> [MockLowering.OverridesField]? {
		var fields = [MockLowering.OverridesField]()
		for entry in rootEntries {
			switch entry {
			case let .place(variant):
				let declaration = world.declaration(of: variant)
				switch kinds[Int(declaration)] {
				case .mockConstruction:
					guard case let .built(record) = records[Int(variant)] else { return nil }
					fields.append(mockOverridesField(of: declaration, record: record, in: world))
				case .publicMockCall:
					guard let field = mockPublicMockCallOverridesField(of: declaration, in: world) else { return nil }
					fields.append(field)
				case .rename, .mockUnavailableDependency:
					// A rename reads no override, and a property nothing fulfills reads the one `mock()` binds before its nodes.
					break
				case .builtByInitializer, .inlineSeam, .seamCall, .unavailableDependency, .receivesOnlyIfAvailable, .erased, .lazy, .sendable, .seamHole, .cycle:
					return nil
				}
			case .closer:
				return nil
			}
		}
		return fields
	}

	/// The member of `mock()`'s overrides that configures `declaration`, a child of a mock root's world whose place is
	/// `record`: under the name it is bound by, its configuration where it is overridden by one
	/// (`isOverriddenByConfiguration(_:in:)`), else the closure that overrides it, `@Sendable` where a `@Sendable` function
	/// builds it or it is built for an actor's argument (`mockOverrideType(of:usesHandWrittenMock:isConfigured:isSendable:instantiable:)`), as its own record reads it.
	static func mockOverridesField(of declaration: DeclarationID, record: BuiltPlaceRecord, in world: some NodeRecordSources) -> MockLowering.OverridesField {
		let instantiable = world.scope(of: declaration).instantiable
		let isConfigured = isOverriddenByConfiguration(declaration, in: world)
		let usesHandWrittenMock = world.construction(of: declaration) == .handWrittenMock && instantiable.mockInitializer != nil
		let isSendable = record.isSendable || childrenAreBuiltForActorArgument(of: 0, isBuiltForActorArgument: false, in: world)
		let type = mockOverrideType(of: record, usesHandWrittenMock: usesHandWrittenMock, isConfigured: isConfigured, isSendable: isSendable, instantiable: instantiable)
		return MockLowering.OverridesField(
			name: record.property.label,
			typeSource: type.asSource,
			defaultValue: isConfigured ? ".init()" : "nil",
			sendability: isConfigured ? .whenConfigurationIsTypedSendable(instantiable.concreteInstantiable.asSource) : isSendable ? .always : .never,
		)
	}

	/// The member of the configuration around `declaration`, a call of another module's public mock in a mock root's
	/// world, that configures it, under its label: the called mock's own overrides where it takes them, else the closure
	/// that builds the called type (`publicMockCallOverrideType(of:calledType:calledFunction:builtAs:)`), as its own record
	/// reads it. Its record is never `@Sendable`.
	static func mockPublicMockCallOverridesField(of declaration: DeclarationID, in world: some NodeRecordSources) -> MockLowering.OverridesField? {
		let scope = world.scope(of: declaration)
		guard let property = world.property(of: declaration), let call = scope.publicMockCall, let calledFunction = calledMockFunction(of: scope.instantiable, builtAs: property) else { return nil }
		let type = publicMockCallOverrideType(of: call, calledType: scope.instantiable.concreteInstantiable, calledFunction: calledFunction, builtAs: property)
		return MockLowering.OverridesField(name: property.label, typeSource: type.asSource, defaultValue: call.takesOverrides ? ".init()" : "nil", sendability: .never)
	}

	/// The member that configures `declaration`, a call of another module's public mock in a mock root's world, in a
	/// configuration `@Sendable`-typed: always a `@Sendable` closure (`MockLowering.PublicMockCallNode.sendableConfigurationFieldForm`).
	static func mockPublicMockCallSendableFieldForm(of declaration: DeclarationID, in world: some NodeRecordSources) -> MockLowering.ConfigurationRecord.ChildField.SendableForm? {
		let scope = world.scope(of: declaration)
		guard let property = world.property(of: declaration), let call = scope.publicMockCall, let calledFunction = calledMockFunction(of: scope.instantiable, builtAs: property) else { return nil }
		return if call.takesOverrides {
			.init(typeSource: "(@Sendable () -> \(scope.instantiable.concreteInstantiable.asSource).\(ReservedName.mockOverridesTypeName))?", defaultValue: "nil", configuredTypeName: nil)
		} else {
			.init(typeSource: "(@Sendable \(publicMockCallOverrideClosureType(of: call, calledFunction: calledFunction, builtAs: property)))?", defaultValue: "nil", configuredTypeName: nil)
		}
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
