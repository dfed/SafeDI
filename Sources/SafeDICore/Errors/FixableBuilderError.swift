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

public enum FixableBuilderError: DiagnosticError {
    case missingDependencies
    case unexpectedVariableDeclaration
    case unexpectedInitializer
    case unexpectedFuncationDeclaration

    public var description: String {
        switch self {
        case .missingDependencies:
            return "Missing nested `@\(DependenciesVisitor.macroName) public struct \(DependenciesVisitor.decoratedStructName)` declaration"
        case .unexpectedVariableDeclaration:
            return "Found unexpected variable declaration in `\(BuilderVisitor.decoratedStructName)`"
        case .unexpectedInitializer:
            return "Found unexpected initializer in `\(BuilderVisitor.decoratedStructName)`"
        case .unexpectedFuncationDeclaration:
            return "Found unexpected function declaration in `\(BuilderVisitor.decoratedStructName)`"
        }
    }

    public var diagnostic: SwiftDiagnostics.DiagnosticMessage {
        BuilderDiagnosticMessage(error: self)
    }

    public var fixIt: SwiftDiagnostics.FixItMessage {
        BuilderFixItMessage(error: self)
    }

    // MARK: - BuilderDiagnosticMessage

    private struct BuilderDiagnosticMessage: DiagnosticMessage {
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

        let error: FixableBuilderError
    }

    // MARK: - BuilderFixItMessage

    private struct BuilderFixItMessage: FixItMessage {
        var message: String {
            switch error {
            case .missingDependencies:
                return "Create nested `@\(DependenciesVisitor.macroName) struct \(DependenciesVisitor.decoratedStructName)`"
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
