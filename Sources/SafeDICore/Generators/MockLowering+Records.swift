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

extension MockLowering {
	/// The alternative a built place's record tries before its construction, where the mock walk hooked the construction
	/// (`ConstructionHook`) with a read of the place's override, or `nil` where the hook says something the record cannot:
	/// a read the walk cannot name as a value path, another construction, or a call of the builder other than with the
	/// construction's arguments.
	/// - Parameters:
	///   - hook: The walk's hook of the place.
	///   - construction: The construction the record calls, spelled.
	///   - argumentValues: The values the construction passes, spelled, in its order.
	///   - erasedType: The type the place's value is erased to, where the property is erased.
	static func constructionAlternative(
		of hook: ConstructionHook,
		construction: String,
		argumentValues: [String],
		erasedType: TypeDescription?,
	) -> ConstructionAlternative? {
		guard hook.construction == nil || hook.construction == construction,
		      let closure = overrideReadPath(hook.builder)
		else { return nil }
		let bindingName = ReservedName.configurationBuilderPropertyName
		let call = "\(bindingName)(\(argumentValues.joined(separator: ", ")))"
		let resultWrapper: TypeDescription?
		if hook.call == call {
			resultWrapper = nil
		} else if let erasedType, hook.call == "\(erasedType.asSource)(\(call))" {
			resultWrapper = erasedType
		} else {
			return nil
		}
		return ConstructionAlternative(
			closure: closure,
			bindingName: bindingName,
			requiresAbsent: [],
			use: .calledWithConstructionArguments,
			resultWrapper: resultWrapper,
		)
	}

	/// The value path of an override read spelled `safeDIOverrides.<member>.<member>…`, or `nil` for any other read, such
	/// as a local a `@Sendable` function's extractor bound it to.
	static func overrideReadPath(_ read: String) -> ValuePath? {
		let parts = read.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
		guard parts.count > 1, parts[0] == ReservedName.mockOverridesParameterName, !parts.contains(where: \.isEmpty) else { return nil }
		var path = ValuePath.rootDeclaration(parts[0])
		for member in parts.dropFirst() {
			path = .member(member, of: path)
		}
		return path
	}
}

extension MockLowering {
	/// What the mock walk hands production's record function (`ScopeGenerator.builtPlaceRecord(of:…)`) at one built place:
	/// whether the place writes a builder function, the name of that function, the names its construction reads its
	/// values under where the mock binds them apart from their labels, and the override it tries first.
	struct BuiltPlaceInputs {
		let functionName: String
		let hasFunction: Bool
		let readNames: [Property: String]
		let alternatives: [ConstructionAlternative]
		/// The construction function a public mock's configured place calls instead (`MockLowering+PublicRecords.swift`).
		var publicConstruction: PublicConstructionInputs?
	}

	/// The names a construction reads its dependencies under where the walk passes them apart from their labels
	/// (`argumentValues(of:given:…)`), by the property the dependency declares: a name bound apart, the lazy wrapper whose
	/// instance it reads, or a parameter of `mock()`. A dependency passed `nil` reads nothing, as production's record says.
	static func readNames(
		of initializer: Initializer,
		given dependencies: [Dependency],
		argumentValues: [(label: String, value: String)],
	) -> [Property: String] {
		let passedDependencies = initializer.arguments.compactMap { dependency(passedTo: $0, among: dependencies) }
		var readNames = [Property: String]()
		for (dependency, argument) in zip(passedDependencies, argumentValues) where argument.value != "nil" {
			let instanceSuffix = ".\(Dependency.lazilyInstantiatedInstancePropertyName)"
			let name = argument.value.hasSuffix(instanceSuffix) ? String(argument.value.dropLast(instanceSuffix.count)) : argument.value
			if name != dependency.property.label {
				readNames[dependency.property] = name
			}
		}
		return readNames
	}

	/// The alternative a place tries before its construction where the walk reads its override at `overrideRead`, whose
	/// result is wrapped in `resultWrapper`; `nil` where the read is no value path, as a local an extractor bound it to.
	static func overrideAlternative(reading overrideRead: String, resultWrapper: TypeDescription?) -> ConstructionAlternative? {
		overrideReadPath(overrideRead).map { closure in
			ConstructionAlternative(
				closure: closure,
				bindingName: ReservedName.configurationBuilderPropertyName,
				requiresAbsent: [],
				use: .calledWithConstructionArguments,
				resultWrapper: resultWrapper,
			)
		}
	}
}

extension ArgumentSource {
	/// This source read under `name` where it reads the declaration of `label`: what a read becomes where a mock binds the
	/// label apart (`ScopeGenerator.builtPlaceRecord(of:…readNames:…)`).
	func renamed(from label: String, to name: String) -> ArgumentSource {
		switch self {
		case let .binding(boundLabel) where boundLabel == label:
			.binding(label: name)
		case let .lazyInstance(boundLabel, throughOptional) where boundLabel == label:
			.lazyInstance(label: name, throughOptional: throughOptional)
		case .binding,
		     .lazyInstance,
		     .nil,
		     .forwardedSpread,
		     .wrapper,
		     .optionalWrapper,
		     .builderArgument,
		     .spelledArgument:
			self
		}
	}
}

extension MockLowering.Walk {
	/// A generator in one context it is written in: what production's plan node is made once for (`planNode(…)` in
	/// `ScopeGenerator`).
	struct PlanNodeKey: Hashable {
		let generator: ObjectIdentifier
		let unavailableProperties: Set<Property>
	}

	/// Keeps what the walk hands production's record function at the built place it is lowering.
	mutating func recordInputs(
		of node: MockLowering.ConstantNode,
		hasFunction: Bool,
		overrideRead: String?,
		initializer: Initializer,
		instantiable: Instantiable,
		dependencyArguments: [(label: String, value: String)],
		usesMockInitializer: Bool,
	) {
		// A construction by the type's hand-written mock, or one that reads defaults from its configuration, is one the record
		// cannot spell yet: its target is the initializer, and its arguments are reads alone.
		guard !usesMockInitializer, !constructionReadsConfiguration(of: instantiable, usesMockInitializer: usesMockInitializer) else { return }
		var alternatives = [ConstructionAlternative]()
		if let overrideRead {
			// An override read the record cannot name, as a local an extractor bound it to, leaves the place unrecorded.
			guard let alternative = MockLowering.overrideAlternative(reading: overrideRead, resultWrapper: node.overrideResultWrapper) else { return }
			alternatives.append(alternative)
		}
		builtPlaceInputs[childIndexPath] = MockLowering.BuiltPlaceInputs(
			functionName: node.functionName,
			hasFunction: hasFunction,
			readNames: MockLowering.readNames(of: initializer, given: instantiable.dependencies, argumentValues: dependencyArguments),
			alternatives: alternatives,
		)
	}

	/// Records, through production's record function, the built place the walk lowered `node` at.
	mutating func recordBuiltPlace(of generator: ScopeGenerator, node: MockLowering.TreeNode, isLoopMember: Bool, unavailableProperties: Set<Property>) {
		guard case .built = node,
		      let inputs = builtPlaceInputs[childIndexPath],
		      case let .property(instantiable, property, forwardedProperties, erasedToConcreteExistential, _, seamCall) = generator.scopeData
		else { return }
		let key = PlanNodeKey(generator: ObjectIdentifier(generator), unavailableProperties: unavailableProperties)
		let planNode = planNodes[key] ?? PlanNode()
		planNodes[key] = planNode
		// A construction whose reads the record function cannot name (`Initializer.GenerationError`) leaves the place
		// unrecorded: the walk's own statement is what the mock writes.
		do {
			let record = try generator.builtPlaceRecord(
				of: property,
				instantiable: instantiable,
				forwardedProperties: forwardedProperties,
				erasedToConcreteExistential: erasedToConcreteExistential,
				unavailableProperties: unavailableProperties,
				functionName: inputs.functionName,
				hasFunction: inputs.hasFunction,
				children: [],
				node: planNode,
				isPlannedAtPlace: seamCall == nil && !isLoopMember,
				readNames: inputs.readNames,
				alternatives: inputs.alternatives,
			)
			builtRecords[childIndexPath] = record.flatMap { publicRecord(of: $0, inputs: inputs) }
		} catch {
			unrecordedPlaceErrors[childIndexPath] = error
		}
	}
}
