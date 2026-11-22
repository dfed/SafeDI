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
	/// The public mock of `instantiable`, this root's mocked type, or the first rule it meets that the lowering does not lower
	/// yet. A mock that takes no parameter and builds nothing but the type is the `mock()` and `__safeDI_mock()` pair, whose
	/// guard hashes its empty signature.
	func lowerPublicMockRoot(of instantiable: Instantiable, context: MockContext) -> MockLowering.Result {
		guard let publicMockContext = context.publicMockContext,
		      propertiesToGenerate.isEmpty,
		      instantiable.dependencies.isEmpty,
		      instantiable.mockInitializer == nil,
		      let initializer = instantiable.initializer,
		      initializer.arguments.isEmpty
		else { return .unsupported(.publicMockRoot) }
		let plan = Self.publicMockPlan(
			of: instantiable,
			forwardedDependencies: [],
			forwardedDefaults: [:],
			rootDefaultParameters: [],
			flatReceivedParameters: [],
			flatReceivedParameterMockDefaults: [:],
			flatUncoveredParameters: [],
			promotedNodes: [],
			onlyIfAvailableOverrides: [],
			wrapperParameterByInstance: [:],
			parameterTree: [],
			builders: nil,
			hasOverrides: false,
			typesDeclaredEscaping: [],
			context: publicMockContext,
		)
		let typeName = instantiable.concreteInstantiable.asSource
		let mockAttributesPrefix = instantiable.mockAttributes.isEmpty ? "" : "\(instantiable.mockAttributes) "
		let construction = if instantiable.declarationType.isExtension {
			"\(typeName).\(InstantiableVisitor.instantiateMethodName)()"
		} else {
			"\(typeName)()"
		}
		let code = """
		extension \(typeName) {
		    \(mockAttributesPrefix)public static func mock() -> \(typeName) {
		        \(typeName).\(ReservedName.publicMockFunctionName)()
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    \(mockAttributesPrefix)public static func \(ReservedName.publicMockFunctionName)() -> \(typeName) {
		        \(construction)
		    }
		}

		\(Self.guardEnumDeclaration(extending: typeName, named: plan.guardTypeName))
		"""
		return if let mockConditionalCompilation = context.mockConditionalCompilation {
			.lowered("#if \(mockConditionalCompilation)\n\(code)\n#endif")
		} else {
			.lowered(code)
		}
	}
}

extension ScopeGenerator {
	/// The builders `mock()` takes optional for the places its calls of other modules' public mocks fill, from the root's
	/// children, `orderedChildren`, in generation order, as `seamMockBuilders` computes them for a mock whose calls are made
	/// at the root's level, fill every place of each builder they take, and hold no place or call in their fills; or the
	/// first rule the calls meet. Each family of hole type is one builder, labeled from its stem
	/// (`stemsOfOptionalBuilders`) apart from `safeDIOverrides`, in label order.
	func filledCallBuilders(of orderedChildren: [OrderedChild], context: MockContext) -> MockLowering.Lowering<MockLowering.FilledCallBuilders> {
		var calls = [MockLowering.FilledCallBuilders.Call]()
		var filledCalls = [FilledCall]()
		var namesFillsDeclare = Set<String>()
		// What the mock's root level declares, which a fill reading a value of the caller's scope reads.
		var rootLevelProperties = Set<Property>()
		for child in orderedChildren {
			if let property = child.generator.property {
				rootLevelProperties.insert(property)
			}
		}
		for child in orderedChildren where child.generator.publicMockCall != nil && child.generator.fillsABuilder {
			let generator = child.generator
			guard let publicMockCall = generator.publicMockCall,
			      publicMockCall.passedUpBuilders.isEmpty,
			      !generator.buildsInSendableFunction,
			      !generator.declaresCycleParameters,
			      generator.reboundProperties.isEmpty
			else { return .unsupported(.fill) }
			// A fill that reads a value of the caller's scope reads what the mock binds or offers for it.
			for fill in generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: child.propertiesGeneratedLater).map(\.generator) {
				guard case .fill = fill.scopeData,
				      fill.receivedProperties.allSatisfy({ rootLevelProperties.contains($0) || rootLevelProperties.contains($0.asUnwrappedProperty) })
				else { return .unsupported(.fill) }
			}
			// A place inside a fill takes a required builder, which is not lowered yet. A call inside a fill is generated with the
			// fill, reading the builders `mock()` takes optional for the places it fills as the call does.
			let fillPlaces = generator.fillPlaces(insideSendableFunction: false)
			guard fillPlaces.places.isEmpty else { return .unsupported(.fill) }
			let filledCall = FilledCall(generator: generator, isInsideSendableFunction: false, enclosingCalls: [])
			guard filledCall.filledBuilders.count == publicMockCall.builders.count else { return .unsupported(.fill) }
			for callInsideFill in fillPlaces.calls {
				guard let calledMock = callInsideFill.generator.publicMockCall,
				      calledMock.passedUpBuilders.isEmpty,
				      callInsideFill.filledBuilders.count + callInsideFill.reenteredBuilders.count == calledMock.builders.count
				else { return .unsupported(.fill) }
			}
			namesFillsDeclare.formUnion(fillPlaces.declaredLabels)
			filledCalls.append(filledCall)
			filledCalls.append(contentsOf: fillPlaces.calls)
			calls.append(.init(generator: generator, propertiesGeneratedLater: child.propertiesGeneratedLater))
		}
		guard !calls.isEmpty else { return .lowered(.none) }
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
			generatorsToVisit.append(contentsOf: generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []).map(\.generator))
		}
		let families = Self.filledFamilies(of: filledCalls)
		let stems = Self.stemsOfOptionalBuilders(
			of: families.map { ($0.family.holeType, $0.receivedProperty) },
			besideOwnHoleTypes: [],
			passedUpHoleTypes: [],
			requiredStems: [:],
		)
		var labels = GeneratedNameAllocator(reserving: [ReservedName.mockOverridesParameterName])
		var parameters = [(label: String, declaration: String)]()
		var holeBuildersByCall = [ObjectIdentifier: [String: FillPlaceBindings.HoleBuilder]]()
		var buildersByFamily = [MockRootParameters.SeamMockBuilder.Family: FillPlaceBindings.HoleBuilder]()
		for filled in families {
			let stem = stems[filled.family.holeType, default: ""]
			let label = labels.claim(filled.family.isSendable ? DependencyTreeGenerator.sendableBuilderLabel(ofStem: stem) : DependencyTreeGenerator.plainBuilderLabel(ofStem: stem))
			// A builder whose label a name of the tree or of the fills has is called by a name apart, which `mock()` binds.
			guard !namesFillsDeclare.contains(label), !namesBoundInTheTree.contains(label) else { return .unsupported(.fill) }
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
		return .lowered(MockLowering.FilledCallBuilders(
			calls: calls,
			parameters: parameters,
			fillPlaceBindings: FillPlaceBindings(bindingsByGenerator: [:], holeBuildersByCall: holeBuildersByCall, holeBuildersByInlinePlace: holeBuildersByInlinePlaceInFills),
		))
	}

	/// Whether the tree of `orderedChildren`, outside the fills of its calls, builds inline a place of another module's public
	/// mock of one of `holeTypes`, a hole of that mock, which reads the builder `mock()` takes for its hole type and family, as
	/// `holeBuildersByInlinePlace(in:buildersByFamily:foreignPublicMocks:)` finds them. Walked with a stack, since a tree can be
	/// as deep as the module has types.
	private func treeBuildsInlinePlaceReadingBuilder(
		of orderedChildren: [OrderedChild],
		holeTypes: Set<SeamSignature.HoleType>,
		foreignPublicMocks: [TypeDescription: SeamResolution.ForeignPublicMock],
	) throws -> Bool {
		guard !holeTypes.isEmpty, !foreignPublicMocks.isEmpty else { return false }
		// Each scope with the public mock built inline nearest above it, and the type its declaration instantiates, which a
		// `fulfilledByType:` names.
		var generatorsToVisit = orderedChildren.map { (generator: $0.generator, publicMockBuiltInline: SeamResolution.ForeignPublicMock?.none, instantiatedType: TypeDescription?.none) }
		while let (generator, publicMockBuiltInline, declaredInstantiatedType) = generatorsToVisit.popLast() {
			// A scope that closes a cycle builds nothing, and a call's places are the call's.
			guard case let .property(instantiable, property, _, _, false, _) = generator.scopeData, generator.publicMockCall == nil else { continue }
			let instantiatedType = declaredInstantiatedType ?? property.typeDescription.asInstantiatedType
			if let publicMockBuiltInline,
			   try publicMockBuiltInline.visibleDeclarations().instantiables[instantiatedType] == nil,
			   holeTypes.contains(SeamSignature.HoleType(instantiatedType: instantiatedType.spelledCanonically, builtType: property.typeDescription.builtTypeOfWrapper.spelledCanonically))
			{
				return true
			}
			let enclosingPublicMock = foreignPublicMocks[instantiable.concreteInstantiable] ?? publicMockBuiltInline
			let instantiatedTypes = Dictionary(instantiable.dependencies.map { ($0.property, $0.asInstantiatedType) }, uniquingKeysWith: { first, _ in first })
			generatorsToVisit += generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []).map { child in
				(child.generator, enclosingPublicMock, child.generator.property.flatMap { instantiatedTypes[$0] })
			}
		}
		return false
	}
}

/// Stage D1's lowering of lane C's family: public mock roots, the sites of their holes, the payloads and members bound before
/// a node, the fills of their calls, and the calls of other modules' public mocks.
extension MockLowering.Walk {
	/// The node of `generator`, a site of a hole or a fill, whose statements are appended to `lines`, or the first rule it
	/// meets.
	mutating func placeOrFillNode(
		of generator: ScopeGenerator,
		inScope _: Set<Property>,
		path _: String,
		indent _: String,
		lines _: inout [String],
	) async -> MockLowering.Lowering<MockLowering.TreeNode> {
		switch generator.scopeData {
		case .hole:
			.unsupported(.holeSite)
		case .root, .fill, .property, .alias:
			.unsupported(.fill)
		}
	}

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
		// A call nested in a type's builder function is configured by that type's configuration, which a `@Sendable` builder
		// function reads as a closure.
		guard !generator.buildsInSendableFunction,
		      !isPropertyCycle,
		      !erasedToConcreteExistential,
		      property.propertyType.isConstant || property.propertyType == .instantiator && forwardedProperties.isEmpty,
		      property.typeDescription.asInstantiatedType == instantiable.concreteInstantiable
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
		let node = MockLowering.PublicMockCallNode(
			property: property,
			calledType: instantiable.concreteInstantiable,
			call: publicMockCall,
			overrideClosureType: overrideBuilders.map { _ in
				let parameterTypes = initializer.arguments.map { argument in
					(argument.typeDescription.strippingEscaping.autoclosureValueType ?? argument.typeDescription)
						.asFunctionParameter(amongTypesDeclaredEscaping: publicMockCall.typesDeclaredEscaping)
						.asSource
				}
				return "(\(parameterTypes.joined(separator: ", "))) -> \(property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource)"
			},
		)
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
		let structValuesByLabel = filledCall == nil ? [:] : generator.publicMockBuilderStructValuesByLabel
		let lazilyInstantiatedInstances = generator.mockLoweringLazilyInstantiatedInstanceProperties
		var arguments = [String]()
		// What the override closure is handed for each argument: a builder as `publicMockOverrideBuilders` says, which reads
		// the values the call passes, and any other argument as the call passes it.
		var overrideArguments = [String]()
		var argumentByLabel = [String: String]()
		func labeled(_ value: String, as argument: Initializer.Argument) -> String {
			argument.label == "_" ? value : "\(argument.label.spelledAsArgumentLabel): \(value)"
		}
		for argument in initializer.arguments {
			if let builderStruct = structValuesByLabel[argument.innerLabel] {
				let fillsStruct = builderStruct.replacingOccurrences(of: "\n\(ScopeGenerator.standardIndent)", with: "\n\(innerIndent)")
				arguments.append(labeled(holeBuilders[argument.innerLabel]?.structValue(fillsStruct: fillsStruct) ?? fillsStruct, as: argument))
				if let overrideBuilders {
					// A builder an internal mock passes up whole is not lowered yet.
					guard let overrideBuilder = overrideBuilders[argument.innerLabel], case .fill = overrideBuilder else { return .unsupported(.publicMockCall) }
					overrideArguments.append(argument.innerLabel)
				}
			} else {
				// A value the call passes is the root level's binding of its label, which an optional parameter takes as it is.
				guard let dependency = instantiable.dependencies.first(where: { $0.property.label == argument.innerLabel }),
				      dependency.source != .forwarded,
				      !lazilyInstantiatedInstances.contains(dependency.property),
				      !generator.unavailableOptionalProperties.contains(dependency.property),
				      scope.contains(dependency.property) || dependency.property.typeDescription.isOptional && scope.contains(dependency.property.asUnwrappedProperty)
				else { return .unsupported(.publicMockCall) }
				arguments.append(labeled(dependency.property.label, as: argument))
				overrideArguments.append(dependency.property.label)
				argumentByLabel[argument.innerLabel] = dependency.property.label
			}
		}
		if publicMockCall.takesOverrides {
			arguments.append("\(ReservedName.mockOverridesParameterName): \(nodePath)")
		}
		let defaultCall = "\(instantiable.concreteInstantiable.asSource).\(publicMockCall.functionName)(\(arguments.joined(separator: ", ")))"
		let call: String
		if let overrideBuilders {
			// A builder's slot holds its label until here, so that each builder reads every value the call passes.
			let handed = zip(initializer.arguments, overrideArguments).map { argument, value in
				overrideBuilders[argument.innerLabel]?.expression(argumentByLabel: argumentByLabel, holeBuilder: holeBuilders[argument.innerLabel]) ?? value
			}
			let overrideName = ReservedName.configurationBuilderPropertyName
			call = "if let \(overrideName) = \(nodePath) { \(overrideName)(\(handed.joined(separator: ", "))) } else { \(defaultCall) }"
		} else {
			call = defaultCall
		}
		let typeName = property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource
		let functionName = ScopeGenerator.functionName(toBuildPropertyNamed: property.label)
		// A call held in an instantiator is made in the builder function the instantiator holds.
		let isInstantiator = !property.propertyType.isConstant
		guard let filledCall else {
			lines.append("\(indent)\(publicMockCall.guardLine(for: instantiable.concreteInstantiable))")
			if isInstantiator {
				lines.append("\(indent)func \(functionName)() -> \(typeName) {")
				lines.append("\(indent)\(ScopeGenerator.standardIndent)\(call)")
				lines.append("\(indent)}")
				lines.append("\(indent)let \(property.label) = \(property.typeDescription.asSource)(\(functionName))")
			} else {
				lines.append("\(indent)let \(property.label) = \(call)")
			}
			return .lowered(.publicMockCall(node))
		}
		let fillCode: String
		do {
			fillCode = try await generator.mockLoweringFillCode(propertiesGeneratedLater: filledCall.propertiesGeneratedLater, fillPlaceBindings: filledCallBuilders.fillPlaceBindings).joined(separator: "\n")
		} catch {
			return .unsupported(.fill)
		}
		lines.append("\(indent)func \(functionName)() -> \(typeName) {")
		for line in fillCode.split(separator: "\n", omittingEmptySubsequences: false) where !fillCode.isEmpty {
			lines.append(line.isEmpty ? "" : "\(innerIndent)\(line)")
		}
		lines.append("\(innerIndent)\(publicMockCall.guardLine(for: instantiable.concreteInstantiable))")
		lines.append("\(innerIndent)return \(call)")
		lines.append("\(indent)}")
		lines.append(isInstantiator ? "\(indent)let \(property.label) = \(property.typeDescription.asSource)(\(functionName))" : "\(indent)let \(property.label): \(typeName) = \(functionName)()")
		return .lowered(.publicMockCall(node))
	}
}

extension MockLowering {
	/// A node of a mock's tree that calls another module's public mock, which builds the node's whole tree.
	struct PublicMockCallNode {
		let property: Property
		/// The type whose public mock the node calls.
		let calledType: TypeDescription
		let call: PublicMockCall
		/// For a call of a mock that takes no overrides, the type of the closure that builds the called type, where the call
		/// offers one (`ScopeGenerator.MockParameterNode.offersOverrideClosure`).
		let overrideClosureType: String?

		/// The member of the calling mock's overrides that configures the call: the called mock's own `SafeDIOverrides`, or,
		/// for a mock that takes none, the closure that builds the called type, where the call offers one.
		var overridesField: OverridesField? {
			if call.takesOverrides {
				OverridesField(
					name: property.label,
					typeSource: "\(calledType.asSource).\(ReservedName.mockOverridesTypeName)",
					defaultValue: ".init()",
					sendability: .never,
				)
			} else if let overrideClosureType {
				OverridesField(name: property.label, typeSource: "(\(overrideClosureType))?", defaultValue: "nil", sendability: .never)
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
		let fillPlaceBindings: ScopeGenerator.FillPlaceBindings
		/// The name `mock()` binds each builder a call passes up under, by the property the call's leaf receives it as.
		var passedUpBuilderNames: [Property: String] = [:]

		/// No call fills a builder.
		static let none = FilledCallBuilders(calls: [], parameters: [], fillPlaceBindings: ScopeGenerator.FillPlaceBindings(bindingsByGenerator: [:]))

		/// The lines that bind each builder a call passes up apart from its label, before anything else `mock()` binds.
		func leadingBindingLines(indent: String) -> [String] {
			passedUpBuilderNames.sorted { $0.key < $1.key }.map { "\(indent)let \($0.value) = \($0.key.label)" }
		}

		/// The declarations of the builders, one per line at `indent`.
		func parameterLines(indent: String) -> [String] {
			parameters.map { "\(indent)\($0.declaration)" }
		}
	}
}
