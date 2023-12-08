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
            protocol ExampleService {}
            """
        } diagnostics: {
            """
            @Instantiable
            ┬────────────
            ╰─ 🛑 @Instantiable must decorate a class, struct, or actor
            protocol ExampleService {}
            """
        }
    }

    // MARK: FixIt tests

    func test_fixit_addsFixitWhenMultipleInjectableMacrosOnTopOfSingleProperty() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Received
                @Instantiated
                let invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Received
                ╰─ 🛑 Dependency can have at most one of @Instantiated, @Received, or @Forwarded attached macro
                   ✏️ Remove excessive attached macros
                @Instantiated
                let invariantA: InvariantA
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init() {}

                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Received
                @Instantiated
                let invariantA: InvariantA
            }
            """
        }
    }

    func test_fixit_addsFixitWhenInjectableParameterHasInitializer() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                public init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Instantiated
                let invariantA: InvariantA = .init()
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                public init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Instantiated
                ╰─ 🛑 Dependency must not have hand-written initializer
                   ✏️ Remove initializer
                let invariantA: InvariantA = .init()
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
                public init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Instantiated
                let invariantA: InvariantA 
            }
            """
        } expansion: {
            """
            public struct ExampleService {
                public init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }
                let invariantA: InvariantA 
            }
            """
        }
    }

    func test_fixit_addsFixitWhenInjectableTypeIsNotPublicOrOpen() {
        assertMacro {
            """
            @Instantiable
            struct ExampleService {
                public init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Instantiated
                let invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            ╰─ 🛑 @Instantiable-decorated type must be `public` or `open`
               ✏️ Add `public` modifier
            struct ExampleService {
                public init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Instantiated
                let invariantA: InvariantA
            }
            """
        } fixes: {
            """
            @Instantiable
            public 
            public ExampleService {
                public init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Instantiated
                let invariantA: InvariantA
            }
            """ // this fixes are wrong (we aren't deleting 'struct'), but also the whitespace is wrong in Xcode.
            // TODO: fix Xcode spacing of this replacement.
        } expansion: {
            """
            @Instantiable
            public 
            public ExampleService {
                public init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Instantiated
                let invariantA: InvariantA
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
                let invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
                @Instantiated
                let invariantA: InvariantA
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init(invariantA: InvariantA) {
            self.invariantA = invariantA
            }

                @Instantiated
                let invariantA: InvariantA
            }
            """ // Whitespace is correct in Xcode, but not here.
        } expansion: {
            """
            public struct ExampleService {
            public init(invariantA: InvariantA) {
            self.invariantA = invariantA
            }
                let invariantA: InvariantA
            }
            """
        }
    }

    func test_fixit_addsFixitMissingRequiredInitializerWhenDependencyMissingFromInit() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                public init(variantA: VariantA, variantB: VariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                    invariantA = InvariantA()
                }

                @Forwarded
                let variantA: VariantA
                @Forwarded
                let variantB: VariantB
                @Received
                let invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
                public init(variantA: VariantA, variantB: VariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                    invariantA = InvariantA()
                }

                @Forwarded
                let variantA: VariantA
                @Forwarded
                let variantB: VariantB
                @Received
                let invariantA: InvariantA
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init(variantA: VariantA, variantB: VariantB, invariantA: InvariantA) {
            self.variantA = variantA
            self.variantB = variantB
            self.invariantA = invariantA
            }

                public init(variantA: VariantA, variantB: VariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                    invariantA = InvariantA()
                }

                @Forwarded
                let variantA: VariantA
                @Forwarded
                let variantB: VariantB
                @Received
                let invariantA: InvariantA
            }
            """
        } expansion: {
            """
            public struct ExampleService {
            public init(variantA: VariantA, variantB: VariantB, invariantA: InvariantA) {
            self.variantA = variantA
            self.variantB = variantB
            self.invariantA = invariantA
            }

                public init(variantA: VariantA, variantB: VariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                    invariantA = InvariantA()
                }
                let variantA: VariantA
                let variantB: VariantB
                let invariantA: InvariantA
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
                private let invariantAInstantiator: Instantiator<InvariantA>
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
                @Instantiated
                private let invariantAInstantiator: Instantiator<InvariantA>
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init(invariantAInstantiator: Instantiator<InvariantA>) {
            self.invariantAInstantiator = invariantAInstantiator
            }

                @Instantiated
                private let invariantAInstantiator: Instantiator<InvariantA>
            }
            """
        } expansion: {
            """
            public struct ExampleService {
            public init(invariantAInstantiator: Instantiator<InvariantA>) {
            self.invariantAInstantiator = invariantAInstantiator
            }
                private let invariantAInstantiator: Instantiator<InvariantA>
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
                private var invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
                @LazyInstantiated
                private var invariantA: InvariantA
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init(invariantAInstantiator: Instantiator<InvariantA>) {
            _invariantA = LazyInstantiated(invariantAInstantiator)
            }

                @LazyInstantiated
                private var invariantA: InvariantA
            }
            """
        } expansion: {
            """
            public struct ExampleService {
            public init(invariantAInstantiator: Instantiator<InvariantA>) {
            _invariantA = LazyInstantiated(invariantAInstantiator)
            }

                @LazyInstantiated
                private var invariantA: InvariantA
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
                private var invariantA: InvariantA
                @Instantiated
                let invariantAInstantiator: Instantiator<InvariantA>
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type must have `public` or `open` initializer comprising all injected parameters
                                            ✏️ Add required initializer
                @LazyInstantiated
                private var invariantA: InvariantA
                @Instantiated
                let invariantAInstantiator: Instantiator<InvariantA>
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            public init(invariantAInstantiator: Instantiator<InvariantA>) {
            _invariantA = LazyInstantiated(invariantAInstantiator)
            self.invariantAInstantiator = invariantAInstantiator
            }

                @LazyInstantiated
                private var invariantA: InvariantA
                @Instantiated
                let invariantAInstantiator: Instantiator<InvariantA>
            }
            """
        } expansion: {
            """
            public struct ExampleService {
            public init(invariantAInstantiator: Instantiator<InvariantA>) {
            _invariantA = LazyInstantiated(invariantAInstantiator)
            self.invariantAInstantiator = invariantAInstantiator
            }

                @LazyInstantiated
                private var invariantA: InvariantA
                let invariantAInstantiator: Instantiator<InvariantA>
            }
            """
        }
    }
}
#endif
