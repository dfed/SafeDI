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

// What a module needs to generate the public mocks of its `@Instantiable(generateMock: .public)` types, beyond what
// an internal mock needs: the access of each parameter and member, proven from the declarations (`TypeAccessProof`),
// the module-level configuration structs the public mocks of a module share, and the construction functions that
// resolve a type's default-valued parameters where the type's own declaration resolves them.

/// What a module's public mocks read from the module as a whole.
struct PublicMockContext: Sendable {
	/// The proof of every type's access over the module's declaration map, which every public mock of the module reads.
	let proof: TypeAccessProof
	/// The comment the module's public mocks' file carries, naming the types their `public` declarations name that SafeDI
	/// reads no declaration of, or `nil` when the run writes none (`SeamResolution.carriesUnreadTypeComment`).
	let unreadTypeComment: UnreadTypeComment?
	/// The module that declares each concrete type, where it is known.
	let moduleNameByType: [TypeDescription: String]
	/// The module the mocks are generated in, when it is known.
	let moduleName: String?
	/// The name of each concrete type's module-level configuration struct (`configurationTypeNames(of:moduleName:)`).
	let configurationTypeNameByType: [TypeDescription: String]
	/// For each `generateMock: .public` type declared inside an extension, the declarations of the extended type that
	/// bound it (`DependencyTreeGenerator.extendedTypeAccessNeeds(of:in:)`), which a public mock needs to be `public`.
	let extendedTypeAccessNeedsByType: [TypeDescription: [AccessNeed]]

	/// The access with which a declaration can name every type in `types`: the narrowest proof among them, a type with
	/// no entry resolved to its plain declaration in the module the mocks are generated in and otherwise read from
	/// `admittedModules`, and the cause of the narrowest.
	func access(ofTypes types: [TypeDescription], admittedModules: Set<String?>) -> TypeAccessProof.ParameterAccess {
		var narrowest = TypeAccessProof.ParameterAccess(level: .public, cause: nil)
		for type in types {
			// The mocks are generated in the module whose files the proof's `isOwnFile` names as its own: a context computed
			// for another module's public mock names none.
			let access = proof.access(ofParameterTyped: type, mentionedFrom: .generatedCode(ofModuleNamed: moduleName, isRunsOwnModule: true), admittedModules: admittedModules)
			if access.level < narrowest.level {
				narrowest = access
			}
		}
		return narrowest
	}

	/// The names of the module-level configuration structs of `concreteTypes`: `__safeDI_<Module>_<Type>_MockConfiguration`,
	/// with each type spelled by `asIdentifier`, or `__safeDI_<Type>_MockConfiguration` when the module is unknown. Two
	/// types whose names collide are named apart by trailing underscores, in sorted type order.
	static func configurationTypeNames(of concreteTypes: some Sequence<TypeDescription>, moduleName: String?) -> [TypeDescription: String] {
		var names = [TypeDescription: String]()
		var takenStems = Set<String>()
		for type in Set(concreteTypes).sorted() {
			var stem = "\(ReservedName.builderFunctionNamePrefix)\(moduleName.map { "\($0)_" } ?? "")\(type.asIdentifier)"
			while takenStems.contains(stem) {
				stem += "_"
			}
			takenStems.insert(stem)
			names[type] = "\(stem)_MockConfiguration"
		}
		return names
	}

	/// The name of the module-level function that forwards to `type`'s provider of the default of `label`, which a
	/// public declaration's default argument can name without naming `type`.
	func forwarderName(of type: TypeDescription, label: String) -> String {
		let configurationTypeName = configurationTypeNameByType[type] ?? "\(ReservedName.builderFunctionNamePrefix)\(type.asIdentifier)_MockConfiguration"
		let stem = configurationTypeName.dropLast("_MockConfiguration".count)
		return "\(stem)_mockDefault_\(label)".spelledAsJoinedIdentifier
	}

	/// `type`, which a member of `enclosingType` spells, qualified so that a declaration outside `enclosingType` names the
	/// same type (`TypeAccessProof.qualifyingNestedTypes(in:writtenWithin:)`): a module-level configuration spells it
	/// so, and the access of a type nested in `enclosingType` is its nested declaration's.
	func qualifyingNestedTypes(in type: TypeDescription, writtenWithin enclosingType: TypeDescription) -> TypeDescription {
		proof.qualifyingNestedTypes(in: type, writtenWithin: enclosingType)
	}

	/// The name of the static method in a type's extension that evaluates the default of `label` for its configuration.
	static func providerName(label: String) -> String {
		"\(ReservedName.builderFunctionNamePrefix)mockDefault_\(label)".spelledAsJoinedIdentifier
	}

	/// The name of the static method in a public mock's type's extension that evaluates the default of `label` of the
	/// type's own construction, apart from `providerName(label:)`, which the type's configuration declares when the type
	/// is also built in a public mock's tree.
	static func rootProviderName(label: String) -> String {
		"\(ReservedName.builderFunctionNamePrefix)publicMockDefault_\(label)".spelledAsJoinedIdentifier
	}
}

/// A stored member of a generated public struct (`SafeDIOverrides`, or a module-level configuration), with the
/// access its types allow.
struct PublicStructMember {
	/// The member's name, which is also its initializer parameter's label.
	let name: String
	/// The member's stored type.
	let typeSource: String
	/// The type of the initializer parameter that sets it, which an autoclosure parameter spells otherwise.
	let parameterTypeSource: String
	/// The member's access: the narrowest its types are proven at.
	let access: AccessLevel
	/// The default of the initializer parameter that sets it.
	let defaultExpression: String
	/// What an initializer that does not take the member assigns it.
	let omittedValue: String
	/// Whether the initializer parameter has no argument label.
	let isUnlabeled: Bool
	/// The member's documentation comment, when it has one.
	let documentation: String?
}

extension ScopeGenerator {
	/// The access levels at which a public struct with `members` has an initializer, widest first: `public`, which may
	/// take no member, and each narrower level a member has.
	static func publicInitializerLevels(of members: [PublicStructMember]) -> [AccessLevel] {
		[.public] + Set(members.map(\.access)).filter { $0 < .public }.sorted(by: >)
	}

	/// The initializers and stored members of a public struct, indented by `indent`: one initializer per level of
	/// `publicInitializerLevels(of:)`, each taking every member at or above its level, in member order, and assigning
	/// each member it omits its `omittedValue`.
	static func publicStructBody(members: [PublicStructMember], indent: String) -> [String] {
		let memberIndent = "\(indent)\(standardIndent)"
		var lines = [String]()
		for level in publicInitializerLevels(of: members) {
			let takenMembers = members.filter { $0.access >= level }
			let levelPrefix = level == .internal ? "" : "\(level.spelledOnGeneratedDeclaration) "
			if takenMembers.isEmpty {
				lines.append("\(indent)\(levelPrefix)init() {")
			} else {
				lines.append("\(indent)\(levelPrefix)init(")
				lines.append(takenMembers.map { member in
					"\(memberIndent)\(member.isUnlabeled ? "_ " : "")\(member.name): \(member.parameterTypeSource) = \(member.defaultExpression)"
				}.joined(separator: ",\n"))
				lines.append("\(indent)) {")
			}
			for member in members {
				let value = member.access >= level ? member.name : member.omittedValue
				lines.append("\(memberIndent)self.\(member.name) = \(value)")
			}
			lines.append("\(indent)}")
			lines.append("")
		}
		for member in members {
			if let documentation = member.documentation {
				lines.append("\(indent)/// \(documentation)")
			}
			let accessPrefix = member.access == .internal ? "" : "\(member.access.spelledOnGeneratedDeclaration) "
			lines.append("\(indent)\(accessPrefix)let \(member.name): \(member.typeSource)")
		}
		return lines
	}

	/// The module-level configuration struct that every public mock of the module shares for `node`'s type, and the
	/// construction function in the type's extension that resolves the type's defaults where its declaration does.
	/// - Parameters:
	///   - handWrittenMockDefaultParameters: The defaults of the type's hand-written mock, whose expressions the
	///     construction function resolves the fields of the same label and type with, whichever way it constructs.
	static func publicConfigurationDeclarations(
		for node: MockParameterNode,
		configurationTypeName: String,
		context: PublicMockContext,
		cycleEdges: Set<CycleEdge>,
		requiresSendable: Bool,
		handWrittenMockDefaultParameters: [MockParameterNode.DefaultParameter],
	) -> String {
		let concreteType = node.concreteType
		let admittedModules: Set<String?> = [context.moduleName, context.moduleNameByType[concreteType]]
		let sendableAnnotation = requiresSendable ? "@Sendable " : ""
		var members = [PublicStructMember]()

		// Each child the type builds itself, as an internal configuration struct holds it, except a child beneath a
		// cycle edge, whose struct would contain itself.
		let nonCycleChildren = node.propertyChildren.filter { child in
			!cycleEdges.contains(CycleEdge(parent: concreteType.asSource, child: child.concreteType.asSource))
		}
		let childLabelMap = disambiguatePropertyLabels(for: nonCycleChildren)
		for child in nonCycleChildren {
			members.append(publicMember(
				for: child,
				named: disambiguatedLabel(for: child, labelMap: childLabelMap),
				context: context,
				admittedModules: admittedModules,
				requiresSendable: requiresSendable,
			))
		}

		// Each default-valued parameter: optional, with `nil` meaning the declaration's default, unless the parameter is
		// optional itself, which the member holds as it is, defaulting to what the declaration's default evaluates to.
		// The struct is declared at the module's top level, where a type nested in the type is named qualified.
		for defaultParameter in publicDefaultParameters(of: node, handWrittenMockDefaultParameters: handWrittenMockDefaultParameters) {
			let valueType = context.qualifyingNestedTypes(in: defaultParameter.typeDescription, writtenWithin: concreteType)
			let access = context.access(ofTypes: [valueType], admittedModules: admittedModules).level
			if defaultParameter.typeDescription.isOptional {
				let isNilLiteral = defaultParameter.defaultExpression == "nil"
				let provider = "\(concreteType.asSource).\(PublicMockContext.providerName(label: defaultParameter.label))()"
				let forwarder = "\(context.forwarderName(of: concreteType, label: defaultParameter.label))()"
				members.append(publicDefaultMember(
					name: defaultParameter.label,
					valueType: valueType,
					access: access,
					defaultExpression: isNilLiteral ? "nil" : (access == .public ? forwarder : provider),
					omittedValue: isNilLiteral ? "nil" : provider,
					requiresSendable: requiresSendable,
					documentation: "The default of `\(concreteType.asSource)`'s `\(defaultParameter.label.spelledWithoutBackticks)` unless set.",
				))
			} else {
				members.append(publicDefaultMember(
					name: defaultParameter.label,
					valueType: .optional(valueType),
					access: access,
					defaultExpression: "nil",
					omittedValue: "nil",
					requiresSendable: requiresSendable,
					documentation: "`nil` keeps the default of `\(concreteType.asSource)`'s `\(defaultParameter.label.spelledWithoutBackticks)`.",
				))
			}
		}

		// The builder, which the type's own type and every type its arguments name keep from being wider. It takes each
		// argument as the type's member declares it, named as the members above name their types.
		let builderParameterTypes = node.callSiteArguments.map { argument in
			context.qualifyingNestedTypes(in: argument.typeDescription.asFunctionParameter, writtenWithin: concreteType)
		}
		let builderAccess = context.access(ofTypes: builderParameterTypes + [concreteType], admittedModules: admittedModules).level
		let builderType = "(\(sendableAnnotation)(\(builderParameterTypes.map(\.asSource).joined(separator: ", "))) -> \(concreteType.asSource))?"
		members.append(PublicStructMember(
			name: ReservedName.configurationBuilderPropertyName,
			typeSource: builderType,
			parameterTypeSource: builderType,
			access: builderAccess,
			defaultExpression: "nil",
			omittedValue: "nil",
			isUnlabeled: true,
			documentation: "Overrides how `\(concreteType.asSource)` is constructed. Parameters match the type’s initializer or custom mock method.",
		))

		var lines = [String]()
		lines.append("/// Configuration for how `\(concreteType.asSource)` is constructed within the public mock trees of \(context.moduleName.map { "module `\($0)`" } ?? "this module").")
		lines.append("public struct \(configurationTypeName) {")
		lines.append(contentsOf: publicStructBody(members: members, indent: standardIndent))
		lines.append("}")
		lines.append("")
		lines.append(contentsOf: publicConstructionFunctions(
			for: node,
			builderType: builderType,
			context: context,
			handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
		))
		return lines.joined(separator: "\n")
	}

	/// The default-valued parameters of `node`, each with the expression a public mock resolves it with: its type's
	/// hand-written mock's default of the same label and type when the mock declares one, as the type's internal
	/// configuration struct resolves it, whichever way the node is built.
	static func publicDefaultParameters(
		of node: MockParameterNode,
		handWrittenMockDefaultParameters: [MockParameterNode.DefaultParameter],
	) -> [MockParameterNode.DefaultParameter] {
		node.defaultParameters.map { defaultParameter in
			guard let handWrittenDefault = handWrittenMockDefaultParameters.first(where: {
				$0.isDefault(forParameterLabeled: defaultParameter.label, ofType: defaultParameter.typeDescription)
			}) else { return defaultParameter }
			return handWrittenDefault
		}
	}

	/// The member of a public struct that configures how `child` is built: its own module-level configuration when it
	/// has one, which is public, or else an optional closure, as visible as the types it names.
	static func publicMember(
		for child: MockParameterNode,
		named name: String,
		context: PublicMockContext,
		admittedModules: Set<String?>,
		requiresSendable: Bool,
	) -> PublicStructMember {
		if let publicMockOverridesMember = child.publicMockOverridesMember(sendable: requiresSendable || child.requiresSendable) {
			// The public mock another module generated takes its own `SafeDIOverrides`, which is `public`.
			return PublicStructMember(
				name: name,
				typeSource: publicMockOverridesMember.type,
				parameterTypeSource: publicMockOverridesMember.type,
				access: .public,
				defaultExpression: publicMockOverridesMember.defaultValue,
				omittedValue: publicMockOverridesMember.defaultValue,
				isUnlabeled: false,
				documentation: nil,
			)
		} else if child.needsConfigurationStruct, let configurationTypeName = context.configurationTypeNameByType[child.concreteType] {
			return PublicStructMember(
				name: name,
				typeSource: configurationTypeName,
				parameterTypeSource: configurationTypeName,
				access: .public,
				defaultExpression: ".init()",
				omittedValue: ".init()",
				isUnlabeled: false,
				documentation: nil,
			)
		} else {
			let childSendable = (requiresSendable || child.requiresSendable) ? "@Sendable " : ""
			let closureType = "(\(childSendable)\(child.builderClosureType))?"
			let access = context.access(
				ofTypes: child.callSiteArguments.map(\.typeDescription) + [child.instantiatedTypeDescription],
				admittedModules: admittedModules,
			).level
			return PublicStructMember(
				name: name,
				typeSource: closureType,
				parameterTypeSource: closureType,
				access: access,
				defaultExpression: "nil",
				omittedValue: "nil",
				isUnlabeled: false,
				documentation: nil,
			)
		}
	}

	/// A member holding a default-valued parameter's value of `valueType`. A struct a `@Sendable` builder function reads
	/// holds a `@Sendable` closure that returns the value, which its initializer takes as an autoclosure, so that the
	/// function captures no value whose type may not be `Sendable`.
	static func publicDefaultMember(
		name: String,
		valueType: TypeDescription,
		access: AccessLevel,
		defaultExpression: String,
		omittedValue: String,
		requiresSendable: Bool,
		documentation: String,
	) -> PublicStructMember {
		if requiresSendable {
			PublicStructMember(
				name: name,
				typeSource: "@Sendable () -> \(valueType.asSource)",
				parameterTypeSource: "@autoclosure @escaping @Sendable () -> \(valueType.asSource)",
				access: access,
				defaultExpression: autoclosureDefault(defaultExpression),
				omittedValue: "{ \(omittedValue) }",
				isUnlabeled: false,
				documentation: documentation,
			)
		} else {
			PublicStructMember(
				name: name,
				typeSource: valueType.asSource,
				parameterTypeSource: valueType.asSource,
				access: access,
				defaultExpression: defaultExpression,
				omittedValue: omittedValue,
				isUnlabeled: false,
				documentation: documentation,
			)
		}
	}

	/// The name of the construction function a node's type is built with in a public mock: `__safeDI_mock` when it is
	/// built with its hand-written mock, else `__safeDI_init`.
	static func publicConstructionFunctionName(of node: MockParameterNode) -> String {
		"\(ReservedName.builderFunctionNamePrefix)\(node.useMockInitializer ? "mock" : "init")"
	}

	/// The extension of `node`'s type that holds the function a public mock builds it with and the providers of its
	/// optional defaults, followed by the module-level forwarders of the public ones. Each type their signatures spell is
	/// qualified as the module-level configuration qualifies it: an extension of a nested type sees the type's own members,
	/// but not those of the types enclosing it, which its declaration's members see.
	static func publicConstructionFunctions(
		for node: MockParameterNode,
		builderType: String,
		context: PublicMockContext,
		handWrittenMockDefaultParameters: [MockParameterNode.DefaultParameter],
	) -> [String] {
		let concreteType = node.concreteType
		let admittedModules: Set<String?> = [context.moduleName, context.moduleNameByType[concreteType]]
		let dependencyLabels = Set(node.dependencies.map(\.property.label))
		let defaultParameters = publicDefaultParameters(of: node, handWrittenMockDefaultParameters: handWrittenMockDefaultParameters)
		// safedi-source-rule: allow uniqueKeysWithValues — the labels of one function's parameters are distinct.
		let defaultParametersByLabel = Dictionary(uniqueKeysWithValues: defaultParameters.map { ($0.label, $0) })
		func qualified(_ type: TypeDescription) -> TypeDescription {
			context.qualifyingNestedTypes(in: type, writtenWithin: concreteType)
		}
		var parameters = [String]()
		var resolutions = [String]()
		var builderArguments = [String]()
		var constructionArguments = [String]()
		for argument in node.callSiteArguments {
			let name = argument.innerLabel
			if !dependencyLabels.contains(argument.innerLabel), let defaultParameter = defaultParametersByLabel[argument.label] {
				if defaultParameter.typeDescription.isOptional {
					parameters.append("\(name.spelledAsArgumentLabel): \(qualified(defaultParameter.typeDescription).asSource)")
				} else {
					parameters.append("\(name.spelledAsArgumentLabel): \(TypeDescription.optional(qualified(defaultParameter.typeDescription)).asSource)")
					resolutions.append("\(standardIndent)\(standardIndent)let \(name) = \(name) ?? (\(defaultParameter.defaultExpression))")
				}
			} else {
				parameters.append("\(name.spelledAsArgumentLabel): \(qualified(argument.typeDescription.asFunctionParameter).asSource)")
			}
			builderArguments.append(name)
			constructionArguments.append(argument.label == "_" ? name : "\(argument.label.spelledAsArgumentLabel): \(name)")
		}
		parameters.append("\(ReservedName.configurationBuilderPropertyName): \(builderType)")
		let construction = if node.useMockInitializer {
			"\(concreteType.asSource).\(node.customMockName ?? InstantiableVisitor.mockMethodName)(\(constructionArguments.joined(separator: ", ")))"
		} else if node.isExtensionBased {
			"\(concreteType.asSource).\(InstantiableVisitor.instantiateMethodName)(\(constructionArguments.joined(separator: ", ")))"
		} else {
			"\(concreteType.asSource)(\(constructionArguments.joined(separator: ", ")))"
		}
		let returnType = node.useMockInitializer ? node.instantiatedTypeDescription.asSource : concreteType.asSource
		let builderName = ReservedName.configurationBuilderPropertyName
		let optionalDefaultParameters = defaultParameters.filter { $0.typeDescription.isOptional && $0.defaultExpression != "nil" }
		var lines = [String]()
		lines.append("extension \(concreteType.asSource) {")
		for defaultParameter in optionalDefaultParameters {
			lines.append("\(standardIndent)nonisolated static func \(PublicMockContext.providerName(label: defaultParameter.label))() -> \(qualified(defaultParameter.typeDescription).asSource) { \(defaultParameter.defaultExpression) }")
		}
		// The function mirrors the isolation the member it calls spells, so a caller that can call the member can call it.
		let isolationPrefix = node.constructionIsolation.map { "\($0) " } ?? ""
		lines.append("\(standardIndent)\(isolationPrefix)static func \(publicConstructionFunctionName(of: node))(\(parameters.joined(separator: ", "))) -> \(returnType) {")
		lines.append(contentsOf: resolutions)
		lines.append("\(standardIndent)\(standardIndent)\(resolutions.isEmpty ? "" : "return ")if let \(builderName) { \(builderName)(\(builderArguments.joined(separator: ", "))) } else { \(construction) }")
		lines.append("\(standardIndent)}")
		lines.append("}")
		// A public member's default names the provider through a module-level function, which a public declaration's
		// default argument can name without naming the type, which may be narrower than `public`.
		let optionalDefaultValueTypes = optionalDefaultParameters.map { defaultParameter in
			(label: defaultParameter.label, valueType: qualified(defaultParameter.typeDescription))
		}
		for (label, valueType) in optionalDefaultValueTypes where context.access(ofTypes: [valueType], admittedModules: admittedModules).level == .public {
			lines.append("@usableFromInline nonisolated func \(context.forwarderName(of: concreteType, label: label))() -> \(valueType.asSource) { \(concreteType.asSource).\(PublicMockContext.providerName(label: label))() }")
		}
		return lines
	}
}

extension ScopeGenerator {
	/// The nodes at a mock root's level that the mock builds for dependencies the mocked type's tree receives, which a
	/// public mock takes as parameters that default to `nil`: every node but those of the mocked type's own
	/// `@Instantiated` dependencies, including one the mock builds as the `LazilyInstantiated` its tree receives.
	static func publicMockPromotedNodes(of instantiable: Instantiable, in nodes: [MockParameterNode]) -> [MockParameterNode] {
		let ownProperties = Set(instantiable.dependencies.lazy.filter { dependency in
			switch dependency.source {
			case .instantiated:
				true
			case .received, .aliased, .forwarded:
				false
			}
		}.map(\.property))
		return nodes.filter { node in
			!ownProperties.contains(node.property)
				&& !(node.property.propertyType.isLazilyInstantiated && node.typeDescription.lazilyInstantiatedInstanceType.map {
					ownProperties.contains(Property(label: node.propertyLabel, typeDescription: $0))
				} ?? false)
		}
	}

	/// The parameter a public mock takes for a node it builds for a received dependency: the node's value, optional,
	/// which is the instance of a lazily instantiated node, since no parameter of a public mock is `LazilyInstantiated`.
	static func publicMockParameterProperty(of node: MockParameterNode) -> Property {
		let valueType = if node.property.propertyType.isLazilyInstantiated {
			node.typeDescription.lazilyInstantiatedInstanceType ?? node.typeDescription
		} else {
			node.typeDescription
		}
		return Property(label: node.propertyLabel, typeDescription: .optional(valueType.unwrapped))
	}
}

/// How the body of a public mock differs from an internal mock's, passed down its tree.
struct PublicMockEmission: Sendable {
	/// For each node at the mock root's level that the mock builds for a received dependency, the parameter that
	/// holds a value its caller passed instead, by the node's property. Empty beneath the mock root's level.
	let promotedParameterNames: [Property: String]
	/// What the module's public mocks share.
	let context: PublicMockContext
	/// The concrete types whose configurations a `@Sendable` builder function reads, which hold each default as a
	/// `@Sendable` closure.
	let sendableConfigurationTypeNames: Set<String>

	/// The emission beneath the mock root's level, where no node is built for a received dependency.
	var beneathRoot: PublicMockEmission {
		PublicMockEmission(promotedParameterNames: [:], context: context, sendableConfigurationTypeNames: sendableConfigurationTypeNames)
	}
}

extension ScopeGenerator {
	/// The arguments a public mock passes the construction function of `node`, which needs a configuration: each of its
	/// call-site arguments, a default read from its configuration where the override is reachable, or else `nil` for a
	/// non-optional default, which the function resolves, and the provider's value for an optional one.
	static func publicBuilderArguments(
		for node: MockParameterNode,
		nodePath: String,
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
		uncoveredDependencyNames: [String: [TypeDescription: String]],
		sendableOverrideExtractor: SendableOverrideExtractor?,
		overrideReachable: Bool,
		emission: PublicMockEmission,
	) -> [String] {
		// Each label names one dependency: `validateDependencyLabelsAreDistinct` rejects a declaration in a generated tree that repeats one.
		let dependenciesByLabel = Dictionary(grouping: node.dependencies, by: \.property.label).compactMapValues(\.first)
		let defaultParametersByLabel = Dictionary(grouping: node.defaultParameters, by: \.label).compactMapValues(\.first)
		let relativePath = nodePath
			.replacingOccurrences(of: "\(ReservedName.mockOverridesParameterName).", with: "")
			.replacingOccurrences(of: ".", with: "_")
		let storesDefaultsAsClosures = emission.sendableConfigurationTypeNames.contains(node.concreteType.asSource)
		return node.callSiteArguments.map { argument in
			if let dependency = dependenciesByLabel[argument.innerLabel] {
				return dependencyArgument(
					argument,
					of: dependency,
					for: node,
					lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
					uncoveredDependencyNames: uncoveredDependencyNames,
				)
			} else if overrideReachable {
				let expression = if let sendableOverrideExtractor {
					sendableOverrideExtractor.extract("\(nodePath).\(argument.label)", localNameSuffix: "\(relativePath)_\(argument.label)")
				} else {
					"\(nodePath).\(argument.label)"
				}
				return storesDefaultsAsClosures ? "\(expression)()" : expression
			} else if let defaultParameter = defaultParametersByLabel[argument.label],
			          defaultParameter.typeDescription.isOptional,
			          defaultParameter.defaultExpression != "nil"
			{
				// No configuration holds the default beneath a pruned edge, so the provider evaluates it.
				return "\(node.concreteType.asSource).\(PublicMockContext.providerName(label: argument.label))()"
			} else {
				return "nil"
			}
		}
	}

	/// The expression that builds `node`, which needs a configuration, in a public mock: a call of its construction
	/// function (`publicConstructionFunctions`), passed `overrideExpression`'s builder, wrapped in the existential an
	/// erased node is declared as.
	static func publicConstructionExpression(
		for node: MockParameterNode,
		overrideExpression: String?,
		arguments: [String],
	) -> String {
		let labeledArguments = zip(node.callSiteArguments, arguments).map { argument, value in
			"\(argument.innerLabel.spelledAsArgumentLabel): \(value)"
		} + ["\(ReservedName.configurationBuilderPropertyName): \(overrideExpression ?? "nil")"]
		let call = "\(node.concreteType.asSource).\(publicConstructionFunctionName(of: node))(\(labeledArguments.joined(separator: ", ")))"
		return node.erasedToConcreteExistential ? "\(node.concreteExistentialType.asSource)(\(call))" : call
	}

	/// An expression that evaluates to the value the caller passed as `parameterName`, when it passed one, and
	/// otherwise to `construction`, which may be an `if` expression itself.
	static func passing(_ parameterName: String, orBuilding construction: String) -> String {
		if construction.hasPrefix("if ") {
			"if let \(parameterName) { \(parameterName) } else \(construction)"
		} else {
			"if let \(parameterName) { \(parameterName) } else { \(construction) }"
		}
	}
}

/// A parameter of a public mock's `mock()`, which every tier at or narrower than its access takes.
struct PublicMockParameter: Sendable {
	/// How a parameter defaults, which a call depends on and the guard hashes.
	enum DefaultKind: String, Sendable {
		/// The caller must pass it.
		case none
		/// `nil`, meaning "build it as the mock does" or "the declaration's default".
		case nilValue = "nil"
		/// An expression the declaration wrote, kept as written (a magic literal).
		case expression
		/// A provider's value: the declaration's default, evaluated where the declaration resolves it.
		case provider
	}

	/// The parameter's name, which is also its argument label.
	let name: String
	/// The parameter's type as the signature spells it.
	let type: TypeDescription
	/// `type` as SafeDI proves its access, which `UnreadTypeComment` checks: a default-valued parameter of the mocked
	/// type's construction, which `mock()` spells as written in the type's extension, names each type nested in the type
	/// qualified (`TypeAccessProof.qualifyingNestedTypes(in:writtenWithin:)`); every other parameter's is `type`.
	let provenType: TypeDescription
	/// The parameter's type as the signature spells it, `@escaping` and `@autoclosure` included.
	let typeSource: String
	/// The default, as source after ` = `, or `nil` for none.
	let defaultSource: String?
	let defaultKind: DefaultKind
	/// The narrowest access its types are proven at, which is the narrowest tier that takes it.
	let access: AccessLevel
	/// How the narrowest of its types is proven, when that is narrower than `public`.
	var accessCause: TypeAccessProof.Cause?
	/// For a parameter on no tier (`PublicMockPlan.noTierParameters`), the call in the mock's tree of another module's
	/// public mock whose tier omits it.
	var nestedOmission: NestedOmission?

	/// A call of another module's public mock, in a public mock's tree, whose tier omits a parameter that nothing else
	/// in the tree receives, so that no tier of the public mock takes it.
	struct NestedOmission: Sendable {
		/// The type whose public mock the call calls.
		let type: TypeDescription
		/// The tier the call reaches.
		let tier: AccessLevel
		/// The tier of the called mock that takes the parameter.
		let parameterAccess: AccessLevel
		let declaringModule: ModuleIdentity
		let callerModule: ModuleIdentity
		let requirement: AccessRequirement
		/// The declarations in the called mock's tree that receive the parameter.
		let receivers: [(declaringType: TypeDescription, dependency: Dependency)]
	}

	/// What the parameter stands for, which decides what a mock tree that calls the public mock passes for it.
	let role: Role
	/// For a received dependency taken as `T? = nil`, whether the mock builds it when passed `nil`, rather than passing
	/// `nil` on to the receivers in its tree, which receive it only if available.
	var isBuiltWhenNil = false
	/// For a dependency the mock builds when passed `nil` as a `LazilyInstantiated` or `SendableLazilyInstantiated`,
	/// taken by value, the wrapper it builds, which a calling mock that can build it builds in its place, as the inline
	/// mock would, and passes the instance of.
	var builtWrapper: Property?
	/// For the builder of a hole in the mock's tree, the hole, which a module calling the mock that sees a type that
	/// fulfills it fills.
	var hole: SeamSignature.Hole?

	/// What a parameter of a public mock stands for.
	enum Role: Sendable {
		/// The mocked type's `@Forwarded` property, which a caller building the type with an `Instantiator` is handed.
		case forwarded(Property)
		/// A default-valued parameter of the type's construction, which a calling mock tree never passes.
		case constructionDefault
		/// A dependency the mocked type's tree receives, received as `property`: required where the mock cannot build
		/// it, and otherwise taken as `T? = nil`, which the mock builds when `nil`.
		case received(Property, isRequired: Bool)
		/// The `SafeDIOverrides` of the mock's tree.
		case overrides
	}
}

/// What a public mock (`generateMock: .public`) generates beyond an internal mock's body.
struct PublicMockPlan: Sendable {
	/// The parameters of the narrowest tier, which takes every parameter, in signature order.
	let parameters: [PublicMockParameter]
	/// The parameters on no tier: what only the calls of other modules' public mocks in the tree receive, which every
	/// such call's tier omits. No tier takes them and the guard hashes none, but a caller's leaf declares them as it
	/// declares an omitted parameter, so that a caller holding a value for one is told the mock would drop it.
	var noTierParameters = [PublicMockParameter]()
	/// The tiers, widest first: `public`, then each narrower access a parameter has.
	let tiers: [AccessLevel]
	/// The empty enum every call names, whose name hashes the signature.
	let guardTypeName: String
	/// The members of `SafeDIOverrides` that hold the mocked type's own optional-typed default-valued parameters.
	let defaultFields: [PublicStructMember]
	/// The static methods in the mocked type's extension that evaluate its own optional-typed defaults.
	let providerDeclarations: [String]
	/// The lines that resolve each parameter taken as `T? = nil` in place of a non-optional default, before the tree.
	let defaultResolutions: [String]
	/// The parameter each node at the mock root's level built for a received dependency is passed by.
	let promotedParameterNames: [Property: String]
	/// What the construction of the mocked type passes for each of its own default-valued parameters, by label.
	let constructionDefaultValues: [String: String]
	/// The holes of the mock's tree, whose builders `mock()` takes, in builder-label order.
	var holes = [SeamSignature.Hole]()

	/// The parameters the tier at `tier` takes.
	func parameters(ofTier tier: AccessLevel) -> [PublicMockParameter] {
		parameters.filter { $0.access >= tier }
	}
}

extension ScopeGenerator {
	/// The plan of the public mock of `instantiable`, a mock root with `parameters`, named by `parameterNames`.
	/// - Parameter forwardedParameterMockDefaults: The name of the hand-written mock that a forwarded parameter of its
	///   type defaults to, by type (`MockScopes.forwardedParameterMockDefaults`).
	static func publicMockPlan(
		of instantiable: Instantiable,
		parameters: MockRootParameters,
		parameterNames: MockRootParameterNames,
		forwardedParameterMockDefaults: [TypeDescription: String],
		context: PublicMockContext,
	) -> PublicMockPlan {
		// The value an internal mock's forwarded parameter defaults to, which a public mock takes as `T? = nil`. Each
		// label names one argument.
		var constructionDefaults = [String: String]()
		for argument in parameters.rootConstructionInitializer?.arguments ?? [] {
			constructionDefaults[argument.innerLabel] = argument.defaultValueExpression
		}
		var forwardedDefaults = [String: (expression: String, isHandWrittenMock: Bool)]()
		for dependency in parameters.forwardedDependencies {
			if let defaultExpression = constructionDefaults[dependency.property.label] {
				forwardedDefaults[dependency.property.label] = (defaultExpression, false)
			} else if let mockMethodName = forwardedParameterMockDefaults[dependency.property.typeDescription] {
				forwardedDefaults[dependency.property.label] = ("\(dependency.property.typeDescription.asSource).\(mockMethodName)()", true)
			}
		}
		let treePropertyNodes = parameters.parameterTree.propertyNodes
		var plan = publicMockPlan(
			of: instantiable,
			forwardedDependencies: parameters.forwardedDependencies,
			forwardedDefaults: forwardedDefaults,
			rootDefaultParameters: parameters.rootDefaultParameters,
			flatReceivedParameters: zip(parameters.flatReceivedProperties, parameterNames.flatReceivedNames).map { (property: $0, name: $1) },
			flatUncoveredParameters: parameters.flatUncoveredParameters,
			promotedNodes: publicMockPromotedNodes(of: instantiable, in: treePropertyNodes).map { node in
				(node: node, name: disambiguatedLabel(for: node, labelMap: parameters.rootLabelMap))
			},
			onlyIfAvailableOverrides: parameterNames.onlyIfAvailableOverrides,
			parameterTree: parameters.parameterTree,
			passedUpHoles: parameters.parameterTree.passedUpHolesByBuilder,
			sendablePassedUpBuilders: parameters.parameterTree.passedUpBuildersCapturedBySendableFunctions,
			// A public mock takes each property received only if available as a parameter, so only the tree's nodes make
			// a `SafeDIOverrides`.
			hasOverrides: !treePropertyNodes.isEmpty,
			context: context,
		)
		plan.noTierParameters = noTierParameters(in: parameters.parameterTree, leftOut: parameters.receivedOnlyByPublicMockCallsLeftOut)
		return plan
	}

	/// The parameters on no tier of a public mock whose tree is `items` (see `PublicMockPlan.noTierParameters`): each
	/// property of `leftOut` that a call of another module's public mock in the tree omits, once per label, in tree order.
	private static func noTierParameters(in items: [MockTreeItem], leftOut: Set<Property>) -> [PublicMockParameter] {
		guard !leftOut.isEmpty else { return [] }
		var noTierParameters = [PublicMockParameter]()
		var labels = Set<String>()
		// Depth first, in tree order, on a stack of its own, since a mock tree can be as deep as the module has types.
		var nodesToVisit = Array(items.propertyNodes.reversed())
		while let node = nodesToVisit.popLast() {
			if let publicMockCall = node.publicMockCall {
				for parameter in publicMockCall.omittedParameters {
					guard case let .received(property, _) = parameter.role,
					      leftOut.contains(property),
					      labels.insert(property.label).inserted
					else { continue }
					var noTierParameter = PublicMockParameter(
						name: property.label,
						type: property.typeDescription,
						provenType: property.typeDescription,
						typeSource: property.typeDescription.asSource,
						defaultSource: "nil",
						defaultKind: .nilValue,
						access: parameter.access,
						accessCause: parameter.accessCause,
						role: .received(property, isRequired: false),
					)
					noTierParameter.nestedOmission = parameter.nestedOmission ?? PublicMockParameter.NestedOmission(
						type: publicMockCall.type,
						tier: publicMockCall.tier,
						parameterAccess: parameter.access,
						declaringModule: publicMockCall.declaringModule,
						callerModule: publicMockCall.callerModule,
						requirement: publicMockCall.requirement,
						receivers: (publicMockCall.receiversByLabel[property.label] ?? []).filter { receiver in
							receiver.dependency.property.label == property.label && receiver.dependency.source.isReceived
						},
					)
					noTierParameters.append(noTierParameter)
				}
			}
			nodesToVisit.append(contentsOf: node.propertyChildren.reversed())
		}
		return noTierParameters
	}

	/// The plan of a public mock of `instantiable` whose internal mock would take the given parameters.
	/// - Parameters:
	///   - forwardedDefaults: The default an internal mock gives each forwarded parameter, by label: the construction
	///     initializer's default (`isHandWrittenMock` false) or the call of the forwarded type's hand-written mock.
	///   - hasOverrides: Whether the mock has a `SafeDIOverrides`, which holds the mocked type's own optional-typed
	///     defaults unless `mock()` is isolated to a global actor; otherwise each is a parameter defaulting to its
	///     provider.
	static func publicMockPlan(
		of instantiable: Instantiable,
		forwardedDependencies: [Dependency],
		forwardedDefaults: [String: (expression: String, isHandWrittenMock: Bool)],
		rootDefaultParameters: [MockRootParameters.RootDefaultParameter],
		flatReceivedParameters: [(property: Property, name: String)],
		flatUncoveredParameters: [MockRootParameters.UncoveredParameter],
		promotedNodes: [(node: MockParameterNode, name: String)],
		onlyIfAvailableOverrides: [OnlyIfAvailableOverride],
		parameterTree: [MockTreeItem],
		passedUpHoles: [Property: SeamSignature.Hole],
		sendablePassedUpBuilders: Set<Property>,
		hasOverrides: Bool,
		context: PublicMockContext,
	) -> PublicMockPlan {
		let typeName = instantiable.concreteInstantiable.asSource
		let ownModules: Set<String?> = [context.moduleName, instantiable.moduleName]
		let receiverModulesByLabel = receiverModules(in: parameterTree, context: context)
		// The cause of each access computed, by type and receive label, which a parameter of that access records.
		var accessCauses = [String: TypeAccessProof.Cause]()
		func access(of type: TypeDescription, receivedAs label: String?) -> AccessLevel {
			let admittedModules = ownModules.union(label.map { receiverModulesByLabel[$0, default: []] } ?? [])
			let access = context.access(ofTypes: [type], admittedModules: admittedModules)
			accessCauses["\(label ?? ""):\(type.asSource)"] = access.cause
			return access.level
		}
		func cause(of type: TypeDescription, receivedAs label: String?) -> TypeAccessProof.Cause? {
			accessCauses["\(label ?? ""):\(type.asSource)"]
		}
		var leadingParameters = [PublicMockParameter]()
		var defaultResolutions = [String]()
		var providerDeclarations = [String]()
		var defaultFields = [PublicStructMember]()
		var constructionDefaultValues = [String: String]()
		let bodyIndent = "\(standardIndent)\(standardIndent)"
		/// The parameter of a default-valued `type` taken as `T? = nil`, resolved in the body to the default, whose access
		/// is `provenType`'s.
		func optionalParameter(named name: String, type: TypeDescription, provenType: TypeDescription, resolvedTo expression: String, role: PublicMockParameter.Role) -> PublicMockParameter {
			defaultResolutions.append("\(bodyIndent)let \(name) = \(name) ?? (\(expression))")
			let optionalType = TypeDescription.optional(type)
			return PublicMockParameter(name: name, type: optionalType, provenType: .optional(provenType), typeSource: optionalType.asSource, defaultSource: "nil", defaultKind: .nilValue, access: access(of: provenType, receivedAs: nil), role: role)
		}
		// A `mock()` isolated to a global actor evaluates the type's own defaults as an internal mock does, in its own
		// isolation, where a default may read the actor's state: each is a parameter of `mock()`, never a field of the
		// nonisolated `SafeDIOverrides` initializer, and its provider shares the isolation.
		let mockIsolation: String? = if instantiable.generatedMockIsGlobalActorIsolated {
			instantiable.declarationIsolation.flatMap { $0 == "nonisolated" ? nil : $0 } ?? Initializer.globalActorAttribute(in: instantiable.mockAttributes)
		} else {
			nil
		}
		let ownDefaultsAreFields = hasOverrides && mockIsolation == nil
		/// The provider of an optional-typed default, and how a declaration names it.
		func provider(named label: String, type: TypeDescription, access: AccessLevel, expression: String) -> String {
			let isPublic = access == .public
			if providerDeclarations.isEmpty, mockIsolation == nil, instantiable.declarationIsolation == nil {
				// SafeDI cannot see isolation a type takes from a conformance or a superclass (a SwiftUI `View`, a
				// `UIViewController` subclass), which is the user's to opt into through `mockAttributes`; the comment says so
				// where the compiler reports a default that reads the actor's state.
				providerDeclarations.append("\(standardIndent)// These providers evaluate `\(typeName)`'s own defaults outside any actor, since SafeDI sees no isolation on it. If one")
				providerDeclarations.append("\(standardIndent)// reads the state of an actor `\(typeName)` takes from a conformance or a superclass and does not compile, give its")
				providerDeclarations.append("\(standardIndent)// `@\(InstantiableVisitor.macroName)` `mockAttributes: \"@MainActor\"` (or that actor).")
			}
			providerDeclarations.append("\(standardIndent)\(isPublic ? "@usableFromInline " : "")\(mockIsolation ?? "nonisolated") static func \(PublicMockContext.rootProviderName(label: label))() -> \(type.asSource) { \(expression) }")
			return "\(typeName).\(PublicMockContext.rootProviderName(label: label))()"
		}

		for dependency in forwardedDependencies {
			let property = dependency.property
			if let forwardedDefault = forwardedDefaults[property.label] {
				if property.typeDescription.isOptional, !forwardedDefault.isHandWrittenMock {
					let providerCall = provider(named: property.label, type: property.typeDescription, access: access(of: property.typeDescription, receivedAs: nil), expression: forwardedDefault.expression)
					leadingParameters.append(PublicMockParameter(name: property.label, type: property.typeDescription, provenType: property.typeDescription, typeSource: property.typeDescription.asSource, defaultSource: providerCall, defaultKind: .provider, access: access(of: property.typeDescription, receivedAs: nil), role: .forwarded(property)))
				} else {
					leadingParameters.append(optionalParameter(named: property.label, type: property.typeDescription.strippingEscaping, provenType: property.typeDescription.strippingEscaping, resolvedTo: forwardedDefault.expression, role: .forwarded(property)))
				}
			} else {
				leadingParameters.append(PublicMockParameter(name: property.label, type: property.typeDescription, provenType: property.typeDescription, typeSource: property.typeDescription.asFunctionParameter.asSource, defaultSource: nil, defaultKind: .none, access: access(of: property.typeDescription, receivedAs: nil), role: .forwarded(property)))
			}
		}
		for rootDefault in rootDefaultParameters {
			let type = rootDefault.typeDescription
			// `mock()` is declared in the type's extension, where a type nested in it is named as written, but its access
			// is its nested declaration's, which the qualified type names.
			let provenType = context.qualifyingNestedTypes(in: type, writtenWithin: instantiable.concreteInstantiable)
			let typeAccess = access(of: provenType, receivedAs: nil)
			if rootDefault.defaultExpression.hasPrefix("#") {
				// A magic literal is evaluated where the parameter is declared, so the parameter keeps it.
				leadingParameters.append(PublicMockParameter(name: rootDefault.label, type: type, provenType: provenType, typeSource: rootDefault.typeSource, defaultSource: rootDefault.defaultExpression, defaultKind: .expression, access: typeAccess, role: .constructionDefault))
			} else if type.isOptional {
				let isNilLiteral = rootDefault.defaultExpression == "nil"
				let providerCall = isNilLiteral ? "nil" : provider(named: rootDefault.label, type: type, access: typeAccess, expression: rootDefault.defaultExpression)
				if ownDefaultsAreFields {
					defaultFields.append(publicDefaultMember(
						name: rootDefault.label,
						valueType: type,
						access: typeAccess,
						defaultExpression: providerCall,
						omittedValue: providerCall,
						requiresSendable: false,
						documentation: isNilLiteral
							? "The value of `\(typeName)`'s `\(rootDefault.label.spelledWithoutBackticks)`, `nil` unless set."
							: "The default of `\(typeName)`'s `\(rootDefault.label.spelledWithoutBackticks)` unless set; `.init(\(rootDefault.label.spelledAsArgumentLabel): nil)` passes `nil`.",
					))
					constructionDefaultValues[rootDefault.label] = "\(ReservedName.mockOverridesParameterName).\(rootDefault.label)"
				} else {
					leadingParameters.append(PublicMockParameter(name: rootDefault.label, type: type, provenType: provenType, typeSource: type.asSource, defaultSource: providerCall, defaultKind: isNilLiteral ? .nilValue : .provider, access: typeAccess, role: .constructionDefault))
				}
			} else {
				leadingParameters.append(optionalParameter(named: rootDefault.label, type: type, provenType: provenType, resolvedTo: rootDefault.defaultExpression, role: .constructionDefault))
			}
		}
		for (property, name) in flatReceivedParameters {
			if let hole = passedUpHoles[property] {
				// The builder of a hole of another module's public mock the tree calls, which the mock passes up: it is as
				// visible as that mock's computation proves, and a caller that sees a type fulfilling the hole fills it. One
				// a `@Sendable` builder function captures is taken `@Sendable`, so a caller passes it up `@Sendable` too.
				let builder = sendablePassedUpBuilders.contains(property) ? Property(label: property.label, typeDescription: .attributed(property.typeDescription, specifiers: [], attributes: ["Sendable"])) : property
				leadingParameters.append(PublicMockParameter(name: name, type: builder.typeDescription, provenType: builder.typeDescription, typeSource: builder.typeDescription.asFunctionParameter.asSource, defaultSource: nil, defaultKind: .none, access: hole.tierAccess, accessCause: hole.accessCause, role: .received(builder, isRequired: true), hole: hole))
			} else {
				leadingParameters.append(PublicMockParameter(name: name, type: property.typeDescription, provenType: property.typeDescription, typeSource: property.typeDescription.asFunctionParameter.asSource, defaultSource: nil, defaultKind: .none, access: access(of: property.typeDescription, receivedAs: property.label), role: .received(property, isRequired: true)))
			}
		}
		for uncovered in flatUncoveredParameters {
			let typeSource = uncovered.isSendableAutoclosure ? "@autoclosure @escaping @Sendable () -> \(uncovered.typeSource)" : uncovered.typeSource
			leadingParameters.append(PublicMockParameter(name: uncovered.label, type: uncovered.property.typeDescription, provenType: uncovered.property.typeDescription, typeSource: typeSource, defaultSource: nil, defaultKind: .none, access: access(of: uncovered.property.typeDescription, receivedAs: uncovered.property.label), role: .received(uncovered.property, isRequired: true)))
		}
		// Each hole's builder, required: what fills the hole takes the values in scope at its site. The tree calls each
		// builder by the name the sites call it by, bound before anything else, in builder-label order.
		let holes = parameterTree.holesOfTree
		defaultResolutions.insert(contentsOf: holes.map { "\(bodyIndent)let \($0.internalName) = \($0.builderLabel)" }, at: 0)
		for hole in holes {
			let builderType = hole.builderType(qualifiedBy: instantiable.concreteInstantiable)
			let closureType = hole.stageFunctionType(at: 0, qualifiedBy: instantiable.concreteInstantiable)
			leadingParameters.append(PublicMockParameter(
				name: hole.builderLabel,
				type: closureType,
				provenType: closureType,
				typeSource: builderType.asSource,
				defaultSource: nil,
				defaultKind: .none,
				access: hole.tierAccess,
				accessCause: hole.accessCause,
				role: .received(Property(label: hole.builderLabel, typeDescription: closureType), isRequired: true),
				hole: hole,
			))
		}

		// The received dependencies the mock builds and those received only if available, each `T? = nil`, by name.
		var promotedParameterNames = [Property: String]()
		var optionalReceivedParameters = [PublicMockParameter]()
		for (node, name) in promotedNodes {
			let parameterProperty = publicMockParameterProperty(of: node)
			let parameterName = node.property.propertyType.isLazilyInstantiated ? node.propertyLabel : name
			promotedParameterNames[node.property] = parameterName
			optionalReceivedParameters.append(PublicMockParameter(name: parameterName, type: parameterProperty.typeDescription, provenType: parameterProperty.typeDescription, typeSource: parameterProperty.typeDescription.asSource, defaultSource: "nil", defaultKind: .nilValue, access: access(of: parameterProperty.typeDescription, receivedAs: node.propertyLabel), accessCause: cause(of: parameterProperty.typeDescription, receivedAs: node.propertyLabel), role: .received(parameterProperty, isRequired: false), isBuiltWhenNil: true, builtWrapper: node.property.propertyType.isLazilyInstantiated ? node.property : nil))
		}
		for onlyIfAvailableOverride in onlyIfAvailableOverrides {
			optionalReceivedParameters.append(PublicMockParameter(name: onlyIfAvailableOverride.name, type: onlyIfAvailableOverride.typeDescription, provenType: onlyIfAvailableOverride.typeDescription, typeSource: onlyIfAvailableOverride.typeDescription.asSource, defaultSource: "nil", defaultKind: .nilValue, access: access(of: onlyIfAvailableOverride.typeDescription, receivedAs: onlyIfAvailableOverride.receivedProperty.label), accessCause: cause(of: onlyIfAvailableOverride.typeDescription, receivedAs: onlyIfAvailableOverride.receivedProperty.label), role: .received(Property(label: onlyIfAvailableOverride.receivedProperty.label, typeDescription: onlyIfAvailableOverride.typeDescription), isRequired: false)))
		}
		optionalReceivedParameters.sort { ($0.name, $0.typeSource) < ($1.name, $1.typeSource) }

		var parameters = leadingParameters + optionalReceivedParameters
		if hasOverrides {
			let overridesType = TypeDescription.simple(name: "SafeDIOverrides")
			parameters.append(PublicMockParameter(name: ReservedName.mockOverridesParameterName, type: overridesType, provenType: overridesType, typeSource: overridesType.asSource, defaultSource: ".init()", defaultKind: .expression, access: .public, role: .overrides))
		}
		let tiers = [AccessLevel.public] + Set(parameters.map(\.access)).filter { $0 < .public }.sorted(by: >)
		var hash = SeamSignatureHash()
		for parameter in parameters {
			hash.combine(parameter.name)
			hash.combine(parameter.type.withoutAny.asSource)
			hash.combine(parameter.access.spelledOnGeneratedDeclaration)
			hash.combine(parameter.defaultKind.rawValue)
		}
		// Each hole's fields after every parameter, as a seam hashes them – those of the holes whose builders the mock
		// passes up too – since a caller that computed the struct without a field would resolve its label from its own
		// scope instead.
		let hashedHoles = holes + passedUpHoles.sorted { $0.key < $1.key }.map(\.value)
		for field in hashedHoles.flatMap({ SeamSignature.CallShape.Hole($0).fields.joined() }) {
			hash.combine(field.label)
			hash.combine(field.type)
			hash.combine(field.access.spelledOnGeneratedDeclaration)
		}
		var plan = PublicMockPlan(
			parameters: parameters,
			tiers: tiers,
			guardTypeName: "\(ReservedName.builderFunctionNamePrefix)\(instantiable.concreteInstantiable.asIdentifier)_mock_\(hash.hexadecimal)",
			defaultFields: defaultFields,
			providerDeclarations: providerDeclarations,
			defaultResolutions: defaultResolutions,
			promotedParameterNames: promotedParameterNames,
			constructionDefaultValues: constructionDefaultValues,
		)
		plan.holes = holes
		return plan
	}

	/// The modules that declare a receiver of each label in `items`' tree: a type whose declaration receives a
	/// dependency of that label, required or only if available. A type with no entry is proven by the mentions of the
	/// mocked type's module and of these modules.
	static func receiverModules(in items: [MockTreeItem], context: PublicMockContext) -> [String: Set<String?>] {
		var modulesByLabel = [String: Set<String?>]()
		// A stack of the nodes left to visit, since a mock tree can be as deep as the module has types.
		var nodesToVisit = items.propertyNodes
		while let node = nodesToVisit.popLast() {
			for dependency in node.dependencies {
				switch dependency.source {
				case .received:
					modulesByLabel[dependency.property.label, default: []].insert(context.moduleNameByType[node.concreteType])
				case let .aliased(fulfillingProperty, _, _):
					modulesByLabel[fulfillingProperty.label, default: []].insert(context.moduleNameByType[node.concreteType])
				case .instantiated, .forwarded:
					break
				}
			}
			nodesToVisit.append(contentsOf: node.propertyChildren)
		}
		return modulesByLabel
	}

	/// The tiers of a public mock: the `mock()` of each tier of `plan`, widest first, all carrying `attributesPrefix`.
	/// The narrowest tier's body is `narrowestBody`; each wider tier calls the next narrower one, passing every
	/// parameter it takes and `nil` for each it omits, so the call names a label only the narrower tier has. The `public`
	/// tier is marked for `unreadTypeComment`, when there is one.
	static func publicMockTiers(
		of plan: PublicMockPlan,
		typeName: String,
		returnType: String,
		attributesPrefix: String,
		narrowestBody: [String],
		unreadTypeComment: UnreadTypeComment?,
	) -> [String] {
		let indent = standardIndent
		let bodyIndent = "\(indent)\(indent)"
		var lines = [String]()
		for (index, tier) in plan.tiers.enumerated() {
			let parameters = plan.parameters(ofTier: tier)
			// The `public` tier is marked for the file's comment when it names a type SafeDI reads no declaration of: what a
			// builder returns, and the value of every other parameter but the overrides, whose type the mock declares.
			if tier == .public, let marker = unreadTypeComment?.markerLine(
				namedBy: parameters.compactMap { parameter in
					if let hole = parameter.hole {
						hole.property.typeDescription
					} else if parameter.name == ReservedName.mockOverridesParameterName {
						nil
					} else {
						parameter.provenType
					}
				},
				indent: indent,
			) {
				lines.append(marker)
			}
			lines.append("\(indent)\(attributesPrefix)\(tier == .internal ? "" : "\(tier.spelledOnGeneratedDeclaration) ")static func mock(")
			lines.append(parameters.map { parameter in
				"\(bodyIndent)\(parameter.name.spelledAsArgumentLabel): \(parameter.typeSource)\(parameter.defaultSource.map { " = \($0)" } ?? "")"
			}.joined(separator: ",\n"))
			lines.append("\(indent)) -> \(returnType) {")
			if index == plan.tiers.count - 1 {
				lines.append(contentsOf: narrowestBody)
			} else {
				let takenNames = Set(parameters.map(\.name))
				// An omitted parameter that defaults to a provider is passed the provider's value, the declaration's
				// default, which `nil` would replace.
				let arguments = plan.parameters(ofTier: plan.tiers[index + 1]).map { parameter in
					let value = if takenNames.contains(parameter.name) {
						parameter.name
					} else if parameter.defaultKind == .provider, let defaultSource = parameter.defaultSource {
						defaultSource
					} else {
						"nil"
					}
					return "\(parameter.name.spelledAsArgumentLabel): \(value)"
				}
				lines.append("\(bodyIndent)\(typeName).mock(\(arguments.joined(separator: ", ")))")
			}
			lines.append("\(indent)}")
			if index < plan.tiers.count - 1 {
				lines.append("")
			}
		}
		return lines
	}
}

extension ScopeGenerator {
	/// The `public struct SafeDIOverrides` of a public mock: a member for each node at the mock root's level, as an
	/// internal mock's holds it, then the mocked type's own optional-typed defaults, each as visible as its types,
	/// with an initializer for each access a member has.
	static func publicSafeDIOverridesStruct(
		rootChildren: [MockParameterNode],
		rootLabelMap: [String: [TypeDescription: String]],
		defaultFields: [PublicStructMember],
		mockedType: Instantiable,
		context: PublicMockContext,
		indent: String,
	) -> String {
		let members = rootChildren.map { child in
			publicMember(
				for: child,
				named: disambiguatedLabel(for: child, labelMap: rootLabelMap),
				context: context,
				admittedModules: [context.moduleName, mockedType.moduleName, context.moduleNameByType[child.concreteType]],
				requiresSendable: false,
			)
		} + defaultFields
		var lines = [String]()
		lines.append("\(indent)/// Overrides for the mock dependency tree.")
		lines.append("\(indent)public struct SafeDIOverrides {")
		lines.append(contentsOf: publicStructBody(members: members, indent: "\(indent)\(standardIndent)"))
		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}
}

/// Why the public mock of a `generateMock: .public` type cannot be generated, reported at its `generateMock:` argument.
struct PublicMockFinding: Hashable, Sendable {
	let sourceDiagnostics: [SourceDiagnostic]

	/// A required parameter of the mock is narrower than `public`, so the `public` tier cannot take it.
	struct OmittedRequiredParameter {
		/// How the mock takes the parameter.
		enum Kind {
			/// The mocked type forwards it.
			case forwarded
			/// A type in the mocked type's tree receives it, which the mock cannot build.
			case received
			/// A type in the mocked type's tree instantiates it, which no declaration the module sees fulfills.
			case instantiated
			/// The builder of a hole of the mocked type's tree, which returns the hole's property.
			case builder(SeamSignature.Hole)
		}

		let property: Property
		let kind: Kind
		let level: AccessLevel
		/// How the parameter's narrowest type is proven, which a type narrower than `public` always has.
		let cause: TypeAccessProof.Cause
		/// The declarations in the tree that receive or instantiate the parameter, in tree order.
		let receivers: [(declaringType: TypeDescription, dependency: Dependency)]
	}

	/// `generateMock: .public` on a type a narrower enclosing type keeps from being `public`.
	static func narrowerEnclosingType(of instantiable: Instantiable, enclosingTypeName: String, enclosingLevel: AccessLevel) -> PublicMockFinding {
		let typeName = instantiable.concreteInstantiable.asSource
		let level = enclosingLevel.spelledOnGeneratedDeclaration
		return PublicMockFinding(sourceDiagnostics: [
			SourceDiagnostic(
				severity: .error,
				location: instantiable.mockGenerationArgumentLocation,
				message: "`\(typeName)` cannot have a public mock because `\(enclosingTypeName)` is `\(level)`. Make `\(enclosingTypeName)` `public`, or use `generateMock: .internal`.",
				fixIts: instantiable.mockGenerationArgumentRange.map { [SourceDiagnostic.FixIt(range: $0, replacement: ".internal")] } ?? [],
			),
		])
	}

	/// `generateMock: .public` on a type narrower than `public`, which the macro rejects (`publicMockRequiresPublicType`)
	/// once it expands: a plain error at the declaration, with no fix-it, which the macro keeps for the IDE.
	static func typeTheMacroRejects(_ instantiable: Instantiable, level: AccessLevel) -> PublicMockFinding {
		let typeName = instantiable.concreteInstantiable.asSource
		return PublicMockFinding(sourceDiagnostics: [
			SourceDiagnostic(
				severity: .error,
				location: instantiable.declarationLocation,
				message: "`\(typeName)` is `\(level.spelling)` and declares `generateMock: .public`. The @\(InstantiableVisitor.macroName) macro rejects that: `generateMock: .public` requires a `public` or `open` type. Declare `\(typeName)` `public`, or use `generateMock: .internal`.",
			),
		])
	}

	/// The modules that call the public mock of `instantiable` compute its signature from declarations that leave out
	/// `declaration`, so their calls would not match the mock: a directory this module's configuration adds declares it
	/// (`viaTargetGraph`), or a dependent module whose module info names no module does.
	static func callersCannotSee(_ declaration: TypeDescription, of instantiable: Instantiable, viaTargetGraph: Bool) -> PublicMockFinding {
		let typeName = instantiable.concreteInstantiable.asSource
		let declarationName = declaration.asSource
		let message = viaTargetGraph
			? "SafeDI cannot generate the public mock of `\(typeName)`: its signature depends on `\(declarationName)`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call the mock cannot see that declaration, so their calls would not match the mock. Declare `\(declarationName)` in a file of this module, or of a module it depends on."
			: "SafeDI cannot generate the public mock of `\(typeName)`: its signature depends on `\(declarationName)`, which is declared in a module whose SafeDI module info names no module, and the modules that call the mock, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the mock. Generate that module's module info with `--module-name`."
		return PublicMockFinding(sourceDiagnostics: [
			SourceDiagnostic(severity: .error, location: instantiable.mockGenerationArgumentLocation, message: message),
		])
	}

	/// The callers of `instantiable`'s public mock compute its signature without `declaration`, a plain declaration that
	/// proves a parameter's type narrower than `public`, which they would count as `public`: reported at the declaration.
	static func callersCannotSeePlainDeclaration(_ declaration: PlainTypeDeclaration, of instantiable: Instantiable, viaTargetGraph: Bool) -> PublicMockFinding {
		let typeName = "`\(instantiable.concreteInstantiable.asSource)`"
		let declarationName = "`\(declaration.typeDescription.asSource)`"
		let message = viaTargetGraph
			? "SafeDI cannot generate the public mock of \(typeName): it takes its parameters at the access this declaration of \(declarationName) proves, which is in a directory this module's `#SafeDIConfiguration` adds, and the modules that call the mock cannot see it, so they would count \(declarationName) as `public`, and their calls would not match the mock. Declare \(declarationName) in a file of this module, or of a module it depends on."
			: "SafeDI cannot generate the public mock of \(typeName): it takes its parameters at the access this declaration of \(declarationName) proves, which is in a module whose SafeDI module info names no module, and the modules that call the mock, which compute its signature from the modules this module's module info names, cannot see it, so they would count \(declarationName) as `public`, and their calls would not match the mock. Generate that module's module info with `--module-name`."
		return PublicMockFinding(sourceDiagnostics: [
			SourceDiagnostic(severity: .error, location: declaration.access.declarationStartLocation ?? instantiable.mockGenerationArgumentLocation, message: message),
		])
	}

	/// `publicTierOmitsRequiredParameter`: the `public` tier the mock requires cannot take `parameter`.
	static func omittedRequiredParameter(_ parameter: OmittedRequiredParameter, of instantiable: Instantiable) -> PublicMockFinding {
		let typeName = "`\(instantiable.concreteInstantiable.asSource)`"
		let receiverNames = parameter.receivers.map(\.declaringType).uniqued().map { "`\($0.asSource)`" }
		// A lone receiver that receives the parameter through an alias of it, which names the alias.
		let aliasReceiver = parameter.receivers.count == 1 ? parameter.receivers.first.flatMap { receiver in
			receiver.dependency.source.fulfillingProperty.map { _ in (declaringType: receiver.declaringType, aliasProperty: receiver.dependency.property) }
		} : nil
		let receivedTaker = if let aliasReceiver {
			"which the initializer of `\(aliasReceiver.declaringType.asSource)` receives through its alias `\(aliasReceiver.aliasProperty.label)` (`fulfilledByDependencyNamed: \"\(parameter.property.label)\"`)"
		} else if receiverNames.count > 1 {
			"which the initializers of \(receiverNames.joinedAsList) receive"
		} else {
			"which the initializer of \(receiverNames.first ?? typeName) receives"
		}
		let taker = switch parameter.kind {
		case .forwarded:
			"which \(typeName) forwards"
		case .received:
			receivedTaker
		case .instantiated:
			"which \(receiverNames.first ?? typeName) instantiates and no `@Instantiable` declaration this module sees fulfills"
		case let .builder(hole):
			"which returns `\(hole.property.typeDescription.asSource)` for the hole `\(hole.property.label)`"
		}
		let parameterName = if case let .builder(hole) = parameter.kind {
			hole.builderLabel
		} else {
			parameter.property.asSource
		}
		let causeText = SeamAccessExplanation.causeSentence(parameter.cause, receivers: [])
		var remedies = SeamAccessExplanation.causeRemedies(parameter.cause, neededLevel: .public)
		switch parameter.kind {
		case .forwarded where parameter.cause.leavesOutMockOnlyMockOfType:
			remedies.append("give `\(parameter.cause.type.asSource)` a `mockOnly` mock")
		case .received:
			remedies.append("receive \(aliasReceiver.map { "`\($0.aliasProperty.label)`" } ?? "it") with `onlyIfAvailable: true` and an optional type")
		case .forwarded, .instantiated:
			break
		case let .builder(hole):
			// A stub the mock builds in place of taking the builder, which production never sees.
			let holeType = hole.property.typeDescription.asInstantiatedType.withoutAny.asSource
			let module = instantiable.moduleName.map { "module `\($0)`" } ?? "this module"
			remedies.append("declare in \(module), or a module it depends on, a `mockOnly` `@\(InstantiableVisitor.macroName)` type that fulfills `\(holeType)` (`@\(InstantiableVisitor.macroName)(fulfillingAdditionalTypes: [\(holeType).self], mockOnly: true)`), which the mock builds instead of taking `\(hole.builderLabel)`, leaving production's hole as it is")
		}
		if case let .signatures(_, _, provers, _) = parameter.cause {
			// The members that prove the type, by name, each of which proves it at the level it spells.
			for prover in provers where prover.cap == nil {
				remedies.append("make \(prover.name) `public`")
			}
		}
		remedies.append("use `generateMock: .internal`")
		let message = "SafeDI cannot generate the public mock of \(typeName): its `public` tier, which `generateMock: .public` requires, cannot take `\(parameterName)`, \(taker), and cannot pass `nil` for it, since it is required. \(causeText) \(SeamAccessExplanation.joined(remedies))"
		let verb = switch parameter.kind {
		case .instantiated, .builder:
			"instantiates"
		case .forwarded, .received:
			"receives"
		}
		var sourceDiagnostics = [SourceDiagnostic(severity: .error, location: instantiable.mockGenerationArgumentLocation, message: message)]
			+ SeamAccessExplanation.declarationNotes(for: parameter.cause, neededLevel: .public)
		for receiver in parameter.receivers {
			sourceDiagnostics.append(SourceDiagnostic(
				severity: .note,
				location: receiver.dependency.declarationLocation,
				message: "`\(receiver.declaringType.asSource)` \(verb) `\(receiver.dependency.property.asSource)` here.",
			))
		}
		return PublicMockFinding(sourceDiagnostics: sourceDiagnostics)
	}
}

extension ScopeGenerator {
	/// What keeps `instantiable`'s public mock from being generated, from the parameters this mock root's `mock()`
	/// takes: a narrower enclosing type, and each required parameter narrower than `public`. A public mock's tiers are
	/// otherwise always generated, so this decides whether one root can be generated, which the query reports too.
	/// - Parameter forwardedTypesWithMockDefaults: The types whose hand-written mock a forwarded parameter of their type
	///   defaults to (`MockScopes.forwardedParameterMockDefaults`), which the mock then takes as `T? = nil`.
	func publicMockFindings(of instantiable: Instantiable, context: PublicMockContext, forwardedTypesWithMockDefaults: Set<TypeDescription>) async -> [PublicMockFinding] {
		// The type's own declaration, the types enclosing it in its file and, for a type declared inside an extension,
		// the declarations of the type the extension extends that SafeDI records, outermost first, each with its own
		// level. The macro requires the type itself to be `public` or `open`, or directly inside a `public extension`, but
		// `generate` runs before the macro expands, so a narrower type gets a plain error that points at the macro's rule.
		// Otherwise only an enclosing type can make it narrower, and the innermost such type is the one to name.
		var narrowerEnclosingType: (type: TypeDescription, level: AccessLevel)?
		for accessNeed in context.extendedTypeAccessNeedsByType[instantiable.concreteInstantiable, default: []] + instantiable.accessNeeds(constructingWithMockMethod: false) {
			switch accessNeed.declaration {
			case let .type(type), let .extensionDeclaringType(type):
				guard TypeAccessProof.normalized(accessNeed.level) < .public else { continue }
				if type == instantiable.concreteInstantiable {
					return [PublicMockFinding.typeTheMacroRejects(instantiable, level: accessNeed.level)]
				} else {
					narrowerEnclosingType = (type, accessNeed.level)
				}
			case .member, .extensionDeclaringMember:
				continue
			}
		}
		if let narrowerEnclosingType {
			return [PublicMockFinding.narrowerEnclosingType(of: instantiable, enclosingTypeName: narrowerEnclosingType.type.asSource, enclosingLevel: narrowerEnclosingType.level)]
		}
		let parameters = await mockRootParameters(instantiable: instantiable)
		let ownModules: Set<String?> = [context.moduleName, instantiable.moduleName]
		let receiverModulesByLabel = Self.receiverModules(in: parameters.parameterTree, context: context)
		let treeReceivers = Self.treeReceivers(in: parameters.parameterTree, mockedType: instantiable)
		var omittedParameters = [PublicMockFinding.OmittedRequiredParameter]()
		func check(_ property: Property, kind: PublicMockFinding.OmittedRequiredParameter.Kind) {
			let isForwarded = if case .forwarded = kind {
				true
			} else {
				false
			}
			let admittedModules = isForwarded ? ownModules : ownModules.union(receiverModulesByLabel[property.label, default: []])
			let access = context.access(ofTypes: [property.typeDescription], admittedModules: admittedModules)
			guard access.level < .public, let cause = access.cause else { return }
			omittedParameters.append(PublicMockFinding.OmittedRequiredParameter(
				property: property,
				kind: kind,
				level: access.level,
				cause: cause,
				// An alias receives the property it is fulfilled by.
				receivers: isForwarded ? [] : treeReceivers.filter { ($0.dependency.source.fulfillingProperty ?? $0.dependency.property).label == property.label },
			))
		}
		let constructionDefaultLabels = Set((parameters.rootConstructionInitializer?.arguments ?? []).filter(\.hasDefaultValue).map(\.innerLabel))
		for dependency in parameters.forwardedDependencies
			where !constructionDefaultLabels.contains(dependency.property.label) && !forwardedTypesWithMockDefaults.contains(dependency.property.typeDescription)
		{
			check(dependency.property, kind: .forwarded)
		}
		// A builder the tree passes up is checked as the hole's own builder is, below.
		let passedUpHoles = parameters.parameterTree.passedUpHolesByBuilder
		for property in parameters.flatReceivedProperties where passedUpHoles[property] == nil {
			check(property, kind: .received)
		}
		for uncovered in parameters.flatUncoveredParameters {
			check(uncovered.property, kind: .instantiated)
		}
		// A hole's builder is as visible as the hole's type, proven as a seam's builder is.
		for hole in parameters.parameterTree.holesOfTree + passedUpHoles.sorted(by: { $0.key < $1.key }).map(\.value) where hole.tierAccess < .public {
			guard let cause = hole.accessCause else { continue }
			omittedParameters.append(PublicMockFinding.OmittedRequiredParameter(
				property: hole.property,
				kind: .builder(hole),
				level: hole.tierAccess,
				cause: cause,
				receivers: [(declaringType: hole.ownerType, dependency: Dependency(property: hole.property, source: .instantiated(fulfillingTypeDescription: nil, erasedToConcreteExistential: hole.erasedToConcreteExistential), declarationLocation: hole.declarationLocation))],
			))
		}
		return omittedParameters.map { PublicMockFinding.omittedRequiredParameter($0, of: instantiable) }
	}

	/// The declarations in `items`' tree that receive or instantiate a dependency, by its label, in tree order: the
	/// mocked type's own first.
	static func receivers(in items: [MockTreeItem], mockedType: Instantiable) -> [String: [(declaringType: TypeDescription, dependency: Dependency)]] {
		Dictionary(grouping: treeReceivers(in: items, mockedType: mockedType)) { $0.dependency.property.label }
	}

	/// Each dependency a declaration in `items`' tree declares, with that declaration, in tree order: the mocked type's
	/// own first.
	static func treeReceivers(in items: [MockTreeItem], mockedType: Instantiable) -> [(declaringType: TypeDescription, dependency: Dependency)] {
		var receivers = mockedType.dependencies.map { (declaringType: mockedType.concreteInstantiable, dependency: $0) }
		// Depth first, in tree order, on a stack of its own, since a mock tree can be as deep as the module has types.
		var nodesToVisit = Array(items.propertyNodes.reversed())
		while let node = nodesToVisit.popLast() {
			receivers += node.dependencies.map { (declaringType: node.concreteType, dependency: $0) }
			nodesToVisit.append(contentsOf: node.propertyChildren.reversed())
		}
		return receivers
	}
}

/// The plan of a public mock a module computed for one of its own types, as another module's mock tree reads it to
/// call the mock.
struct OwnPublicMockPlan: Sendable {
	/// The mocked type's declaration, as the mock root is built from it.
	let instantiable: Instantiable
	let plan: PublicMockPlan
	/// The declarations in the mock's tree that receive each label, in tree order, which a diagnostic notes.
	let receiversByLabel: [String: [(declaringType: TypeDescription, dependency: Dependency)]]
}

/// How a mock tree calls the public mock another module generated for a type the tree cannot build itself (see
/// `Scope.publicMockCall`). The tree's scope for the type is a leaf that declares the mock's whole signature: each
/// parameter of the tier the call reaches as the dependency it stands for – a forwarded property, or a received one,
/// required or only if available – and each parameter that tier omits as a receive only if available, which the call
/// never passes but which orders the leaf among its siblings, as the receivers the mock builds would be ordered.
struct PublicMockCall: Sendable {
	/// The type whose mock the call calls.
	let type: TypeDescription
	/// The tier the call reaches: the narrowest the calling module can reach.
	let tier: AccessLevel
	/// The parameters of `tier` that stand for a dependency, in signature order, which the call passes by name.
	let passedParameters: [PassedParameter]
	/// The parameters `tier` omits, which the call passes `nil` for by leaving them out.
	let omittedParameters: [PublicMockParameter]
	/// Whether the mock takes `safeDIOverrides`, which the call passes the calling mock's entry for the type.
	let takesOverrides: Bool
	/// The enum the call names, whose name hashes the mock's signature.
	let guardTypeName: String
	/// See `SeamCall.carriesPluginComment`.
	let carriesPluginComment: Bool
	/// The module that declares the type and generated its mock.
	let declaringModule: ModuleIdentity
	/// The module whose mock tree makes the call.
	let callerModule: ModuleIdentity
	/// What the calling module needs of the declaring module's declarations.
	let requirement: AccessRequirement
	/// The condition the declaring module generates its mocks under, and the calling module's.
	let declaringModuleMockCondition: MockCondition
	let callerModuleMockCondition: MockCondition

	/// Whether the calling module's mocks can call the mock: the two modules generate their mocks under one condition,
	/// spelled the same, or the declaring module's mocks are unconditional.
	var mockConditionsAgree: Bool {
		declaringModuleMockCondition.conditionalCompilation == nil || declaringModuleMockCondition == callerModuleMockCondition
	}

	/// The declarations in the public mock's tree that receive each label, which a diagnostic notes.
	let receiversByLabel: [String: [(declaringType: TypeDescription, dependency: Dependency)]]
	/// The holes whose builders the call fills (`DependencyTreeGenerator.holesFilled(byCallsOf:in:)`); the call passes
	/// every other builder up, as a dependency the calling tree receives.
	var filledHoles = [SeamSignature.Hole]()
}

extension PublicMockCall {
	/// A parameter of the called tier that stands for a dependency: the mocked type's forwarded property, or a dependency
	/// its tree receives, which the leaf declares as it is passed.
	struct PassedParameter: Sendable {
		/// The parameter's name, its argument label.
		let name: String
		/// The parameter's type.
		let type: TypeDescription
		/// The dependency the leaf declares for it.
		let dependency: Dependency
		/// Whether the called mock builds the dependency when the call passes `nil` (`PublicMockParameter.isBuiltWhenNil`).
		let isBuiltWhenNil: Bool
		/// The wrapper the called mock builds when the call passes `nil`, for a lazily instantiated dependency it takes by
		/// value (`PublicMockParameter.builtWrapper`).
		var builtWrapper: Property?
		/// For the builder of a hole, the hole (`PublicMockParameter.hole`).
		let hole: SeamSignature.Hole?
	}

	/// The line before the call that names the mock's guard enum, so that a call generated from another signature
	/// than the mock's fails to compile there, with a comment under the SwiftPM plugin saying what to do then.
	func guardLine(for concreteType: TypeDescription) -> String {
		"_ = \(concreteType.asSource).\(guardTypeName).self\(carriesPluginComment ? " \(Instantiable.seamCallPluginComment(for: concreteType))" : "")"
	}
}

extension ScopeGenerator.PublicMockTierOmission {
	/// `leafTierOmitsProvidedValue`: the error at the provider, with a note at each receiver of the parameter in the
	/// public mock's tree, worded by row 4b's formatter for a seam's omitted parameter.
	var sourceDiagnostics: [SourceDiagnostic] {
		let call = publicMockCall
		func name(_ type: TypeDescription) -> String {
			"`\(type.asSource)`"
		}
		let label = "`\(receivedProperty.label)`"
		let receivers = parameter.nestedOmission?.receivers ?? (call.receiversByLabel[receivedProperty.label] ?? []).filter { receiver in
			receiver.dependency.property.label == receivedProperty.label && receiver.dependency.source.isReceived
		}
		let receiverNames = receivers.map(\.declaringType).uniqued().map(name).joinedAsList
		let callerModule = call.callerModule.moduleName.map { "module `\($0)`" } ?? "this module"
		let caller = call.requirement == .packageUnverified ? "\(callerModule), which SafeDI cannot tell is in the same package," : callerModule
		let declaringModule = call.declaringModule.moduleName.map { " in module `\($0)`" } ?? ""
		let type = name(call.type)
		// A parameter on no tier needs the level of the call in the mock's tree that omits it.
		let neededLevel = AccessLevel.level(satisfying: parameter.nestedOmission?.requirement ?? call.requirement)
		let causeText = parameter.accessCause.map { " " + SeamAccessExplanation.causeSentence($0, receivers: receivers.map { SeamAccessExplanation.Receiver(declaringType: $0.declaringType, aliasProperty: nil, isInstantiateMethodParameter: false) }) } ?? ""
		var remedies = [String]()
		let unverifiedPackage = call.requirement == .packageUnverified ? ", or `public` if the two modules are in different packages" : ""
		if case let .signatures(_, _, provers, _)? = parameter.accessCause, let first = provers.first, first.cap == nil {
			remedies.append("widen \(first.name) to `\(neededLevel.spelledOnGeneratedDeclaration)`\(unverifiedPackage)")
		}
		remedies += SeamAccessExplanation.causeRemedies(parameter.accessCause, neededLevel: neededLevel)
		remedies.append("stop providing \(label) on this path")
		let what: String
		if let nested = parameter.nestedOmission {
			// No tier takes the parameter: a call in the mock's tree omits it.
			let nestedCallerModule = nested.callerModule.moduleName.map { "module `\($0)`" } ?? "this module"
			let nestedCaller = nested.requirement == .packageUnverified ? "\(nestedCallerModule), which SafeDI cannot tell is in the same package," : nestedCallerModule
			let nestedReceiverNames = nested.receivers.map(\.declaringType).uniqued().map(name).joinedAsList
			what = "no mock SafeDI generated for \(type) takes it: \(type)'s mock tree calls the `\(nested.tier.spelledOnGeneratedDeclaration)` mock SafeDI generated for \(name(nested.type))\(nested.declaringModule.moduleName.map { " in module `\($0)`" } ?? ""), the narrowest one \(nestedCaller) can call, which takes \(label) only on its `\(nested.parameterAccess.spelledOnGeneratedDeclaration)` tier, so calling it would pass `nil` to \(nestedReceiverNames.isEmpty ? name(nested.type) : nestedReceiverNames), which the inline mock would hand \(label)."
		} else {
			what = "the `\(call.tier.spelledOnGeneratedDeclaration)` mock SafeDI generated for \(type)\(declaringModule), the narrowest one \(caller) can call, does not take it: `\(call.type.asSource).mock` takes \(label) only on its `\(parameter.access.spelledOnGeneratedDeclaration)` tier, so this call would pass `nil` to \(receiverNames.isEmpty ? type : receiverNames), which the inline mock would hand \(label)."
		}
		let message = "\(name(providerDeclaringType)) provides `\(providerProperty.asSource)`, but \(what)\(causeText) \(SeamAccessExplanation.joined(remedies))"
		return [SourceDiagnostic(severity: .error, location: providerDeclarationLocation, message: message)]
			+ SeamAccessExplanation.declarationNotes(for: parameter.accessCause, neededLevel: neededLevel)
			+ receivers.map { receiver in
				SourceDiagnostic(
					severity: .note,
					location: receiver.dependency.declarationLocation,
					message: "`\(receiver.declaringType.asSource)` receives `\(receiver.dependency.property.asSource)` here.",
				)
			}
	}
}

extension ScopeGenerator {
	/// A call of another module's public mock, in a mock tree, that the calling module's mock condition does not reach.
	struct PublicMockCallUnderOtherMockCondition: Sendable {
		let publicMockCall: PublicMockCall
		/// The dependency that leads to the call.
		let referenceLocation: Dependency.DeclarationLocation?

		var sourceDiagnostic: SourceDiagnostic {
			func spelling(of mockCondition: MockCondition) -> String {
				mockCondition.conditionalCompilation.map { "compile under `#if \($0)`" } ?? "compile unconditionally"
			}
			let declaringCondition = publicMockCall.declaringModuleMockCondition.conditionalCompilation.map { "`#if \($0)`" } ?? "no condition"
			let declaringModule = publicMockCall.declaringModule.moduleName.map { "`\($0)`" } ?? "its module"
			return SourceDiagnostic(
				severity: .error,
				location: referenceLocation,
				message: "`\(publicMockCall.type.asSource).mock()` is generated under \(declaringCondition) in \(declaringModule), but this module's mocks \(spelling(of: publicMockCall.callerModuleMockCondition)). Give both modules one `mockConditionalCompilation`.",
			)
		}
	}
}
