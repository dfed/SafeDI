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

public enum FixableInjectableError: DiagnosticError {
    case unexpectedMutable

    public var description: String {
        switch self {
        case .unexpectedMutable:
            "Dependency can not be mutable"
        }
    }

    public var diagnostic: DiagnosticMessage {
        InjectableDiagnosticMessage(error: self)
    }

    public var fixIt: FixItMessage {
        InjectableFixItMessage(error: self)
    }

    // MARK: - InjectableDiagnosticMessage

    private struct InjectableDiagnosticMessage: DiagnosticMessage {
        var diagnosticID: MessageID {
            MessageID(domain: "\(Self.self)", id: error.description)
        }

        var severity: DiagnosticSeverity {
            switch error {
            case .unexpectedMutable:
                .error
            }
        }

        var message: String {
            error.description
        }

        let error: FixableInjectableError
    }

    // MARK: - InjectableFixItMessage

    private struct InjectableFixItMessage: FixItMessage {
        var message: String {
            switch error {
            case .unexpectedMutable:
                "Replace `var` with `let`"
            }
        }

        var fixItID: SwiftDiagnostics.MessageID {
            MessageID(domain: "\(Self.self)", id: error.description)
        }

        let error: FixableInjectableError
    }
}
