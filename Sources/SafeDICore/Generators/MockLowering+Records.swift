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

	/// An override read a place's construction makes: its text, and the value path it reads where it names the overrides'
	/// members (`overrideReadPath(_:)`), `nil` where it reads a local a `@Sendable` function's extractor bound it to.
	struct OverrideRead {
		let text: String
		let path: ValuePath?
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
		/// The argument labels of the construction the walk passes `nil`, which a record must pass `nil` too.
		var labelsPassedNil = Set<String>()
		/// The argument labels of the construction the walk passes a value.
		var labelsPassedValue = Set<String>()
		/// Where the construction reads defaults from its configuration or calls its type's hand-written mock, what the
		/// record holds in place of production's call (`MockLowering+ClosersAndDefaults.swift`).
		var configuredConstruction: ConfiguredConstruction?
		/// The override the place's construction reads, as the walk spelled it, or `nil`.
		var overrideReadText: String?

		/// What of these the place's record reads beyond its generator, which a plan node is made once for: one generator
		/// can be lowered at two places that differ in them, whose records then differ.
		var recordedKey: RecordedKey {
			RecordedKey(
				functionName: functionName,
				hasFunction: hasFunction,
				readNames: readNames,
				labelsPassedNil: labelsPassedNil,
				labelsPassedValue: labelsPassedValue,
				configuredConstruction: configuredConstruction,
				overrideReadText: overrideReadText,
			)
		}

		struct RecordedKey: Hashable {
			let functionName: String
			let hasFunction: Bool
			let readNames: [Property: String]
			let labelsPassedNil: Set<String>
			let labelsPassedValue: Set<String>
			let configuredConstruction: ConfiguredConstruction?
			let overrideReadText: String?
		}
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
	static func overrideAlternative(reading overrideRead: ValuePath?, resultWrapper: TypeDescription?) -> ConstructionAlternative? {
		overrideRead.map { closure in
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
	///
	/// Mock roots share one construction memo, so whether two places hold one generator follows the order the roots are
	/// built in. The key therefore also holds what the place's record reads beyond the generator (`BuiltPlaceInputs.RecordedKey`):
	/// two places of one generator share a node only where their records agree, as places of two generators never do.
	struct PlanNodeKey: Hashable {
		let generator: ObjectIdentifier
		let unavailableProperties: Set<Property>
		let inputs: MockLowering.BuiltPlaceInputs.RecordedKey
	}

	/// Keeps what the walk hands production's record function at the built place it is lowering.
	mutating func recordInputs(
		of node: MockLowering.ConstantNode,
		hasFunction: Bool,
		overrideRead: MockLowering.OverrideRead?,
		initializer: Initializer,
		instantiable: Instantiable,
		dependencyArguments: [(label: String, value: String)],
		usesMockInitializer: Bool,
	) {
		// A construction by the type's hand-written mock, or one that reads defaults from its configuration, records its target
		// and its defaults' reads apart (`configuredConstruction(of:…)`), or nothing where it cannot say them.
		let configuredConstruction = configuredConstruction(of: node, instantiable: instantiable, readsOverride: overrideRead != nil, usesMockInitializer: usesMockInitializer)
		guard configuredConstruction != .unrecorded else {
			unrecordedReasons[childIndexPath] = "configuredUnrecorded"
			return
		}
		var alternatives = [ConstructionAlternative]()
		if let overrideRead {
			// An override read the record cannot name, as a local an extractor bound it to, leaves the place unrecorded,
			// except in an internal mock, whose record reads the override of the configuration its call hands it
			// (`relativeConfiguration(of:…)`), so a place built in a `@Sendable` function records the read its path names.
			guard let alternative = MockLowering.overrideAlternative(reading: overrideRead.path, resultWrapper: node.overrideResultWrapper)
				?? internalMockOverrideAlternative(of: node)
			else {
				unrecordedReasons[childIndexPath] = "overrideLocal"
				return
			}
			alternatives.append(alternative)
		}
		builtPlaceInputs[childIndexPath] = MockLowering.BuiltPlaceInputs(
			functionName: node.functionName,
			hasFunction: hasFunction,
			readNames: MockLowering.readNames(of: initializer, given: instantiable.dependencies, argumentValues: dependencyArguments),
			alternatives: alternatives,
			labelsPassedNil: Set(dependencyArguments.filter { $0.value == "nil" }.map(\.label)),
			labelsPassedValue: Set(dependencyArguments.filter { $0.value != "nil" }.map(\.label)),
			configuredConstruction: configuredConstruction.recorded,
			overrideReadText: overrideRead?.text,
		)
	}

	/// Records, through production's record function, the built place the walk lowered `node` at.
	mutating func recordBuiltPlace(of generator: ScopeGenerator, node: MockLowering.TreeNode, isLoopMember: Bool, unavailableProperties: Set<Property>) {
		guard case .built = node,
		      let inputs = builtPlaceInputs[childIndexPath],
		      case let .property(instantiable, property, forwardedProperties, erasedToConcreteExistential, _, seamCall) = generator.scopeData
		else { return }
		let key = PlanNodeKey(generator: ObjectIdentifier(generator), unavailableProperties: unavailableProperties, inputs: inputs.recordedKey)
		let planNode = planNodes[key] ?? PlanNode()
		planNodes[key] = planNode
		// The record is made once the walk is done (`recordBuiltPlaces()`), when the records of the places in its builder
		// function are known.
		builtPlaceCalls[childIndexPath] = MockLowering.BuiltPlaceCall(
			generator: generator,
			property: property,
			instantiable: instantiable,
			forwardedProperties: forwardedProperties,
			erasedToConcreteExistential: erasedToConcreteExistential,
			unavailableProperties: unavailableProperties,
			inputs: inputs,
			node: planNode,
			treeNode: node,
			isPlannedAtPlace: seamCall == nil && !isLoopMember && !pathsWithUnplannedLines.contains(childIndexPath),
		)
	}
}
