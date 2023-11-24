import SwiftSyntax

/// An argument rewriter that rewrites labeled expressions that match the input prefix.
public final class LabeledExpressionRewriter: SyntaxRewriter {

    // MARK: Initialization

    /// - Parameters:
    ///   - expressionDeclarationsToRewrite: The expressions should be rewritten when the expression declaration is found immediately after the label.
    ///   - prefix: The prefix to prepend to the expression declaration.
    public init(expressionDeclarationsToRewrite: Set<String>, rewrittenWithPrefixedMember prefix: String) {
        declReferenceExprSyntaxRewriter = DeclReferenceExprSyntaxRewriter(
            expressionDeclarationsToRewrite: expressionDeclarationsToRewrite,
            rewrittenWithPrefixedMember: prefix)
    }

    // MARK: SyntaxRewriter

    public override func visit(_ node: LabeledExprSyntax) -> LabeledExprSyntax {
        var rewrittenNode = node
        if let declarationReferenceExpression = DeclReferenceExprSyntax(node.expression) {
            rewrittenNode.expression = declReferenceExprSyntaxRewriter.visit(declarationReferenceExpression)

        } else if 
            let memberAccessExpression = MemberAccessExprSyntax(node.expression),
            let base = memberAccessExpression.base
        {
            // A member access expressions could be comprised of other member access expressions. Drill into the base.
            rewrittenNode.expression = ExprSyntax(
                MemberAccessExprSyntax(
                    base: declReferenceExprSyntaxRewriter.visit(base),
                    declName: memberAccessExpression.declName)
            )
        }

        return rewrittenNode
    }

    private let declReferenceExprSyntaxRewriter: DeclReferenceExprSyntaxRewriter

    // MARK: - DeclReferenceExprSyntaxRewriter

    /// An argument rewriter that rewrites labeled expressions that match the input prefix.
    private final class DeclReferenceExprSyntaxRewriter: SyntaxRewriter {

        init(expressionDeclarationsToRewrite: Set<String>, rewrittenWithPrefixedMember prefix: String) {
            self.expressionDeclarationsToRewrite = expressionDeclarationsToRewrite
            self.prefix = prefix
        }

        // MARK: SyntaxRewriter

        override func visit(_ node: MemberAccessExprSyntax) -> ExprSyntax {
            var rewrittenNode = node
            if let base = node.base {
                // Only recurse on the base. We do **not** want to rewrite the declaration.
                rewrittenNode.base = visit(base)
            }
            return ExprSyntax(rewrittenNode)
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
            if expressionDeclarationsToRewrite.contains(node.baseName.text) {
                // Prepend the `prefix.` to this expression.
                return ExprSyntax(
                    MemberAccessExprSyntax(
                        base: DeclReferenceExprSyntax(
                            baseName: TokenSyntax(
                                TokenKind.identifier(prefix),
                                presence: .present)
                            ),
                        declName: node)
                )
            } else {
                return ExprSyntax(node)
            }
        }

        // MARK: Private

        private let expressionDeclarationsToRewrite: Set<String>
        private let prefix: String
    }

}
