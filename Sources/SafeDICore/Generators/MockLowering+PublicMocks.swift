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
	/// guard hashes its empty signature; a mock with a tree is lowered by the walk (`lowerMockRootWithTree(of:context:)`),
	/// which hands its nodes to `publicMockWithTree`.
	func lowerPublicMockRoot(of instantiable: Instantiable, context: MockContext) async -> MockLowering.Result {
		guard let publicMockContext = context.publicMockContext else { return .unsupported(.publicMockRoot) }
		guard propertiesToGenerate.isEmpty,
		      instantiable.dependencies.isEmpty,
		      // D1 lane hook (lane C): the type's own hand-written mock builds it where it has one.
		      let initializer = MockLowering.rootConstructionInitializer(of: instantiable),
		      initializer.arguments.isEmpty
		else {
			return await lowerMockRootWithTree(of: instantiable, context: context)
		}
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
		let construction = MockLowering.rootConstruction(of: instantiable, argumentList: "")
		let returnType = MockLowering.rootReturnType(of: instantiable)
		let code = """
		extension \(typeName) {
		    \(mockAttributesPrefix)public static func mock() -> \(returnType) {
		        \(typeName).\(ReservedName.publicMockFunctionName)()
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    \(mockAttributesPrefix)public static func \(ReservedName.publicMockFunctionName)() -> \(returnType) {
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

	/// The properties of the root's children, `orderedChildren`, that the public mock of `instantiable` promotes for received
	/// dependencies, which it takes as optional parameters (`publicMockPromotedNodes(of:in:)`): every child but the mocked
	/// type's own instantiated properties and a `LazilyInstantiated` of one's instance.
	func publicMockPromotedProperties(of instantiable: Instantiable, among orderedChildren: [OrderedChild]) -> Set<Property> {
		guard instantiable.generateMock == .public else { return [] }
		let ownProperties = Set(instantiable.dependencies.lazy.filter { dependency in
			switch dependency.source {
			case .instantiated:
				true
			case .received, .aliased, .forwarded:
				false
			}
		}.map(\.property))
		return Set(orderedChildren.compactMap { child -> Property? in
			guard case let .property(_, property, _, _, _, _) = child.generator.scopeData, !ownProperties.contains(property) else { return nil }
			let isWrapperOfOwnInstance = property.propertyType.isLazilyInstantiated && property.typeDescription.lazilyInstantiatedInstanceType.map {
				ownProperties.contains(Property(label: property.label, typeDescription: $0))
			} ?? false
			return isWrapperOfOwnInstance ? nil : property
		})
	}

	/// The modules that declare a receiver of each label in this mock root's tree, as `publicMockPlan` admits them: a type of
	/// the tree whose declaration receives a dependency of that label, or aliases one. Walked with a stack, since a tree can
	/// be as deep as the module has types.
	private func publicMockReceiverModules(context: PublicMockContext) -> [String: Set<String?>] {
		var modulesByLabel = [String: Set<String?>]()
		var generatorsToVisit = orderedChildrenComputedAfresh(propertiesGeneratedLater: []).map(\.generator)
		while let generator = generatorsToVisit.popLast() {
			if case let .property(instantiable, _, _, _, _, _) = generator.scopeData {
				let moduleName = context.moduleNameByType[instantiable.concreteInstantiable]
				for dependency in instantiable.dependencies {
					switch dependency.source {
					case .received:
						modulesByLabel[dependency.property.label, default: []].insert(moduleName)
					case let .aliased(fulfillingProperty, _, _):
						modulesByLabel[fulfillingProperty.label, default: []].insert(moduleName)
					case .instantiated, .forwarded:
						break
					}
				}
			}
			generatorsToVisit.append(contentsOf: generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []).map(\.generator))
		}
		return modulesByLabel
	}

	/// The public mock of `instantiable`, whose tree's top-level nodes are `nodes`, in generation order, bound by
	/// `bindingLines`, as `generateMockRootCode` emits it for a public mock: its `public` `SafeDIOverrides` where a node is
	/// built, the `mock()` and `__safeDI_mock` pair of each tier, which takes `signature`'s parameters, the overrides last,
	/// the narrowest tier's binding each node and returning the type built from them, and the guard enum; or the first rule
	/// it meets that the lowering does not lower yet.
	func publicMockWithTree(
		of instantiable: Instantiable,
		signature: MockLowering.RootSignature,
		nodes: [MockLowering.TreeNode],
		bindingLines: [String],
		rootRenames: [String: [TypeDescription: String]],
		unavailableProperties: Set<Property>,
		filledCallBuilders: MockLowering.FilledCallBuilders,
		configurations: [MockLowering.ConfigurationRecord],
		context: MockContext,
	) -> MockLowering.Result {
		guard let publicMockContext = context.publicMockContext else { return .unsupported(.publicMockRoot) }
		// Each dependency the mock promotes to its root is an optional parameter, named as the node's binding, which the walk
		// binds the node from. A name the parameters take apart from the binding's is not lowered yet.
		let promotedProperties = publicMockPromotedProperties(of: instantiable, among: orderedChildrenComputedAfresh(propertiesGeneratedLater: []))
		var promotedNodes = [(property: Property, name: String)]()
		for node in nodes where promotedProperties.contains(node.property) {
			switch node {
			case let .built(builtNode):
				promotedNodes.append((property: node.property, name: builtNode.bindingName))
			case .publicMockCall:
				// A promoted call is bound under its label (`publicMockCallNode`).
				promotedNodes.append((property: node.property, name: node.property.label))
			case .alias, .cycleClosing:
				return .unsupported(.publicMockRoot)
			}
		}
		let indent = Self.standardIndent
		let bodyIndent = "\(indent)\(indent)"
		let typeName = instantiable.concreteInstantiable.asSource
		let mockAttributesPrefix = instantiable.mockAttributes.isEmpty ? "" : "\(instantiable.mockAttributes) "
		// A public mock takes each property received only if available as a parameter, so only the tree's nodes make a
		// `SafeDIOverrides`.
		let hasOverrides = nodes.contains(where: \.isPropertyNode)
		let plan = publicMockPlan(of: instantiable, signature: signature, promotedNodes: promotedNodes, filledCallBuilders: filledCallBuilders, hasOverrides: hasOverrides, context: context, publicMockContext: publicMockContext)
		// The walk read each optional builder under the internal name the plan gives it.
		guard promotedNodes.allSatisfy({ plan.promotedParameterNames[$0.property] == $0.name }), plan.optionalBuilderNames == (filledCallBuilders.optionalBuilderNames ?? [:]) else { return .unsupported(.publicMockRoot) }
		var lines = ["extension \(typeName) {"]
		if !plan.providerDeclarations.isEmpty {
			// The providers of the type's own optional-typed defaults, which the parameters default to.
			if let marker = publicMockContext.unreadTypeComment?.markerLine(namedBy: plan.parameters.filter { $0.defaultKind == .provider }.map(\.type), indent: indent) {
				lines.append(marker)
			}
			lines.append(contentsOf: plan.providerDeclarations)
			lines.append("")
		}
		if !plan.builders.isEmpty {
			// The scope types the builders `mock()` takes are handed, as a seam declares them.
			for declaration in Self.ownScopeTypeDeclarations(
				builders: plan.builders,
				scopeEnums: plan.scopeEnums,
				holes: plan.holes,
				typesDeclaredEscaping: signature.typesDeclaredEscaping,
				unreadTypeComment: publicMockContext.unreadTypeComment,
				namesForwardedTypes: true,
			) {
				lines.append(declaration)
				lines.append("")
			}
		}
		if hasOverrides {
			// The members are in inline order: the build's order without a child that holds a place starting after its
			// siblings (`MockParameterNode.inlineOrderPosition`).
			let inlineOrderedNodes = inlineOrdered(nodes, property: \.property)
			lines.append(MockLowering.publicOverridesStruct(
				members: inlineOrderedNodes.compactMap(MockLowering.PublicConstructionRecord.ChildMember.init(of:)),
				mockedTypeModuleName: instantiable.moduleName,
				context: publicMockContext,
				indent: indent,
			))
			lines.append("")
		}
		var body = plan.defaultResolutions
		body.append(contentsOf: bindingLines)
		// D1 lane hook (lane C): the mocked type's own hand-written mock builds it where it has one, and `mock()` returns what
		// that mock returns (lane D's `MockLowering+HandWrittenMocks.swift`).
		let argumentList = MockLowering.rootConstructionInitializer(of: instantiable).map { initializer in
			MockLowering.rootArgumentList(of: initializer, given: instantiable.dependencies, renames: rootRenames, passingNilTo: unavailableProperties)
		} ?? Instantiable.incorrectlyConfiguredComment
		body.append("\(bodyIndent)return \(MockLowering.rootConstruction(of: instantiable, argumentList: argumentList))")
		lines.append(contentsOf: Self.publicMockTiers(
			of: plan,
			typeName: typeName,
			returnType: MockLowering.rootReturnType(of: instantiable),
			attributesPrefix: mockAttributesPrefix,
			narrowestBody: body,
			unreadTypeComment: publicMockContext.unreadTypeComment,
		))
		lines.append("}")
		lines.append("")
		lines.append(Self.guardEnumDeclaration(extending: typeName, named: plan.guardTypeName))
		let code = lines.joined(separator: "\n")
		let lowered = if let mockConditionalCompilation = context.mockConditionalCompilation {
			"#if \(mockConditionalCompilation)\n\(code)\n#endif"
		} else {
			code
		}
		return .lowered(lowered, configurations: configurations)
	}

	/// The plan of the public mock of `instantiable`, whose root's signature is `signature`, that promotes `promotedNodes`,
	/// under the names given, and takes the builders its calls fill (`filledCallBuilders`) optional, as `publicMockPlan`
	/// plans it from the emitter's parameter tree.
	private func publicMockPlan(
		of instantiable: Instantiable,
		signature: MockLowering.RootSignature,
		promotedNodes: [(property: Property, name: String)],
		filledCallBuilders: MockLowering.FilledCallBuilders,
		hasOverrides: Bool,
		context: MockContext,
		publicMockContext: PublicMockContext,
	) -> PublicMockPlan {
		// Each forwarded parameter defaults to the default the initializer gives the parameter of its label, else to the
		// hand-written mock its type has, as the signature's does.
		let forwardedDependencies = instantiable.dependencies.filter { $0.source == .forwarded }.sorted { $0.property < $1.property }
		var forwardedDefaults = [String: ForwardedParameterDefault]()
		for dependency in forwardedDependencies {
			let label = dependency.property.label
			if let constructionDefault = MockLowering.rootConstructionInitializer(of: instantiable)?.arguments.first(where: { $0.innerLabel == label })?.defaultValueExpression {
				forwardedDefaults[label] = .constructionDefault(constructionDefault)
			} else if let mockDefault = context.flatParameterMockDefaults[dependency.property.typeDescription] {
				forwardedDefaults[label] = .handWrittenMock(mockDefault)
			}
		}
		let rootDefaultParameters = signature.rootDefaultParameters.compactMap { parameter in
			parameter.defaultExpression.map { defaultExpression in
				MockRootParameters.RootDefaultParameter(
					label: parameter.name,
					typeSource: parameter.typeSource ?? parameter.property.typeDescription.asSource,
					defaultExpression: defaultExpression,
					typeDescription: parameter.property.typeDescription.strippingEscaping,
				)
			}
		}
		// D1 lane hook (lane C): a value the tree receives lazily is taken as the wrapper it receives, keyed by its instance,
		// whose hand-written mock the wrapper defaults to (`ScopeGenerator.publicMockWrapperParameters`).
		var flatReceivedParameterMockDefaults = [Property: FlatParameterMockDefault]()
		var flatReceivedParameters = [(property: Property, name: String)]()
		var wrapperParameterByInstance = [Property: Property]()
		for parameter in signature.flatReceivedParameters {
			var property = parameter.property
			if property.typeDescription.lazilyInstantiatedInstanceType != nil {
				let instance = property.asValidatedForDependencyCycles
				wrapperParameterByInstance[instance] = property
				property = instance
			}
			flatReceivedParameters.append((property: property, name: parameter.name))
			flatReceivedParameterMockDefaults[property] = context.flatParameterMockDefaults[property.typeDescription]
		}
		return Self.publicMockPlan(
			of: instantiable,
			forwardedDependencies: forwardedDependencies,
			forwardedDefaults: forwardedDefaults,
			rootDefaultParameters: rootDefaultParameters,
			flatReceivedParameters: flatReceivedParameters,
			flatReceivedParameterMockDefaults: flatReceivedParameterMockDefaults,
			flatUncoveredParameters: signature.uncoveredRootParameters,
			promotedNodes: promotedNodes,
			onlyIfAvailableOverrides: signature.onlyIfAvailableOverrides,
			wrapperParameterByInstance: wrapperParameterByInstance,
			parameterTree: [],
			builders: mockBuilders,
			hasOverrides: hasOverrides,
			typesDeclaredEscaping: signature.typesDeclaredEscaping,
			receiverModulesByLabel: publicMockReceiverModules(context: publicMockContext),
			filledFamilies: filledCallBuilders.families.isEmpty ? nil : (families: filledCallBuilders.families, namesInBody: publicMockNamesInBody(namesFillsDeclare: filledCallBuilders.namesFillsDeclare)),
			context: publicMockContext,
		)
	}

	/// The names of the builders a public mock takes optional, by family, which the walk reads them under: the internal names
	/// its plan gives them, computed before the walk names the nodes it promotes, from their labels, which
	/// `publicMockWithTree` checks the plan from the walk's names gives too. `nil` where its calls fill no builder.
	func publicMockOptionalBuilderNames(
		of instantiable: Instantiable,
		signature: MockLowering.RootSignature,
		filledCallBuilders: MockLowering.FilledCallBuilders,
		context: MockContext,
	) -> [MockRootParameters.SeamMockBuilder.Family: String]? {
		guard instantiable.generateMock == .public, let publicMockContext = context.publicMockContext, !filledCallBuilders.families.isEmpty else { return nil }
		let promotedProperties = publicMockPromotedProperties(of: instantiable, among: orderedChildrenComputedAfresh(propertiesGeneratedLater: []))
		let plan = publicMockPlan(
			of: instantiable,
			signature: signature,
			promotedNodes: propertiesToGenerate.compactMap(\.property).filter(promotedProperties.contains).map { (property: $0, name: $0.label) },
			filledCallBuilders: filledCallBuilders,
			hasOverrides: !propertiesToGenerate.isEmpty,
			context: context,
			publicMockContext: publicMockContext,
		)
		return plan.optionalBuilderNames
	}

	/// The names the narrowest tier's body of this root's public mock declares beside its parameters, apart from which its
	/// optional builders are named: each property's builder function and each dependency's label of every type its tree
	/// builds, and the labels its calls' fills declare (`namesFillsDeclare`), as `publicMockOptionalBuilders` reads them
	/// from a parameter tree. Walked with a stack, since a tree can be as deep as the module has types.
	private func publicMockNamesInBody(namesFillsDeclare: Set<String>) -> Set<String> {
		var namesInBody = namesFillsDeclare
		var generatorsToVisit = orderedChildrenComputedAfresh(propertiesGeneratedLater: []).map(\.generator)
		while let generator = generatorsToVisit.popLast() {
			guard case let .property(instantiable, property, _, _, _, _) = generator.scopeData else { continue }
			namesInBody.insert(Self.functionName(toBuildPropertyNamed: property.label))
			namesInBody.formUnion(instantiable.dependencies.map(\.property.label))
			generatorsToVisit.append(contentsOf: generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []).map(\.generator))
		}
		return namesInBody
	}
}

extension PublicMockPlan {
	/// The internal name of each builder the mock takes optional, by family.
	var optionalBuilderNames: [ScopeGenerator.MockRootParameters.SeamMockBuilder.Family: String] {
		var names = [ScopeGenerator.MockRootParameters.SeamMockBuilder.Family: String]()
		for parameter in parameters {
			guard let family = parameter.optionalBuilderFamily, let internalName = parameter.internalName else { continue }
			names[family] = internalName
		}
		return names
	}
}

extension ScopeGenerator {
	/// The elements in inline order: the build's order without a child that holds a place starting after its siblings
	/// (`MockParameterNode.inlineOrderPosition`), an element of no child keeping its place after them.
	nonisolated func inlineOrdered<Element>(_ elements: [Element], property: (Element) -> Property) -> [Element] {
		let children = propertiesToGenerate
		var inlinePositionByProperty = [Property: Int]()
		for (position, index) in computeOrderedPropertyToGenerateIndices(startingCarriersLast: false).enumerated() {
			guard let property = children[index].property, inlinePositionByProperty[property] == nil else { continue }
			inlinePositionByProperty[property] = position
		}
		return elements.enumerated().sorted { lhs, rhs in
			(inlinePositionByProperty[property(lhs.element)] ?? Int.max, lhs.offset) < (inlinePositionByProperty[property(rhs.element)] ?? Int.max, rhs.offset)
		}.map(\.element)
	}
}

extension MockLowering {
	/// The construction a public mock's configured `node`, whose children are `children`, builds its type with, which its
	/// configuration record carries, its children in the inline order of `generator`, the node's, as the configuration's
	/// members are.
	static func publicConstructionRecord(of node: ConstantNode, children: [TreeNode], orderedBy generator: ScopeGenerator) -> PublicConstructionRecord? {
		PublicConstructionRecord(of: node, children: generator.inlineOrdered(children, property: \.property))
	}
}

extension MockLowering.ConstantNode {
	/// The lines that end a public mock's configured node's builder function, which returns a call of its type's
	/// construction function handed the builder its override at `overridePath` reads, and bind the node; or the first rule
	/// they meet that the lowering does not lower yet.
	func publicBuilderFunctionEndLines(children: [MockLowering.TreeNode], overrideRead overridePath: String?, indent: String) -> MockLowering.Lowering<[String]> {
		// The node passes its construction function every argument the function takes.
		let record = MockLowering.PublicConstructionRecord(of: self, children: children)
		guard record.arguments.count == arguments.count else { return .unsupported(.defaultValuedParameter) }
		let bodyIndent = "\(indent)\(ScopeGenerator.standardIndent)"
		// D1 lane hook (lane C): an instantiator's builder function writes `return` only before statements of its own, as
		// `builderFunctionEndLines` says, its defaults' reads included.
		let returnPrefix = hasChildren || !receiverBindings.isEmpty || !sendableAutoclosureBindingNames.isEmpty || !isWrapped ? "return " : ""
		let erasedTo: TypeDescription? = if isErased {
			isWrapped ? property.typeDescription.asInstantiatedTypeSpelledAsDeclared : property.typeDescription
		} else {
			nil
		}
		let call = MockLowering.publicConstructionCall(of: record, arguments: arguments.map(\.value), builderRead: overridePath, erasedTo: erasedTo)
		var lines = ["\(bodyIndent)\(returnPrefix)\(call)"]
		lines.append("\(indent)}")
		lines.append(contentsOf: promotedBindingLines(indent: indent))
		return .lowered(lines)
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
		indent: String,
		lines: inout [String],
	) async -> MockLowering.Lowering<MockLowering.TreeNode> {
		switch generator.scopeData {
		case let .hole(property, erasedToConcreteExistential, site):
			guard let site else { return .unsupported(.holeSite) }
			guard !rootLabels.contains(property.label), labels.insert(property.label).inserted else { return .unsupported(.siblingLabelCollision) }
			// The site calls its place's member on the struct its route leads to, handed the values in scope there, as the
			// emitter's `MockAliasNode.holeSite` does.
			lines.append(GeneratedCodeText.indentingNonEmptyLines(
				of: ScopeGenerator.buildSiteCode(
					of: property,
					at: site,
					functionName: nil,
					readingInstancesOf: generator.mockLoweringCallSiteLazilyInstantiatedInstanceProperties,
				),
				by: indent,
			))
			// The site binds its property from the builder, as an alias binds its own: no override reads it.
			return .lowered(.alias(MockLowering.AliasBinding(
				property: property,
				bindingName: property.label,
				fulfillingProperty: Property(label: site.builderLabel, typeDescription: site.builtType),
				fulfillingName: site.builderLabel,
				isErased: erasedToConcreteExistential,
				isOnlyIfAvailable: false,
				isBoundToNil: false,
				declarationReference: nil,
			)))
		case .root, .fill, .property, .alias:
			return .unsupported(.fill)
		}
	}
}
