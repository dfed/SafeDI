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

/// Stage D1, lane D: what a module's public mocks share, lowered from the public construction records of their roots'
/// lowerings as `generateMockCode` generates it from the emitter's nodes: one module-level configuration per configured
/// type, `__safeDI_<Module>_<Type>_MockConfiguration`, followed by the extension of the type that holds its construction
/// functions; each public mock's `SafeDIOverrides`; and the call of a construction function, which lane C's walk spells.
extension MockLowering {
	/// The call of `record`'s construction function, handed `arguments`, one per argument of the construction, and the
	/// builder `builderRead` reads, or `nil`, wrapped in `erasedTo` where the node erases what it builds.
	static func publicConstructionCall(
		of record: PublicConstructionRecord,
		arguments: [String],
		builderRead: String?,
		erasedTo: TypeDescription?,
	) -> String {
		var labeledArguments = zip(record.arguments, arguments).map { argument, value in
			"\(argument.innerLabel.spelledAsArgumentLabel): \(value)"
		}
		labeledArguments.append("\(ReservedName.configurationBuilderPropertyName): \(builderRead ?? "nil")")
		let call = "\(record.concreteType.asSource).\(record.functionName)(\(labeledArguments.joined(separator: ", ")))"
		return if let erasedTo {
			"\(erasedTo.asSource)(\(call))"
		} else {
			call
		}
	}

	/// The value of the provider of `type`'s default of `label`, which evaluates the default where the type's declaration
	/// resolves it.
	static func publicProviderRead(of type: TypeDescription, label: String) -> String {
		"\(type.asSource).\(PublicMockContext.providerName(label: label))()"
	}

	/// The `public struct SafeDIOverrides` of a public mock of a type of `mockedTypeModuleName`, indented by `indent`: a
	/// member for each of `members`, the nodes at the mock root's level whose calls offer an override, in inline order.
	static func publicOverridesStruct(
		members: [PublicConstructionRecord.ChildMember],
		mockedTypeModuleName: String?,
		context: PublicMockContext,
		indent: String,
	) -> String {
		let structMembers = members.map { member in
			publicMember(
				member,
				context: context,
				admittedModules: [context.moduleName, mockedTypeModuleName, context.moduleNameByType[member.concreteType]],
				requiresSendable: false,
			)
		}
		var lines = [String]()
		lines.append("\(indent)/// Overrides for the mock dependency tree.")
		lines.append("\(indent)nonisolated public struct \(ReservedName.mockOverridesTypeName) {")
		lines.append(contentsOf: ScopeGenerator.publicStructBody(members: structMembers, indent: "\(indent)\(ScopeGenerator.standardIndent)"))
		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}

	/// The module-level configurations of `records`' types, each followed by its type's construction functions: one per
	/// type, described by the first record of the type, with a function for the first record of each construction, the
	/// initializer's before the hand-written mock's. `records` are every public mock root's, in root order, each root's in the order its walk finished them.
	static func publicConfigurationDeclarations(
		of records: [PublicConstructionRecord],
		context: PublicMockContext,
		// The configurations `@Sendable`-typed, as a type a `Sendable` wrapper builds anywhere in the
		// module has (`MockContext.sendableConfigurationTypeNames`).
		sendableConfigurationTypeNames: Set<String>,
	) -> (declarations: [String], fulfillers: Set<FulfillerImports.Fulfiller>) {
		var recordsByType = [TypeDescription: [PublicConstructionRecord]]()
		var typesInOrder = [TypeDescription]()
		// The types every root configures above its repeated ancestors, then those configured only
		// beneath them (`DependencyTreeGenerator.configurationsBeneathRepeatedAncestors`).
		for record in records.filter(\.describesConfiguration) + records.filter({ !$0.describesConfiguration }) {
			if recordsByType[record.concreteType] == nil {
				typesInOrder.append(record.concreteType)
			}
			recordsByType[record.concreteType, default: []].append(record)
		}
		var declarations = [String]()
		// The declarations each construction builds, and the mocked type of the root whose record
		// introduced the type, as `generateMockCode` records them for every construction it declares a function for.
		var fulfillers = Set<FulfillerImports.Fulfiller>()
		for type in typesInOrder {
			// A type configured only beneath a repeated ancestor takes its configuration from a node built with its initializer
			// wherever one is.
			guard let typeRecords = recordsByType[type],
			      let structRecord = typeRecords.first(where: \.describesConfiguration) ?? typeRecords.first(where: { !$0.usesMockInitializer }) ?? typeRecords.first,
			      let configurationTypeName = context.configurationTypeNameByType[type]
			else { continue }
			let constructionRecords = [false, true].compactMap { usesMockInitializer in
				typeRecords.first { $0.usesMockInitializer == usesMockInitializer }
			}
			declarations.append(publicConfigurationDeclaration(
				of: structRecord,
				constructionRecords: constructionRecords,
				configurationTypeName: configurationTypeName,
				context: context,
				requiresSendable: sendableConfigurationTypeNames.contains(type.asSource),
			))
			fulfillers.formUnion(constructionRecords.flatMap(\.fulfillers))
			fulfillers.formUnion([typeRecords.first?.mockedTypeFulfiller].compactMap(\.self))
		}
		return (declarations: declarations, fulfillers: fulfillers)
	}

	/// The module-level configuration `record` describes, named `configurationTypeName`, and the extension of its type that
	/// holds a function for each of `constructionRecords`.
	private static func publicConfigurationDeclaration(
		of record: PublicConstructionRecord,
		constructionRecords: [PublicConstructionRecord],
		configurationTypeName: String,
		context: PublicMockContext,
		requiresSendable: Bool,
	) -> String {
		let concreteType = record.concreteType
		let admittedModules: Set<String?> = [context.moduleName, context.moduleNameByType[concreteType]]
		var members = record.childMembers.map { member in
			publicMember(member, context: context, admittedModules: admittedModules, requiresSendable: requiresSendable)
		}
		// Each default-valued parameter: optional, with `nil` keeping the declaration's default, unless the parameter is
		// optional itself, which the member holds as it is, defaulting to what the declaration's default evaluates to.
		for defaultField in record.defaultFields {
			members.append(publicDefaultMember(of: defaultField, concreteType: concreteType, context: context, admittedModules: admittedModules, requiresSendable: requiresSendable))
		}
		let builderType = record.builderType(requiresSendable: requiresSendable)
		members.append(PublicStructMember(
			name: ReservedName.configurationBuilderPropertyName,
			typeSource: builderType,
			parameterTypeSource: builderType,
			access: context.access(ofTypes: record.builderParameterTypes + [concreteType], admittedModules: admittedModules).level,
			defaultExpression: "nil",
			omittedValue: "nil",
			isUnlabeled: true,
			documentation: "Overrides how `\(concreteType.asSource)` is constructed. Parameters match the type’s initializer or custom mock method.",
		))
		var lines = [String]()
		lines.append("/// Configuration for how `\(concreteType.asSource)` is constructed within the public mock trees of \(context.moduleName.map { "module `\($0)`" } ?? "this module").")
		lines.append("nonisolated public struct \(configurationTypeName) {")
		lines.append(contentsOf: ScopeGenerator.publicStructBody(members: members, indent: ScopeGenerator.standardIndent))
		lines.append("}")
		lines.append("")
		lines.append("extension \(concreteType.asSource) {")
		// One provider per label, value type and default, across the type's constructions: two of one label differ in the
		// type they return, which each call's argument selects.
		var providers = [DefaultField]()
		for defaultField in ([record] + constructionRecords).flatMap(\.defaultFields)
			where defaultField.hasPublicProvider && !providers.contains(where: {
				$0.label == defaultField.label && $0.publicValueType == defaultField.publicValueType && $0.publicDefaultExpression == defaultField.publicDefaultExpression
			})
		{
			providers.append(defaultField)
		}
		for provider in providers {
			lines.append("\(ScopeGenerator.standardIndent)nonisolated static func \(PublicMockContext.providerName(label: provider.label))() -> \(provider.publicValueType.asSource) { \(provider.publicDefaultExpression) }")
		}
		for constructionRecord in constructionRecords {
			lines.append(contentsOf: constructionRecord.constructionFunctionLines(requiresSendable: requiresSendable))
		}
		lines.append("}")
		// A public member's default names its provider through a module-level function, which a public declaration's default
		// argument can name without naming the type, which may be narrower than `public`.
		for defaultField in record.defaultFields where defaultField.hasPublicProvider && context.access(ofTypes: [defaultField.publicValueType], admittedModules: admittedModules).level == .public {
			lines.append("@usableFromInline nonisolated func \(context.forwarderName(of: concreteType, label: defaultField.label))() -> \(defaultField.publicValueType.asSource) { \(publicProviderRead(of: concreteType, label: defaultField.label)) }")
		}
		return lines.joined(separator: "\n")
	}

	/// The member of a public configuration of `concreteType` that holds `defaultField`, as visible as its value's type.
	private static func publicDefaultMember(
		of defaultField: DefaultField,
		concreteType: TypeDescription,
		context: PublicMockContext,
		admittedModules: Set<String?>,
		requiresSendable: Bool,
	) -> PublicStructMember {
		let valueType = defaultField.publicValueType
		let access = context.access(ofTypes: [valueType], admittedModules: admittedModules).level
		guard valueType.isOptional else {
			return ScopeGenerator.publicDefaultMember(
				name: defaultField.label,
				valueType: .optional(valueType),
				access: access,
				defaultExpression: "nil",
				omittedValue: "nil",
				requiresSendable: requiresSendable,
				documentation: "`nil` keeps the default of `\(concreteType.asSource)`’s `\(defaultField.label.spelledWithoutBackticks)`.",
			)
		}
		let provider = publicProviderRead(of: concreteType, label: defaultField.label)
		let forwarder = "\(context.forwarderName(of: concreteType, label: defaultField.label))()"
		return ScopeGenerator.publicDefaultMember(
			name: defaultField.label,
			valueType: valueType,
			access: access,
			defaultExpression: defaultField.hasPublicProvider ? (access == .public ? forwarder : provider) : "nil",
			omittedValue: defaultField.hasPublicProvider ? provider : "nil",
			requiresSendable: requiresSendable,
			documentation: "The default of `\(concreteType.asSource)`’s `\(defaultField.label.spelledWithoutBackticks)` unless set.",
		)
	}

	/// The member of a public struct that configures a child as `member` describes it, `@Sendable` where the struct is read
	/// in a `@Sendable` builder function (`requiresSendable`) or the child is built in one.
	private static func publicMember(
		_ member: PublicConstructionRecord.ChildMember,
		context: PublicMockContext,
		admittedModules: Set<String?>,
		requiresSendable: Bool,
	) -> PublicStructMember {
		switch member.source {
		case let .calledMockOverrides(typeSource, defaultValue):
			return PublicStructMember(
				name: member.name,
				typeSource: typeSource,
				parameterTypeSource: typeSource,
				access: .public,
				defaultExpression: defaultValue,
				omittedValue: defaultValue,
				isUnlabeled: false,
				documentation: nil,
			)
		case let .built(isConfigured, builderClosureType, childRequiresSendable, accessTypes):
			if isConfigured, let configurationTypeName = context.configurationTypeNameByType[member.concreteType] {
				return PublicStructMember(
					name: member.name,
					typeSource: configurationTypeName,
					parameterTypeSource: configurationTypeName,
					access: .public,
					defaultExpression: ".init()",
					omittedValue: ".init()",
					isUnlabeled: false,
					documentation: nil,
				)
			}
			let closureType = "(\(requiresSendable || childRequiresSendable ? "@Sendable " : "")\(builderClosureType))?"
			return PublicStructMember(
				name: member.name,
				typeSource: closureType,
				parameterTypeSource: closureType,
				access: context.access(ofTypes: accessTypes, admittedModules: admittedModules).level,
				defaultExpression: "nil",
				omittedValue: "nil",
				isUnlabeled: false,
				documentation: nil,
			)
		}
	}
}

extension MockLowering.PublicConstructionRecord {
	/// The construction a public mock's `node`, whose children `children` are in inline order, builds its type with: its
	/// initializer, or an extension's `instantiate(…)`.
	init(of node: MockLowering.ConstantNode, children: [MockLowering.TreeNode]) {
		// The arguments the construction is passed, which leave out a parameter left to its default
		// (`ScopeGenerator.MockConstruction.callSiteArguments`).
		// Or its hand-written mock, which a public mock builds it with too.
		let construction = ScopeGenerator.MockConstruction(instantiable: node.instantiable, useMockInitializer: node.usesMockInitializer, builderTypesDeclaredEscaping: [])
		self.init(
			concreteType: construction.concreteType,
			usesMockInitializer: node.usesMockInitializer,
			isExtensionBased: construction.isExtensionBased,
			customMockName: construction.customMockName,
			constructionAttributes: construction.constructionAttributes,
			// What the hand-written mock returns, for a node built with it
			// (`MockLowering.PublicConstructionRecord.constructionReturnType`).
			constructionReturnType: construction.constructionReturnType,
			sendsArguments: node.instantiable.declarationType == .actorType && !node.usesMockInitializer,
			arguments: construction.callSiteArguments.map { Argument(label: $0.label, innerLabel: $0.innerLabel, typeDescription: $0.typeDescription) },
			builderParameterTypes: construction.builderParameterTypes,
			childMembers: children.compactMap(ChildMember.init(of:)),
			defaultFields: node.defaultFields,
		)
	}

	/// The name of the construction function: `__safeDI_mock` for the hand-written mock, else `__safeDI_init`.
	var functionName: String {
		usesMockInitializer ? ReservedName.publicMockFunctionName : "\(ReservedName.builderFunctionNamePrefix)init"
	}

	/// The type of the builder that overrides the construction: optional, handed each argument, returning the concrete type,
	/// `@Sendable` where the configuration is `@Sendable`-typed.
	func builderType(requiresSendable: Bool) -> String {
		"(\(requiresSendable ? "@Sendable " : "")(\(builderParameterTypes.map { sending($0.asSource) }.joined(separator: ", "))) -> \(concreteType.asSource))?"
	}

	/// `parameter` spelled `sending` where the construction is an actor's initializer.
	private func sending(_ parameter: String) -> String {
		sendsArguments ? "sending \(parameter)" : parameter
	}

	/// The construction function, indented as a member of its type's extension: it calls the builder when it is set, and
	/// otherwise the construction, with the attributes the construction spells, as written.
	func constructionFunctionLines(requiresSendable: Bool) -> [String] {
		let indent = ScopeGenerator.standardIndent
		let builderName = ReservedName.configurationBuilderPropertyName
		var parameters = [String]()
		var resolutions = [String]()
		var values = [String]()
		for argument in arguments {
			let name = argument.innerLabel
			// A default the function takes optionally and resolves where it is not passed, an `@autoclosure` one as a
			// closure it calls here, once per construction, as in production.
			if let defaultField = defaultFields.first(where: { $0.label == argument.label }) {
				let valueType = defaultField.publicValueType
				if valueType.isOptional {
					parameters.append("\(name.spelledAsArgumentLabel): \(sending(valueType.asSource))")
				} else {
					parameters.append("\(name.spelledAsArgumentLabel): \(sending(TypeDescription.optional(valueType).asSource))")
					resolutions.append("\(indent)\(indent)let \(name) = \(name) ?? (\(defaultField.publicDefaultExpression))")
				}
				values.append(defaultField.isAutoclosure ? "\(name)()" : name)
			} else {
				parameters.append("\(name.spelledAsArgumentLabel): \(sending(argument.typeDescription.asFunctionParameter.asSource))")
				values.append(name)
			}
		}
		parameters.append("\(builderName): \(builderType(requiresSendable: requiresSendable))")
		let constructionArguments = zip(arguments, values).map { argument, value in
			argument.label == "_" ? value : "\(argument.label.spelledAsArgumentLabel): \(value)"
		}.joined(separator: ", ")
		let construction = if usesMockInitializer {
			"\(concreteType.asSource).\(customMockName ?? InstantiableVisitor.mockMethodName)(\(constructionArguments))"
		} else if isExtensionBased {
			"\(concreteType.asSource).\(InstantiableVisitor.instantiateMethodName)(\(constructionArguments))"
		} else {
			"\(concreteType.asSource)(\(constructionArguments))"
		}
		let attributesPrefix = constructionAttributes.map { "\($0) " } ?? ""
		var lines = ["\(indent)\(attributesPrefix)static func \(functionName)(\(parameters.joined(separator: ", "))) -> \(constructionReturnType.asSource) {"]
		lines.append(contentsOf: resolutions)
		lines.append("\(indent)\(indent)\(resolutions.isEmpty ? "" : "return ")if let \(builderName) { \(builderName)(\(values.joined(separator: ", "))) } else { \(construction) }")
		lines.append("\(indent)}")
		return lines
	}
}

extension MockLowering.PublicConstructionRecord.ChildMember {
	/// The member that configures `child`, or `nil` for an alias, which the overrides hold no member of.
	init?(of child: MockLowering.TreeNode) {
		switch child {
		case let .built(node):
			self.init(
				name: node.bindingName,
				concreteType: node.instantiable.concreteInstantiable,
				source: .built(
					isConfigured: node.hasConfiguration,
					builderClosureType: node.builderClosureType,
					requiresSendable: node.requiresSendable,
					accessTypes: (node.instantiable.initializer?.arguments ?? []).map(\.typeDescription) + [node.property.typeDescription.asInstantiatedType],
				),
			)
		case .alias:
			return nil
		case let .cycleClosing(_, bindingName, concreteType):
			// A node that closes a cycle on a node of its type is configured by that type's configuration, as the emitter
			// nests it (a property cycle needs one).
			self.init(
				name: bindingName,
				concreteType: concreteType,
				source: .built(isConfigured: true, builderClosureType: "", requiresSendable: false, accessTypes: []),
			)
		case let .publicMockCall(call):
			// A call whose override closure the calling mock cannot offer has no member.
			let field: MockLowering.OverridesField? = call.overridesField
			guard let field else { return nil }
			self.init(
				name: field.name,
				concreteType: call.calledType,
				source: .calledMockOverrides(typeSource: field.typeSource, defaultValue: field.defaultValue),
			)
		}
	}
}
