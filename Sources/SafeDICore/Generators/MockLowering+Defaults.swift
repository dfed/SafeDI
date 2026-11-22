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

/// Stage D1, lane D: a node's default-valued parameters, each a field of its type's `SafeDIMockConfiguration`, which its
/// construction reads as `resolveBuilderArguments` reads it: from the node's configuration where its override is reachable,
/// else from a configuration built afresh, for the defaults the type's hand-written mock declares too.
extension MockLowering {
	/// A field of a configuration for a default-valued parameter of the construction it configures, with the default its
	/// type's hand-written mock declares for the same label and type, else its own.
	struct DefaultField: Sendable, Equatable {
		let label: String
		/// The type of the value the parameter takes.
		let valueTypeSource: String
		let defaultExpression: String
		let isAutoclosure: Bool
		let isClosureType: Bool
		let isDeclaredEscaping: Bool

		init(of parameter: ScopeGenerator.MockParameterNode.DefaultParameter, handWrittenMockDefaultParameters: [ScopeGenerator.MockParameterNode.DefaultParameter]) {
			label = parameter.label
			valueTypeSource = parameter.valueTypeDescription.asSource
			defaultExpression = handWrittenMockDefaultParameters.first(where: {
				$0.isDefault(forParameterLabeled: parameter.label, ofType: parameter.typeDescription)
			})?.defaultExpression ?? parameter.defaultExpression
			isAutoclosure = parameter.isAutoclosure
			isClosureType = parameter.isClosureType
			isDeclaredEscaping = parameter.isDeclaredEscaping
		}

		/// The field's parameter of the configuration's initializer, at `indent`, and the field its storage holds, in a
		/// configuration that is not `@Sendable`-typed.
		func configurationParameter(indent: String) -> (parameter: String, field: ConfigurationStorage.Field) {
			if isAutoclosure {
				// Evaluated where the type is built: the configuration stores a closure, which the construction calls.
				(
					parameter: "\(indent)\(label): @autoclosure @escaping () -> \(valueTypeSource) = \(ScopeGenerator.autoclosureDefault(defaultExpression))",
					field: Self.field(named: label, typeSource: "() -> \(valueTypeSource)", parameterTypeSource: "@escaping () -> \(valueTypeSource)"),
				)
			} else if isClosureType {
				(
					parameter: "\(indent)\(label): @escaping \(valueTypeSource) = \(defaultExpression)",
					field: Self.field(named: label, typeSource: valueTypeSource, parameterTypeSource: "@escaping \(valueTypeSource)"),
				)
			} else {
				(
					parameter: "\(indent)\(label): \(isDeclaredEscaping ? "@escaping " : "")\(valueTypeSource) = \(defaultExpression)",
					field: Self.field(named: label, typeSource: valueTypeSource, parameterTypeSource: "\(isDeclaredEscaping ? "@escaping " : "")\(valueTypeSource)"),
				)
			}
		}

		private static func field(named name: String, typeSource: String, parameterTypeSource: String) -> ConfigurationStorage.Field {
			ConfigurationStorage.Field(
				name: name,
				typeSource: typeSource,
				parameterTypeSource: parameterTypeSource,
				accessPrefix: "",
				documentation: nil,
				isProvenSendable: false,
			)
		}
	}
}

extension MockLowering.Walk {
	/// The fields of the configuration of a node of `instantiable` for its construction's default-valued parameters, with
	/// the defaults the type's hand-written mock declares; or the rule of a node that starts the extraction of a `@Sendable`
	/// builder function, whose defaults the emitter reads inside it.
	func configurationDefaultFields(of instantiable: Instantiable, startsExtraction: Bool) -> MockLowering.Lowering<[MockLowering.DefaultField]> {
		let construction = ScopeGenerator.MockConstruction(instantiable: instantiable, useMockInitializer: false, builderTypesDeclaredEscaping: [])
		let handWrittenDefaults = handWrittenMockDefaultParameters[instantiable.concreteInstantiable, default: []]
		let defaultFields = construction.defaultParameters.map { MockLowering.DefaultField(of: $0, handWrittenMockDefaultParameters: handWrittenDefaults) }
		guard defaultFields.isEmpty || !startsExtraction else { return .unsupported(.wrapper) }
		return .lowered(defaultFields)
	}

	/// The arguments of `initializer`'s construction of `instantiable`, as `resolveBuilderArguments` passes them: each
	/// dependency's value from `dependencyArguments`, in order, and each default-valued parameter the construction surfaces
	/// read from the node's configuration at `nodePath`, or from one built afresh where no override reaches the node, which
	/// surfaces only the defaults the type's hand-written mock declares too.
	func constructionArguments(
		of _: Initializer,
		given instantiable: Instantiable,
		dependencyArguments: [(label: String, value: String)],
		nodePath: String,
		overrideReachable: Bool,
	) -> [(label: String, value: String)] {
		let construction = ScopeGenerator.MockConstruction(instantiable: instantiable, useMockInitializer: false, builderTypesDeclaredEscaping: [])
		guard !construction.defaultParameters.isEmpty else { return dependencyArguments }
		let handWrittenDefaults = handWrittenMockDefaultParameters[instantiable.concreteInstantiable, default: []]
		let surfacedArguments = overrideReachable
			? construction.callSiteArguments
			: construction.callSiteArguments.filter { argument in
				construction.dependencyInnerLabels.contains(argument.innerLabel)
					|| !argument.hasDefaultValue
					|| handWrittenDefaults.contains(where: { $0.isDefault(forParameterLabeled: argument.label, ofType: argument.typeDescription.strippingEscaping) })
			}
		var dependencyValues = dependencyArguments[...]
		return surfacedArguments.compactMap { argument in
			if instantiable.dependencies.contains(where: argument.isFulfilled(by:)) {
				return dependencyValues.popFirst()
			}
			let configurationRead = overrideReachable
				? readingOverride("\(nodePath).\(argument.label)", localNameSuffix: "\(GeneratedCodeText.overrideRelativePath(of: nodePath))_\(argument.label)")
				: "\(instantiable.concreteInstantiable.asSource).\(ScopeGenerator.MockParameterNode.configurationStructName)().\(argument.label)"
			// An `@autoclosure` parameter's field is a closure, called where the type is built.
			let isAutoclosure = argument.typeDescription.strippingEscaping.autoclosureValueType != nil
			return (label: argument.label.spelledAsArgumentLabel, value: isAutoclosure ? "\(configurationRead)()" : configurationRead)
		}
	}
}
