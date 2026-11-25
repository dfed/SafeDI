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
		let hasConfiguration: Bool
		/// Whether the place is built with its type's hand-written mock, whose configuration has another shape.
		let builtWithHandWrittenMock: Bool

		/// The override path the place reads: `path` where its parent's configuration has a field for it
		/// (`isReachable`), else the path of the nearest place of its type above it where both read a configuration or
		/// both a closure and both are built the same way, else `nil`, and the place reads no override.
		static func own(path: String, hasConfiguration: Bool, builtWithHandWrittenMock: Bool, isReachable: Bool, nearest: AncestorOverridePath?) -> AncestorOverridePath? {
			if isReachable {
				AncestorOverridePath(path: path, hasConfiguration: hasConfiguration, builtWithHandWrittenMock: builtWithHandWrittenMock)
			} else if let nearest, nearest.hasConfiguration == hasConfiguration, nearest.builtWithHandWrittenMock == builtWithHandWrittenMock {
				nearest
			} else {
				nil
			}
		}
	}

	/// The passed argument through which a type key function of `concreteType` takes the configuration its place reads.
	/// Its name is one per type, and a passed argument is a declaration inside the function it is handed to, so a read of
	/// the name resolves to the nearest place of the type above it: the rule above, as the engine's nearest declaration.
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

		/// A place built with its type's hand-written mock reads a configuration of another shape than one built with its
		/// initializer (`validateConfigurationsAreBuiltOneWay` leaves out a place beneath a cycle edge), so the two ways take
		/// parameters of two names, and a place reads only the nearest place built its own way (issue #720's shape).
		init(concreteType: TypeDescription, builtWithHandWrittenMock: Bool, configurationType: TypeDescription) {
			name = ReservedName.builderFunctionNamePrefix + concreteType.asIdentifier + (builtWithHandWrittenMock ? "_mockConfiguration" : "_configuration")
			readsConfigurationStruct = !configurationType.isClosure && !configurationType.isOptional
			type = readsConfigurationStruct || configurationType.isOptional ? configurationType : .optional(configurationType)
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

	/// What a built place of `concreteType` that reads a configuration of `configurationType` hands its function: the member
	/// `label` of its parent's configuration where the parent's configuration has a field for it (`parentConfiguration`, a
	/// read of the parent's parameter, or the mock's `safeDIOverrides` at the root), else a read of its own type's parameter,
	/// which resolves to the nearest place of its type above it (`nearestIsProvided`, as the path key reads it), or to
	/// nothing. The function declares the same list as its parameters, so a call and the function it calls come from one
	/// rule.
	static func passedArguments(
		ofBuiltPlaceOf concreteType: TypeDescription,
		label: String,
		builtWithHandWrittenMock: Bool,
		configurationType: TypeDescription?,
		parentConfiguration: ValuePath?,
		nearestIsProvided: Bool,
		staysOutsideSendableFunctions: Bool,
	) -> [PassedArgument] {
		guard let parameter = configurationParameter(ofPlaceOf: concreteType, builtWithHandWrittenMock: builtWithHandWrittenMock, configurationType: configurationType) else { return [] }
		let value: ValuePath = if let parentConfiguration {
			.member(label, of: parentConfiguration)
		} else {
			parameter.read(isProvided: nearestIsProvided)
		}
		return [parameter.argument(handing: value, staysOutsideSendableFunctions: staysOutsideSendableFunctions)]
	}

	/// What a closer hands the function it closes on: a read of the closed-on type's parameter, which resolves to the
	/// configuration of the place it closes on, the nearest place of that type above it. Never an absolute path, so alike
	/// places that share a function hand alike closers. `closedOnIsProvided` says whether the path key's closed-on place
	/// read a configuration; where it read none, the read is of nothing, `nil`, as that place was handed.
	static func passedArguments(
		ofCloser generator: ScopeGenerator,
		closedOnBuiltWithHandWrittenMock: Bool,
		configurationType: TypeDescription?,
		closedOnIsProvided: Bool,
		staysOutsideSendableFunctions: Bool,
	) -> [PassedArgument] {
		guard let closedOn = generator.closedOnDeclaration,
		      let parameter = configurationParameter(ofPlaceOf: closedOn.concreteType, builtWithHandWrittenMock: closedOnBuiltWithHandWrittenMock, configurationType: configurationType)
		else { return [] }
		return [parameter.argument(handing: parameter.read(isProvided: closedOnIsProvided), staysOutsideSendableFunctions: staysOutsideSendableFunctions)]
	}

	/// The parameter a type key function of `concreteType` takes its configuration through, or `nil` where its place reads
	/// no configuration and no override closure.
	static func configurationParameter(ofPlaceOf concreteType: TypeDescription, builtWithHandWrittenMock: Bool, configurationType: TypeDescription?) -> ConfigurationParameter? {
		configurationType.map { ConfigurationParameter(concreteType: concreteType, builtWithHandWrittenMock: builtWithHandWrittenMock, configurationType: $0) }
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
		/// The name of the place's own parameter in the type key's form, where it reads a configuration struct.
		let ownParameterName: String?
		/// The configuration the path key's place reads, `safeDIOverrides.<member>…`, or `nil` where it reads none.
		let pathKeyConfiguration: ValuePath?
	}

	/// The read of `mock()`'s `safeDIOverrides`, the configuration of the mock root's children.
	static var mockOverridesRead: ValuePath {
		.rootDeclaration(ReservedName.mockOverridesParameterName)
	}

	/// The type key's form of a built place's configuration: what its call hands its function (`passedArguments(ofBuiltPlaceOf:…)`),
	/// and the alternatives its construction tries, each override read at an absolute path (`overrideReadPath`) replaced by
	/// a read of the place's own parameter (its `safeDIBuilder` member, or the parameter itself where it is the override
	/// closure). So alike places of one type that read their configurations at different paths record alike, and a place a
	/// cycle builds again reads the configuration of the nearest place of its type built the same way, as the path key reads it.
	static func relativeConfiguration(
		of node: ConstantNode,
		context: BuiltPlaceConfigurationContext,
		alternatives: [ConstructionAlternative],
		sendableConfigurationTypeNames: Set<String>,
	) -> (passedArguments: [PassedArgument], alternatives: [ConstructionAlternative]) {
		let configurationType = configurationType(of: node)
		guard let parameter = configurationParameter(ofPlaceOf: node.instantiable.concreteInstantiable, builtWithHandWrittenMock: node.usesMockInitializer, configurationType: configurationType) else {
			return (passedArguments: [], alternatives: alternatives)
		}
		let staysOutsideSendableFunctions = if node.hasConfiguration {
			!sendableConfigurationTypeNames.contains(node.instantiable.concreteInstantiable.asSource)
		} else {
			!node.requiresSendable
		}
		let passedArguments = passedArguments(
			ofBuiltPlaceOf: node.instantiable.concreteInstantiable,
			label: context.fieldName,
			builtWithHandWrittenMock: node.usesMockInitializer,
			configurationType: configurationType,
			parentConfiguration: context.parentConfiguration,
			nearestIsProvided: context.nearestIsProvided,
			staysOutsideSendableFunctions: staysOutsideSendableFunctions,
		)
		let ownRead = ValuePath.passedArgument(parameter.name)
		let overrideRead: ValuePath = node.hasConfiguration ? .member(ReservedName.configurationBuilderPropertyName, of: ownRead) : ownRead
		let relativeAlternatives = alternatives.map { alternative in
			ConstructionAlternative(
				closure: overrideRead,
				bindingName: alternative.bindingName,
				requiresAbsent: alternative.requiresAbsent,
				use: alternative.use,
				resultWrapper: alternative.resultWrapper,
			)
		}
		return (passedArguments: passedArguments, alternatives: relativeAlternatives)
	}
}

extension MockLowering.Walk {
	/// Puts the built place recorded at the walk's place in the type key's form of its configuration
	/// (`MockLowering.relativeConfiguration(of:…)`). A public mock's places take another configuration, which its own records hand.
	mutating func relateConfiguration(ofBuiltPlaceAt path: [Int], of node: MockLowering.TreeNode) {
		guard !buildsPublicMock,
		      case let .built(constantNode) = node,
		      case var .built(record) = builtRecords[path],
		      let context = builtPlaceConfigurationContexts[path]
		else { return }
		let relative = MockLowering.relativeConfiguration(of: constantNode, context: context, alternatives: record.alternatives, sendableConfigurationTypeNames: sendableConfigurationTypeNames)
		record.passedArguments = relative.passedArguments
		record.alternatives = relative.alternatives
		builtRecords[path] = .built(record)
	}
}

extension MockLowering.Walk {
	/// The override each built place the walk recorded reads in the type key's form, resolved back to the absolute read the
	/// path key makes (`safeDIOverrides.<member>…`), by the place's path of child indices: each place's configuration is what
	/// its call hands it (`BuiltPlaceRecord.passedArguments`), read of its parent's configuration, of the nearest place
	/// around it with the same parameter, or of nothing. A place beneath a place left unrecorded resolves to nothing. What the
	/// shadow comparison holds the relative form to: it must read what the path key reads, at every place.
	func absoluteConfigurationReads() -> [[Int]: ValuePath] {
		var configurationByPath = [[Int]: ValuePath]()
		for path in placePathsInWalkOrder {
			guard case let .built(record) = builtRecords[path], let argument = record.passedArguments.first else { continue }
			if let resolved = resolve(argument.value, at: path) {
				configurationByPath[path] = resolved
			}
		}
		return configurationByPath
	}

	/// The absolute read `value`, handed at the place at `path`, resolves to, or `nil` where it reads nothing: a read of a
	/// parameter is of the nearest place around `path` that takes it, which reads the configuration the path key's place
	/// reads there, so each place is checked against its ancestors as the path key spells them.
	private func resolve(_ value: ValuePath, at path: [Int]) -> ValuePath? {
		switch value {
		case .rootDeclaration:
			return value
		case let .member(member, of: base):
			return resolve(base, at: path).map { .member(member, of: $0) }
		case let .read(read):
			guard case .binding = read.source else { return nil }
			return nearestConfiguration(takingParameterNamed: read.label, around: path)
		case let .passedArgument(name):
			return nearestConfiguration(takingParameterNamed: name, around: path)
		case .optionalMember, .call, .emptyInitialization:
			// A fresh configuration, or anything but a configuration, reads no override.
			return nil
		}
	}

	/// The configuration the path key reads at the nearest place around `path` whose own parameter is named `name`.
	private func nearestConfiguration(takingParameterNamed name: String, around path: [Int]) -> ValuePath? {
		var ancestor = path
		while !ancestor.isEmpty {
			ancestor.removeLast()
			if let context = builtPlaceConfigurationContexts[ancestor], context.ownParameterName == name {
				return context.pathKeyConfiguration
			}
		}
		return nil
	}

	/// The alternatives of the built place at `path`, with each read of the place's own configuration parameter replaced by
	/// the absolute read it resolves to (`absoluteConfigurationReads()`).
	func alternativesReadAbsolutely(at path: [Int], configurationReads: [[Int]: ValuePath]) -> [ConstructionAlternative] {
		guard case let .built(record) = builtRecords[path] else { return [] }
		guard let configuration = configurationReads[path] else { return record.passedArguments.isEmpty ? record.alternatives : [] }
		return record.alternatives.map { alternative in
			let closure: ValuePath = if case let .member(member, of: _) = alternative.closure {
				.member(member, of: configuration)
			} else {
				configuration
			}
			return ConstructionAlternative(closure: closure, bindingName: alternative.bindingName, requiresAbsent: alternative.requiresAbsent, use: alternative.use, resultWrapper: alternative.resultWrapper)
		}
	}
}
