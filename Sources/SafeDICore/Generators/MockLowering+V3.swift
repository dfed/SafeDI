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

/// `.v3Unstable`'s mock API (`SafeDIAPIVersion`): the mocked type is configured like any type its mock builds, by a
/// `SafeDIOverrides` that holds a field for each child it builds, its initializer's defaults and its builder; `mock()`
/// takes what nothing in the tree builds, a builder for each `@Instantiated` dependency it cannot build, and a
/// `SafeDIReceived` (or, for a type with nothing to configure, an optional instance) for each received dependency it can.
extension ScopeGenerator {
	/// The mock of `instantiable` in `.v3Unstable`'s API, whose tree's top-level nodes are `nodes`, in inline order
	/// (`MockParameterNode.inlineOrderPosition`), which its configuration and `mock()` keep, bound by `bindingLines`,
	/// with the configuration of the mocked type appended to `walk`'s records.
	static func v3MockWithTree(
		of instantiable: Instantiable,
		signature: MockLowering.RootSignature,
		nodes: [MockLowering.TreeNode],
		bindingLines: [String],
		builders: [(label: String, declaration: String)],
		rootRenames: [String: [TypeDescription: String]],
		unavailableProperties: Set<Property>,
		instancesReadByValue: Set<Property>,
		walk: inout MockLowering.Walk,
		context: MockContext,
	) -> MockLowering.Result {
		let indent = standardIndent
		let bodyIndent = "\(indent)\(indent)"
		let typeName = instantiable.concreteInstantiable.asSource
		let mockAttributesPrefix = instantiable.mockAttributes.isEmpty ? "" : "\(instantiable.mockAttributes) "
		let usesMockInitializer = instantiable.mockInitializer != nil
		let overrides = ReservedName.mockOverridesParameterName

		// The mocked type's configuration: a field for each child it builds that the mock does not promote, its defaults,
		// and its builder.
		var rootRecord = MockLowering.ConfigurationRecord(
			concreteType: instantiable.concreteInstantiable,
			usesMockInitializer: usesMockInitializer,
			childFieldSources: MockLowering.ConfigurationRecord.childFieldSources(of: nodes.filter { node in
				if case let .built(builtNode) = node {
					builtNode.promotedParameterName == nil
				} else {
					true
				}
			}),
			builderParameters: MockLowering.BuilderParameters(of: instantiable, usesMockInitializer: usesMockInitializer),
			defaultFields: walk.configurationDefaultFields(of: instantiable, usesMockInitializer: usesMockInitializer),
		)
		rootRecord.isV3 = true
		rootRecord.v3ConfigurationNames = context.v3ConfigurationNames

		// The parameters, in order: forwarded, received that nothing builds (with the builders calls pass up), received only
		// if available, a builder per dependency the mock cannot build, then received that the mock builds.
		let beforeUncovered = signature.onlyIfAvailableOverrides.map { override in
			"\(bodyIndent)\(override.name): \(override.typeDescription.asSource) = nil"
		}
		var afterUncovered = [String]()
		for node in nodes {
			switch node {
			case let .built(node):
				guard let parameterName = node.promotedParameterName else { continue }
				let valueType = MockLowering.v3ReceivedValueType(of: node.property)
				if node.hasConfiguration {
					afterUncovered.append("\(bodyIndent)\(parameterName): SafeDIReceived<\(valueType.asSource), \(context.v3ConfigurationNames.typeName(of: node.instantiable.concreteInstantiable))> = .built(.init())")
				} else {
					afterUncovered.append("\(bodyIndent)\(parameterName): \(TypeDescription.optional(valueType).asSource) = nil")
				}
			case let .publicMockCall(node):
				// A received value another module's public mock builds is passed as an optional instance; the call is configured
				// by the root's field for it.
				guard let parameterName = node.v3PromotedParameterName else { continue }
				afterUncovered.append("\(bodyIndent)\(parameterName): \(TypeDescription.optional(node.property.typeDescription).asSource) = nil")
			case .alias, .cycleClosing:
				continue
			}
		}
		var parameterLines = signature.parameterLines(indent: bodyIndent, builders: builders, includingRootDefaults: false, beforeUncovered: beforeUncovered)
		parameterLines.append(contentsOf: afterUncovered)
		parameterLines.append("\(bodyIndent)\(overrides): \(ReservedName.mockOverridesTypeName) = .init()")

		var lines = ["extension \(typeName) {"]
		lines.append("\(indent)\(mockAttributesPrefix)static func mock(")
		lines.append(parameterLines.joined(separator: ",\n"))
		lines.append("\(indent)) -> \(MockLowering.rootReturnType(of: instantiable)) {")
		lines.append(contentsOf: bindingLines)
		if let initializer = MockLowering.rootConstructionInitializer(of: instantiable) {
			let dependencyArguments = MockLowering.rootDependencyArguments(of: initializer, given: instantiable.dependencies, renames: rootRenames, passingNilTo: unavailableProperties, readingInstancesOf: instancesReadByValue)
			// A construction that passes a default it reads from the overrides to a `@Sendable` `@autoclosure` reads each into a
			// local first, as a node's builder function does (`constructionPassesConfigurationReadToSendableAutoclosure`): the
			// overrides are not `Sendable`, so the autoclosure cannot capture them.
			let readsOverridesIntoLocals = walk.constructionPassesConfigurationReadToSendableAutoclosure(of: instantiable, usesMockInitializer: usesMockInitializer)
			if readsOverridesIntoLocals {
				walk.sendableOverrideExtractor = SendableOverrideExtractor(
					functionName: ReservedName.publicMockFunctionName,
					names: walk.rootLevelNames ?? GeneratedNameAllocator(reserving: Set(signature.sendableAutoclosureBindings.values.map(\.localName))),
				)
			}
			let arguments = walk.constructionArguments(of: initializer, given: instantiable, usesMockInitializer: usesMockInitializer, dependencyArguments: dependencyArguments, nodePath: overrides, overrideReachable: true)
			if let extractor = walk.sendableOverrideExtractor {
				lines.append(contentsOf: extractor.extractions.map { "\(bodyIndent)let \($0.localName) = \($0.expression)" })
				walk.sendableOverrideExtractor = nil
			}
			let argumentList = arguments.map { $0.label == "_" ? $0.value : "\($0.label): \($0.value)" }.joined(separator: ", ")
			let construction = MockLowering.rootConstruction(of: instantiable, argumentList: argumentList)
			let builder = ReservedName.configurationBuilderPropertyName
			lines.append("\(bodyIndent)return if let \(builder) = \(overrides).\(builder) { \(builder)(\(arguments.map(\.value).joined(separator: ", "))) } else { \(construction) }")
		} else {
			lines.append("\(bodyIndent)return \(MockLowering.rootConstruction(of: instantiable, argumentList: Instantiable.incorrectlyConfiguredComment))")
		}
		lines.append("\(indent)}")
		lines.append("}")
		if let mockConditionalCompilation = context.mockConditionalCompilation {
			lines.insert("#if \(mockConditionalCompilation)", at: 0)
			lines.append("#endif")
		}
		return MockLowering.Result(code: MockLowering.joinedLines(lines), configurations: walk.configurationRecords + [rootRecord])
	}
}

extension MockLowering.ConfigurationRecord {
	/// The sources of the fields of a configuration for `children`, the nodes its type builds.
	static func childFieldSources(of children: [MockLowering.TreeNode]) -> [ChildFieldSource] {
		// A configuration `@Sendable`-typed takes each child's override `@Sendable` (`ScopeGenerator.configurationField`).
		children.compactMap { child in
			switch child {
			case let .built(childNode):
				return .built(bindingName: childNode.fieldName, hasConfiguration: childNode.hasConfiguration, requiresSendable: childNode.requiresSendable, concreteType: childNode.instantiable.concreteInstantiable, builderParameters: MockLowering.BuilderParameters(of: childNode.instantiable, usesMockInitializer: childNode.usesMockInitializer), propertyType: childNode.property.typeDescription)
			case .alias:
				return nil
			// A node that closes a cycle is configured by the configuration of the type it repeats.
			case let .cycleClosing(_, bindingName, concreteType):
				let field = MockLowering.cycleClosingOverridesField(boundAs: bindingName, concreteType: concreteType)
				return .closingCycle(ChildField(name: field.name, typeSource: field.typeSource, defaultValue: field.defaultValue, sendableForm: .init(typeSource: field.typeSource, defaultValue: field.defaultValue, configuredTypeName: concreteType.asSource)), concreteType: concreteType)
			// A call's member in a configuration `@Sendable`-typed is a `@Sendable` closure
			// (`publicMockOverridesMember(sendable:)`).
			case let .publicMockCall(call):
				return call.overridesField.map { field in
					.spelled(ChildField(name: field.name, typeSource: field.typeSource, defaultValue: field.defaultValue, sendableForm: call.sendableConfigurationFieldForm))
				}
			}
		}
	}
}

// MARK: - Cycles

extension MockLowering {
	/// A configuration in lexical scope where the walk is, in `.v3Unstable`: the expression that reads it, and whether that
	/// expression is optional (a builder function's parameter for the nearest configuration of a type above its pass).
	struct V3ConfigurationInScope {
		let expression: String
		let isOptional: Bool
		/// Whether the node the configuration configures is built with its type's hand-written mock, or `nil` for a cycle
		/// target's nearest configuration, which the target's caller hands it.
		let usesMockInitializer: Bool?
	}

	/// A builder function a cycle closes on in `.v3Unstable`: each call hands it the configuration it builds from, and the
	/// nearest configuration of each other configured type its subtree builds, which a later pass's nodes of that type
	/// inherit.
	struct V3CycleTarget {
		/// The configured types of the function's subtree other than its own, by their spelling, in that order.
		let nearestTypes: [TypeDescription]
	}
}

extension MockLowering.Walk {
	/// The builder functions of `generators`' trees, in `.v3Unstable`, that a cycle closes on, by generator.
	mutating func v3CycleTargets(beneath generators: [ScopeGenerator]) -> [ObjectIdentifier: MockLowering.V3CycleTarget] {
		struct Frame {
			let generator: ScopeGenerator
			let declaration: ScopeGenerator.BuiltDeclaration
			var configuredTypes = Set<TypeDescription>()
			var isClosedOn = false
		}
		var targets = [ObjectIdentifier: MockLowering.V3CycleTarget]()
		var stack = [Frame]()
		// Each entry is a generator to enter, or `nil` to leave the frame on top of `stack`.
		var toVisit: [ScopeGenerator?] = generators.reversed()
		while let next = toVisit.popLast() {
			guard let generator = next else {
				let frame = stack.removeLast()
				if frame.isClosedOn {
					targets[ObjectIdentifier(frame.generator)] = MockLowering.V3CycleTarget(
						nearestTypes: frame.configuredTypes.subtracting([frame.declaration.concreteType]).sorted { $0.asSource < $1.asSource },
					)
				}
				if !stack.isEmpty {
					stack[stack.count - 1].configuredTypes.formUnion(frame.configuredTypes)
				}
				continue
			}
			guard case let .property(instantiable, property, _, _, isPropertyCycle, _) = generator.scopeData else { continue }
			if isPropertyCycle {
				if let closedOn = generator.closedOnDeclaration, let index = stack.lastIndex(where: { $0.declaration == closedOn }) {
					stack[index].isClosedOn = true
				}
				continue
			}
			let children = generator.orderedChildGenerators
			let isConfigured = isV3Configured(generator)
			var frame = Frame(generator: generator, declaration: ScopeGenerator.BuiltDeclaration(property: property, concreteType: instantiable.concreteInstantiable))
			if isConfigured {
				frame.configuredTypes.insert(instantiable.concreteInstantiable)
			}
			stack.append(frame)
			toVisit.append(nil)
			toVisit.append(contentsOf: children.reversed())
		}
		return targets
	}

	/// Whether the node `generator` builds has a configuration: a child it builds, or a default-valued parameter.
	mutating func isV3Configured(_ generator: ScopeGenerator) -> Bool {
		guard case let .property(instantiable, property, _, _, _, _) = generator.scopeData else { return false }
		let usesMockInitializer = instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType)
		return generator.orderedChildGenerators.contains { $0.mockLoweringBuiltProperty != nil } || !configurationDefaultFields(of: instantiable, usesMockInitializer: usesMockInitializer).isEmpty
	}

	/// The nearest configuration of `concreteType` in lexical scope, if any.
	func v3NearestConfiguration(of concreteType: TypeDescription) -> MockLowering.V3ConfigurationInScope? {
		v3ConfigurationsInScope[concreteType]?.last
	}

	/// The expression a node of `concreteType` reads its configuration from: the field `fieldPath` of its parent's, else the
	/// nearest configuration of its type in scope, else its type's defaults.
	func v3ConfigurationExpression(of concreteType: TypeDescription, field fieldPath: String) -> String {
		guard let nearest = v3NearestConfiguration(of: concreteType) else { return "\(fieldPath) ?? .init()" }
		return nearest.isOptional ? "\(fieldPath) ?? \(nearest.expression) ?? .init()" : "\(fieldPath) ?? \(nearest.expression)"
	}

	/// The name of a cycle target's parameter that holds the nearest configuration of `concreteType` above its pass.
	static func v3NearestParameterName(of concreteType: TypeDescription) -> String {
		ReservedName.nearestConfigurationParameterName(ofTypeIdentifier: concreteType.asIdentifier)
	}

	/// The arguments a call of a cycle target hands its nearest parameters, from what is in scope.
	func v3NearestArguments(of target: MockLowering.V3CycleTarget) -> [String] {
		target.nearestTypes.map { type in v3NearestConfiguration(of: type)?.expression ?? "nil" }
	}
}

extension MockLowering {
	/// What `.v3Unstable` names each type's configuration in a module: `T.SafeDIOverrides`, nested in a type the module
	/// declares, and `__safeDI_<Module>_<T>_MockConfiguration` at file scope for a type another module declares, since
	/// that module may nest a `SafeDIOverrides` of its own in it, which a second would make ambiguous.
	struct V3ConfigurationNames: Sendable, Equatable {
		init() {
			fileScopeNameByType = [:]
			publicNameByType = [:]
			publicMockTypes = []
		}

		/// - Parameter publicNameByType: The public configuration of each type the module's public mocks configure, which
		///   is the type's only configuration in the module: an internal mock builds such a type as a public mock does.
		/// - Parameter publicMockTypes: The types of the module's public mocks, each configured by its mock's root
		///   `SafeDIOverrides` (`PublicMockContext.v3PublicMockTypes`).
		init(foreignTypes: [TypeDescription], moduleName: String?, publicNameByType: [TypeDescription: String], publicMockTypes: Set<TypeDescription>) {
			fileScopeNameByType = PublicMockContext.configurationTypeNames(of: foreignTypes, moduleName: moduleName)
			self.publicNameByType = publicNameByType
			self.publicMockTypes = publicMockTypes
		}

		/// The name of the configuration of `type`.
		func typeName(of type: TypeDescription) -> String {
			typeDescription(of: type).asSource
		}

		/// The configuration of `type`, as `typeName(of:)` names it.
		func typeDescription(of type: TypeDescription) -> TypeDescription {
			if let name = publicNameByType[type] ?? fileScopeNameByType[type] {
				.simple(name: name, generics: [])
			} else {
				.nested(name: ReservedName.mockOverridesTypeName, parentType: type, generics: [])
			}
		}

		/// Whether the module configures `type` with a public configuration, which an internal mock builds it through.
		func isConfiguredPublicly(_ type: TypeDescription) -> Bool {
			publicNameByType[type] != nil
		}

		/// Whether `type`'s configuration is its public mock's root `SafeDIOverrides`, which holds its defaults in the root's
		/// form even where it is `Sendable`-typed (`PublicMockPlan.v3RootDefaultMembers`), never as the closures a
		/// module-level `Sendable` configuration stores.
		func isConfiguredByPublicMockRoot(_ type: TypeDescription) -> Bool {
			publicMockTypes.contains(type)
		}

		/// The name of the configuration of `type` where the module declares it at file scope, else `nil`.
		func fileScopeName(of type: TypeDescription) -> String? {
			fileScopeNameByType[type]
		}

		private let fileScopeNameByType: [TypeDescription: String]
		private let publicNameByType: [TypeDescription: String]
		private let publicMockTypes: Set<TypeDescription>
	}
}

extension MockLowering.Walk {
	/// Records a node a `.v3Unstable` mock promotes at its root's level, written as `nodeLines`, as one text place at `path`:
	/// its builder function, as the walk writes it, and its binding from the value `mock()` is passed for it, the instance
	/// or a value built from the configuration it is passed (`ConstantNode.promotedBindingLines(indent:)`), which no built
	/// record says. Every place beneath the node is its text. `rootDeclarations` are what `mock()` binds before its tree,
	/// which the text reads by name.
	mutating func recordPromotedPlace(_ node: MockLowering.ConstantNode, at path: [Int], lines nodeLines: [String], indent: String, rootDeclarations: [Property]) {
		guard let parameterName = node.promotedParameterName else { return }
		for placePath in placePathsInWalkOrder where placePath.count > path.count && Array(placePath.prefix(path.count)) == path {
			pathsCoveredByLoopUnits.insert(placePath)
		}
		let valueType = MockLowering.v3ReceivedValueType(of: node.property)
		let parameterType: TypeDescription = if let configurationTypeName = node.v3ReceivedConfigurationTypeName, node.v3ReceivedConfigurationName != nil {
			.simple(name: "SafeDIReceived", generics: [valueType, .simple(name: configurationTypeName, generics: [])])
		} else {
			.optional(valueType)
		}
		v3PromotedParameterDeclarations.append(Property(label: parameterName, typeDescription: parameterType))
		// The function's lines, then the binding's, which begins with `let` at the node's indent.
		let bindingIndex = nodeLines.firstIndex { $0.hasPrefix("\(indent)let ") } ?? nodeLines.endIndex
		let unindented = nodeLines.map { element in
			element
				.split(separator: "\n", omittingEmptySubsequences: false)
				.map { line in line.hasPrefix(indent) ? String(line.dropFirst(indent.count)) : String(line) }
				.joined(separator: "\n")
		}
		var outerTypes = [String: TypeDescription]()
		for declaration in rootDeclarations + v3PromotedParameterDeclarations {
			outerTypes[declaration.label] = declaration.typeDescription
		}
		let functionText = unindented[..<bindingIndex].joined(separator: "\n")
		// A text that binds a value at its top or calls a function of SafeDI's it does not declare leaves the place
		// unrecorded, so the root keeps the walk's text. Only a promoted dependency whose tree leads to a fill of another
		// module's public mock writes such text (its payload bindings precede its function), which no test reaches yet: the
		// fix of that shape owes its guards a failing test. Six shapes were tried and each fill landed inside the function:
		// a promoted flow filling a called screen's hole, a `.public` mock passing the place up, a loop of promoted
		// instantiators, a promoted `SendableInstantiator`, one of a flow that calls the screen, and the public mock smoke
		// seeds.
		guard let place = MockLowering.textPlace(functionText, outerTypes: outerTypes) else { return }
		let bindingText = unindented[bindingIndex...].joined(separator: "\n")
		var reads = place.reads
		var readNames = Set(reads.map(\.label))
		// The binding reads the value `mock()` is passed and what a construction in place reads; the configuration its
		// `.built` case binds, and the functions the text declares, are its own.
		let namesBoundByBinding = Set([node.bindingName] + [node.v3ReceivedConfigurationName].compactMap(\.self))
		for token in MockLowering.codeTokens(in: bindingText) where !token.isMember && !token.isLabel && !MockLowering.keywords.contains(token.name) && !place.declaredFunctionNames.contains(token.name) {
			guard token.name == parameterName || !namesBoundByBinding.contains(token.name),
			      MockLowering.namesAValue(token.name, outerTypes: outerTypes),
			      outerTypes[token.name] != nil || token.name.first?.isLowercase == true
			else { continue }
			if readNames.insert(token.name).inserted {
				reads.append(MockLowering.valueRead(token.name, outerTypes: outerTypes))
			}
		}
		loopUnitRecords[path] = .alias(AliasPlaceRecord(
			property: Property(label: node.bindingName, typeDescription: valueType),
			fulfillingProperty: nil,
			text: unindented.joined(separator: "\n"),
			reads: reads,
			declaredFunctionNames: place.declaredFunctionNames,
		))
	}
}
