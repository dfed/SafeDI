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

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import SafeDIMacros

let testMacros: [String: Macro.Type] = [
    BuilderMacro.name: BuilderMacro.self,
    DependenciesMacro.name: DependenciesMacro.self,
    ConstructedMacro.name: ConstructedMacro.self,
    SingletonMacro.name: SingletonMacro.self,
]

final class MacroTests: XCTestCase {

    // MARK: Expansion tests

    func test_builderAndDependenciesMacros_withNoInvariantsOrVariants() throws {
        assertMacroExpansion(
            """
            @builder("myExample")
            public struct MyExampleBuilder {
                @dependencies
                public struct Dependencies {
                    func build() -> MyExample {
                        MyExample()
                    }
                }
            }
            """,
            expandedSource: """
            public struct MyExampleBuilder {
                public struct Dependencies {
                    func build() -> MyExample {
                        MyExample()
                    }

                    public init() {

                    }
                }

                // Inject this builder as a dependency by adding `let myExampleBuilder: MyExampleBuilder` to your @dependencies type
                public init(getDependencies: @escaping () -> Dependencies) {
                    self.getDependencies = getDependencies
                }

                // Inject this built product as a dependency by adding `let myExample: MyExample` to your @dependencies type
                public func build() -> MyExample {
                    getDependencies().build()
                }

                private let getDependencies: () -> Dependencies
            }
            """,
            macros: testMacros
        )
    }

    func test_builderAndDependenciesMacros_withSingleInvariantAndNoVariants() throws {
        assertMacroExpansion(
            """
            @builder("myExample")
            public struct MyExampleBuilder {
                @dependencies
                public struct Dependencies {
                    func build() -> MyExample {
                        MyExample(invariantA: invariantA)
                    }

                    @constructed
                    private let invariantA: InvariantA
                }
            }
            """,
            expandedSource: """
            public struct MyExampleBuilder {
                public struct Dependencies {
                    func build() -> MyExample {
                        MyExample(invariantA: invariantA)
                    }
                    private let invariantA: InvariantA

                    public init(invariantA: InvariantA) {
                        self.invariantA = invariantA
                    }
                }

                // Inject this builder as a dependency by adding `let myExampleBuilder: MyExampleBuilder` to your @dependencies type
                public init(getDependencies: @escaping () -> Dependencies) {
                    self.getDependencies = getDependencies
                }

                // Inject this built product as a dependency by adding `let myExample: MyExample` to your @dependencies type
                public func build() -> MyExample {
                    getDependencies().build()
                }

                private let getDependencies: () -> Dependencies
            }
            """,
            macros: testMacros
        )
    }

    func test_builderAndDependenciesMacros_withMultipleInvariantsAndNoVariants() throws {
        assertMacroExpansion(
            """
            @builder("myExample")
            public struct MyExampleBuilder {
                @dependencies
                public struct Dependencies {
                    func build() -> MyExample {
                        MyExample(
                            invariantA: invariantA,
                            invariantB: invariantB,
                            invariantC: invariantC
                        )
                    }

                    @constructed
                    private let invariantA: InvariantA
                    private let invariantB: InvariantB
                    @singleton
                    private let invariantC: InvariantC
                }
            }
            """,
            expandedSource: """
            public struct MyExampleBuilder {
                public struct Dependencies {
                    func build() -> MyExample {
                        MyExample(
                            invariantA: invariantA,
                            invariantB: invariantB,
                            invariantC: invariantC
                        )
                    }
                    private let invariantA: InvariantA
                    private let invariantB: InvariantB
                    private let invariantC: InvariantC

                    public init(invariantA: InvariantA, invariantB: InvariantB, invariantC: InvariantC) {
                        self.invariantA = invariantA
                        self.invariantB = invariantB
                        self.invariantC = invariantC
                    }
                }

                // Inject this builder as a dependency by adding `let myExampleBuilder: MyExampleBuilder` to your @dependencies type
                public init(getDependencies: @escaping () -> Dependencies) {
                    self.getDependencies = getDependencies
                }

                // Inject this built product as a dependency by adding `let myExample: MyExample` to your @dependencies type
                public func build() -> MyExample {
                    getDependencies().build()
                }

                private let getDependencies: () -> Dependencies
            }
            """,
            macros: testMacros
        )
    }

    func test_builderAndDependenciesMacros_withNoInvariantsAndSingleVariant() throws {
        assertMacroExpansion(
            """
            @builder("myExample")
            public struct MyExampleBuilder {
                @dependencies
                public struct Dependencies {
                    func build(variant: Variant) -> MyExample {
                        MyExample(variant: variant)
                    }
                }
            }
            """,
            expandedSource: """
            public struct MyExampleBuilder {
                public struct Dependencies {
                    func build(variant: Variant) -> MyExample {
                        MyExample(variant: variant)
                    }

                    public init() {

                    }
                }

                // Inject this builder as a dependency by adding `let myExampleBuilder: MyExampleBuilder` to your @dependencies type
                public init(getDependencies: @escaping (Variant) -> Dependencies) {
                    self.getDependencies = getDependencies
                }

                // Inject this built product as a dependency by adding `let myExample: MyExample` to your @dependencies type
                public func build(variant: Variant) -> MyExample {
                    getDependencies(variant).build(variant: variant)
                }

                private let getDependencies: (Variant) -> Dependencies
            }
            """,
            macros: testMacros
        )
    }

    func test_builderAndDependenciesMacros_withSingleInvariantAndVariant() throws {
        assertMacroExpansion(
            """
            @builder("myExample")
            public struct MyExampleBuilder {
                @dependencies
                public struct Dependencies {
                    func build(variant: Variant) -> MyExample {
                        MyExample(
                            invariantA: invariantA,
                            variant: variant
                        )
                    }

                    @constructed
                    private let invariantA: InvariantA
                }
            }
            """,
            expandedSource: """
            public struct MyExampleBuilder {
                public struct Dependencies {
                    func build(variant: Variant) -> MyExample {
                        MyExample(
                            invariantA: invariantA,
                            variant: variant
                        )
                    }
                    private let invariantA: InvariantA

                    public init(invariantA: InvariantA) {
                        self.invariantA = invariantA
                    }
                }

                // Inject this builder as a dependency by adding `let myExampleBuilder: MyExampleBuilder` to your @dependencies type
                public init(getDependencies: @escaping (Variant) -> Dependencies) {
                    self.getDependencies = getDependencies
                }

                // Inject this built product as a dependency by adding `let myExample: MyExample` to your @dependencies type
                public func build(variant: Variant) -> MyExample {
                    getDependencies(variant).build(variant: variant)
                }

                private let getDependencies: (Variant) -> Dependencies
            }
            """,
            macros: testMacros
        )
    }

    func test_builderAndDependenciesMacros_withMultipleInvariantsAndSingleVariant() throws {
        assertMacroExpansion(
            """
            @builder("myExample")
            public struct MyExampleBuilder {
                @dependencies
                public struct Dependencies {
                    func build(variant: Variant) -> MyExample {
                        MyExample(
                            invariantA: invariantA,
                            invariantB: invariantB,
                            invariantC: invariantC,
                            variant: variant
                        )
                    }

                    @constructed
                    private let invariantA: InvariantA
                    private let invariantB: InvariantB
                    @singleton
                    private let invariantC: InvariantC
                }
            }
            """,
            expandedSource: """
            public struct MyExampleBuilder {
                public struct Dependencies {
                    func build(variant: Variant) -> MyExample {
                        MyExample(
                            invariantA: invariantA,
                            invariantB: invariantB,
                            invariantC: invariantC,
                            variant: variant
                        )
                    }
                    private let invariantA: InvariantA
                    private let invariantB: InvariantB
                    private let invariantC: InvariantC

                    public init(invariantA: InvariantA, invariantB: InvariantB, invariantC: InvariantC) {
                        self.invariantA = invariantA
                        self.invariantB = invariantB
                        self.invariantC = invariantC
                    }
                }

                // Inject this builder as a dependency by adding `let myExampleBuilder: MyExampleBuilder` to your @dependencies type
                public init(getDependencies: @escaping (Variant) -> Dependencies) {
                    self.getDependencies = getDependencies
                }

                // Inject this built product as a dependency by adding `let myExample: MyExample` to your @dependencies type
                public func build(variant: Variant) -> MyExample {
                    getDependencies(variant).build(variant: variant)
                }

                private let getDependencies: (Variant) -> Dependencies
            }
            """,
            macros: testMacros
        )
    }

    func test_builderAndDependenciesMacros_withNoInvariantsAndMultipleVariant() throws {
        assertMacroExpansion(
            """
            @builder("myExample")
            public struct MyExampleBuilder {
                @dependencies
                public struct Dependencies {
                    func build(variantA: VariantA, variantB: VariantB) -> MyExample {
                        MyExample(variantA: variantA, variantB: VariantB)
                    }
                }
            }
            """,
            expandedSource: """
            public struct MyExampleBuilder {
                public struct Dependencies {
                    func build(variantA: VariantA, variantB: VariantB) -> MyExample {
                        MyExample(variantA: variantA, variantB: VariantB)
                    }

                    public init() {

                    }
                }

                // Inject this builder as a dependency by adding `let myExampleBuilder: MyExampleBuilder` to your @dependencies type
                public init(getDependencies: @escaping (VariantA, VariantB) -> Dependencies) {
                    self.getDependencies = getDependencies
                }

                // Inject this built product as a dependency by adding `let myExample: MyExample` to your @dependencies type
                public func build(variantA: VariantA, variantB: VariantB) -> MyExample {
                    getDependencies(variantA, variantB).build(variantA: variantA, variantB: variantB)
                }

                private let getDependencies: (VariantA, VariantB) -> Dependencies
            }
            """,
            macros: testMacros
        )
    }

    func test_builderAndDependenciesMacros_withSingleInvariantAndMultipleVariants() throws {
        assertMacroExpansion(
            """
            @builder("myExample")
            public struct MyExampleBuilder {
                @dependencies
                public struct Dependencies {
                    func build(variantA: VariantA, variantB: VariantB) -> MyExample {
                        MyExample(
                            invariantA: invariantA,
                            variantA: VariantA,
                            variantB: VariantB
                        )
                    }

                    @constructed
                    private let invariantA: InvariantA
                }
            }
            """,
            expandedSource: """
            public struct MyExampleBuilder {
                public struct Dependencies {
                    func build(variantA: VariantA, variantB: VariantB) -> MyExample {
                        MyExample(
                            invariantA: invariantA,
                            variantA: VariantA,
                            variantB: VariantB
                        )
                    }
                    private let invariantA: InvariantA

                    public init(invariantA: InvariantA) {
                        self.invariantA = invariantA
                    }
                }

                // Inject this builder as a dependency by adding `let myExampleBuilder: MyExampleBuilder` to your @dependencies type
                public init(getDependencies: @escaping (VariantA, VariantB) -> Dependencies) {
                    self.getDependencies = getDependencies
                }

                // Inject this built product as a dependency by adding `let myExample: MyExample` to your @dependencies type
                public func build(variantA: VariantA, variantB: VariantB) -> MyExample {
                    getDependencies(variantA, variantB).build(variantA: variantA, variantB: variantB)
                }

                private let getDependencies: (VariantA, VariantB) -> Dependencies
            }
            """,
            macros: testMacros
        )
    }

    func test_builderAndDependenciesMacros_withMultipleInvariantsAndMultipleVariants() throws {
        assertMacroExpansion(
            """
            @builder("myExample")
            public struct MyExampleBuilder {
                @dependencies
                public struct Dependencies {
                    func build(variantA: VariantA, variantB: VariantB) -> MyExample {
                        MyExample(
                            invariantA: invariantA,
                            invariantB: invariantB,
                            invariantC: invariantC,
                            variantA: variantA,
                            variantB: variantB
                        )
                    }

                    @constructed
                    private let invariantA: InvariantA
                    private let invariantB: InvariantB
                    @singleton
                    private let invariantC: InvariantC
                }
            }
            """,
            expandedSource: """
            public struct MyExampleBuilder {
                public struct Dependencies {
                    func build(variantA: VariantA, variantB: VariantB) -> MyExample {
                        MyExample(
                            invariantA: invariantA,
                            invariantB: invariantB,
                            invariantC: invariantC,
                            variantA: variantA,
                            variantB: variantB
                        )
                    }
                    private let invariantA: InvariantA
                    private let invariantB: InvariantB
                    private let invariantC: InvariantC

                    public init(invariantA: InvariantA, invariantB: InvariantB, invariantC: InvariantC) {
                        self.invariantA = invariantA
                        self.invariantB = invariantB
                        self.invariantC = invariantC
                    }
                }

                // Inject this builder as a dependency by adding `let myExampleBuilder: MyExampleBuilder` to your @dependencies type
                public init(getDependencies: @escaping (VariantA, VariantB) -> Dependencies) {
                    self.getDependencies = getDependencies
                }

                // Inject this built product as a dependency by adding `let myExample: MyExample` to your @dependencies type
                public func build(variantA: VariantA, variantB: VariantB) -> MyExample {
                    getDependencies(variantA, variantB).build(variantA: variantA, variantB: variantB)
                }

                private let getDependencies: (VariantA, VariantB) -> Dependencies
            }
            """,
            macros: testMacros
        )
    }
}
