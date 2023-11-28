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

import XCTest

@testable import SafeDICore

final class InitializerTests: XCTestCase {

    func test_generateSafeDIInitializer_withNoArguments() throws {
        let initializer = Initializer(
            isOptional: false,
            hasGenericParameter: false,
            hasGenericWhereClause: false,
            arguments: []
        )

        XCTAssertThrowsError(
            try initializer.generateSafeDIInitializer(
                fulfilling: [],
                typeIsClass: false,
                trailingNewline: true).description
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .noDependencies)
        }
    }

    func test_generateSafeDIInitializer_throwsWhenInitializerIsOptional() throws {
        let initializer = Initializer(
            isOptional: true,
            hasGenericParameter: false,
            hasGenericWhereClause: false,
            arguments: []
        )

        XCTAssertThrowsError(
            try initializer.generateSafeDIInitializer(
                fulfilling: [],
                typeIsClass: false,
                trailingNewline: true).description
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .optionalInitializer)
        }
    }

    func test_generateSafeDIInitializer_throwsWhenInitializerHasGenericParameters() throws {
        let initializer = Initializer(
            isOptional: false,
            hasGenericParameter: true,
            hasGenericWhereClause: false,
            arguments: [
                .init(
                    innerLabel: "variant",
                    type: "Variant"
                )
            ]
        )

        XCTAssertThrowsError(
            try initializer.generateSafeDIInitializer(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "variant",
                            type: "Variant"
                        ),
                        source: .propagatedVariant
                    )
                ],
                typeIsClass: false,
                trailingNewline: true).description
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .genericParameterInInitializer)
        }
    }

    func test_generateSafeDIInitializer_throwsWhenInitializerHasGenericWhereClause() throws {
        let initializer = Initializer(
            isOptional: false,
            hasGenericParameter: false,
            hasGenericWhereClause: true,
            arguments: [
                .init(
                    innerLabel: "variant",
                    type: "Variant"
                )
            ]
        )

        XCTAssertThrowsError(
            try initializer.generateSafeDIInitializer(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "variant",
                            type: "Variant"
                        ),
                        source: .propagatedVariant
                    )
                ],
                typeIsClass: false,
                trailingNewline: true).description
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .whereClauseOnInitializer)
        }
    }

    func test_generateSafeDIInitializer_throwsWhenInitializerHasUnexpectedArgument() throws {
        let initializer = Initializer(
            isOptional: false,
            hasGenericParameter: false,
            hasGenericWhereClause: false,
            arguments: [
                .init(
                    innerLabel: "variant",
                    type: "Variant"
                )
            ]
        )

        XCTAssertThrowsError(
            try initializer.generateSafeDIInitializer(
                fulfilling: [],
                typeIsClass: false,
                trailingNewline: true).description
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .tooManyArguments(labels: ["variant"]))
        }
    }

    func test_generateSafeDIInitializer_throwsWhenInitializerIsMissingArgument() throws {
        let initializer = Initializer(
            isOptional: false,
            hasGenericParameter: false,
            hasGenericWhereClause: false,
            arguments: []
        )

        XCTAssertThrowsError(
            try initializer.generateSafeDIInitializer(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "variant",
                            type: "Variant"
                        ),
                        source: .propagatedVariant
                    )
                ],
                typeIsClass: false,
                trailingNewline: true).description
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .missingArguments(labels: ["variant"]))
        }
    }

    func test_generateSafeDIInitializer_withSingleVariantWithoutOuterLabel() throws {
        let initializer = Initializer(
            isOptional: false,
            hasGenericParameter: false,
            hasGenericWhereClause: false,
            arguments: [
                .init(
                    innerLabel: "variant",
                    type: "Variant"
                )
            ]
        )

        XCTAssertEqual(
            try initializer.generateSafeDIInitializer(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "variant",
                            type: "Variant"
                        ),
                        source: .propagatedVariant
                    )
                ],
                typeIsClass: false,
                trailingNewline: true).description,
            """
            public init(buildSafeDIDependencies: (Variant) -> (Variant), variant: Variant) {
                let dependencies = buildSafeDIDependencies(variant)
                self.init(variant: dependencies)
            }
            """
        )
    }

    func test_generateSafeDIInitializer_withSingleVariantWithOuterLabel() throws {
        let initializer = Initializer(
            isOptional: false,
            hasGenericParameter: false,
            hasGenericWhereClause: false,
            arguments: [
                .init(
                    outerLabel: "with",
                    innerLabel: "variant",
                    type: "Variant"
                )
            ]
        )

        XCTAssertEqual(
            try initializer.generateSafeDIInitializer(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "variant",
                            type: "Variant"
                        ),
                        source: .propagatedVariant
                    )
                ],
                typeIsClass: false,
                trailingNewline: true).description,
            """
            public init(buildSafeDIDependencies: (Variant) -> (Variant), variant: Variant) {
                let dependencies = buildSafeDIDependencies(variant)
                self.init(with: dependencies)
            }
            """
        )
    }

    func test_generateSafeDIInitializer_withMultipleVariants() throws {
        let initializer = Initializer(
            isOptional: false,
            hasGenericParameter: false,
            hasGenericWhereClause: false,
            arguments: [
                .init(
                    outerLabel: "with",
                    innerLabel: "variantA",
                    type: "VariantA"
                ),
                .init(
                    innerLabel: "variantB",
                    type: "VariantB"
                ),
                .init(
                    innerLabel: "variantC",
                    type: "VariantC"
                )
            ]
        )

        XCTAssertEqual(
            try initializer.generateSafeDIInitializer(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "variantA",
                            type: "VariantA"
                        ),
                        source: .propagatedVariant),
                    .init(
                        property: .init(
                            label: "variantB",
                            type: "VariantB"
                        ),
                        source: .propagatedVariant
                    ),
                    .init(
                        property: .init(
                            label: "variantC",
                            type: "VariantC"
                        ),
                        source: .propagatedVariant
                    )
                ],
                typeIsClass: false,
                trailingNewline: true).description,
            """
            public init(buildSafeDIDependencies: (VariantA, VariantB, VariantC) -> (variantA: VariantA, variantB: VariantB, variantC: VariantC), variantA: VariantA, variantB: VariantB, variantC: VariantC) {
                let dependencies = buildSafeDIDependencies(variantA, variantB, variantC)
                self.init(with: dependencies.variantA, variantB: dependencies.variantB, variantC: dependencies.variantC)
            }
            """
        )
    }

    func test_generateSafeDIInitializer_withSingleInvariantWithoutOuterLabel() throws {
        let initializer = Initializer(
            isOptional: false,
            hasGenericParameter: false,
            hasGenericWhereClause: false,
            arguments: [
                .init(
                    innerLabel: "invariant",
                    type: "Invariant"
                )
            ]
        )

        XCTAssertEqual(
            try initializer.generateSafeDIInitializer(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "invariant",
                            type: "Invariant"
                        ),
                        source: .providedInvariant
                    )
                ],
                typeIsClass: false,
                trailingNewline: true).description,
            """
            public init(buildSafeDIDependencies: () -> (Invariant)) {
                let dependencies = buildSafeDIDependencies()
                self.init(invariant: dependencies)
            }
            """
        )
    }

    func test_generateSafeDIInitializer_withSingleInvariantWithOuterLabel() throws {
        let initializer = Initializer(
            isOptional: false,
            hasGenericParameter: false,
            hasGenericWhereClause: false,
            arguments: [
                .init(
                    outerLabel: "with",
                    innerLabel: "invariant",
                    type: "Invariant"
                )
            ]
        )

        XCTAssertEqual(
            try initializer.generateSafeDIInitializer(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "invariant",
                            type: "Invariant"
                        ),
                        source: .providedInvariant
                    )
                ],
                typeIsClass: false,
                trailingNewline: true).description,
            """
            public init(buildSafeDIDependencies: () -> (Invariant)) {
                let dependencies = buildSafeDIDependencies()
                self.init(with: dependencies)
            }
            """
        )
    }

    func test_generateSafeDIInitializer_withMultipleInvariants() throws {
        let initializer = Initializer(
            isOptional: false,
            hasGenericParameter: false,
            hasGenericWhereClause: false,
            arguments: [
                .init(
                    innerLabel: "invariantA",
                    type: "InvariantA"
                ),
                .init(
                    outerLabel: "with",
                    innerLabel: "invariantB",
                    type: "InvariantB"
                ),
                .init(
                    innerLabel: "invariantC",
                    type: "InvariantC"
                )
            ]
        )

        XCTAssertEqual(
            try initializer.generateSafeDIInitializer(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "invariantA",
                            type: "InvariantA"
                        ),
                        source: .providedInvariant),
                    .init(
                        property: .init(
                            label: "invariantB",
                            type: "InvariantB"
                        ),
                        source: .constructedInvariant
                    ),
                    .init(
                        property: .init(
                            label: "invariantC",
                            type: "InvariantC"
                        ),
                        source: .singletonInvariant
                    )
                ],
                typeIsClass: false,
                trailingNewline: true).description,
            """
            public init(buildSafeDIDependencies: () -> (invariantA: InvariantA, invariantB: InvariantB, invariantC: InvariantC)) {
                let dependencies = buildSafeDIDependencies()
                self.init(invariantA: dependencies.invariantA, with: dependencies.invariantB, invariantC: dependencies.invariantC)
            }
            """
        )
    }

    func test_generateSafeDIInitializer_withSingleVariantAndInvariant() throws {
        let initializer = Initializer(
            isOptional: false,
            hasGenericParameter: false,
            hasGenericWhereClause: false,
            arguments: [
                .init(
                    innerLabel: "variant",
                    type: "Variant"
                ),
                .init(
                    innerLabel: "invariant",
                    type: "Invariant"
                )
            ]
        )

        XCTAssertEqual(
            try initializer.generateSafeDIInitializer(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "variant",
                            type: "Variant"
                        ),
                        source: .propagatedVariant
                    ),
                    .init(
                        property: .init(
                            label: "invariant",
                            type: "Invariant"
                        ),
                        source: .constructedInvariant
                    )
                ],
                typeIsClass: false,
                trailingNewline: true).description,
            """
            public init(buildSafeDIDependencies: (Variant) -> (variant: Variant, invariant: Invariant), variant: Variant) {
                let dependencies = buildSafeDIDependencies(variant)
                self.init(variant: dependencies.variant, invariant: dependencies.invariant)
            }
            """
        )
    }

    func test_generateSafeDIInitializer_withMultileVariantsAndInvariants() throws {
        let initializer = Initializer(
            isOptional: false,
            hasGenericParameter: false,
            hasGenericWhereClause: false,
            arguments: [
                .init(
                    innerLabel: "invariantA",
                    type: "InvariantA"
                ),
                .init(
                    innerLabel: "variantA",
                    type: "VariantA"
                ),
                .init(
                    innerLabel: "invariantB",
                    type: "InvariantB"
                ),
                .init(
                    innerLabel: "variantB",
                    type: "VariantB"
                )
            ]
        )

        XCTAssertEqual(
            try initializer.generateSafeDIInitializer(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "variantA",
                            type: "VariantA"
                        ),
                        source: .propagatedVariant
                    ),
                    .init(
                        property: .init(
                            label: "variantB",
                            type: "VariantB"
                        ),
                        source: .propagatedVariant
                    ),
                    .init(
                        property: .init(
                            label: "invariantA",
                            type: "InvariantA"
                        ),
                        source: .constructedInvariant
                    ),
                    .init(
                        property: .init(
                            label: "invariantB",
                            type: "InvariantB"
                        ),
                        source: .constructedInvariant
                    )
                ],
                typeIsClass: false,
                trailingNewline: true).description,
            """
            public init(buildSafeDIDependencies: (VariantA, VariantB) -> (variantA: VariantA, variantB: VariantB, invariantA: InvariantA, invariantB: InvariantB), variantA: VariantA, variantB: VariantB) {
                let dependencies = buildSafeDIDependencies(variantA, variantB)
                self.init(invariantA: dependencies.invariantA, variantA: dependencies.variantA, invariantB: dependencies.invariantB, variantB: dependencies.variantB)
            }
            """
        )
    }

    func test_generateSafeDIInitializer_onClassWithMultileVariantsAndInvariants() throws {
        let initializer = Initializer(
            isOptional: false,
            hasGenericParameter: false,
            hasGenericWhereClause: false,
            arguments: [
                .init(
                    innerLabel: "invariantA",
                    type: "InvariantA"
                ),
                .init(
                    innerLabel: "variantA",
                    type: "VariantA"
                ),
                .init(
                    innerLabel: "invariantB",
                    type: "InvariantB"
                ),
                .init(
                    innerLabel: "variantB",
                    type: "VariantB"
                )
            ]
        )

        XCTAssertEqual(
            try initializer.generateSafeDIInitializer(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "variantA",
                            type: "VariantA"
                        ),
                        source: .propagatedVariant
                    ),
                    .init(
                        property: .init(
                            label: "variantB",
                            type: "VariantB"
                        ),
                        source: .propagatedVariant
                    ),
                    .init(
                        property: .init(
                            label: "invariantA",
                            type: "InvariantA"
                        ),
                        source: .constructedInvariant
                    ),
                    .init(
                        property: .init(
                            label: "invariantB",
                            type: "InvariantB"
                        ),
                        source: .constructedInvariant
                    )
                ],
                typeIsClass: true,
                trailingNewline: true).description,
            """
            public convenience init(buildSafeDIDependencies: (VariantA, VariantB) -> (variantA: VariantA, variantB: VariantB, invariantA: InvariantA, invariantB: InvariantB), variantA: VariantA, variantB: VariantB) {
                let dependencies = buildSafeDIDependencies(variantA, variantB)
                self.init(invariantA: dependencies.invariantA, variantA: dependencies.variantA, invariantB: dependencies.invariantB, variantB: dependencies.variantB)
            }
            """
        )
    }

}
