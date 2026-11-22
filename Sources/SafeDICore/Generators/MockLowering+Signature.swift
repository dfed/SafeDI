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
		/// A parameter of `mock()`: the property it binds under its label, and its default, if it has one.
		struct Parameter {
			let property: Property
			let defaultExpression: String?
			/// The parameter's type as `mock()` declares it, where that is not the property's type as a parameter.
			var typeSource: String?
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
		/// The lines that document, above `mock()`, each uncovered parameter several types create
		/// (`MockRootParameters.UncoveredParameter.sharedValueDocumentation`).
		let sharedValueDocumentation: [String]
		/// The names the constructions of the root's tree declare `@escaping`, which the parameters spell so.
		let typesDeclaredEscaping: Set<TypeDescription>

		/// The properties the forwarded, received and uncovered parameters bind, which every node of the tree is built after.
		/// The default-valued ones are the initializer's alone.
		var properties: Set<Property> {
			Set((forwardedParameters + flatReceivedParameters + uncoveredParameters).map(\.property))
		}

		/// The labels the parameters bind, which no node of the tree may bind again.
		var labels: Set<String> {
			Set(parameters.map(\.property.label))
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

		/// The parameters' declarations in `mock()`, at `indent`.
		func parameterLines(indent: String) -> [String] {
			parameters.map { parameter in
				let typeSource = parameter.typeSource ?? parameter.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource
				return if let defaultExpression = parameter.defaultExpression {
					"\(indent)\(parameter.property.label): \(typeSource) = \(defaultExpression)"
				} else {
					"\(indent)\(parameter.property.label): \(typeSource)"
				}
			}
		}
	}
}

extension ScopeGenerator {
	/// The parameters of this mock root's `mock()` other than its overrides, or the first rule they meet that the lowering
	/// does not lower yet.
	func lowerRootSignature(of instantiable: Instantiable, context: MockContext) -> MockLowering.Lowering<MockLowering.RootSignature> {
		var forwardedParameters = [MockLowering.RootSignature.Parameter]()
		for dependency in instantiable.dependencies.sorted(by: { $0.property < $1.property }) where dependency.source == .forwarded {
			// A forwarded wrapper declares the forms of its instance beside it, which the tree's receives read.
			guard dependency.property.propertyType.isConstant else { return .unsupported(.wrapper) }
			// The default the initializer gives the parameter of its label wins over the hand-written mock its type has.
			let constructionDefault = instantiable.initializer?.arguments.first { $0.innerLabel == dependency.property.label }?.defaultValueExpression
			forwardedParameters.append(MockLowering.RootSignature.Parameter(
				property: dependency.property,
				defaultExpression: constructionDefault ?? context.flatParameterMockDefaults[dependency.property.typeDescription]?.expression,
			))
		}
		var rootDefaultParameters = [MockLowering.RootSignature.Parameter]()
		for (argument, defaultExpression) in Self.defaultValuedMockParameterArguments(of: instantiable) {
			// `mock()` takes an `@autoclosure` as one and passes its call, so the value is evaluated where the type is built.
			guard argument.typeDescription.strippingEscaping.autoclosureValueType == nil else { return .unsupported(.defaultValuedParameter) }
			rootDefaultParameters.append(MockLowering.RootSignature.Parameter(
				property: Property(label: argument.label, typeDescription: argument.typeDescription),
				defaultExpression: defaultExpression,
				typeSource: argument.typeDescription.asFunctionParameter.asSource,
			))
		}
		// The forms of what the tree receives only if available are overrides of `mock()`, not parameters.
		guard onlyIfAvailableUnwrappedReceivedProperties.isEmpty else { return .unsupported(.onlyIfAvailable) }
		// Each in the mocked type's own spelling where it receives the dependency, else its receivers' most explicit one.
		let receivedProperties = MockedTypeSpellings(of: instantiable, treeReceivedProperties: receivedProperties).spellings(of: receivedProperties)
		// The mock wraps the instance it is passed for a `LazilyInstantiated` it cannot build.
		guard !receivedProperties.contains(where: { $0.typeDescription.lazilyInstantiatedInstanceType != nil }) else { return .unsupported(.wrapper) }
		let forwardedProperties = instantiable.forwardedReceivableProperties
		let receivedNonOptionalProperties = Set(receivedProperties.filter { !$0.typeDescription.isOptional })
		var flatReceivedParameters = [MockLowering.RootSignature.Parameter]()
		for property in receivedProperties.sorted(by: { $0.precedesInMockOrder($1) }) {
			// A forwarded `x: X` fulfills an `x: X?` too, and so does a received `x: X`, which the parameter of its own binds.
			guard !forwardedProperties.contains(property),
			      !property.typeDescription.isOptional
			      || !receivedNonOptionalProperties.contains(property.asUnwrappedProperty) && !forwardedProperties.contains(property.asUnwrappedProperty)
			else { continue }
			// A node the mock promotes for an optional receive binds its non-optional value, which provides this one.
			guard property.typeDescription.isOptional || !propertiesToDeclare.contains(property.asOptionalProperty) else { return .unsupported(.flatParameter) }
			guard !Self.provides(property, declaredProperties: propertiesToDeclare, forwardedProperties: []) else { continue }
			flatReceivedParameters.append(MockLowering.RootSignature.Parameter(
				property: property,
				defaultExpression: context.flatParameterMockDefaults[property.typeDescription]?.expression,
			))
		}
		let uncoveredParameters: [MockRootParameters.UncoveredParameter]
		switch lowerUncoveredParameters(of: instantiable) {
		case let .lowered(lowered):
			uncoveredParameters = lowered
		case let .unsupported(rule):
			return .unsupported(rule)
		}
		// A type that generates its dependency tree takes a builder for each hole type of its places in place of their
		// parameters (`seamMockBuilders`), which lane C's family lowers.
		guard !instantiable.generatesDependencyTree || uncoveredParameters.isEmpty else { return .unsupported(.holeSite) }
		// Two parameters of one label are named apart.
		let parameters = forwardedParameters + rootDefaultParameters + flatReceivedParameters + uncoveredParameters.map {
			MockLowering.RootSignature.Parameter(property: $0.property, defaultExpression: nil, typeSource: $0.typeSource)
		}
		guard Set(parameters.map(\.property.label)).count == parameters.count else { return .unsupported(.siblingLabelCollision) }
		return .lowered(MockLowering.RootSignature(
			forwardedParameters: forwardedParameters,
			rootDefaultParameters: rootDefaultParameters,
			flatReceivedParameters: flatReceivedParameters,
			uncoveredParameters: parameters.suffix(uncoveredParameters.count),
			sharedValueDocumentation: uncoveredParameters.flatMap(\.sharedValueDocumentation),
			typesDeclaredEscaping: typesDeclaredEscaping,
		))
	}

	/// The `@Instantiated` dependencies of the mocked type, `instantiable`, and of the types of its tree that the mock cannot
	/// build, which `mock()` takes, as `mockRootParameters(instantiable:mockDefaults:)` collects them: the mocked type's in
	/// its declaration order, then each node's, in the order a walk of the tree in generation order first meets them; or the
	/// first rule they meet that the lowering does not lower yet. A dependency is uncovered where no child of the type that
	/// instantiates it builds its label (for the mocked type, its property or a `LazilyInstantiated` of it). The tree is
	/// walked with a stack, since it can be as deep as the module has types.
	private func lowerUncoveredParameters(of instantiable: Instantiable) -> MockLowering.Lowering<[MockRootParameters.UncoveredParameter]> {
		/// A node of the tree that builds a type, and where it is among the nodes the type above it builds: its declaration
		/// index there, or none for a node the mock promotes, then its index in generation order.
		struct Visit {
			let generator: ScopeGenerator
			let declarationPath: [Position]
			/// The labels the builder functions around the node declare, which hide a parameter of the same label there.
			let namesDeclaredByEnclosingBuilderFunctions: Set<String>
		}
		struct Position: Comparable {
			let declarationIndex: Int
			let generationIndex: Int

			static func < (lhs: Position, rhs: Position) -> Bool {
				(lhs.declarationIndex, lhs.generationIndex) < (rhs.declarationIndex, rhs.generationIndex)
			}
		}
		/// The generators of the children that build a type, each at its position among them.
		func propertyChildren(of generator: ScopeGenerator, declaredBy dependencies: [Dependency], at path: [Position], enclosedBy names: Set<String>) -> [Visit] {
			var declarationIndexByLabel = [String: Int]()
			for (index, dependency) in dependencies.enumerated() where declarationIndexByLabel[dependency.property.label] == nil {
				declarationIndexByLabel[dependency.property.label] = index
			}
			return generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []).map(\.generator).enumerated().compactMap { generationIndex, child in
				guard case let .property(_, property, _, _, _, _) = child.scopeData else { return nil }
				let position = Position(declarationIndex: declarationIndexByLabel[property.label] ?? Int.max, generationIndex: generationIndex)
				return Visit(generator: child, declarationPath: path + [position], namesDeclaredByEnclosingBuilderFunctions: names)
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
		func add(_ dependency: Dependency, createdBy type: TypeDescription, at path: [Position]) {
			if dependencyByProperty[dependency.property] == nil {
				properties.append(dependency.property)
				dependencyByProperty[dependency.property] = dependency
			}
			creatingTypesByProperty[dependency.property, default: []].append((path: path, type: type))
		}

		let rootChildren = propertyChildren(of: self, declaredBy: instantiable.dependencies, at: [], enclosedBy: [])
		var builtProperties = Set<Property>()
		for child in rootChildren {
			guard let property = child.generator.property else { continue }
			builtProperties.insert(property)
			if let instanceProperty = property.asLazilyInstantiatedInstanceProperty {
				builtProperties.insert(instanceProperty)
			}
		}
		// The mocked type is built in the body of `mock()`, outside every builder function.
		for dependency in instantiable.dependencies where isInstantiated(dependency) && !builtProperties.contains(dependency.property) {
			add(dependency, createdBy: instantiable.concreteInstantiable, at: [])
		}
		var visits = Array(rootChildren.reversed())
		while let visit = visits.popLast() {
			// The walk does not lower a node that closes a cycle, whose dependencies would not surface as parameters.
			guard case let .property(nodeInstantiable, _, _, _, isPropertyCycle, _) = visit.generator.scopeData, !isPropertyCycle else { continue }
			let children = propertyChildren(of: visit.generator, declaredBy: nodeInstantiable.dependencies, at: visit.declarationPath, enclosedBy: [])
			let childLabels = Set(children.compactMap(\.generator.property?.label))
			var uncoveredLabels = Set<String>()
			for dependency in nodeInstantiable.dependencies where isInstantiated(dependency) && !childLabels.contains(dependency.property.label) {
				// A builder function around the type declares the label, which would hide the parameter there: `mock()` names it
				// apart.
				guard !visit.namesDeclaredByEnclosingBuilderFunctions.contains(dependency.property.label) else { return .unsupported(.siblingLabelCollision) }
				uncoveredLabels.insert(dependency.property.label)
				add(dependency, createdBy: nodeInstantiable.concreteInstantiable, at: visit.declarationPath)
			}
			var namesDeclared = visit.namesDeclaredByEnclosingBuilderFunctions
			for dependency in nodeInstantiable.dependencies where !uncoveredLabels.contains(dependency.property.label) {
				namesDeclared.insert(dependency.property.label)
			}
			visits.append(contentsOf: children.reversed().map {
				Visit(generator: $0.generator, declarationPath: $0.declarationPath, namesDeclaredByEnclosingBuilderFunctions: namesDeclared)
			})
		}
		var parameters = [MockRootParameters.UncoveredParameter]()
		for property in properties {
			guard let dependency = dependencyByProperty[property] else { continue }
			// A value a type built in a `@Sendable` builder function instantiates is a `@Sendable` autoclosure, which no
			// node the walk lowers is (lane B's family).
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
				isSendableAutoclosure: false,
				creatingTypes: creatingTypes,
			))
		}
		return .lowered(parameters)
	}
}
