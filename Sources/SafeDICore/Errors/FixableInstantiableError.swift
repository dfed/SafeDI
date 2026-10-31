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

import SwiftDiagnostics

public enum FixableInstantiableError: DiagnosticError {
	case missingInstantiableConformance
	case missingRequiredInstantiateMethod(typeName: String)
	case instantiateMethodNotStatic
	/// The extension's `instantiate()` method spells this `private` or `fileprivate` access, which generated code in
	/// another file cannot use.
	case privateOrFilePrivateInstantiateMethod(AccessLevel)
	case disallowedGenericParameter
	case disallowedEffectSpecifiers
	case incorrectReturnType(typeName: String)
	case disallowedGenericWhereClause
	case dependencyHasTooManyAttributes
	case dependencyHasInitializer(propertyName: String, initializer: String)
	/// The decorated type spells this `private` or `fileprivate` access, which generated code in another file cannot use.
	case privateOrFilePrivateType(AccessLevel)
	case missingRequiredInitializer(MissingInitializer)
	case mockMethodMissingArguments(methodName: String, [Property])
	/// The hand-written mock method spells this `private` or `fileprivate` access, which a generated mock in another
	/// file cannot use.
	case privateOrFilePrivateMockMethod(AccessLevel)
	case mockMethodIncorrectReturnType(typeName: String)
	case extensionMockMethodIncorrectReturnType(typeName: String)
	case duplicateMockMethod
	case mockMethodNeedsCustomName
	case mockMethodConflictsWithGeneratedMock(customMockName: String)
	case customMockNameWithoutMockGeneration
	case customMockNameMethodNotFound(String)
	case mockMethodNonDependencyMissingDefaultValue([Property])
	case mockOnlyWithGenerateMock
	case mockOnlyWithIsRoot
	case mockOnlyMissingMockMethod(typeName: String, methodName: String)
	case unlabeledDefaultBeforeUnlabeledParameter(defaultedParameter: Property, followingParameter: Property)
	case calleeScopeReferenceInDefaultExpression(parameterLabel: String, typeName: String)
	/// A name SafeDI binds, or refers to, in generated code collides with a name generated code introduces.
	case reservedName(name: String, reservation: ReservedName)

	public enum MissingInitializer: Sendable {
		case hasOnlyInjectableProperties
		case hasInjectableAndNotInjectableProperties
		case hasNoInjectableProperties
		/// The initializer spells this `private` or `fileprivate` access, which generated code in another file cannot use.
		case isPrivateOrFilePrivate(AccessLevel)
		case missingArguments([Property])
	}

	public var description: String {
		switch self {
		case .missingInstantiableConformance:
			"@\(InstantiableVisitor.macroName)-decorated type or extension must declare conformance to `Instantiable`."
		case let .missingRequiredInstantiateMethod(typeName):
			"@\(InstantiableVisitor.macroName)-decorated extension of `\(typeName)` must have a `static func instantiate() -> \(typeName)` method."
		case .instantiateMethodNotStatic:
			"@\(InstantiableVisitor.macroName)-decorated extension’s `instantiate()` method must be `static`: SafeDI calls it on the extended type. Add `static`."
		case let .privateOrFilePrivateInstantiateMethod(accessLevel):
			"@\(InstantiableVisitor.macroName)-decorated extension’s `instantiate()` method must not be `\(accessLevel.spelling)`: SafeDI calls it in a generated file, where a `\(accessLevel.spelling)` method is not visible. Remove `\(accessLevel.spelling)`."
		case .disallowedGenericParameter:
			"@\(InstantiableVisitor.macroName)-decorated extension’s `instantiate()` method must not have a generic parameter."
		case .disallowedEffectSpecifiers:
			"@\(InstantiableVisitor.macroName)-decorated extension’s `instantiate()` method must not throw or be async."
		case let .incorrectReturnType(typeName):
			"@\(InstantiableVisitor.macroName)-decorated extension’s `instantiate()` method must return the extended type, `\(typeName)`."
		case .disallowedGenericWhereClause:
			"@\(InstantiableVisitor.macroName)-decorated extension must not have a generic `where` clause. To build a specialization of a generic type, return that specialization from an `instantiate()` method instead."
		case .dependencyHasTooManyAttributes:
			"A property can be decorated with only one of @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue)."
		case let .dependencyHasInitializer(propertyName, initializer):
			"`\(propertyName)` must not have a default value: SafeDI passes every @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), and @\(Dependency.Source.forwardedRawValue) property in through the initializer. Remove `\(initializer)`."
		case let .privateOrFilePrivateType(accessLevel):
			"@\(InstantiableVisitor.macroName)-decorated type must not be `\(accessLevel.spelling)`: SafeDI constructs it in a generated file, where a `\(accessLevel.spelling)` type is not visible. Remove `\(accessLevel.spelling)`."
		case let .missingRequiredInitializer(missingInitializer):
			switch missingInitializer {
			case .hasOnlyInjectableProperties:
				"@\(InstantiableVisitor.macroName)-decorated type must have an initializer with a parameter for each @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue)-decorated property."
			case .hasInjectableAndNotInjectableProperties:
				"@\(InstantiableVisitor.macroName)-decorated type must have an initializer with a parameter for each @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue)-decorated property. Parameters in this initializer that do not correspond to a decorated property must have default values."
			case .hasNoInjectableProperties:
				"@\(InstantiableVisitor.macroName)-decorated type with no @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue)-decorated properties must have an initializer that either takes no parameters or has a default value for each parameter."
			case let .isPrivateOrFilePrivate(accessLevel):
				"@\(InstantiableVisitor.macroName)-decorated type’s initializer must not be `\(accessLevel.spelling)`: SafeDI calls it in a generated file, where a `\(accessLevel.spelling)` initializer is not visible. Remove `\(accessLevel.spelling)`."
			case let .missingArguments(properties):
				"@\(InstantiableVisitor.macroName)-decorated type must have an initializer with a parameter for each @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue)-decorated property. This initializer has no parameter for \(properties.asBacktickedList)."
			}
		case let .mockMethodMissingArguments(methodName, properties):
			"This `\(methodName)()` method has no parameter for \(properties.asBacktickedList). A hand-written mock must take a parameter for each @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue)-decorated property; extra parameters with default values are allowed."
		case let .privateOrFilePrivateMockMethod(accessLevel):
			"@\(InstantiableVisitor.macroName)-decorated type’s `mock()` method must not be `\(accessLevel.spelling)`: a generated mock calls it in a generated file, where a `\(accessLevel.spelling)` method is not visible. Remove `\(accessLevel.spelling)`."
		case let .mockMethodIncorrectReturnType(typeName):
			"@\(InstantiableVisitor.macroName)-decorated type’s `mock()` method must return `Self` or `\(typeName)`."
		case let .extensionMockMethodIncorrectReturnType(typeName):
			"@\(InstantiableVisitor.macroName)-decorated extension’s `mock()` method must return `\(typeName)` or a type listed in `fulfillingAdditionalTypes`."
		case .duplicateMockMethod:
			"@\(InstantiableVisitor.macroName)-decorated type must have at most one `mock()` method. Remove this duplicate."
		case .mockMethodNeedsCustomName:
			"@\(InstantiableVisitor.macroName)-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method because the generated and hand-written methods would have ambiguous signatures. Rename your method and add `customMockName` to `@\(InstantiableVisitor.macroName)`."
		case let .mockMethodConflictsWithGeneratedMock(customMockName):
			"This `mock()` method conflicts with the `mock()` that `generateMock: true` generates. This type’s hand-written mock is `\(customMockName)`, which `customMockName` names; remove this method or rename it."
		case .customMockNameWithoutMockGeneration:
			"`customMockName` requires `generateMock: true` or `mockOnly: true`."
		case let .customMockNameMethodNotFound(name):
			"`customMockName` names `\(name)`, but this declaration has no method named `\(name)`. Add a `public static func \(name)(…)` method."
		case let .mockMethodNonDependencyMissingDefaultValue(properties):
			if properties.count == 1 {
				"This `mock()` method’s parameter \(properties.asBacktickedList) does not correspond to a dependency, so it must have a default value."
			} else {
				"This `mock()` method’s parameters \(properties.asBacktickedList) do not correspond to a dependency, so they must have default values."
			}
		case .mockOnlyWithGenerateMock:
			"`mockOnly` and `generateMock` cannot both be `true`: a `mockOnly` declaration provides a hand-written mock. To generate a mock, set `generateMock: true` on the production `@\(InstantiableVisitor.macroName)` declaration instead."
		case .mockOnlyWithIsRoot:
			"`mockOnly` types cannot be marked `isRoot`."
		case let .mockOnlyMissingMockMethod(typeName, methodName):
			"@\(InstantiableVisitor.macroName)(mockOnly: true) requires a `static func \(methodName)(…) -> \(typeName)` method."
		case let .unlabeledDefaultBeforeUnlabeledParameter(defaultedParameter, followingParameter):
			"Unlabeled parameter `\(defaultedParameter.asSource)` has a default value but is followed by unlabeled required parameter `\(followingParameter.asSource)`, so a generated `mock()` cannot leave `\(defaultedParameter.label)` out of its call. Add an argument label to `\(defaultedParameter.label)`, move unlabeled parameters with defaults after the required ones, or remove the default."
		case let .calleeScopeReferenceInDefaultExpression(parameterLabel, typeName):
			"The default value of `\(parameterLabel)` refers to `Self`. A generated `mock()` repeats this default outside `\(typeName)`, where `Self` names a different type. Write `\(typeName)` instead of `Self`, or remove the default."
		case let .reservedName(name, reservation):
			switch reservation {
			case .builderFunctionName:
				"`\(name)` begins with `\(ReservedName.builderFunctionNamePrefix)`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `\(ReservedName.builderFunctionNamePrefix)`."
			case .mockOverridesParameter:
				"`\(name)` is reserved: it is the name of the parameter through which a generated `mock()` takes its overrides, and a name spelled the same would collide with it in generated code. Rename it."
			case .configurationBuilderProperty:
				"`\(name)` is reserved: it is the name of the property of a generated `SafeDIMockConfiguration` that overrides how its type is built, and a name spelled the same would collide with it in generated code. Rename it."
			case let .constructedType(typeName):
				"`\(name)` is reserved: generated code constructs the `\(typeName)` type by that name, and a name spelled the same would hide the type from it. Rename it."
			}
		}
	}

	public var diagnostic: DiagnosticMessage {
		InstantiableDiagnosticMessage(error: self)
	}

	public var fixIt: FixItMessage {
		InstantiableFixItMessage(error: self)
	}

	// MARK: - InstantiableDiagnosticMessage

	private struct InstantiableDiagnosticMessage: DiagnosticMessage {
		init(error: FixableInstantiableError) {
			diagnosticID = MessageID(domain: "\(Self.self)", id: error.description)
			severity = switch error {
			case .missingInstantiableConformance,
			     .missingRequiredInstantiateMethod,
			     .instantiateMethodNotStatic,
			     .privateOrFilePrivateInstantiateMethod,
			     .disallowedGenericParameter,
			     .disallowedEffectSpecifiers,
			     .incorrectReturnType,
			     .disallowedGenericWhereClause,
			     .dependencyHasTooManyAttributes,
			     .dependencyHasInitializer,
			     .privateOrFilePrivateType,
			     .missingRequiredInitializer,
			     .mockMethodMissingArguments,
			     .privateOrFilePrivateMockMethod,
			     .mockMethodIncorrectReturnType,
			     .extensionMockMethodIncorrectReturnType,
			     .duplicateMockMethod,
			     .mockMethodNeedsCustomName,
			     .mockMethodConflictsWithGeneratedMock,
			     .customMockNameWithoutMockGeneration,
			     .customMockNameMethodNotFound,
			     .mockMethodNonDependencyMissingDefaultValue,
			     .mockOnlyWithGenerateMock,
			     .mockOnlyWithIsRoot,
			     .mockOnlyMissingMockMethod,
			     .unlabeledDefaultBeforeUnlabeledParameter,
			     .calleeScopeReferenceInDefaultExpression,
			     .reservedName:
				.error
			}
			message = error.description
		}

		let diagnosticID: MessageID
		let severity: DiagnosticSeverity
		let message: String
	}

	// MARK: - InstantiableFixItMessage

	private struct InstantiableFixItMessage: FixItMessage {
		init(error: FixableInstantiableError) {
			message = switch error {
			case .missingInstantiableConformance:
				"Declare conformance to `Instantiable`"
			case let .missingRequiredInstantiateMethod(typeName):
				"Add `public static func instantiate() -> \(typeName)` method"
			case .instantiateMethodNotStatic:
				"Add `static` modifier"
			case let .privateOrFilePrivateInstantiateMethod(accessLevel):
				"Remove `\(accessLevel.spelling)` modifier"
			case .disallowedGenericParameter:
				"Remove generic parameter"
			case .disallowedEffectSpecifiers:
				"Remove effect specifiers"
			case let .incorrectReturnType(typeName):
				"Make `instantiate()` return `\(typeName)`"
			case .disallowedGenericWhereClause:
				"Remove generic `where` clause"
			case .dependencyHasTooManyAttributes:
				"Remove excessive attached macros"
			case let .dependencyHasInitializer(_, initializer):
				"Remove `\(initializer)`"
			case let .privateOrFilePrivateType(accessLevel):
				"Remove `\(accessLevel.spelling)` modifier"
			case let .missingRequiredInitializer(missingInitError):
				switch missingInitError {
				case .hasOnlyInjectableProperties,
				     .hasInjectableAndNotInjectableProperties,
				     .hasNoInjectableProperties:
					"Add required initializer"
				case let .isPrivateOrFilePrivate(accessLevel):
					"Remove `\(accessLevel.spelling)` modifier"
				case let .missingArguments(properties):
					"Add arguments for \(properties.map(\.asSource).joined(separator: ", "))"
				}
			case let .mockMethodMissingArguments(methodName, properties):
				"Add `\(methodName)()` arguments for \(properties.map(\.asSource).joined(separator: ", "))"
			case let .privateOrFilePrivateMockMethod(accessLevel):
				"Remove `\(accessLevel.spelling)` modifier from `mock()` method"
			case let .mockMethodIncorrectReturnType(typeName),
			     let .extensionMockMethodIncorrectReturnType(typeName):
				"Change `mock()` return type to `\(typeName)`"
			case .duplicateMockMethod:
				"Remove duplicate `mock()` method"
			case .mockMethodNeedsCustomName:
				"Rename method to `customMock` and add `customMockName: \"customMock\"` to `@Instantiable`"
			case .mockMethodConflictsWithGeneratedMock:
				"Remove this `mock()` method"
			case .customMockNameWithoutMockGeneration:
				"Add `generateMock: true` or `mockOnly: true` to `@Instantiable`"
			case let .customMockNameMethodNotFound(name):
				"Add `public static func \(name)(…)` method"
			case let .mockMethodNonDependencyMissingDefaultValue(properties):
				"Add default values to `mock()` non-dependency parameters for \(properties.map(\.asSource).joined(separator: ", "))"
			case .mockOnlyWithGenerateMock:
				"Remove `generateMock: true`"
			case .mockOnlyWithIsRoot:
				"Remove `isRoot: true`"
			case let .mockOnlyMissingMockMethod(typeName, methodName):
				"Add `public static func \(methodName)(…) -> \(typeName)` method"
			case let .unlabeledDefaultBeforeUnlabeledParameter(defaultedParameter, _):
				"Add argument label `\(defaultedParameter.label)`"
			case let .calleeScopeReferenceInDefaultExpression(parameterLabel, _):
				"Remove the default from `\(parameterLabel)` or move the referenced value to a file-scoped or module-scoped symbol"
			case let .reservedName(name, reservation):
				switch reservation {
				case .builderFunctionName:
					"Rename `\(name)` to `\(ReservedName.removingBuilderFunctionNamePrefix(from: name))`"
				case .mockOverridesParameter, .configurationBuilderProperty, .constructedType:
					"Rename `\(name)`"
				}
			}
			fixItID = MessageID(domain: "\(Self.self)", id: error.description)
		}

		let message: String
		let fixItID: MessageID
	}
}

// MARK: - [Property]

extension [Property] {
	/// The properties as a comma-separated list, each spelled as source in backticks.
	fileprivate var asBacktickedList: String {
		map { "`\($0.asSource)`" }.joined(separator: ", ")
	}
}
