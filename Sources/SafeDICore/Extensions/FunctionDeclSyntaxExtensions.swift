import SwiftSyntax
import SwiftSyntaxBuilder

extension FunctionDeclSyntax {

    public static var buildTemplate: Self {
        try! FunctionDeclSyntax("""
            func build(<#T##parameter#>: <#T##ParameterType#>) \(returnClauseTemplate) {
                <#T##ConcreteBuiltProductType#>(<#T##parameter#>: <#T##ParameterType#>)
            }
        """)
    }

    public static var returnClauseTemplate: ReturnClauseSyntax {
        ReturnClauseSyntax(
            type: TypeSyntax(" <#T##BuiltProductType#>")
        )
    }
}
