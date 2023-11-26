import SwiftSyntax
import SwiftSyntaxBuilder

extension FunctionDeclSyntax {

    static var buildTemplate: Self {
        try! FunctionDeclSyntax("""
            func build(<#T##parameter#>: <#T##ParameterType#>) \(returnClauseTemplate) {
                <#T##ConcreteBuiltProductType#>(<#T##parameter#>: <#T##ParameterType#>)
            }
        """)
    }

    static var returnClauseTemplate: ReturnClauseSyntax {
        ReturnClauseSyntax(
            type: TypeSyntax(" <#T##BuiltProductType#>")
        )
    }
}
