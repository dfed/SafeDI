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
import SafeDICore
import SwiftParser

// MARK: - Overriding every place of a mock's configuration tree

/// A mock's configuration tree as one release generated it, read from the `SafeDIOverrides` and
/// `SafeDIMockConfiguration` declarations of its generated files: what a test can override at each place of the mock's
/// tree. Release acceptance overrides every place at once with the tree the older release generated, since an adopter's
/// test is written against that release's API, and compares what each release's mock builds with those overrides.
struct ReleaseMockConfigurationTree: Equatable {
	/// A field of an overrides or configuration initializer.
	struct Field: Equatable {
		enum Kind: Equatable {
			/// A nested `<Type>.SafeDIMockConfiguration`, by the type's name as the field spells it.
			case configuration(typeName: String)
			/// A closure that builds the value: its parameter types, in order, and the type it returns.
			case builder(parameterTypes: [String], returnType: String)
		}

		let label: String
		let kind: Kind
	}

	/// A configuration's fields: the nested configurations and builders, then the type's own builder, `nil` when its
	/// configuration takes none.
	struct Configuration: Equatable {
		let fields: [Field]
		let builder: Field.Kind?
	}

	init(generatedFiles: [String: String]) {
		var overridesByTypeName = [String: [Field]]()
		var configurationByTypeName = [String: Configuration]()
		for fileName in generatedFiles.keys.sorted() {
			guard let contents = generatedFiles[fileName] else { continue }
			let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
			var extendedTypeName: String?
			var index = 0
			while index < lines.count {
				let line = lines[index]
				index += 1
				if line.hasSuffix("{"), let keyword = line.range(of: "extension "), keyword.lowerBound == line.startIndex || line[..<keyword.lowerBound].hasSuffix(" ") {
					extendedTypeName = line[keyword.upperBound...].split(separator: " ").first.map(String.init)
					continue
				}
				let isOverrides = line.hasSuffix("struct SafeDIOverrides {")
				let isConfiguration = line.hasSuffix("struct SafeDIMockConfiguration {")
				guard isOverrides || isConfiguration, let typeName = extendedTypeName else { continue }
				guard let initializerStart = lines[index...].firstIndex(where: { $0.hasSuffix("init(") }) else { continue }
				var fields = [Field]()
				var builder: Field.Kind?
				var parameterIndex = initializerStart + 1
				while parameterIndex < lines.count, !lines[parameterIndex].hasPrefix(")") {
					let parameter = lines[parameterIndex]
					parameterIndex += 1
					guard let (label, kind) = Self.field(parameter) else { continue }
					if label == "_ safeDIBuilder" {
						builder = kind
					} else {
						fields.append(Field(label: label, kind: kind))
					}
				}
				index = parameterIndex
				if isOverrides {
					if overridesByTypeName[typeName] == nil {
						overridesByTypeName[typeName] = fields
					}
				} else if configurationByTypeName[typeName] == nil {
					configurationByTypeName[typeName] = Configuration(fields: fields, builder: builder)
				}
			}
		}
		self.overridesByTypeName = overridesByTypeName
		self.configurationByTypeName = configurationByTypeName
	}

	/// The fields of each mocked type's `SafeDIOverrides`, by the type's name.
	let overridesByTypeName: [String: [Field]]
	/// Each type's `SafeDIMockConfiguration`, by the type's name.
	let configurationByTypeName: [String: Configuration]

	/// A parameter line of an overrides or configuration initializer, `label: Type = default,`, as a field; `nil` for
	/// a parameter that is neither a nested configuration nor a builder closure that is neither `async` nor `throws`.
	static func field(_ parameter: String) -> (label: String, kind: Field.Kind)? {
		var declaration = parameter.hasSuffix(",") ? String(parameter.dropLast()) : parameter
		guard let colon = declaration.range(of: ": ") else { return nil }
		let label = String(declaration[..<colon.lowerBound])
		declaration = String(declaration[colon.upperBound...])
		if let defaultStart = declaration.range(of: " = ", options: .backwards) {
			declaration = String(declaration[..<defaultStart.lowerBound])
		}
		let type = declaration.replacingOccurrences(of: "@escaping ", with: "")
		if type.hasSuffix(".SafeDIMockConfiguration") {
			return (label, .configuration(typeName: String(type.dropLast(".SafeDIMockConfiguration".count))))
		}
		guard type.hasPrefix("("), type.hasSuffix(")?") else { return nil }
		var closure = Substring(type.dropFirst().dropLast(2))
		for attribute in ["@Sendable ", "@MainActor "] where closure.hasPrefix(attribute) {
			closure = closure.dropFirst(attribute.count)
		}
		guard closure.hasPrefix("("), let parametersEnd = matchingParenthesis(in: closure) else { return nil }
		let afterParameters = closure[closure.index(after: parametersEnd)...]
		guard afterParameters.hasPrefix(" -> ") else { return nil }
		let parameters = closure[closure.index(after: closure.startIndex)..<parametersEnd]
		return (label, .builder(parameterTypes: topLevelComponents(of: parameters), returnType: String(afterParameters.dropFirst(" -> ".count))))
	}

	/// The index of the parenthesis that closes the one `text` begins with.
	private static func matchingParenthesis(in text: Substring) -> Substring.Index? {
		var depth = 0
		for index in text.indices {
			switch text[index] {
			case "(", "[", "<":
				depth += 1
			case ")", "]", ">":
				if text[index] == ">", index > text.startIndex, text[text.index(before: index)] == "-" {
					continue
				}
				depth -= 1
				if depth == 0 {
					return index
				}
			default:
				continue
			}
		}
		return nil
	}

	/// `text` split at the commas outside any brackets, each part trimmed.
	static func topLevelComponents(of text: Substring) -> [String] {
		var components = [String]()
		var depth = 0
		var current = ""
		var previous: Character?
		for character in text {
			switch character {
			case "(", "[", "<":
				depth += 1
			case ")", "]":
				depth -= 1
			case ">" where previous != "-":
				depth -= 1
			case ",":
				if depth == 0 {
					components.append(current.trimmingCharacters(in: .whitespaces))
					current = ""
					previous = character
					continue
				}
			default:
				break
			}
			current.append(character)
			previous = character
		}
		if !current.trimmingCharacters(in: .whitespaces).isEmpty {
			components.append(current.trimmingCharacters(in: .whitespaces))
		}
		return components
	}
}

/// How the probes build a type in place of a mock: the function each type the fixture declares is built with, by the
/// type's name, where that function takes exactly the parameters a builder closure of the type is handed.
struct ReleaseOverrideConstructors {
	/// Reads every `@Instantiable` type the fixture's files declare.
	init(fixtureFiles: [String]) {
		var constructors = [String: (function: String, parameterTypes: [String])]()
		for contents in fixtureFiles {
			let visitor = FileVisitor()
			visitor.walk(Parser.parse(source: contents))
			for instantiable in visitor.instantiables {
				guard !instantiable.mockOnly,
				      instantiable.customMockName == nil,
				      instantiable.mockInitializer == nil,
				      instantiable.mockAttributes.isEmpty,
				      instantiable.generatedInitializerAttributes.isEmpty,
				      let initializer = instantiable.initializer,
				      !initializer.isAsync,
				      !initializer.doesThrow,
				      !initializer.isOptional,
				      !initializer.hasGenericParameter
				else { continue }
				let typeName = instantiable.concreteInstantiable.asSource
				let function = instantiable.declarationType.isExtension ? "\(typeName).instantiate" : "\(typeName).init"
				constructors[typeName] = (function, initializer.arguments.map { Self.normalized($0.typeDescription.asSource) })
			}
		}
		self.constructors = constructors
	}

	/// The function that builds `typeName` from a builder closure's `parameterTypes`, or `nil` when the type has none
	/// that takes exactly those.
	func function(building typeName: String, from parameterTypes: [String]) -> String? {
		guard let constructor = constructors[typeName] ?? constructors[Self.unqualified(typeName)],
		      constructor.parameterTypes == parameterTypes.map(Self.normalized)
		else { return nil }
		return constructor.function
	}

	private let constructors: [String: (function: String, parameterTypes: [String])]

	private static func normalized(_ type: String) -> String {
		type.replacingOccurrences(of: "@escaping ", with: "").filter { !$0.isWhitespace }
	}

	private static func unqualified(_ typeName: String) -> String {
		typeName.split(separator: ".").last.map(String.init) ?? typeName
	}
}

/// A probe that calls a generated `mock()` with an override at every place of its configuration tree the probes can
/// build, each counted under its place (`differentialValueOverride`): `<T>.mock(safeDIOverrides: every place)`.
struct ReleaseOverrideProbe: Equatable {
	let probe: DifferentialValueProbe
	/// How many places the probe overrides.
	let placeCount: Int
	/// How many places it leaves to the mock: a builder whose type the probes cannot build, a configuration of a type
	/// already on the way to the place, and every place past `ReleaseOverrideProbe.placeLimit`.
	let skippedPlaceCount: Int

	/// The most places one probe overrides, so that its expression stays small enough to compile quickly.
	static let placeLimit = 400

	/// The override probe of `mockedTypeName`'s `mock()`, from the configuration tree `tree`, or `nil` when it overrides
	/// no place.
	static func probe(
		mockedTypeName: String,
		mockArguments: [String] = [],
		tree: ReleaseMockConfigurationTree,
		constructors: ReleaseOverrideConstructors,
	) -> ReleaseOverrideProbe? {
		guard let fields = tree.overridesByTypeName[mockedTypeName] else { return nil }
		var placeCount = 0
		var skippedPlaceCount = 0

		func builderExpression(place: String, kind: ReleaseMockConfigurationTree.Field.Kind) -> String? {
			guard case let .builder(parameterTypes, returnType) = kind else { return nil }
			guard placeCount < placeLimit, let function = constructors.function(building: returnType, from: parameterTypes) else {
				skippedPlaceCount += 1
				return nil
			}
			placeCount += 1
			return "differentialValueOverride(\(stringLiteral(place)), \(function))"
		}

		func arguments(of fields: [ReleaseMockConfigurationTree.Field], place: String, typesOnPath: [String]) -> [String] {
			var fieldArguments = [String]()
			for field in fields {
				let fieldPlace = place.isEmpty ? field.label : "\(place).\(field.label)"
				switch field.kind {
				case let .configuration(typeName):
					guard !typesOnPath.contains(typeName), let configuration = tree.configurationByTypeName[typeName] else {
						skippedPlaceCount += 1
						continue
					}
					var configurationArguments = arguments(of: configuration.fields, place: fieldPlace, typesOnPath: typesOnPath + [typeName])
					if let builder = configuration.builder, let expression = builderExpression(place: fieldPlace, kind: builder) {
						configurationArguments.append(expression)
					}
					if !configurationArguments.isEmpty {
						fieldArguments.append("\(field.label): .init(\(configurationArguments.joined(separator: ", ")))")
					}
				case .builder:
					if let expression = builderExpression(place: fieldPlace, kind: field.kind) {
						fieldArguments.append("\(field.label): \(expression)")
					}
				}
			}
			return fieldArguments
		}

		let overrides = arguments(of: fields, place: "", typesOnPath: [mockedTypeName])
		guard placeCount > 0 else { return nil }
		let call = "\(mockedTypeName).mock(\((mockArguments + ["safeDIOverrides: .init(\(overrides.joined(separator: ", ")))"]).joined(separator: ", ")))"
		return ReleaseOverrideProbe(
			probe: DifferentialValueProbe(name: "\(mockedTypeName).mock(safeDIOverrides: every place)", expression: call),
			placeCount: placeCount,
			skippedPlaceCount: skippedPlaceCount,
		)
	}

	private static func stringLiteral(_ text: String) -> String {
		"\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
	}
}
