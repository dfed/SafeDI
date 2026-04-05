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
	case missingAttributes
	case disallowedGenericParameter
	case disallowedEffectSpecifiers
	case incorrectReturnType
	case disallowedGenericWhereClause
	case dependencyHasTooManyAttributes
	case dependencyHasInitializer
	case missingPublicOrOpenAttribute
	case missingRequiredInitializer(MissingInitializer)
	case mockMethodMissingArguments([Property])
	case mockMethodNotPublic
	case mockMethodIncorrectReturnType(typeName: String)
	case duplicateMockMethod
	case mockMethodConflictsWithGenerateMock
	case mockMethodDependencyHasDefaultValue([Property])
	case mockMethodNonDependencyMissingDefaultValue([Property])

	public enum MissingInitializer: Sendable {
		case hasOnlyInjectableProperties
		case hasInjectableAndNotInjectableProperties
		case hasNoInjectableProperties
		case isNotPublicOrOpen
		case missingArguments([Property])
	}

	public var description: String {
		switch self {
		case .missingInstantiableConformance:
			"@\(InstantiableVisitor.macroName)-decorated type or extension must declare conformance to `Instantiable`"
		case let .missingRequiredInstantiateMethod(typeName):
			"@\(InstantiableVisitor.macroName)-decorated extension of \(typeName) must have a `public static func instantiate() -> \(typeName)` method"
		case .missingAttributes:
			"@\(InstantiableVisitor.macroName)-decorated extension must have an `instantiate()` method that is both `public` and `static`"
		case .disallowedGenericParameter:
			"@\(InstantiableVisitor.macroName)-decorated extension’s `instantiate()` method must not have a generic parameter"
		case .disallowedEffectSpecifiers:
			"@\(InstantiableVisitor.macroName)-decorated extension’s `instantiate()` method must not throw or be async"
		case .incorrectReturnType:
			"@\(InstantiableVisitor.macroName)-decorated extension’s `instantiate()` method must return the same base type as the extended type"
		case .disallowedGenericWhereClause:
			"@\(InstantiableVisitor.macroName)-decorated extension must not have a generic `where` clause"
		case .dependencyHasTooManyAttributes:
			"Dependency can have at most one of @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue) attached macro"
		case .dependencyHasInitializer:
			"Dependency must not have hand-written initializer"
		case .missingPublicOrOpenAttribute:
			"@\(InstantiableVisitor.macroName)-decorated type must be `public` or `open`"
		case let .missingRequiredInitializer(missingInitializer):
			switch missingInitializer {
			case .hasOnlyInjectableProperties:
				"@\(InstantiableVisitor.macroName)-decorated type must have a `public` or `open` initializer with a parameter for each @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue)-decorated property."
			case .hasInjectableAndNotInjectableProperties:
				"@\(InstantiableVisitor.macroName)-decorated type must have a `public` or `open` initializer with a parameter for each @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue)-decorated property. Parameters in this initializer that do not correspond to a decorated property must have default values."
			case .hasNoInjectableProperties:
				"@\(InstantiableVisitor.macroName)-decorated type with no @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue)-decorated properties must have a `public` or `open` initializer that either takes no parameters or has a default value for each parameter."
			case .isNotPublicOrOpen:
				"@\(InstantiableVisitor.macroName)-decorated type must have a `public` or `open` initializer."
			case .missingArguments:
				"@\(InstantiableVisitor.macroName)-decorated type must have a `public` or `open` initializer with a parameter for each @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue)-decorated property."
			}
		case .mockMethodMissingArguments:
			"@\(InstantiableVisitor.macroName)-decorated type's `mock()` method must have a parameter for each @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue)-decorated property. Extra parameters with default values are allowed."
		case .mockMethodNotPublic:
			"@\(InstantiableVisitor.macroName)-decorated type's `mock()` method must be `public` or `open`."
		case let .mockMethodIncorrectReturnType(typeName):
			"@\(InstantiableVisitor.macroName)-decorated type's `mock()` method must return `Self` or `\(typeName)`."
		case .duplicateMockMethod:
			"@\(InstantiableVisitor.macroName)-decorated type must have at most one `mock()` method. Remove this duplicate."
		case .mockMethodConflictsWithGenerateMock:
			"@\(InstantiableVisitor.macroName)-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method when there are no dependencies, because the generated and hand-written methods would have ambiguous signatures."
		case .mockMethodDependencyHasDefaultValue:
			"@\(InstantiableVisitor.macroName)-decorated type's `mock()` method must not have default values on dependency parameters when `generateMock` is `true`. Default values would create ambiguity with the generated mock method."
		case .mockMethodNonDependencyMissingDefaultValue:
			"@\(InstantiableVisitor.macroName)-decorated type's `mock()` method has non-dependency parameters without default values. Parameters that do not correspond to a dependency must have default values."
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
			     .missingAttributes,
			     .disallowedGenericParameter,
			     .disallowedEffectSpecifiers,
			     .incorrectReturnType,
			     .disallowedGenericWhereClause,
			     .dependencyHasTooManyAttributes,
			     .dependencyHasInitializer,
			     .missingPublicOrOpenAttribute,
			     .missingRequiredInitializer,
			     .mockMethodMissingArguments,
			     .mockMethodNotPublic,
			     .mockMethodIncorrectReturnType,
			     .duplicateMockMethod,
			     .mockMethodConflictsWithGenerateMock,
			     .mockMethodDependencyHasDefaultValue,
			     .mockMethodNonDependencyMissingDefaultValue:
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
			case .missingAttributes:
				"Set `public static` modifiers"
			case .disallowedGenericParameter:
				"Remove generic parameter"
			case .disallowedEffectSpecifiers:
				"Remove effect specifiers"
			case .incorrectReturnType:
				"Make `instantiate()`’s return type the same base type as the extended type"
			case .disallowedGenericWhereClause:
				"Remove generic `where` clause"
			case .dependencyHasTooManyAttributes:
				"Remove excessive attached macros"
			case .dependencyHasInitializer:
				"Remove initializer"
			case .missingPublicOrOpenAttribute:
				"Add `public` modifier"
			case let .missingRequiredInitializer(missingInitError):
				switch missingInitError {
				case .hasOnlyInjectableProperties,
				     .hasInjectableAndNotInjectableProperties,
				     .hasNoInjectableProperties:
					"Add required initializer"
				case .isNotPublicOrOpen:
					"Add `public` modifier"
				case let .missingArguments(properties):
					"Add arguments for \(properties.map(\.asSource).joined(separator: ", "))"
				}
			case let .mockMethodMissingArguments(properties):
				"Add mock() arguments for \(properties.map(\.asSource).joined(separator: ", "))"
			case .mockMethodNotPublic:
				"Add `public` modifier to mock() method"
			case let .mockMethodIncorrectReturnType(typeName):
				"Change mock() return type to `\(typeName)`"
			case .duplicateMockMethod:
				"Remove duplicate mock() method"
			case .mockMethodConflictsWithGenerateMock:
				"Remove `generateMock: true`"
			case let .mockMethodDependencyHasDefaultValue(properties):
				"Remove default values from mock() dependency parameters for \(properties.map(\.asSource).joined(separator: ", "))"
			case let .mockMethodNonDependencyMissingDefaultValue(properties):
				"Add default values to mock() non-dependency parameters for \(properties.map(\.asSource).joined(separator: ", "))"
			}
			fixItID = MessageID(domain: "\(Self.self)", id: error.description)
		}

		let message: String
		let fixItID: MessageID
	}
}
