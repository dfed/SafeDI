import SwiftSyntax
import SwiftParser
import XCTest

@testable import SafeDIVisitors

final class LabeledExpressionRewriterTests: XCTestCase {

    func testRewrite() {
        let rewriter = LabeledExpressionRewriter(
            expressionDeclarationsToRewrite: .init([
                "providedProperty",
                "constructedProperty"
            ]),
            rewrittenWithPrefixedMember: "scope")

        let source = """
        Test(
            string: "Bart",
            prefixedProvided: providedProperty,
            prefixedProvidedWithPropertyAccess: providedProperty.test,
            prefixedProvidedWithNestedPropertyAccess: providedProperty.test.thing,
            prefixedConstructed: constructedProperty,
            doNotRewrite: doNotRewrite,
            doNotRewriteWithMisleadingPropertyAccess: doNotRewrite.providedProperty,
            doNotRewriteWithNestedMisleadingPropertyAccess: doNotRewrite.providedProperty.test,
            type: ProvidedProperty.self
        )
        """

        XCTAssertEqual(
            rewriter.rewrite(Parser.parse(source: source)).description,
            """
            Test(
                string: "Bart",
                prefixedProvided: scope.providedProperty,
                prefixedProvidedWithPropertyAccess: scope.providedProperty.test,
                prefixedProvidedWithNestedPropertyAccess: scope.providedProperty.test.thing,
                prefixedConstructed: scope.constructedProperty,
                doNotRewrite: doNotRewrite,
                doNotRewriteWithMisleadingPropertyAccess: doNotRewrite.providedProperty,
                doNotRewriteWithNestedMisleadingPropertyAccess: doNotRewrite.providedProperty.test,
                type: ProvidedProperty.self
            )
            """
        )
    }
}
