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

extension ScopeGenerator {
	/// The calls of other modules' public mocks that fill builders in the tree of `orderedChildren`, the root's children in
	/// generation order, each with the `propertiesGeneratedLater` its fills are generated with, in the order the walk reaches
	/// them (depth first, each level in generation order), with the places inside their fills and inside the fills of the
	/// calls those fills make (`FillPlace`, numbered across the calls), the labels those fills declare, and every call that
	/// fills a builder, at the root's level or inside a fill (`FilledCall`). A call is made inside a `@Sendable` function
	/// where an enclosing builder function, or its own, is one. Walked with a stack, since a tree can be as deep as the module
	/// has types.
	func callsFillingBuilders(of orderedChildren: [OrderedChild]) -> (calls: [MockLowering.FilledCallBuilders.Call], fillPlaces: [FillPlace], namesFillsDeclare: Set<String>, filledCalls: [FilledCall]) {
		var calls = [MockLowering.FilledCallBuilders.Call]()
		var fillPlaces = [FillPlace]()
		var namesFillsDeclare = Set<String>()
		var filledCalls = [FilledCall]()
		var childrenToVisit = orderedChildren.reversed().map { (child: $0, isInsideSendableFunction: false) }
		while let (child, isInsideSendableFunction) = childrenToVisit.popLast() {
			let generator = child.generator
			if generator.publicMockCall != nil {
				guard generator.fillsABuilder else { continue }
				let requiresSendable = isInsideSendableFunction || generator.buildsInSendableFunction
				// A place inside a fill takes a required builder, which an internal mock takes (a public mock's are places of its
				// own tree). A call inside a fill is generated with the fill, reading the builders `mock()` takes for the places
				// it fills as the call does.
				let callPlaces = generator.fillPlaces(insideSendableFunction: requiresSendable)
				fillPlaces += callPlaces.places.map { place in
					FillPlace(generator: place.generator, dependency: place.dependency, isInsideSendableFunction: place.isInsideSendableFunction, order: fillPlaces.count + place.order)
				}
				namesFillsDeclare.formUnion(callPlaces.declaredLabels)
				filledCalls.append(FilledCall(generator: generator, isInsideSendableFunction: requiresSendable, enclosingCalls: []))
				filledCalls.append(contentsOf: callPlaces.calls)
				calls.append(.init(generator: generator, propertiesGeneratedLater: child.propertiesGeneratedLater))
				continue
			}
			guard case .property(_, _, _, _, false, _) = generator.scopeData else { continue }
			let grandchildren = generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: generator.mockLoweringBodyPropertiesGeneratedLater(child.propertiesGeneratedLater))
			let nestedIsInsideSendableFunction = isInsideSendableFunction || generator.buildsInSendableFunction
			childrenToVisit.append(contentsOf: grandchildren.reversed().map { ($0, nestedIsInsideSendableFunction) })
		}
		return (calls, fillPlaces, namesFillsDeclare, filledCalls)
	}

	/// The builders `mock()` takes for the places its calls of other modules' public mocks fill and for those inside their
	/// fills, read from the tree of `orderedChildren`, the root's children in generation order, and the calls, each taken by
	/// the walk as it reaches it.
	///
	/// An internal mock takes the builders its one classification names (`seamMockBuilders`, `MockRootParameters`): each
	/// call's builder of a family reads the builder of that family, and each place inside a fill binds it. The signature
	/// declares the builders of the mock's own places and of what its calls pass up (`RootSignature.passedUpBuilders`); the
	/// others are declared here. A public mock takes optional builders for the families its calls fill, named as its plan
	/// names them (`optionalBuilderNames`, by family), which a first call, without names, finds for the plan.
	func filledCallBuilders(of orderedChildren: [OrderedChild], context: MockContext, seamMockBuilders: [MockRootParameters.SeamMockBuilder] = [], optionalBuilderNames: [MockRootParameters.SeamMockBuilder.Family: String]? = nil) throws -> MockLowering.FilledCallBuilders {
		// Only a call of another module's public mock fills a builder, and a module that calls none, as most do, has no call to
		// find in the tree.
		guard !context.foreignPublicMocks.isEmpty else { return .none }
		let found = callsFillingBuilders(of: orderedChildren)
		// Without calls, a place of another module's public mock the tree builds inline still reads the builder `mock()`
		// takes for its family, a seam's own place's or one a call passes up.
		guard !found.calls.isEmpty || !seamMockBuilders.isEmpty else { return MockLowering.FilledCallBuilders(calls: [], parameters: [], fillPlaceBindings: FillPlaceBindings(bindingsByGenerator: [:])) }
		var parameters = [(label: String, declaration: String)]()
		var builderBindingLines = [(label: String, line: String)]()
		var holeBuildersByCall = [ObjectIdentifier: [String: FillPlaceBindings.HoleBuilder]]()
		var buildersByFamily = [MockRootParameters.SeamMockBuilder.Family: FillPlaceBindings.HoleBuilder]()
		var fillPlaceBindingsInOrder = [(order: Int, generator: ObjectIdentifier, binding: SendableAutoclosureParameter)]()
		var families = [FilledFamily]()
		for builder in seamMockBuilders {
			let holeBuilder = FillPlaceBindings.HoleBuilder(name: builder.internalName, isOptional: builder.isOptional)
			buildersByFamily[builder.family] = holeBuilder
			for place in builder.fillPlaces {
				fillPlaceBindingsInOrder.append((place.order, place.generator, SendableAutoclosureParameter(name: place.dependency.property.label, localName: builder.internalName, valueType: place.dependency.property.typeDescription)))
			}
			// Each call's builder of the family reads the builder `mock()` takes for it.
			for callBuilder in builder.filledCallBuilders {
				holeBuildersByCall[callBuilder.call, default: [:]][callBuilder.label] = holeBuilder
			}
			// The signature declares and binds a builder of the mock's own places or of what its calls pass up.
			guard builder.places.isEmpty, builder.passedUpProperties.isEmpty else { continue }
			if builder.isOptional {
				parameters.append((builder.label, "\(builder.label): \(TypeDescription.optional(builder.parameterType.strippingEscaping).asSource) = nil"))
			} else {
				parameters.append((builder.label, "\(builder.label): \(builder.parameterType.asSource)"))
			}
			if builder.internalName != builder.label {
				builderBindingLines.append((builder.label, "let \(builder.internalName) = \(builder.label)"))
			}
		}
		if seamMockBuilders.isEmpty {
			// A public mock's places inside fills are places of its own tree, so every family its calls fill is a builder it
			// takes optional.
			let fillPlaceFamilies = Set(found.fillPlaces.map(MockRootParameters.SeamMockBuilder.Family.init(of:)))
			families = Self.filledFamilies(of: found.filledCalls).filter { !fillPlaceFamilies.contains($0.family) }
			for filled in families {
				guard let name = optionalBuilderNames?[filled.family] else { continue }
				let parameterType = MockRootParameters.SeamMockBuilder.parameterType(ofPlaceProperties: filled.placeProperties, in: filled.family)
				parameters.append((name, "\(name): \(TypeDescription.optional(parameterType.strippingEscaping).asSource) = nil"))
				let holeBuilder = FillPlaceBindings.HoleBuilder(name: name, isOptional: true)
				buildersByFamily[filled.family] = holeBuilder
				for callBuilder in filled.callBuilders {
					holeBuildersByCall[callBuilder.call, default: [:]][callBuilder.label] = holeBuilder
				}
			}
		}
		var fillPlaceBindingsByGenerator = [ObjectIdentifier: [SendableAutoclosureParameter]]()
		for (_, generator, binding) in fillPlaceBindingsInOrder.sorted(by: { $0.order < $1.order }) {
			fillPlaceBindingsByGenerator[generator, default: []].append(binding)
		}
		parameters.sort { $0.label < $1.label }
		// A place of another module's public mock the tree builds inline reads the builder `mock()` takes for its hole type and
		// family: inside a fill, where the fill's code reads it, and outside every fill, where the walk's node reads it.
		let inlinePlaceBuildersOutsideFills = try holeBuildersByInlinePlaceOutsideFills(of: orderedChildren, buildersByFamily: buildersByFamily, foreignPublicMocks: context.foreignPublicMocks)
		let holeBuildersByInlinePlaceInFills = try Self.holeBuildersByInlinePlaceInFills(of: found.filledCalls, buildersByFamily: buildersByFamily, foreignPublicMocks: context.foreignPublicMocks)
		var filledCallBuilders = MockLowering.FilledCallBuilders(
			calls: found.calls,
			parameters: parameters,
			fillPlaceBindings: FillPlaceBindings(bindingsByGenerator: fillPlaceBindingsByGenerator, holeBuildersByCall: holeBuildersByCall, holeBuildersByInlinePlace: holeBuildersByInlinePlaceInFills),
		)
		filledCallBuilders.families = families
		filledCallBuilders.holeBuildersByInlinePlace = inlinePlaceBuildersOutsideFills
		filledCallBuilders.namesFillsDeclare = found.namesFillsDeclare
		filledCallBuilders.builderBindingLines = builderBindingLines
		return filledCallBuilders
	}

	/// Whether the leaf of `generator`, a call of another module's public mock, receives `property`: an internal caller's leaf
	/// receives each builder the call passes up, while a `.public` caller's receives none and passes its own struct's member.
	private func callsLeafReceivesBuilder(of generator: ScopeGenerator, _ property: Property) -> Bool {
		guard case let .property(instantiable, _, _, _, _, _) = generator.scopeData else { return false }
		return instantiable.dependencies.contains { $0.property == property }
	}

	/// The family of each builder a call of another module's public mock in the tree of `generators` passes up, by the
	/// property the call's leaf receives it as, with whether a `@Sendable` builder function captures it, from
	/// `PublicMockCall.passedUpBuilders`. Walked with a stack,
	/// since a tree can be as deep as the module has types. The lowering's signature names a builder per family
	/// (`seamMockBuilders`).
	func passedUpBuilderFamilies(of generators: [ScopeGenerator]) -> [Property: MockLowering.PassedUpBuilderFamily] {
		var familyByProperty = [Property: MockLowering.PassedUpBuilderFamily]()
		// Each generator with whether a `@Sendable` builder function encloses it.
		var generatorsToVisit = generators.map { ($0, false) }
		while let (generator, isInsideSendableFunction) = generatorsToVisit.popLast() {
			let capturesSendably = isInsideSendableFunction || generator.buildsInSendableFunction
			if let publicMockCall = generator.publicMockCall {
				let passedUpLabels = Set(publicMockCall.passedUpBuilders.map(\.label))
				for parameter in publicMockCall.passedParameters {
					// A `.public` caller's leaf receives no builder: the call passes its own struct's member.
					guard let builder = parameter.builder, passedUpLabels.contains(builder.label), callsLeafReceivesBuilder(of: generator, parameter.dependency.property) else { continue }
					// A builder of the `@Sendable` family, or one a `@Sendable` builder function captures, is of the `@Sendable`
					// family.
					let property = parameter.dependency.property
					let family = MockRootParameters.SeamMockBuilder.Family(holeType: builder.enumKey.holeType, isSendable: builder.enumKey.isSendable || capturesSendably)
					let isCaptured = capturesSendably || familyByProperty[property]?.isCapturedBySendableFunction == true
					let isSendable = family.isSendable || familyByProperty[property]?.family.isSendable == true
					let placeProperties = (familyByProperty[property]?.placeProperties ?? []) + MockRootParameters.SeamMockBuilder.PassedUpBuilder(family: family, calledBuilders: [(builder, publicMockCall.calledBuilders)]).placeProperties
					familyByProperty[property] = MockLowering.PassedUpBuilderFamily(
						family: MockRootParameters.SeamMockBuilder.Family(holeType: family.holeType, isSendable: isSendable),
						isCapturedBySendableFunction: isCaptured,
						placeProperties: placeProperties,
					)
				}
			}
			generatorsToVisit.append(contentsOf: generator.orderedChildGenerators.map { ($0, capturesSendably) })
		}
		return familyByProperty
	}

	/// The builder `mock()` takes for each place of another module's public mock that the tree of `orderedChildren` builds
	/// inline outside the fills of its calls, keyed by the place's path of child indices (`OrderedChild.index`, one per level
	/// beneath the root), as `ScopeGenerator.holeBuildersByInlinePlace(in:buildersByFamily:foreignPublicMocks:)` finds them
	/// by node: a generator built at two places is two places. Walked with a stack, since a tree can be as deep as the module
	/// has types.
	private func holeBuildersByInlinePlaceOutsideFills(
		of orderedChildren: [OrderedChild],
		buildersByFamily: [MockRootParameters.SeamMockBuilder.Family: FillPlaceBindings.HoleBuilder],
		foreignPublicMocks: [TypeDescription: SeamResolution.ForeignPublicMock],
	) throws -> [[Int]: FillPlaceBindings.HoleBuilder] {
		guard !buildersByFamily.isEmpty, !foreignPublicMocks.isEmpty else { return [:] }
		var holeBuilderByPath = [[Int]: FillPlaceBindings.HoleBuilder]()
		// Each scope with its path, whether a `@Sendable` builder function encloses it, the public mock built inline nearest
		// above it, and the type its declaration instantiates, which a `fulfilledByType:` names.
		var generatorsToVisit = orderedChildren.map { (generator: $0.generator, path: [$0.index], isInsideSendableFunction: false, publicMockBuiltInline: SeamResolution.ForeignPublicMock?.none, instantiatedType: TypeDescription?.none) }
		while let (generator, path, isInsideSendableFunction, publicMockBuiltInline, declaredInstantiatedType) = generatorsToVisit.popLast() {
			// A scope that closes a cycle builds nothing, and a call's places are the call's.
			guard case let .property(instantiable, property, _, _, false, _) = generator.scopeData, generator.publicMockCall == nil else { continue }
			let instantiatedType = declaredInstantiatedType ?? property.typeDescription.asInstantiatedType
			let requiresSendable = isInsideSendableFunction || generator.buildsInSendableFunction
			if let publicMockBuiltInline, try publicMockBuiltInline.visibleDeclarations().instantiables[instantiatedType] == nil {
				let family = MockRootParameters.SeamMockBuilder.Family(
					holeType: SeamSignature.HoleType(instantiatedType: instantiatedType.spelledCanonically, builtType: property.typeDescription.builtTypeOfWrapper.spelledCanonically),
					isSendable: requiresSendable || property.propertyType.isSendable,
				)
				holeBuilderByPath[path] = buildersByFamily[family]
			}
			let enclosingPublicMock = foreignPublicMocks[instantiable.concreteInstantiable] ?? publicMockBuiltInline
			let instantiatedTypes = Dictionary(instantiable.dependencies.map { ($0.property, $0.asInstantiatedType) }, uniquingKeysWith: { first, _ in first })
			generatorsToVisit += generator.orderedChildGeneratorsWithIndices.map { index, child in
				(child, path + [index], requiresSendable, enclosingPublicMock, child.property.flatMap { instantiatedTypes[$0] })
			}
		}
		return holeBuilderByPath
	}
}

/// Stage D1's lowering of lane E's family: the calls of other modules' public mocks, their fills, override closures and
/// optional builders.
extension MockLowering.Walk {
	/// The names of the shared fill bodies among `codes`, the fills of a call, that `mock()` declares once before its tree
	/// (`fillBodies`), each recorded the first time the walk reaches it. A mock declares a body there only where its text is
	/// the whole function, holding no root function and calling none, and where it is `@Sendable` or the call is inside no
	/// `@Sendable` function, which calls no function that is not; a body of a name the walk reached with another key, or
	/// inside a `@Sendable` function of the fills' own trees where it is not `@Sendable` itself, stays where its fill wrote it.
	mutating func declareFillBodies(of codes: [GeneratedCode], isInsideSendableFunction: Bool) -> Set<String> {
		var names = Set<String>()
		for record in RootFunctionHoisting.recordsDeclarableWhereReached(in: codes) where Self.isDeclaredOnce(record, insideSendableFunction: isInsideSendableFunction) {
			if let key = fillBodyKeysByName[record.name] {
				if key == record.key {
					names.insert(record.name)
				}
			} else {
				fillBodyKeysByName[record.name] = record.key
				fillBodies.append(record)
				names.insert(record.name)
			}
		}
		return names
	}

	/// Whether `record` is a shared fill body `mock()` may declare once (`declareFillBodies(of:isInsideSendableFunction:)`):
	/// only a shared body's record (`ScopeGenerator.sharedFillBodyFunction`) is declared so, never a fill or a dispatcher.
	/// Whether the body is `@Sendable` is its fill's own flag (`ScopeGenerator.buildsInSendableFunction(ofFill:)`), never the
	/// called seam's case facts (`SeamSignature.Places.Case.isBuiltInSendableFunction`, `isPassedOnSendable`): the flag also
	/// holds where a `@Sendable` function of the caller's own tree refers to the fill, which no case of the called seam's
	/// place graph sees, and a body declared from the case facts alone would not be `@Sendable` there.
	private static func isDeclaredOnce(_ record: RootFunctionRecord, insideSendableFunction: Bool) -> Bool {
		guard case let .fillBody(function, _) = record.declaration, record.calls.isEmpty, record.isSendable || !insideSendableFunction else { return false }
		return !function.pathCode.holdsRootFunction
	}

	/// The node of `generator`, `publicMockCall` of another module's public mock building `built`, whose statements are
	/// appended to `lines`. The call names the mock's guard where it is made and passes the mock its own `SafeDIOverrides`,
	/// which the calling mock's overrides hold under the node's label.
	mutating func publicMockCallNode(
		of generator: ScopeGenerator,
		publicMockCall: PublicMockCall,
		building built: (instantiable: Instantiable, property: Property, forwardedProperties: Set<Property>, erasedToConcreteExistential: Bool),
		inScope _: Set<Property>,
		path: String,
		indent: String,
		lines: inout [String],
	) async throws -> MockLowering.TreeNode {
		let (instantiable, property, forwardedProperties, erasedToConcreteExistential) = built
		// The leaf takes the called tier's parameters as its mock's.
		let initializer = (instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType) ? instantiable.mockInitializer : instantiable.initializer) ?? Initializer(arguments: [])
		// A call of a mock that takes no overrides is configured by an override closure, handed what the called `mock()`
		// takes, where the call can hand each builder as a function a person writes (`ScopeGenerator.publicMockOverrideBuilders`).
		let overrideBuilders = publicMockCall.takesOverrides ? nil : generator.publicMockOverrideBuilders
		// The member that configures the call is a `@Sendable` closure where the call is built inside a `@Sendable` function,
		// or where the configuration holding it is `@Sendable`-typed (`publicMockOverridesMember(sendable:)`).
		let overridesAreSendable = isInsideSendableFunction || generator.buildsInSendableFunction || parentConcreteType.map(sendableConfigurationTypeNames.contains) ?? false
		let node = MockLowering.PublicMockCallNode(
			property: property,
			calledType: instantiable.concreteInstantiable,
			call: publicMockCall,
			overridesAreSendable: overridesAreSendable,
			overrideClosureType: overrideBuilders.map { _ in
				let parameterTypes = initializer.arguments.map { argument in
					(argument.typeDescription.strippingEscaping.autoclosureValueType ?? argument.typeDescription)
						.asFunctionParameter(amongTypesDeclaredEscaping: publicMockCall.typesDeclaredEscaping)
						.asSource
				}
				return "(\(parameterTypes.joined(separator: ", "))) -> \(property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource)"
			},
		)
		// A call whose own builder function is `@Sendable` outside every other starts the extraction of its override reads
		// into locals before that function; inside an enclosing `@Sendable` function the override is read through that
		// function's extractor.
		let startsExtraction = sendableOverrideExtractor == nil && generator.buildsInSendableFunction
		let nodePath = "\(path).\(property.label)"
		// A call that fills builders is made in a builder function of its own, which declares the fills and names the guard
		// first; it passes each builder the struct of the builder `mock()` takes optional for the builder's places, or of
		// its fills where that builder is `nil`. Any other call names the guard where it is made.
		let filledCall: MockLowering.FilledCallBuilders.Call? = if generator.fillsABuilder, !filledCallBuilders.calls.isEmpty {
			filledCallBuilders.calls.removeFirst()
		} else {
			nil
		}
		let innerIndent = filledCall == nil ? indent : "\(indent)\(ScopeGenerator.standardIndent)"
		let holeBuilders = filledCallBuilders.fillPlaceBindings.holeBuildersByCall[ObjectIdentifier(generator)] ?? [:]
		let structValuesByLabel = generator.publicMockBuilderStructValuesByLabel(propertiesGeneratedLater: filledCall?.propertiesGeneratedLater ?? [])
		let holeArgumentValuesByLabel = generator.holeArgumentValuesByLabel
		let lazilyInstantiatedInstances = generator.mockLoweringLazilyInstantiatedInstanceProperties
		let lazilyInstantiatedNamesOfLabels = lazilyInstantiatedNames
		var arguments = [String]()
		// What the override closure is handed for each argument: a builder as `publicMockOverrideBuilders` says, which reads
		// the values the call passes, and any other argument as the call passes it.
		var overrideArguments = [String]()
		var argumentByLabel = [String: String]()
		var passedUpBuilderBindings = [String]()
		func labeled(_ value: String, as argument: Initializer.Argument) -> String {
			argument.label == "_" ? value : "\(argument.label.spelledAsArgumentLabel): \(value)"
		}
		for argument in initializer.arguments {
			if let dependency = instantiable.dependencies.first(where: { $0.property.label == argument.innerLabel }),
			   let builderName = filledCallBuilders.passedUpBuilderNames[dependency.property]
			{
				// A builder the call passes up is the builder `mock()` takes, which the call's builder function binds under the
				// label the leaf receives it as, and which an override closure is handed as it is (`.callersBuilder`).
				// `mock()` takes it as the flat received parameter of its property (`lowerRootSignature(of:context:)`).
				if overrideBuilders != nil {
					overrideArguments.append(dependency.property.label)
				}
				// The leaf reads the builder under the name `mock()` binds it, bound again under its label where they differ.
				if builderName != dependency.property.label {
					passedUpBuilderBindings.append("let \(dependency.property.label): \(dependency.property.typeDescription.strippingEscaping.asSource) = \(builderName)")
				}
				arguments.append(labeled(".init(\(ReservedName.noScopeArgumentLabel): \(dependency.property.label))", as: argument))
			} else if let builderStruct = structValuesByLabel[argument.innerLabel] {
				// safedi-source-rule: allow stringScan — not cold, and bounded: it runs once for each builder struct that a call of another module’s public mock passes, as often as the mock bodies write such a call, and each run reads only that one struct’s text (its fills), never the generated file. Removed by the roadmap’s row 5 (mock bodies: one writer).
				let fillsStruct = builderStruct.replacingOccurrences(of: "\n\(ScopeGenerator.standardIndent)", with: "\n\(innerIndent)")
				arguments.append(labeled(holeBuilders[argument.innerLabel]?.structValue(fillsStruct: fillsStruct) ?? fillsStruct, as: argument))
				if overrideBuilders != nil {
					overrideArguments.append(argument.innerLabel)
				}
			} else if overrideBuilders == nil, let holeValue = holeArgumentValuesByLabel[argument.innerLabel] {
				// A builder a `.public` caller's call passes up, as its own struct's member.
				arguments.append(labeled(holeValue, as: argument))
			} else if let dependency = instantiable.dependencies.first(where: { $0.property.label == argument.innerLabel }) {
				// A value the call passes is the root level's binding of its label, which an optional parameter takes as it is, or
				// the instance of the lazy wrapper the tree holds of it, read at the call (`dependencyArgument`).
				let value: String
				if generator.unavailableOptionalProperties.contains(dependency.property) || unavailableProperties.contains(dependency.property) {
					// A value the call's leaf receives only if available that nothing provides where the call is made, or that a
					// `@Sendable` function would capture, is passed `nil` (`constructionArgumentList(of:unavailableProperties:)`).
					// So is one a sibling built after the call provides.
					value = "nil"
				} else if dependency.source == .forwarded {
					// A value the called type forwards is the parameter of the builder function the instantiator holds.
					value = dependency.property.label
				} else if dependency.source.isReceived,
				          lazilyInstantiatedInstances.contains(dependency.property.asUnwrappedProperty),
				          let wrapperName = lazilyInstantiatedNamesOfLabels[dependency.property.label].flatMap({ namesByType in
				          	[Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType].compactMap { namesByType[.simple(name: $0, generics: [dependency.property.typeDescription.unwrapped])] }.first
				          })
				{
					// The instance of the wrapper `mock()` binds apart from the instance it takes
					// (`dependencyArgument`).
					value = "\(wrapperName).\(Dependency.lazilyInstantiatedInstancePropertyName)"
				} else if buildsPublicMock,
				          dependency.source.isReceived,
				          lazilyInstantiatedInstances.contains(dependency.property.asUnwrappedProperty),
				          let wrapperParameterName = publicMockWrapperParameterNames[dependency.property.label].flatMap({ namesByType in
				          	[Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType].lazy.compactMap { namesByType[.simple(name: $0, generics: [dependency.property.typeDescription.unwrapped])] }.first
				          })
				{
					// The instance of the wrapper a public mock takes as a parameter, which `mock()` names apart where its root
					// binds another value of the label (`instancesReadThroughPublicMockWrapperParameters`).
					value = "\(wrapperParameterName).\(Dependency.lazilyInstantiatedInstancePropertyName)"
				} else if dependency.source.isReceived,
				          lazilyInstantiatedInstances.contains(dependency.property.asUnwrappedProperty),
				          let (wrapperType, renamedName) = renames[dependency.property.label].flatMap({ namesByType in
				          	[Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType].lazy.compactMap { wrapperName -> (TypeDescription, String)? in
				          		let wrapperType = TypeDescription.simple(name: wrapperName, generics: [dependency.property.typeDescription.unwrapped])
				          		return namesByType[wrapperType].map { (wrapperType, $0) }
				          	}.first
				          })
				{
					// The instance of a wrapper the mock names apart, bound again under its label in the call's builder function
					// (`emitReceiverBindings`), as a receive the mock names apart is below.
					if filledCall == nil {
						passedUpBuilderBindings.append("let \(dependency.property.label): \(wrapperType.asSource) = \(renamedName)")
					}
					value = "\(dependency.property.label).\(Dependency.lazilyInstantiatedInstancePropertyName)"
				} else if dependency.source.isReceived, let wrapperName = lazilyInstantiatedNamesOfLabels[dependency.property.label]?[dependency.property.typeDescription] {
					// The wrapper `mock()` binds around the instance it takes, passed by name
					// (`dependencyArgument`).
					value = wrapperName
				} else if dependency.source.isReceived, let renamedName = renames[dependency.property.label].flatMap({ $0[dependency.property.typeDescription] ?? $0[dependency.property.typeDescription.unwrapped] }) {
					// A receive the mock names apart, found by its type and then its unwrapped type, since the optional parameter
					// of a public mock's tier is fulfilled by a non-optional value named apart, is bound again under its label in
					// the call's builder function (`emitReceiverBindings`): a call that fills a builder binds it with the leaf's
					// other receives, after its fills.
					if filledCall == nil {
						passedUpBuilderBindings.append("let \(dependency.property.label): \(dependency.property.typeDescription.asSource) = \(renamedName)")
					}
					value = dependency.property.label
				} else if dependency.source.isReceived, lazilyInstantiatedInstances.contains(dependency.property.asUnwrappedProperty) {
					value = "\(dependency.property.label).\(Dependency.lazilyInstantiatedInstancePropertyName)"
				} else {
					value = dependency.property.label
				}
				arguments.append(labeled(value, as: argument))
				overrideArguments.append(value)
				argumentByLabel[argument.innerLabel] = value
			}
		}
		// Inside a `@Sendable` function the member is read into a local before the outermost such function, only where the
		// call reads it.
		var extractionLines = [String]()
		// A call beneath an edge in `cycleEdges`, or beneath a node that is, reads no override: its parent's configuration
		// has no field for it, so the called mock builds with its own defaults.
		let readsOverride = overridePathReachable && !isPruned(instantiable.concreteInstantiable, beneath: parentConcreteType)
		let overrideRead: String
		if readsOverride, publicMockCall.takesOverrides || overrideBuilders != nil {
			if startsExtraction {
				// The call's own builder function reads its override into a local named after it (`startedSendableOverrideExtractor`).
				let enclosingExtractor = startExtraction(inFunctionNamed: ScopeGenerator.functionName(toBuildPropertyNamed: property.label))
				overrideRead = readingOverride(nodePath, localNameSuffix: ReservedName.configurationBuilderPropertyName)
				extractionLines = endExtraction(restoring: enclosingExtractor, indent: indent)
			} else {
				overrideRead = readingOverride(nodePath, localNameSuffix: "\(GeneratedCodeText.overrideRelativePath(of: nodePath))_\(ReservedName.configurationBuilderPropertyName)")
			}
		} else {
			overrideRead = nodePath
		}
		if readsOverride, publicMockCall.takesOverrides {
			arguments.append("\(ReservedName.mockOverridesParameterName): \(overridesAreSendable ? "\(overrideRead)?() ?? .init()" : overrideRead)")
		}
		let unerasedCall = "\(instantiable.concreteInstantiable.asSource).\(publicMockCall.functionName)(\(arguments.joined(separator: ", ")))"
		let defaultCall = erasedToConcreteExistential ? "\(property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource)(\(unerasedCall))" : unerasedCall
		let call: String
		if readsOverride, let overrideBuilders {
			// A builder's slot holds its label until here, so that each builder reads every value the call passes.
			let handed = zip(initializer.arguments, overrideArguments).map { argument, value in
				overrideBuilders[argument.innerLabel]?.expression(argumentByLabel: argumentByLabel, holeBuilder: holeBuilders[argument.innerLabel]) ?? value
			}
			let overrideName = ReservedName.configurationBuilderPropertyName
			call = "if let \(overrideName) = \(overrideRead) { \(overrideName)(\(handed.joined(separator: ", "))) } else { \(defaultCall) }"
		} else {
			call = defaultCall
		}
		let typeName = property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource
		let functionName = ScopeGenerator.functionName(toBuildPropertyNamed: property.label)
		let functionDecorator = ScopeGenerator.localFunctionPrefix(isSendable: generator.buildsInSendableFunction)
		// The values an instantiator's builder function takes from the instantiator, in label order, which the call passes on.
		let forwarded = forwardedProperties.sorted { $0.label < $1.label }
		let functionParameters = forwarded.map { "\($0.label): \($0.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: generator.typesDeclaredEscaping).asSource)" }.joined(separator: ", ")
		// A call a public mock promotes at its root's level reads its caller's value first, which only a call with no builder
		// bound again is lowered for.
		let isPromoted = parentConcreteType == nil && promotedProperties.contains(property)
		func instantiatorBindingLines() -> [String] {
			isPromoted
				? [MockLowering.promotedWrapperBindingLine(of: property.typeDescription, named: property.label, passing: property.label, handing: functionName, forwardedProperties: forwarded, indent: indent)]
				: MockLowering.wrapperBindingLines(of: property.typeDescription, named: property.label, handing: functionName, forwardedProperties: forwarded, indent: indent)
		}
		// A call held in an instantiator is made in the builder function the instantiator holds.
		let isInstantiator = !property.propertyType.isConstant
		guard let filledCall else {
			lines.append("\(indent)\(publicMockCall.guardLine(for: instantiable.concreteInstantiable))")
			lines.append(contentsOf: extractionLines)
			// A call on a loop of builders first rebinds the members its tree receives, and its level
			// binds its wrapper where it reads it outside the loop (`MockLowering+Loops.swift`).
			if let loopMembership {
				lines.append(contentsOf: loopMemberCallLines(of: generator, property: property, in: loopMembership, functionDeclaration: "\(indent)\(functionDecorator)func \(functionName)(\(functionParameters)) -> \(typeName) {", bodyLines: passedUpBuilderBindings, call: call, indent: indent))
				return .publicMockCall(node)
			}
			// A call that passes a builder up binds it in a builder function of its own.
			// An instantiator's builder function, which takes what the instantiator forwards, binds them inside it.
			guard passedUpBuilderBindings.isEmpty else {
				lines.append("\(indent)\(functionDecorator)func \(functionName)(\(isInstantiator ? functionParameters : "")) -> \(typeName) {")
				lines.append(contentsOf: passedUpBuilderBindings.map { "\(indent)\(ScopeGenerator.standardIndent)\($0)" })
				lines.append("\(indent)\(ScopeGenerator.standardIndent)return \(call)")
				lines.append("\(indent)}")
				if isInstantiator {
					lines.append(contentsOf: instantiatorBindingLines())
				} else {
					lines.append("\(indent)let \(property.label): \(typeName) = \(functionName)()")
				}
				return .publicMockCall(node)
			}
			if isInstantiator {
				lines.append("\(indent)\(functionDecorator)func \(functionName)(\(functionParameters)) -> \(typeName) {")
				lines.append("\(indent)\(ScopeGenerator.standardIndent)\(call)")
				lines.append("\(indent)}")
				lines.append(contentsOf: instantiatorBindingLines())
			} else {
				lines.append("\(indent)let \(property.label) = \(isPromoted ? ScopeGenerator.passing(property.label, orBuilding: call) : call)")
			}
			return .publicMockCall(node)
		}
		let fillCodes = try await generator.mockLoweringFillCode(propertiesGeneratedLater: filledCall.propertiesGeneratedLater, fillPlaceBindings: filledCallBuilders.fillPlaceBindings)
		// The fills' shared bodies `mock()` declares once, before its tree, which the fills call by name.
		let declaredFillBodyNames = declareFillBodies(of: fillCodes, isInsideSendableFunction: isInsideSendableFunction || generator.buildsInSendableFunction)
		let fillCode = fillCodes.map { code in
			guard !declaredFillBodyNames.isEmpty else { return code.spelled() }
			// Written inside a level, which leaves out the empty line an omitted body begins, then unindented again.
			let marker = "\t"
			return GeneratedCodeText.lines(of: GeneratedCode.indented(.omittingRootFunctions(code, named: declaredFillBodyNames), by: marker).spelled())
				.map { $0.dropFirst(marker.count) }
				.joined(separator: "\n")
		}.joined(separator: "\n")
		lines.append(contentsOf: extractionLines)
		let functionDeclaration = "\(indent)\(functionDecorator)func \(functionName)(\(functionParameters)) -> \(typeName) {"
		// The statements of the call's builder function before its call, unindented.
		var bodyLines = [String]()
		// The members a `@Sendable` family's places inside the fills read, which the call's builder function calls at its top.
		bodyLines.append(contentsOf: generator.memberCallsInsideBuilderFunction.map { $0.line(bindingNamesPassedByName: enclosingBindingNamesPassedByName, lazilyInstantiatedBindingNames: [:]) })
		if !fillCode.isEmpty {
			bodyLines.append(contentsOf: GeneratedCodeText.lines(of: fillCode))
		}
		bodyLines.append(publicMockCall.guardLine(for: instantiable.concreteInstantiable))
		// Each receive of the call's leaf the mock names apart is bound again under its label (`emitReceiverBindings`), a
		// receive of a lazy wrapper's instance binding the wrapper named apart.
		for dependency in instantiable.dependencies {
			// A builder the call passes up is bound again under the label the leaf receives it as, as a receive named apart is.
			if let builderName = filledCallBuilders.passedUpBuilderNames[dependency.property] {
				if builderName != dependency.property.label {
					bodyLines.append("let \(dependency.property.label): \(dependency.property.typeDescription.strippingEscaping.asSource) = \(builderName)")
				}
				continue
			}
			guard case .received = dependency.source, !generator.unavailableOptionalProperties.contains(dependency.property), let names = renames[dependency.property.label] else { continue }
			if generator.mockLoweringLazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty) {
				let instanceType = dependency.property.typeDescription.unwrapped
				guard let (wrapperType, name) = [Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType]
					.lazy
					.map({ TypeDescription.simple(name: $0, generics: [instanceType]) })
					.compactMap({ wrapperType in names[wrapperType].map { (wrapperType, $0) } })
					.first
				else { continue }
				bodyLines.append("let \(dependency.property.label): \(wrapperType.asSource) = \(name)")
			} else if let name = names[dependency.property.typeDescription] ?? names[dependency.property.asUnwrappedProperty.typeDescription] {
				bodyLines.append("let \(dependency.property.label): \(dependency.property.typeDescription.asSource) = \(name)")
			}
		}
		// A call on a loop of builders first rebinds the members its tree receives, and its level binds its wrapper where it
		// reads it outside the loop (`MockLowering+Loops.swift`).
		if let loopMembership {
			// A public mock's call that promotes a member of a loop of itself is passed its caller's wrapper, which its function
			// and its level read first, as the promoted wrapper is bound.
			if isPromoted {
				let promotedLine = { (indent: String) in
					MockLowering.promotedWrapperBindingLine(of: property.typeDescription, named: property.label, passing: property.label, handing: functionName, forwardedProperties: forwarded, indent: indent)
				}
				lines.append(functionDeclaration)
				lines.append(promotedLine(innerIndent))
				lines.append(contentsOf: bodyLines.map { $0.isEmpty ? "" : "\(innerIndent)\($0)" })
				lines.append("\(innerIndent)return \(call)")
				lines.append("\(indent)}")
				let bindingLines = loopMembership.declaresBinding ? [promotedLine(indent)] : []
				lines.append(contentsOf: bindingLines)
				lastLoopMemberLineCounts = MockLowering.LoopMemberLineCounts(prelude: extractionLines.count, binding: bindingLines.count)
				return .publicMockCall(node)
			} else {
				lines.append(contentsOf: loopMemberCallLines(of: generator, property: property, in: loopMembership, functionDeclaration: functionDeclaration, bodyLines: bodyLines, call: call, indent: indent))
				// The locals the call's `@Sendable` builder function reads from the overrides are the member's prelude.
				lastLoopMemberLineCounts = MockLowering.LoopMemberLineCounts(prelude: extractionLines.count, binding: lastLoopMemberLineCounts?.binding ?? 0)
				return .publicMockCall(node)
			}
		}
		lines.append(functionDeclaration)
		lines.append(contentsOf: bodyLines.map { $0.isEmpty ? "" : "\(innerIndent)\($0)" })
		lines.append("\(innerIndent)return \(call)")
		lines.append("\(indent)}")
		if isInstantiator {
			lines.append(contentsOf: instantiatorBindingLines())
		} else {
			lines.append("\(indent)let \(property.label): \(typeName) = \(isPromoted ? ScopeGenerator.passing(property.label, orBuilding: "\(functionName)()") : "\(functionName)()")")
		}
		return .publicMockCall(node)
	}
}

extension MockLowering {
	/// The family of a builder a call of another module's public mock passes up, by the property the call's leaf receives it
	/// as: whether a `@Sendable` builder function captures it, and the properties of the places the called builders reach, in
	/// the order of the calls (`SeamMockBuilder.PassedUpBuilder.placeProperties`).
	struct PassedUpBuilderFamily {
		let family: ScopeGenerator.MockRootParameters.SeamMockBuilder.Family
		let isCapturedBySendableFunction: Bool
		let placeProperties: [Property]
	}

	/// A node of a mock's tree that calls another module's public mock, which builds the node's whole tree.
	struct PublicMockCallNode {
		let property: Property
		/// The type whose public mock the node calls.
		let calledType: TypeDescription
		let call: PublicMockCall
		/// Whether the member that configures the call is a `@Sendable` closure: the call is built inside a `@Sendable`
		/// function, or the configuration that holds the member is `@Sendable`-typed.
		let overridesAreSendable: Bool
		/// For a call of a mock that takes no overrides, the type of the closure that builds the called type, where the call
		/// offers one (`ScopeGenerator.publicMockOverrideBuilders`).
		let overrideClosureType: String?

		/// The member of the calling mock's overrides that configures the call: the called mock's own `SafeDIOverrides`, or,
		/// for a mock that takes none, the closure that builds the called type, where the call offers one.
		var overridesField: OverridesField? {
			if call.takesOverrides {
				overridesAreSendable
					? OverridesField(
						name: property.label,
						typeSource: "(@Sendable () -> \(calledType.asSource).\(ReservedName.mockOverridesTypeName))?",
						defaultValue: "nil",
						sendability: .always,
					)
					: OverridesField(
						name: property.label,
						typeSource: "\(calledType.asSource).\(ReservedName.mockOverridesTypeName)",
						defaultValue: ".init()",
						sendability: .never,
					)
			} else if let overrideClosureType {
				OverridesField(
					name: property.label,
					typeSource: "(\(overridesAreSendable ? "@Sendable " : "")\(overrideClosureType))?",
					defaultValue: "nil",
					sendability: overridesAreSendable ? .always : .never,
				)
			} else {
				nil
			}
		}

		/// The member that configures the call in a configuration `@Sendable`-typed, always a `@Sendable` closure
		/// (`ScopeGenerator.configurationField(of:named:parentRequiresSendable:sendableConfigurationTypeNames:)`).
		var sendableConfigurationFieldForm: ConfigurationRecord.ChildField.SendableForm? {
			if call.takesOverrides {
				.init(typeSource: "(@Sendable () -> \(calledType.asSource).\(ReservedName.mockOverridesTypeName))?", defaultValue: "nil", configuredTypeName: nil)
			} else {
				overrideClosureType.map { .init(typeSource: "(@Sendable \($0))?", defaultValue: "nil", configuredTypeName: nil) }
			}
		}
	}
}

extension MockLowering {
	/// The builders `mock()` takes optional for the places its root-level calls of other modules' public mocks fill
	/// (`ScopeGenerator.filledCallBuilders(of:context:)`), and the calls, in generation order, each taken by the walk as it reaches it.
	struct FilledCallBuilders {
		/// A call that fills builders, with the `propertiesGeneratedLater` its fills are generated with.
		struct Call {
			let generator: ScopeGenerator
			let propertiesGeneratedLater: Set<Property>
		}

		/// The calls the walk has not reached yet.
		var calls: [Call]
		/// Each builder's label and its declaration, in label order.
		let parameters: [(label: String, declaration: String)]
		/// The builders each call hands its called builders, which its fills are generated with.
		private(set) var fillPlaceBindings: ScopeGenerator.FillPlaceBindings

		/// These builders with the names the mock root binds each value apart from its label under, by label and type, which a
		/// fill reading the caller's own value from the root's binding binds the label to (`FillPlaceBindings.rootBindingNames`):
		/// known once the walk names the root's level.
		mutating func bindingRootNames(_ rootBindingNames: [String: [TypeDescription: String]]) {
			fillPlaceBindings = ScopeGenerator.FillPlaceBindings(
				bindingsByGenerator: fillPlaceBindings.bindingsByGenerator,
				rootBindingNames: rootBindingNames,
				holeBuildersByCall: fillPlaceBindings.holeBuildersByCall,
				holeBuildersByInlinePlace: fillPlaceBindings.holeBuildersByInlinePlace,
			)
		}

		/// The name `mock()` binds each builder a call passes up under, by the property the call's leaf receives it as
		/// (`RootSignature.passedUpBuilders`).
		var passedUpBuilderNames: [Property: String] = [:]
		/// The families of hole type the calls fill, in the order `filledFamilies(of:)` gives, which a public mock's plan names.
		var families = [ScopeGenerator.FilledFamily]()
		/// The labels the calls' fills declare, which a public mock's optional builders are named apart from.
		var namesFillsDeclare = Set<String>()
		/// The lines that bind each builder `mock()` takes for the calls' places under its internal name where that is not
		/// its label, with the label, which orders them among the signature's passed-up builders (`RootSignature.passedUpBuilders`).
		var builderBindingLines = [(label: String, line: String)]()
		/// The builder `mock()` takes that each place of another module's public mock the tree builds inline outside every
		/// fill reads, by the place's path of child indices beneath the root (`MockLowering.Walk.childIndexPath`).
		var holeBuildersByInlinePlace = [[Int]: ScopeGenerator.FillPlaceBindings.HoleBuilder]()

		/// No call fills a builder.
		static let none = FilledCallBuilders(calls: [], parameters: [], fillPlaceBindings: ScopeGenerator.FillPlaceBindings(bindingsByGenerator: [:]))
	}
}

extension MockLowering {
	/// A place of another module's public mock the tree builds inline outside every fill, a hole of that mock, which reads the
	/// builder `mock()` takes for its hole type and family, as a call of the public mock hands the place the builder
	/// (`ScopeGenerator.FillPlaceBindings.holeBuildersByInlinePlace`).
	struct InlinePlace {
		/// The builder the place reads.
		let builder: ScopeGenerator.FillPlaceBindings.HoleBuilder
		/// The read of the place's override where its wrapper is bound, outside its builder function.
		let overrideRead: String?

		/// The statements that bind a place held in a wrapper, `typeDescription`, as `bindingName`: the wrapper made of the
		/// builder where no override is set, or else around the builder function `functionName`, as `wrapperBindingLines`
		/// makes it (`ScopeGenerator.generateInstantiatorBinding`).
		func wrapperBindingLines(of typeDescription: TypeDescription, named bindingName: String, handing functionName: String, forwardedProperties: [Property], cycleParameterArguments: [String], indent: String) -> [String] {
			let unwrappedType = typeDescription.unwrapped
			let binding = unwrappedType.isConstructedByAnnotation ? "\(bindingName): \(unwrappedType.asSource)" : bindingName
			let bindingPrefix = "\(indent)let \(binding) = "
			let wrapperLines = MockLowering.wrapperBindingLines(of: typeDescription, named: bindingName, handing: functionName, forwardedProperties: forwardedProperties, cycleParameterArguments: cycleParameterArguments, indent: indent)
			let construction = String(MockLowering.joinedLines(wrapperLines).dropFirst(bindingPrefix.count))
			let value = builder.inlinePlaceValue(construction: construction, overrideExpression: overrideRead, wrappingBuilderIn: unwrappedType.spelledForConstruction)
			return GeneratedCodeText.lines(of: "\(bindingPrefix)\(value)")
		}
	}
}
