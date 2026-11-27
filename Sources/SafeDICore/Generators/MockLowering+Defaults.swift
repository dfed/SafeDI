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
		let valueTypeDescription: TypeDescription
		let defaultExpression: String
		let isAutoclosure: Bool
		let isClosureType: Bool
		let isDeclaredEscaping: Bool
		/// Whether the parameter is a `@Sendable` `@autoclosure`, whose closure a configuration stores `@Sendable`, since
		/// the autoclosure the construction is passed captures it.
		let isSendableAutoclosure: Bool

		init(of parameter: ScopeGenerator.DefaultParameter, handWrittenMockDefaultParameters: [ScopeGenerator.DefaultParameter]) {
			label = parameter.label
			valueTypeDescription = parameter.valueTypeDescription
			defaultExpression = handWrittenMockDefaultParameters.first(where: {
				$0.isDefault(forParameterLabeled: parameter.label, ofType: parameter.typeDescription)
			})?.defaultExpression ?? parameter.defaultExpression
			isAutoclosure = parameter.isAutoclosure
			isClosureType = parameter.isClosureType
			isDeclaredEscaping = parameter.isDeclaredEscaping
			isSendableAutoclosure = MockLowering.isSendableAutoclosure(parameter.typeDescription)
		}

		/// The field's parameter of the configuration's initializer, at `indent`, and the field its storage holds, in a
		/// configuration that is not `@Sendable`-typed.
		func configurationParameter(indent: String) -> (parameter: String, field: ConfigurationStorage.Field) {
			if isAutoclosure {
				// Evaluated where the type is built: the configuration stores a closure, which the construction calls.
				(
					parameter: "\(indent)\(label): @autoclosure @escaping \(closureTypeSource) = \(ScopeGenerator.autoclosureDefault(defaultExpression))",
					field: Self.field(named: label, typeSource: closureTypeSource, parameterTypeSource: "@escaping \(closureTypeSource)"),
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

		/// The closure an `@autoclosure` parameter's field stores, spelled: `@Sendable` where the parameter's autoclosure is.
		private var closureTypeSource: String {
			"\(isSendableAutoclosure ? "@Sendable " : "")() -> \(valueTypeSource)"
		}

		/// The type of the value the parameter takes, spelled.
		var valueTypeSource: String {
			valueTypeDescription.asSource
		}

		/// The type of the value a public mock's configuration and construction function take for the field: an
		/// `@autoclosure` parameter's as a closure that returns its value.
		var publicValueType: TypeDescription {
			isAutoclosure ? MockLowering.closureTaken(forAutoclosureReturning: valueTypeDescription, isSendable: isSendableAutoclosure) : valueTypeDescription
		}

		/// The default a public mock resolves the field with: an `@autoclosure` parameter's wrapped in a closure.
		var publicDefaultExpression: String {
			isAutoclosure ? "{ \(defaultExpression) }" : defaultExpression
		}

		/// Whether the type's extension declares a provider of the field's default for a public mock: its value is optional
		/// and its default is no `nil` literal, which a configuration member and a pruned node's argument read through it.
		var hasPublicProvider: Bool {
			publicValueType.isOptional && publicDefaultExpression != "nil"
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

extension MockLowering {
	/// Whether `typeDescription`, without `@escaping`, is a `@Sendable` `@autoclosure`.
	static func isSendableAutoclosure(_ typeDescription: TypeDescription) -> Bool {
		guard case let .attributed(_, _, attributes) = typeDescription.strippingEscaping else { return false }
		// safedi-source-rule: allow stringScan — `attributes` is a type’s `[String]` of attributes: membership among a few elements, no scan of text.
		return attributes.contains("autoclosure") && attributes.contains("Sendable")
	}

	/// The closure a public mock takes in place of an `@autoclosure` parameter returning `valueType`: `@Sendable` where
	/// the autoclosure is, which captures it.
	static func closureTaken(forAutoclosureReturning valueType: TypeDescription, isSendable: Bool) -> TypeDescription {
		let closure = TypeDescription.closure(arguments: [], isAsync: false, doesThrow: false, returnType: valueType)
		return isSendable ? closure.asSendableFunction : closure
	}
}

extension MockLowering.Walk {
	/// The fields of the configuration of a node of `instantiable` for its construction's default-valued parameters, with
	/// the defaults the type's hand-written mock declares. A node built with its type's hand-written mock
	/// (`usesMockInitializer`) takes the mock's default-valued parameters.
	mutating func configurationDefaultFields(of instantiable: Instantiable, usesMockInitializer: Bool) -> [MockLowering.DefaultField] {
		let construction = mockConstruction(of: instantiable, usesMockInitializer: usesMockInitializer)
		let handWrittenDefaults = handWrittenMockDefaultParameters[instantiable.concreteInstantiable, default: []]
		return construction.defaultParameters.map { MockLowering.DefaultField(of: $0, handWrittenMockDefaultParameters: handWrittenDefaults) }
	}

	/// Whether a construction of a node of `instantiable` reads an argument from the node's configuration: a default-valued
	/// parameter, or an argument no dependency fulfills and no default fills, which only a build that compiles no mock
	/// generates (`UnfulfilledMockParameter`) and which the emitter reads as it reads a default (`resolveBuilderArguments`).
	mutating func constructionReadsConfiguration(of instantiable: Instantiable, usesMockInitializer: Bool) -> Bool {
		Self.readsConfiguration(mockConstruction(of: instantiable, usesMockInitializer: usesMockInitializer), given: instantiable)
	}

	/// Whether the construction of a node of `instantiable` passes a default it reads from its configuration to a
	/// `@Sendable` `@autoclosure`, which would capture the overrides the read names: its builder function then reads the
	/// configuration into locals before it, as a `@Sendable` builder function does.
	mutating func constructionPassesConfigurationReadToSendableAutoclosure(of instantiable: Instantiable, usesMockInitializer: Bool) -> Bool {
		mockConstruction(of: instantiable, usesMockInitializer: usesMockInitializer).callSiteArguments.contains { argument in
			MockLowering.dependency(passedTo: argument, among: instantiable.dependencies) == nil && MockLowering.isSendableAutoclosure(argument.typeDescription)
		}
	}

	private static func readsConfiguration(_ construction: ScopeGenerator.MockConstruction, given instantiable: Instantiable) -> Bool {
		!construction.defaultParameters.isEmpty
			|| construction.callSiteArguments.contains(where: { MockLowering.dependency(passedTo: $0, among: instantiable.dependencies) == nil })
	}

	/// The arguments of `initializer`'s construction of `instantiable`, as `resolveBuilderArguments` passes them: each
	/// dependency's value from `dependencyArguments`, in order, and each default-valued parameter the construction surfaces
	/// read from the node's configuration at `nodePath`, or from one built afresh where no override reaches the node, which
	/// surfaces only the defaults the type's hand-written mock declares too, where the node is built with `init`; a node built
	/// with the hand-written mock (`usesMockInitializer`) surfaces none of its defaults there.
	mutating func constructionArguments(
		of _: Initializer,
		given instantiable: Instantiable,
		usesMockInitializer: Bool,
		dependencyArguments: [(label: String, value: String)],
		nodePath: String,
		overrideReachable: Bool,
	) -> [(label: String, value: String)] {
		let construction = mockConstruction(of: instantiable, usesMockInitializer: usesMockInitializer)
		guard Self.readsConfiguration(construction, given: instantiable) else { return dependencyArguments }
		guard !buildsPublicMock else {
			return publicConstructionArguments(of: construction, given: instantiable, dependencyArguments: dependencyArguments, nodePath: nodePath, overrideReachable: overrideReachable)
		}
		let handWrittenDefaults = handWrittenMockDefaultParameters[instantiable.concreteInstantiable, default: []]
		let storesDefaultsAsClosures = sendableConfigurationTypeNames.contains(instantiable.concreteInstantiable.asSource)
		let surfacedArguments = overrideReachable
			? construction.callSiteArguments
			: Self.argumentsSurfacedWithoutOverride(of: construction, usesMockInitializer: usesMockInitializer, handWrittenDefaults: handWrittenDefaults)
		var dependencyValues = dependencyArguments[...]
		return surfacedArguments.compactMap { argument in
			if MockLowering.dependency(passedTo: argument, among: instantiable.dependencies) != nil {
				return dependencyValues.popFirst()
			}
			let configurationRead = overrideReachable
				? readingOverride("\(nodePath).\(argument.label)", localNameSuffix: "\(GeneratedCodeText.overrideRelativePath(of: nodePath))_\(argument.label)")
				: "\(instantiable.concreteInstantiable.asSource).\(ScopeGenerator.mockConfigurationStructName)().\(argument.label)"
			// The field is a closure, called where the type is built, for an `@autoclosure` parameter, and for every value
			// that is not a function where the configuration is `@Sendable`-typed (`resolveBuilderArguments`).
			let typeDescription = argument.typeDescription.strippingEscaping
			let isStoredAsClosure = typeDescription.autoclosureValueType != nil
				|| (storesDefaultsAsClosures && !typeDescription.isClosure)
			return (label: argument.label.spelledAsArgumentLabel, value: isStoredAsClosure ? "\(configurationRead)()" : configurationRead)
		}
	}

	/// The arguments `construction` surfaces where no override reaches its node: each
	/// dependency, each parameter without a default, and, where the node is built with `init`, each default the type's
	/// hand-written mock declares too.
	private static func argumentsSurfacedWithoutOverride(
		of construction: ScopeGenerator.MockConstruction,
		usesMockInitializer: Bool,
		handWrittenDefaults: [ScopeGenerator.DefaultParameter],
	) -> [Initializer.Argument] {
		construction.callSiteArguments.filter { argument in
			construction.dependencyInnerLabels.contains(argument.innerLabel)
				|| !argument.hasDefaultValue
				|| (!usesMockInitializer && handWrittenDefaults.contains(where: { $0.isDefault(forParameterLabeled: argument.label, ofType: argument.typeDescription.strippingEscaping) }))
		}
	}

	/// Whether the construction of a node of `instantiable` that no override reaches reads a default from a configuration it
	/// builds afresh: whether an argument it surfaces there is no dependency.
	mutating func readsConfigurationBuiltAfresh(of instantiable: Instantiable, usesMockInitializer: Bool) -> Bool {
		let construction = mockConstruction(of: instantiable, usesMockInitializer: usesMockInitializer)
		let handWrittenDefaults = handWrittenMockDefaultParameters[instantiable.concreteInstantiable, default: []]
		return Self.argumentsSurfacedWithoutOverride(of: construction, usesMockInitializer: usesMockInitializer, handWrittenDefaults: handWrittenDefaults).contains { argument in
			!construction.dependencyInnerLabels.contains(argument.innerLabel)
		}
	}

	/// The arguments a public mock passes the construction function of `construction`'s type, as
	/// `ScopeGenerator.publicBuilderArguments` passes them: every call-site argument, a dependency's value from
	/// `dependencyArguments`, in order, and a default read from the node's configuration at `nodePath` where its override is
	/// reachable, else its provider's value for an optional default, or `nil`, which the function resolves. An
	/// `@autoclosure` default is a closure there, which the function calls.
	private func publicConstructionArguments(
		of construction: ScopeGenerator.MockConstruction,
		given instantiable: Instantiable,
		dependencyArguments: [(label: String, value: String)],
		nodePath: String,
		overrideReachable: Bool,
	) -> [(label: String, value: String)] {
		// A `@Sendable`-typed configuration stores every default as a `@Sendable` closure, which the read calls
		// (`ScopeGenerator.publicBuilderArguments`).
		let storesDefaultsAsClosures = sendableConfigurationTypeNames.contains(instantiable.concreteInstantiable.asSource)
		var dependencyValues = dependencyArguments[...]
		return construction.callSiteArguments.compactMap { argument in
			if MockLowering.dependency(passedTo: argument, among: instantiable.dependencies) != nil {
				return dependencyValues.popFirst()
			}
			let value = if overrideReachable {
				readingOverride("\(nodePath).\(argument.label)", localNameSuffix: "\(GeneratedCodeText.overrideRelativePath(of: nodePath))_\(argument.label)")
					+ (storesDefaultsAsClosures ? "()" : "")
			} else if let defaultParameter = construction.defaultParameters.first(where: { $0.label == argument.label }),
			          // The construction's own default decides, as the emitter's does, whatever default the provider evaluates.
			          MockLowering.DefaultField(of: defaultParameter, handWrittenMockDefaultParameters: []).hasPublicProvider
			{
				MockLowering.publicProviderRead(of: instantiable.concreteInstantiable, label: argument.label)
			} else {
				"nil"
			}
			return (label: argument.label.spelledAsArgumentLabel, value: value)
		}
	}
}
