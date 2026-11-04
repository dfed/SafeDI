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
	/// The hand-written mock method is `async` or `throws`, which a generated mock, calling it synchronously, cannot
	/// call.
	case mockMethodHasEffectSpecifiers(methodName: String)
	case mockMethodIncorrectReturnType(typeName: String)
	case extensionMockMethodIncorrectReturnType(typeName: String)
	case duplicateMockMethod
	case mockMethodNeedsCustomName
	case mockMethodConflictsWithGeneratedMock(customMockName: String)
	case customMockNameWithoutMockGeneration
	case customMockNameMethodNotFound(String)
	case mockMethodNonDependencyMissingDefaultValue([Property])
	/// A `mockOnly` declaration also asks for a generated mock, spelled as `spelling` (`true`, `.public`).
	case mockOnlyWithGenerateMock(spelling: String)
	/// `generateMock: .public` on a type declaration whose spelled access, `accessLevel`, is narrower than `public`.
	case publicMockRequiresPublicType(typeName: String, accessLevel: AccessLevel, isSpelled: Bool)
	/// `generateMock: .public` on an `@Instantiable` extension, which cannot prove the extended type is `public`.
	case publicMockOnExtension
	/// `generateMock: .public` on a declaration with a generic parameter clause, or on one declared inside the body of
	/// `genericTypeName`, a type that has one.
	case publicMockOnGenericType(typeName: String, genericTypeName: String?)
	/// A default-valued non-dependency parameter is `@autoclosure`, which a generated mock cannot pass on.
	case defaultValuedAutoclosureParameter(parameterLabel: String)
	case mockOnlyWithIsRoot
	case generateDependencyTreeWithIsRoot
	case generateDependencyTreeWithMockOnly
	case mockOnlyMissingMockMethod(typeName: String, methodName: String)
	case unlabeledDefaultBeforeUnlabeledParameter(defaultedParameter: Property, followingParameter: Property)
	case calleeScopeReferenceInDefaultExpression(parameterLabel: String, typeName: String)
	/// A name SafeDI binds, or refers to, in generated code collides with a name generated code introduces.
	case reservedName(name: String, reservation: ReservedName)
	/// An `instantiate(…)` parameter without a default value, which is a dependency, is named `_`, which names no
	/// dependency. `argumentLabel` is the name a fix-it gives the parameter, when one is offered.
	case unnamedInstantiateDependency(argumentLabel: String)
	/// Two names of one declaration that SafeDI matches by name, `earlierName` and `laterName`, are equal as `String`s
	/// but differ in their UTF-8 bytes: Swift reads them as two names, and SafeDI as one.
	case namesEncodedDifferently(earlierName: String, laterName: String)
	/// A dependency's type names types declared inside the decorated declaration, each spelled as `spelling`, which code
	/// SafeDI generates in another type's extension cannot resolve.
	case unqualifiedNestedType(typeNames: [(spelling: String, qualifiedSpelling: String)], enclosingTypeName: String, dependencyLabel: String)

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
		case let .mockMethodHasEffectSpecifiers(methodName):
			"This `\(methodName)()` method must be neither `async` nor `throws`: generated mocks call it synchronously. Remove its effect specifiers."
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
			"`mockOnly` cannot be combined with `generateMock: true`, `.internal`, or `.public`: a `mockOnly` declaration provides a hand-written mock. To generate a mock, set `generateMock` on the production `@\(InstantiableVisitor.macroName)` declaration instead."
		case let .publicMockRequiresPublicType(typeName, accessLevel, _):
			"`generateMock: .public` requires a `public` or `open` type; `\(typeName)` is `\(accessLevel.spelling)`. Make it `public`, or use `.internal`."
		case .publicMockOnExtension:
			"`generateMock: .public` needs a type declaration; an extension cannot prove its type is `public`. Use `.internal`, or write a public `mock()` by hand."
		case let .publicMockOnGenericType(typeName, genericTypeName):
			if let genericTypeName {
				"`generateMock: .public` cannot be used on `\(typeName)`, which is declared inside the generic type `\(genericTypeName)`: SafeDI cannot generate a public `mock()` for a type in a generic context. Use `generateMock: .internal` for a mock its own module calls, or write a public `mock()` by hand for other modules to call."
			} else {
				"`generateMock: .public` cannot be used on the generic type `\(typeName)`: SafeDI cannot generate a public `mock()` for a type in a generic context. Use `generateMock: .internal` for a mock its own module calls, or write a public `mock()` by hand for other modules to call."
			}
		case let .defaultValuedAutoclosureParameter(parameterLabel):
			"A default-valued `@autoclosure` parameter cannot be forwarded by a generated mock. Remove `@autoclosure` from `\(parameterLabel)`, or remove its default."
		case .mockOnlyWithIsRoot:
			"`mockOnly` types cannot be marked `isRoot`."
		case .generateDependencyTreeWithIsRoot:
			"`isRoot` and `generateDependencyTree` cannot both be `true`: a root's dependency tree is generated as a `public init()` that takes nothing, and a type whose dependency tree SafeDI generates in its own module receives what its tree needs as parameters. Keep one."
		case .generateDependencyTreeWithMockOnly:
			"`mockOnly` types cannot be marked `generateDependencyTree`: a `mockOnly` declaration provides a hand-written mock and has no dependency tree."
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
		case let .namesEncodedDifferently(earlierName, laterName):
			"The names `\(earlierName)` (\(earlierName.codePoints)) and `\(laterName)` (\(laterName.codePoints)) look the same but are encoded differently, so SafeDI cannot tell them apart. Rename one of them."
		case .unnamedInstantiateDependency:
			"This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value."
		case let .unqualifiedNestedType(typeNames, enclosingTypeName, dependencyLabel):
			if typeNames.count == 1 {
				"The generated code that builds or receives `\(dependencyLabel)` lives in another type’s extension, where \(typeNames.map { "`\($0.spelling)`" }.joinedAsList), declared in `\(enclosingTypeName)`, does not resolve. Write it as \(typeNames.map { "`\($0.qualifiedSpelling)`" }.joinedAsList)."
			} else {
				"The generated code that builds or receives `\(dependencyLabel)` lives in another type’s extension, where \(typeNames.map { "`\($0.spelling)`" }.joinedAsList), declared in `\(enclosingTypeName)`, do not resolve. Write them as \(typeNames.map { "`\($0.qualifiedSpelling)`" }.joinedAsList)."
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
			     .mockMethodHasEffectSpecifiers,
			     .mockMethodIncorrectReturnType,
			     .extensionMockMethodIncorrectReturnType,
			     .duplicateMockMethod,
			     .mockMethodNeedsCustomName,
			     .mockMethodConflictsWithGeneratedMock,
			     .customMockNameWithoutMockGeneration,
			     .customMockNameMethodNotFound,
			     .mockMethodNonDependencyMissingDefaultValue,
			     .mockOnlyWithGenerateMock,
			     .publicMockRequiresPublicType,
			     .publicMockOnExtension,
			     .publicMockOnGenericType,
			     .defaultValuedAutoclosureParameter,
			     .mockOnlyWithIsRoot,
			     .generateDependencyTreeWithIsRoot,
			     .generateDependencyTreeWithMockOnly,
			     .mockOnlyMissingMockMethod,
			     .unlabeledDefaultBeforeUnlabeledParameter,
			     .calleeScopeReferenceInDefaultExpression,
			     .reservedName,
			     .unnamedInstantiateDependency,
			     .namesEncodedDifferently:
				.error
			case .unqualifiedNestedType:
				.warning
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
			case let .mockMethodHasEffectSpecifiers(methodName):
				"Remove effect specifiers from `\(methodName)()`"
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
			case let .mockOnlyWithGenerateMock(spelling):
				"Remove `generateMock: \(spelling)`"
			case let .publicMockRequiresPublicType(_, accessLevel, isSpelled):
				if isSpelled {
					"Replace `\(accessLevel.spelling)` with `public`"
				} else {
					"Insert `public`"
				}
			case .publicMockOnExtension, .publicMockOnGenericType:
				"Replace `.public` with `.internal`"
			case let .defaultValuedAutoclosureParameter(parameterLabel):
				"Remove `@autoclosure` from `\(parameterLabel)`"
			case .mockOnlyWithIsRoot:
				"Remove `isRoot: true`"
			case .generateDependencyTreeWithIsRoot, .generateDependencyTreeWithMockOnly:
				"Remove `generateDependencyTree: true`"
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
			case let .unnamedInstantiateDependency(argumentLabel):
				"Name the parameter `\(argumentLabel)`"
			case let .namesEncodedDifferently(_, laterName):
				"Rename `\(laterName)`"
			case let .unqualifiedNestedType(typeNames, _, _):
				"Replace \(typeNames.map { "`\($0.spelling)` with `\($0.qualifiedSpelling)`" }.joinedAsList)"
			}
			fixItID = MessageID(domain: "\(Self.self)", id: error.description)
		}

		let message: String
		let fixItID: MessageID
	}
}

// MARK: - String

extension String {
	/// This text's Unicode scalars in the notation people read code points in, such as `U+0063 U+0301`.
	var codePoints: String {
		unicodeScalars.map { scalar in
			let hexadecimal = String(scalar.value, radix: 16, uppercase: true)
			return "U+\(String(repeating: "0", count: max(0, 4 - hexadecimal.count)))\(hexadecimal)"
		}.joined(separator: " ")
	}
}

// MARK: - [String]

extension [String] {
	/// The strings joined as a list in prose: `A`, `A and B`, or `A, B, and C`.
	var joinedAsList: String {
		if count > 2 {
			"\(dropLast().joined(separator: ", ")), and \(self[count - 1])"
		} else {
			joined(separator: " and ")
		}
	}
}

// MARK: - [Property]

extension [Property] {
	/// The properties as a comma-separated list, each spelled as source in backticks.
	fileprivate var asBacktickedList: String {
		map { "`\($0.asSource)`" }.joined(separator: ", ")
	}
}

/// The message of a fix-it that replaces the `generateMock:` argument's value, offered beside an error's own fix-it.
public struct MockGenerationArgumentFixItMessage: FixItMessage {
	public init(replacement: String) {
		message = "Replace `.public` with `\(replacement)`"
	}

	public let message: String

	public var fixItID: MessageID {
		MessageID(domain: "\(Self.self)", id: message)
	}
}
