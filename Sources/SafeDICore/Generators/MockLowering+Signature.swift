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
/// `generateMockRootCode`. Each kind of parameter the lowering does not lower yet returns the rule it belongs to.
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
		// D1 lane hook (lane C): the wrappers an internal mock binds around the instances it is passed of the
		// `LazilyInstantiated` values its tree receives and cannot build, each name and value, in property order.
		let lazilyInstantiatedBindings: [(name: String, value: String)]
		/// The name each receive of such a wrapper, by label and type, is passed by, never bound again under its label.
		let lazilyInstantiatedBindingNamesByLabelAndType: [String: [TypeDescription: String]]

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
			Set((forwardedParameters + flatReceivedParameters + uncoveredParameters).map(\.property))
		}

		/// The names the parameters and the overrides' bindings bind, which no node of the tree may bind again.
		var labels: Set<String> {
			Set(parameters.map(\.name)).union(onlyIfAvailableOverrides.map(\.name))
		}

		/// The properties of the `@Instantiated` dependencies the mock cannot build, which a type of the tree is passed.
		var uncoveredProperties: Set<Property> {
			Set(uncoveredParameters.map(\.property))
		}

		/// The lines that document, above `mock()`, each parameter several types create, at `indent`.
		func sharedValueDocumentationLines(indent: String) -> [String] {
			sharedValueDocumentation.map { "\(indent)\($0)" }
		}

		/// Every parameter, in the order `mock()` declares them.
		var parameters: [Parameter] {
			forwardedParameters + rootDefaultParameters + flatReceivedParameters + uncoveredParameters
		}

		/// The signature without the flat received parameters of `properties`, which another kind of parameter takes in their
		/// place: a builder a call of another module's public mock passes up (lane C's family).
		func removingFlatReceivedParameters(_ properties: Set<Property>) -> RootSignature {
			RootSignature(
				forwardedParameters: forwardedParameters,
				rootDefaultParameters: rootDefaultParameters,
				flatReceivedParameters: flatReceivedParameters.filter { !properties.contains($0.property) },
				uncoveredParameters: uncoveredParameters,
				uncoveredRootParameters: uncoveredRootParameters,
				sharedValueDocumentation: sharedValueDocumentation,
				onlyIfAvailableOverrides: onlyIfAvailableOverrides,
				renamesByLabelAndType: renamesByLabelAndType,
				uncoveredParameterNamesByLabelAndType: uncoveredParameterNamesByLabelAndType,
				typesDeclaredEscaping: typesDeclaredEscaping,
				lazilyInstantiatedBindings: lazilyInstantiatedBindings,
				lazilyInstantiatedBindingNamesByLabelAndType: lazilyInstantiatedBindingNamesByLabelAndType,
			)
		}

		/// The parameters' declarations in `mock()`, at `indent`, with `builders` (label-sorted, each the full
		/// `label: Type = default` text) listed among the flat received parameters as the emitter lists a seam's own mock's
		/// builders: each before the first flat received parameter whose property's label sorts after the builder's, the rest
		/// after the last, before the uncovered parameters.
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
	/// The parameters of this mock root's `mock()` other than its overrides, or the first rule they meet that the lowering
	/// does not lower yet.
	func lowerRootSignature(of instantiable: Instantiable, context: MockContext) -> MockLowering.Lowering<MockLowering.RootSignature> {
		lowerRootSignature(of: instantiable, flatParameterMockDefaults: context.flatParameterMockDefaults)
	}

	/// The same, read with the defaults of the module's flat parameters, which is all of the module's mock context the
	/// signature reads, so that `query needs`, which has no mock context, reads the same signature.
	func lowerRootSignature(
		of instantiable: Instantiable,
		flatParameterMockDefaults: [TypeDescription: FlatParameterMockDefault],
	) -> MockLowering.Lowering<MockLowering.RootSignature> {
		var forwardedParameters = [MockLowering.RootSignature.Parameter]()
		for dependency in instantiable.dependencies.sorted(by: { $0.property < $1.property }) where dependency.source == .forwarded {
			// A forwarded wrapper declares the forms of its instance beside it, which the tree's receives read.
			guard dependency.property.propertyType.isConstant else { return .unsupported(.wrapper) }
			// The default the construction (the type's own hand-written mock, else its initializer) gives the parameter of its
			// label wins over the hand-written mock the parameter's type has.
			let constructionDefault = MockLowering.rootConstructionInitializer(of: instantiable)?.arguments.first { $0.innerLabel == dependency.property.label }?.defaultValueExpression
			forwardedParameters.append(MockLowering.RootSignature.Parameter(
				property: dependency.property,
				defaultExpression: constructionDefault ?? flatParameterMockDefaults[dependency.property.typeDescription]?.expression,
			))
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
		// D1 lane hook (lane C): the mock takes no parameter or override for what only calls of other modules' public mocks
		// receive and every call omits (`receivedOnlyByPublicMockCallsLeftOut`), and takes what they pass as a receive only if
		// available.
		let receivedOnlyByPublicMockCallsLeftOut = Self.receivedOnlyByPublicMockCallsLeftOut(
			receivedOnlyByPublicMockCalls: receivedOnlyByPublicMockCalls,
			passedByPublicMockCalls: passedByPublicMockCalls,
			labelsReadInsideSendableFunctions: passedByPublicMockCallLabelsReadInsideSendableFunctions(of: instantiable),
		)
		// Each in the mocked type's own spelling where it receives the dependency, else its receivers' most explicit one.
		var receivedProperties = MockedTypeSpellings(of: instantiable, treeReceivedProperties: receivedProperties).spellings(of: receivedProperties.subtracting(receivedOnlyByPublicMockCallsLeftOut))
		var onlyIfAvailableUnwrappedReceivedProperties = receivedOnlyByPublicMockCalls.isEmpty
			? onlyIfAvailableUnwrappedReceivedProperties
			: onlyIfAvailableUnwrappedReceivedProperties.filter { property in
				receivedProperties.contains(property) || receivedProperties.contains(property.asOptionalProperty)
			}
		let forwardedProperties = instantiable.forwardedReceivableProperties
		/// Whether a property the mocked type forwards fulfills a receive of `property`, as a forwarded `x: X` fulfills an
		/// `x: X?` too.
		func isFulfilledByForwardedProperty(_ property: Property) -> Bool {
			forwardedProperties.contains(property) || forwardedProperties.contains(property.asUnwrappedProperty)
		}
		// The mock wraps the instance it is passed for a `LazilyInstantiated` it cannot build.
		// D1 lane hook (lane C): a public mock takes the wrapper itself (`publicMockWrapperParameters`), where its tree receives
		// the label in no other form; one beside its instance, or defaulted to a wrapper around a hand-written mock, is not
		// lowered yet. An internal mock takes the wrapper's instance by value and binds the wrapper apart from its label
		// (`generateMockRootCode`'s `lazilyInstantiatedReceivedProperties`), where the tree provides neither the wrapper nor
		// its instance and the mocked type forwards no form of the label.
		var wrappedReceivedProperties = [Property]()
		if instantiable.generateMock == .public {
			let receivedLabels = receivedProperties.map(\.label)
			guard !receivedProperties.contains(where: { property in
				guard let instanceType = property.typeDescription.lazilyInstantiatedInstanceType else { return false }
				return receivedLabels.count(where: { $0 == property.label }) > 1
					|| flatParameterMockDefaults[instanceType.unwrapped] != nil
			}) else { return .unsupported(.wrapper) }
		} else {
			for property in receivedProperties where property.typeDescription.lazilyInstantiatedInstanceType != nil {
				guard !Self.provides(property, declaredProperties: propertiesToDeclare, forwardedProperties: []),
				      !isFulfilledByForwardedProperty(property)
				else { continue }
				let instance = property.asValidatedForDependencyCycles
				// An instance the mocked type itself instantiates, which the mock may not build, is not lowered yet.
				guard !instantiable.dependencies.contains(where: { dependency in
					guard case .instantiated = dependency.source else { return false }
					return dependency.property == instance.asUnwrappedProperty || dependency.lazilyInstantiatedInstanceProperty == instance.asUnwrappedProperty
				}) else { return .unsupported(.wrapper) }
				// A wrapper whose instance the tree provides is not made from it: the mock takes the wrapper as it is.
				guard !Self.provides(instance, declaredProperties: propertiesToDeclare, forwardedProperties: []) else { continue }
				// The instance of one beside a property of its label and type the mocked type forwards is named apart from it,
				// which the lowering does not lower yet.
				guard !isFulfilledByForwardedProperty(instance) else { return .unsupported(.wrapper) }
				wrappedReceivedProperties.append(property)
			}
			wrappedReceivedProperties.sort()
		}
		if !wrappedReceivedProperties.isEmpty {
			// A property received by value and the instance of a `LazilyInstantiated` received under its label are one
			// parameter, spelled as the form the mock's order lists first.
			var parameterProperties = Set<Property>()
			for property in receivedProperties.sorted(by: { $0.precedesInMockOrder($1) }) where !isFulfilledByForwardedProperty(property) {
				parameterProperties.insert(property.asValidatedForDependencyCycles)
			}
			receivedProperties = parameterProperties
			// A dependency some receiver requires, as `LazilyInstantiated` or by value, is required.
			onlyIfAvailableUnwrappedReceivedProperties = Set(onlyIfAvailableUnwrappedReceivedProperties.map(\.asValidatedForDependencyCycles))
				.subtracting(
					requiredReceivedProperties.lazy
						.filter { !isFulfilledByForwardedProperty($0) }
						.map(\.asValidatedForDependencyCycles.asUnwrappedProperty),
				)
		}
		let receivedNonOptionalProperties = Set(receivedProperties.filter { !$0.typeDescription.isOptional })
		var flatReceivedProperties = [Property]()
		var onlyIfAvailableReceivedProperties = [Property]()
		for property in receivedProperties.sorted(by: { $0.precedesInMockOrder($1) }) {
			// A forwarded `x: X` fulfills an `x: X?` too, and so does a received `x: X`, which the parameter of its own binds.
			guard !forwardedProperties.contains(property),
			      !property.typeDescription.isOptional
			      || !receivedNonOptionalProperties.contains(property.asUnwrappedProperty) && !forwardedProperties.contains(property.asUnwrappedProperty)
			else { continue }
			// A node the mock promotes for an optional receive binds its non-optional value, which provides this one.
			guard property.typeDescription.isOptional || !propertiesToDeclare.contains(property.asOptionalProperty) else { return .unsupported(.flatParameter) }
			guard !Self.provides(property, declaredProperties: propertiesToDeclare, forwardedProperties: []) else { continue }
			// A property every receiver receives only if available is an override, defaulting to `nil`; one any requires is a
			// parameter.
			if onlyIfAvailableUnwrappedReceivedProperties.contains(property.asUnwrappedProperty) {
				onlyIfAvailableReceivedProperties.append(property)
			} else {
				flatReceivedProperties.append(property)
			}
		}
		let tree = treeNames(of: instantiable)
		let uncoveredParameters = tree.uncoveredParameters
		let forwardedAndDefaultLabels = Set(forwardedParameters.map(\.name)).union(rootDefaultParameters.map(\.name))
		let treeBindingNames = Self.bindingNames(of: tree.rootPropertyNodes, besideParametersKeepingTheirLabels: forwardedAndDefaultLabels)
		let namesDeclaredInBuilderFunctions = tree.namesDeclaredInBuilderFunctions
		// An uncovered dependency is named apart from another of its label, a forwarded or default-valued parameter, a binding
		// of the root's tree, a label the mocked type receives or aliases, and a label a builder function around a type it is
		// passed to declares.
		let uncoveredNames = Self.namesApart(
			preferredNames: uncoveredParameters.map(\.property.label),
			typeDescriptions: uncoveredParameters.map(\.property.typeDescription),
			namesInScope: forwardedAndDefaultLabels
				.union(treeBindingNames)
				.union(instantiable.dependencies.lazy.compactMap { dependency in
					switch dependency.source {
					case .received, .aliased:
						dependency.property.label
					case .instantiated, .forwarded:
						nil
					}
				}),
			reservedNames: namesDeclaredInBuilderFunctions
				.union(flatReceivedProperties.map(\.label))
				.union(onlyIfAvailableReceivedProperties.map(\.label)),
			hiddenEntries: tree.uncoveredIndicesHiddenWhereReferenced,
		)
		// D1 lane hook (lane C): an internal mock's override of what only calls of other modules' public mocks receive is
		// named after the others, and apart from them and the flat received parameters, which keep their names beside it.
		let onlyPublicMockCallsReceive: Set<Property> = instantiable.generateMock == .public || receivedOnlyByPublicMockCalls.isEmpty
			? []
			: Self.onlyIfAvailableReceivedProperties(onlyIfAvailableReceivedProperties, receivedOnlyBy: receivedOnlyByPublicMockCalls)
		// A flat received parameter is named apart from the other parameters, the overrides and the root's tree bindings.
		let flatReceivedNames = Self.namesApart(
			preferredNames: flatReceivedProperties.map(\.label),
			typeDescriptions: flatReceivedProperties.map(\.typeDescription),
			namesInScope: forwardedAndDefaultLabels
				.union(uncoveredNames)
				.union(onlyIfAvailableReceivedProperties.filter { !onlyPublicMockCallsReceive.contains($0) }.map(\.label))
				.union(treeBindingNames),
			reservedNames: namesDeclaredInBuilderFunctions,
		)
		let ownOverrides = Self.onlyIfAvailableOverrides(
			for: onlyIfAvailableReceivedProperties.filter { !onlyPublicMockCallsReceive.contains($0) },
			namedAfter: [:],
			namesInMockScope: forwardedAndDefaultLabels.union(uncoveredNames).union(treeBindingNames),
			reservedNames: Set(flatReceivedNames).union(namesDeclaredInBuilderFunctions),
		)
		let overridesOnlyPublicMockCallsReceive = onlyPublicMockCallsReceive.isEmpty ? [] : Self.onlyIfAvailableOverrides(
			for: onlyIfAvailableReceivedProperties.filter { onlyPublicMockCallsReceive.contains($0) },
			namedAfter: [:],
			namesInMockScope: forwardedAndDefaultLabels.union(uncoveredNames).union(treeBindingNames).union(flatReceivedNames).union(ownOverrides.map(\.name)),
			reservedNames: Set(flatReceivedNames).union(namesDeclaredInBuilderFunctions),
		)
		var ownOverridesInOrder = ownOverrides.makeIterator()
		var overridesOnlyPublicMockCallsReceiveInOrder = overridesOnlyPublicMockCallsReceive.makeIterator()
		let onlyIfAvailableOverrides = onlyIfAvailableReceivedProperties.compactMap { property in
			onlyPublicMockCallsReceive.contains(property) ? overridesOnlyPublicMockCallsReceiveInOrder.next() : ownOverridesInOrder.next()
		}
		var renamesByLabelAndType = [String: [TypeDescription: String]]()
		for (property, name) in zip(flatReceivedProperties, flatReceivedNames) where name != property.label {
			renamesByLabelAndType[property.label, default: [:]][property.typeDescription] = name
		}
		for override in onlyIfAvailableOverrides where override.name != override.receivedProperty.label {
			renamesByLabelAndType[override.receivedProperty.label, default: [:]][override.receivedProperty.typeDescription] = override.name
		}
		// D1 lane hook (lane C): `mock()` binds each wrapper around the instance it is passed, under a name apart from its label
		// (`mockRootTopLevelNames`), which the types that receive the wrapper, the mocked type included, are passed by name.
		var lazilyInstantiatedPropertiesToBind = [Property]()
		for property in wrappedReceivedProperties where !lazilyInstantiatedPropertiesToBind.contains(property.asUnwrappedProperty) {
			lazilyInstantiatedPropertiesToBind.append(property.asUnwrappedProperty)
		}
		// An instance the mocked type instantiates and the mock cannot build is the parameter the wrapper is made from, which
		// the lowering does not bind yet.
		guard !lazilyInstantiatedPropertiesToBind.contains(where: { property in
			uncoveredParameters.contains { $0.property == property.asValidatedForDependencyCycles }
		}) else { return .unsupported(.wrapper) }
		let lazilyInstantiatedBindingNames = Self.namesApart(
			preferredNames: lazilyInstantiatedPropertiesToBind.map { property in
				"\(property.label)_\(property.propertyType.isSendable ? "sendableLazilyInstantiated" : "lazilyInstantiated")".spelledAsJoinedIdentifier
			},
			typeDescriptions: lazilyInstantiatedPropertiesToBind.map(\.asValidatedForDependencyCycles.typeDescription),
			namesInScope: forwardedAndDefaultLabels
				.union(uncoveredNames)
				.union(onlyIfAvailableReceivedProperties.filter { !onlyPublicMockCallsReceive.contains($0) }.map(\.label))
				.union(flatReceivedProperties.map(\.label))
				.union(flatReceivedNames)
				.union(onlyIfAvailableOverrides.map(\.name))
				.union(treeBindingNames)
				.union(namesDeclaredInBuilderFunctions),
			reservedNames: [],
		)
		var lazilyInstantiatedBindings = [(name: String, value: String)]()
		var lazilyInstantiatedBindingNameByProperty = [Property: String]()
		for (property, bindingName) in zip(lazilyInstantiatedPropertiesToBind, lazilyInstantiatedBindingNames) {
			lazilyInstantiatedBindingNameByProperty[property] = bindingName
			let instanceProperty = property.asValidatedForDependencyCycles
			let wrapperTypeSource = property.typeDescription.asSource
			// The parameter may be named apart from its label; an optional instance, or an override, is mapped.
			if let index = flatReceivedProperties.firstIndex(of: instanceProperty) {
				lazilyInstantiatedBindings.append((bindingName, "\(wrapperTypeSource) { \(flatReceivedNames[index]) }"))
			} else if let index = flatReceivedProperties.firstIndex(of: Property(label: instanceProperty.label, typeDescription: .optional(instanceProperty.typeDescription))) {
				lazilyInstantiatedBindings.append((bindingName, "\(flatReceivedNames[index]).map { instance in \(wrapperTypeSource) { instance } }"))
			} else {
				let instanceName = onlyIfAvailableOverrides.first { $0.receivedProperty.asUnwrappedProperty == instanceProperty }?.name ?? instanceProperty.label
				lazilyInstantiatedBindings.append((bindingName, "\(instanceName).map { instance in \(wrapperTypeSource) { instance } }"))
			}
		}
		var lazilyInstantiatedBindingNamesByLabelAndType = [String: [TypeDescription: String]]()
		for property in wrappedReceivedProperties {
			lazilyInstantiatedBindingNamesByLabelAndType[property.label, default: [:]][property.typeDescription] = lazilyInstantiatedBindingNameByProperty[property.asUnwrappedProperty]
		}
		// A call that takes the wrapper only if available is passed the binding a required receive of the label makes.
		for property in wrappedReceivedProperties where !property.typeDescription.isOptional {
			let optionalType = TypeDescription.optional(property.typeDescription)
			if lazilyInstantiatedBindingNamesByLabelAndType[property.label]?[optionalType] == nil {
				lazilyInstantiatedBindingNamesByLabelAndType[property.label]?[optionalType] = lazilyInstantiatedBindingNameByProperty[property]
			}
		}
		var uncoveredParameterNamesByLabelAndType = [String: [TypeDescription: String]]()
		for (parameter, name) in zip(uncoveredParameters, uncoveredNames) where name != parameter.property.label {
			uncoveredParameterNamesByLabelAndType[parameter.property.label, default: [:]][parameter.property.typeDescription] = name
		}
		let flatReceivedParameters = zip(flatReceivedProperties, flatReceivedNames).map { property, name in
			MockLowering.RootSignature.Parameter(
				property: property,
				defaultExpression: flatParameterMockDefaults[property.typeDescription]?.expression,
				name: name,
			)
		}
		// A type that generates its dependency tree takes a builder for each hole type of its places in place of their
		// parameters (`seamMockBuilders`), which lane C's family lowers.
		guard !instantiable.generatesDependencyTree || uncoveredParameters.isEmpty else { return .unsupported(.holeSite) }
		// A value a type built in a `@Sendable` builder function instantiates is a `@Sendable` autoclosure, which `mock()`
		// reads into a local and each type that instantiates it calls; the lowering builds neither yet.
		guard !uncoveredParameters.contains(where: \.isSendableAutoclosure) else { return .unsupported(.wrapper) }
		let namedUncoveredParameters = zip(uncoveredParameters, uncoveredNames).map { parameter, name in
			MockRootParameters.UncoveredParameter(
				property: parameter.property,
				label: name,
				typeSource: parameter.typeSource,
				instantiatedType: parameter.instantiatedType,
				isSendableAutoclosure: parameter.isSendableAutoclosure,
				creatingTypes: parameter.creatingTypes,
			)
		}
		let signature = MockLowering.RootSignature(
			forwardedParameters: forwardedParameters,
			rootDefaultParameters: rootDefaultParameters,
			flatReceivedParameters: flatReceivedParameters,
			uncoveredParameters: namedUncoveredParameters.map {
				MockLowering.RootSignature.Parameter(property: $0.property, defaultExpression: nil, typeSource: $0.typeSource, name: $0.label)
			},
			uncoveredRootParameters: namedUncoveredParameters,
			sharedValueDocumentation: namedUncoveredParameters.flatMap(\.sharedValueDocumentation),
			onlyIfAvailableOverrides: onlyIfAvailableOverrides,
			renamesByLabelAndType: renamesByLabelAndType,
			uncoveredParameterNamesByLabelAndType: uncoveredParameterNamesByLabelAndType,
			typesDeclaredEscaping: typesDeclaredEscaping,
			lazilyInstantiatedBindings: lazilyInstantiatedBindings,
			lazilyInstantiatedBindingNamesByLabelAndType: lazilyInstantiatedBindingNamesByLabelAndType,
		)
		// D1 lane hook (lane B): the overrides' bindings, and the receives of parameters and overrides named apart, are
		// `mock()`'s and the walk's (`lowerMockRootWithTree(of:context:)`).
		// No two parameters or bindings of `mock()` share a name: the emitter names them apart.
		guard signature.labels.count == signature.parameters.count + signature.onlyIfAvailableOverrides.count else { return .unsupported(.siblingLabelCollision) }
		return .lowered(signature)
	}

	/// The names the property nodes at a mock root's level, `properties`, are bound under, as
	/// `ScopeGenerator.bindingNames(of:labels:labelMap:)` gives them: each node's label, or, where nodes of the level or a
	/// parameter that keeps its label (`parameterLabels`) share it, a name apart, as `disambiguatePropertyLabels` names it.
	private static func bindingNames(of properties: [Property], besideParametersKeepingTheirLabels parameterLabels: Set<String>) -> Set<String> {
		var seenLabels = Set<String>()
		var collidingLabels = parameterLabels.intersection(properties.map(\.label))
		for property in properties where !seenLabels.insert(property.label).inserted {
			collidingLabels.insert(property.label)
		}
		guard !collidingLabels.isEmpty else { return seenLabels }
		let collidingProperties = properties.filter { collidingLabels.contains($0.label) }
		let names = identifierSafeNames(
			for: collidingProperties.map { property in
				let instantiatedType = property.typeDescription.asInstantiatedType
				return (label: property.label, suffixTypes: [instantiatedType.simplified, instantiatedType, property.typeDescription])
			},
			reservedNames: seenLabels.subtracting(collidingLabels).union(parameterLabels),
		)
		return seenLabels.subtracting(collidingLabels).union(names)
	}

	/// What the names of `mock()`'s parameters are chosen from in the tree of a mock root: its bindings, the names its
	/// builder functions declare, and the `@Instantiated` dependencies the mock cannot build.
	private struct TreeNames {
		/// The `@Instantiated` dependencies of the mocked type and of the types of its tree that the mock cannot build, each
		/// under its label, as `mockRootParameters(instantiable:mockDefaults:)` collects them.
		let uncoveredParameters: [MockRootParameters.UncoveredParameter]
		/// The indices of the uncovered parameters whose label a builder function around a type passed them declares.
		let uncoveredIndicesHiddenWhereReferenced: Set<Int>
		/// The properties of the property nodes at the root's level, in order.
		let rootPropertyNodes: [Property]
		/// The labels of the dependencies of every node of the tree, which its builder function declares
		/// (`namesDeclaredInBuilderFunctions(of:)`).
		let namesDeclaredInBuilderFunctions: Set<String>
	}

	/// The names in the tree of the mocked type, `instantiable`, that the names of `mock()`'s parameters are chosen from. The
	/// uncovered dependencies are the mocked type's in its declaration order, then each node's, in the order a walk of the
	/// tree in generation order first meets them; a dependency is uncovered where no child of the type that instantiates it
	/// builds its label (for the mocked type, its property or a `LazilyInstantiated` of it). The tree is walked with a stack,
	/// since it can be as deep as the module has types.
	private func treeNames(of instantiable: Instantiable) -> TreeNames {
		/// A node of the tree that builds a type, and where it is among the nodes the type above it builds: its declaration
		/// index there, or none for a node the mock promotes, then its index in generation order.
		struct Visit {
			let generator: ScopeGenerator
			let declarationPath: [Position]
			/// The labels the builder functions around the node declare, which hide a parameter of the same label there.
			let namesDeclaredByEnclosingBuilderFunctions: Set<String>
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
		/// The generators of the children that build a type, each at its position among them.
		func propertyChildren(of generator: ScopeGenerator, declaredBy dependencies: [Dependency], at path: [Position], enclosedBy names: Set<String>, insideSendableFunction: Bool) -> [Visit] {
			var declarationIndexByLabel = [String: Int]()
			for (index, dependency) in dependencies.enumerated() where declarationIndexByLabel[dependency.property.label] == nil {
				declarationIndexByLabel[dependency.property.label] = index
			}
			return generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []).map(\.generator).enumerated().compactMap { generationIndex, child in
				guard case let .property(_, property, _, _, _, _) = child.scopeData else { return nil }
				let position = Position(declarationIndex: declarationIndexByLabel[property.label] ?? Int.max, generationIndex: generationIndex)
				return Visit(
					generator: child,
					declarationPath: path + [position],
					namesDeclaredByEnclosingBuilderFunctions: names,
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
		var creatingTypesByProperty = [Property: [(path: [Position], type: TypeDescription)]]()
		var hiddenProperties = Set<Property>()
		var propertiesInstantiatedInSendableFunction = Set<Property>()
		var namesDeclaredInBuilderFunctions = Set<String>()
		func add(_ dependency: Dependency, createdBy type: TypeDescription, at path: [Position], isHiddenWhereReferenced: Bool, isInstantiatedInSendableFunction: Bool) {
			if dependencyByProperty[dependency.property] == nil {
				properties.append(dependency.property)
				dependencyByProperty[dependency.property] = dependency
			}
			creatingTypesByProperty[dependency.property, default: []].append((path: path, type: type))
			if isHiddenWhereReferenced {
				hiddenProperties.insert(dependency.property)
			}
			if isInstantiatedInSendableFunction {
				propertiesInstantiatedInSendableFunction.insert(dependency.property)
			}
		}

		/// The properties the sites of holes among a generator's children bind, which no parameter covers
		/// (`ScopeGenerator.uncoveredInstantiatedDependencies(ofMockedType:treePropertyNodes:holeSiteProperties:)`).
		func holeSiteProperties(of generator: ScopeGenerator) -> [Property] {
			generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []).compactMap { child in
				guard case let .hole(property, _, .some) = child.generator.scopeData else { return nil }
				return property
			}
		}
		let rootChildren = propertyChildren(of: self, declaredBy: instantiable.dependencies, at: [], enclosedBy: [], insideSendableFunction: false)
		var builtProperties = Set<Property>(holeSiteProperties(of: self))
		for child in rootChildren {
			guard let property = child.generator.property else { continue }
			builtProperties.insert(property)
			if let instanceProperty = property.asLazilyInstantiatedInstanceProperty {
				builtProperties.insert(instanceProperty)
			}
		}
		// The mocked type is built in the body of `mock()`, outside every builder function.
		for dependency in instantiable.dependencies where isInstantiated(dependency) && !builtProperties.contains(dependency.property) {
			add(dependency, createdBy: instantiable.concreteInstantiable, at: [], isHiddenWhereReferenced: false, isInstantiatedInSendableFunction: false)
		}
		var visits = Array(rootChildren.reversed())
		while let visit = visits.popLast() {
			guard case let .property(nodeInstantiable, _, _, _, isPropertyCycle, _) = visit.generator.scopeData else { continue }
			for dependency in nodeInstantiable.dependencies {
				namesDeclaredInBuilderFunctions.insert(dependency.property.label)
			}
			// A node that closes a cycle builds nothing beneath it, and its dependencies surface as no parameter.
			guard !isPropertyCycle else { continue }
			let children = propertyChildren(of: visit.generator, declaredBy: nodeInstantiable.dependencies, at: visit.declarationPath, enclosedBy: [], insideSendableFunction: visit.isInsideSendableFunction)
			let childLabels = Set(children.compactMap(\.generator.property?.label)).union(holeSiteProperties(of: visit.generator).map(\.label))
			var uncoveredLabels = Set<String>()
			for dependency in nodeInstantiable.dependencies where isInstantiated(dependency) && !childLabels.contains(dependency.property.label) {
				uncoveredLabels.insert(dependency.property.label)
				// A builder function around the type that declares the label would hide the parameter there.
				add(
					dependency,
					createdBy: nodeInstantiable.concreteInstantiable,
					at: visit.declarationPath,
					isHiddenWhereReferenced: visit.namesDeclaredByEnclosingBuilderFunctions.contains(dependency.property.label),
					isInstantiatedInSendableFunction: visit.isInsideSendableFunction,
				)
			}
			var namesDeclared = visit.namesDeclaredByEnclosingBuilderFunctions
			for dependency in nodeInstantiable.dependencies where !uncoveredLabels.contains(dependency.property.label) {
				namesDeclared.insert(dependency.property.label)
			}
			visits.append(contentsOf: children.reversed().map {
				Visit(
					generator: $0.generator,
					declarationPath: $0.declarationPath,
					namesDeclaredByEnclosingBuilderFunctions: namesDeclared,
					isInsideSendableFunction: $0.isInsideSendableFunction,
				)
			})
		}
		var parameters = [MockRootParameters.UncoveredParameter]()
		for property in properties {
			guard let dependency = dependencyByProperty[property] else { continue }
			let typeSource = property.propertyType.isConstant
				? property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asFunctionParameter.asSource
				: property.typeDescription.asFunctionParameter.asSource
			var creatingTypes = [TypeDescription]()
			for (_, type) in (creatingTypesByProperty[property] ?? []).sorted(by: { $0.path.lexicographicallyPrecedes($1.path) }) where !creatingTypes.contains(type) {
				creatingTypes.append(type)
			}
			parameters.append(MockRootParameters.UncoveredParameter(
				property: property,
				label: property.label,
				typeSource: typesDeclaredEscaping.contains(property.typeDescription)
					? property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource
					: typeSource,
				instantiatedType: dependency.asInstantiatedType,
				isSendableAutoclosure: propertiesInstantiatedInSendableFunction.contains(property),
				creatingTypes: creatingTypes,
			))
		}
		return TreeNames(
			uncoveredParameters: parameters,
			uncoveredIndicesHiddenWhereReferenced: Set(properties.indices.filter { hiddenProperties.contains(properties[$0]) }),
			rootPropertyNodes: rootChildren.compactMap { child in
				guard case let .property(_, property, _, _, _, _) = child.generator.scopeData else { return nil }
				return property
			},
			namesDeclaredInBuilderFunctions: namesDeclaredInBuilderFunctions,
		)
	}
}

extension MockLoweringShadow {
	/// How the uncovered parameters `query needs` reports of the mock root `mockRoot`, whose mocked type is `instantiable`,
	/// read from the lowering's signature, compare with `emitted`, the emitter's (`MockRootParameters.flatUncoveredParameters`).
	static func queryComparison(
		of mockRoot: ScopeGenerator,
		instantiable: Instantiable,
		flatParameterMockDefaults: [TypeDescription: ScopeGenerator.FlatParameterMockDefault],
		emitted: [ScopeGenerator.MockRootParameters.UncoveredParameter],
	) async -> Comparison {
		let outcome = await mockRoot.queryNeedsOutcome(of: instantiable, flatParameterMockDefaults: flatParameterMockDefaults, comparingWith: text(of: emitted))
		return Comparison(mockedType: instantiable.concreteInstantiable.asSource, outcome: outcome, subject: .queryNeeds)
	}

	/// Each parameter on a line of its own, as `query needs` reads it: its name, type, instantiated type and creating types.
	fileprivate static func text(of parameters: [ScopeGenerator.MockRootParameters.UncoveredParameter]) -> String {
		parameters.map { parameter in
			"\(parameter.label): \(parameter.typeSource) (\(parameter.instantiatedType.asSource)) created by \(parameter.creatingTypes.map(\.asSource).joined(separator: ", "))"
		}.joined(separator: "\n")
	}
}

extension ScopeGenerator {
	/// How the uncovered parameters of this mock root's lowered signature compare with `emittedText`.
	fileprivate func queryNeedsOutcome(
		of instantiable: Instantiable,
		flatParameterMockDefaults: [TypeDescription: FlatParameterMockDefault],
		comparingWith emittedText: String,
	) -> MockLoweringShadow.Outcome {
		switch lowerRootSignature(of: instantiable, flatParameterMockDefaults: flatParameterMockDefaults) {
		case let .lowered(signature):
			MockLoweringShadow.outcome(comparing: .lowered(MockLoweringShadow.text(of: signature.uncoveredRootParameters)), with: emittedText)
		case let .unsupported(rule):
			.unsupported(rule)
		}
	}
}
