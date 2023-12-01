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

import SwiftSyntax
import SwiftSyntaxBuilder

extension Array where Element == Dependency {

    var removingDuplicateInitializerArguments: Self {
        var alreadySeenInitializerArgument = Set<Property>()
        return filter {
            let initializerArgument = $0.asInitializerArgument
            if alreadySeenInitializerArgument.contains(initializerArgument) {
                return false
            } else {
                alreadySeenInitializerArgument.insert(initializerArgument)
                return true
            }
        }
    }

    var buildDependenciesFunctionParameter: FunctionParameterSyntax {
        FunctionParameterSyntax(
            firstName: Initializer.Argument.dependenciesArgumentName,
            colon: .colonToken(trailingTrivia: .space),
            type: buildDependenciesFunctionSignature,
            trailingComma: filter { $0.isForwarded }.isEmpty ? nil : .commaToken(trailingTrivia: .space)
        )
    }

    var buildDependenciesFunctionSignature: FunctionTypeSyntax {
        FunctionTypeSyntax(
            parameters: buildDependenciesClosureArguments,
            returnClause: ReturnClauseSyntax(
                leadingTrivia: .space,
                type: TupleTypeSyntax(
                    leadingTrivia: .space,
                    elements: buildDependenciesClosureReturnType
                )
            )
        )
    }

    var buildDependenciesClosureArguments: TupleTypeElementListSyntax {
        TupleTypeElementListSyntax {
            for variantUnamedTuple in variantUnamedTuples {
                variantUnamedTuple
            }
        }
    }

    var buildDependenciesClosureReturnType: TupleTypeElementListSyntax {
        TupleTypeElementListSyntax {
            for invariantNamedTuple in namedInitializerReturnTypeTuples {
                invariantNamedTuple
            }
        }
    }

    var namedInitializerReturnTypeTuples: [TupleTypeElementSyntax] {
        return map {
            if count > 1 {
                return $0.asInitializerArgument.asNamedTupleTypeElement
            } else {
                return $0.asInitializerArgument.asUnnamedTupleTypeElement
            }
        }
        .transformUntilLast {
            var node = $0
            node.trailingComma = .commaToken(trailingTrivia: .space)
            return node
        }
    }

    var variantUnamedTuples: [TupleTypeElementSyntax] {
        filter { $0.isForwarded }
            .map(\.property.asUnnamedTupleTypeElement)
            .transformUntilLast {
                var node = $0
                node.trailingComma = .commaToken(trailingTrivia: .space)
                return node
            }
    }

    var initializerFunctionParameters: [FunctionParameterSyntax] {
        removingDuplicateInitializerArguments
            .map { $0.asInitializerArgument.asFunctionParamter }
            .transformUntilLast {
                var node = $0
                node.trailingComma = .commaToken(trailingTrivia: .space)
                return node
            }
    }

    var forwardedFunctionParameters: [FunctionParameterSyntax] {
        filter { $0.isForwarded }
            .map { $0.property.asFunctionParamter }
            .transformUntilLast {
                var node = $0
                node.trailingComma = .commaToken(trailingTrivia: .space)
                return node
            }
    }

    var forwardedLabeledExpressions: [LabeledExprSyntax] {
        filter { $0.isForwarded }
            .map { $0.property.asUnnamedLabeledExpr }
            .transformUntilLast {
                var node = $0
                node.trailingComma = .commaToken(trailingTrivia: .space)
                return node
            }
    }

    var dependenciesDeclaration: VariableDeclSyntax {
        VariableDeclSyntax(
            leadingTrivia: .spaces(4),
            .let,
            name: PatternSyntax(
                IdentifierPatternSyntax(
                    leadingTrivia: .space,
                    identifier: isEmpty ? .identifier("_") : Initializer.dependenciesToken)
            ),
            initializer: InitializerClauseSyntax(
                leadingTrivia: .space,
                equal: .equalToken(trailingTrivia: .space),
                value: FunctionCallExprSyntax(
                    calledExpression: DeclReferenceExprSyntax(
                        baseName: Initializer.Argument.dependenciesArgumentName),
                    leftParen: .leftParenToken(),
                    arguments: LabeledExprListSyntax {
                        for forwardedLabeledExpression in forwardedLabeledExpressions {
                            forwardedLabeledExpression
                        }
                    },
                    rightParen: .rightParenToken()
                ),
                trailingTrivia: .newline
            )
        )
    }
}

extension Array {
    fileprivate func transformUntilLast(_ transform: (Element) throws -> Element) rethrows -> [Element] {
        var arrayToTransform = self
        guard let lastItem = arrayToTransform.popLast() else {
            // Array is empty.
            return self
        }
        return try arrayToTransform.map { try transform($0) } + [lastItem]
    }
}
