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

public enum FixableDependenciesError: DiagnosticError {
    case missingDependenciesAttribute
    case missingPublicAttributeOnDependencies
    case dependencyHasTooManyAttributes
    case dependencyIsStatic
    case dependencyIsNotPrivate
    case dependencyIsMutable
    case unexpectedInitializer
    case missingBuildMethod
    case missingBuildMethodReturnClause
    case multipleBuildMethods
    case duplicateDependency

    public var description: String {
        switch self {
        case .missingDependenciesAttribute:
            return "Missing `@\(DependenciesVisitor.macroName)` attached macro on `public struct Dependencies`"
        case .missingPublicAttributeOnDependencies:
            return "Missing `public` modifier on `struct Dependencies`"
        case .dependencyHasTooManyAttributes:
            return "Dependency can have at most one `@\(Dependency.Source.constructedAttributeName)` or `@\(Dependency.Source.singletonAttributeName)` attached macro"
        case .dependencyIsStatic:
            return "Dependency must not be `static`"
        case .dependencyIsNotPrivate:
            return "Dependency property must be `private`"
        case .dependencyIsMutable:
            return "Dependency must be immutable"
        case .unexpectedInitializer:
            return "Dependency must not have hand-written initializer"
        case .missingBuildMethod:
            return "@\(DependenciesVisitor.macroName)-decorated type must have `func build(...) -> BuiltProduct` method"
        case .missingBuildMethodReturnClause:
            return "@\(DependenciesVisitor.macroName)-decorated type's `func build(...)` method must return a type"
        case .multipleBuildMethods:
            return "@\(DependenciesVisitor.macroName)-decorated type must have a single `func build(...) -> BuiltProduct` method"
        case .duplicateDependency:
            return "Every declared dependency must have a unique name"
        }
    }

    public var diagnostic: DiagnosticMessage {
        DependenciesDiagnosticMessage(error: self)
    }

    public var fixIt: FixItMessage {
        DependenciesFixItMessage(error: self)
    }

    // MARK: - DependenciesDiagnosticMessage

    private struct DependenciesDiagnosticMessage: DiagnosticMessage {

        var diagnosticID: MessageID {
            MessageID(domain: "FixableDependenciesError.DiagnosticMessage", id: error.description)
        }

        var severity: DiagnosticSeverity {
            switch error {
            case .missingDependenciesAttribute,
                    .missingPublicAttributeOnDependencies,
                    .dependencyHasTooManyAttributes,
                    .dependencyIsStatic,
                    .dependencyIsNotPrivate,
                    .dependencyIsMutable,
                    .unexpectedInitializer,
                    .missingBuildMethod,
                    .missingBuildMethodReturnClause,
                    .multipleBuildMethods,
                    .duplicateDependency:
                return .error
            }
        }

        var message: String {
            error.description
        }

        let error: FixableDependenciesError
    }

    // MARK: - DependenciesFixItMessage

    struct DependenciesFixItMessage: SwiftDiagnostics.FixItMessage {
        var message: String {
            switch error {
            case .missingDependenciesAttribute:
                return "Attach `@\(DependenciesVisitor.macroName)` macro"
            case .missingPublicAttributeOnDependencies:
                return "Make `struct \(DependenciesVisitor.decoratedStructName)` have an access level of `public`"
            case .dependencyHasTooManyAttributes:
                return "Remove all but first `@\(Dependency.Source.constructedAttributeName)` or `@\(Dependency.Source.singletonAttributeName)` attached macro"
            case .dependencyIsStatic:
                return "Remove `static` from property"
            case .dependencyIsNotPrivate:
                return "Make property `private`"
            case .dependencyIsMutable:
                return "Make property immutable"
            case .unexpectedInitializer:
                return "Remove initializer"
            case .missingBuildMethod:
                return "Add `func build(...) -> BuiltProduct` template"
            case .missingBuildMethodReturnClause:
                return "Add return clause to `func build(...)`"
            case .multipleBuildMethods:
                return "Remove duplicate `func build(...)` method"
            case .duplicateDependency:
                return "Delete duplicated dependency"
            }
        }

        var fixItID: SwiftDiagnostics.MessageID {
            MessageID(domain: "FixableDependenciesError.FixItMessage", id: error.description)
        }


        let error: FixableDependenciesError
    }
}
