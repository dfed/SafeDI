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

struct SafeDIToolCodeGenerationErrorTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Error Tests

	@Test
	mutating func run_onCodeWithPropertyWithUnknownFulfilledType_throwsError() async {
		await assertThrowsError(
			"""
			No `@Instantiable`-decorated type or extension found to fulfill `@Instantiated`-decorated property with type `DoesNotExist`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable(isRoot: true)
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

	@Test
	mutating func run_onCodeWithPropertyWithUnknownTypeWithDotSuffixOfFulfillableType_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `value: NestedType` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Instantiator<Child> -> Grandchild

			Did you mean one of the following available properties?
			\t`value: Grandchild.NestedType`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root {
					    @Instantiated let childBuilder: Instantiator<Child>
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child {
					    @Forwarded let value: Grandchild.NestedType
					    @Instantiated let grandchild: Grandchild
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Grandchild {
					    public struct NestedType {}
					    @Received let value: NestedType
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithPropertyWithUnknownTypeWithDotPrefixOfFulfillableType_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `value: Root.NestedType` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Instantiator<Child> -> Grandchild

			Did you mean one of the following available properties?
			\t`value: NestedType`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root {
					    @Instantiated let childBuilder: Instantiator<Child>
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child {
					    public struct NestedType {}
					    @Forwarded let value: NestedType
					    @Instantiated let grandchild: Grandchild
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Grandchild {
					    @Received let value: Root.NestedType
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithMultipleInstantiateMethodsForTheSameTypeWithSameParameters_throwsError() async {
		await assertThrowsError(
			"""
			@Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unqiue types. Found multiple types or extensions fulfilling `Container<Int>`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					extension Container: Instantiable {}
					""",
					"""
					@Instantiable(conformsElsewhere: true)
					extension Array {
					    public static func instantiate() -> Container<Int> {
					        .init(0)
					    }
					}
					""",
					"""
					@Instantiable(conformsElsewhere: true)
					extension Array {
					    public static func instantiate() -> Container<Int> {
					        .init(0)
					    }
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithMultipleInstantiateMethodsForTheSameTypeWithDifferentParameters_throwsError() async {
		await assertThrowsError(
			"""
			@Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unqiue types. Found multiple types or extensions fulfilling `Container<Int>`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					extension Container: Instantiable {}
					""",
					"""
					@Instantiable(conformsElsewhere: true)
					extension Array {
					    public static func instantiate() -> Container<Int> {
					        .init(0)
					    }
					}
					""",
					"""
					@Instantiable(conformsElsewhere: true)
					extension Array {
					    public static func instantiate(intValue: Int) -> Container<Int> {
					        .init(intValue)
					    }
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithUnfulfillableInstantiatedProperty_throwsError() async {
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
					    @Instantiated let urlSession: URLSession // URLSession is not `@Instantiable`! This will fail!
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController {
					    @Instantiated let networkService: NetworkService
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithUnfulfillableReceivedProperty_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `urlSession: URLSession` is not @Instantiated or @Forwarded in chain:
			\tRootViewController -> DefaultNetworkService
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import Foundation

					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService {
					    @Received let urlSession: URLSession // URLSession is not `@Instantiable`! This will fail!
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController {
					    @Instantiated let networkService: NetworkService
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithUnfulfillableInstantiatedPropertyDueToUnexpectedAny_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `erasedType: any ErasedType` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			Did you mean one of the following available properties?
			\t`erasedType: ErasedType`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root {
					    @Instantiated(fulfilledByType: "SomeErasedType") let erasedType: ErasedType
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					public protocol ErasedType {}

					@Instantiable
					public final class SomeErasedType: ErasedType {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child {
					    @Received let erasedType: any ErasedType
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithUnfulfillableInstantiatedPropertyDueToDroppedAny_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `erasedType: ErasedType` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			Did you mean one of the following available properties?
			\t`erasedType: any ErasedType`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root {
					    @Instantiated(fulfilledByType: "SomeErasedType") let erasedType: any ErasedType
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					public protocol ErasedType {}

					@Instantiable
					public final class SomeErasedType: ErasedType {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child {
					    @Received let erasedType: ErasedType
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithUnfulfillableInstantiatedPropertyDueToUnexpectedForceUnwrap_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `thing: Thing!` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			Did you mean one of the following available properties?
			\t`thing: Thing`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root {
					    @Instantiated let thing: Thing
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child {
					    @Received let thing: Thing!
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithUnfulfillableInstantiatedPropertyDueToDroppedForceUnwrap_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `thing: Thing` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			Did you mean one of the following available properties?
			\t`thing: Thing!`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root {
					    @Instantiated let thing: Thing!
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child {
					    @Received let thing: Thing
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithUnfulfillableInstantiatedPropertyDueToUnexpectedOptional_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `thing: Thing?` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			The non-optional `thing: Thing` is available in chain. Did you mean to decorate this property with `@Received(onlyIfAvailable: true)`?
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root {
					    @Instantiated let thing: Thing
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child {
					    @Received let thing: Thing?
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithUnfulfillableInstantiatedPropertyDueToDroppedOptional_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `thing: Thing` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			Did you mean one of the following available properties?
			\t`thing: Thing?`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root {
					    @Instantiated let thing: Thing?
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child {
					    @Received let thing: Thing
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithUnfulfillableInstantiatedPropertyDueToIncorrectType_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `thing: OtherThing` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			Did you mean one of the following available properties?
			\t`thing: Thing`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root {
					    @Instantiated let thing: Thing
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing {}

					@Instantiable
					public final class OtherThing {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child {
					    @Received let thing: OtherThing
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithUnfulfillableInstantiatedPropertyDueToIncorrectTypeOrLabel_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `thing: OtherThing` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			Did you mean one of the following available properties?
			\t`otherThing: OtherThing`
			\t`thing: Thing`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root {
					    @Instantiated let thing: Thing
					    @Instantiated let otherThing: OtherThing
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing {}

					@Instantiable
					public final class OtherThing {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child {
					    @Received let thing: OtherThing
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithInstantiatedPropertyWithForwardedArgument_throwsError() async {
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
					    @Forwarded let urlSession: URLSession
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController {
					    @Instantiated let networkService: NetworkService
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithDiamondDependencyWhereAReceivedPropertyIsUnfulfillableOnOneBranch_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `blankie: Blankie` is not @Instantiated or @Forwarded in chain:
			\tRoot -> ChildB -> Grandchild
			"""
		) {
			try await executeSafeDIToolTest(
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
					    @Instantiated let grandchild: Grandchild
					    @Instantiated let blankie: Blankie
					}
					""",
					"""
					@Instantiable
					public final class ChildB {
					    @Instantiated let grandchild: Grandchild
					}
					""",
					"""
					@Instantiable
					public final class Grandchild {
					    @Received let blankie: Blankie
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

	@Test
	mutating func run_onCodeWithDiamondDependencyWhereMultipleReceivedPropertiesAreUnfulfillableOnOneBranch_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `blankie2: Blankie` is not @Instantiated or @Forwarded in chain:
			\tRoot -> ChildA -> Grandchild

			Did you mean one of the following available properties?
			\t`blankie: Blankie`

			@Received property `blankie2: Blankie` is not @Instantiated or @Forwarded in chain:
			\tRoot -> ChildB -> Grandchild

			@Received property `blankie: Blankie` is not @Instantiated or @Forwarded in chain:
			\tRoot -> ChildB -> Grandchild
			"""
		) {
			try await executeSafeDIToolTest(
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
					    @Instantiated let grandchild: Grandchild
					    @Instantiated let blankie: Blankie
					}
					""",
					"""
					@Instantiable
					public final class ChildB {
					    @Instantiated let grandchild: Grandchild
					}
					""",
					"""
					@Instantiable
					public final class Grandchild {
					    @Received let blankie: Blankie
					    @Received let blankie2: Blankie
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

	@Test
	mutating func run_onCodeWithInstantiatedPropertyThatRefersToCurrentInstantiable_throwsError() async throws {
		await assertThrowsError(
			"""
			Dependency cycle detected:
			\tAuthService -> AuthService
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

					    @Instantiated let networkService: NetworkService

					    @Instantiated let authService: AuthService
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController {
					    public init(authService: AuthService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
					        self.authService = authService
					        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
					        super.init(nibName: nil, bundle: nil)
					    }

					    @Instantiated let authService: AuthService
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithReceivedPropertyThatRefersToCurrentInstantiable_throwsError() async throws {
		await assertThrowsError(
			"""
			Dependency received in same chain it is instantiated:
			\t@Instantiated authService: AuthService -> @Received authService: AuthService
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

					    @Instantiated let networkService: NetworkService

					    @Received let authService: AuthService
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController {
					    public init(authService: AuthService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
					        self.authService = authService
					        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
					        super.init(nibName: nil, bundle: nil)
					    }

					    @Instantiated let authService: AuthService
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithUnfulfillableAliasedReceivedPropertyName_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `networkService2: NetworkService` is not @Instantiated or @Forwarded in chain:
			\tRootViewController -> DefaultAuthService

			Did you mean one of the following available properties?
			\t`networkService: NetworkService`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import Foundation

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
					    @Instantiated let networkService: NetworkService

					    @Instantiated let authService: AuthService
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

					    @Received(fulfilledByDependencyNamed: "networkService2", ofType: NetworkService.self) let networking: NetworkService
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithUnfulfillableAliasedReceivedPropertyType_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `networkService: NetworkService2` is not @Instantiated or @Forwarded in chain:
			\tRootViewController -> DefaultAuthService

			Did you mean one of the following available properties?
			\t`networkService: NetworkService`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import Foundation

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
					    @Instantiated let networkService: NetworkService

					    @Instantiated let authService: AuthService
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

					    @Received(fulfilledByDependencyNamed: "networkService", ofType: NetworkService2.self) let networking: NetworkService
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWhereAliasedReceivedPropertyRefersToCurrentInstantiable_throwsError() async throws {
		await assertThrowsError(
			"""
			Dependency received in same chain it is instantiated:
			\t@Instantiated authService: AuthService -> @Received authService: AuthService
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

					    @Instantiated let networkService: NetworkService

					    @Received(fulfilledByDependencyNamed: "authService", ofType: AuthService.self) let renamedAuthService: AuthService
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController {
					    public init(authService: AuthService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
					        self.authService = authService
					        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
					        super.init(nibName: nil, bundle: nil)
					    }

					    @Instantiated let authService: AuthService
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithUnfulfillableReceivedPropertyOnExtendedInstantiatedType_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `urlSession: URLSession` is not @Instantiated or @Forwarded in chain:
			\tRootViewController -> URLSessionWrapper
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

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController {
					    @Instantiated let urlSessionWrapper: URLSessionWrapper
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithDuplicateInstantiableNames_throwsError() async {
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

	@Test
	mutating func run_onCodeWithDuplicateInstantiableNamesWhereOneIsRoot_throwsError() async {
		await assertThrowsError(
			"""
			@Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unqiue types. Found multiple types or extensions fulfilling `RootViewController`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable(isRoot: true)
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

	@Test
	mutating func run_onCodeWithDuplicateInstantiableNamesViaDeclarationAndExtension_throwsError() async {
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

	@Test
	mutating func run_onCodeWithDuplicateInstantiableNamesViaDeclarationAndExtensionWhereDeclarationIsRoot_throwsError() async {
		await assertThrowsError(
			"""
			@Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unqiue types. Found multiple types or extensions fulfilling `RootViewController`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable(isRoot: true)
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

	@Test
	mutating func run_onCodeWithDuplicateInstantiableNamesViaDeclarationAndExtensionWhereExtensionIsRoot_throwsError() async {
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

					@Instantiable(isRoot: true)
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

	@Test
	mutating func run_onCodeWithDuplicateInstantiableNamesViaExtension_throwsError() async {
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

	@Test
	mutating func run_onCodeWithDuplicateInstantiableFulfillment_throwsError() async {
		await assertThrowsError(
			"""
			@Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unqiue types. Found multiple types or extensions fulfilling `UIViewController`
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable(isRoot: true, fulfillingAdditionalTypes: [UIViewController.self])
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

	@Test
	mutating func run_onCodeWithCircularPropertyDependenciesImmediatelyInitialized_throwsError() async {
		await assertThrowsError(
			"""
			Dependency cycle detected:
			\tA -> B -> C -> A
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
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
					    @Instantiated let a: A
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithCircularPropertyDependenciesImmediatelyInitializedWithMixOfReceivedAndInstantiated_throwsError() async throws {
		await assertThrowsError(
			"""
			Dependency cycle detected:
			\tA -> C -> B -> A
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root {
						@Instantiated public let a: A // A -> C -> Received B
						@Instantiated public let b: B // B -> Received A
					}

					@Instantiable
					public final class A {
						@Instantiated let c: C
					}

					@Instantiable
					public final class B {
						@Received public let a: A
					}

					@Instantiable
					public final class C {
						@Received public let b: B
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithCircularPropertyDependenciesImmediatelyInitializedAndReceived_throwsError() async {
		await assertThrowsError(
			"""
			Dependency cycle detected:
			\tA -> B -> C -> A
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
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

	@Test
	mutating func run_onCodeWithCircularPropertyDependenciesLazyInitializedAndReceived_throwsError() async throws {
		await assertThrowsError(
			"""
			Dependency cycle detected! @Instantiated `aBuilder: Instantiator<A>` is @Received in tree created by @Instantiated `aBuilder: Instantiator<A>`. Declare @Received `aBuilder: Instantiator<A>` on `C` as @Instantiated to fix. Full cycle:
			\tInstantiator<A> -> Instantiator<B> -> Instantiator<C> -> Instantiator<A>
			"""
		) {
			try await executeSafeDIToolTest(
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
					    @Received let aBuilder: Instantiator<A>
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithCircularPropertyDependenciesLazyInitializedAndOnlyIfAvailableReceived_throwsError() async throws {
		await assertThrowsError(
			"""
			Dependency cycle detected! @Instantiated `aBuilder: Instantiator<A>?` is @Received in tree created by @Instantiated `aBuilder: Instantiator<A>?`. Declare @Received `aBuilder: Instantiator<A>?` on `C` as @Instantiated to fix. Full cycle:
			\tInstantiator<A>? -> Instantiator<B> -> Instantiator<C> -> Instantiator<A>?
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root {
					    @Instantiated let aBuilder: Instantiator<A>?
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
					    @Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithCircularPropertyDependenciesImmediatelyInitializedWithVaryingNames_throwsError() async {
		await assertThrowsError(
			"""
			Dependency cycle detected:
			\tB -> C -> A -> B
			"""
		) {
			try await executeSafeDIToolTest(
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
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public struct C {
					    @Instantiated let a2: A
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithCircularReceivedDependencies_throwsError() async {
		await assertThrowsError(
			"""
			Dependency received in same chain it is instantiated:
			\t@Instantiated a: A -> @Received b: B -> @Received c: C -> @Received a: A
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root {
					    @Instantiated private let a: A
					    @Instantiated private let b: B
					    @Instantiated private let c: C
					}
					""",
					"""
					@Instantiable
					public struct A {
					    @Received private let b: B
					}
					""",
					"""
					@Instantiable
					public struct B {
					    @Received private let c: C
					}
					""",
					"""
					@Instantiable
					public struct C {
					    @Received private let a: A
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithCircularReceivedRenamedDependencies_throwsError() async {
		await assertThrowsError(
			"""
			Dependency received in same chain it is instantiated:
			\t@Instantiated a: A -> @Received renamedB: B -> @Received c: C -> @Received a: A
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root {
					    @Instantiated private let a: A
					    @Instantiated private let b: B
					    @Received(fulfilledByDependencyNamed: "b", ofType: B.self) private let renamedB: B
					    @Instantiated private let c: C
					}
					""",
					"""
					@Instantiable
					public struct A {
					    @Received private let renamedB: B
					}
					""",
					"""
					@Instantiable
					public struct B {
					    @Received private let c: C
					}
					""",
					"""
					@Instantiable
					public struct C {
					    @Received private let a: A
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithMultipleCircularReceivedRenamedDependencies_throwsError() async {
		await assertThrowsError(
			"""
			Dependency received in same chain it is instantiated:
			\t@Instantiated c: C -> @Received renamedB: B -> @Received c: C
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root {
					    @Instantiated private let a: A
					}
					""",
					"""
					@Instantiable
					public struct A {
					    @Instantiated private let b: B
					    @Received(fulfilledByDependencyNamed: "b", ofType: B.self) private let renamedB: B
					    @Instantiated private let c: C
					}
					""",
					"""
					@Instantiable
					public struct B {
					    @Received private let c: C
					}
					""",
					"""
					@Instantiable
					public struct C {
					    @Received private let renamedB: B
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_OnCodeWithOptionalPropertyAliasAndMarkedOnlyIfAvailableAndItIsOnlyAvialableViaCircularDependency_throws_error() async throws {
		await assertThrowsError(
			"""
			Dependency cycle detected:
				C -> B -> C
			"""
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root {
						public init(aBuilder: Instantiator<A>) {
							fatalError("SafeDI doesn't inspect the initializer body")
						}

						@Instantiated let aBuilder: Instantiator<A>
					}
					""",
					"""
					@Instantiable
					public final class A {
						public init(c: C) {
							fatalError("SafeDI doesn't inspect the initializer body")
						}

						@Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class B {
						public init(cRenamed: CRenamed?) {
							fatalError("SafeDI doesn't inspect the initializer body")
						}

						@Received(fulfilledByDependencyNamed: "c", ofType: C.self, onlyIfAvailable: true) let cRenamed: CRenamed?
					}
					""",
					"""
					@Instantiable
					public final class C {
						public init(b: B) {
							fatalError("SafeDI doesn't inspect the initializer body")
						}

						@Instantiated let b: B
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithIncorrectErasedInstantiatorFirstGeneric_whenInstantiableHasSingleForwardedProperty_throwsError() async throws {
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

					    @Received let networkService: NetworkService
					}
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
					    public init(authService: AuthService, networkService: NetworkService, loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>) {
					        self.authService = authService
					        self.networkService = networkService
					        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
					        derivedValue = false
					        super.init(nibName: nil, bundle: nil)
					    }

					    @Instantiated let networkService: NetworkService

					    @Instantiated let authService: AuthService

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
					    @Forwarded private let user: User

					    @Received let networkService: NetworkService
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	@Test
	mutating func run_onCodeWithIncorrectErasedInstantiatorFirstGeneric_whenInstantiableHasMultipleForwardedProperty_throwsError() async throws {
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

					    @Received let networkService: NetworkService
					}
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
					    public init(authService: AuthService, networkService: NetworkService, loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>) {
					        self.authService = authService
					        self.networkService = networkService
					        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
					        derivedValue = false
					        super.init(nibName: nil, bundle: nil)
					    }

					    @Instantiated let networkService: NetworkService

					    @Instantiated let authService: AuthService

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
					    @Forwarded private let user: User

					    @Forwarded private let userManager: UserManager

					    @Received let networkService: NetworkService
					}
					""",
				],
				buildDependencyTreeOutput: true,
				filesToDelete: &filesToDelete
			)
		}
	}

	// MARK: Argument handling error tests

	@Test
	func include_throwsErrorWhenCanNotCreateEnumerator() async {
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
		await SafeDITool.$fileFinder.withValue(FailingFileFinder()) {
			var tool = SafeDITool()
			tool.swiftSourcesFilePath = nil
			tool.showVersion = false
			tool.include = ["Fake"]
			tool.includeFilePath = nil
			tool.additionalImportedModules = []
			tool.additionalImportedModulesFilePath = nil
			tool.moduleInfoOutput = nil
			tool.dependentModuleInfoFilePath = nil
			tool.dependencyTreeOutput = nil
			tool.dotFileOutput = nil
			await assertThrowsError("Could not create file enumerator for directory 'Fake'") {
				try await tool.run()
			}
		}
	}

	@Test
	func include_throwsErrorWhenNoSwiftSourcesFilePathAndNoInclude() async {
		var tool = SafeDITool()
		tool.swiftSourcesFilePath = nil
		tool.showVersion = false
		tool.include = []
		tool.includeFilePath = nil
		tool.additionalImportedModules = []
		tool.additionalImportedModulesFilePath = nil
		tool.moduleInfoOutput = nil
		tool.dependentModuleInfoFilePath = nil
		tool.dependencyTreeOutput = nil
		tool.dotFileOutput = nil
		await assertThrowsError("Must provide 'swift-sources-file-path', '--include', or '--include-file-path'.") {
			try await tool.run()
		}
	}

	// MARK: Private

	private var filesToDelete = [URL]()
}
