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

let testMacros: [String: Macro.Type] = [
    ConstructableVisitor.macroName: ConstructableMacro.self,
    Dependency.Source.constructedInvariant.rawValue: InjectableMacro.self,
    Dependency.Source.providedInvariant.rawValue: InjectableMacro.self,
    Dependency.Source.singletonInvariant.rawValue: InjectableMacro.self,
    Dependency.Source.propagatedVariant.rawValue: InjectableMacro.self,
]

final class MacroTests: XCTestCase {

    // MARK: XCTestCase

    override func invokeTest() {
        withMacroTesting(macros: testMacros) {
            super.invokeTest()
        }
    }

    // MARK: Expansion tests

    func test_constructableAndInjectableMacros_withNoInvariantsOrVariants() throws {
        assertMacroExpansion(
            """
            @Constructable
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

    func test_constructableAndInjectableMacros_withSingleInvariantAndNoVariants() throws {
        assertMacroExpansion(
            """
            @Constructable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Constructed
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

    func test_constructableAndInjectableMacros_withMultipleInvariantsAndNoVariants() throws {
        assertMacroExpansion(
            """
            @Constructable(fulfillingAdditionalTypes: [ExampleService.self])
            public struct DefaultExampleService: ExampleService {
                init(
                    invariantA: invariantA,
                    invariantB: invariantB,
                    invariantC: invariantC)
                {
                    self.invariantA = invariantA
                    self.invariantB = invariantB
                    self.invariantC = invariantC
                }

                @Constructed
                public let invariantA: InvariantA
                @Provided
                let invariantB: InvariantB
                @Singleton
                private let invariantC: InvariantC
            }
            """,
            expandedSource: """
            public struct DefaultExampleService: ExampleService {
                init(
                    invariantA: invariantA,
                    invariantB: invariantB,
                    invariantC: invariantC)
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

    func test_constructableAndInjectableMacros_withNoInvariantsAndSingleVariant() throws {
        assertMacroExpansion(
            """
            @Constructable
            public struct ExampleService {
                init(with variant: Variant) {
                    self.variant = variant
                }

                @Propagated
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

    func test_constructableAndInjectableMacros_withSingleInvariantAndVariant() throws {
        assertMacroExpansion(
            """
            @Constructable
            public struct ExampleService {
                init(with variant: Variant, invariant: Invariant) {
                    self.variant = variant
                    self.invariant = invariant
                }

                @Propagated
                public let variant: Variant
                @Constructed
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

    func test_constructableAndInjectableMacros_withMultipleInvariantsAndSingleVariant() throws {
        assertMacroExpansion(
            """
            @Constructable
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

                @Propagated
                public let variant: Variant
                @Constructed
                private let invariantA: invariantA
                @Provided
                private let invariantB: InvariantB
                @Singleton
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

    func test_constructableAndInjectableMacros_withNoInvariantsAndMultipleVariant() throws {
        assertMacroExpansion(
            """
            @Constructable
            public struct ExampleService {
                init(variantA: VariantA, variantB: VariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                }

                @Propagated
                let variantA: VariantA
                @Propagated
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

    func test_constructableAndInjectableMacros_withSingleInvariantAndMultipleVariants() throws {
        assertMacroExpansion(
            """
            @Constructable
            public struct ExampleService {
                init(variantA: VariantA, variantB: VariantB, invariantA: InvariantA) {
                    self.variantA = variantA
                    self.variantB = variantB
                    self.invariantA = invariantA
                }

                @Propagated
                let variantA: VariantA
                @Propagated
                let variantB: VariantB
                @Constructed
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

    func test_constructableAndInjectableMacros_withMultipleInvariantsAndMultipleVariants() throws {
        assertMacroExpansion(
            """
            @Constructable
            public struct ExampleService {
                init(variantA: VariantA, variantB: VariantB, invariantA: InvariantA, invariantB: InvariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                    self.invariantA = invariantA
                    self.invariantB = invariantB
                }

                @Propagated
                let variantA: VariantA
                @Propagated
                let variantB: VariantB
                @Constructed
                private let invariantA: InvariantA
                @Singleton
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

    func test_constructableMacro_throwsErrorWhenOnProtocol() {
        assertMacro {
            """
            @Constructable
            protocol ExampleService {}
            """
        } diagnostics: {
            """
            @Constructable
            ┬─────────────
            ╰─ 🛑 @Constructable must decorate a class, struct, or actor
            protocol ExampleService {}
            """
        }
    }

    func test_injectableMacro_throwsErrorWhenOnProtocol() {
        assertMacro {
            """
            @Constructed
            protocol ExampleService {}
            """
        } diagnostics: {
            """
            @Constructed
            ┬───────────
            ╰─ 🛑 This macro must decorate a instance variable
            protocol ExampleService {}
            """
        }
    }

    func test_constructableMacro_throwsErrorWhenInjectableMacroAttachedtoStaticProperty() {
        assertMacro {
            """
            @Constructable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Provided
                static let invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            @Constructable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Provided
                ┬────────
                ╰─ 🛑 This macro can not decorate `static` variables
                static let invariantA: InvariantA
            }
            """
        }
    }

    // MARK: FixIt tests

    func test_constructableMacro_addsFixitWhenMultipleInjectableMacrosOntopOfSingleProperty() {
        assertMacro {
            """
            @Constructable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Provided
                @Constructed
                let invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            @Constructable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Provided
                ╰─ 🛑 Dependency can have at most one of @Constructed, @Provided, @Singleton, or @Propagated attached macro
                   ✏️ Remove excessive attached macros
                @Constructed
                let invariantA: InvariantA
            }
            """
        } fixes: {
            """
            @Constructable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Provided
            }
            """ // fixes are super wrong here. We delete @Provided not the rest.
        }
    }

    func test_constructableAndInjectableMacros_addsFixitWhenInjectableParameterHasInitializer() {
        assertMacro {
            """
            @Constructable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Constructed
                let invariantA: InvariantA = .init()
            }
            """
        } diagnostics: {
            """
            @Constructable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Constructed
                ╰─ 🛑 Dependency must not have hand-written initializer
                   ✏️ Remove initializer
                let invariantA: InvariantA = .init()
            }
            """
        } fixes: {
            """
            @Constructable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Constructed
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

                public init(buildSafeDIDependencies: () -> (InvariantA )) {
                    let dependencies = buildSafeDIDependencies()
                    self.init(invariantA: dependencies)
                }
            }
            """
        }
    }

    func test_constructableMacro_addsFixitWhenInjectableTypeIsNotPublicOrOpen() {
        assertMacro {
            """
            @Constructable
            struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Constructed
                let invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            @Constructable
            ╰─ 🛑 @Constructable-decorated type must be `public` or `open`
               ✏️ Add `public` modifier
            struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Constructed
                let invariantA: InvariantA
            }
            """
        } fixes: {
            """
            @Constructable
            public 
            public ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Constructed
                let invariantA: InvariantA
            }
            """ // this fixes are wrong (we aren't deleting 'struct'), but also the whitespace is wrong in Xcode.
            // TODO: fix Xcode spacing of this replacement.
        } expansion: {
            """
            @Constructable
            public 
            public ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Constructed
                let invariantA: InvariantA
            }
            """
        }
    }

    func test_constructableAndInjectableMacros_addsFixitWhenInjectableParameterIsMutable() {
        assertMacro {
            """
            @Constructable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Constructed
                var invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            @Constructable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Constructed
                var invariantA: InvariantA
                ┬──
                ╰─ 🛑 Dependency can not be mutable
                   ✏️ Replace `var` with `let`
            }
            """
        } fixes: {
            """
            @Constructable
            public struct ExampleService {
                init(invariantA: InvariantA) {
                    self.invariantA = invariantA
                }

                @Constructed let  let invariantA: InvariantA
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

    func test_constructableMacro_addsFixitMissingRequiredInitializerWithoutAnyDependencies() {
        assertMacro {
            """
            @Constructable
            public struct ExampleService {
            }
            """
        } diagnostics: {
            """
            @Constructable
            public struct ExampleService {
                                         ╰─ 🛑 @Constructable-decorated type must have initializer for all injected parameters
                                            ✏️ Add required initializer
            }
            """
        } fixes: {
            """
            @Constructable
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

    func test_constructableAndInjectableMacros_addsFixitMissingRequiredInitializerWithDependencies() {
        assertMacro {
            """
            @Constructable
            public struct ExampleService {
                @Constructed
                let invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            @Constructable
            public struct ExampleService {
                                         ╰─ 🛑 @Constructable-decorated type must have initializer for all injected parameters
                                            ✏️ Add required initializer
                @Constructed
                let invariantA: InvariantA
            }
            """
        } fixes: {
            """
            @Constructable
            public struct ExampleService {
            init(invariantA: InvariantA) {
            self.invariantA = invariantA
            }

                @Constructed
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

    func test_constructableMacro_addsFixitMissingRequiredInitializerWhenDependencyMissingFromInit() {
        assertMacro {
            """
            @Constructable
            public struct ExampleService {
                init(variantA: VariantA, variantB: VariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                    invariantA = InvariantA()
                }

                @Propagated
                let variantA: VariantA
                @Propagated
                let variantB: VariantB
                @Provided
                let invariantA: InvariantA
            }
            """
        } diagnostics: {
            """
            @Constructable
            public struct ExampleService {
                                         ╰─ 🛑 @Constructable-decorated type must have initializer for all injected parameters
                                            ✏️ Add required initializer
                init(variantA: VariantA, variantB: VariantB) {
                    self.variantA = variantA
                    self.variantB = variantB
                    invariantA = InvariantA()
                }

                @Propagated
                let variantA: VariantA
                @Propagated
                let variantB: VariantB
                @Provided
                let invariantA: InvariantA
            }
            """
        } fixes: {
            """
            @Constructable
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

                @Propagated
                let variantA: VariantA
                @Propagated
                let variantB: VariantB
                @Provided
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

}
#endif
