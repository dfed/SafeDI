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
	/// The mock of `instantiable` in `.v3Unstable`'s API, whose tree's top-level nodes are `nodes`, bound by `bindingLines`,
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
			childFieldSources: MockLowering.ConfigurationRecord.childFieldSources(of: nodes.filter { $0.builtNode?.promotedParameterName == nil }),
			builderParameters: MockLowering.BuilderParameters(of: instantiable, usesMockInitializer: usesMockInitializer),
		)
		rootRecord.defaultFields = walk.configurationDefaultFields(of: instantiable, usesMockInitializer: usesMockInitializer)
		rootRecord.isV3 = true

		// The parameters, in order: forwarded, received that nothing builds (with the builders calls pass up), received only
		// if available, a builder per dependency the mock cannot build, then received that the mock builds.
		let beforeUncovered = signature.onlyIfAvailableOverrides.map { override in
			"\(bodyIndent)\(override.name): \(override.typeDescription.asSource) = nil"
		}
		var afterUncovered = [String]()
		for case let .built(node) in nodes {
			guard let parameterName = node.promotedParameterName else { continue }
			let valueType = MockLowering.v3ReceivedValueType(of: node.property)
			if node.hasConfiguration {
				afterUncovered.append("\(bodyIndent)\(parameterName): SafeDIReceived<\(valueType.asSource), \(node.instantiable.concreteInstantiable.asSource).\(ReservedName.mockOverridesTypeName)> = .built(.init())")
			} else {
				afterUncovered.append("\(bodyIndent)\(parameterName): \(TypeDescription.optional(valueType).asSource) = nil")
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
			let arguments = walk.constructionArguments(of: initializer, given: instantiable, usesMockInitializer: usesMockInitializer, dependencyArguments: dependencyArguments, nodePath: overrides, overrideReachable: true)
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
		children.compactMap { child in
			if case let .built(childNode) = child {
				return .built(bindingName: childNode.bindingName, hasConfiguration: childNode.hasConfiguration, requiresSendable: childNode.requiresSendable, concreteType: childNode.instantiable.concreteInstantiable, builderParameters: MockLowering.BuilderParameters(of: childNode.instantiable, usesMockInitializer: childNode.usesMockInitializer), propertyType: childNode.property.typeDescription)
			}
			return child.overridesField.map { field in
				.spelled(ChildField(name: field.name, typeSource: field.typeSource, defaultValue: field.defaultValue, sendableForm: child.sendableConfigurationFieldForm))
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
