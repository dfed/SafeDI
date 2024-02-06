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
        Dependency.Source.instantiatedRawValue: InjectableMacro.self,
        Dependency.Source.receivedRawValue: InjectableMacro.self,
        Dependency.Source.forwardedRawValue: InjectableMacro.self,
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
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                @Instantiated
                var instantiatedA: InstantiatedA
            }
            """
        } diagnostics: {
            """
            public struct ExampleService {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                @Instantiated
                var instantiatedA: InstantiatedA
                ┬──
                ╰─ 🛑 Dependency can not be mutable unless it is decorated with a property wrapper. Mutations to a dependency are not propagated through the dependency tree.
                   ✏️ Replace `var` with `let`
            }
            """
        } fixes: {
            """
            public struct ExampleService {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                @Instantiated let  let instantiatedA: InstantiatedA
            }
            """ // fixes are wrong! It’s duplicating the correction. not sure why.
        } expansion: {
            """
            public struct ExampleService {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                let  let instantiatedA: InstantiatedA
            }
            """ // expansion is wrong! It’s duplicating the correction. not sure why.
        }
    }

    func test_fixit_doesNotAddFixitWhenInjectableParameterIsMutableWithPropertyWrapper() {
        assertMacro {
            """
            import SwiftUI

            public struct ExampleView {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                @ObservedObject
                @Instantiated
                var instantiatedA: InstantiatedA

                var body: some View {
                    Text("\\(ObjectIdentifier(instantiatedA))")
                }
            }
            """
        } expansion: {
            #"""
            import SwiftUI

            public struct ExampleView {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                @ObservedObject
                var instantiatedA: InstantiatedA

                var body: some View {
                    Text("\(ObjectIdentifier(instantiatedA))")
                }
            }
            """#
        }
    }

    // MARK: Error tests

    func test_throwsErrorWhenInjectableMacroAttachedtoStaticProperty() {
        assertMacro {
            """
            public struct ExampleService {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                @Received
                static let instantiatedA: InstantiatedA
            }
            """
        } diagnostics: {
            """
            public struct ExampleService {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                @Received
                ┬────────
                ╰─ 🛑 This macro can not decorate `static` variables
                static let instantiatedA: InstantiatedA
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

    func test_throwsErrorWhenFulfilledByTypeIsNotALiteral() {
        assertMacro {
            """
            public struct ExampleService {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                static let fulfilledByType = "ConcreteType"
                @Instantiated(fulfilledByType: fulfilledByType)
                let instantiatedA: InstantiatedA
            }
            """
        } diagnostics: {
            """
            public struct ExampleService {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                static let fulfilledByType = "ConcreteType"
                @Instantiated(fulfilledByType: fulfilledByType)
                ┬──────────────────────────────────────────────
                ╰─ 🛑 The argument `fulfilledByType` must be a string literal
                let instantiatedA: InstantiatedA
            }
            """
        }
    }

    func test_throwsErrorWhenFulfilledByTypeIsANestedType() {
        assertMacro {
            """
            public struct ExampleService {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                @Instantiated(fulfilledByType: "Module.ConcreteType")
                let instantiatedA: InstantiatedA
            }
            """
        } diagnostics: {
            """
            public struct ExampleService {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                @Instantiated(fulfilledByType: "Module.ConcreteType")
                ┬────────────────────────────────────────────────────
                ╰─ 🛑 The argument `fulfilledByType` must refer to a simple, unnested type
                let instantiatedA: InstantiatedA
            }
            """
        }
    }

    func test_throwsErrorWhenFulfilledByTypeIsAnOptionalType() {
        assertMacro {
            """
            public struct ExampleService {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                @Instantiated(fulfilledByType: "ConcreteType?")
                let instantiatedA: InstantiatedA
            }
            """
        } diagnostics: {
            """
            public struct ExampleService {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                @Instantiated(fulfilledByType: "ConcreteType?")
                ┬──────────────────────────────────────────────
                ╰─ 🛑 The argument `fulfilledByType` must refer to a simple, unnested type
                let instantiatedA: InstantiatedA
            }
            """
        }
    }

    func test_throwsErrorWhenFulfilledByTypeIsAnImplicitlyUnwrappedType() {
        assertMacro {
            """
            public struct ExampleService {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                @Instantiated(fulfilledByType: "ConcreteType!")
                let instantiatedA: InstantiatedA
            }
            """
        } diagnostics: {
            """
            public struct ExampleService {
                init(instantiatedA: InstantiatedA) {
                    self.instantiatedA = instantiatedA
                }

                @Instantiated(fulfilledByType: "ConcreteType!")
                ┬──────────────────────────────────────────────
                ╰─ 🛑 The argument `fulfilledByType` must refer to a simple, unnested type
                let instantiatedA: InstantiatedA
            }
            """
        }
    }

    func test_throwsErrorWhenfulfilledByDependencyNamedIsNotAStringLiteral() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                static let instantiatedAName: StaticString = "instantiatedA"
                @Received(fulfilledByDependencyNamed: instantiatedAName, ofType: InstantiatedA.self)
                let receivedA: ReceivedA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                static let instantiatedAName: StaticString = "instantiatedA"
                @Received(fulfilledByDependencyNamed: instantiatedAName, ofType: InstantiatedA.self)
                ┬───────────────────────────────────────────────────────────────────────────────────
                ╰─ 🛑 The argument `fulfilledByDependencyNamed` must be a string literal
                let receivedA: ReceivedA
            }
            """
        }
    }

    func test_throwsErrorWhenOfTypeIsAnInvalidType() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                @Received(fulfilledByDependencyNamed: "instantiatedA", ofType: "InstantiatedA")
                let receivedA: ReceivedA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                @Received(fulfilledByDependencyNamed: "instantiatedA", ofType: "InstantiatedA")
                ┬──────────────────────────────────────────────────────────────────────────────
                ╰─ 🛑 The argument `ofType` must be a type literal
                let receivedA: ReceivedA
            }
            """
        }
    }

    func test_throwsErrorWhenIsExistentialIsAnInvalidType() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                static let erasedToConcreteExistential = true
                @Received(
                    fulfilledByDependencyNamed: "receivedA",
                    ofType: ReceivedA.self,
                    erasedToConcreteExistential: erasedToConcreteExistential
                )
                let receivedA: AnyReceivedA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                static let erasedToConcreteExistential = true
                @Received(
                ╰─ 🛑 The argument `erasedToConcreteExistential` must be a bool literal
                    fulfilledByDependencyNamed: "receivedA",
                    ofType: ReceivedA.self,
                    erasedToConcreteExistential: erasedToConcreteExistential
                )
                let receivedA: AnyReceivedA
            }
            """
        }
    }
}
#endif
