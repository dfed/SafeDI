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

    public enum MissingInitializer: Sendable {
        case hasOnlyInjectableProperties
        case hasInjectableAndNotInjectableProperties
        case hasNoInjectableProperties
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
                 .missingAttributes,
                 .disallowedGenericParameter,
                 .disallowedEffectSpecifiers,
                 .incorrectReturnType,
                 .disallowedGenericWhereClause,
                 .dependencyHasTooManyAttributes,
                 .dependencyHasInitializer,
                 .missingPublicOrOpenAttribute,
                 .missingRequiredInitializer:
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
            case .missingRequiredInitializer:
                "Add required initializer"
            }
            fixItID = MessageID(domain: "\(Self.self)", id: error.description)
        }

        let message: String
        let fixItID: MessageID
    }
}
