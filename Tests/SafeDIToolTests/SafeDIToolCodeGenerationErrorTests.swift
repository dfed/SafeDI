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

import SafeDICore
import XCTest

@testable import SafeDITool

final class SafeDIToolCodeGenerationErrorTests: XCTestCase {
    // MARK: XCTestCase

    override func setUpWithError() throws {
        try super.setUpWithError()

        filesToDelete = [URL]()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        for fileToDelete in filesToDelete {
            try FileManager.default.removeItem(at: fileToDelete)
        }
        fileFinder = FileManager.default
    }

    #if !os(Linux) // Linux does not support multiple invokations of the same test.
        override func invokeTest() {
            // Stop test execution on the first failure so we don't get repeated failures per repeated test run.
            continueAfterFailure = false
            // Run each test five times to ensure ordering is consistent.
            for _ in 0..<5 {
                super.invokeTest()
            }
        }
    #endif

    // MARK: Error Tests

    func test_run_onCodeWithPropertyWithUnknownFulfilledType_throwsError() async {
        await assertThrowsError(
            """
            No `@Instantiable`-decorated type or extension found to fulfill `@Instantiated`-decorated property with type `DoesNotExist`
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {
                        @Instantiated(fulfilledByType: "DoesNotExist")
                        let networkService: NetworkService
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithUnfulfillableInstantiatedProperty_throwsError() async {
        await assertThrowsError(
            """
            No `@Instantiable`-decorated type or extension found to fulfill `@Instantiated`-decorated property with type `URLSession`
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    import Foundation

                    public protocol NetworkService {}

                    @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                    public final class DefaultNetworkService: NetworkService {
                        @Instantiated
                        let urlSession: URLSession // URLSession is not `@Instantiable`! This will fail!
                    }
                    """,
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {
                        @Instantiated
                        let networkService: NetworkService
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithUnfulfillableReceivedProperty_throwsError() async {
        await assertThrowsError(
            """
            @Received property `urlSession: URLSession` is not @Instantiated or @Forwarded in chain: RootViewController -> DefaultNetworkService
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    import Foundation

                    public protocol NetworkService {}

                    @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                    public final class DefaultNetworkService: NetworkService {
                        @Received
                        let urlSession: URLSession // URLSession is not `@Instantiable`! This will fail!
                    }
                    """,
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {
                        @Instantiated
                        let networkService: NetworkService
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithInstantiatedPropertyWithForwardedArgument_throwsError() async {
        await assertThrowsError(
            """
            Property `networkService: NetworkService` on RootViewController has at least one @Forwarded property. Property should instead be of type `Instantiator<DefaultNetworkService>`.
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    import Foundation

                    public protocol NetworkService {}

                    @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                    public final class DefaultNetworkService: NetworkService {
                        @Forwarded
                        let urlSession: URLSession
                    }
                    """,
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {
                        @Instantiated
                        let networkService: NetworkService
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithDiamondDependencyWhereAReceivedPropertyIsUnfulfillableOnOneBranch_throwsError() async {
        await assertThrowsError(
            """
            @Received property `blankie: Blankie` is not @Instantiated or @Forwarded in chain: Root -> ChildB -> Grandchild
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    @Instantiable
                    public final class Root {
                        @Instantiated
                        let childA: ChildA
                        @Instantiated
                        let childB: ChildB
                    }
                    """,
                    """
                    @Instantiable
                    public final class ChildA {
                        @Instantiated
                        let grandchild: Grandchild
                        @Instantiated
                        let blankie: Blankie
                    }
                    """,
                    """
                    @Instantiable
                    public final class ChildB {
                        @Instantiated
                        let grandchild: Grandchild
                    }
                    """,
                    """
                    @Instantiable
                    public final class Grandchild {
                        @Received
                        let blankie: Blankie
                    }
                    """,
                    """
                    @Instantiable
                    public final class Blankie {}
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithInstantiatedPropertyThatRefersToCurrentInstantiable_throwsError() async throws {
        await assertThrowsError(
            """
            Dependency cycle detected!
            AuthService -> AuthService
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    public struct User {}
                    """,
                    """
                    public protocol NetworkService {}

                    @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                    public final class DefaultNetworkService: NetworkService {}
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

                        @Instantiated
                        let networkService: NetworkService

                        @Instantiated
                        let authService: AuthService
                    }
                    """,
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {
                        public init(authService: AuthService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
                            self.authService = authService
                            self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
                            super.init(nibName: nil, bundle: nil)
                        }

                        @Instantiated
                        let authService: AuthService
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithReceivedPropertyThatRefersToCurrentInstantiable_throwsError() async throws {
        await assertThrowsError(
            """
            Dependency cycle detected!
            AuthService -> AuthService
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    public struct User {}
                    """,
                    """
                    public protocol NetworkService {}

                    @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                    public final class DefaultNetworkService: NetworkService {}
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

                        @Instantiated
                        let networkService: NetworkService

                        @Received
                        let authService: AuthService
                    }
                    """,
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {
                        public init(authService: AuthService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
                            self.authService = authService
                            self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
                            super.init(nibName: nil, bundle: nil)
                        }

                        @Instantiated
                        let authService: AuthService
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithUnfulfillableAliasedReceivedPropertyName_throwsError() async {
        await assertThrowsError(
            """
            @Received property `networkService2: NetworkService` is not @Instantiated or @Forwarded in chain: RootViewController -> DefaultAuthService
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    import Foundation

                    public protocol NetworkService {}

                    @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                    public final class DefaultNetworkService: NetworkService {}
                    """,
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {
                        @Instantiated
                        let networkService: NetworkService

                        @Instantiated
                        let authService: AuthService
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

                        @Received(
                            fulfilledByDependencyNamed: "networkService2",
                            ofType: NetworkService.self
                        )
                        let networking: NetworkService
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithUnfulfillableAliasedReceivedPropertyType_throwsError() async {
        await assertThrowsError(
            """
            @Received property `networkService: NetworkService2` is not @Instantiated or @Forwarded in chain: RootViewController -> DefaultAuthService
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    import Foundation

                    public protocol NetworkService {}

                    @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                    public final class DefaultNetworkService: NetworkService {}
                    """,
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {
                        @Instantiated
                        let networkService: NetworkService

                        @Instantiated
                        let authService: AuthService
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

                        @Received(
                            fulfilledByDependencyNamed: "networkService",
                            ofType: NetworkService2.self
                        )
                        let networking: NetworkService
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWhereAliasedReceivedPropertyRefersToCurrentInstantiable_throwsError() async throws {
        await assertThrowsError(
            """
            Dependency cycle detected!
            AuthService -> AuthService
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    public struct User {}
                    """,
                    """
                    public protocol NetworkService {}

                    @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                    public final class DefaultNetworkService: NetworkService {}
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

                        @Instantiated
                        let networkService: NetworkService

                        @Received(fulfilledByDependencyNamed: "authService", ofType: AuthService.self)
                        let renamedAuthService: AuthService
                    }
                    """,
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {
                        public init(authService: AuthService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
                            self.authService = authService
                            self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
                            super.init(nibName: nil, bundle: nil)
                        }

                        @Instantiated
                        let authService: AuthService
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithUnfulfillableReceivedPropertyOnExtendedInstantiatedType_throwsError() async {
        await assertThrowsError(
            """
            @Received property `urlSession: URLSession` is not @Instantiated or @Forwarded in chain: RootViewController -> URLSessionWrapper
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    import URLSessionWrapper

                    @Instantiable
                    extension URLSessionWrapper: Instantiable {
                        public func instantiate(urlSession: URLSession) -> URLSessionWrapper {
                            URLSessionWrapper(urlSession)
                        }
                    }
                    """,
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {
                        @Instantiated
                        let urlSessionWrapper: URLSessionWrapper
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithNestedInstantiable_throwsError() async {
        await assertThrowsError(
            """
            @Instantiable types must be top-level declarations. Found the following nested @Instantiable types: SplashViewController
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {
                        @Instantiable
                        public final class SplashViewController: UIViewController {}
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithMultipleNestedInstantiable_throwsError() async {
        await assertThrowsError(
            """
            @Instantiable types must be top-level declarations. Found the following nested @Instantiable types: AuthenticatedViewController, SplashViewController
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {
                        @Instantiable
                        public final class SplashViewController: UIViewController {}

                        @Instantiable
                        public final class AuthenticatedViewController: UIViewController {}
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithDuplicateInstantiable_throwsError() async {
        await assertThrowsError(
            """
            @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unqiue types. Found multiple types or extensions fulfilling `RootViewController`
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {}
                    """,
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {}
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithDuplicateInstantiableAndInstantiable_throwsError() async {
        await assertThrowsError(
            """
            @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unqiue types. Found multiple types or extensions fulfilling `RootViewController`
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {}
                    """,
                    """
                    import UIKit

                    @Instantiable
                    extension RootViewController: Instantiable {
                        public static func instantiate() -> RootViewController {
                            RootViewController()
                        }
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithDuplicateInstantiableViaExtension_throwsError() async {
        await assertThrowsError(
            """
            @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unqiue types. Found multiple types or extensions fulfilling `UserDefaults`
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    import Foundation

                    @Instantiable
                    extension UserDefaults: Instantiable {
                        public static func instantiate() -> UserDefaults {
                            .standard
                        }
                    }
                    """,
                    """
                    import Foundation

                    @Instantiable
                    extension UserDefaults: Instantiable {
                        public static func instantiate(suiteName: String) -> UserDefaults {
                            UserDefaults(suiteName: suiteName)
                        }
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithDuplicateInstantiableFulfillment_throwsError() async {
        await assertThrowsError(
            """
            @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unqiue types. Found multiple types or extensions fulfilling `UIViewController`
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    import UIKit

                    @Instantiable(fulfillingAdditionalTypes: [UIViewController.self])
                    public final class RootViewController: UIViewController {}
                    """,
                    """
                    import UIKit

                    @Instantiable(fulfillingAdditionalTypes: [UIViewController.self])
                    public final class SplashViewController: UIViewController {}
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithCircularPropertyDependenciesImmediatelyInitialized_throwsError() async {
        await assertThrowsError(
            """
            Dependency cycle detected!
            A -> B -> C -> A
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    @Instantiable
                    public final class Root {
                        @Instantiated
                        let a: A
                    }
                    """,
                    """
                    @Instantiable
                    public final class A {
                        @Instantiated
                        let b: B
                    }
                    """,
                    """
                    @Instantiable
                    public final class B {
                        @Instantiated
                        let c: C
                    }
                    """,
                    """
                    @Instantiable
                    public final class C {
                        @Instantiated
                        let a: A
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithCircularPropertyDependenciesImmediatelyInitializedAndReceived_throwsError() async {
        await assertThrowsError(
            """
            Dependency cycle detected!
            A -> B -> C -> A
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    @Instantiable
                    public final class Root {
                        @Instantiated let a: A
                    }
                    """,
                    """
                    @Instantiable
                    public final class A {
                        @Instantiated let b: B
                    }
                    """,
                    """
                    @Instantiable
                    public final class B {
                        @Instantiated let c: C
                    }
                    """,
                    """
                    @Instantiable
                    public final class C {
                        @Received let a: A
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithCircularPropertyDependenciesLazyInitializedAndReceived_throwsError() async throws {
        await assertThrowsError(
            """
            Dependency cycle detected! @Instantiated `aBuilder: Instantiator<A>` is @Received in tree created by @Instantiated `aBuilder: Instantiator<A>`. Declare @Received `aBuilder: Instantiator<A>` on `C` as @Instantiated to fix. Full cycle:
            Instantiator<A> -> Instantiator<B> -> Instantiator<C> -> Instantiator<A>
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    @Instantiable
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
                        @Received let aBuilder: Instantiator<A>
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithCircularPropertyDependenciesImmediatelyInitializedWithVaryingNames_throwsError() async {
        await assertThrowsError(
            """
            Dependency cycle detected!
            B -> C -> A -> B
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    @Instantiable
                    public struct Root {
                        @Instantiated
                        let a: A
                    }
                    """,
                    """
                    @Instantiable
                    public struct A {
                        @Instantiated
                        let b: B
                    }
                    """,
                    """
                    @Instantiable
                    public struct B {
                        @Instantiated
                        let c: C
                    }
                    """,
                    """
                    @Instantiable
                    public struct C {
                        @Instantiated
                        let a2: A
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithCircularReceivedDependencies_throwsError() async {
        await assertThrowsError(
            """
            Dependency cycle detected on Root!
            a: A -> b: B -> c: C -> a: A
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    @Instantiable
                    public struct Root {
                        @Instantiated
                        private let a: A
                        @Instantiated
                        private let b: B
                        @Instantiated
                        private let c: C
                    }
                    """,
                    """
                    @Instantiable
                    public struct A {
                        @Received
                        private let b: B
                    }
                    """,
                    """
                    @Instantiable
                    public struct B {
                        @Received
                        private let c: C
                    }
                    """,
                    """
                    @Instantiable
                    public struct C {
                        @Received
                        private let a: A
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithCircularReceivedRenamedDependencies_throwsError() async {
        await assertThrowsError(
            """
            Dependency cycle detected on A!
            b: B -> c: C -> renamedB: B -> b: B
            """
        ) {
            try await executeSafeDIToolTest(
                swiftFileContent: [
                    """
                    @Instantiable
                    public struct Root {
                        @Instantiated
                        private let a: A
                    }
                    """,
                    """
                    @Instantiable
                    public struct A {
                        @Instantiated
                        private let b: B
                        @Received(fulfilledByDependencyNamed: "b", ofType: B.self)
                        private let renamedB: B
                        @Instantiated
                        private let c: C
                    }
                    """,
                    """
                    @Instantiable
                    public struct B {
                        @Received
                        private let c: C
                    }
                    """,
                    """
                    @Instantiable
                    public struct C {
                        @Received
                        private let renamedB: B
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithIncorrectErasedInstantiatorFirstGeneric_whenInstantiableHasSingleForwardedProperty_throwsError() async throws {
        await assertThrowsError(
            """
            Property `loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>` on LoggedInViewController incorrectly configured. Property should instead be of type `ErasedInstantiator<LoggedInViewController.ForwardedProperties, UIViewController>`.
            """
        ) {
            try await executeSafeDIToolTest(
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

                        @Received
                        let networkService: NetworkService
                    }
                    """,
                    """
                    public protocol NetworkService {}

                    @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                    public final class DefaultNetworkService: NetworkService {}
                    """,
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {
                        public init(authService: AuthService, networkService: NetworkService, loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>) {
                            self.authService = authService
                            self.networkService = networkService
                            self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
                            derivedValue = false
                            super.init(nibName: nil, bundle: nil)
                        }

                        @Instantiated
                        let networkService: NetworkService

                        @Instantiated
                        let authService: AuthService

                        @Instantiated(fulfilledByType: "LoggedInViewController")
                        let loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>

                        private let derivedValue: Bool

                        func login(username: String, password: String) {
                            Task { @MainActor in
                                let loggedInViewController = loggedInViewControllerBuilder.instantiate(username)
                                pushViewController(loggedInViewController)
                            }
                        }
                    }
                    """,
                    """
                    import UIKit

                    @Instantiable
                    public final class LoggedInViewController: UIViewController {
                        @Forwarded
                        private let user: User

                        @Received
                        let networkService: NetworkService
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    func test_run_onCodeWithIncorrectErasedInstantiatorFirstGeneric_whenInstantiableHasMultipleForwardedProperty_throwsError() async throws {
        await assertThrowsError(
            """
            Property `loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>` on LoggedInViewController incorrectly configured. Property should instead be of type `ErasedInstantiator<LoggedInViewController.ForwardedProperties, UIViewController>`.
            """
        ) {
            try await executeSafeDIToolTest(
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

                        @Received
                        let networkService: NetworkService
                    }
                    """,
                    """
                    public protocol NetworkService {}

                    @Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
                    public final class DefaultNetworkService: NetworkService {}
                    """,
                    """
                    import UIKit

                    @Instantiable
                    public final class RootViewController: UIViewController {
                        public init(authService: AuthService, networkService: NetworkService, loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>) {
                            self.authService = authService
                            self.networkService = networkService
                            self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
                            derivedValue = false
                            super.init(nibName: nil, bundle: nil)
                        }

                        @Instantiated
                        let networkService: NetworkService

                        @Instantiated
                        let authService: AuthService

                        @Instantiated(fulfilledByType: "LoggedInViewController")
                        let loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>

                        private let derivedValue: Bool

                        func login(username: String, password: String) {
                            Task { @MainActor in
                                let loggedInViewController = loggedInViewControllerBuilder.instantiate(username)
                                pushViewController(loggedInViewController)
                            }
                        }
                    }
                    """,
                    """
                    import UIKit

                    @Instantiable
                    public final class LoggedInViewController: UIViewController {

                        @Forwarded
                        private let user: User

                        @Forwarded
                        private let userManager: UserManager

                        @Received
                        let networkService: NetworkService
                    }
                    """,
                ],
                buildDependencyTreeOutput: true,
                filesToDelete: &filesToDelete
            )
        }
    }

    // MARK: Argument handling error tests

    func test_include_throwsErrorWhenCanNotCreateEnumerator() async {
        final class FailingFileFinder: FileFinder {
            func enumerator(
                at _: URL,
                includingPropertiesForKeys _: [URLResourceKey]?,
                options _: FileManager.DirectoryEnumerationOptions,
                errorHandler _: ((URL, any Error) -> Bool)?
            ) -> FileManager.DirectoryEnumerator? {
                nil
            }
        }
        fileFinder = FailingFileFinder()

        var tool = SafeDITool()
        tool.swiftSourcesFilePath = nil
        tool.include = ["Fake"]
        tool.additionalImportedModules = []
        tool.moduleInfoOutput = nil
        tool.moduleInfoPaths = []
        tool.dependencyTreeOutput = nil
        await assertThrowsError("Could not create file enumerator for directory 'Fake'") {
            try await tool.run()
        }
    }

    func test_include_throwsErrorWhenNoSwiftSourcesFilePathAndNoInclude() async {
        var tool = SafeDITool()
        tool.swiftSourcesFilePath = nil
        tool.include = []
        tool.additionalImportedModules = []
        tool.moduleInfoOutput = nil
        tool.moduleInfoPaths = []
        tool.dependencyTreeOutput = nil
        await assertThrowsError("Must provide either 'swift-sources-file-path' or '--include'.") {
            try await tool.run()
        }
    }

    // MARK: Private

    private var filesToDelete = [URL]()
}
