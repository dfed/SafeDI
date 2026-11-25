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

/// Stage D1, lane D: the parameters of a mock root's `mock()` other than its overrides, lowered from the mocked type's
/// declaration and its finished generator, as `mockRootParameters(instantiable:mockDefaults:)` computes them for
/// `generateMockRootCode`.
extension MockLowering {
	/// The parameters `mock()` takes before its overrides, each under its label, in the order `mock()` declares them.
	struct RootSignature {
		/// A parameter of `mock()`: the property it binds under its name, and its default, if it has one.
		struct Parameter {
			init(property: Property, defaultExpression: String?, typeSource: String? = nil, name: String? = nil) {
				self.property = property
				self.defaultExpression = defaultExpression
				self.typeSource = typeSource
				self.name = name ?? property.label
			}

			let property: Property
			let defaultExpression: String?
			/// The parameter's type as `mock()` declares it, where that is not the property's type as a parameter.
			let typeSource: String?
			/// The parameter's name: its property's label, unless `mock()` names it apart from another name in its scope.
			let name: String
		}

		/// The mocked type's `@Forwarded` properties, in property order.
		let forwardedParameters: [Parameter]
		/// The arguments of the mocked type's initializer that take a default and are none of its dependencies, in order.
		let rootDefaultParameters: [Parameter]
		/// The dependencies the tree receives that the mock cannot build, in the mock's order (`precedesInMockOrder`).
		let flatReceivedParameters: [Parameter]
		/// The `@Instantiated` dependencies of the mocked type and of the types of its tree that the mock cannot build, the
		/// mocked type's first, then in the order the walk of the tree first meets them.
		let uncoveredParameters: [Parameter]
		/// The same uncovered parameters, each named as `mock()` takes it, with the types that create it, as
		/// `MockRootParameters.flatUncoveredParameters` holds them.
		let uncoveredRootParameters: [ScopeGenerator.MockRootParameters.UncoveredParameter]
		/// The lines that document, above `mock()`, each uncovered parameter several types create
		/// (`MockRootParameters.UncoveredParameter.sharedValueDocumentation`).
		let sharedValueDocumentation: [String]
		/// The overrides of what the tree receives only if available that nothing in it provides, each a field of the
		/// overrides and a binding of `mock()`, in the mock's order (`precedesInMockOrder`), named apart after the parameters.
		let onlyIfAvailableOverrides: [ScopeGenerator.OnlyIfAvailableOverride]
		/// The name a receive of each label and type is handed where a flat received parameter or an override of it is named
		/// apart from its label, as the emitter's `renamedFlatParameterAndOverrideMap`.
		let renamesByLabelAndType: [String: [TypeDescription: String]]
		/// The name each uncovered parameter named apart from its label is passed to the types that instantiate it under, by
		/// label and type, as the emitter's `uncoveredDependencyNameMap`.
		let uncoveredParameterNamesByLabelAndType: [String: [TypeDescription: String]]
		/// The names the constructions of the root's tree declare `@escaping`, which the parameters spell so.
		let typesDeclaredEscaping: Set<TypeDescription>
		// The wrappers an internal mock binds around the instances it is passed of the
		// `LazilyInstantiated` values its tree receives and cannot build, each name and value, in property order.
		let lazilyInstantiatedBindings: [(name: String, value: String)]
		/// The name each receive of such a wrapper, by label and type, is passed by, never bound again under its label.
		let lazilyInstantiatedBindingNamesByLabelAndType: [String: [TypeDescription: String]]
		// The labels the builder functions of the root's tree declare, which a root alias named apart
		// is named apart from too (`renamingAliases`' reserved names).
		let namesDeclaredInBuilderFunctions: Set<String>

		// The builders the calls of other modules' public mocks pass up, in label order, each one
		// parameter of `mock()` among the flat received parameters.
		var passedUpBuilders = [PassedUpBuilder]()

		/// Every builder an internal mock takes, from the one classification of its parameters (`seamMockBuilders`), which the
		/// calls' builders and the places inside their fills read (`filledCallBuilders`).
		var seamMockBuilders = [ScopeGenerator.MockRootParameters.SeamMockBuilder]()

		/// The nodes of the tree that build a type, each before its children (`MockTreeNames.propertyNodes`).
		var propertyNodes = [ScopeGenerator.MockTreeNames.PropertyNode]()

		/// The name of the override of each property instantiated only if available that nothing fulfills
		/// (`MockRootParameters.unavailableDependencyOverrideProperties`), which the type that declares the property binds it
		/// from.
		var unavailableDependencyOverrideNames = [Property: String]()

		/// A builder `mock()` takes for every builder of one hole type and family its tree's calls pass up
		/// (`MockRootParameters.SeamMockBuilder`).
		struct PassedUpBuilder {
			/// The parameter's label.
			let label: String
			/// The name `mock()` binds the parameter under before anything else, apart from the names of the tree, or the label.
			let internalName: String
			/// The properties the calls' leaves receive the builder as, in the mock's order.
			let properties: [Property]
			/// The parameter's type as `mock()` declares it.
			let typeSource: String
			/// The parameter's default: a builder that returns `nil` for a builder of places instantiated only if available,
			/// whose type is optional, the value production gives a place nothing fulfills.
			let defaultExpression: String?
			// The places of a seam's own internal mock the builder builds, each the uncovered dependency
			// it stands for, named as its parameter would have been (`ScopeGenerator.seamMockBuilders`).
			let places: [ScopeGenerator.MockRootParameters.UncoveredParameter]
			// The hole type and family the builder builds, which a call's builder of that family joins.
			let family: ScopeGenerator.MockRootParameters.SeamMockBuilder.Family
			/// The adapters of the builder to the properties whose form takes a value it does not take.
			var adapters: [Adapter]

			/// A builder that takes nothing, adapted to a call's form that takes a value, which it drops.
			struct Adapter {
				let property: Property
				let name: String
				let typeSource: String
			}
		}

		// The builders that only build places, which no call passes up, each listed among the flat
		// received parameters by its label, in label order.
		var placeOnlyBuilderDeclarations: [(label: String, declaration: String)] {
			passedUpBuilders.compactMap { builder in
				builder.properties.isEmpty ? (builder.label, "\(builder.label): \(builder.typeSource)\(builder.defaultExpression.map { " = \($0)" } ?? "")") : nil
			}
		}

		// The properties of the places the builders build, which `mock()` takes no parameter of.
		var placeProperties: [Property] {
			passedUpBuilders.flatMap { $0.places.map(\.property) }
		}

		/// The name each property a call's leaf receives a passed-up builder as reads it under.
		var passedUpBuilderNames: [Property: String] {
			var names = [Property: String]()
			for builder in passedUpBuilders {
				for property in builder.properties {
					names[property] = builder.internalName
				}
				for adapter in builder.adapters {
					names[adapter.property] = adapter.name
				}
			}
			return names
		}

		/// The wrappers `mock()` binds, in each form their receives read, which the tree's receives of them find in scope.
		var lazilyInstantiatedProperties: Set<Property> {
			Set(lazilyInstantiatedBindingNamesByLabelAndType.flatMap { label, names in
				names.keys.map { Property(label: label, typeDescription: $0) }
			})
		}

		/// The lines that bind the wrappers around the instances `mock()` is passed, at `indent`.
		func lazilyInstantiatedBindingLines(indent: String) -> [String] {
			lazilyInstantiatedBindings.map { "\(indent)let \($0.name) = \($0.value)" }
		}

		/// The properties the forwarded, received and uncovered parameters bind, which every node of the tree is built after.
		/// The default-valued ones are the initializer's alone.
		var properties: Set<Property> {
			// Every property a call's leaf receives a passed-up builder as, in whichever form.
			// Also the properties of the places the builders build.
			Set((forwardedParameters + flatReceivedParameters + uncoveredParameters).map(\.property)).union(passedUpBuilders.flatMap(\.properties)).union(placeProperties)
		}

		/// The names the parameters and the overrides' bindings bind, which no node of the tree may bind again.
		var labels: Set<String> {
			// A builder a call passes up that `mock()` binds apart is in scope under that name alone,
			// which the tree's names are apart from, so a node may bind its label.
			let internalNameByLabel = Dictionary(passedUpBuilders.map { ($0.label, $0.internalName) }, uniquingKeysWith: { first, _ in first })
			return Set(parameters.map { internalNameByLabel[$0.name] ?? $0.name })
				.union(onlyIfAvailableOverrides.map(\.name))
				// A builder that only builds places is in scope under its internal name.
				.union(passedUpBuilders.filter(\.properties.isEmpty).map(\.internalName))
		}

		/// The properties of the `@Instantiated` dependencies the mock cannot build, which a type of the tree is passed.
		var uncoveredProperties: Set<Property> {
			Set(uncoveredParameters.map(\.property)).union(placeProperties)
		}

		/// The lines that document, above `mock()`, each parameter several types create, at `indent`.
		func sharedValueDocumentationLines(indent: String) -> [String] {
			sharedValueDocumentation.map { "\(indent)\($0)" }
		}

		/// Every parameter, in the order `mock()` declares them.
		var parameters: [Parameter] {
			forwardedParameters + rootDefaultParameters + flatReceivedParameters + uncoveredParameters
		}

		/// The parameters' declarations in `mock()`, at `indent`, with `builders` (label-sorted, each the full
		/// `label: Type = default` text) listed among the flat received parameters as the emitter lists a seam's own mock's
		/// builders: each before the first flat received parameter whose property's label sorts after the builder's, the rest
		/// after the last, before the uncovered parameters.
		// The `@Sendable` autoclosure parameters, by the property each stands for.
		// Also each place a builder builds, which the type that instantiates it binds from the builder
		// (`ScopeGenerator.SendableAutoclosureParameter.binding`).
		var sendableAutoclosureBindings: [Property: ScopeGenerator.SendableAutoclosureParameter] {
			var bindings = [Property: ScopeGenerator.SendableAutoclosureParameter]()
			for parameter in uncoveredRootParameters where parameter.isSendableAutoclosure {
				bindings[parameter.property] = ScopeGenerator.SendableAutoclosureParameter(name: parameter.label, localName: MockLowering.sendableAutoclosureLocalName(of: parameter.label))
			}
			for builder in passedUpBuilders {
				for place in builder.places {
					bindings[place.property] = ScopeGenerator.SendableAutoclosureParameter(name: place.label, localName: builder.internalName, valueType: place.property.typeDescription)
				}
			}
			return bindings
		}

		/// The lines that read each `@Sendable` autoclosure parameter into a local before any builder function, which the
		/// types that instantiate its value call (`ScopeGenerator.SendableAutoclosureParameter`).
		func sendableAutoclosureLocalBindingLines(indent: String) -> [String] {
			uncoveredRootParameters.filter(\.isSendableAutoclosure).map { parameter in
				"\(indent)let \(MockLowering.sendableAutoclosureLocalName(of: parameter.label)) = \(parameter.label)"
			}
		}

		func parameterLines(indent: String, builders: [(label: String, declaration: String)] = []) -> [String] {
			var lines = (forwardedParameters + rootDefaultParameters).map { line(of: $0, indent: indent) }
			var buildersToList = builders[...]
			for parameter in flatReceivedParameters {
				while let builder = buildersToList.first, builder.label < parameter.property.label {
					lines.append("\(indent)\(builder.declaration)")
					buildersToList = buildersToList.dropFirst()
				}
				lines.append(line(of: parameter, indent: indent))
			}
			lines.append(contentsOf: buildersToList.map { "\(indent)\($0.declaration)" })
			lines.append(contentsOf: uncoveredParameters.map { line(of: $0, indent: indent) })
			return lines
		}

		private func line(of parameter: Parameter, indent: String) -> String {
			let typeSource = parameter.typeSource ?? parameter.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource
			return if let defaultExpression = parameter.defaultExpression {
				"\(indent)\(parameter.name): \(typeSource) = \(defaultExpression)"
			} else {
				"\(indent)\(parameter.name): \(typeSource)"
			}
		}
	}
}

extension ScopeGenerator {
	/// The parameters of this mock root's `mock()` other than its overrides.
	func lowerRootSignature(of instantiable: Instantiable, context: MockContext) -> MockLowering.RootSignature {
		lowerRootSignature(of: instantiable, flatParameterMockDefaults: context.flatParameterMockDefaults)
	}

	/// The same, read with the defaults of the module's flat parameters, which is all of the module's mock context the
	/// signature reads, so that `query needs`, which has no mock context, reads the same signature.
	func lowerRootSignature(
		of instantiable: Instantiable,
		flatParameterMockDefaults: [TypeDescription: FlatParameterMockDefault],
	) -> MockLowering.RootSignature {
		// The one classification of the mock's parameters (`mockRootParameters(instantiable:mockDefaults:treeNames:)`),
		// read from this generator's tree.
		let tree = treeNames(of: instantiable)
		let parameters = mockRootParameters(instantiable: instantiable, mockDefaults: flatParameterMockDefaults, treeNames: tree.names)
		let forwardedParameters = parameters.forwardedDependencies.map { dependency in
			MockLowering.RootSignature.Parameter(property: dependency.property, defaultExpression: parameters.forwardedParameterDefaults[dependency.property.label]?.expression)
		}
		var rootDefaultParameters = [MockLowering.RootSignature.Parameter]()
		for (argument, defaultExpression) in Self.defaultValuedMockParameterArguments(of: instantiable) {
			// `mock()` takes an `@autoclosure` as one and passes its call, so the value is evaluated where the type is built. A
			// throwing one is taken as one that does not throw, since `mock()` calls it outside any function that throws.
			rootDefaultParameters.append(MockLowering.RootSignature.Parameter(
				property: Property(label: argument.label, typeDescription: argument.typeDescription),
				defaultExpression: defaultExpression,
				typeSource: argument.typeDescription.autoclosureTakenWithoutThrowing.asFunctionParameter.asSource,
			))
		}
		// A public mock takes the wrapper its tree receives in place of the instance it stands for
		// (`publicMockWrapperParameterByInstance`), and binds no wrapper for it.
		let wrapperParameterByInstance = parameters.publicMockWrapperParameterByInstance
		let flatReceivedProperties = parameters.flatReceivedProperties.map { wrapperParameterByInstance[$0] ?? $0 }
		let onlyIfAvailableReceivedProperties = parameters.onlyIfAvailableReceivedProperties.map { wrapperParameterByInstance[$0] ?? $0 }
		let wrappersTakenAsParameters = Set(wrapperParameterByInstance.values.map(\.asUnwrappedProperty))
		let wrapperByInstanceBesideForwardedProperty = parameters.lazilyInstantiatedPropertyByInstanceBesideForwardedProperty
		let forwardedAndDefaultLabels = Set(forwardedParameters.map(\.name)).union(rootDefaultParameters.map(\.name))
		let treeBindingNames = Self.bindingNames(of: tree.names.rootProperties, labels: Set(tree.names.rootProperties.map(\.label)), labelMap: parameters.rootLabelMap)
		let namesDeclaredInBuilderFunctions = tree.names.namesDeclaredInBuilderFunctions
		let namedUncoveredParameters = parameters.uncoveredParameters
		// A type that generates its dependency tree takes, in its internal mock, a builder for each hole type and family of its
		// places in place of their parameters (`seamMockBuilders`), which keep the names their parameters would have had.
		let flatUncoveredParameters = parameters.flatUncoveredParameters
		let flatUncoveredNames = flatUncoveredParameters.map(\.label)
		// An internal mock's override of what only calls of other modules' public mocks receive is
		// named after the others, and apart from them and the flat received parameters, which keep their names beside it.
		let onlyPublicMockCallsReceive = parameters.onlyIfAvailableReceivedPropertiesOnlyPublicMockCallsReceive
		// The builders `mock()` takes for its own places and for what its calls pass up, each listed among the flat received
		// parameters by its label; the classification takes no flat parameter of what they build.
		let passedUpBuilders = parameters.seamMockBuilders.compactMap { builder -> MockLowering.RootSignature.PassedUpBuilder? in
			guard !builder.isOptional, !builder.places.isEmpty || !builder.passedUpProperties.isEmpty else { return nil }
			return MockLowering.RootSignature.PassedUpBuilder(
				label: builder.label,
				internalName: builder.internalName,
				properties: builder.passedUpProperties,
				typeSource: builder.parameterType.asSource,
				defaultExpression: builder.family.holeType.builtType.isOptional ? ReservedName.nilBuilderSource : nil,
				places: builder.places,
				family: builder.family,
				adapters: builder.adapters.map { .init(property: $0.property, name: $0.name, typeSource: $0.typeDescription.asSource) },
			)
		}
		let builderLabels = Set(passedUpBuilders.map(\.label))
		let otherFlatReceivedNames = Self.namesApart(
			preferredNames: flatReceivedProperties.map(\.label),
			// A public mock's wrapper parameter is named apart by the value it stands for, as the
			// emitter names the instance it takes as that wrapper (`publicMockWrapperParameters`).
			typeDescriptions: flatReceivedProperties.map { property in
				instantiable.generateMock == .public && property.typeDescription.lazilyInstantiatedInstanceType != nil
					? property.asValidatedForDependencyCycles.typeDescription
					: wrapperByInstanceBesideForwardedProperty[property]?.typeDescription ?? property.typeDescription
			},
			namesInScope: forwardedAndDefaultLabels
				.union(flatUncoveredNames)
				.union(builderLabels)
				.union(onlyIfAvailableReceivedProperties.filter { !onlyPublicMockCallsReceive.contains($0) }.map(\.label))
				.union(treeBindingNames),
			reservedNames: namesDeclaredInBuilderFunctions,
		)
		var flatReceivedNames = otherFlatReceivedNames
		let ownOverrides = Self.onlyIfAvailableOverrides(
			for: onlyIfAvailableReceivedProperties.filter { !onlyPublicMockCallsReceive.contains($0) },
			namedAfter: wrapperByInstanceBesideForwardedProperty,
			namesInMockScope: forwardedAndDefaultLabels.union(flatUncoveredNames).union(treeBindingNames),
			reservedNames: Set(otherFlatReceivedNames).union(builderLabels).union(namesDeclaredInBuilderFunctions),
		)
		let overridesOnlyPublicMockCallsReceive = onlyPublicMockCallsReceive.isEmpty ? [] : Self.onlyIfAvailableOverrides(
			for: onlyIfAvailableReceivedProperties.filter { onlyPublicMockCallsReceive.contains($0) },
			namedAfter: wrapperByInstanceBesideForwardedProperty,
			namesInMockScope: forwardedAndDefaultLabels.union(flatUncoveredNames).union(treeBindingNames).union(otherFlatReceivedNames).union(builderLabels).union(ownOverrides.map(\.name)),
			reservedNames: Set(otherFlatReceivedNames).union(builderLabels).union(namesDeclaredInBuilderFunctions),
		)
		var ownOverridesInOrder = ownOverrides.makeIterator()
		var overridesOnlyPublicMockCallsReceiveInOrder = overridesOnlyPublicMockCallsReceive.makeIterator()
		var onlyIfAvailableOverrides = onlyIfAvailableReceivedProperties.compactMap { property in
			onlyPublicMockCallsReceive.contains(property) ? overridesOnlyPublicMockCallsReceiveInOrder.next() : ownOverridesInOrder.next()
		}
		// A public mock names its parameters as the one function that names a public mock root's does
		// (`mockRootParameterNames(of:)`), whose overrides stand for the instances its wrapper parameters take the place of.
		let parameterNames: MockRootParameterNames
		if instantiable.generateMock == .public {
			parameterNames = Self.mockRootParameterNames(of: parameters)
			flatReceivedNames = parameterNames.flatReceivedNames
			onlyIfAvailableOverrides = parameterNames.onlyIfAvailableOverrides.map { override in
				guard let wrapper = wrapperParameterByInstance[override.receivedProperty] else { return override }
				return OnlyIfAvailableOverride(receivedProperty: wrapper, typeDescription: wrapper.typeDescription, name: override.name)
			}
		} else {
			parameterNames = MockRootParameterNames(
				treeBindingNames: treeBindingNames,
				namesDeclaredInBuilderFunctions: namesDeclaredInBuilderFunctions,
				otherFlatLabels: Array(forwardedAndDefaultLabels.union(flatUncoveredNames).union(onlyIfAvailableReceivedProperties.filter { !onlyPublicMockCallsReceive.contains($0) }.map(\.label))),
				flatReceivedNames: flatReceivedNames,
				onlyIfAvailableOverrides: onlyIfAvailableOverrides,
			)
		}
		// A wrapper a public mock takes in place of the instance is no rename: its receivers, and the types that read its
		// instance, are passed it by name (`lazilyInstantiatedBindingNameMap`).
		var renamesByLabelAndType = [String: [TypeDescription: String]]()
		for (index, (property, name)) in zip(flatReceivedProperties, flatReceivedNames).enumerated()
			where name != property.label && wrapperByInstanceBesideForwardedProperty[property] == nil
			&& wrapperParameterByInstance[parameters.flatReceivedProperties[index]] == nil
		{
			renamesByLabelAndType[property.label, default: [:]][property.typeDescription] = name
		}
		for (index, override) in onlyIfAvailableOverrides.enumerated()
			where override.name != override.receivedProperty.label && wrapperByInstanceBesideForwardedProperty[override.receivedProperty] == nil
			&& wrapperParameterByInstance[parameters.onlyIfAvailableReceivedProperties[index]] == nil
		{
			renamesByLabelAndType[override.receivedProperty.label, default: [:]][override.receivedProperty.typeDescription] = override.name
		}
		// `mock()` binds each wrapper around the instance it is passed, under a name apart from its label, which the types that
		// receive the wrapper, the mocked type included, are passed by name (`mockRootTopLevelNames`).
		let topLevelNames = Self.mockRootTopLevelNames(of: parameters, parameterNames: parameterNames)
		var lazilyInstantiatedBindings = [(name: String, value: String)]()
		for (property, bindingName) in zip(topLevelNames.lazilyInstantiatedPropertiesToBind, topLevelNames.lazilyInstantiatedBindingNames) where !wrappersTakenAsParameters.contains(property) {
			let instanceProperty = property.asValidatedForDependencyCycles
			let wrapperTypeSource = property.typeDescription.asSource
			// The parameter may be named apart from its label; an optional instance, or an override, is mapped.
			if let index = flatReceivedProperties.firstIndex(of: instanceProperty) {
				lazilyInstantiatedBindings.append((bindingName, "\(wrapperTypeSource) { \(flatReceivedNames[index]) }"))
			} else if tree.mockedTypeUncoveredProperties.contains(instanceProperty),
			          let parameter = flatUncoveredParameters.first(where: { $0.property == instanceProperty })
			{
				// The instance is the parameter of a dependency the mocked type instantiates, which is always passed.
				lazilyInstantiatedBindings.append((bindingName, "\(wrapperTypeSource) { \(parameter.label) }"))
			} else if let index = flatReceivedProperties.firstIndex(of: Property(label: instanceProperty.label, typeDescription: .optional(instanceProperty.typeDescription))) {
				lazilyInstantiatedBindings.append((bindingName, "\(flatReceivedNames[index]).map { instance in \(wrapperTypeSource) { instance } }"))
			} else {
				let instanceName = onlyIfAvailableOverrides.first { $0.receivedProperty.asUnwrappedProperty == instanceProperty }?.name ?? instanceProperty.label
				lazilyInstantiatedBindings.append((bindingName, "\(instanceName).map { instance in \(wrapperTypeSource) { instance } }"))
			}
		}
		let lazilyInstantiatedBindingNamesByLabelAndType = topLevelNames.lazilyInstantiatedBindingNameMap
		var uncoveredParameterNamesByLabelAndType = [String: [TypeDescription: String]]()
		for parameter in namedUncoveredParameters where parameter.label != parameter.property.label {
			uncoveredParameterNamesByLabelAndType[parameter.property.label, default: [:]][parameter.property.typeDescription] = parameter.label
		}
		var flatReceivedParameters = zip(flatReceivedProperties, flatReceivedNames).map { property, name in
			MockLowering.RootSignature.Parameter(
				property: property,
				defaultExpression: flatParameterMockDefaults[property.typeDescription]?.expression,
				name: name,
			)
		}
		// A builder a call passes up is listed among the flat received parameters by its label, once
		// for the properties it joins.
		for builder in passedUpBuilders {
			guard let property = builder.properties.first else { continue }
			let position = flatReceivedParameters.firstIndex { $0.property.label > builder.label } ?? flatReceivedParameters.endIndex
			flatReceivedParameters.insert(.init(property: property, defaultExpression: builder.defaultExpression, typeSource: builder.typeSource, name: builder.label), at: position)
		}
		var signature = MockLowering.RootSignature(
			forwardedParameters: forwardedParameters,
			rootDefaultParameters: rootDefaultParameters,
			flatReceivedParameters: flatReceivedParameters,
			uncoveredParameters: flatUncoveredParameters.map {
				MockLowering.RootSignature.Parameter(property: $0.property, defaultExpression: nil, typeSource: $0.isSendableAutoclosure ? "@autoclosure @escaping @Sendable () -> \($0.typeSource)" : $0.typeSource, name: $0.label)
			},
			uncoveredRootParameters: flatUncoveredParameters,
			sharedValueDocumentation: flatUncoveredParameters.flatMap(\.sharedValueDocumentation),
			onlyIfAvailableOverrides: onlyIfAvailableOverrides,
			renamesByLabelAndType: renamesByLabelAndType,
			uncoveredParameterNamesByLabelAndType: uncoveredParameterNamesByLabelAndType,
			typesDeclaredEscaping: typesDeclaredEscaping,
			lazilyInstantiatedBindings: lazilyInstantiatedBindings,
			lazilyInstantiatedBindingNamesByLabelAndType: lazilyInstantiatedBindingNamesByLabelAndType,
			namesDeclaredInBuilderFunctions: namesDeclaredInBuilderFunctions,
		)
		signature.passedUpBuilders = passedUpBuilders
		signature.seamMockBuilders = parameters.seamMockBuilders
		signature.propertyNodes = tree.names.propertyNodes
		for override in onlyIfAvailableOverrides where parameters.unavailableDependencyOverrideProperties.contains(override.receivedProperty) {
			signature.unavailableDependencyOverrideNames[override.receivedProperty] = override.name
		}
		// The overrides' bindings, and the receives of parameters and overrides named apart, are
		// `mock()`'s and the walk's (`lowerMockRootWithTree(of:context:)`).
		return signature
	}

	/// What the names of `mock()`'s parameters are chosen from in the tree of a mock root: its bindings, the names its
	/// builder functions declare, and the `@Instantiated` dependencies the mock cannot build.
	struct TreeNames {
		/// What the classification reads of the tree.
		let names: ScopeGenerator.MockTreeNames
		/// The `@Instantiated` dependencies of the mocked type itself that the mock cannot build.
		let mockedTypeUncoveredProperties: Set<Property>
	}

	/// The names in the tree of the mocked type, `instantiable`, that the names of `mock()`'s parameters are chosen from. The
	/// uncovered dependencies are the mocked type's in its declaration order, then each node's, in the order a walk of the
	/// tree in generation order first meets them; a dependency is uncovered where no child of the type that instantiates it
	/// builds its label (for the mocked type, its property or a `LazilyInstantiated` of it). The tree is walked with a stack,
	/// since it can be as deep as the module has types.
	/// - Parameter readsFills: Whether to read the families of the builders the calls pass up, and the calls that fill
	///   builders with the places inside their fills, which only the mock's own lowering reads.
	func treeNames(of instantiable: Instantiable, readsFills: Bool = true) -> TreeNames {
		/// A node of the tree that builds a type, and where it is among the nodes the type above it builds: its declaration
		/// index there, or none for a node the mock promotes, then its index in generation order. A node keeps only its own
		/// position and the index of the node above it, so a deep tree copies no path per node; the path and the names the
		/// builder functions around a node declare are read back up the chain only for an uncovered dependency, which few
		/// nodes have.
		struct Node {
			let parentIndex: Int?
			let position: Position
			/// The labels the node's own builder function declares, which hide a parameter of the same label beneath it.
			var namesDeclared: [String]
		}
		struct Visit {
			let generator: ScopeGenerator
			let nodeIndex: Int
			/// Whether the node is built inside a `@Sendable` builder function: its own, or one around it.
			let isInsideSendableFunction: Bool
		}
		struct Position: Comparable {
			let declarationIndex: Int
			let generationIndex: Int

			static func < (lhs: Position, rhs: Position) -> Bool {
				(lhs.declarationIndex, lhs.generationIndex) < (rhs.declarationIndex, rhs.generationIndex)
			}
		}
		var nodes = [Node]()
		func path(toNodeAt index: Int?) -> [Position] {
			var path = [Position]()
			var current = index
			while let nodeIndex = current {
				path.append(nodes[nodeIndex].position)
				current = nodes[nodeIndex].parentIndex
			}
			return path.reversed()
		}
		/// Whether a builder function around the node, its own excluded, declares `label`.
		func isDeclaredAround(nodeAt index: Int, _ label: String) -> Bool {
			var current = nodes[index].parentIndex
			while let nodeIndex = current {
				guard !nodes[nodeIndex].namesDeclared.contains(label) else { return true }
				current = nodes[nodeIndex].parentIndex
			}
			return false
		}
		/// The generators of the children that build a type, each at its position among them.
		func propertyChildren(of generator: ScopeGenerator, declaredBy dependencies: [Dependency], under parentIndex: Int?, insideSendableFunction: Bool) -> [Visit] {
			generator.orderedChildGenerators.enumerated().compactMap { generationIndex, child in
				guard case let .property(_, property, _, _, _, _) = child.scopeData, !child.isUnavailableDependency else { return nil }
				let position = Position(declarationIndex: dependencies.firstIndex(where: { $0.property.label == property.label }) ?? Int.max, generationIndex: generationIndex)
				nodes.append(Node(parentIndex: parentIndex, position: position, namesDeclared: []))
				return Visit(
					generator: child,
					nodeIndex: nodes.count - 1,
					isInsideSendableFunction: insideSendableFunction || child.buildsInSendableFunction,
				)
			}
		}

		func isInstantiated(_ dependency: Dependency) -> Bool {
			switch dependency.source {
			case .instantiated:
				true
			case .received, .aliased, .forwarded:
				false
			}
		}
		var properties = [Property]()
		var dependencyByProperty = [Property: Dependency]()
		var creatingTypesByProperty = [Property: [(nodeIndex: Int?, type: TypeDescription)]]()
		var hiddenProperties = Set<Property>()
		var propertiesInstantiatedInSendableFunction = Set<Property>()
		var namesDeclaredInBuilderFunctions = Set<String>()
		func add(_ dependency: Dependency, createdBy type: TypeDescription, atNode nodeIndex: Int?, isHiddenWhereReferenced: Bool, isInstantiatedInSendableFunction: Bool) {
			if dependencyByProperty[dependency.property] == nil {
				properties.append(dependency.property)
				dependencyByProperty[dependency.property] = dependency
			}
			creatingTypesByProperty[dependency.property, default: []].append((nodeIndex: nodeIndex, type: type))
			if isHiddenWhereReferenced {
				hiddenProperties.insert(dependency.property)
			}
			if isInstantiatedInSendableFunction {
				propertiesInstantiatedInSendableFunction.insert(dependency.property)
			}
		}

		/// The properties the sites of holes among a generator's children bind, and those it binds to `nil` because they are
		/// instantiated only if available and nothing fulfills their type, neither of which a parameter covers
		/// (`ScopeGenerator.uncoveredInstantiatedDependencies(ofMockedType:treePropertyNodes:holeSiteProperties:)`).
		func holeSiteProperties(of generator: ScopeGenerator) -> [Property] {
			generator.orderedChildGenerators.compactMap { child in
				switch child.scopeData {
				case let .hole(property, _, .some):
					property
				case let .property(_, property, _, _, _, _):
					child.isUnavailableDependency ? property : nil
				case .hole, .alias, .fill, .root:
					nil
				}
			}
		}
		/// The properties a generator's type instantiates only if available that nothing fulfills.
		func unavailableDependencyProperties(of generator: ScopeGenerator) -> [Property] {
			generator.orderedChildGenerators.lazy.filter(\.isUnavailableDependency).compactMap(\.property)
		}
		var unavailableProperties = unavailableDependencyProperties(of: self)
		let rootChildren = propertyChildren(of: self, declaredBy: instantiable.dependencies, under: nil, insideSendableFunction: false)
		let rootHoleSiteProperties = holeSiteProperties(of: self)
		var builtProperties = Set<Property>(rootHoleSiteProperties)
		for child in rootChildren {
			guard let property = child.generator.property else { continue }
			builtProperties.insert(property)
			if let instanceProperty = property.asLazilyInstantiatedInstanceProperty {
				builtProperties.insert(instanceProperty)
			}
		}
		// The mocked type is built in the body of `mock()`, outside every builder function.
		var mockedTypeUncoveredDependencies = [Dependency]()
		for dependency in instantiable.dependencies where isInstantiated(dependency) && !builtProperties.contains(dependency.property) {
			mockedTypeUncoveredDependencies.append(dependency)
			add(dependency, createdBy: instantiable.concreteInstantiable, atNode: nil, isHiddenWhereReferenced: false, isInstantiatedInSendableFunction: false)
		}
		var passedUpBuilderProperties = Set<Property>()
		var holdsCallFillingBuilder = false
		var visits = Array(rootChildren.reversed())
		var builderFunctionNames = Set<String>()
		var propertyNodes = [ScopeGenerator.MockTreeNames.PropertyNode]()
		// The index in `propertyNodes` of each node visited, by its index in `nodes`; a node is visited before its children.
		var propertyNodeIndexByNodeIndex = [Int: Int]()
		while let visit = visits.popLast() {
			guard case let .property(nodeInstantiable, nodeProperty, _, erasedToConcreteExistential, isPropertyCycle, _) = visit.generator.scopeData else { continue }
			propertyNodeIndexByNodeIndex[visit.nodeIndex] = propertyNodes.count
			propertyNodes.append(ScopeGenerator.MockTreeNames.PropertyNode(
				parentIndex: nodes[visit.nodeIndex].parentIndex.flatMap { propertyNodeIndexByNodeIndex[$0] },
				property: nodeProperty,
				instantiable: nodeInstantiable,
				erasedToConcreteExistential: erasedToConcreteExistential,
				isPropertyCycle: isPropertyCycle,
				generator: visit.generator,
				isInsideSendableFunction: visit.isInsideSendableFunction,
			))
			builderFunctionNames.insert(ScopeGenerator.functionName(toBuildPropertyNamed: nodeProperty.label))
			let publicMockCall = visit.generator.publicMockCall
			if publicMockCall != nil, visit.generator.fillsABuilder {
				holdsCallFillingBuilder = true
			}
			for dependency in nodeInstantiable.dependencies {
				namesDeclaredInBuilderFunctions.insert(dependency.property.label)
				if let publicMockCall, publicMockCall.passesUpBuilder(receivedAs: dependency.property) {
					passedUpBuilderProperties.insert(dependency.property)
				}
			}
			// A node that closes a cycle builds nothing beneath it, and its dependencies surface as no parameter.
			guard !isPropertyCycle else { continue }
			if !visit.isInsideSendableFunction {
				for property in unavailableDependencyProperties(of: visit.generator) where !unavailableProperties.contains(property) {
					unavailableProperties.append(property)
				}
			}
			let children = propertyChildren(of: visit.generator, declaredBy: nodeInstantiable.dependencies, under: visit.nodeIndex, insideSendableFunction: visit.isInsideSendableFunction)
			// Most types build every dependency they instantiate, so the labels their children build are gathered only for a
			// type that instantiates one.
			let childLabels: Set<String> = nodeInstantiable.dependencies.contains(where: isInstantiated)
				? Set(children.compactMap(\.generator.property?.label)).union(holeSiteProperties(of: visit.generator).map(\.label))
				: []
			var namesDeclared = [String]()
			for dependency in nodeInstantiable.dependencies {
				let label = dependency.property.label
				guard isInstantiated(dependency), !childLabels.contains(label) else {
					namesDeclared.append(label)
					continue
				}
				// A builder function around the type that declares the label would hide the parameter there.
				add(
					dependency,
					createdBy: nodeInstantiable.concreteInstantiable,
					atNode: visit.nodeIndex,
					isHiddenWhereReferenced: isDeclaredAround(nodeAt: visit.nodeIndex, label),
					isInstantiatedInSendableFunction: visit.isInsideSendableFunction,
				)
			}
			nodes[visit.nodeIndex].namesDeclared = namesDeclared
			visits.append(contentsOf: children.reversed())
		}
		var uncoveredDependencies = [ScopeGenerator.MockTreeNames.UncoveredDependency]()
		for property in properties {
			guard let dependency = dependencyByProperty[property] else { continue }
			var creatingTypes = [TypeDescription]()
			let creations = creatingTypesByProperty[property] ?? []
			let orderedCreations = creations.count < 2
				? creations
				: creations.map { (path: path(toNodeAt: $0.nodeIndex), type: $0.type) }.sorted(by: { $0.path.lexicographicallyPrecedes($1.path) }).map { (nodeIndex: Int?.none, type: $0.type) }
			for (_, type) in orderedCreations where !creatingTypes.contains(type) {
				creatingTypes.append(type)
			}
			uncoveredDependencies.append(ScopeGenerator.MockTreeNames.UncoveredDependency(
				dependency: dependency,
				isHiddenWhereReferenced: hiddenProperties.contains(property),
				isInstantiatedInSendableFunction: propertiesInstantiatedInSendableFunction.contains(property),
				creatingTypes: creatingTypes,
			))
		}
		// The families of the builders the calls pass up, which only a tree that passes one up walks for.
		var names = ScopeGenerator.MockTreeNames(
			rootProperties: rootChildren.compactMap { child in
				guard case let .property(_, property, _, _, _, _) = child.generator.scopeData else { return nil }
				return property
			},
			mockedTypeUncoveredDependencies: mockedTypeUncoveredDependencies,
			uncoveredDependencies: uncoveredDependencies,
			namesDeclaredInBuilderFunctions: namesDeclaredInBuilderFunctions,
			builderFunctionNames: builderFunctionNames,
		)
		names.propertyNodes = propertyNodes
		names.unavailableDependencyProperties = unavailableProperties
		names.rootHoleSiteProperties = rootHoleSiteProperties
		// The families of the builders the calls pass up, which only a tree that passes one up walks for.
		if readsFills, !passedUpBuilderProperties.isEmpty {
			names.passedUpBuilderFamilies = passedUpBuilderFamilies(of: orderedChildGenerators)
		}
		// The calls that fill builders and the places inside their fills, which only a tree that holds such a call walks for.
		if readsFills, holdsCallFillingBuilder {
			let found = callsFillingBuilders(of: orderedChildrenComputedAfresh(propertiesGeneratedLater: []))
			names.fillPlaces = found.fillPlaces
			names.namesDeclaredInFills = found.namesFillsDeclare
			names.filledCalls = found.filledCalls
		}
		return TreeNames(
			names: names,
			mockedTypeUncoveredProperties: Set(mockedTypeUncoveredDependencies.map(\.property)),
		)
	}
}
