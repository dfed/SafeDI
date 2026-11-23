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

import Foundation

/// Stage D1, lane D: the `SafeDIMockConfiguration` structs of a module's mocks, lowered from the configuration records of
/// every root's lowering, as `generateMockCode` generates them from the emitter's nodes: one struct per concrete type,
/// from the first record of the type in root order, merged into the code of the mock root of that type, or else into
/// the module's shared configuration code.
extension MockLowering {
	/// The module's configuration code lowered from `roots`' records: each root's code with the configuration of its own
	/// type merged in, in `roots`' order, and the module's shared configuration code, `nil` where it has none; or the rule
	/// of the first root, in type order, whose lowering is unsupported, which decides every struct the module generates.
	static func configurationCode(
		of roots: [LoweredRoot],
		mockConditionalCompilation: String?,
		sendableConfigurationTypeNames: Set<String>,
		publicMockContext: PublicMockContext?,
	) -> Lowering<(mergedCodes: [String], configurationCode: String?)> {
		var loweredRoots = [(code: String, records: [ConfigurationRecord])]()
		var firstUnsupportedRoot: (mockedType: TypeDescription, rule: Rule)?
		for root in roots {
			switch root.lowered {
			case let .lowered(code, records):
				loweredRoots.append((code: code, records: records))
			case let .unsupported(rule):
				if firstUnsupportedRoot.map({ root.mockedType < $0.mockedType }) ?? true {
					firstUnsupportedRoot = (mockedType: root.mockedType, rule: rule)
				}
			}
		}
		if let firstUnsupportedRoot {
			return .unsupported(firstUnsupportedRoot.rule)
		}
		// D1 lane hook (lane C): a configuration `@Sendable`-typed, as a type a `Sendable` wrapper builds anywhere in the
		// module has, takes `@Sendable` closures (`configurationStruct(amongConfigurationsTypedSendable:)`); a public mock's,
		// and a public mock's module-level one too (`publicConfigurationDeclarations`); one with a child whose field the
		// lowering does not spell there is not lowered yet.
		guard !loweredRoots.contains(where: { $0.records.contains { record in
			sendableConfigurationTypeNames.contains(record.concreteType.asSource)
				&& record.publicConstruction == nil && record.childFields.contains { $0.sendableForm == nil }
		} }) else {
			return .unsupported(.wrapper)
		}
		let rootedTypeNames = Set(roots.map(\.mockedType.asSource))
		var seenTypeNames = Set<String>()
		var rootedStructs = [String: String]()
		var sharedExtensions = [(typeName: String, structCode: String)]()
		let recordsInRootOrder = zip(roots, loweredRoots).sorted { $0.0.mockedType < $1.0.mockedType }.map(\.1.records)
		let recordsReadingConfiguration = Self.recordsReadingConfiguration(of: loweredRoots.map(\.records))
		for records in recordsInRootOrder {
			// A public mock's records describe its module-level configurations, which are lowered after these.
			for record in records where record.publicConstruction == nil && record.beneathRepeatedAncestor == nil && seenTypeNames.insert(record.concreteType.asSource).inserted {
				let typeName = record.concreteType.asSource
				// The first record can be of a node that reads no overrides from the configuration, beneath a cycle edge,
				// built the other way from the nodes that read them: the configuration describes those that read them.
				let structRecord = recordsReadingConfiguration[record.concreteType].flatMap { recordReadingConfiguration in
					recordReadingConfiguration.oneWayConstruction?.requirements == record.oneWayConstruction?.requirements ? nil : recordReadingConfiguration
				} ?? record
				let structCode = structRecord.configurationStruct(amongConfigurationsTypedSendable: sendableConfigurationTypeNames)
				if rootedTypeNames.contains(typeName) {
					rootedStructs[typeName] = structCode
				} else {
					sharedExtensions.append((typeName: typeName, structCode: structCode))
				}
			}
		}
		// Then the configurations beneath repeated ancestors, a public mock's before an internal mock's, as
		// `generateMockCode` takes them.
		for isPublicMock in [true, false] {
			switch Self.configurationsBeneathRepeatedAncestors(of: recordsInRootOrder, isPublicMock: isPublicMock) {
			case let .lowered(records):
				// A public mock's configuration there is a module-level declaration, which this lowering does not lower yet.
				guard !isPublicMock || records.isEmpty else { return .unsupported(.cycle) }
				for record in records where seenTypeNames.insert(record.concreteType.asSource).inserted {
					let typeName = record.concreteType.asSource
					if rootedTypeNames.contains(typeName) {
						rootedStructs[typeName] = record.configurationStruct(amongConfigurationsTypedSendable: sendableConfigurationTypeNames)
					} else {
						sharedExtensions.append((typeName: typeName, structCode: record.configurationStruct(amongConfigurationsTypedSendable: sendableConfigurationTypeNames)))
					}
				}
			case let .unsupported(rule):
				return .unsupported(rule)
			}
		}
		let mergedCodes = zip(roots, loweredRoots).map { root, loweredRoot in
			let code = loweredRoot.code
			guard let structCode = rootedStructs[root.mockedType.asSource] else { return code }
			let configurationCode = Self.configurationCode(
				extensions: [(typeName: root.mockedType.asSource, structCode: structCode)],
				publicDeclarations: [],
				mockConditionalCompilation: mockConditionalCompilation,
			)
			return code + "\n\n" + configurationCode.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		let publicRecords = recordsInRootOrder.flatMap { records in records.compactMap(\.publicConstruction) }
		var publicDeclarations = [String]()
		if let publicMockContext {
			switch Self.publicConfigurationDeclarations(of: publicRecords, context: publicMockContext, sendableConfigurationTypeNames: sendableConfigurationTypeNames) {
			case let .lowered(declarations):
				publicDeclarations = declarations
			case let .unsupported(rule):
				return .unsupported(rule)
			}
		}
		let configurationCode = sharedExtensions.isEmpty && publicDeclarations.isEmpty
			? nil
			: Self.configurationCode(extensions: sharedExtensions, publicDeclarations: publicDeclarations, mockConditionalCompilation: mockConditionalCompilation)
		return .lowered((mergedCodes: mergedCodes, configurationCode: configurationCode))
	}

	/// For each type, the first record, across `recordsByRoot` in the roots' order and each root's records in the order its
	/// walk entered them, of a node that reads its configuration, no edge in `cycleEdges` above it: of one built with the
	/// type's initializer where there is one, else of one built with its hand-written mock, as
	/// `DependencyTreeGenerator.validateConfigurationsAreBuiltOneWay` returns its nodes.
	private static func recordsReadingConfiguration(of recordsByRoot: [[ConfigurationRecord]]) -> [TypeDescription: ConfigurationRecord] {
		var firstRecords = [TypeDescription: (builtWithoutMock: ConfigurationRecord?, builtByMock: ConfigurationRecord?)]()
		for records in recordsByRoot {
			let recordsInWalkOrder = records.compactMap { record in record.oneWayConstruction.map { (record: record, construction: $0) } }
				.sorted { $0.construction.walkOrder < $1.construction.walkOrder }
			for (record, construction) in recordsInWalkOrder where !construction.isBeneathCycleEdge {
				var first = firstRecords[record.concreteType] ?? (builtWithoutMock: nil, builtByMock: nil)
				if record.usesMockInitializer {
					first.builtByMock = first.builtByMock ?? record
				} else {
					first.builtWithoutMock = first.builtWithoutMock ?? record
				}
				firstRecords[record.concreteType] = first
			}
		}
		return firstRecords.compactMapValues { $0.builtWithoutMock ?? $0.builtByMock }
	}

	/// The records `recordsInRootOrder`, each root's records in roots' type order, generate a configuration from beneath
	/// their repeated ancestors, for the mocks of one kind, in the order `generateMockCode` generates them
	/// (`DependencyTreeGenerator.configurationsBeneathRepeatedAncestors`): each type a construction there reads the
	/// configuration of, and each type whose configuration one of their configurations nests, transitively, unless a node of
	/// the kind above every repeated ancestor configures the type; each from a node built with its initializer wherever one
	/// is, else from one built with its hand-written mock. A nested configuration of a node that records none, as one that
	/// closes a cycle, is not lowered yet.
	private static func configurationsBeneathRepeatedAncestors(
		of recordsInRootOrder: [[ConfigurationRecord]],
		isPublicMock: Bool,
	) -> Lowering<[ConfigurationRecord]> {
		struct Candidate {
			let rootIndex: Int
			let record: ConfigurationRecord
		}
		struct Construction: Hashable {
			let concreteType: TypeDescription
			let usesMockInitializer: Bool
		}
		var typesConfiguredAbove = Set<TypeDescription>()
		for records in recordsInRootOrder {
			for record in records where record.beneathRepeatedAncestor == nil && (record.publicConstruction != nil) == isPublicMock {
				typesConfiguredAbove.insert(record.concreteType)
			}
		}
		var candidates = [Candidate]()
		var candidateConstructions = Set<Construction>()
		func addCandidate(_ record: ConfigurationRecord, ofRootAt rootIndex: Int) -> Bool {
			let isNew = !typesConfiguredAbove.contains(record.concreteType)
				&& candidateConstructions.insert(Construction(concreteType: record.concreteType, usesMockInitializer: record.usesMockInitializer)).inserted
			if isNew {
				candidates.append(Candidate(rootIndex: rootIndex, record: record))
			}
			return isNew
		}
		for (rootIndex, records) in recordsInRootOrder.enumerated() {
			for record in records {
				guard let beneath = record.beneathRepeatedAncestor, beneath.isPublicMock == isPublicMock, beneath.readsConfiguration else { continue }
				_ = addCandidate(record, ofRootAt: rootIndex)
			}
		}
		var readTypes = [TypeDescription]()
		for candidate in candidates where !readTypes.contains(candidate.record.concreteType) {
			readTypes.append(candidate.record.concreteType)
		}

		var chosenCandidates = [TypeDescription: Candidate]()
		var neededTypes = Set<TypeDescription>()
		var foundCandidate: Bool
		repeat {
			chosenCandidates = [:]
			for candidate in candidates {
				let type = candidate.record.concreteType
				if let chosen = chosenCandidates[type] {
					if chosen.record.usesMockInitializer, !candidate.record.usesMockInitializer {
						chosenCandidates[type] = candidate
					}
				} else {
					chosenCandidates[type] = candidate
				}
			}
			foundCandidate = false
			neededTypes = Set(readTypes)
			var typesToWalk = readTypes
			while let type = typesToWalk.popLast() {
				guard let chosen = chosenCandidates[type] else { continue }
				for child in chosen.record.beneathRepeatedAncestor?.nestedChildren ?? [] where !typesConfiguredAbove.contains(child.concreteType) {
					guard let recordIndex = child.recordIndex else { return .unsupported(.cycle) }
					if addCandidate(recordsInRootOrder[chosen.rootIndex][recordIndex], ofRootAt: chosen.rootIndex) {
						foundCandidate = true
					}
					if neededTypes.insert(child.concreteType).inserted {
						typesToWalk.append(child.concreteType)
					}
				}
			}
		} while foundCandidate

		var typesInOrder = [TypeDescription]()
		for candidate in candidates where neededTypes.contains(candidate.record.concreteType) && !typesInOrder.contains(candidate.record.concreteType) {
			typesInOrder.append(candidate.record.concreteType)
		}
		return .lowered(typesInOrder.compactMap { chosenCandidates[$0]?.record })
	}

	/// The code that declares each of `extensions`' structs in an extension of its type, then `publicDeclarations`, under the
	/// mock condition.
	private static func configurationCode(
		extensions: [(typeName: String, structCode: String)],
		publicDeclarations: [String],
		mockConditionalCompilation: String?,
	) -> String {
		let body = (extensions.map { "extension \($0.typeName) {\n\($0.structCode)\n}" } + publicDeclarations).joined(separator: "\n\n")
		return if let mockConditionalCompilation {
			"#if \(mockConditionalCompilation)\n\(body)\n#endif\n"
		} else {
			"\(body)\n"
		}
	}
}

extension MockLowering {
	/// The member of a configuration that configures a node bound as `bindingName` that closes a cycle on a node of
	/// `concreteType`: that type's configuration, as the emitter nests the configuration of a node that repeats one around it
	/// (`ScopeGenerator.configurationField`), unless an edge in `cycleEdges` prunes it.
	static func cycleClosingOverridesField(boundAs bindingName: String, concreteType: TypeDescription) -> OverridesField? {
		OverridesField(
			name: bindingName,
			typeSource: "\(concreteType.asSource).\(ScopeGenerator.MockParameterNode.configurationStructName)",
			defaultValue: ".init()",
			sendability: .whenConfigurationIsTypedSendable(concreteType.asSource),
		)
	}

	/// The configured types around a node's children, which the walk restores when it leaves them.
	struct ConfiguredNodeEntry {
		/// Whether the node records its configuration: its type repeats no configured node around it, and it is beneath no
		/// node that does.
		let recordsConfiguration: Bool
		/// The node's type, which the walk inserted among the configured types around it, unless one there has it.
		fileprivate let insertedType: String?
		fileprivate let wasBeneathRepeatedConfiguredAncestor: Bool
		/// The order in which the walk entered the node's children, among every configured node's of the root.
		let walkOrder: Int

		/// Whether the node records the configuration the module's mocks may generate from a node beneath a repeated ancestor:
		/// its type repeats no configured node around it, and it is beneath a node that does.
		var recordsBeneathRepeatedAncestor: Bool {
			insertedType != nil && wasBeneathRepeatedConfiguredAncestor
		}
	}

	/// A configured node whose children the walk finished, as its parent reads it: its property, and the index of its
	/// record among the root's, `nil` where it records none.
	struct FinishedConfiguredChild {
		let property: Property
		let recordIndex: Int?
	}
}

extension MockLowering.ConfigurationRecord {
	/// What `DependencyTreeGenerator.configurationsBeneathRepeatedAncestors` reads of a node beneath a node whose type
	/// repeats one around it (`ScopeGenerator.ConfigurationTypes.nodesBeneathRepeatedAncestors`).
	struct BeneathRepeatedAncestor: Sendable, Equatable {
		/// Whether code generated for the node reads its type's configuration: an internal mock's construction that reads a
		/// configuration built afresh, or any node a public mock builds with a construction function.
		let readsConfiguration: Bool
		let isPublicMock: Bool
		/// The children whose configurations the node's configuration nests
		/// (`ScopeGenerator.childrenWithNestedConfigurations(of:cycleEdges:)`), in order.
		let nestedChildren: [NestedChild]
	}

	/// A child whose configuration a configuration nests: its type, and the index of its record among the root's, `nil`
	/// where it records none, as a node that closes a cycle or repeats a type around it.
	struct NestedChild: Sendable, Equatable {
		let concreteType: TypeDescription
		let recordIndex: Int?
	}
}

extension MockLowering.Walk {
	/// Enters the children of a node of `concreteType`, as `ScopeGenerator.collectUniqueConfigurationTypes` walks them.
	mutating func enteringConfiguredNode(of concreteType: TypeDescription) -> MockLowering.ConfiguredNodeEntry {
		let typeName = concreteType.asSource
		let repeatsAncestor = !configuredAncestorTypes.insert(typeName).inserted
		let entry = MockLowering.ConfiguredNodeEntry(
			recordsConfiguration: !repeatsAncestor && !isBeneathRepeatedConfiguredAncestor,
			insertedType: repeatsAncestor ? nil : typeName,
			wasBeneathRepeatedConfiguredAncestor: isBeneathRepeatedConfiguredAncestor,
			walkOrder: configuredNodesEntered,
		)
		configuredNodesEntered += 1
		isBeneathRepeatedConfiguredAncestor = isBeneathRepeatedConfiguredAncestor || repeatsAncestor
		finishedConfiguredChildren.append([])
		return entry
	}

	/// Leaves the children `entry` entered, returning the configured ones the walk finished.
	mutating func leavingConfiguredNode(_ entry: MockLowering.ConfiguredNodeEntry) -> [MockLowering.FinishedConfiguredChild] {
		if let insertedType = entry.insertedType {
			configuredAncestorTypes.remove(insertedType)
		}
		isBeneathRepeatedConfiguredAncestor = entry.wasBeneathRepeatedConfiguredAncestor
		return finishedConfiguredChildren.popLast() ?? []
	}

	/// Tells the configured node around `node` that the walk finished it, with the index of its record, if any.
	mutating func finishConfiguredNode(_ node: MockLowering.ConstantNode, recordIndex: Int?) {
		guard !finishedConfiguredChildren.isEmpty else { return }
		finishedConfiguredChildren[finishedConfiguredChildren.count - 1].append(MockLowering.FinishedConfiguredChild(property: node.property, recordIndex: recordIndex))
	}

	/// Records the configuration of `node`, beneath a node whose type repeats one around it, with what the module's choice
	/// among such nodes reads (`ScopeGenerator.collectUniqueConfigurationTypes`): whether code generated for it reads the
	/// configuration, and the records of the children its configuration nests, which the walk finished as `finishedChildren`.
	mutating func recordBeneathRepeatedAncestor(
		_ node: MockLowering.ConstantNode,
		children: [MockLowering.TreeNode],
		finishedChildren: [MockLowering.FinishedConfiguredChild],
	) {
		let parentConcreteType = node.instantiable.concreteInstantiable.asSource
		// A child beneath an edge in `cycleEdges` has no member in its parent's configuration.
		let recordedChildren = children.filter { child in child.concreteType.map { !isPruned($0, beneath: parentConcreteType) } ?? true }
		var record = MockLowering.ConfigurationRecord(of: node, children: recordedChildren)
		record.beneathRepeatedAncestor = MockLowering.ConfigurationRecord.BeneathRepeatedAncestor(
			readsConfiguration: buildsPublicMock || readsConfigurationBuiltAfresh(of: node.instantiable, usesMockInitializer: node.usesMockInitializer),
			isPublicMock: buildsPublicMock,
			nestedChildren: recordedChildren.compactMap { child in
				switch child {
				case let .built(childNode):
					childNode.hasConfiguration
						? MockLowering.ConfigurationRecord.NestedChild(
							concreteType: childNode.instantiable.concreteInstantiable,
							recordIndex: finishedChildren.first(where: { $0.property == childNode.property })?.recordIndex,
						)
						: nil
				case let .cycleClosing(_, _, concreteType):
					MockLowering.ConfigurationRecord.NestedChild(concreteType: concreteType, recordIndex: nil)
				case .alias, .publicMockCall:
					// A call of another module's public mock nests that mock's overrides, no configuration.
					nil
				}
			},
		)
		configurationRecords.append(record)
		finishConfiguredNode(node, recordIndex: configurationRecords.count - 1)
	}
}

extension MockLowering.ConfigurationRecord {
	/// The `SafeDIMockConfiguration` this record describes, nested in an extension of its type: a field per child, one per
	/// default-valued parameter, then the builder that overrides how the type is built, each held in the configuration's storage.
	// D1 lane hook (lane C): a configuration `@Sendable`-typed, `typeNames` naming the types whose configurations are.
	func configurationStruct(amongConfigurationsTypedSendable typeNames: Set<String>) -> String {
		let requiresSendable = typeNames.contains(concreteType.asSource)
		let indent = ScopeGenerator.standardIndent
		let innerIndent = "\(indent)\(ScopeGenerator.standardIndent)"
		let parameterIndent = "\(innerIndent)\(ScopeGenerator.standardIndent)"
		var lines = [
			"\(indent)/// Configuration for how this type is constructed within a mock tree.",
			"\(indent)struct \(ScopeGenerator.MockParameterNode.configurationStructName) {",
		]
		var parameters = [String]()
		var fields = [ConfigurationStorage.Field]()
		for childField in childFields {
			// A child's field in a configuration `@Sendable`-typed is `@Sendable`, proven `Sendable` (`configurationField`).
			let (typeSource, defaultValue, isProvenSendable) = if requiresSendable, let sendableForm = childField.sendableForm {
				(sendableForm.typeSource, sendableForm.defaultValue, sendableForm.configuredTypeName.map(typeNames.contains) ?? true)
			} else {
				(childField.typeSource, childField.defaultValue, false)
			}
			parameters.append("\(parameterIndent)\(childField.name): \(typeSource) = \(defaultValue)")
			fields.append(ConfigurationStorage.Field(
				name: childField.name,
				typeSource: typeSource,
				parameterTypeSource: typeSource,
				accessPrefix: "",
				documentation: nil,
				isProvenSendable: isProvenSendable,
			))
		}
		for defaultField in defaultFields {
			let (parameter, field) = requiresSendable
				? defaultField.sendableConfigurationParameter(indent: parameterIndent)
				: defaultField.configurationParameter(indent: parameterIndent)
			parameters.append(parameter)
			fields.append(field)
		}
		let builderType = "(\(requiresSendable ? "@Sendable " : "")\(concreteBuilderClosureType))?"
		parameters.append("\(parameterIndent)_ \(ReservedName.configurationBuilderPropertyName): \(builderType) = nil")
		fields.append(ConfigurationStorage.Field(
			name: ReservedName.configurationBuilderPropertyName,
			typeSource: builderType,
			parameterTypeSource: builderType,
			accessPrefix: "",
			documentation: Self.builderDocumentation,
			isProvenSendable: requiresSendable,
		))
		let storage = ConfigurationStorage(fields: fields)
		lines.append("\(innerIndent)init(")
		lines.append(parameters.joined(separator: ",\n"))
		lines.append("\(innerIndent)) {")
		lines.append(contentsOf: storage.initialization(to: fields.map(\.name), indent: parameterIndent))
		lines.append("\(innerIndent)}")
		lines.append("")
		lines.append(contentsOf: storage.readers(indent: innerIndent))
		lines.append("")
		lines.append(contentsOf: storage.declarations(indent: innerIndent))
		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}

	/// The documentation of the builder a configuration holds.
	private static let builderDocumentation = "Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used."
}

extension MockLoweringShadow {
	/// How the configurations lowered from `roots`' records compare with those the emitter generated: one comparison of
	/// each root's merged code, then one of the module's shared configuration code, `emittedConfigurationCode`.
	static func configurationComparisons(
		of roots: [MockLowering.LoweredRoot],
		emittedConfigurationCode: String?,
		mockConditionalCompilation: String?,
		sendableConfigurationTypeNames: Set<String>,
		publicMockContext: PublicMockContext?,
	) -> [Comparison] {
		var comparisons = [Comparison]()
		switch MockLowering.configurationCode(
			of: roots,
			mockConditionalCompilation: mockConditionalCompilation,
			sendableConfigurationTypeNames: sendableConfigurationTypeNames,
			publicMockContext: publicMockContext,
		) {
		case let .lowered((mergedCodes, configurationCode)):
			for (root, mergedCode) in zip(roots, mergedCodes) {
				comparisons.append(Comparison(
					mockedType: root.mockedType.asSource,
					outcome: outcome(comparing: .lowered(mergedCode), with: root.emittedMergedCode),
					subject: .mergedCode,
				))
			}
			comparisons.append(Comparison(
				mockedType: "",
				outcome: outcome(comparing: .lowered(configurationCode ?? ""), with: emittedConfigurationCode ?? ""),
				subject: .moduleConfigurations,
			))
		case let .unsupported(rule):
			for root in roots {
				comparisons.append(Comparison(mockedType: root.mockedType.asSource, outcome: .unsupported(rule), subject: .mergedCode))
			}
			comparisons.append(Comparison(mockedType: "", outcome: .unsupported(rule), subject: .moduleConfigurations))
		}
		return comparisons
	}
}

extension MockLowering.DefaultField {
	// D1 lane hook (lane C): a default-valued field of a configuration `@Sendable`-typed.
	/// The field's parameter of a configuration `@Sendable`-typed, at `indent`, and the field its storage holds: a closure
	/// `@Sendable` at its top, or, for any other value, a `@Sendable` closure that returns it, which the construction calls
	/// (`ScopeGenerator.generateConfigurationStruct`).
	func sendableConfigurationParameter(indent: String) -> (parameter: String, field: ConfigurationStorage.Field) {
		let field = { (typeSource: String, parameterTypeSource: String) in
			ConfigurationStorage.Field(
				name: label,
				typeSource: typeSource,
				parameterTypeSource: parameterTypeSource,
				accessPrefix: "",
				documentation: nil,
				isProvenSendable: true,
			)
		}
		if isClosureType, !isAutoclosure {
			let closureSendable = valueTypeDescription.isSendableFunction ? "" : "@Sendable "
			return (
				parameter: "\(indent)\(label): \(closureSendable)@escaping \(valueTypeSource) = \(defaultExpression)",
				field: field("\(closureSendable)\(valueTypeSource)", "\(closureSendable)@escaping \(valueTypeSource)"),
			)
		} else {
			return (
				parameter: "\(indent)\(label): @autoclosure @escaping @Sendable () -> \(valueTypeSource) = \(ScopeGenerator.autoclosureDefault(defaultExpression))",
				field: field("@Sendable () -> \(valueTypeSource)", "@escaping @Sendable () -> \(valueTypeSource)"),
			)
		}
	}
}
