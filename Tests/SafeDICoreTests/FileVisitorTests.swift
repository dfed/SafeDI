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

import SwiftParser
import SwiftSyntax
import XCTest

@testable import SafeDICore

final class FileVisitorTests: XCTestCase {
    func test_walk_findsInstantiable() {
        let fileVisitor = FileVisitor()
        fileVisitor.walk(Parser.parse(source: """
        import UIKit

        @Instantiable
        public final class LoggedInViewController: UIViewController {
            public init(user: User, networkService: NetworkService) {
                fatalError("SafeDI doesn't inspect the initializer body")
            }

            @Forwarded
            private let user: User

            @Received
            let networkService: NetworkService
        }
        """))
        XCTAssertEqual(
            fileVisitor.instantiables,
            [
                Instantiable(
                    instantiableType: .simple(name: "LoggedInViewController"),
                    isRoot: false,
                    initializer: Initializer(
                        arguments: [
                            .init(
                                innerLabel: "user",
                                typeDescription: .simple(name: "User"),
                                hasDefaultValue: false
                            ),
                            .init(
                                innerLabel: "networkService",
                                typeDescription: .simple(name: "NetworkService"),
                                hasDefaultValue: false
                            ),
                        ]
                    ),
                    additionalInstantiables: nil,
                    dependencies: [
                        Dependency(
                            property: Property(
                                label: "user",
                                typeDescription: .simple(name: "User")
                            ),
                            source: .forwarded
                        ),
                        Dependency(
                            property: Property(
                                label: "networkService",
                                typeDescription: .simple(name: "NetworkService")
                            ),
                            source: .received
                        ),
                    ],
                    declarationType: .classType
                ),
            ]
        )
    }

    func test_walk_findsMultipleInstantiables() {
        let fileVisitor = FileVisitor()
        fileVisitor.walk(Parser.parse(source: """
        @Instantiable
        public final class LoggedInViewController: UIViewController {
            public init(user: User, networkService: NetworkService) {
                fatalError("SafeDI doesn't inspect the initializer body")
            }

            @Forwarded
            private let user: User

            @Received
            let networkService: NetworkService
        }

        @Instantiable
        public struct SomeOtherInstantiable {
            public init() {}
        }
        """))
        XCTAssertEqual(
            fileVisitor.instantiables,
            [
                Instantiable(
                    instantiableType: .simple(name: "LoggedInViewController"),
                    isRoot: false,
                    initializer: Initializer(
                        arguments: [
                            .init(
                                innerLabel: "user",
                                typeDescription: .simple(name: "User"),
                                hasDefaultValue: false
                            ),
                            .init(
                                innerLabel: "networkService",
                                typeDescription: .simple(name: "NetworkService"),
                                hasDefaultValue: false
                            ),
                        ]
                    ),
                    additionalInstantiables: nil,
                    dependencies: [
                        Dependency(
                            property: Property(
                                label: "user",
                                typeDescription: .simple(name: "User")
                            ),
                            source: .forwarded
                        ),
                        Dependency(
                            property: Property(
                                label: "networkService",
                                typeDescription: .simple(name: "NetworkService")
                            ),
                            source: .received
                        ),
                    ],
                    declarationType: .classType
                ),
                Instantiable(
                    instantiableType: .simple(name: "SomeOtherInstantiable"),
                    isRoot: false,
                    initializer: Initializer(arguments: []),
                    additionalInstantiables: nil,
                    dependencies: [],
                    declarationType: .structType
                ),
            ]
        )
    }

    func test_walk_findsInstantiableNestedInOuterInstantiableConcreteDeclaration() {
        let fileVisitor = FileVisitor()
        fileVisitor.walk(Parser.parse(source: """
        @Instantiable(fulfillingAdditionalTypes: [SomeProtocol.self])
        public struct OuterLevel: SomeProtocol {
            public init() {}

            @Instantiable
            public struct InnerLevel {
                public init() {}
            }
        }
        """))
        XCTAssertEqual(
            fileVisitor.instantiables,
            [
                Instantiable(
                    instantiableType: .simple(name: "OuterLevel"),
                    isRoot: false,
                    initializer: Initializer(arguments: []),
                    additionalInstantiables: [
                        .simple(name: "SomeProtocol"),
                    ],
                    dependencies: [],
                    declarationType: .structType
                ),
                Instantiable(
                    instantiableType: .nested(name: "InnerLevel", parentType: .simple(name: "OuterLevel")),
                    isRoot: false,
                    initializer: Initializer(arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .structType
                ),
            ]
        )
    }

    func test_walk_findsInstantiableNestedInOuterExtendedInstantiable() {
        let fileVisitor = FileVisitor()
        fileVisitor.walk(Parser.parse(source: """
        extension OuterLevel {
            public static func instantiate() -> OuterLevel { fatalError() }

            @Instantiable
            public struct InnerLevel {
                public init() {}
            }
        }
        """))
        XCTAssertEqual(
            fileVisitor.instantiables,
            [
                Instantiable(
                    instantiableType: .simple(name: "OuterLevel"),
                    isRoot: false,
                    initializer: Initializer(arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .extensionType
                ),
                Instantiable(
                    instantiableType: .nested(name: "InnerLevel", parentType: .simple(name: "OuterLevel")),
                    isRoot: false,
                    initializer: Initializer(arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .structType
                ),
            ]
        )
    }

    func test_walk_findsInstantiablesNestedInOuterExtendedInstantiable() {
        let fileVisitor = FileVisitor()
        fileVisitor.walk(Parser.parse(source: """
        extension OuterLevel {
            public static func instantiate() -> OuterLevel { fatalError() }

            @Instantiable
            public actor InnerLevel1 {
                public init() {}
            }
            @Instantiable
            public class InnerLevel2 {
                public init() {}
            }
            @Instantiable
            public struct InnerLevel3 {
                public init() {}
            }
            public struct InnerLevel4 {
                public init() {}
            }
        }
        """))
        XCTAssertEqual(
            fileVisitor.instantiables,
            [
                Instantiable(
                    instantiableType: .simple(name: "OuterLevel"),
                    isRoot: false,
                    initializer: Initializer(arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .extensionType
                ),
                Instantiable(
                    instantiableType: .nested(name: "InnerLevel1", parentType: .simple(name: "OuterLevel")),
                    isRoot: false,
                    initializer: Initializer(arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .actorType
                ),
                Instantiable(
                    instantiableType: .nested(name: "InnerLevel2", parentType: .simple(name: "OuterLevel")),
                    isRoot: false,
                    initializer: Initializer(arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .classType
                ),
                Instantiable(
                    instantiableType: .nested(name: "InnerLevel3", parentType: .simple(name: "OuterLevel")),
                    isRoot: false,
                    initializer: Initializer(arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .structType
                ),
            ]
        )
    }

    func test_walk_findsInstantiableNestedWithinEnum() {
        let fileVisitor = FileVisitor()
        fileVisitor.walk(Parser.parse(source: """
        public enum OuterLevel {
            @Instantiable
            public struct InnerLevel {
                public init() {}
            }
        }
        """))
        XCTAssertEqual(
            fileVisitor.instantiables,
            [
                Instantiable(
                    instantiableType: .nested(name: "InnerLevel", parentType: .simple(name: "OuterLevel")),
                    isRoot: false,
                    initializer: Initializer(arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .structType
                ),
            ]
        )
    }

    func test_walk_findsDeeplyNestedInstantiables() {
        let fileVisitor = FileVisitor()
        fileVisitor.walk(Parser.parse(source: """
        public enum Nested {
            @Instantiable
            public struct Nested {
                public init() {}

                @Instantiable
                public actor Nested {
                    public init() {}

                    @Instantiable
                    public final class Nested {
                        public init() {}

                        @Instantiable
                        public actor Nested {
                            public init() {}

                            @Instantiable
                            public final class Nested {
                                public init() {}

                                @Instantiable
                                public struct Nested {
                                    public init() {}

                                    @Instantiable
                                    public final class Nested {
                                        public init() {}

                                        @Instantiable
                                        public actor Nested {
                                            public init() {}

                                            @Instantiable
                                            public actor Nested {
                                                public init() {}

                                                @Instantiable
                                                public struct Nested {
                                                    public init() {}

                                                    @Instantiable
                                                    public struct Nested {
                                                        public init() {}

                                                        @Instantiable
                                                        public final class Nested {
                                                            public init() {}

                                                            @Instantiable
                                                            public final class Nested {
                                                                public init() {}

                                                                @Instantiable
                                                                public final class Nested {
                                                                    public init() {}

                                                                    @Instantiable
                                                                    public final class Nested {
                                                                        public init() {}

                                                                        @Instantiable
                                                                        public final class Nested {
                                                                            public init() {}

                                                                            @Instantiable
                                                                            public final class Nested {
                                                                                public init() {}

                                                                                @Instantiable
                                                                                public final class Nested {
                                                                                    public init() {}

                                                                                    @Instantiable
                                                                                    public final class Nested {
                                                                                        public init() {}

                                                                                        @Instantiable
                                                                                        public actor Nested {
                                                                                            public init() {}
                                                                                        }
                                                                                    }
                                                                                }
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        """))
        XCTAssertEqual(
            fileVisitor.instantiables,
            [
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .simple(name: "Nested")),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .structType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .actorType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .classType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .actorType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .classType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .structType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .classType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .actorType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .actorType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .structType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .structType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .classType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .classType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .classType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .classType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .classType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .classType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))))))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .classType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))))))))),
                    isRoot: false,
                    initializer: Initializer(isPublicOrOpen: true, isOptional: false, isAsync: false, doesThrow: false, hasGenericParameter: false, hasGenericWhereClause: false, arguments: []),
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .classType
                ),
                Instantiable(
                    instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))))))))))),
                    isRoot: false,
                    initializer: nil,
                    additionalInstantiables: [],
                    dependencies: [],
                    declarationType: .actorType
                ),
            ]
        )
    }
}
