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

    func test_generateSafeDIInitializer_throwsWhenInitializerIsNotPublicOrOpen() throws {
        let initializer = Initializer(
            isPublicOrOpen: false,
            arguments: []
        )

        XCTAssertThrowsError(
            try initializer.validate(fulfilling: [])
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .inaccessibleInitializer)
        }
    }

    func test_generateSafeDIInitializer_throwsWhenInitializerIsOptional() throws {
        let initializer = Initializer(
            isOptional: true,
            arguments: []
        )

        XCTAssertThrowsError(
            try initializer.validate(fulfilling: [])
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .optionalInitializer)
        }
    }

    func test_generateSafeDIInitializer_throwsWhenInitializerIsAsync() throws {
        let initializer = Initializer(
            isAsync: true,
            arguments: []
        )

        XCTAssertThrowsError(
            try initializer.validate(fulfilling: [])
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .asyncInitializer)
        }
    }

    func test_generateSafeDIInitializer_throwsWhenInitializerThrows() throws {
        let initializer = Initializer(
            doesThrow: true,
            arguments: []
        )

        XCTAssertThrowsError(
            try initializer.validate(fulfilling: [])
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .throwingInitializer)
        }
    }

    func test_generateSafeDIInitializer_throwsWhenInitializerHasGenericParameters() throws {
        let initializer = Initializer(
            hasGenericParameter: true,
            arguments: [
                .init(
                    innerLabel: "variant",
                    typeDescription: .simple(name: "Variant")
                )
            ]
        )

        XCTAssertThrowsError(
            try initializer.validate(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "variant",
                            typeDescription: .simple(name: "Variant")
                        ),
                        source: .forwarded
                    )
                ]
            )
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .genericParameterInInitializer)
        }
    }

    func test_generateSafeDIInitializer_throwsWhenInitializerHasGenericWhereClause() throws {
        let initializer = Initializer(
            hasGenericWhereClause: true,
            arguments: [
                .init(
                    innerLabel: "variant",
                    typeDescription: .simple(name: "Variant")
                )
            ]
        )

        XCTAssertThrowsError(
            try initializer.validate(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "variant",
                            typeDescription: .simple(name: "Variant")
                        ),
                        source: .forwarded
                    )
                ]
            )
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .whereClauseOnInitializer)
        }
    }

    func test_generateSafeDIInitializer_throwsWhenInitializerHasUnexpectedArgument() throws {
        let initializer = Initializer(
            arguments: [
                .init(
                    innerLabel: "variant",
                    typeDescription: .simple(name: "Variant")
                )
            ]
        )

        XCTAssertThrowsError(
            try initializer.validate(fulfilling: [])
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .unexpectedArgument("variant: Variant"))
        }
    }

    func test_generateSafeDIInitializer_throwsWhenInitializerIsMissingArgumentsAndDependenciesExist() throws {
        let initializer = Initializer(arguments: [])

        XCTAssertThrowsError(
            try initializer.validate(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "variant",
                            typeDescription: .simple(name: "Variant")
                        ),
                        source: .forwarded
                    )
                ]
            )
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .missingArguments(["variant: Variant"]))
        }
    }

    func test_generateSafeDIInitializer_throwsWhenInitializerIsMissingArgumentLabel() throws {
        let initializer = Initializer(
            arguments: [
                .init(
                    innerLabel: "someVariant",
                    typeDescription: .simple(name: "Variant")
                )
            ]
        )

        XCTAssertThrowsError(
            try initializer.validate(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "variant",
                            typeDescription: .simple(name: "Variant")
                        ),
                        source: .forwarded
                    )
                ]
            )
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .unexpectedArgument("someVariant: Variant"))
        }
    }

    func test_generateSafeDIInitializer_throwsWhenInitializerIsMissingArgumentType() throws {
        let initializer = Initializer(
            arguments: [
                .init(
                    innerLabel: "variant",
                    typeDescription: .simple(name: "NotThatVariant")
                )
            ]
        )

        XCTAssertThrowsError(
            try initializer.validate(
                fulfilling: [
                    .init(
                        property: .init(
                            label: "variant",
                            typeDescription: .simple(name: "Variant")
                        ),
                        source: .forwarded
                    )
                ]
            )
        ) { error in
            XCTAssertEqual(error as? Initializer.GenerationError, .unexpectedArgument("variant: NotThatVariant"))
        }
    }
}
