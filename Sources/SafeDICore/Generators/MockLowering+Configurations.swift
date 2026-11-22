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
		// A configuration `@Sendable`-typed, as a type a `Sendable` wrapper builds anywhere in the module has, takes
		// `@Sendable` closures, which lane B's family lowers.
		guard !loweredRoots.contains(where: { $0.records.contains { sendableConfigurationTypeNames.contains($0.concreteType.asSource) } }) else {
			return .unsupported(.wrapper)
		}
		let rootedTypeNames = Set(roots.map(\.mockedType.asSource))
		var seenTypeNames = Set<String>()
		var rootedStructs = [String: String]()
		var sharedExtensions = [(typeName: String, structCode: String)]()
		let recordsInRootOrder = zip(roots, loweredRoots).sorted { $0.0.mockedType < $1.0.mockedType }.map(\.1.records)
		for records in recordsInRootOrder {
			for record in records where seenTypeNames.insert(record.concreteType.asSource).inserted {
				let typeName = record.concreteType.asSource
				let structCode = record.configurationStruct
				if rootedTypeNames.contains(typeName) {
					rootedStructs[typeName] = structCode
				} else {
					sharedExtensions.append((typeName: typeName, structCode: structCode))
				}
			}
		}
		let mergedCodes = zip(roots, loweredRoots).map { root, loweredRoot in
			let code = loweredRoot.code
			guard let structCode = rootedStructs[root.mockedType.asSource] else { return code }
			let configurationCode = Self.configurationCode(
				extensions: [(typeName: root.mockedType.asSource, structCode: structCode)],
				mockConditionalCompilation: mockConditionalCompilation,
			)
			return code + "\n\n" + configurationCode.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		let configurationCode = sharedExtensions.isEmpty
			? nil
			: Self.configurationCode(extensions: sharedExtensions, mockConditionalCompilation: mockConditionalCompilation)
		return .lowered((mergedCodes: mergedCodes, configurationCode: configurationCode))
	}

	/// The code that declares each of `extensions`' structs in an extension of its type, under the mock condition.
	private static func configurationCode(
		extensions: [(typeName: String, structCode: String)],
		mockConditionalCompilation: String?,
	) -> String {
		let body = extensions.map { "extension \($0.typeName) {\n\($0.structCode)\n}" }.joined(separator: "\n\n")
		return if let mockConditionalCompilation {
			"#if \(mockConditionalCompilation)\n\(body)\n#endif\n"
		} else {
			"\(body)\n"
		}
	}
}

extension MockLowering.ConfigurationRecord {
	/// The `SafeDIMockConfiguration` this record describes, nested in an extension of its type: a field per child, then
	/// the builder that overrides how the type is built, each held in the configuration's storage.
	var configurationStruct: String {
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
			parameters.append("\(parameterIndent)\(childField.name): \(childField.typeSource) = \(childField.defaultValue)")
			fields.append(ConfigurationStorage.Field(
				name: childField.name,
				typeSource: childField.typeSource,
				parameterTypeSource: childField.typeSource,
				accessPrefix: "",
				documentation: nil,
				isProvenSendable: false,
			))
		}
		let builderType = "(\(concreteBuilderClosureType))?"
		parameters.append("\(parameterIndent)_ \(ReservedName.configurationBuilderPropertyName): \(builderType) = nil")
		fields.append(ConfigurationStorage.Field(
			name: ReservedName.configurationBuilderPropertyName,
			typeSource: builderType,
			parameterTypeSource: builderType,
			accessPrefix: "",
			documentation: Self.builderDocumentation,
			isProvenSendable: false,
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
		publicMockContext _: PublicMockContext?,
	) -> [Comparison] {
		var comparisons = [Comparison]()
		switch MockLowering.configurationCode(of: roots, mockConditionalCompilation: mockConditionalCompilation, sendableConfigurationTypeNames: sendableConfigurationTypeNames) {
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
