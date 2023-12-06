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

import MacroTesting
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

import SafeDICore

#if canImport(SafeDIMacros)
@testable import SafeDIMacros


final class InjectableMacroTests: XCTestCase {

    let testMacros: [String: Macro.Type] = [
        Dependency.Source.instantiated.rawValue: InjectableMacro.self,
        Dependency.Source.inherited.rawValue: InjectableMacro.self,
        Dependency.Source.forwarded.rawValue: InjectableMacro.self,
    ]

    // MARK: XCTestCase

    override func invokeTest() {
        withMacroTesting(macros: testMacros) {
            super.invokeTest()
        }
    }

    // MARK: Fixit Tests

    func test_fixit_addsFixitWhenInjectableParameterIsMutable() {
        assertMacro {
            """
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Instantiated
                var invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Instantiated
                var invariantA: InvariantA
                ┬──
                ╰─ 🛑 Dependency can not be mutable
                   ✏️ Replace `var` with `let`
            }
            """
        } fixes: {
            """
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Instantiated let  let invariantA: InvariantA
            }
            """ // fixes are wrong! It's duplicating the correction. not sure why.
        } expansion: {
            """
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                let  let invariantA: InvariantA
            }
            """ // expansion is wrong! It's duplicating the correction. not sure why.
        }
    }


    // MARK: Error tests

    func test_throwsErrorWhenInjectableMacroAttachedtoStaticProperty() {
        assertMacro {
            """
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Inherited
                static let invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Inherited
                ┬─────────
                ╰─ 🛑 This macro can not decorate `static` variables
                static let invariantA: InvariantA
            }
            """
        }
    }

    func test_throwsErrorWhenOnProtocol() {
        assertMacro {
            """
            @Instantiated
            protocol ExampleService {}
            """
        } diagnostics: {
            """
            @Instantiated
            ┬────────────
            ╰─ 🛑 This macro must decorate a instance variable
            protocol ExampleService {}
            """
        }
    }
}
#endif
