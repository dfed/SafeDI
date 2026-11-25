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
/// The place records of a mock's closers and defaults: what the mock walk hands production's record functions
/// (`ScopeGenerator.closingPlaceRecord(of:…)`) at a place that closes a cycle, or whose builder function a default, a
/// `@Sendable` autoclosure or a receiver's rebinding decides, so the type key can lay a mock out as it lays out production.
extension MockLowering.Walk {
	/// The record of the closer of `generator`, bound as `bindingName`, which calls the function named
	/// `closedOnFunctionName`, or `nil` where the type key does not plan it: a member of a loop of builders, or a place the
	/// generator writes with anything the type key does not plan (`ScopeGenerator.isPlannedByGenerator`).
	func closerRecord(
		of generator: ScopeGenerator,
		instantiable: Instantiable,
		property: Property,
		erasedToConcreteExistential: Bool,
		forwardedProperties: [Property],
		closedOnFunctionName: String,
	) -> PlaceRecord? {
		generator.closingPlaceRecord(
			of: property,
			instantiable: instantiable,
			forwardedProperties: forwardedProperties,
			erasedToConcreteExistential: erasedToConcreteExistential,
			closedOnFunctionName: closedOnFunctionName,
			unavailableProperties: unavailableProperties,
			isPlannedAtPlace: loopMembership == nil,
			readNames: cycleParameterReadNames(of: generator),
		)
	}

	/// Records the closer of `generator` that `record` was made for, at the walk's place, with the place it closes on: the
	/// nearest place around the walk that builds the declaration it repeats, whose configuration it hands the function on
	/// once that place is finished (`leaveClosedOnPlace(of:readsOverride:)`).
	mutating func recordCloser(_ record: PlaceRecord, of generator: ScopeGenerator) {
		closerAndDefaultRecords[childIndexPath] = record
		guard let closedOnDeclaration = generator.closedOnDeclaration,
		      let index = closedOnPlacesByLabel[closedOnDeclaration.property.label]?.lastIndex(where: { $0.declaration == closedOnDeclaration })
		else { return }
		closedOnPlacesByLabel[closedOnDeclaration.property.label]?[index].closers.append((path: childIndexPath, generator: generator))
	}

	/// Enters the place the walk builds `declaration` at, which a closer beneath can close on.
	mutating func enterClosedOnPlace(declaring declaration: ScopeGenerator.BuiltDeclaration) {
		closedOnPlacesByLabel[declaration.property.label, default: []].append(ClosedOnPlace(declaration: declaration))
	}

	/// Leaves the place `node` is built at, once its configuration is known, and hands each closer beneath that closes on it
	/// the place's configuration (`MockLowering.passedArguments(ofCloser:…)`): its configuration struct where it has one, else
	/// its override closure, read where the place reads its override (`readsOverride`). A public mock's places take another
	/// configuration, which its own records hand.
	mutating func leaveClosedOnPlace(of node: MockLowering.ConstantNode, readsOverride: Bool) {
		guard let place = closedOnPlacesByLabel[node.property.label]?.popLast(), !place.closers.isEmpty, !buildsPublicMock else { return }
		let configurationType = MockLowering.configurationType(of: node)
		let staysOutsideSendableFunctions = if node.hasConfiguration {
			!sendableConfigurationTypeNames.contains(node.instantiable.concreteInstantiable.asSource)
		} else {
			!node.requiresSendable
		}
		for closer in place.closers {
			guard case var .closer(record) = closerAndDefaultRecords[closer.path] else { continue }
			record.passedArguments = MockLowering.passedArguments(
				ofCloser: closer.generator,
				closedOnBuiltWithHandWrittenMock: node.usesMockInitializer,
				configurationType: configurationType,
				closedOnIsProvided: readsOverride,
				staysOutsideSendableFunctions: staysOutsideSendableFunctions,
			)
			closerAndDefaultRecords[closer.path] = .closer(record)
		}
	}

	/// The names the mock binds the labels of `generator`'s cycle parameters apart under, where it binds one apart, by the
	/// parameter's property: what `MockLowering.cycleParameterArguments(of:…)` passes in place of the label.
	func cycleParameterReadNames(of generator: ScopeGenerator) -> [Property: String] {
		let lazilyInstantiatedInstanceProperties = generator.mockLoweringCallSiteLazilyInstantiatedInstanceProperties
		var readNames = [Property: String]()
		for parameter in generator.cycleParameters where !unavailableProperties.contains(parameter.property) {
			let label = parameter.property.label
			let name: String? = if lazilyInstantiatedInstanceProperties.contains(parameter.property.asUnwrappedProperty) {
				// The instance is read from the wrapper of its label the mock names apart, where it names one apart.
				[Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType].lazy.compactMap { renames[label]?[.simple(name: $0, generics: [parameter.property.asUnwrappedProperty.typeDescription])] }.first
			} else {
				lazilyInstantiatedNames[label]?[parameter.property.typeDescription] ?? renames[label]?[parameter.property.typeDescription] ?? renames[label]?[parameter.property.asUnwrappedProperty.typeDescription]
			}
			if let name, name != label {
				readNames[parameter.property] = name
			}
		}
		return readNames
	}
}

extension MockLowering.Walk {
	/// A place around the walk that a closer beneath it can close on, and the closers beneath it that do, by their paths of
	/// child indices.
	struct ClosedOnPlace {
		let declaration: ScopeGenerator.BuiltDeclaration
		var closers = [(path: [Int], generator: ScopeGenerator)]()
	}
}

extension MockLowering {
	/// The type of what configures `node` in its parent's configuration: its configuration struct, or the optional closure
	/// that overrides how it is built (`ConstantNode.overridesField`), as a type.
	static func configurationType(of node: ConstantNode) -> TypeDescription {
		if node.hasConfiguration {
			.nested(name: "SafeDIMockConfiguration", parentType: node.instantiable.concreteInstantiable, generics: [])
		} else {
			.optional(node.builderClosureTypeDescription(isSendable: node.requiresSendable))
		}
	}

	/// Whether a node the mock builds writes a builder function: where it builds children or a wrapper, as production's
	/// place does, and also where its function binds a receive named apart again (`receiverBindings`), reads a default from
	/// its configuration (`readsDefaults`), or binds the value of a `@Sendable` autoclosure parameter of `mock()`
	/// (`hasSendableAutoclosureBindings`), which production's place never does: the input the mock walk hands production's
	/// built record function for whether the place has a function.
	static func writesBuilderFunction(hasChildren: Bool, isWrapped: Bool, hasReceiverBindings: Bool, readsDefaults: Bool, hasSendableAutoclosureBindings: Bool) -> Bool {
		hasChildren || isWrapped || hasReceiverBindings || readsDefaults || hasSendableAutoclosureBindings
	}

	/// The statements that begin a node's builder function, before its children's, as places the type key reads: each
	/// receive named apart bound again under its label, then the value of each `@Sendable` autoclosure parameter the node
	/// instantiates, as `ConstantNode.receiverBindingLines(indent:)` writes them, unindented. Each is a place written as
	/// text whose one read is the name it binds from: the name the receive is bound apart under, or the local `mock()`
	/// reads the autoclosure into (`RootDeclarationRecord`).
	static func receiverBindingPlaces(
		receiverBindings: [(property: Property, name: String)],
		sendableAutoclosureBindings: [(property: Property, parameter: ScopeGenerator.SendableAutoclosureParameter)],
	) -> [GeneratedCode] {
		var places = [GeneratedCode]()
		for binding in receiverBindings {
			let read = Property(label: binding.name, typeDescription: binding.property.typeDescription)
			places.append(.place(PlacePlan(
				code: .text("let \(binding.property.label): \(binding.property.typeDescription.asSource) = \(binding.name)"),
				record: .alias(AliasPlaceRecord(
					property: binding.property,
					fulfillingProperty: read,
					text: "let \(binding.property.label): \(binding.property.typeDescription.asSource) = \(binding.name)",
					reads: [PlaceRead(argumentLabel: binding.property.label, label: binding.name, property: read, source: .binding(label: binding.name))],
				)),
			)))
		}
		for (property, parameter) in sendableAutoclosureBindings {
			let read = sendableAutoclosureLocalProperty(of: parameter, builds: property)
			places.append(.place(PlacePlan(
				code: .text(parameter.binding),
				record: .alias(AliasPlaceRecord(
					property: Property(label: parameter.name, typeDescription: property.typeDescription),
					fulfillingProperty: nil,
					text: parameter.binding,
					reads: [PlaceRead(argumentLabel: parameter.name, label: parameter.localName, property: read, source: .binding(label: parameter.localName))],
				)),
			)))
		}
		return places
	}

	/// The declaration `mock()` binds a `@Sendable` autoclosure parameter's closure under at the root's top, which builds
	/// `property`: what a binding of its value reads, and what the root records it as (`RootDeclarationRecord`).
	static func sendableAutoclosureLocalProperty(of parameter: ScopeGenerator.SendableAutoclosureParameter, builds property: Property) -> Property {
		let valueType = parameter.valueType ?? property.typeDescription
		return Property(
			label: parameter.localName,
			typeDescription: .attributed(.closure(arguments: [], isAsync: false, doesThrow: false, returnType: valueType), specifiers: [], attributes: ["Sendable"]),
		)
	}
}

extension MockLowering {
	/// How the record of a built place says its construction, where production's record cannot: as production's call, as
	/// a construction that reads defaults from its configuration or calls its type's hand-written mock, or not at all.
	enum ConstructionRecording: Equatable {
		/// Production's record says the construction: it calls the initializer with dependency reads alone.
		case asProduction
		/// The record says the construction once `MockLowering.Walk.configuring(_:with:instantiable:)` rewrites it.
		case configured(ConfiguredConstruction)
		/// No record can say it yet, and the place keeps its text: a public mock's construction function.
		case unrecorded

		/// The construction to record, where the place has one apart from production's.
		var recorded: ConfiguredConstruction? {
			switch self {
			case let .configured(construction):
				construction
			case .asProduction,
			     .unrecorded:
				nil
			}
		}
	}

	/// What a built place's record holds in place of production's call where its construction reads defaults from its
	/// configuration or calls its type's hand-written mock: whether it calls the mock, the parameter its function takes its
	/// configuration through, whose members its defaults read (`defaultArgumentReads(of:…)`), and whether an override
	/// reaches the place.
	struct ConfiguredConstruction: Hashable {
		let usesMockInitializer: Bool
		let configurationParameter: ConfigurationParameter
		let overrideReachable: Bool
	}
}

extension MockLowering.Walk {
	/// How the record of `node`, a place of `instantiable` built as `usesMockInitializer` says, says its construction.
	/// `readsOverride` is whether an override reaches the place.
	mutating func configuredConstruction(of node: MockLowering.ConstantNode, instantiable: Instantiable, readsOverride: Bool, usesMockInitializer: Bool) -> MockLowering.ConstructionRecording {
		guard usesMockInitializer || constructionReadsConfiguration(of: instantiable, usesMockInitializer: usesMockInitializer) else { return .asProduction }
		// A public mock builds such a place with its type's construction function, which no record says yet.
		guard !buildsPublicMock else { return .unrecorded }
		return .configured(MockLowering.ConfiguredConstruction(
			usesMockInitializer: usesMockInitializer,
			configurationParameter: MockLowering.ConfigurationParameter(
				concreteType: instantiable.concreteInstantiable,
				builtWithHandWrittenMock: usesMockInitializer,
				configurationType: MockLowering.configurationType(of: node),
			),
			overrideReachable: readsOverride,
		))
	}

	/// `record`, production's record of a place of `instantiable`, with the construction `construction` says: its target the
	/// type's hand-written mock where the place calls it, and its arguments the construction's, each dependency read as
	/// production reads it under the construction's own label, and each default a member of the place's configuration.
	/// `nil` where the record cannot say the construction: a dependency the construction passes that production's record
	/// does not read, or defaults read from a configuration built afresh.
	mutating func configuring(_ record: PlaceRecord, with construction: MockLowering.ConfiguredConstruction, instantiable: Instantiable) -> PlaceRecord? {
		guard case let .built(built) = record else { return record }
		var dependencyReads = [PlaceRead]()
		let passedDependencies = mockConstruction(of: instantiable, usesMockInitializer: construction.usesMockInitializer).callSiteArguments.compactMap { argument in
			MockLowering.dependency(passedTo: argument, among: instantiable.dependencies).map { (argument: argument, dependency: $0) }
		}
		for (argument, dependency) in passedDependencies {
			guard let read = built.arguments.first(where: { $0.property == dependency.property }) else { return nil }
			dependencyReads.append(PlaceRead(argumentLabel: argument.label, label: read.label, property: read.property, source: read.source, staysOutsideSendableFunctions: read.staysOutsideSendableFunctions))
		}
		guard let reads = defaultArgumentReads(
			of: instantiable,
			usesMockInitializer: construction.usesMockInitializer,
			dependencyReads: dependencyReads,
			configurationParameter: construction.configurationParameter,
			overrideReachable: construction.overrideReachable,
		) else { return nil }
		var configured = BuiltPlaceRecord(
			property: built.property,
			isErased: built.isErased,
			concreteType: built.concreteType,
			isExtension: built.isExtension,
			target: construction.usesMockInitializer
				? .mock(instantiable.concreteInstantiable, name: instantiable.customMockName ?? InstantiableVisitor.mockMethodName)
				: built.target,
			arguments: reads.arguments,
			forwardedProperties: built.forwardedProperties,
			cycleParameters: built.cycleParameters,
			callCycleArguments: built.callCycleArguments,
			functionName: built.functionName,
			isSendable: built.isSendable,
			typesDeclaredEscaping: built.typesDeclaredEscaping,
			lineEnd: built.lineEnd,
			hasFunction: built.hasFunction,
			children: built.children,
			node: built.node,
			sharingFields: built.sharingFields,
		)
		if !reads.argumentValues.isEmpty {
			configured.argumentValues = reads.argumentValues
		}
		return .built(configured)
	}
}

extension MockLowering.Walk {
	/// The override alternative of `node`, at the walk's place in an internal mock, read at the path of the configuration
	/// its path key reads (`BuiltPlaceConfigurationContext.pathKeyConfiguration`) rather than at the local a `@Sendable`
	/// builder function's extractor reads it into: the record's form, which `relativeConfiguration(of:…)` reads of the
	/// configuration the place's call hands its function. `nil` in a public mock, whose configurations are never
	/// `Sendable` and whose places in a `@Sendable` function keep their text.
	func internalMockOverrideAlternative(of node: MockLowering.ConstantNode) -> ConstructionAlternative? {
		guard !buildsPublicMock, let configuration = builtPlaceConfigurationContexts[childIndexPath]?.pathKeyConfiguration else { return nil }
		return ConstructionAlternative(
			closure: node.hasConfiguration ? .member(ReservedName.configurationBuilderPropertyName, of: configuration) : configuration,
			bindingName: ReservedName.configurationBuilderPropertyName,
			requiresAbsent: [],
			use: .calledWithConstructionArguments,
			resultWrapper: node.overrideResultWrapper,
		)
	}
}
