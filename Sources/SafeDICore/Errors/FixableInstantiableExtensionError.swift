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

public enum FixableInstantiableExtensionError: DiagnosticError {
    case incorrectDeclarationType
    case missingInstantiableConformance
    case missingRequiredInstantiateMethod(typeName: String)
    case missingAttributes
    case disallowedGenericParameter
    case disallowedEffectSpecifiers
    case incorrectReturnType
    case disallowedGenericWhereClause

    public var description: String {
        switch self {
        case .incorrectDeclarationType:
            "@\(InstantiableVisitor.extendedMacroName)-decoration is reserved for extensions"
        case .missingInstantiableConformance:
            "@\(InstantiableVisitor.extendedMacroName)-decorated extension must declare conformance to `Instantiable`"
        case let .missingRequiredInstantiateMethod(typeName):
            "@\(InstantiableVisitor.extendedMacroName)-decorated extension of \(typeName) must have a `public static func instantiate() -> \(typeName)` method"
        case .missingAttributes:
            "@\(InstantiableVisitor.extendedMacroName)-decorated extension must have an `instantiate()` method that is both `public` and `static`"
        case .disallowedGenericParameter:
            "@\(InstantiableVisitor.extendedMacroName)-decorated extension’s `instantiate()` method must not have a generic parameter"
        case .disallowedEffectSpecifiers:
            "@\(InstantiableVisitor.extendedMacroName)-decorated extension’s `instantiate()` method must not throw or be async"
        case .incorrectReturnType:
            "@\(InstantiableVisitor.extendedMacroName)-decorated extension’s `instantiate()` method must return the same type as the extended type"
        case .disallowedGenericWhereClause:
            "@\(InstantiableVisitor.extendedMacroName)-decorated extension must not have a generic `where` clause"
        }
    }

    public var diagnostic: DiagnosticMessage {
        InstantiableExtensionDiagnosticMessage(error: self)
    }

    public var fixIt: FixItMessage {
        InstantiableExtensionFixItMessage(error: self)
    }

    // MARK: - InstantiableExtensionDiagnosticMessage

    private struct InstantiableExtensionDiagnosticMessage: DiagnosticMessage {
        var diagnosticID: MessageID {
            MessageID(domain: "\(Self.self)", id: error.description)
        }

        var severity: DiagnosticSeverity {
            switch error {
            case .incorrectDeclarationType,
                    .missingInstantiableConformance,
                    .missingRequiredInstantiateMethod,
                    .missingAttributes,
                    .disallowedGenericParameter,
                    .disallowedEffectSpecifiers,
                    .incorrectReturnType,
                    .disallowedGenericWhereClause:
                    .error
            }
        }

        var message: String {
            error.description
        }

        let error: FixableInstantiableExtensionError
    }

    // MARK: - InstantiableExtensionFixItMessage

    private struct InstantiableExtensionFixItMessage: FixItMessage {
        var message: String {
            switch error {
            case .incorrectDeclarationType:
                "Replace macro with \(InstantiableVisitor.macroName)"
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
                "Make `instantiate()`’s return type the same as the extended type"
            case .disallowedGenericWhereClause:
                "Remove generic `where` clause"
            }
        }

        var fixItID: MessageID {
            MessageID(domain: "\(Self.self)", id: error.description)
        }

        let error: FixableInstantiableExtensionError
    }
}
