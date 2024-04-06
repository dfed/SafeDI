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
    case incorrectDeclarationType
    case dependencyHasTooManyAttributes
    case dependencyHasInitializer
    case missingPublicOrOpenAttribute
    case missingRequiredInitializer(hasInjectableProperties: Bool)

    public var description: String {
        switch self {
        case .incorrectDeclarationType:
            "@\(InstantiableVisitor.macroName)-decoration is reserved for type declarations"
        case .dependencyHasTooManyAttributes:
            "Dependency can have at most one of @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue) attached macro"
        case .dependencyHasInitializer:
            "Dependency must not have hand-written initializer"
        case .missingPublicOrOpenAttribute:
            "@\(InstantiableVisitor.macroName)-decorated type must be `public` or `open`"
        case let .missingRequiredInitializer(hasInjectableProperties):
            if hasInjectableProperties {
                "@\(InstantiableVisitor.macroName)-decorated type must have a `public` or `open` initializer with a parameter for each @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue)-decorated property. Parameters in this initializer that do not correspond to a decorated property must have default values."
            } else {
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
        var diagnosticID: MessageID {
            MessageID(domain: "\(Self.self)", id: error.description)
        }

        var severity: DiagnosticSeverity {
            switch error {
            case .incorrectDeclarationType,
                    .dependencyHasTooManyAttributes,
                    .dependencyHasInitializer,
                    .missingPublicOrOpenAttribute,
                    .missingRequiredInitializer:
                    .error
            }
        }

        var message: String {
            error.description
        }

        let error: FixableInstantiableError
    }

    // MARK: - InstantiableFixItMessage

    private struct InstantiableFixItMessage: FixItMessage {
        var message: String {
            switch error {
            case .incorrectDeclarationType:
                "Replace macro with \(InstantiableVisitor.extendedMacroName)"
            case .dependencyHasTooManyAttributes:
                "Remove excessive attached macros"
            case .dependencyHasInitializer:
                "Remove initializer"
            case .missingPublicOrOpenAttribute:
                "Add `public` modifier"
            case .missingRequiredInitializer:
                "Add required initializer"
            }
        }

        var fixItID: MessageID {
            MessageID(domain: "\(Self.self)", id: error.description)
        }

        let error: FixableInstantiableError
    }
}
