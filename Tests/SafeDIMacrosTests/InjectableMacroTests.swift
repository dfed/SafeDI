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

        // MARK: Behavior Tests

        func test_providingMacros_containsInjectable() {
            XCTAssertTrue(SafeDIMacroPlugin().providingMacros.contains(where: { $0 == InjectableMacro.self }))
        }

        func test_propertyIsFulfilledByTypeWithStringLiteral_expandsWithoutIssue() {
            assertMacro {
                """
                public struct ExampleService {
                    @Instantiated(fulfilledByType: "SomethingElse") let something: Something
                }
                """
            } expansion: {
                """
                public struct ExampleService {
                    let something: Something
                }
                """
            }
        }

        func test_propertyIsFulfilledByTypeWithStringLiteralNestedType_expandsWithoutIssue() {
            assertMacro {
                """
                public struct ExampleService {
                    init(instantiatedA: InstantiatedA) {
                        self.instantiatedA = instantiatedA
                    }

                    @Instantiated(fulfilledByType: "Module.ConcreteType") let instantiatedA: InstantiatedA
                }
                """
            } expansion: {
                """
                public struct ExampleService {
                    init(instantiatedA: InstantiatedA) {
                        self.instantiatedA = instantiatedA
                    }

                    let instantiatedA: InstantiatedA
                }
                """
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

                    @Instantiated var instantiatedA: InstantiatedA
                }
                """
            } diagnostics: {
                """
                public struct ExampleService {
                    init(instantiatedA: InstantiatedA) {
                        self.instantiatedA = instantiatedA
                    }

                    @Instantiated var instantiatedA: InstantiatedA
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

                    @Instantiated  let instantiatedA: InstantiatedA
                }
                """
            } expansion: {
                """
                public struct ExampleService {
                    init(instantiatedA: InstantiatedA) {
                        self.instantiatedA = instantiatedA
                    }

                    let instantiatedA: InstantiatedA
                }
                """
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
                    @Instantiated var instantiatedA: InstantiatedA

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

        func test_throwsErrorWhenUsingFulfilledByTypeOnInstantiator() {
            assertMacro {
                """
                public struct ExampleService {
                    @Instantiated(fulfilledByType: "LoginViewController") let loginViewControllerBuilder: Instantiator<UIViewController>
                }
                """
            } diagnostics: {
                """
                public struct ExampleService {
                    @Instantiated(fulfilledByType: "LoginViewController") let loginViewControllerBuilder: Instantiator<UIViewController>
                    ┬────────────────────────────────────────────────────
                    ╰─ 🛑 The argument `fulfilledByType` can not be used on an `Instantiator` or `SendableInstantiator`. Use an `ErasedInstantiator` or `SendableErasedInstantiator` instead
                }
                """
            }
        }

        func test_throwsErrorWhenErasedInstantiatorUsedWithoutFulfilledByTypeArgument() {
            assertMacro {
                """
                public struct ExampleService {
                    @Instantiated let loginViewControllerBuilder: ErasedInstantiator<UIViewController>
                }
                """
            } diagnostics: {
                """
                public struct ExampleService {
                    @Instantiated let loginViewControllerBuilder: ErasedInstantiator<UIViewController>
                    ┬────────────
                    ╰─ 🛑 `ErasedInstantiator` and `SendableErasedInstantiator` require use of the argument `fulfilledByType`
                }
                """
            }
        }

        func test_throwsErrorWhenInjectableMacroAttachedtoStaticProperty() {
            assertMacro {
                """
                public struct ExampleService {
                    init(instantiatedA: InstantiatedA) {
                        self.instantiatedA = instantiatedA
                    }

                    @Received static let instantiatedA: InstantiatedA
                }
                """
            } diagnostics: {
                """
                public struct ExampleService {
                    init(instantiatedA: InstantiatedA) {
                        self.instantiatedA = instantiatedA
                    }

                    @Received static let instantiatedA: InstantiatedA
                    ┬────────
                    ╰─ 🛑 This macro can not decorate `static` variables
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
                    @Instantiated(fulfilledByType: fulfilledByType) let instantiatedA: InstantiatedA
                }
                """
            } diagnostics: {
                """
                public struct ExampleService {
                    init(instantiatedA: InstantiatedA) {
                        self.instantiatedA = instantiatedA
                    }

                    static let fulfilledByType = "ConcreteType"
                    @Instantiated(fulfilledByType: fulfilledByType) let instantiatedA: InstantiatedA
                    ┬──────────────────────────────────────────────
                    ╰─ 🛑 The argument `fulfilledByType` must be a string literal
                }
                """
            }
        }

        func test_throwsErrorWhenFulfilledByTypeIsNotAStringExpression() {
            assertMacro {
                """
                public struct ExampleService {
                    init(instantiatedA: InstantiatedA) {
                        self.instantiatedA = instantiatedA
                    }

                    static let fulfilledByType = "ConcreteType"
                    @Instantiated(fulfilledByType: "\\(Self.fulfilledByType)") let instantiatedA: InstantiatedA
                }
                """
            } diagnostics: {
                #"""
                public struct ExampleService {
                    init(instantiatedA: InstantiatedA) {
                        self.instantiatedA = instantiatedA
                    }

                    static let fulfilledByType = "ConcreteType"
                    @Instantiated(fulfilledByType: "\(Self.fulfilledByType)") let instantiatedA: InstantiatedA
                    ┬────────────────────────────────────────────────────────
                    ╰─ 🛑 The argument `fulfilledByType` must be a string literal
                }
                """#
            }
        }

        func test_throwsErrorWhenFulfilledByTypeIsAnOptionalType() {
            assertMacro {
                """
                public struct ExampleService {
                    init(instantiatedA: InstantiatedA) {
                        self.instantiatedA = instantiatedA
                    }

                    @Instantiated(fulfilledByType: "ConcreteType?") let instantiatedA: InstantiatedA
                }
                """
            } diagnostics: {
                """
                public struct ExampleService {
                    init(instantiatedA: InstantiatedA) {
                        self.instantiatedA = instantiatedA
                    }

                    @Instantiated(fulfilledByType: "ConcreteType?") let instantiatedA: InstantiatedA
                    ┬──────────────────────────────────────────────
                    ╰─ 🛑 The argument `fulfilledByType` must refer to a simple type
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

                    @Instantiated(fulfilledByType: "ConcreteType!") let instantiatedA: InstantiatedA
                }
                """
            } diagnostics: {
                """
                public struct ExampleService {
                    init(instantiatedA: InstantiatedA) {
                        self.instantiatedA = instantiatedA
                    }

                    @Instantiated(fulfilledByType: "ConcreteType!") let instantiatedA: InstantiatedA
                    ┬──────────────────────────────────────────────
                    ╰─ 🛑 The argument `fulfilledByType` must refer to a simple type
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
                    @Received(fulfilledByDependencyNamed: instantiatedAName, ofType: InstantiatedA.self) let receivedA: ReceivedA
                }
                """
            } diagnostics: {
                """
                @Instantiable
                public struct ExampleService {
                    static let instantiatedAName: StaticString = "instantiatedA"
                    @Received(fulfilledByDependencyNamed: instantiatedAName, ofType: InstantiatedA.self) let receivedA: ReceivedA
                    ┬───────────────────────────────────────────────────────────────────────────────────
                    ╰─ 🛑 The argument `fulfilledByDependencyNamed` must be a string literal
                }
                """
            }
        }

        func test_throwsErrorWhenOfTypeIsAnInvalidType() {
            assertMacro {
                """
                @Instantiable
                public struct ExampleService {
                    @Received(fulfilledByDependencyNamed: "instantiatedA", ofType: "InstantiatedA") let receivedA: ReceivedA
                }
                """
            } diagnostics: {
                """
                @Instantiable
                public struct ExampleService {
                    @Received(fulfilledByDependencyNamed: "instantiatedA", ofType: "InstantiatedA") let receivedA: ReceivedA
                    ┬──────────────────────────────────────────────────────────────────────────────
                    ╰─ 🛑 The argument `ofType` must be a type literal
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
                    @Received(fulfilledByDependencyNamed: "receivedA", ofType: ReceivedA.self, erasedToConcreteExistential: erasedToConcreteExistential) let receivedA: AnyReceivedA
                }
                """
            } diagnostics: {
                """
                @Instantiable
                public struct ExampleService {
                    static let erasedToConcreteExistential = true
                    @Received(fulfilledByDependencyNamed: "receivedA", ofType: ReceivedA.self, erasedToConcreteExistential: erasedToConcreteExistential) let receivedA: AnyReceivedA
                    ┬───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
                    ╰─ 🛑 The argument `erasedToConcreteExistential` must be a bool literal
                }
                """
            }
        }
    }
#endif
