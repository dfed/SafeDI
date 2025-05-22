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

import Foundation
import SafeDICore
import Testing

@testable import SafeDITool

@Suite(.serialized)
final class SafeDIToolDOTGenerationTests {
    // MARK: Initialization

    init() throws {
        filesToDelete = [URL]()
    }

    deinit {
        for fileToDelete in filesToDelete {
            try! FileManager.default.removeItem(at: fileToDelete)
        }
    }

    // MARK: DOT Generation Tests

    @Test
    func run_successfullyGeneratesOutputFileWhenNoCodeInput() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2

            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenSingleRoot() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                import Foundation

                public protocol NetworkService {}

                @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                public final class DefaultNetworkService: NetworkService {
                    let urlSession: URLSession = .shared
                }
                """,
                """
                @Instantiable(isRoot: true)
                public final class RootViewController: UIViewController {
                    @Instantiated let networkService: NetworkService
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                RootViewController -- "networkService: NetworkService"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenMultipleRootsExist() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                import Foundation

                public protocol NetworkService {}

                @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                public final class DefaultNetworkService: NetworkService {
                    let urlSession: URLSession = .shared
                }
                """,
                """
                @Instantiable(isRoot: true)
                public struct Root1 {
                    @Instantiated let networkService: NetworkService
                }
                """,
                """
                @Instantiable(isRoot: true)
                public struct Root2 {
                    @Instantiated let networkService: NetworkService
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root1 -- "networkService: NetworkService"

                Root2 -- "networkService: NetworkService"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenRootHasMultipleLayers() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                public struct User {}
                """,
                """
                public protocol AuthService {
                    func login(username: String, password: String) async -> User
                }

                @Instantiable(fulfillingAdditionalTypes: [AuthService.self])
                public final class DefaultAuthService: AuthService {
                    public func login(username: String, password: String) async -> User {
                        User()
                    }

                    @Received let networkService: NetworkService                }
                """,
                """
                public protocol NetworkService {}

                @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                public final class DefaultNetworkService: NetworkService {
                    public init() {}
                }
                """,
                """
                import UIKit

                @Instantiable(isRoot: true)
                public final class RootViewController: UIViewController {
                    public init(authService: AuthService, networkService: NetworkService, loggedInViewControllerBuilder: ErasedInstantiator<User, UIViewController>) {
                        self.authService = authService
                        self.networkService = networkService
                        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
                        derivedValue = false
                        super.init(nibName: nil, bundle: nil)
                    }

                    @Instantiated let networkService: NetworkService

                    @Instantiated let authService: AuthService

                    @Instantiated(fulfilledByType: "LoggedInViewController") let loggedInViewControllerBuilder: ErasedInstantiator<User, UIViewController>

                    private let derivedValue: Bool

                    func login(username: String, password: String) {
                        Task { @MainActor in
                            let user = await authService.login(username: username, password: password)
                            let loggedInViewController = loggedInViewControllerBuilder.instantiate(user)
                            pushViewController(loggedInViewController)
                        }
                    }
                }
                """,
                """
                import UIKit

                @Instantiable
                public final class LoggedInViewController: UIViewController {
                    @Forwarded private let user: User

                    @Received let networkService: NetworkService                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                RootViewController -- "networkService: NetworkService"
                RootViewController -- "authService: AuthService"
                RootViewController -- "loggedInViewControllerBuilder: ErasedInstantiator<User, UIViewController>"
                "loggedInViewControllerBuilder: ErasedInstantiator<User, UIViewController>" -- "user: User"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenRootInstantiatesPropertiesThatUtilizesSingleForwardedPropertyInSubBuilders() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                public struct User {}
                """,
                """
                public protocol AuthService {
                    func login(username: String, password: String) async -> User
                }

                @Instantiable(fulfillingAdditionalTypes: [AuthService.self])
                public final class DefaultAuthService: AuthService {
                    public func login(username: String, password: String) async -> User {
                        User()
                    }

                    @Received let networkService: NetworkService                }
                """,
                """
                public protocol NetworkService {}

                @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                public final class DefaultNetworkService: NetworkService {
                    public init() {}
                }
                """,
                """
                import UIKit

                @Instantiable(isRoot: true)
                public final class RootViewController: UIViewController {
                    public init(authService: AuthService, networkService: NetworkService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
                        self.authService = authService
                        self.networkService = networkService
                        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
                        derivedValue = false
                        super.init(nibName: nil, bundle: nil)
                    }

                    @Instantiated let networkService: NetworkService

                    @Instantiated let authService: AuthService

                    @Instantiated let loggedInViewControllerBuilder: Instantiator<LoggedInViewController>

                    private let derivedValue: Bool

                    func login(username: String, password: String) {
                        Task { @MainActor in
                            let user = await authService.login(username: username, password: password)
                            let loggedInViewController = loggedInViewControllerBuilder.instantiate(user)
                            pushViewController(loggedInViewController)
                        }
                    }
                }
                """,
                """
                @Instantiable
                public final class UserService {
                    @Received let user: User
                }
                """,
                """
                import UIKit

                @Instantiable
                public final class LoggedInViewController: UIViewController {
                    @Forwarded private let user: User

                    @Received let networkService: NetworkService
                    @Instantiated let userService: UserService
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                RootViewController -- "networkService: NetworkService"
                RootViewController -- "authService: AuthService"
                RootViewController -- "loggedInViewControllerBuilder: Instantiator<LoggedInViewController>"
                "loggedInViewControllerBuilder: Instantiator<LoggedInViewController>" -- "userService: UserService"
                "loggedInViewControllerBuilder: Instantiator<LoggedInViewController>" -- "user: User"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenRootInstantiatesPropertiesThatUtilizeMultipleForwardedPropertiesInSubBuilders() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                public struct User {
                    public var id: String
                    public var name: String
                }
                """,
                """
                public protocol AuthService {
                    func login(username: String, password: String) async -> User
                }

                @Instantiable(fulfillingAdditionalTypes: [AuthService.self])
                public final class DefaultAuthService: AuthService {
                    public func login(username: String, password: String) async -> User {
                        User()
                    }

                    @Received let networkService: NetworkService                }
                """,
                """
                public protocol NetworkService {}

                @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                public final class DefaultNetworkService: NetworkService {
                    public init() {}
                }
                """,
                """
                import UIKit

                @Instantiable(isRoot: true)
                public final class RootViewController: UIViewController {
                    public init(authService: AuthService, networkService: NetworkService, loggedInViewControllerBuilder: ErasedInstantiator<(userID: String, userName: String), UIViewController>) {
                        self.authService = authService
                        self.networkService = networkService
                        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
                        derivedValue = false
                        super.init(nibName: nil, bundle: nil)
                    }

                    @Instantiated let networkService: NetworkService

                    @Instantiated let authService: AuthService

                    @Instantiated(fulfilledByType: "LoggedInViewController") let loggedInViewControllerBuilder: ErasedInstantiator<(userID: String, userName: String), UIViewController>

                    private let derivedValue: Bool

                    func login(username: String, password: String) {
                        Task { @MainActor in
                            let user = await authService.login(username: username, password: password)
                            let loggedInViewController = loggedInViewControllerBuilder.instantiate((userID: user.id, userName: user.name))
                            pushViewController(loggedInViewController)
                        }
                    }
                }
                """,
                """
                @Instantiable
                public final class UserService {
                    @Received let userName: String

                    @Received let userID: String
                }
                """,
                """
                import UIKit

                @Instantiable
                public final class LoggedInViewController: UIViewController {
                    @Forwarded private let userName: String

                    @Forwarded private let userID: String

                    @Received let networkService: NetworkService
                    @Instantiated let userService: UserService
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                RootViewController -- "networkService: NetworkService"
                RootViewController -- "authService: AuthService"
                RootViewController -- "loggedInViewControllerBuilder: ErasedInstantiator<(userID: String, userName: String), UIViewController>"
                "loggedInViewControllerBuilder: ErasedInstantiator<(userID: String, userName: String), UIViewController>" -- "userService: UserService"
                "loggedInViewControllerBuilder: ErasedInstantiator<(userID: String, userName: String), UIViewController>" -- "userID: String"
                "loggedInViewControllerBuilder: ErasedInstantiator<(userID: String, userName: String), UIViewController>" -- "userName: String"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenRootInstantiatesPropertiesThatUtilizeMultipleForwardedPropertiesAndDependencyInversionInSubBuilders() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                public struct User {
                    public var id: String
                    public var name: String
                }
                """,
                """
                public protocol AuthService {
                    func login(username: String, password: String) async -> User
                }

                @Instantiable(fulfillingAdditionalTypes: [AuthService.self])
                public final class DefaultAuthService: AuthService {
                    public func login(username: String, password: String) async -> User {
                        User()
                    }

                    @Received let networkService: NetworkService                }
                """,
                """
                public protocol NetworkService {}

                @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                public final class DefaultNetworkService: NetworkService {
                    public init() {}
                }
                """,
                """
                import UIKit

                @Instantiable(isRoot: true)
                public final class RootViewController: UIViewController {
                    public init(authService: AuthService, networkService: NetworkService, loggedInViewControllerBuilder: ErasedInstantiator<LoggedInViewController.ForwardedProperties, UIViewController>) {
                        self.authService = authService
                        self.networkService = networkService
                        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
                        derivedValue = false
                        super.init(nibName: nil, bundle: nil)
                    }

                    @Instantiated let networkService: NetworkService

                    @Instantiated let authService: AuthService

                    @Instantiated(fulfilledByType: "LoggedInViewController") let loggedInViewControllerBuilder: ErasedInstantiator<LoggedInViewController.ForwardedProperties, UIViewController>

                    private let derivedValue: Bool

                    func login(username: String, password: String) {
                        Task { @MainActor in
                            let user = await authService.login(username: username, password: password)
                            let loggedInViewController = loggedInViewControllerBuilder.instantiate((userID: user.id, userName: user.name))
                            pushViewController(loggedInViewController)
                        }
                    }
                }
                """,
                """
                @Instantiable
                public final class UserService {
                    @Received let userName: String

                    @Received let userID: String
                }
                """,
                """
                import UIKit

                @Instantiable
                public final class LoggedInViewController: UIViewController {
                    @Forwarded private let userName: String

                    @Forwarded private let userID: String

                    @Received let networkService: NetworkService
                    @Instantiated let userService: UserService
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                RootViewController -- "networkService: NetworkService"
                RootViewController -- "authService: AuthService"
                RootViewController -- "loggedInViewControllerBuilder: ErasedInstantiator<LoggedInViewController.ForwardedProperties, UIViewController>"
                "loggedInViewControllerBuilder: ErasedInstantiator<LoggedInViewController.ForwardedProperties, UIViewController>" -- "userService: UserService"
                "loggedInViewControllerBuilder: ErasedInstantiator<LoggedInViewController.ForwardedProperties, UIViewController>" -- "userID: String"
                "loggedInViewControllerBuilder: ErasedInstantiator<LoggedInViewController.ForwardedProperties, UIViewController>" -- "userName: String"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenRootInstantiatesPropertiesThatUtilizePropertiesNotDirectlyProvidedByParent() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                public struct User {}
                """,
                """
                public protocol AuthService {
                    func login(username: String, password: String) async -> User
                }

                @Instantiable(fulfillingAdditionalTypes: [AuthService.self])
                public final class DefaultAuthService: AuthService {
                    public func login(username: String, password: String) async -> User {
                        User()
                    }

                    @Received let networkService: NetworkService                }
                """,
                """
                public protocol NetworkService {}

                @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                public final class DefaultNetworkService: NetworkService {
                    public init() {}
                }
                """,
                """
                import UIKit

                @Instantiable(isRoot: true)
                public final class RootViewController: UIViewController {
                    public init(authService: AuthService, networkService: NetworkService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
                        self.authService = authService
                        self.networkService = networkService
                        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
                        derivedValue = false
                        super.init(nibName: nil, bundle: nil)
                    }

                    @Instantiated let authService: AuthService

                    @Instantiated let networkService: NetworkService

                    @Instantiated let loggedInViewControllerBuilder: Instantiator<LoggedInViewController>

                    private let derivedValue: Bool

                    func login(username: String, password: String) {
                        Task { @MainActor in
                            let user = await authService.login(username: username, password: password)
                            let loggedInViewController = loggedInViewControllerBuilder.instantiate(user)
                            pushViewController(loggedInViewController)
                        }
                    }
                }
                """,
                """
                @Instantiable
                public final class UserService {
                    @Received let user: User

                    @Received private let networkService: NetworkService
                }
                """,
                """
                import UIKit

                @Instantiable
                public final class LoggedInViewController: UIViewController {
                    @Forwarded private let user: User

                    @Instantiated let userService: UserService
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                RootViewController -- "networkService: NetworkService"
                RootViewController -- "authService: AuthService"
                RootViewController -- "loggedInViewControllerBuilder: Instantiator<LoggedInViewController>"
                "loggedInViewControllerBuilder: Instantiator<LoggedInViewController>" -- "userService: UserService"
                "loggedInViewControllerBuilder: Instantiator<LoggedInViewController>" -- "user: User"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenRootInstantiatesPropertiesWithMultipleLayersOfInstantiators() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                public struct User {}
                """,
                """
                public protocol AuthService {
                    func login(username: String, password: String) async -> User
                }

                @Instantiable(fulfillingAdditionalTypes: [AuthService.self])
                public final class DefaultAuthService: AuthService {
                    public func login(username: String, password: String) async -> User {
                        User()
                    }

                    @Received let networkService: NetworkService                }
                """,
                """
                public protocol NetworkService {}

                @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                public final class DefaultNetworkService: NetworkService {
                    public init() {}
                }
                """,
                """
                import UIKit

                @Instantiable(isRoot: true)
                public final class RootViewController: UIViewController {
                    public init(authService: AuthService, networkService: NetworkService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
                        self.authService = authService
                        self.networkService = networkService
                        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
                        derivedValue = false
                        super.init(nibName: nil, bundle: nil)
                    }

                    @Instantiated let authService: AuthService

                    @Instantiated let networkService: NetworkService

                    @Instantiated let loggedInViewControllerBuilder: Instantiator<LoggedInViewController>

                    private let derivedValue: Bool

                    func login(username: String, password: String) {
                        Task { @MainActor in
                            let user = await authService.login(username: username, password: password)
                            let loggedInViewController = loggedInViewControllerBuilder.instantiate(user)
                            pushViewController(loggedInViewController)
                        }
                    }
                }
                """,
                """
                @Instantiable
                public final class UserService {
                    @Received let user: User

                    @Received private let networkService: NetworkService
                }
                """,
                """
                import UIKit

                @Instantiable
                public final class LoggedInViewController: UIViewController {
                    @Forwarded private let user: User

                    @Instantiated let userServiceInstantiator: Instantiator<UserService>
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                RootViewController -- "networkService: NetworkService"
                RootViewController -- "authService: AuthService"
                RootViewController -- "loggedInViewControllerBuilder: Instantiator<LoggedInViewController>"
                "loggedInViewControllerBuilder: Instantiator<LoggedInViewController>" -- "userServiceInstantiator: Instantiator<UserService>"
                "loggedInViewControllerBuilder: Instantiator<LoggedInViewController>" -- "user: User"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenRootInstantiatesPropertiesWithMultipleTreesThatReceiveTheSameProperty() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                @Instantiable(isRoot: true)
                public final class Root {
                    @Instantiated let childA: ChildA
                    @Instantiated let childB: ChildB
                    @Instantiated let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class ChildA {
                    @Instantiated let grandchildAA: GrandchildAA
                    @Instantiated let grandchildAB: GrandchildAB
                }
                """,
                """
                @Instantiable
                public final class GrandchildAA {
                    @Received let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class GrandchildAB {
                    @Received let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class ChildB {
                    @Instantiated let grandchildBA: GrandchildBA
                    @Instantiated let grandchildBB: GrandchildBB
                }
                """,
                """
                @Instantiable
                public final class GrandchildBA {
                    @Received let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class GrandchildBB {
                    @Received let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class GreatGrandchild {}
                """,

            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root -- "greatGrandchild: GreatGrandchild"
                Root -- "childA: ChildA"
                Root -- "childB: ChildB"
                "childA: ChildA" -- "grandchildAA: GrandchildAA"
                "childA: ChildA" -- "grandchildAB: GrandchildAB"
                "childB: ChildB" -- "grandchildBA: GrandchildBA"
                "childB: ChildB" -- "grandchildBB: GrandchildBB"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenRootInstantiatesPropertiesWithMultipleTreesThatInstantiateTheSamePropertyInMiddleLevel() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                @Instantiable(isRoot: true)
                public final class Root {
                    @Instantiated let childA: ChildA
                    @Instantiated let childB: ChildB
                }
                """,
                """
                @Instantiable
                public final class ChildA {
                    @Instantiated let grandchildAA: GrandchildAA
                    @Instantiated let grandchildAB: GrandchildAB
                    @Instantiated let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class GrandchildAA {
                    @Received let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class GrandchildAB {
                    @Received let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class ChildB {
                    @Instantiated let grandchildBA: GrandchildBA
                    @Instantiated let grandchildBB: GrandchildBB
                    @Instantiated let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class GrandchildBA {
                    @Received let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class GrandchildBB {
                    @Received let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class GreatGrandchild {}
                """,

            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root -- "childA: ChildA"
                Root -- "childB: ChildB"
                "childA: ChildA" -- "greatGrandchild: GreatGrandchild"
                "childA: ChildA" -- "grandchildAA: GrandchildAA"
                "childA: ChildA" -- "grandchildAB: GrandchildAB"
                "childB: ChildB" -- "greatGrandchild: GreatGrandchild"
                "childB: ChildB" -- "grandchildBA: GrandchildBA"
                "childB: ChildB" -- "grandchildBB: GrandchildBB"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenRootInstantiatesPropertiesWithSingleTreeThatInstantiatesTheSamePropertyAtMultipleLevels() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                @Instantiable(isRoot: true)
                public final class Root {
                    @Instantiated let child: Child
                }
                """,
                """
                @Instantiable
                public final class Recreated {}
                """,
                """
                @Instantiable
                public final class Child {
                    @Instantiated let grandchild: Grandchild
                    @Instantiated let recreated: Recreated
                }
                """,
                """
                @Instantiable
                public final class Grandchild {
                    @Instantiated let greatGrandchild: GreatGrandchild
                    @Instantiated let recreated: Recreated
                }
                """,
                """
                @Instantiable
                public final class GreatGrandchild {
                    @Received let recreated: Recreated
                }
                """,

            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root -- "child: Child"
                "child: Child" -- "grandchild: Grandchild"
                "child: Child" -- "recreated: Recreated"
                "grandchild: Grandchild" -- "recreated: Recreated"
                "grandchild: Grandchild" -- "greatGrandchild: GreatGrandchild"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenRootInstantiatesPropertiesWithMultipleTreesThatInstantiateTheSamePropertyMultipleLayersDeep() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                @Instantiable(isRoot: true)
                public final class Root {
                    @Instantiated let childA: ChildA
                    @Instantiated let childB: ChildB
                }
                """,
                """
                @Instantiable
                public final class ChildA {
                    @Instantiated let grandchildAA: GrandchildAA
                    @Instantiated let grandchildAB: GrandchildAB
                }
                """,
                """
                @Instantiable
                public final class GrandchildAA {
                    @Instantiated let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class GrandchildAB {
                    @Instantiated let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class ChildB {
                    @Instantiated let grandchildBA: GrandchildBA
                    @Instantiated let grandchildBB: GrandchildBB
                }
                """,
                """
                @Instantiable
                public final class GrandchildBA {
                    @Instantiated let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class GrandchildBB {
                    @Instantiated let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class GreatGrandchild {}
                """,

            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root -- "childA: ChildA"
                Root -- "childB: ChildB"
                "childA: ChildA" -- "grandchildAA: GrandchildAA"
                "childA: ChildA" -- "grandchildAB: GrandchildAB"
                "grandchildAA: GrandchildAA" -- "greatGrandchild: GreatGrandchild"
                "grandchildAB: GrandchildAB" -- "greatGrandchild: GreatGrandchild"
                "childB: ChildB" -- "grandchildBA: GrandchildBA"
                "childB: ChildB" -- "grandchildBB: GrandchildBB"
                "grandchildBA: GrandchildBA" -- "greatGrandchild: GreatGrandchild"
                "grandchildBB: GrandchildBB" -- "greatGrandchild: GreatGrandchild"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenRootInstantiatesPropertiesWithMultipleTreesThatInstantiateTheSamePropertyAcrossMultipleModules() async throws {
        let greatGrandchildModuleOutput = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                @Instantiable
                public final class GreatGrandchild: Sendable {}
                """,
            ],
            buildDOTFileOutput: false,
            filesToDelete: &filesToDelete
        )

        let grandchildModuleOutput = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                import GreatGrandchildModule

                @Instantiable
                public final class GrandchildAA {
                    @Instantiated let greatGrandchild: GreatGrandchild
                }
                """,
                """
                import GreatGrandchildModule

                @Instantiable
                public final class GrandchildAB {
                    @Instantiated let greatGrandchild: GreatGrandchild
                }
                """,
                """
                import GreatGrandchildModule

                @Instantiable
                public final class GrandchildBA {
                    @Instantiated var greatGrandchildInstantiator: SendableInstantiator<GreatGrandchild>
                }
                """,
                """
                import GreatGrandchildModule

                @Instantiable
                public final class GrandchildBB {
                    @Instantiated greatGrandchildInstantiator: SendableInstantiator<GreatGrandchild>
                }
                """,
            ],
            dependentModuleInfoPaths: [greatGrandchildModuleOutput.moduleInfoOutputPath],
            buildDOTFileOutput: false,
            filesToDelete: &filesToDelete
        )

        let childModuleOutput = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                import class GrandchildModule.GrandchildAA
                import class GrandchildModule.GrandchildAB

                @MainActor
                @Instantiable
                public final class ChildA {
                    @Instantiated let grandchildAA: GrandchildAA
                    @Instantiated let grandchildAB: GrandchildAB
                }
                """,
                """
                @preconcurrency import GrandchildModule

                @Instantiable
                public final class ChildB {
                    @Instantiated let grandchildBA: GrandchildBA
                    @Instantiated let grandchildBB: GrandchildBB
                }
                """,
            ],
            dependentModuleInfoPaths: [
                greatGrandchildModuleOutput.moduleInfoOutputPath,
                grandchildModuleOutput.moduleInfoOutputPath,
            ],
            buildDOTFileOutput: false,
            filesToDelete: &filesToDelete
        )

        let topLevelModuleOutput = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                import ChildModule

                @MainActor
                @Instantiable(isRoot: true)
                public final class Root {
                    @Instantiated let childA: ChildA
                    @Instantiated let childB: ChildB
                }
                """,
            ],
            dependentModuleInfoPaths: [
                greatGrandchildModuleOutput.moduleInfoOutputPath,
                grandchildModuleOutput.moduleInfoOutputPath,
                childModuleOutput.moduleInfoOutputPath,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(topLevelModuleOutput.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root -- "childA: ChildA"
                Root -- "childB: ChildB"
                "childA: ChildA" -- "grandchildAA: GrandchildAA"
                "childA: ChildA" -- "grandchildAB: GrandchildAB"
                "grandchildAA: GrandchildAA" -- "greatGrandchild: GreatGrandchild"
                "grandchildAB: GrandchildAB" -- "greatGrandchild: GreatGrandchild"
                "childB: ChildB" -- "grandchildBA: GrandchildBA"
                "childB: ChildB" -- "grandchildBB: GrandchildBB"
                "grandchildBA: GrandchildBA" -- "greatGrandchildInstantiator: SendableInstantiator<GreatGrandchild>"
                "grandchildBB: GrandchildBB" -- "greatGrandchildInstantiator: SendableInstantiator<GreatGrandchild>"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenRootHasReceivedAliasOfInstantiable() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                @Instantiable(isRoot: true)
                public struct Root {
                    @Instantiated private let defaultUserService: DefaultUserService

                    @Received(fulfilledByDependencyNamed: "defaultUserService", ofType: DefaultUserService.self) private let userService: any UserService
                }
                """,
                """
                import Foundation

                public protocol UserService {
                    var userName: String? { get set }
                }

                @Instantiable(fulfillingAdditionalTypes: [UserService.self])
                public final class DefaultUserService: UserService {
                    public init() {}

                    public var userName: String?
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root -- "defaultUserService: DefaultUserService"
                Root -- "userService: any UserService <- defaultUserService: DefaultUserService"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenReceivedPropertyIsAliasedTwice() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                public struct User {}
                """,
                """
                public protocol NetworkService {}

                @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                public final class DefaultNetworkService: NetworkService {
                    public init() {}
                }
                """,
                """
                public protocol AuthService {
                    func login(username: String, password: String) async -> User
                }

                @Instantiable(fulfillingAdditionalTypes: [AuthService.self])
                public final class DefaultAuthService: AuthService {
                    public func login(username: String, password: String) async -> User {
                        User(username: username)
                    }

                    @Received let networkService: NetworkService
                    @Received(fulfilledByDependencyNamed: "networkService", ofType: NetworkService.self)
                    let renamedNetworkService: NetworkService

                    @Received(fulfilledByDependencyNamed: "renamedNetworkService", ofType: NetworkService.self)
                    let renamedAgainNetworkService: NetworkService
                }
                """,
                """
                import UIKit

                @Instantiable(isRoot: true)
                public final class RootViewController: UIViewController {
                    public init(authService: AuthService, networkService: NetworkService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
                        self.authService = authService
                        self.networkService = networkService
                        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
                        super.init(nibName: nil, bundle: nil)
                    }

                    @Instantiated let authService: AuthService

                    @Instantiated let networkService: NetworkService
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                RootViewController -- "networkService: NetworkService"
                RootViewController -- "authService: AuthService"
                "authService: AuthService" -- "renamedNetworkService: NetworkService <- networkService: NetworkService"
                "authService: AuthService" -- "renamedAgainNetworkService: NetworkService <- renamedNetworkService: NetworkService"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenFirstPropertyDependsOnLastPropertyAndMiddlePropertyHasNoDependencyEntanglementsWithEither() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                @Instantiable(isRoot: true)
                public final class Root {
                    @Instantiated let child: Child
                }
                """,
                """
                @Instantiable
                public final class Unrelated {}
                """,
                """
                @Instantiable
                public final class Child {
                    @Instantiated let grandchild: Grandchild
                    @Instantiated let unrelated: Unrelated @Instantiated let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class Grandchild {
                    @Received let greatGrandchild: GreatGrandchild
                }
                """,
                """
                @Instantiable
                public final class GreatGrandchild {}
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root -- "child: Child"
                "child: Child" -- "greatGrandchild: GreatGrandchild"
                "child: Child" -- "grandchild: Grandchild"
                "child: Child" -- "unrelated: Unrelated"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenRootHasLotsOfDependenciesThatDependOnOneAnother() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                @Instantiable(isRoot: true)
                public final class Root {
                    @Instantiated let a: A
                    @Instantiated let b: B
                    @Instantiated let c: C
                    @Instantiated let d: D
                    @Instantiated let e: E
                    @Instantiated let f: F
                    @Instantiated let g: G
                    @Instantiated let h: H
                    @Instantiated let i: I
                    @Instantiated let j: J
                    @Instantiated let k: K
                    @Instantiated let l: L
                    @Instantiated let m: M
                    @Instantiated let n: N
                    @Instantiated let o: O
                    @Instantiated let p: P
                    @Instantiated let q: Q
                    @Instantiated let r: R
                    @Instantiated let s: S
                    @Instantiated let t: T
                    @Instantiated let u: U
                    @Instantiated let v: V
                    @Instantiated let w: W
                    @Instantiated let x: X
                    @Instantiated let y: Y
                    @Instantiated let z: Z
                }
                """,
                """
                @Instantiable
                public final class A {
                    @Received let x: X
                }
                """,
                """
                @Instantiable
                public final class B {
                    @Received let a: A
                    @Received let d: D
                    @Received let t: T
                    @Received let o: O
                    @Received let y: Y
                    @Received let s: S
                }
                """,
                """
                @Instantiable
                public final class C {
                    @Received let u: U
                    @Received let n: N
                    @Received let y: Y
                }
                """,
                """
                @Instantiable
                public final class D {
                    @Received let o: O
                    @Received let g: G
                }
                """,
                """
                @Instantiable
                public final class E {
                    @Received let g: G
                }
                """,
                """
                @Instantiable
                public final class F {
                    @Received let a: A
                    @Received let x: X
                }
                """,
                """
                @Instantiable
                public final class G {}
                """,
                """
                @Instantiable
                public final class H {
                    @Received let u: U
                    @Received let g: G
                }
                """,
                """
                @Instantiable
                public final class I {
                    @Received let f: F
                }
                """,
                """
                @Instantiable
                public final class J {
                    @Received let a: A
                    @Received let g: G
                }
                """,
                """
                @Instantiable
                public final class K {
                    @Received let i: I
                    @Received let t: T
                }
                """,
                """
                @Instantiable
                public final class L {
                    @Received let o: O
                    @Received let v: V
                    @Received let e: E
                }
                """,
                """
                @Instantiable
                public final class M {
                    @Received let e: E
                }
                """,
                """
                @Instantiable
                public final class N {
                    @Received let o: O
                    @Received let p: P
                    @Received let e: E
                }
                """,
                """
                @Instantiable
                public final class O {
                    @Received let m: M
                    @Received let e: E
                    @Received let g: G
                    @Received let a: A
                }
                """,
                """
                @Instantiable
                public final class P {
                    @Received let i: I
                    @Received let x: X
                }
                """,
                """
                @Instantiable
                public final class Q {
                    @Received let u: U
                    @Received let t: T
                    @Received let e: E
                }
                """,
                """
                @Instantiable
                public final class R {
                    @Received let a: A
                    @Received let m: M
                    @Received let o: O
                    @Received let n: N
                    @Received let e: E
                }
                """,
                """
                @Instantiable
                public final class S {
                    @Received let a: A
                    @Received let t: T
                    @Received let o: O
                    @Received let r: R
                }
                """,
                """
                @Instantiable
                public final class T {
                    @Received let e: E
                    @Received let n: N
                }
                """,
                """
                @Instantiable
                public final class U {
                    @Received let p: P
                    @Received let d: D
                    @Received let o: O
                    @Received let w: W
                    @Received let n: N
                }
                """,
                """
                @Instantiable
                public final class V {
                    @Received let a: A
                    @Received let t: T
                    @Received let o: O
                    @Received let f: F
                    @Received let c: C
                    @Received let i: I
                    @Received let d: D
                }
                """,
                """
                @Instantiable
                public final class W {
                    @Received let a: A
                    @Received let x: X
                    @Received let o: O
                    @Received let n: N
                }
                """,
                """
                @Instantiable
                public final class X {}
                """,
                """
                @Instantiable
                public final class Y {
                    @Received let u: U
                    @Received let p: P
                }
                """,
                """
                @Instantiable
                public final class Z {
                    @Received let e: E
                    @Received let p: P
                    @Received let l: L
                    @Received let i: I
                    @Received let n: N
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root -- "x: X"
                Root -- "a: A"
                Root -- "g: G"
                Root -- "e: E"
                Root -- "m: M"
                Root -- "o: O"
                Root -- "d: D"
                Root -- "f: F"
                Root -- "i: I"
                Root -- "p: P"
                Root -- "n: N"
                Root -- "r: R"
                Root -- "t: T"
                Root -- "s: S"
                Root -- "w: W"
                Root -- "u: U"
                Root -- "y: Y"
                Root -- "b: B"
                Root -- "c: C"
                Root -- "h: H"
                Root -- "j: J"
                Root -- "k: K"
                Root -- "v: V"
                Root -- "l: L"
                Root -- "q: Q"
                Root -- "z: Z"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenLazyInstantiationCycleExists() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                @Instantiable(isRoot: true)
                public struct Root {
                    @Instantiated let aBuilder: Instantiator<A>
                }
                """,
                """
                @Instantiable
                public struct A {
                    @Instantiated let bBuilder: Instantiator<B>
                }
                """,
                """
                @Instantiable
                public struct B {
                    @Instantiated let cBuilder: Instantiator<C>
                }
                """,
                """
                @Instantiable
                public struct C {
                    @Instantiated let aBuilder: Instantiator<A>
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root -- "aBuilder: Instantiator<A>"
                "aBuilder: Instantiator<A>" -- "bBuilder: Instantiator<B>"
                "bBuilder: Instantiator<B>" -- "cBuilder: Instantiator<C>"
                "cBuilder: Instantiator<C>" -- "aBuilder: Instantiator<A>"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenPartiallyLazyInstantiationCycleExists() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                @Instantiable(isRoot: true)
                public struct Root {
                    @Instantiated let a: A
                }
                """,
                """
                @Instantiable
                public struct A {
                    @Instantiated let b: B
                }
                """,
                """
                @Instantiable
                public struct B {
                    @Instantiated let cBuilder: Instantiator<C>
                }
                """,
                """
                @Instantiable
                public struct C {
                    @Instantiated let a: A
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root -- "a: A"
                "a: A" -- "b: B"
                "b: B" -- "cBuilder: Instantiator<C>"
                "cBuilder: Instantiator<C>" -- "a: A"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenLazySelfInstantiationCycleExists() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                @Instantiable(isRoot: true)
                public struct Root {
                    @Instantiated let a: A
                }
                """,
                """
                @Instantiable
                public struct A {
                    @Instantiated let aBuilder: Instantiator<A>
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root -- "a: A"
                "a: A" -- "aBuilder: Instantiator<A>"
                "aBuilder: Instantiator<A>" -- "aBuilder: Instantiator<A>"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenLazySelfForwardingInstantiationCycleExists() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                @Instantiable(isRoot: true)
                public struct Root {
                    @Instantiated let aBuilder: Instantiator<A>
                }
                """,
                """
                @Instantiable
                public struct A {
                    @Instantiated let aBuilder: Instantiator<A>
                    @Forwarded let context: String
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root -- "aBuilder: Instantiator<A>"
                "aBuilder: Instantiator<A>" -- "aBuilder: Instantiator<A>"
                "aBuilder: Instantiator<A>" -- "context: String"
                "aBuilder: Instantiator<A>" -- "context: String"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenAGenericTypeIsAnExtendedInstantiableWithMultipleGenericReturnTypes() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                @Instantiable(isRoot: true)
                public struct Root {
                    @Instantiated let stringContainer: Container<String>
                    @Instantiated let intContainer: Container<Int>
                    @Instantiated let floatContainer: Container<Float>
                    @Instantiated let voidContainer: Container<Void>
                }
                """,
                """
                public struct Container<T> {
                    let value: T
                }
                @Instantiable
                extension Container: Instantiable {
                    public static func instantiate() -> Container<String> {
                        .init(value: "")
                    }
                    public static func instantiate() -> Container<Int> {
                        .init(value: 0)
                    }
                    public static func instantiate() -> Container<Float> {
                        .init(value: 0)
                    }
                    public static func instantiate() -> Container<Void> {
                        .init(value: ())
                    }
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root -- "stringContainer: Container<String>"
                Root -- "intContainer: Container<Int>"
                Root -- "floatContainer: Container<Float>"
                Root -- "voidContainer: Container<Void>"
            }
            """
        )
    }

    @Test
    func run_writesDOTTree_whenAGenericTypeIsAnExtendedInstantiableWithMultipleGenericFullyQualifiedReturnTypes() async throws {
        let output = try await executeSafeDIToolTest(
            swiftFileContent: [
                """
                @Instantiable(isRoot: true)
                public struct Root {
                    @Instantiated let stringContainer: MyModule.Container<String>
                    @Instantiated let intContainer: MyModule.Container<Int>
                    @Instantiated let floatContainer: MyModule.Container<Float>
                    @Instantiated let voidContainer: MyModule.Container<Void>
                }
                """,
                """
                public struct Container<T> {
                    let value: T
                }
                @Instantiable
                extension MyModule.Container: Instantiable {
                    public static func instantiate() -> MyModule.Container<String> {
                        .init(value: "")
                    }
                    public static func instantiate() -> MyModule.Container<Int> {
                        .init(value: 0)
                    }
                    public static func instantiate() -> MyModule.Container<Float> {
                        .init(value: 0)
                    }
                    public static func instantiate() -> MyModule.Container<Void> {
                        .init(value: ())
                    }
                }
                """,
            ],
            buildDOTFileOutput: true,
            filesToDelete: &filesToDelete
        )

        #expect(try #require(output.dotTree) == """
            graph SafeDI {
                ranksep=2
                Root -- "stringContainer: MyModule.Container<String>"
                Root -- "intContainer: MyModule.Container<Int>"
                Root -- "floatContainer: MyModule.Container<Float>"
                Root -- "voidContainer: MyModule.Container<Void>"
            }
            """
        )
    }

    // MARK: Private

    private var filesToDelete = [URL]()
}
