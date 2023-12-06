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
        Dependency.Source.inherited.rawValue: InjectableMacro.self,
        Dependency.Source.forwarded.rawValue: InjectableMacro.self,
    ]

    // MARK: XCTestCase

    override func invokeTest() {
        withMacroTesting(macros: testMacros) {
            super.invokeTest()
        }
    }

    // MARK: Expansion tests

    func test_expansion_withNoInvariantsOrVariants() throws {
        assertMacroExpansion(
            """
            @Instantiable
            public class ExampleService {
                init() {}
            }
            """,
            expandedSource: """
            public class ExampleService {
                init() {}
            }
            """,
            macros: testMacros
        )
    }

    func test_expansion_withSingleInvariantAndNoVariants() throws {
        assertMacroExpansion(
            """
            @Instantiable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Instantiated
                private let invariantA: InvariantA
            }
            """,
            expandedSource: """
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }
                private let invariantA: InvariantA

                public init(buildSafeDIDependencies: () -> (InvariantA)) {
                    let dependencies = buildSafeDIDependencies()
                    self.init(invariantA: dependencies)
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_expansion_withInstantiableTypeInvariantAndNoVariants() throws {
        assertMacroExpansion(
            """
            @Instantiable
            public struct ExampleService {
                init(invariantAInstantiableType: InstantiableType<InvariantA>) {
                    self.invariantAInstantiableType = invariantAInstantiableType
                }

                @Instantiated
                private let invariantAInstantiableType: InstantiableType<InvariantA>
            }
            """,
            expandedSource: """
            public struct ExampleService {
                init(invariantAInstantiableType: InstantiableType<InvariantA>) {
                    self.invariantAInstantiableType = invariantAInstantiableType
                }
                private let invariantAInstantiableType: InstantiableType<InvariantA>

                public init(buildSafeDIDependencies: () -> (InstantiableType<InvariantA>)) {
                    let dependencies = buildSafeDIDependencies()
                    self.init(invariantAInstantiableType: dependencies)
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_expansion_withLazyInstantiatedInvariantAndNoVariants() throws {
        assertMacroExpansion(
            """
            @Instantiable
            public struct ExampleService {
                init(invariantAInstantiator: Instantiator<InvariantA>) {
                    _invariantA = LazyInstantiated(invariantAInstantiator)
                }

                @LazyInstantiated
                private var invariantA: InvariantA
            }
            """,
            expandedSource: """
            public struct ExampleService {
                init(invariantAInstantiator: Instantiator<InvariantA>) {
                    _invariantA = LazyInstantiated(invariantAInstantiator)
                }

                @LazyInstantiated
                private var invariantA: InvariantA

                public init(buildSafeDIDependencies: () -> (Instantiator<InvariantA>)) {
                    let dependencies = buildSafeDIDependencies()
                    self.init(invariantAInstantiator: dependencies)
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_expansion_withMultipleInvariantsAndNoVariants() throws {
        assertMacroExpansion(
            """
            @Instantiable(fulfillingAdditionalTypes: [ExampleService.self])
            public actor DefaultExampleService: ExampleService {
                init(
                    invariantA: InvariantA,
                    invariantB: InvariantB,
                    invariantC: InvariantC)
                {
                    self.invariantA = invariantA
                    self.invariantB = invariantB
                    self.invariantC = invariantC
                }

                @Instantiated
                public let invariantA: InvariantA
                @Inherited
                let invariantB: InvariantB
                @Instantiated
                private let invariantC: InvariantC
            }
            """,
            expandedSource: """
            public actor DefaultExampleService: ExampleService {
                init(
                    invariantA: InvariantA,
                    invariantB: InvariantB,
                    invariantC: InvariantC)
                {
                    self.invariantA = invariantA
                    self.invariantB = invariantB
                    self.invariantC = invariantC
                }
                public let invariantA: InvariantA
                let invariantB: InvariantB
                private let invariantC: InvariantC

                public init(buildSafeDIDependencies: () -> (invariantA: InvariantA, invariantB: InvariantB, invariantC: InvariantC)) {
                    let dependencies = buildSafeDIDependencies()
                    self.init(invariantA: dependencies.invariantA, invariantB: dependencies.invariantB, invariantC: dependencies.invariantC)
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_expansion_withNoInvariantsAndSingleVariant() throws {
        assertMacroExpansion(
            """
            @Instantiable
            public struct ExampleService {
                init(with variant: Variant) {
                    self.variant = variant
                }

                @Forwarded
                public let variant: Variant
            }
            """,
            expandedSource: """
            public struct ExampleService {
                init(with variant: Variant) {
                    self.variant = variant
                }
                public let variant: Variant

                public init(buildSafeDIDependencies: (Variant) -> (Variant), variant: Variant) {
                    let dependencies = buildSafeDIDependencies(variant)
                    self.init(with: dependencies)
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_expansion_withSingleInvariantAndVariant() throws {
        assertMacroExpansion(
            """
            @Instantiable
            public struct ExampleService {
                init(with variant: Variant, invariant: Invariant) {
                    self.variant = variant
                    self.invariant = invariant
                }

                @Forwarded
                public let variant: Variant
                @Instantiated
                private let invariant: Invariant
            }
            """,
            expandedSource: """
            public struct ExampleService {
                init(with variant: Variant, invariant: Invariant) {
                    self.variant = variant
                    self.invariant = invariant
                }
                public let variant: Variant
                private let invariant: Invariant

                public init(buildSafeDIDependencies: (Variant) -> (variant: Variant, invariant: Invariant), variant: Variant) {
                    let dependencies = buildSafeDIDependencies(variant)
                    self.init(with: dependencies.variant, invariant: dependencies.invariant)
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_expansion_withMultipleInvariantsAndSingleVariant() throws {
        assertMacroExpansion(
            """
            @Instantiable
            public struct ExampleService {
                init(
                    with variant: Variant,
                    invariantA: invariantA,
                    invariantB: InvariantB,
                    invariantC: InvariantC)
                {
                    self.variant = variant
                    self.invariantA = invariantA
                    self.invariantB = invariantB
                    self.invariantC = invariantC
                }

                @Forwarded
                public let variant: Variant
                @Instantiated
                private let invariantA: invariantA
                @Inherited
                private let invariantB: InvariantB
                @Instantiated
                private let invariantC: InvariantC
            }
            """,
            expandedSource: """
            public struct ExampleService {
                init(
                    with variant: Variant,
                    invariantA: invariantA,
                    invariantB: InvariantB,
                    invariantC: InvariantC)
                {
                    self.variant = variant
                    self.invariantA = invariantA
                    self.invariantB = invariantB
                    self.invariantC = invariantC
                }
                public let variant: Variant
                private let invariantA: invariantA
                private let invariantB: InvariantB
                private let invariantC: InvariantC

                public init(buildSafeDIDependencies: (Variant) -> (variant: Variant, invariantA: invariantA, invariantB: InvariantB, invariantC: InvariantC), variant: Variant) {
                    let dependencies = buildSafeDIDependencies(variant)
                    self.init(with: dependencies.variant, invariantA: dependencies.invariantA, invariantB: dependencies.invariantB, invariantC: dependencies.invariantC)
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_expansion_withNoInvariantsAndMultipleVariant() throws {
        assertMacroExpansion(
            """
            @Instantiable
            public struct ExampleService {
                init(variantA: VariantA, variantB: VariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                }

                @Forwarded
                let variantA: VariantA
                @Forwarded
                let variantB: VariantB
            }
            """,
            expandedSource: """
            public struct ExampleService {
                init(variantA: VariantA, variantB: VariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                }
                let variantA: VariantA
                let variantB: VariantB

                public init(buildSafeDIDependencies: (VariantA, VariantB) -> (variantA: VariantA, variantB: VariantB), variantA: VariantA, variantB: VariantB) {
                    let dependencies = buildSafeDIDependencies(variantA, variantB)
                    self.init(variantA: dependencies.variantA, variantB: dependencies.variantB)
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_expansion_withSingleInvariantAndMultipleVariants() throws {
        assertMacroExpansion(
            """
            @Instantiable
            public struct ExampleService {
                init(variantA: VariantA, variantB: VariantB, invariantA: InvariantA) {
                    self.variantA = variantA
                    self.variantB = variantB
                    self.invariantA = invariantA
                }

                @Forwarded
                let variantA: VariantA
                @Forwarded
                let variantB: VariantB
                @Instantiated
                private let invariantA: InvariantA
            }
            """,
            expandedSource: """
            public struct ExampleService {
                init(variantA: VariantA, variantB: VariantB, invariantA: InvariantA) {
                    self.variantA = variantA
                    self.variantB = variantB
                    self.invariantA = invariantA
                }
                let variantA: VariantA
                let variantB: VariantB
                private let invariantA: InvariantA

                public init(buildSafeDIDependencies: (VariantA, VariantB) -> (variantA: VariantA, variantB: VariantB, invariantA: InvariantA), variantA: VariantA, variantB: VariantB) {
                    let dependencies = buildSafeDIDependencies(variantA, variantB)
                    self.init(variantA: dependencies.variantA, variantB: dependencies.variantB, invariantA: dependencies.invariantA)
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_expansion_withMultipleInvariantsAndMultipleVariants() throws {
        assertMacroExpansion(
            """
            @Instantiable
            public struct ExampleService {
                init(variantA: VariantA, variantB: VariantB, invariantA: InvariantA, invariantB: InvariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                    self.invariantA = invariantA
                    self.invariantB = invariantB
                }

                @Forwarded
                let variantA: VariantA
                @Forwarded
                let variantB: VariantB
                @Instantiated
                private let invariantA: InvariantA
                @Instantiated
                public let invariantB: InvariantB
            }
            """,
            expandedSource: """
            public struct ExampleService {
                init(variantA: VariantA, variantB: VariantB, invariantA: InvariantA, invariantB: InvariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                    self.invariantA = invariantA
                    self.invariantB = invariantB
                }
                let variantA: VariantA
                let variantB: VariantB
                private let invariantA: InvariantA
                public let invariantB: InvariantB

                public init(buildSafeDIDependencies: (VariantA, VariantB) -> (variantA: VariantA, variantB: VariantB, invariantA: InvariantA, invariantB: InvariantB), variantA: VariantA, variantB: VariantB) {
                    let dependencies = buildSafeDIDependencies(variantA, variantB)
                    self.init(variantA: dependencies.variantA, variantB: dependencies.variantB, invariantA: dependencies.invariantA, invariantB: dependencies.invariantB)
                }
            }
            """,
            macros: testMacros
        )
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

                @Inherited
                @Instantiated
                let invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Inherited
                ╰─ 🛑 Dependency can have at most one of @Instantiated, @Inherited, or @Forwarded attached macro
                   ✏️ Remove excessive attached macros
                @Instantiated
                let invariantA: InvariantA
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Inherited
            }
            """ // fixes are super wrong here. We delete @Inherited not the rest.
        }
    }

    func test_fixit_addsFixitWhenInjectableParameterHasInitializer() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                init(invariantA: InvariantA) {
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
                init(invariantA: InvariantA) {
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
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Instantiated
                let invariantA: InvariantA 
            }
            """
        } expansion: {
            """
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }
                let invariantA: InvariantA 

                public init(buildSafeDIDependencies: () -> (InvariantA)) {
                    let dependencies = buildSafeDIDependencies()
                    self.init(invariantA: dependencies)
                }
            }
            """
        }
    }

    func test_fixit_addsFixitWhenInjectableTypeIsNotPublicOrOpen() {
        assertMacro {
            """
            @Instantiable
            struct ExampleService {
                init(invariantA: InvariantA) {
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
                init(invariantA: InvariantA) {
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
                init(invariantA: InvariantA) {
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
                init(invariantA: InvariantA) {
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
                                         ╰─ 🛑 @Instantiable-decorated type must have initializer for all injected parameters
                                            ✏️ Add required initializer
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            init() {}

            init() {}
            """ // this is seriously incorrect – it works in Xcode.
        } expansion: {
            """
            public struct ExampleService {
            init() {}

            init() {}
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
                                         ╰─ 🛑 @Instantiable-decorated type must have initializer for all injected parameters
                                            ✏️ Add required initializer
                @Instantiated
                let invariantA: InvariantA
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            init(invariantA: InvariantA) {
            self.invariantA = invariantA
            }

                @Instantiated
                let invariantA: InvariantA
            }
            """ // Whitespace is correct in Xcode, but not here.
        } expansion: {
            """
            public struct ExampleService {
            init(invariantA: InvariantA) {
            self.invariantA = invariantA
            }
                let invariantA: InvariantA

                public init(buildSafeDIDependencies: () -> (InvariantA)) {
                    let dependencies = buildSafeDIDependencies()
                    self.init(invariantA: dependencies)
                }
            }
            """
        }
    }

    func test_fixit_addsFixitMissingRequiredInitializerWhenDependencyMissingFromInit() {
        assertMacro {
            """
            @Instantiable
            public struct ExampleService {
                init(variantA: VariantA, variantB: VariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                    invariantA = InvariantA()
                }

                @Forwarded
                let variantA: VariantA
                @Forwarded
                let variantB: VariantB
                @Inherited
                let invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            @Instantiable
            public struct ExampleService {
                                         ╰─ 🛑 @Instantiable-decorated type must have initializer for all injected parameters
                                            ✏️ Add required initializer
                init(variantA: VariantA, variantB: VariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                    invariantA = InvariantA()
                }

                @Forwarded
                let variantA: VariantA
                @Forwarded
                let variantB: VariantB
                @Inherited
                let invariantA: InvariantA
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            init(variantA: VariantA, variantB: VariantB, invariantA: InvariantA) {
            self.variantA = variantA
            self.variantB = variantB
            self.invariantA = invariantA
            }

                init(variantA: VariantA, variantB: VariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                    invariantA = InvariantA()
                }

                @Forwarded
                let variantA: VariantA
                @Forwarded
                let variantB: VariantB
                @Inherited
                let invariantA: InvariantA
            }
            """
        } expansion: {
            """
            public struct ExampleService {
            init(variantA: VariantA, variantB: VariantB, invariantA: InvariantA) {
            self.variantA = variantA
            self.variantB = variantB
            self.invariantA = invariantA
            }

                init(variantA: VariantA, variantB: VariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                    invariantA = InvariantA()
                }
                let variantA: VariantA
                let variantB: VariantB
                let invariantA: InvariantA

                public init(buildSafeDIDependencies: (VariantA, VariantB) -> (variantA: VariantA, variantB: VariantB, invariantA: InvariantA), variantA: VariantA, variantB: VariantB) {
                    let dependencies = buildSafeDIDependencies(variantA, variantB)
                    self.init(variantA: dependencies.variantA, variantB: dependencies.variantB, invariantA: dependencies.invariantA)
                }
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
                                         ╰─ 🛑 @Instantiable-decorated type must have initializer for all injected parameters
                                            ✏️ Add required initializer
                @Instantiated
                private let invariantAInstantiator: Instantiator<InvariantA>
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            init(invariantAInstantiator: Instantiator<InvariantA>) {
            self.invariantAInstantiator = invariantAInstantiator
            }

                @Instantiated
                private let invariantAInstantiator: Instantiator<InvariantA>
            }
            """
        } expansion: {
            """
            public struct ExampleService {
            init(invariantAInstantiator: Instantiator<InvariantA>) {
            self.invariantAInstantiator = invariantAInstantiator
            }
                private let invariantAInstantiator: Instantiator<InvariantA>

                public init(buildSafeDIDependencies: () -> (Instantiator<InvariantA>)) {
                    let dependencies = buildSafeDIDependencies()
                    self.init(invariantAInstantiator: dependencies)
                }
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
                                         ╰─ 🛑 @Instantiable-decorated type must have initializer for all injected parameters
                                            ✏️ Add required initializer
                @LazyInstantiated
                private var invariantA: InvariantA
            }
            """
        } fixes: {
            """
            @Instantiable
            public struct ExampleService {
            init(invariantAInstantiator: Instantiator<InvariantA>) {
            _invariantA = LazyInstantiated(invariantAInstantiator)
            }

                @LazyInstantiated
                private var invariantA: InvariantA
            }
            """
        } expansion: {
            """
            public struct ExampleService {
            init(invariantAInstantiator: Instantiator<InvariantA>) {
            _invariantA = LazyInstantiated(invariantAInstantiator)
            }

                @LazyInstantiated
                private var invariantA: InvariantA

                public init(buildSafeDIDependencies: () -> (Instantiator<InvariantA>)) {
                    let dependencies = buildSafeDIDependencies()
                    self.init(invariantAInstantiator: dependencies)
                }
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
                                         ╰─ 🛑 @Instantiable-decorated type must have initializer for all injected parameters
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
            init(invariantAInstantiator: Instantiator<InvariantA>) {
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
            init(invariantAInstantiator: Instantiator<InvariantA>) {
            _invariantA = LazyInstantiated(invariantAInstantiator)
            self.invariantAInstantiator = invariantAInstantiator
            }

                @LazyInstantiated
                private var invariantA: InvariantA
                let invariantAInstantiator: Instantiator<InvariantA>

                public init(buildSafeDIDependencies: () -> (Instantiator<InvariantA>)) {
                    let dependencies = buildSafeDIDependencies()
                    self.init(invariantAInstantiator: dependencies)
                }
            }
            """
        }
    }
}
#endif
