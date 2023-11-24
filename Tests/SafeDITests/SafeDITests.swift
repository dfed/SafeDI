import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(SafeDIMacros)
import SafeDIMacros

let testMacros: [String: Macro.Type] = [
    // TODO: define macro here!
    // Left side string version of macro. Right side the macro type.
    :
]
#endif

final class SafeDITests: XCTestCase {
    func testMacro() throws {
        #if canImport(SafeDIMacros)
        assertMacroExpansion(
            """
            """,
            expandedSource: """
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
