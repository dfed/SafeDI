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

public enum FixableExternalInstantiableError: DiagnosticError {
    case missingRequiredInstantiateMethod(typeName: String)
    case missingAttributes
    case disallowedGenericParameter
    case disallowedEffectSpecifiers
    case incorrectReturnType
    case disallowedGenericWhereClause

    public var description: String {
        switch self {
        case let .missingRequiredInstantiateMethod(typeName):
            "@\(ExternalInstantiableVisitor.macroName)-decorated extension of \(typeName) must have a `public static func instantiate() -> \(typeName)` method"
        case .missingAttributes:
            "@\(ExternalInstantiableVisitor.macroName)-decorated extension must have an `instantiate()` method that is both `public` and `static`"
        case .disallowedGenericParameter:
            "@\(ExternalInstantiableVisitor.macroName)-decorated extension's `instantiate()` method must not have a generic parameter"
        case .disallowedEffectSpecifiers:
            "@\(ExternalInstantiableVisitor.macroName)-decorated extension's `instantiate()` method must not throw or be async"
        case .incorrectReturnType:
            "@\(ExternalInstantiableVisitor.macroName)-decorated extension's `instantiate()` method must return the same type as the extended type"
        case .disallowedGenericWhereClause:
            "@\(ExternalInstantiableVisitor.macroName)-decorated extension must not have a generic `where` clause"
        }
    }

    public var diagnostic: DiagnosticMessage {
        ExternalInstantiableDiagnosticMessage(error: self)
    }

    public var fixIt: FixItMessage {
        ExternalInstantiableFixItMessage(error: self)
    }

    // MARK: - ExternalInstantiableDiagnosticMessage

    private struct ExternalInstantiableDiagnosticMessage: DiagnosticMessage {
        var diagnosticID: MessageID {
            MessageID(domain: "\(Self.self)", id: error.description)
        }

        var severity: DiagnosticSeverity {
            switch error {
            case .missingRequiredInstantiateMethod,
                    .missingAttributes,
                    .disallowedGenericParameter,
                    .disallowedEffectSpecifiers,
                    .incorrectReturnType,
                    .disallowedGenericWhereClause:
                return .error
            }
        }

        var message: String {
            error.description
        }

        let error: FixableExternalInstantiableError
    }

    // MARK: - ExternalInstantiableFixItMessage

    private struct ExternalInstantiableFixItMessage: FixItMessage {
        var message: String {
            switch error {
            case let .missingRequiredInstantiateMethod(typeName):
                "Add `public static func instantiate() -> \(typeName)` method"
            case .missingAttributes:
                "Set `public static` modifiers"
            case .disallowedGenericParameter:
                "Remove generic parameter"
            case .disallowedEffectSpecifiers:
                "Remove effect specifiers"
            case .incorrectReturnType:
                "Make `instantiate()`'s return type the same as the extended type"
            case .disallowedGenericWhereClause:
                "Remove generic `where` clause"
            }
        }

        var fixItID: SwiftDiagnostics.MessageID {
            MessageID(domain: "\(Self.self)", id: error.description)
        }

        let error: FixableExternalInstantiableError
    }
}
