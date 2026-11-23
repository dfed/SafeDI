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
	/// The builders `mock()` takes optional for the places its calls of other modules' public mocks fill, from the root's
	/// children, `orderedChildren`, in generation order, as `seamMockBuilders` computes them for a mock whose calls are made
	/// at the root's level, fill every place of each builder they take, and hold no place or call in their fills; or the
	/// first rule the calls meet. Each family of hole type is one builder, labeled from its stem
	/// (`stemsOfOptionalBuilders`) apart from `safeDIOverrides`, in label order.
	///
	/// A public mock names each builder as its plan does (`optionalBuilderNames`, by family), apart from every name of its body.
	func filledCallBuilders(of orderedChildren: [OrderedChild], context: MockContext, rootBoundProperties: Set<Property>, optionalBuilderNames: [MockRootParameters.SeamMockBuilder.Family: String]? = nil) -> MockLowering.Lowering<MockLowering.FilledCallBuilders> {
		var calls = [MockLowering.FilledCallBuilders.Call]()
		var filledCalls = [FilledCall]()
		var namesFillsDeclare = Set<String>()
		// The places inside the calls' fills, each a place of the builder `mock()` takes for its hole type and family, in the
		// order the calls are generated (`fillPlaces(in:)`).
		var fillPlaces = [FillPlace]()
		// What the mock's root level declares, which a fill reading a value of the caller's scope reads: what `mock()` binds
		// before its tree, and the root's children.
		var rootLevelProperties = rootBoundProperties
		for child in orderedChildren {
			if let property = child.generator.property {
				rootLevelProperties.insert(property)
			}
		}
		// A non-optional `LazilyInstantiated` or `SendableLazilyInstantiated` a level binds offers its instance too, which a
		// fill reading the value by value reads.
		func addingInstances(of properties: Set<Property>) -> Set<Property> {
			var properties = properties
			for property in properties where property.typeDescription.unwrapped == property.typeDescription {
				guard let instanceType = property.typeDescription.lazilyInstantiatedInstanceType else { continue }
				properties.insert(Property(label: property.label, typeDescription: instanceType))
			}
			return properties
		}
		rootLevelProperties = addingInstances(of: rootLevelProperties)
		// The calls that fill builders, in the order the walk reaches them (depth first, each level in generation order), each
		// with what the levels above it declare, which a fill reading a value of the caller's scope reads. A call inside a `@Sendable` builder function is not lowered yet.
		var callsInWalkOrder = [(child: OrderedChild, declaredAbove: Set<Property>)]()
		var childrenToVisit = orderedChildren.reversed().map { (child: $0, declaredAbove: rootLevelProperties, isInsideSendableFunction: false) }
		while let (child, declaredAbove, isInsideSendableFunction) = childrenToVisit.popLast() {
			let generator = child.generator
			if generator.publicMockCall != nil {
				guard generator.fillsABuilder else { continue }
				guard !isInsideSendableFunction else { return .unsupported(.fill) }
				callsInWalkOrder.append((child, declaredAbove))
				continue
			}
			guard case let .property(instantiable, _, _, _, false, _) = generator.scopeData else { continue }
			let grandchildren = generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: generator.mockLoweringBodyPropertiesGeneratedLater(child.propertiesGeneratedLater))
			let levelProperties = Set(grandchildren.compactMap(\.generator.property)).union(instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property))
			let nestedDeclaredAbove = addingInstances(of: declaredAbove.union(levelProperties))
			let nestedIsInsideSendableFunction = isInsideSendableFunction || generator.buildsInSendableFunction
			childrenToVisit.append(contentsOf: grandchildren.reversed().map { ($0, nestedDeclaredAbove, nestedIsInsideSendableFunction) })
		}
		for (child, declaredAbove) in callsInWalkOrder {
			let generator = child.generator
			guard let publicMockCall = generator.publicMockCall,
			      publicMockCall.passedUpBuilders.isEmpty,
			      !generator.buildsInSendableFunction,
			      !generator.declaresCycleParameters,
			      generator.reboundProperties.isEmpty
			else { return .unsupported(.fill) }
			// A fill that reads a value of the caller's scope reads what the mock binds or offers for it.
			for fill in generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: child.propertiesGeneratedLater).map(\.generator) {
				// A fill that reads the caller's own value from a root binding named apart from its label binds the label to that
				// name (`bindingRootNames(_:)`).
				guard case .fill = fill.scopeData,
				      fill.receivedProperties.allSatisfy({ declaredAbove.contains($0) || declaredAbove.contains($0.asUnwrappedProperty) })
				else { return .unsupported(.fill) }
			}
			// A place inside a fill takes a required builder, which an internal mock takes (a public mock's are places of its own
			// tree). A call inside a fill is generated with the fill, reading the builders `mock()` takes for the places it fills
			// as the call does.
			let callPlaces = generator.fillPlaces(insideSendableFunction: false)
			guard optionalBuilderNames == nil || callPlaces.places.isEmpty else { return .unsupported(.fill) }
			fillPlaces += callPlaces.places.map { place in
				FillPlace(generator: place.generator, dependency: place.dependency, isInsideSendableFunction: place.isInsideSendableFunction, order: fillPlaces.count + place.order)
			}
			let filledCall = FilledCall(generator: generator, isInsideSendableFunction: false, enclosingCalls: [])
			guard filledCall.filledBuilders.count == publicMockCall.builders.count else { return .unsupported(.fill) }
			for callInsideFill in callPlaces.calls {
				guard let calledMock = callInsideFill.generator.publicMockCall,
				      calledMock.passedUpBuilders.isEmpty,
				      callInsideFill.filledBuilders.count + callInsideFill.reenteredBuilders.count == calledMock.builders.count
				else { return .unsupported(.fill) }
			}
			namesFillsDeclare.formUnion(callPlaces.declaredLabels)
			filledCalls.append(filledCall)
			filledCalls.append(contentsOf: callPlaces.calls)
			calls.append(.init(generator: generator, propertiesGeneratedLater: child.propertiesGeneratedLater))
		}
		// The builders' names are the signature's (`RootSignature.passedUpBuilders`), which the walk reads.
		let passesUpBuilders: Bool
		switch passedUpBuilderFamilies(of: orderedChildren.map(\.generator)) {
		case let .lowered(families):
			passesUpBuilders = !families.isEmpty
		case let .unsupported(rule):
			return .unsupported(rule)
		}
		// A place of another module's public mock the tree builds inline reads the builder `mock()` takes for its hole type
		// and family, a builder a call passes up included, which the walk does not lower yet.
		do {
			guard try !passesUpBuilders || !treeBuildsInlinePlaceReadingBuilder(of: orderedChildren, holeTypes: nil, foreignPublicMocks: context.foreignPublicMocks) else { return .unsupported(.publicMockCall) }
		} catch {
			return .unsupported(.publicMockCall)
		}
		guard !calls.isEmpty else { return .lowered(MockLowering.FilledCallBuilders(calls: [], parameters: [], fillPlaceBindings: FillPlaceBindings(bindingsByGenerator: [:]))) }
		// A builder a call passes up beside the builders the calls fill is not lowered yet.
		guard !passesUpBuilders else { return .unsupported(.publicMockCall) }
		// The labels the tree binds and its types' dependencies have beneath the root's level, which name a builder apart.
		var namesBoundInTheTree = Set<String>()
		var generatorsToVisit = orderedChildren.map(\.generator)
		while let generator = generatorsToVisit.popLast() {
			switch generator.scopeData {
			case let .property(instantiable, property, _, _, _, _):
				namesBoundInTheTree.insert(property.label)
				guard generator.publicMockCall == nil else { continue }
				namesBoundInTheTree.formUnion(instantiable.dependencies.map(\.property.label))
			case let .alias(property, _, _, _, _):
				namesBoundInTheTree.insert(property.label)
			case .root, .hole, .fill:
				break
			}
			generatorsToVisit.append(contentsOf: generator.orderedChildGenerators)
		}
		// Each family of the fills' places is a builder `mock()` requires, which the calls' builders of that family join
		// (`seamMockBuilders`); every other family a call fills is a builder `mock()` takes optional.
		var fillPlacesByFamily = [MockRootParameters.SeamMockBuilder.Family: [FillPlace]]()
		var requiredFamilies = [MockRootParameters.SeamMockBuilder.Family]()
		for fillPlace in fillPlaces {
			let family = MockRootParameters.SeamMockBuilder.Family(of: fillPlace)
			if fillPlacesByFamily[family] == nil {
				requiredFamilies.append(family)
			}
			fillPlacesByFamily[family, default: []].append(fillPlace)
		}
		var requiredHoleTypes = [SeamSignature.HoleType]()
		for family in requiredFamilies where !requiredHoleTypes.contains(family.holeType) {
			requiredHoleTypes.append(family.holeType)
		}
		let requiredStems = DependencyTreeGenerator.stems(of: requiredHoleTypes)
		let allFamilies = Self.filledFamilies(of: filledCalls)
		let families = allFamilies.filter { fillPlacesByFamily[$0.family] == nil }
		let stems = Self.stemsOfOptionalBuilders(
			of: families.map { ($0.family.holeType, $0.receivedProperty) },
			besideOwnHoleTypes: requiredHoleTypes,
			passedUpHoleTypes: [],
			requiredStems: requiredStems,
		)
		var labels = GeneratedNameAllocator(reserving: [ReservedName.mockOverridesParameterName])
		var parameters = [(label: String, declaration: String)]()
		var holeBuildersByCall = [ObjectIdentifier: [String: FillPlaceBindings.HoleBuilder]]()
		var buildersByFamily = [MockRootParameters.SeamMockBuilder.Family: FillPlaceBindings.HoleBuilder]()
		// A builder labeled as another parameter of `mock()` or a name of the tree is named apart, which is not lowered yet.
		var namesBuildersAvoid = namesBoundInTheTree.union(receivedProperties.map(\.label))
		if case let .root(instantiable, _) = scopeData {
			namesBuildersAvoid.formUnion(instantiable.dependencies.map(\.property.label))
			namesBuildersAvoid.formUnion((instantiable.initializer?.arguments ?? []).map(\.innerLabel))
		}
		var fillPlaceBindingsInOrder = [(order: Int, generator: ObjectIdentifier, binding: SendableAutoclosureParameter)]()
		for family in requiredFamilies {
			let stem = requiredStems[family.holeType, default: ""]
			let label = labels.claim(family.isSendable ? DependencyTreeGenerator.sendableBuilderLabel(ofStem: stem) : DependencyTreeGenerator.plainBuilderLabel(ofStem: stem))
			guard !namesFillsDeclare.contains(label), !namesBuildersAvoid.contains(label) else { return .unsupported(.fill) }
			let places = fillPlacesByFamily[family, default: []]
			let parameterType = MockRootParameters.SeamMockBuilder.parameterType(ofPlaceProperties: places.map(\.dependency.property), in: family)
			parameters.append((label, "\(label): \(parameterType.asSource)"))
			for place in places {
				fillPlaceBindingsInOrder.append((place.order, place.generator, SendableAutoclosureParameter(name: place.dependency.property.label, localName: label, valueType: place.dependency.property.typeDescription)))
			}
			let holeBuilder = FillPlaceBindings.HoleBuilder(name: label, isOptional: false)
			buildersByFamily[family] = holeBuilder
			for callBuilder in allFamilies.first(where: { $0.family == family })?.callBuilders ?? [] {
				holeBuildersByCall[callBuilder.call, default: [:]][callBuilder.label] = holeBuilder
			}
		}
		var fillPlaceBindingsByGenerator = [ObjectIdentifier: [SendableAutoclosureParameter]]()
		for (_, generator, binding) in fillPlaceBindingsInOrder.sorted(by: { $0.order < $1.order }) {
			fillPlaceBindingsByGenerator[generator, default: []].append(binding)
		}
		for filled in families {
			let stem = stems[filled.family.holeType, default: ""]
			let label: String
			if let optionalBuilderNames {
				guard let name = optionalBuilderNames[filled.family] else { return .unsupported(.fill) }
				label = name
			} else {
				label = labels.claim(filled.family.isSendable ? DependencyTreeGenerator.sendableBuilderLabel(ofStem: stem) : DependencyTreeGenerator.plainBuilderLabel(ofStem: stem))
				// A builder whose label a name of the tree or of the fills has is called by a name apart, which `mock()` binds.
				guard !namesFillsDeclare.contains(label), !namesBoundInTheTree.contains(label) else { return .unsupported(.fill) }
				// Beside a required builder, a label another parameter of `mock()` has is named apart, which is not lowered yet.
				guard fillPlaces.isEmpty || !namesBuildersAvoid.contains(label) else { return .unsupported(.fill) }
			}
			let parameterType = MockRootParameters.SeamMockBuilder.parameterType(ofPlaceProperties: filled.placeProperties, in: filled.family)
			parameters.append((label, "\(label): \(TypeDescription.optional(parameterType.strippingEscaping).asSource) = nil"))
			let holeBuilder = FillPlaceBindings.HoleBuilder(name: label, isOptional: true)
			buildersByFamily[filled.family] = holeBuilder
			for callBuilder in filled.callBuilders {
				holeBuildersByCall[callBuilder.call, default: [:]][callBuilder.label] = holeBuilder
			}
		}
		parameters.sort { $0.label < $1.label }
		// A place of another module's public mock the tree builds inline reads the builder `mock()` takes for its hole type and
		// family: inside a fill, where the fill's code reads it; outside every fill, where the walk does not lower it yet.
		let holeBuildersByInlinePlaceInFills: [ObjectIdentifier: FillPlaceBindings.HoleBuilder]
		do {
			guard try !treeBuildsInlinePlaceReadingBuilder(of: orderedChildren, holeTypes: Set(buildersByFamily.keys.map(\.holeType)), foreignPublicMocks: context.foreignPublicMocks) else { return .unsupported(.fill) }
			holeBuildersByInlinePlaceInFills = try Self.holeBuildersByInlinePlaceInFills(of: filledCalls, buildersByFamily: buildersByFamily, foreignPublicMocks: context.foreignPublicMocks)
		} catch {
			return .unsupported(.fill)
		}
		var filledCallBuilders = MockLowering.FilledCallBuilders(
			calls: calls,
			parameters: parameters,
			fillPlaceBindings: FillPlaceBindings(bindingsByGenerator: fillPlaceBindingsByGenerator, holeBuildersByCall: holeBuildersByCall, holeBuildersByInlinePlace: holeBuildersByInlinePlaceInFills),
		)
		filledCallBuilders.families = families
		filledCallBuilders.namesFillsDeclare = namesFillsDeclare
		filledCallBuilders.optionalBuilderNames = optionalBuilderNames
		return .lowered(filledCallBuilders)
	}

	/// Whether the leaf of `generator`, a call of another module's public mock, receives `property`: an internal caller's leaf
	/// receives each builder the call passes up, while a `.public` caller's receives none and passes its own struct's member.
	private func callsLeafReceivesBuilder(of generator: ScopeGenerator, _ property: Property) -> Bool {
		guard case let .property(instantiable, _, _, _, _, _) = generator.scopeData else { return false }
		return instantiable.dependencies.contains { $0.property == property }
	}

	/// The family of each builder a call of another module's public mock in the tree of `generators` passes up, by the
	/// property the call's leaf receives it as, with whether a `@Sendable` builder function captures it, as
	/// `PublicMockCall.passedUpBuilders` and `passedUpBuildersCapturedBySendableFunctions` find them; or the first rule the
	/// builders meet. Walked with a stack, since a tree can be as deep as the module has types.
	// D1 lane hook (lane C): the lowering's signature names a builder per family (`seamMockBuilders`).
	func passedUpBuilderFamilies(of generators: [ScopeGenerator]) -> MockLowering.Lowering<[Property: MockLowering.PassedUpBuilderFamily]> {
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
					// family (`passedUpBuilders`).
					let property = parameter.dependency.property
					let family = MockRootParameters.SeamMockBuilder.Family(holeType: builder.enumKey.holeType, isSendable: builder.enumKey.isSendable || capturesSendably)
					let isCaptured = capturesSendably || familyByProperty[property]?.isCapturedBySendableFunction == true
					// One property passed up in two families is not lowered yet.
					guard familyByProperty[property].map({ $0.family.holeType == family.holeType }) ?? true else { return .unsupported(.publicMockCall) }
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
		return .lowered(familyByProperty)
	}

	/// Whether the tree of `orderedChildren`, outside the fills of its calls, builds inline a place of another module's public
	/// mock of one of `holeTypes`, or of any hole type where `holeTypes` is `nil`, a hole of that mock, which reads the builder
	/// `mock()` takes for its hole type and family, as `holeBuildersByInlinePlace(in:buildersByFamily:foreignPublicMocks:)`
	/// finds them. Walked with a stack, since a tree can be as deep as the module has types.
	private func treeBuildsInlinePlaceReadingBuilder(
		of orderedChildren: [OrderedChild],
		holeTypes: Set<SeamSignature.HoleType>?,
		foreignPublicMocks: [TypeDescription: SeamResolution.ForeignPublicMock],
	) throws -> Bool {
		guard holeTypes?.isEmpty != true, !foreignPublicMocks.isEmpty else { return false }
		// Each scope with the public mock built inline nearest above it, and the type its declaration instantiates, which a
		// `fulfilledByType:` names.
		var generatorsToVisit = orderedChildren.map { (generator: $0.generator, publicMockBuiltInline: SeamResolution.ForeignPublicMock?.none, instantiatedType: TypeDescription?.none) }
		while let (generator, publicMockBuiltInline, declaredInstantiatedType) = generatorsToVisit.popLast() {
			// A scope that closes a cycle builds nothing, and a call's places are the call's.
			guard case let .property(instantiable, property, _, _, false, _) = generator.scopeData, generator.publicMockCall == nil else { continue }
			let instantiatedType = declaredInstantiatedType ?? property.typeDescription.asInstantiatedType
			if let publicMockBuiltInline,
			   try publicMockBuiltInline.visibleDeclarations().instantiables[instantiatedType] == nil,
			   holeTypes?.contains(SeamSignature.HoleType(instantiatedType: instantiatedType.spelledCanonically, builtType: property.typeDescription.builtTypeOfWrapper.spelledCanonically)) ?? true
			{
				return true
			}
			let enclosingPublicMock = foreignPublicMocks[instantiable.concreteInstantiable] ?? publicMockBuiltInline
			let instantiatedTypes = Dictionary(instantiable.dependencies.map { ($0.property, $0.asInstantiatedType) }, uniquingKeysWith: { first, _ in first })
			generatorsToVisit += generator.orderedChildGenerators.map { child in
				(child, enclosingPublicMock, child.property.flatMap { instantiatedTypes[$0] })
			}
		}
		return false
	}
}

/// Stage D1's lowering of lane E's family: the calls of other modules' public mocks, their fills, override closures and
/// optional builders.
extension MockLowering.Walk {
	/// The node of `generator`, a call of another module's public mock, whose statements are appended to `lines`, or the
	/// first rule it meets. The call names the mock's guard where it is made and passes the mock its own `SafeDIOverrides`,
	/// which the calling mock's overrides hold under the node's label.
	mutating func publicMockCallNode(
		of generator: ScopeGenerator,
		inScope scope: Set<Property>,
		path: String,
		indent: String,
		lines: inout [String],
	) async -> MockLowering.Lowering<MockLowering.TreeNode> {
		guard let publicMockCall = generator.publicMockCall,
		      case let .property(instantiable, property, forwardedProperties, erasedToConcreteExistential, isPropertyCycle, _) = generator.scopeData
		else { return .unsupported(.publicMockCall) }
		// A call held in an erased type is wrapped in that type, as an inline construction is.
		guard !isPropertyCycle,
		      property.propertyType.isConstant || [.instantiator, .sendableInstantiator].contains(property.propertyType) || erasedToConcreteExistential && [.erasedInstantiator, .sendableErasedInstantiator].contains(property.propertyType),
		      erasedToConcreteExistential || property.typeDescription.asInstantiatedType == instantiable.concreteInstantiable
		else { return .unsupported(.publicMockCall) }
		guard !rootLabels.contains(property.label), labels.insert(property.label).inserted else { return .unsupported(.siblingLabelCollision) }
		// The leaf takes the called tier's parameters as its mock's.
		let constructionInitializer = instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType) ? instantiable.mockInitializer : instantiable.initializer
		guard let initializer = constructionInitializer else { return .unsupported(.publicMockCall) }
		// A call of a mock that takes no overrides is configured by an override closure, handed what the called `mock()`
		// takes, where the call can hand each builder as a function a person writes (`ScopeGenerator.publicMockOverrideBuilders`).
		let overrideBuilders = publicMockCall.takesOverrides ? nil : generator.publicMockOverrideBuilders
		let dependencyLabels = Set(instantiable.dependencies.map(\.property.label))
		// The call leaves a default-valued argument that is no dependency to its default, which the override's closure type
		// leaves out too.
		guard !initializer.arguments.contains(where: { $0.isLeftToItsDefault && !dependencyLabels.contains($0.innerLabel) }) else { return .unsupported(.publicMockCall) }
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
		let filledCall: MockLowering.FilledCallBuilders.Call?
		if generator.fillsABuilder {
			guard !filledCallBuilders.calls.isEmpty, filledCallBuilders.calls[0].generator === generator else { return .unsupported(.fill) }
			filledCall = filledCallBuilders.calls.removeFirst()
		} else {
			filledCall = nil
		}
		let innerIndent = filledCall == nil ? indent : "\(indent)\(ScopeGenerator.standardIndent)"
		let holeBuilders = filledCallBuilders.fillPlaceBindings.holeBuildersByCall[ObjectIdentifier(generator)] ?? [:]
		let structValuesByLabel = generator.publicMockBuilderStructValuesByLabel
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
				guard scope.contains(dependency.property), filledCall == nil else { return .unsupported(.publicMockCall) }
				if let overrideBuilders {
					guard case .callersBuilder = overrideBuilders[argument.innerLabel] else { return .unsupported(.publicMockCall) }
					overrideArguments.append(dependency.property.label)
				}
				// The leaf reads the builder under the name `mock()` binds it, bound again under its label where they differ.
				if builderName != dependency.property.label {
					passedUpBuilderBindings.append("let \(dependency.property.label): \(dependency.property.typeDescription.strippingEscaping.asSource) = \(builderName)")
				}
				arguments.append(labeled(".init(\(ReservedName.noScopeArgumentLabel): \(dependency.property.label))", as: argument))
			} else if let builderStruct = structValuesByLabel[argument.innerLabel] {
				let fillsStruct = builderStruct.replacingOccurrences(of: "\n\(ScopeGenerator.standardIndent)", with: "\n\(innerIndent)")
				arguments.append(labeled(holeBuilders[argument.innerLabel]?.structValue(fillsStruct: fillsStruct) ?? fillsStruct, as: argument))
				if let overrideBuilders {
					// A builder an internal mock passes up whole is not lowered yet.
					guard let overrideBuilder = overrideBuilders[argument.innerLabel], case .fill = overrideBuilder else { return .unsupported(.publicMockCall) }
					overrideArguments.append(argument.innerLabel)
				}
			} else if overrideBuilders == nil, let holeValue = holeArgumentValuesByLabel[argument.innerLabel] {
				// A builder a `.public` caller's call passes up, as its own struct's member. An override closure handed one is not
				// lowered yet: the leaf receives no builder, so the values below find no dependency of its label.
				arguments.append(labeled(holeValue, as: argument))
			} else {
				// A value the call passes is the root level's binding of its label, which an optional parameter takes as it is, or
				// the instance of the lazy wrapper the tree holds of it, read at the call (`dependencyArgument`).
				guard let dependency = instantiable.dependencies.first(where: { $0.property.label == argument.innerLabel }) else { return .unsupported(.publicMockCall) }
				let value: String
				if generator.unavailableOptionalProperties.contains(dependency.property) {
					// A value the call's leaf receives only if available that nothing provides where the call is made, or that a
					// `@Sendable` function would capture, is passed `nil` (`constructionArgumentList(of:unavailableProperties:)`).
					value = "nil"
				} else if dependency.source == .forwarded {
					// A value the called type forwards is the parameter of the builder function the instantiator holds.
					guard forwardedProperties.contains(dependency.property) else { return .unsupported(.publicMockCall) }
					value = dependency.property.label
				} else if dependency.source.isReceived,
				          lazilyInstantiatedInstances.contains(dependency.property.asUnwrappedProperty),
				          let wrapperName = lazilyInstantiatedNamesOfLabels[dependency.property.label].flatMap({ namesByType in
				          	[Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType].compactMap { namesByType[.simple(name: $0, generics: [dependency.property.typeDescription.unwrapped])] }.first
				          })
				{
					// D1 lane hook (lane C): the instance of the wrapper `mock()` binds apart from the instance it takes
					// (`dependencyArgument`).
					value = "\(wrapperName).\(Dependency.lazilyInstantiatedInstancePropertyName)"
				} else if dependency.source.isReceived, let wrapperName = lazilyInstantiatedNamesOfLabels[dependency.property.label]?[dependency.property.typeDescription] {
					// D1 lane hook (lane C): the wrapper `mock()` binds around the instance it takes, passed by name
					// (`dependencyArgument`).
					value = wrapperName
				} else if dependency.source.isReceived, let renamedName = renames[dependency.property.label]?[dependency.property.typeDescription] {
					// D1 lane hook (lane C): a receive the mock names apart is bound again under its label in the call's builder
					// function (`emitReceiverBindings`). An override closure or a fill beside it is not lowered yet.
					guard overrideBuilders == nil, filledCall == nil, property.propertyType.isConstant else { return .unsupported(.publicMockCall) }
					passedUpBuilderBindings.append("let \(dependency.property.label): \(dependency.property.typeDescription.asSource) = \(renamedName)")
					value = dependency.property.label
				} else if dependency.source.isReceived, lazilyInstantiatedInstances.contains(dependency.property.asUnwrappedProperty) {
					// A label the tree holds in both wrapper kinds is named apart, which is not lowered yet.
					guard scope.count(where: { $0.label == dependency.property.label && $0.typeDescription.lazilyInstantiatedInstanceType != nil }) == 1 else { return .unsupported(.publicMockCall) }
					value = "\(dependency.property.label).\(Dependency.lazilyInstantiatedInstancePropertyName)"
				} else {
					guard scope.contains(dependency.property) || dependency.property.typeDescription.isOptional && scope.contains(dependency.property.asUnwrappedProperty) else { return .unsupported(.publicMockCall) }
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
		let overrideRead: String
		if publicMockCall.takesOverrides || overrideBuilders != nil {
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
		if publicMockCall.takesOverrides {
			arguments.append("\(ReservedName.mockOverridesParameterName): \(overridesAreSendable ? "\(overrideRead)?() ?? .init()" : overrideRead)")
		}
		let unerasedCall = "\(instantiable.concreteInstantiable.asSource).\(publicMockCall.functionName)(\(arguments.joined(separator: ", ")))"
		let defaultCall = erasedToConcreteExistential ? "\(property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource)(\(unerasedCall))" : unerasedCall
		let call: String
		if let overrideBuilders {
			// An override closure of a call held in an erased type is not lowered yet.
			guard !erasedToConcreteExistential else { return .unsupported(.publicMockCall) }
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
		let functionDecorator = generator.buildsInSendableFunction ? "@Sendable " : ""
		// The values an instantiator's builder function takes from the instantiator, in label order, which the call passes on.
		let forwarded = forwardedProperties.sorted { $0.label < $1.label }
		let functionParameters = forwarded.map { "\($0.label): \($0.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: generator.typesDeclaredEscaping).asSource)" }.joined(separator: ", ")
		// A call a public mock promotes at its root's level reads its caller's value first, which only a call with no fill and
		// no builder bound again is lowered for.
		let isPromoted = parentConcreteType == nil && promotedProperties.contains(property)
		func instantiatorBindingLines() -> [String] {
			isPromoted
				? [MockLowering.promotedWrapperBindingLine(of: property.typeDescription, named: property.label, passing: property.label, handing: functionName, forwardedProperties: forwarded, indent: indent)]
				: MockLowering.wrapperBindingLines(of: property.typeDescription, named: property.label, handing: functionName, forwardedProperties: forwarded, indent: indent)
		}
		// A call held in an instantiator is made in the builder function the instantiator holds.
		let isInstantiator = !property.propertyType.isConstant
		guard !isPromoted || filledCall == nil && passedUpBuilderBindings.isEmpty else { return .unsupported(.publicMockCall) }
		guard let filledCall else {
			lines.append("\(indent)\(publicMockCall.guardLine(for: instantiable.concreteInstantiable))")
			lines.append(contentsOf: extractionLines)
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
				return .lowered(.publicMockCall(node))
			}
			if isInstantiator {
				lines.append("\(indent)\(functionDecorator)func \(functionName)(\(functionParameters)) -> \(typeName) {")
				lines.append("\(indent)\(ScopeGenerator.standardIndent)\(call)")
				lines.append("\(indent)}")
				lines.append(contentsOf: instantiatorBindingLines())
			} else {
				// A constant call a cycle makes `@Sendable` is made in a builder function of its own, which is not lowered yet.
				guard extractionLines.isEmpty else { return .unsupported(.publicMockCall) }
				lines.append("\(indent)let \(property.label) = \(isPromoted ? ScopeGenerator.passing(property.label, orBuilding: call) : call)")
			}
			return .lowered(.publicMockCall(node))
		}
		// A fill that reads the caller's own value from a root binding the walk has no name for, such as a wrapper a public
		// mock takes under its label, is not lowered yet.
		for fill in generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: filledCall.propertiesGeneratedLater).map(\.generator) {
			guard fill.fillCallerReads.mockRootBindingByLabel.allSatisfy({ label, property in
				filledCallBuilders.fillPlaceBindings.rootBindingNames[label]?[property.typeDescription] != nil
			}) else { return .unsupported(.fill) }
		}
		let fillCode: String
		do {
			fillCode = try await generator.mockLoweringFillCode(propertiesGeneratedLater: filledCall.propertiesGeneratedLater, fillPlaceBindings: filledCallBuilders.fillPlaceBindings).joined(separator: "\n")
		} catch {
			return .unsupported(.fill)
		}
		lines.append(contentsOf: extractionLines)
		lines.append("\(indent)\(functionDecorator)func \(functionName)(\(functionParameters)) -> \(typeName) {")
		// The members a `@Sendable` family's places inside the fills read, which the call's builder function calls at its top.
		lines.append(contentsOf: generator.memberCallsInsideBuilderFunction.map { "\(innerIndent)\($0.line(bindingNamesPassedByName: enclosingBindingNamesPassedByName, lazilyInstantiatedBindingNames: [:]))" })
		for line in fillCode.split(separator: "\n", omittingEmptySubsequences: false) where !fillCode.isEmpty {
			lines.append(line.isEmpty ? "" : "\(innerIndent)\(line)")
		}
		lines.append("\(innerIndent)\(publicMockCall.guardLine(for: instantiable.concreteInstantiable))")
		// Each receive of the call's leaf the mock names apart is bound again under its label (`emitReceiverBindings`), a
		// receive of a lazy wrapper's instance binding the wrapper named apart.
		for dependency in instantiable.dependencies {
			guard case .received = dependency.source, !generator.unavailableOptionalProperties.contains(dependency.property), let names = renames[dependency.property.label] else { continue }
			if generator.mockLoweringLazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty) {
				let instanceType = dependency.property.typeDescription.unwrapped
				guard let (wrapperType, name) = [Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType]
					.lazy
					.map({ TypeDescription.simple(name: $0, generics: [instanceType]) })
					.compactMap({ wrapperType in names[wrapperType].map { (wrapperType, $0) } })
					.first
				else { continue }
				lines.append("\(innerIndent)let \(dependency.property.label): \(wrapperType.asSource) = \(name)")
			} else if let name = names[dependency.property.typeDescription] ?? names[dependency.property.asUnwrappedProperty.typeDescription] {
				lines.append("\(innerIndent)let \(dependency.property.label): \(dependency.property.typeDescription.asSource) = \(name)")
			}
		}
		lines.append("\(innerIndent)return \(call)")
		lines.append("\(indent)}")
		if isInstantiator {
			lines.append(contentsOf: instantiatorBindingLines())
		} else {
			lines.append("\(indent)let \(property.label): \(typeName) = \(functionName)()")
		}
		return .lowered(.publicMockCall(node))
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
		/// offers one (`ScopeGenerator.MockParameterNode.offersOverrideClosure`).
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
			} else if let overrideClosureType {
				.init(typeSource: "(@Sendable \(overrideClosureType))?", defaultValue: "nil", configuredTypeName: nil)
			} else {
				nil
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
		/// The names a public mock's plan gives its optional builders, by family, which the builders are read under.
		var optionalBuilderNames: [ScopeGenerator.MockRootParameters.SeamMockBuilder.Family: String]?

		/// No call fills a builder.
		static let none = FilledCallBuilders(calls: [], parameters: [], fillPlaceBindings: ScopeGenerator.FillPlaceBindings(bindingsByGenerator: [:]))

		/// The declarations of the builders, one per line at `indent`.
		func parameterLines(indent: String) -> [String] {
			parameters.map { "\(indent)\($0.declaration)" }
		}
	}
}
