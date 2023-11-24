import SafeDIVisitors
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// TODO: define macros (e.g. `ExpressionMacro`-conforming type) here.

@main
struct SafeDIPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        // TODO: list macros here!
    ]
}
