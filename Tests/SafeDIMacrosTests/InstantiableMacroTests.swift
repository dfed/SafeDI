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

final class InstantiableMacroTests: XCTestCase {
    let testMacros: [String: Macro.Type] = [
        InstantiableVisitor.macroName: InstantiableMacro.self,
        Dependency.Source.instantiated.rawValue: InjectableMacro.self,
        Dependency.Source.received.rawValue: InjectableMacro.self,
        Dependency.Source.forwarded.rawValue: InjectableMacro.self,
    ]

    // MARK: XCTestCase

    override func invokeTest() {
        withMacroTesting(macros: testMacros) {
            super.invokeTest()
        }
    }

    // MARK: Error tests

    func test_throwsErrorWhenOnProtocol() {
        assertMacro {
            """
            @Instantiable
            public protocol ExampleService {}
            """
        } diagnostics: {
            """
            @Instantiable
            ┬────────────
            ╰─ 🛑 @Instantiable must decorate a class, struct, or actor
            public protocol ExampleService {}
            """
        }
    }

    func test_throwsErrorWhenOnEnum() {
        assertMacro {
            """
            @Instantiable
            public enum ExampleService {}
            """
        } diagnostics: {
            """
            @Instantiable
            ┬────────────
            ╰─ 🛑 @Instantiable must decorate a class, struct, or actor
            public enum ExampleService {}
            """
        }
    }

    func test_throwsErrorWhenMoreThanOneForwardedProperty() {
        assertMacro {
            """
            @Instantiable
            public final class UserService {
                public init(userID: String, userName: String) {
                    self.userID = userID
                    self.userName = userName
                }

                @Forwarded
                let userID: String

                @Forwarded
                let userName: String
            }
            """
        } diagnostics: {
            """
            @Instantiable
            ┬────────────
            ╰─ 🛑 An @Instantiable type must have at most one @Forwarded property
            public final class UserService {
                public init(userID: String, userName: String) {
                    self.userID = userID
                    self.userName = userName
                }

                @Forwarded
                let userID: String

                @Forwarded
                let userName: String
            }
            """
        }
    }

    // MARK: FixIt tests

    func test_fixit_addsFixitWhenMultipleInjectableMacrosOnTopOfSingleProperty() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Received
                @Instantiated
                let receivedA: ReceivedA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
                init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Received
                ╰─ 🛑 Dependency can have at most one of @Instantiated, @Received, or @Forwarded attached macro
                   ✏️ Remove excessive attached macros
                @Instantiated
                let receivedA: ReceivedA
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init() {}

                init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Received
                @Instantiated
                let receivedA: ReceivedA
            }
            """
        }
    }

    func test_fixit_addsFixitWhenInjectableParameterHasInitializer() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Instantiated
                let receivedA: ReceivedA = .init()
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Instantiated
                ╰─ 🛑 Dependency must not have hand-written initializer
                   ✏️ Remove initializer
                let receivedA: ReceivedA = .init()
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Instantiated
                let receivedA: ReceivedA 
            }
            """
        } expansion: {
            """
            public struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }
                let receivedA: ReceivedA 
            }
            """
        }
    }

    func test_fixit_addsFixitWhenInjectableTypeIsNotPublicOrOpen() {
        assertMacro {
            """
            @Instantiable
            struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Instantiated
                let receivedA: ReceivedA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            ╰─ 🛑 @Instantiable-decorated type must be `public` or `open`
               ✏️ Add `public` modifier
            struct ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Instantiated
                let receivedA: ReceivedA
            }
            """
        } fixes: {
            """
            @Instantiable
            public 
            public ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Instantiated
                let receivedA: ReceivedA
            }
            """ // this fixes are wrong (we aren't deleting 'struct'), but also the whitespace is wrong in Xcode.
            // TODO: fix Xcode spacing of this replacement.
        } expansion: {
            """
            @Instantiable
            public 
            public ExampleService {
                public init(receivedA: ReceivedA) {
                    self.receivedA = receivedA
                }

                @Instantiated
                let receivedA: ReceivedA
            }
            """
        }
    }

    func test_fixit_addsFixitMissingRequiredInitializerWithoutAnyDependencies() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init() {}

            public init() {}
            """ // this is seriously incorrect – it works in Xcode.
        } expansion: {
            """
            public struct ExampleService {
            public init() {}

            public init() {}
            """
        }
    }

    func test_fixit_addsFixitMissingRequiredInitializerWithDependencies() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                @Instantiated
                let receivedA: ReceivedA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
                @Instantiated
                let receivedA: ReceivedA
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init(receivedA: ReceivedA) {
            self.receivedA = receivedA
            }

                @Instantiated
                let receivedA: ReceivedA
            }
            """ // Whitespace is correct in Xcode, but not here.
        } expansion: {
            """
            public struct ExampleService {
            public init(receivedA: ReceivedA) {
            self.receivedA = receivedA
            }
                let receivedA: ReceivedA
            }
            """
        }
    }

    func test_fixit_addsFixitMissingRequiredInitializerWhenDependencyMissingFromInit() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                public init(forwardedA: ForwardedA, forwardedB: ForwardedB) {
                    self.forwardedA = forwardedA
                    self.forwardedB = forwardedB
                    receivedA = ReceivedA()
                }

                @Forwarded
                let forwardedA: ForwardedA
                @Received
                let forwardedB: ForwardedB
                @Received
                let receivedA: ReceivedA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
                public init(forwardedA: ForwardedA, forwardedB: ForwardedB) {
                    self.forwardedA = forwardedA
                    self.forwardedB = forwardedB
                    receivedA = ReceivedA()
                }

                @Forwarded
                let forwardedA: ForwardedA
                @Received
                let forwardedB: ForwardedB
                @Received
                let receivedA: ReceivedA
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init(forwardedA: ForwardedA, forwardedB: ForwardedB, receivedA: ReceivedA) {
            self.forwardedA = forwardedA
            self.forwardedB = forwardedB
            self.receivedA = receivedA
            }

                public init(forwardedA: ForwardedA, forwardedB: ForwardedB) {
                    self.forwardedA = forwardedA
                    self.forwardedB = forwardedB
                    receivedA = ReceivedA()
                }

                @Forwarded
                let forwardedA: ForwardedA
                @Received
                let forwardedB: ForwardedB
                @Received
                let receivedA: ReceivedA
            }
            """
        } expansion: {
            """
            public struct ExampleService {
            public init(forwardedA: ForwardedA, forwardedB: ForwardedB, receivedA: ReceivedA) {
            self.forwardedA = forwardedA
            self.forwardedB = forwardedB
            self.receivedA = receivedA
            }

                public init(forwardedA: ForwardedA, forwardedB: ForwardedB) {
                    self.forwardedA = forwardedA
                    self.forwardedB = forwardedB
                    receivedA = ReceivedA()
                }
                let forwardedA: ForwardedA
                let forwardedB: ForwardedB
                let receivedA: ReceivedA
            }
            """
        }
    }

    func test_fixit_addsFixitMissingRequiredInitializerWhenInstantiatorDependencyMissingFromInit() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                @Instantiated
                private let instantiatableAInstantiator: Instantiator<ReceivedA>
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
                @Instantiated
                private let instantiatableAInstantiator: Instantiator<ReceivedA>
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init(instantiatableAInstantiator: Instantiator<ReceivedA>) {
            self.instantiatableAInstantiator = instantiatableAInstantiator
            }

                @Instantiated
                private let instantiatableAInstantiator: Instantiator<ReceivedA>
            }
            """
        } expansion: {
            """
            public struct ExampleService {
            public init(instantiatableAInstantiator: Instantiator<ReceivedA>) {
            self.instantiatableAInstantiator = instantiatableAInstantiator
            }
                private let instantiatableAInstantiator: Instantiator<ReceivedA>
            }
            """
        }
    }


    func test_fixit_addsFixitMissingRequiredInitializerWhenLazyConstructedDependencyMissingFromInit() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                @LazyInstantiated
                private var instantiatableA: ReceivedA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
                @LazyInstantiated
                private var instantiatableA: ReceivedA
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init(instantiatableAInstantiator: Instantiator<ReceivedA>) {
            _instantiatableA = LazyInstantiated(instantiatableAInstantiator)
            }

                @LazyInstantiated
                private var instantiatableA: ReceivedA
            }
            """
        } expansion: {
            """
            public struct ExampleService {
            public init(instantiatableAInstantiator: Instantiator<ReceivedA>) {
            _instantiatableA = LazyInstantiated(instantiatableAInstantiator)
            }

                @LazyInstantiated
                private var instantiatableA: ReceivedA
            }
            """
        }
    }

    func test_fixit_addsFixitMissingRequiredInitializerWhenLazyConstructedAndInstantiatorDependencyOfSameTypeMissingFromInit() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                @LazyInstantiated
                private var instantiatableA: InstantiatableA
                @Instantiated
                let instantiatableAInstantiator: Instantiator<InstantiatableA>
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
                @LazyInstantiated
                private var instantiatableA: InstantiatableA
                @Instantiated
                let instantiatableAInstantiator: Instantiator<InstantiatableA>
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init(instantiatableAInstantiator: Instantiator<InstantiatableA>) {
            _instantiatableA = LazyInstantiated(instantiatableAInstantiator)
            self.instantiatableAInstantiator = instantiatableAInstantiator
            }

                @LazyInstantiated
                private var instantiatableA: InstantiatableA
                @Instantiated
                let instantiatableAInstantiator: Instantiator<InstantiatableA>
            }
            """
        } expansion: {
            """
            public struct ExampleService {
            public init(instantiatableAInstantiator: Instantiator<InstantiatableA>) {
            _instantiatableA = LazyInstantiated(instantiatableAInstantiator)
            self.instantiatableAInstantiator = instantiatableAInstantiator
            }

                @LazyInstantiated
                private var instantiatableA: InstantiatableA
                let instantiatableAInstantiator: Instantiator<InstantiatableA>
            }
            """
        }
    }
}
#endif
