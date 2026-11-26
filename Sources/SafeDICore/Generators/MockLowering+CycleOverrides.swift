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

/// How a mock place that a cycle builds again finds its overrides: through the nearest place above it that builds the same
/// type (decision MOCK-CYCLE-LAP-OVERRIDES, option B), so a mock's overrides hold however many times a test goes around a
/// loop. A place a cycle builds again has no field of its own in its parent's configuration, since `cycleEdges` are chosen
/// per type; the nearest place of its type reads a configuration of the same type, which has the fields of every place
/// beneath it.
///
/// Two forms share one rule. In the path key, where each place's code reads a fixed override path, a place reads the path
/// of the nearest place of its type (`AncestorOverridePath.own`). In the type key, where places of one type share a
/// function, the function takes its type's configuration as a passed argument (`configurationParameter`): each place that
/// calls it hands its own configuration, and a closer hands the configuration of the place it closes on, so one function
/// reads lap 1's overrides on every lap, whichever call reached it.
extension MockLowering {
	/// The override path a place reads, and whether it reads a configuration rather than a closure.
	struct AncestorOverridePath: Equatable {
		let path: String
		/// `path` as the value path the place's record reads, built a member at a time beside the text, since reading it
		/// again from the text would cost each place the length of its path.
		let value: ValuePath
		let hasConfiguration: Bool
		/// Whether the place is built with its type's hand-written mock, whose configuration has another shape.
		let builtWithHandWrittenMock: Bool

		/// The override path the place reads: `path` where its parent's configuration has a field for it
		/// (`isReachable`), else the path of the nearest place of its type above it where both read a configuration or
		/// both a closure and both are built the same way, else `nil`, and the place reads no override.
		static func own(path: String, value: ValuePath, hasConfiguration: Bool, builtWithHandWrittenMock: Bool, isReachable: Bool, nearest: AncestorOverridePath?) -> AncestorOverridePath? {
			if isReachable {
				AncestorOverridePath(path: path, value: value, hasConfiguration: hasConfiguration, builtWithHandWrittenMock: builtWithHandWrittenMock)
			} else if let nearest, nearest.hasConfiguration == hasConfiguration, nearest.builtWithHandWrittenMock == builtWithHandWrittenMock {
				nearest
			} else {
				nil
			}
		}
	}

	/// A configuration a place declares in the type key's form, which a node a cycle builds again of its type, built the
	/// same way, reads (`Walk.relativeConfigurationsByType`).
	struct RelativeConfiguration: Equatable {
		let hasConfiguration: Bool
		let builtWithHandWrittenMock: Bool
	}

	/// The names under which the builder functions of one mock root take the configurations their places read: one for each
	/// concrete type and way of building it, claimed where the walk first reaches a place built so. A name is made from the
	/// type (`TypeDescription.asIdentifier`), which two types can spell alike (`Outer.Inner` and `Outer_Inner`) and which
	/// keeps the backticks a type is named with (`` `default` ``), so each is spelled as one identifier and claimed, with
	/// the name a function takes the type's nearest configuration under (`NearestConfigurations.nearestName(ofParameterNamed:)`),
	/// apart from every name claimed before it and from the locals `mock()` reads its `@Sendable` autoclosure parameters
	/// into, which a builder function calls. The layout names its functions and locals apart from every parameter its
	/// functions take (`TypeKeyLayout.computeDecoratorsAndNames`), so a property labeled as a parameter is named
	/// (`Aa_configuration` beside the type `Aa`) hides nothing either.
	///
	/// It holds one name for each type a root's walk configures, for the length of that root's lowering.
	struct ConfigurationParameterNames {
		/// The name of the parameter that takes the configuration of a place of `concreteType`, built with its hand-written
		/// mock or not. A place built with its type's hand-written mock reads a configuration of another shape than one
		/// built with its initializer (`validateConfigurationsAreBuiltOneWay` leaves out a place beneath a cycle edge), so
		/// the two ways take parameters of two names, and a place reads only the nearest place built its own way (issue
		/// #720's shape).
		mutating func name(ofConfigurationOf concreteType: TypeDescription, builtWithHandWrittenMock: Bool) -> String {
			let construction = Construction(concreteType: concreteType, builtWithHandWrittenMock: builtWithHandWrittenMock)
			if let name = namesByConstruction[construction] {
				return name
			} else {
				let name = allocator.claim(
					"\(ReservedName.builderFunctionNamePrefix)\(concreteType.asIdentifier)\(builtWithHandWrittenMock ? "_mockConfiguration" : "_configuration")".spelledAsJoinedIdentifier,
					occupying: { [$0, NearestConfigurations.nearestName(ofParameterNamed: $0)] },
				)
				namesByConstruction[construction] = name
				return name
			}
		}

		/// The name of the parameter under which the function of a member of a loop of builders takes the configuration of
		/// the loop's level, a place of `concreteType` built with its hand-written mock or not (`loopMemberConfigurations()`),
		/// claimed apart from the name of the level's own function's parameter, which a place of the type beneath the member
		/// reads as the nearest.
		mutating func name(ofLoopLevelConfigurationOf concreteType: TypeDescription, builtWithHandWrittenMock: Bool) -> String {
			let construction = Construction(concreteType: concreteType, builtWithHandWrittenMock: builtWithHandWrittenMock)
			if let name = loopLevelNamesByConstruction[construction] {
				return name
			} else {
				let name = allocator.claim("\(ReservedName.builderFunctionNamePrefix)\(concreteType.asIdentifier)\(builtWithHandWrittenMock ? "_mockLoopConfiguration" : "_loopConfiguration")".spelledAsJoinedIdentifier)
				loopLevelNamesByConstruction[construction] = name
				return name
			}
		}

		/// The name of the parameter under which the function of a member of a loop of builders takes the configuration of
		/// another member of its loop whose level declares it under `label`, where the members take each other's in place of
		/// their level's (`loopMemberConfigurations()`). Two members of one loop can be of one type, so these are named by
		/// their labels, which no two members of a level share, and two loops of one root that declare a label alike share its
		/// name, since no function takes the members of two loops.
		mutating func name(ofMemberConfigurationLabeled label: String) -> String {
			if let name = namesByMemberLabel[label] {
				return name
			} else {
				let name = allocator.claim("\(ReservedName.builderFunctionNamePrefix)\(label)_memberConfiguration".spelledAsJoinedIdentifier)
				namesByMemberLabel[label] = name
				return name
			}
		}

		private struct Construction: Hashable {
			let concreteType: TypeDescription
			let builtWithHandWrittenMock: Bool
		}

		/// A table that claims every name apart from `names`, which the mock declares before its tree.
		init(reserving names: Set<String> = []) {
			allocator = GeneratedNameAllocator(reserving: names)
		}

		private var namesByConstruction = [Construction: String]()
		private var loopLevelNamesByConstruction = [Construction: String]()
		private var namesByMemberLabel = [String: String]()
		private var allocator: GeneratedNameAllocator
	}

	/// The passed argument through which a type key function of a concrete type takes the configuration its place reads.
	/// Its name is one per type (`ConfigurationParameterNames`), and a passed argument is a declaration inside the function
	/// it is handed to, so a read of the name resolves to the nearest place of the type above it: the rule above, as the
	/// engine's nearest declaration.
	/// A place that reads a configuration struct takes it non-optional, and a call that reaches no same-type place hands a
	/// fresh `<T>.SafeDIMockConfiguration()`, as the path key's pruned place reads one today, so the place's defaults read
	/// `configuration.label` alike on every call. A place that reads only an override closure takes it optional, and such a
	/// call hands `nil`, which builds the type as no override does.
	struct ConfigurationParameter: Hashable, Sendable {
		/// The parameter's name in the called function.
		let name: String
		/// The parameter's type: the configuration struct the place reads, or the override closure's type made optional.
		let type: TypeDescription
		/// Whether the place reads a configuration struct rather than an override closure.
		let readsConfigurationStruct: Bool

		/// The parameter named `name` (`ConfigurationParameterNames`) of a place that reads a configuration of
		/// `configurationType`: its type's struct, or an override closure.
		init(name: String, configurationType: TypeDescription) {
			self.name = name
			readsConfigurationStruct = !configurationType.isClosure && !configurationType.isOptional
			type = readsConfigurationStruct || configurationType.isOptional ? configurationType : .optional(configurationType)
		}

		/// The parameter a call hands `type` under `name`, as a closer's passed argument names it.
		init(name: String, type: TypeDescription) {
			self.name = name
			self.type = type
			readsConfigurationStruct = !type.isOptional
		}

		/// A read of this parameter where a call is made: the nearest place of the type's configuration where the path
		/// key reads one there (`isProvided`), else a fresh configuration (`ValuePath.emptyInitialization`, spelled `<type>()`, on the
		/// engine) for a struct, or `nil` for an override closure.
		func read(isProvided: Bool) -> ValuePath {
			if !isProvided, readsConfigurationStruct {
				.emptyInitialization(type)
			} else {
				.read(PlaceRead(
					argumentLabel: name,
					label: name,
					property: Property(label: name, typeDescription: type),
					source: isProvided ? .binding(label: name) : .nil,
				))
			}
		}

		/// The argument a call hands this parameter.
		func argument(handing value: ValuePath, staysOutsideSendableFunctions: Bool) -> PassedArgument {
			PassedArgument(parameterName: name, type: type, value: value, staysOutsideSendableFunctions: staysOutsideSendableFunctions)
		}
	}

	/// What a built place whose function takes its configuration through `parameter` hands that function: the member
	/// `label` of its parent's configuration where the parent's configuration has a field for it (`parentConfiguration`, a
	/// read of the parent's parameter, or the mock's `safeDIOverrides` at the root), else a read of its own type's parameter,
	/// which resolves to the nearest place of its type above it (`nearestIsProvided`, as the path key reads it), or to
	/// nothing. The function declares the same list as its parameters, so a call and the function it calls come from one
	/// rule.
	static func passedArguments(
		ofBuiltPlaceTaking parameter: ConfigurationParameter,
		label: String,
		parentConfiguration: ValuePath?,
		nearestIsProvided: Bool,
		staysOutsideSendableFunctions: Bool,
	) -> [PassedArgument] {
		let value: ValuePath = if let parentConfiguration {
			.member(label, of: parentConfiguration)
		} else {
			parameter.read(isProvided: nearestIsProvided)
		}
		return [parameter.argument(handing: value, staysOutsideSendableFunctions: staysOutsideSendableFunctions)]
	}

	/// What a closer hands the function it closes on, which takes its configuration through `parameter`: a read of the
	/// closed-on type's parameter, which resolves to the
	/// configuration of the place it closes on, the nearest place of that type above it. Never an absolute path, so alike
	/// places that share a function hand alike closers. `closedOnIsProvided` says whether the path key's closed-on place
	/// read a configuration; where it read none, the read is of nothing, `nil`, as that place was handed.
	static func passedArguments(
		ofCloserOnPlaceTaking parameter: ConfigurationParameter,
		closedOnIsProvided: Bool,
		staysOutsideSendableFunctions: Bool,
	) -> [PassedArgument] {
		[parameter.argument(handing: parameter.read(isProvided: closedOnIsProvided), staysOutsideSendableFunctions: staysOutsideSendableFunctions)]
	}
}

extension MockLowering {
	/// What the mock walk knows, where it starts a built place, about where the type key's form of the place reads its
	/// configuration: the configuration of its parent where the parent's configuration has a field for it, and whether
	/// the path key's place reads the overrides of the nearest place of its type built the same way (`AncestorOverridePath`).
	struct BuiltPlaceConfigurationContext {
		/// The name of the place's field in its parent's configuration, which can be named apart from its label.
		let fieldName: String
		/// The parent's configuration, read where the place's call is made: the parent's own parameter, or `mock()`'s
		/// `safeDIOverrides` at the root; `nil` where the parent's configuration has no field for the place.
		let parentConfiguration: ValuePath?
		/// Whether the place, with no field in its parent's configuration, reads the overrides of the nearest place of its
		/// type around it built the same way.
		let nearestIsProvided: Bool
	}

	/// The read of `mock()`'s `safeDIOverrides`, the configuration of the mock root's children.
	static var mockOverridesRead: ValuePath {
		.rootDeclaration(ReservedName.mockOverridesParameterName)
	}

	/// The type key's form of a built place's configuration: what its call hands its function (`passedArguments(ofBuiltPlaceTaking:…)`),
	/// and the alternatives its construction tries, each override read at an absolute path (`OverrideRead.path`) replaced by
	/// a read of the place's own parameter (its `safeDIBuilder` member, or the parameter itself where it is the override
	/// closure). So alike places of one type that read their configurations at different paths record alike, and a place a
	/// cycle builds again reads the configuration of the nearest place of its type built the same way, as the path key reads it.
	static func relativeConfiguration(
		of node: NodeConfiguration,
		parameter: ConfigurationParameter,
		context: BuiltPlaceConfigurationContext,
		alternatives: [ConstructionAlternative],
		hasFunction: Bool,
		sendableConfigurationTypeNames: Set<String>,
	) -> (passedArguments: [PassedArgument], alternatives: [ConstructionAlternative]) {
		let staysOutsideSendableFunctions = if node.hasConfiguration {
			!sendableConfigurationTypeNames.contains(node.instantiable.concreteInstantiable.asSource)
		} else {
			!node.requiresSendable
		}
		let passedArguments = passedArguments(
			ofBuiltPlaceTaking: parameter,
			label: context.fieldName,
			parentConfiguration: context.parentConfiguration,
			nearestIsProvided: context.nearestIsProvided,
			staysOutsideSendableFunctions: staysOutsideSendableFunctions,
		)
		let ownRead = ValuePath.passedArgument(parameter.name)
		let overrideRead: ValuePath = node.hasConfiguration ? .member(ReservedName.configurationBuilderPropertyName, of: ownRead) : ownRead
		var relativeAlternatives = alternatives.map { alternative in
			ConstructionAlternative(
				closure: overrideRead,
				bindingName: alternative.bindingName,
				requiresAbsent: alternative.requiresAbsent,
				use: alternative.use,
				resultWrapper: alternative.resultWrapper,
			)
		}
		// A place no override reaches, at or beneath the edge of a mocked lazy cycle `computeCycleEdges` leaves out, tries
		// the override a reached place of its type tries, of its own parameter, which its call hands a configuration built
		// afresh, `nil`, or its parent's field of it: so its record, and the function places of its type share, is the same
		// whichever edge the order of type names leaves out, and only what its call hands it differs. A place built in its
		// parent's body reads what it is handed in place (`readPassedConfigurationInPlace(ofBuiltPlaceAt:)`): its parent's
		// field, or the configuration of the nearest place of its type, where there is one, else nothing, since `nil` is no
		// override to try.
		if relativeAlternatives.isEmpty, hasFunction || context.parentConfiguration != nil || context.nearestIsProvided,
		   let alternative = overrideAlternative(reading: overrideRead, resultWrapper: node.overrideResultWrapper)
		{
			relativeAlternatives.append(alternative)
		}
		return (passedArguments: passedArguments, alternatives: relativeAlternatives)
	}
}

extension MockLowering.Walk {
	/// The parameter through which the function of a place of `node` takes the configuration the place reads, under the
	/// one name this root gives the node's type built that way.
	mutating func configurationParameter(of node: MockLowering.NodeConfiguration) -> MockLowering.ConfigurationParameter {
		configurationParameter(ofPlaceOf: node.instantiable.concreteInstantiable, builtWithHandWrittenMock: node.usesMockInitializer, configurationType: MockLowering.configurationType(of: node))
	}

	/// The parameter through which the function of a place of `concreteType`, built with its hand-written mock or not,
	/// takes a configuration of `configurationType`. Every parameter of the walk's records is made here, so that every
	/// name comes from the root's one table.
	mutating func configurationParameter(ofPlaceOf concreteType: TypeDescription, builtWithHandWrittenMock: Bool, configurationType: TypeDescription) -> MockLowering.ConfigurationParameter {
		MockLowering.ConfigurationParameter(
			name: configurationParameterNames.name(ofConfigurationOf: concreteType, builtWithHandWrittenMock: builtWithHandWrittenMock),
			configurationType: configurationType,
		)
	}

	/// Puts the built place recorded at the walk's place in the type key's form of its configuration
	/// (`MockLowering.relativeConfiguration(of:…)`). A public mock's places take another configuration, which its own records hand.
	mutating func relateConfiguration(ofBuiltPlaceAt path: [Int], of node: MockLowering.NodeConfiguration) {
		guard !buildsPublicMock,
		      case var .built(record) = builtRecords[path],
		      let context = builtPlaceConfigurationContexts[path]
		else { return }
		let relative = MockLowering.relativeConfiguration(of: node, parameter: configurationParameter(of: node), context: context, alternatives: record.alternatives, hasFunction: record.hasFunction, sendableConfigurationTypeNames: sendableConfigurationTypeNames)
		record.passedArguments = relative.passedArguments
		// A place whose `@Sendable` function the walk starts reading overrides into locals for is handed a `Sendable` member
		// of a configuration that is not, which its call binds before it calls, as the walk binds the locals before the
		// function, so no `@Sendable` closure around the call captures the configuration.
		if pathsStartingExtraction.contains(path) {
			for index in record.passedArguments.indices where !record.passedArguments[index].staysOutsideSendableFunctions {
				record.passedArguments[index].bindsBeforeCall = true
			}
		}
		record.alternatives = relative.alternatives
		builtRecords[path] = .built(record)
	}
}
