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
	/// An override read a place's construction makes: its text, and the value path it reads where it names the overrides'
	/// members, `nil` where it reads a local a `@Sendable` function's extractor bound it to.
	struct OverrideRead {
		let text: String
		let path: ValuePath?
		/// The configuration the place's path key reads the override of, `safeDIOverrides.<member>…`, whatever local a
		/// `@Sendable` function reads the override into.
		let configuration: ValuePath
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
		let labelsPassedNil: Set<String>
		/// The argument labels of the construction the walk passes a value.
		let labelsPassedValue: Set<String>
		/// Where the construction reads defaults from its configuration or calls its type's hand-written mock, what the
		/// record holds in place of production's call (`MockLowering+ClosersAndDefaults.swift`).
		var configuredConstruction: ConfiguredConstruction?
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
	/// This source read under `name`: what a read of a declaration becomes where a mock binds the declaration apart from
	/// its label (`ScopeGenerator.builtPlaceRecord(of:…readNames:…)`), the binding itself, or the lazy wrapper whose
	/// instance the read is of.
	func renamed(to name: String) -> ArgumentSource {
		if case let .lazyInstance(_, throughOptional) = self {
			.lazyInstance(label: name, throughOptional: throughOptional)
		} else {
			.binding(label: name)
		}
	}
}

extension MockLowering.Walk {
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
		guard recordsPlaces else { return }
		// A construction by the type's hand-written mock, or one that reads defaults from its configuration, records its target
		// and its defaults' reads apart (`configuredConstruction(of:…)`).
		// A place of another module's public mock built inline reads the builder `mock()` takes for its hole first
		// (`HoleBuilder.inlinePlaceValue`), which no alternative records.
		guard node.inlinePlace == nil else {
			unrecordedReasons[childIndexPath] = "inlinePlaceBuilder"
			return
		}
		// A node a public mock promotes at its root's level reads its caller's value before its override and its construction
		// (`ConstantNode.passingPromotedValue(orBuilding:)`), a read no alternative records.
		guard node.promotedParameterName == nil else {
			unrecordedReasons[childIndexPath] = "promotedParameter"
			return
		}
		// A public mock builds a configured node by calling its type's construction function, which is handed the override
		// (`ConstantNode.publicBuilderFunctionEndLines(children:overrideRead:indent:)`): a target and an argument no record
		// names.
		guard !buildsPublicMock || !node.hasConfiguration else {
			unrecordedReasons[childIndexPath] = "publicConstructionFunction"
			return
		}
		// Inside a `@Sendable` builder function a public mock reads an override from a local bound before that function
		// (`readingOverride(_:localNameSuffix:)`), since its overrides are never `Sendable`: a local no record names, where
		// the record would read the overrides inside the function.
		guard !buildsPublicMock || overrideRead.map({ $0.path != nil }) ?? true else {
			unrecordedReasons[childIndexPath] = "overrideLocal"
			return
		}
		let configuredConstruction = configuredConstruction(of: node, instantiable: instantiable, usesMockInitializer: usesMockInitializer)
		var alternatives = [ConstructionAlternative]()
		if let overrideRead {
			// An override read through a local an extractor bound it to is recorded as the read of the configuration the
			// place's call hands it (`relativeConfiguration(of:…)`), so a place built in a `@Sendable` function records the
			// read its path names.
			alternatives.append(
				MockLowering.overrideAlternative(reading: overrideRead.path, resultWrapper: node.overrideResultWrapper)
					?? MockLowering.Walk.internalMockOverrideAlternative(of: node, configuration: overrideRead.configuration),
			)
		}
		builtPlaceInputs[childIndexPath] = MockLowering.BuiltPlaceInputs(
			functionName: node.functionName,
			hasFunction: hasFunction,
			readNames: MockLowering.readNames(of: initializer, given: instantiable.dependencies, argumentValues: dependencyArguments),
			alternatives: alternatives,
			labelsPassedNil: Set(dependencyArguments.filter { $0.value == "nil" }.map(\.label)),
			labelsPassedValue: Set(dependencyArguments.filter { $0.value != "nil" }.map(\.label)),
			configuredConstruction: configuredConstruction,
		)
	}

	/// Records, through production's record function, the built place the walk lowered `node` at.
	mutating func recordBuiltPlace(of generator: ScopeGenerator, node: MockLowering.TreeNode, unavailableProperties: Set<Property>) {
		guard case let .built(constantNode) = node,
		      let inputs = builtPlaceInputs.removeValue(forKey: childIndexPath),
		      case let .property(instantiable, property, forwardedProperties, erasedToConcreteExistential, _, seamCall) = generator.scopeData
		else { return }
		// The record is made once the walk is done (`recordBuiltPlaces()`), when the records of the places in its builder
		// function are known.
		let call = MockLowering.BuiltPlaceCall(
			generator: generator,
			property: property,
			instantiable: instantiable,
			forwardedProperties: forwardedProperties,
			erasedToConcreteExistential: erasedToConcreteExistential,
			unavailableProperties: unavailableProperties,
			inputs: inputs,
			node: PlanNode(),
			nodeConfiguration: constantNode.configuration,
			isPlannedAtPlace: seamCall == nil && !pathsWithUnplannedLines.contains(childIndexPath),
		)
		// Every place has a node of its own: only places whose whole records agree, their children's included, share one
		// (`sharingNode(ofBuiltPlaceAt:nodesByKey:)`). Two places of one generator can hold children whose records differ.
		builtPlaceCalls[childIndexPath] = call
	}
}
