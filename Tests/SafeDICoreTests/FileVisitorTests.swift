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

import SwiftSyntax
import SwiftParser
import XCTest

@testable import SafeDICore

final class FileVisitorTests: XCTestCase {

    func test_walk_findsTopLevelInstantiable() {
        let fileVisitor = FileVisitor()
        fileVisitor.walk(Parser.parse(source: """
        import UIKit

        @Instantiable
        public final class LoggedInViewController: UIViewController {

            init(user: User, networkService: NetworkService) {
                self.user = user
                self.networkService = networkService
            }

            @Forwarded
            private let user: User

            @Inherited
            let networkService: NetworkService
        }
        """))
        XCTAssertEqual(
            fileVisitor.instantiables,
            [
                Instantiable(
                    instantiableType: .simple(name: "LoggedInViewController"),
                    additionalInstantiableTypes: nil,
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
                            source: .inherited
                        )
                    ])
            ]
        )
        XCTAssertEqual(
            fileVisitor.disallowedInstantiableDecoratedTypeDescriptions,
            []
        )
    }

    func test_walk_findsMultipleTopLevelInstantiables() {
        let fileVisitor = FileVisitor()
        fileVisitor.walk(Parser.parse(source: """
        @Instantiable
        public final class LoggedInViewController: UIViewController {

            init(user: User, networkService: NetworkService) {
                self.user = user
                self.networkService = networkService
            }

            @Forwarded
            private let user: User

            @Inherited
            let networkService: NetworkService
        }

        @Instantiable
        struct SomeOtherInstantiable {}
        """))
        XCTAssertEqual(
            fileVisitor.instantiables,
            [
                Instantiable(
                    instantiableType: .simple(name: "LoggedInViewController"),
                    additionalInstantiableTypes: nil,
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
                            source: .inherited
                        )
                    ]),
                Instantiable(
                    instantiableType: .simple(name: "SomeOtherInstantiable"),
                    additionalInstantiableTypes: nil,
                    dependencies: []
                )
            ]
        )
        XCTAssertEqual(
            fileVisitor.disallowedInstantiableDecoratedTypeDescriptions,
            []
        )
    }

    func test_walk_errorsOnNestedInstantiable() {
        let fileVisitor = FileVisitor()
        fileVisitor.walk(Parser.parse(source: """
        @Instantiable(fulfillingAdditionalTypes: [SomeProtocol.self])
        public struct OuterLevel: SomeProtocol {
            @Instantiable
            public struct InnerLevel {}
        }
        """))
        XCTAssertEqual(
            fileVisitor.instantiables,
            [
                Instantiable(
                    instantiableType: .simple(name: "OuterLevel"),
                    additionalInstantiableTypes: [
                        .simple(name: "SomeProtocol")
                    ],
                    dependencies: []
                )
            ]
        )
        XCTAssertEqual(
            fileVisitor.disallowedInstantiableDecoratedTypeDescriptions,
            [
                .simple(name: "InnerLevel")
            ]
        )
    }

    func test_walk_errorsOnInstantiableNestedWithinEnum() {
        let fileVisitor = FileVisitor()
        fileVisitor.walk(Parser.parse(source: """
        public enum OuterLevel {
            @Instantiable
            public struct InnerLevel {}
        }
        """))
        XCTAssertEqual(
            fileVisitor.instantiables,
            []
        )
        XCTAssertEqual(
            fileVisitor.disallowedInstantiableDecoratedTypeDescriptions,
            [
                .simple(name: "InnerLevel")
            ]
        )
    }
}