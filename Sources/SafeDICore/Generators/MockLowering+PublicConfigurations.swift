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
	/// initializer's before the hand-written mock's; or the first rule a record meets that the lowering does not lower yet.
	/// `records` are every public mock root's, in root order, each root's in the order its walk finished them.
	static func publicConfigurationDeclarations(
		of records: [PublicConstructionRecord],
		context: PublicMockContext,
	) -> Lowering<[String]> {
		var recordsByType = [TypeDescription: [PublicConstructionRecord]]()
		var typesInOrder = [TypeDescription]()
		for record in records {
			guard !record.hasDefaultParameters else { return .unsupported(.defaultValuedParameter) }
			if recordsByType[record.concreteType] == nil {
				typesInOrder.append(record.concreteType)
			}
			recordsByType[record.concreteType, default: []].append(record)
		}
		var declarations = [String]()
		for type in typesInOrder {
			guard let typeRecords = recordsByType[type],
			      let structRecord = typeRecords.first,
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
			))
		}
		return .lowered(declarations)
	}

	/// The module-level configuration `record` describes, named `configurationTypeName`, and the extension of its type that
	/// holds a function for each of `constructionRecords`.
	private static func publicConfigurationDeclaration(
		of record: PublicConstructionRecord,
		constructionRecords: [PublicConstructionRecord],
		configurationTypeName: String,
		context: PublicMockContext,
	) -> String {
		let concreteType = record.concreteType
		let admittedModules: Set<String?> = [context.moduleName, context.moduleNameByType[concreteType]]
		var members = record.childMembers.map { member in
			publicMember(member, context: context, admittedModules: admittedModules, requiresSendable: false)
		}
		let builderType = record.builderType
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
		for constructionRecord in constructionRecords {
			lines.append(contentsOf: constructionRecord.constructionFunctionLines)
		}
		lines.append("}")
		return lines.joined(separator: "\n")
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
		let initializer = node.instantiable.initializer
		let arguments = initializer?.arguments ?? []
		self.init(
			concreteType: node.instantiable.concreteInstantiable,
			usesMockInitializer: false,
			isExtensionBased: node.instantiable.declarationType.isExtension,
			customMockName: nil,
			constructionIsolation: initializer?.spelledIsolation,
			constructionReturnType: node.instantiable.concreteInstantiable,
			arguments: arguments.map { Argument(label: $0.label, innerLabel: $0.innerLabel, typeDescription: $0.typeDescription) },
			builderParameterTypes: arguments.map { argument in
				(argument.typeDescription.strippingEscaping.autoclosureValueType ?? argument.typeDescription)
					.asFunctionParameter(amongTypesDeclaredEscaping: [])
			},
			childMembers: children.compactMap(ChildMember.init(of:)),
			hasDefaultParameters: arguments.contains(where: \.hasDefaultValue),
		)
	}

	/// The name of the construction function: `__safeDI_mock` for the hand-written mock, else `__safeDI_init`.
	var functionName: String {
		usesMockInitializer ? ReservedName.publicMockFunctionName : "\(ReservedName.builderFunctionNamePrefix)init"
	}

	/// The type of the builder that overrides the construction: optional, handed each argument, returning the concrete type.
	var builderType: String {
		"((\(builderParameterTypes.map(\.asSource).joined(separator: ", "))) -> \(concreteType.asSource))?"
	}

	/// The construction function, indented as a member of its type's extension: it calls the builder when it is set, and
	/// otherwise the construction, with the isolation the construction spells.
	var constructionFunctionLines: [String] {
		let indent = ScopeGenerator.standardIndent
		let builderName = ReservedName.configurationBuilderPropertyName
		var parameters = arguments.map { "\($0.innerLabel.spelledAsArgumentLabel): \($0.typeDescription.asFunctionParameter.asSource)" }
		parameters.append("\(builderName): \(builderType)")
		let values = arguments.map(\.innerLabel)
		let constructionArguments = arguments.map { argument in
			argument.label == "_" ? argument.innerLabel : "\(argument.label.spelledAsArgumentLabel): \(argument.innerLabel)"
		}.joined(separator: ", ")
		let construction = if usesMockInitializer {
			"\(concreteType.asSource).\(customMockName ?? InstantiableVisitor.mockMethodName)(\(constructionArguments))"
		} else if isExtensionBased {
			"\(concreteType.asSource).\(InstantiableVisitor.instantiateMethodName)(\(constructionArguments))"
		} else {
			"\(concreteType.asSource)(\(constructionArguments))"
		}
		let isolationPrefix = constructionIsolation.map { "\($0) " } ?? ""
		return [
			"\(indent)\(isolationPrefix)static func \(functionName)(\(parameters.joined(separator: ", "))) -> \(constructionReturnType.asSource) {",
			"\(indent)\(indent)if let \(builderName) { \(builderName)(\(values.joined(separator: ", "))) } else { \(construction) }",
			"\(indent)}",
		]
	}
}

extension MockLowering.PublicConstructionRecord.ChildMember {
	/// The member that configures `child`, or `nil` for an alias or a cycle closer, which the overrides hold no member of.
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
		case .alias, .cycleClosing:
			return nil
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
