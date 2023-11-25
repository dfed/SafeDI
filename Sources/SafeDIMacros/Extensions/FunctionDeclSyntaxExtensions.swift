import SwiftSyntax
import SwiftSyntaxBuilder

extension FunctionDeclSyntax {

    static var buildTemplate: Self {
        try! FunctionDeclSyntax("public func build(<#T##parameter#>: <#T##ParameterType#>) \(returnClauseTemplate)")
    }

    static var returnClauseTemplate: ReturnClauseSyntax {
        ReturnClauseSyntax(
            type: TypeSyntax(" <#T##BuiltProductType#>")
        )
    }
}
