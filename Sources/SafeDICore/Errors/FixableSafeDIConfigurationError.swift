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

public enum FixableSafeDIConfigurationError: DiagnosticError {
    case decoratingNonStruct
    case missingAdditionalImportedModulesProperty
    case missingAdditionalDirectoriesToIncludeProperty
    case additionalImportedModulesNotStringLiteralArray
    case additionalDirectoriesToIncludeNotStringLiteralArray

    public var description: String {
        switch self {
        case .decoratingNonStruct:
            "@\(SafeDIConfigurationVisitor.macroName) must decorate a struct"
        case .missingAdditionalImportedModulesProperty:
            "@\(SafeDIConfigurationVisitor.macroName)-decorated type must have a `let additionalImportedModules: [StaticString]` property"
        case .missingAdditionalDirectoriesToIncludeProperty:
            "@\(SafeDIConfigurationVisitor.macroName)-decorated type must have a `let additionalDirectoriesToInclude: [StaticString]` property"
        case .additionalImportedModulesNotStringLiteralArray:
            "The `additionalImportedModules` property must be initialized with an array of string literals"
        case .additionalDirectoriesToIncludeNotStringLiteralArray:
            "The `additionalDirectoriesToInclude` property must be initialized with an array of string literals"
        }
    }

    public var diagnostic: DiagnosticMessage {
        SafeDIConfigurationDiagnosticMessage(error: self)
    }

    public var fixIt: FixItMessage {
        SafeDIConfigurationFixItMessage(error: self)
    }

    // MARK: - SafeDIConfigurationDiagnosticMessage

    private struct SafeDIConfigurationDiagnosticMessage: DiagnosticMessage {
        init(error: FixableSafeDIConfigurationError) {
            diagnosticID = MessageID(domain: "\(Self.self)", id: error.description)
            severity = switch error {
            case .decoratingNonStruct,
                 .missingAdditionalImportedModulesProperty,
                 .missingAdditionalDirectoriesToIncludeProperty,
                 .additionalImportedModulesNotStringLiteralArray,
                 .additionalDirectoriesToIncludeNotStringLiteralArray:
                .error
            }
            message = error.description
        }

        let diagnosticID: MessageID
        let severity: DiagnosticSeverity
        let message: String
    }

    // MARK: - SafeDIConfigurationFixItMessage

    private struct SafeDIConfigurationFixItMessage: FixItMessage {
        init(error: FixableSafeDIConfigurationError) {
            message = switch error {
            case .decoratingNonStruct:
                "Replace with a struct"
            case .missingAdditionalImportedModulesProperty:
                "Add `let additionalImportedModules: [StaticString]` property"
            case .missingAdditionalDirectoriesToIncludeProperty:
                "Add `let additionalDirectoriesToInclude: [StaticString]` property"
            case .additionalImportedModulesNotStringLiteralArray:
                "Replace with an array of string literals"
            case .additionalDirectoriesToIncludeNotStringLiteralArray:
                "Replace with an array of string literals"
            }
            fixItID = MessageID(domain: "\(Self.self)", id: error.description)
        }

        let message: String
        let fixItID: MessageID
    }
}
