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
    case dependencyHasTooManyAttributes
    case dependencyHasInitializer
    case missingPublicOrOpenAttribute
    case missingRequiredInitializer

    public var description: String {
        switch self {
        case .dependencyHasTooManyAttributes:
            "Dependency can have at most one of @\(Dependency.Source.instantiated), @\(Dependency.Source.received), or @\(Dependency.Source.forwarded) attached macro"
        case .dependencyHasInitializer:
            "Dependency must not have hand-written initializer"
        case .missingPublicOrOpenAttribute:
            "@\(InstantiableVisitor.macroName)-decorated type must be `public` or `open`"
        case .missingRequiredInitializer:
            // TODO: Create fixit just for `public` or `open` missing.
            "@\(InstantiableVisitor.macroName)-decorated type must have `public` or `open` initializer comprising all injected parameters"
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
            case .dependencyHasTooManyAttributes,
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

        var fixItID: SwiftDiagnostics.MessageID {
            MessageID(domain: "\(Self.self)", id: error.description)
        }

        let error: FixableInstantiableError
    }
}
