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

enum FixableBuilderError: DiagnosticError {
    case missingDependencies
    case unexpectedVariableDeclaration
    case unexpectedInitializer
    case unexpectedFuncationDeclaration

    var description: String {
        switch self {
        case .missingDependencies:
            return "Missing nested `@\(DependenciesMacro.name) public struct \(DependenciesMacro.decoratedStructName)` declaration"
        case .unexpectedVariableDeclaration:
            return "Found unexpected variable declaration in `\(BuilderMacro.decoratedStructName)`"
        case .unexpectedInitializer:
            return "Found unexpected initializer in `\(BuilderMacro.decoratedStructName)`"
        case .unexpectedFuncationDeclaration:
            return "Found unexpected function declaration in `\(BuilderMacro.decoratedStructName)`"
        }
    }

    var diagnostic: DiagnosticMessage {
        DiagnosticMessage(error: self)
    }

    var fixIt: FixItMessage {
        FixItMessage(error: self)
    }

    struct DiagnosticMessage: SwiftDiagnostics.DiagnosticMessage {

        let error: FixableBuilderError

        var diagnosticID: MessageID {
            MessageID(domain: "FixableBuilderError.DiagnosticMessage", id: error.description)
        }

        var severity: DiagnosticSeverity {
            switch error {
            case .missingDependencies,
                    .unexpectedVariableDeclaration,
                    .unexpectedInitializer,
                    .unexpectedFuncationDeclaration:
                return .error
            }
        }

        var message: String {
            error.description
        }
    }

    struct FixItMessage: SwiftDiagnostics.FixItMessage {
        var message: String {
            switch error {
            case .missingDependencies:
                return "Create nested `@\(DependenciesMacro.name) struct \(DependenciesMacro.decoratedStructName)`"
            case .unexpectedVariableDeclaration:
                return "Delete variable declaration"
            case .unexpectedInitializer:
                return "Delete initializer"
            case .unexpectedFuncationDeclaration:
                return "Delete function declaration"
            }
        }

        var fixItID: SwiftDiagnostics.MessageID {
            MessageID(domain: "FixableBuilderError.FixItMessage", id: error.description)
        }


        let error: FixableBuilderError
    }
}
