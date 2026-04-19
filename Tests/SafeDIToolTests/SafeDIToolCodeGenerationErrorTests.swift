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
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithPropertyWithUnknownFulfilledType_throwsError() async {
		await assertThrowsError(
			"""
			No `@Instantiable`-decorated type or extension found to fulfill `@Instantiated`-decorated property with type `DoesNotExist`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    @Instantiated(fulfilledByType: "DoesNotExist")
					    let networkService: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithPropertyWithUnknownTypeWithDotSuffixOfFulfillableType_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `value: NestedType` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Instantiator<Child> -> Grandchild

			Did you mean one of the following available properties?
			\t`value: Grandchild.NestedType`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let childBuilder: Instantiator<Child>
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Forwarded let value: Grandchild.NestedType
					    @Instantiated let grandchild: Grandchild
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Grandchild: Instantiable {
					    public struct NestedType {}
					    @Received let value: NestedType
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithPropertyWithUnknownTypeWithDotPrefixOfFulfillableType_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `value: Root.NestedType` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Instantiator<Child> -> Grandchild

			Did you mean one of the following available properties?
			\t`value: NestedType`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let childBuilder: Instantiator<Child>
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    public struct NestedType {}
					    @Forwarded let value: NestedType
					    @Instantiated let grandchild: Grandchild
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Grandchild: Instantiable {
					    @Received let value: Root.NestedType
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithMultipleInstantiateMethodsForTheSameTypeWithSameParameters_throwsError() async {
		await assertThrowsError(
			"""
			@Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `Container<Int>`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					extension Container: Instantiable {}
					""",
					"""
					@Instantiable(conformsElsewhere: true)
					extension Array: Instantiable {
					    public static func instantiate() -> Container<Int> {
					        .init(0)
					    }
					}
					""",
					"""
					@Instantiable(conformsElsewhere: true)
					extension Array: Instantiable {
					    public static func instantiate() -> Container<Int> {
					        .init(0)
					    }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithMultipleInstantiateMethodsForTheSameTypeWithDifferentParameters_throwsError() async {
		await assertThrowsError(
			"""
			@Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `Container<Int>`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					extension Container: Instantiable {}
					""",
					"""
					@Instantiable(conformsElsewhere: true)
					extension Array: Instantiable {
					    public static func instantiate() -> Container<Int> {
					        .init(0)
					    }
					}
					""",
					"""
					@Instantiable(conformsElsewhere: true)
					extension Array: Instantiable {
					    public static func instantiate(intValue: Int) -> Container<Int> {
					        .init(intValue)
					    }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableInstantiatedProperty_throwsError() async {
		await assertThrowsError(
			"""
			No `@Instantiable`-decorated type or extension found to fulfill `@Instantiated`-decorated property with type `URLSession`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import Foundation

					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    @Instantiated let urlSession: URLSession // URLSession is not `@Instantiable`! This will fail!
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    @Instantiated let networkService: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedProperty_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `urlSession: URLSession` is not @Instantiated or @Forwarded in chain:
			\tRootViewController -> DefaultNetworkService
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import Foundation

					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    @Received let urlSession: URLSession // URLSession is not `@Instantiable`! This will fail!
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    @Instantiated let networkService: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToUnexpectedAny_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `erasedType: any ErasedType` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			Did you mean one of the following available properties?
			\t`erasedType: ErasedType`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated(fulfilledByType: "SomeErasedType") let erasedType: ErasedType
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					public protocol ErasedType {}

					@Instantiable
					public final class SomeErasedType: ErasedType, Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let erasedType: any ErasedType
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToDroppedAny_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `erasedType: ErasedType` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			Did you mean one of the following available properties?
			\t`erasedType: any ErasedType`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated(fulfilledByType: "SomeErasedType") let erasedType: any ErasedType
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					public protocol ErasedType {}

					@Instantiable
					public final class SomeErasedType: ErasedType, Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let erasedType: ErasedType
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToUnexpectedForceUnwrap_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `thing: Thing!` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			Did you mean one of the following available properties?
			\t`thing: Thing`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let thing: Thing
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing: Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let thing: Thing!
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToDroppedForceUnwrap_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `thing: Thing` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			Did you mean one of the following available properties?
			\t`thing: Thing!`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let thing: Thing!
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing: Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let thing: Thing
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToUnexpectedOptional_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `thing: Thing?` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			The non-optional `thing: Thing` is available in chain. Did you mean to decorate this property with `@Received(onlyIfAvailable: true)`?
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let thing: Thing
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing: Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let thing: Thing?
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToDroppedOptional_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `thing: Thing` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			Did you mean one of the following available properties?
			\t`thing: Thing?`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let thing: Thing?
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing: Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let thing: Thing
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToIncorrectType_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `thing: OtherThing` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			Did you mean one of the following available properties?
			\t`thing: Thing`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let thing: Thing
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing: Instantiable {}

					@Instantiable
					public final class OtherThing: Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let thing: OtherThing
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToIncorrectTypeOrLabel_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `thing: OtherThing` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child

			Did you mean one of the following available properties?
			\t`otherThing: OtherThing`
			\t`thing: Thing`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let thing: Thing
					    @Instantiated let otherThing: OtherThing
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing: Instantiable {}

					@Instantiable
					public final class OtherThing: Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let thing: OtherThing
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithInstantiatedPropertyWithForwardedArgument_throwsError() async {
		await assertThrowsError(
			"""
			Property `networkService: NetworkService` on RootViewController has at least one @Forwarded property. Property should instead be of type `Instantiator<DefaultNetworkService>`.
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import Foundation

					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    @Forwarded let urlSession: URLSession
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    @Instantiated let networkService: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDiamondDependencyWhereAReceivedPropertyIsUnfulfillableOnOneBranch_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `blankie: Blankie` is not @Instantiated or @Forwarded in chain:
			\tRoot -> ChildB -> Grandchild
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let childA: ChildA
					    @Instantiated let childB: ChildB
					}
					""",
					"""
					@Instantiable
					public final class ChildA: Instantiable {
					    @Instantiated let grandchild: Grandchild
					    @Instantiated let blankie: Blankie
					}
					""",
					"""
					@Instantiable
					public final class ChildB: Instantiable {
					    @Instantiated let grandchild: Grandchild
					}
					""",
					"""
					@Instantiable
					public final class Grandchild: Instantiable {
					    @Received let blankie: Blankie
					}
					""",
					"""
					@Instantiable
					public final class Blankie: Instantiable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
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
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let childA: ChildA
					    @Instantiated let childB: ChildB
					}
					""",
					"""
					@Instantiable
					public final class ChildA: Instantiable {
					    @Instantiated let grandchild: Grandchild
					    @Instantiated let blankie: Blankie
					}
					""",
					"""
					@Instantiable
					public final class ChildB: Instantiable {
					    @Instantiated let grandchild: Grandchild
					}
					""",
					"""
					@Instantiable
					public final class Grandchild: Instantiable {
					    @Received let blankie: Blankie
					    @Received let blankie2: Blankie
					}
					""",
					"""
					@Instantiable
					public final class Blankie: Instantiable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithInstantiatedPropertyThatRefersToCurrentInstantiable_throwsError() async {
		await assertThrowsError(
			"""
			Dependency cycle detected:
			\tAuthService -> AuthService
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public struct User {
					    public init(username: String) {}
					}
					""",
					"""
					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    public init() {}
					}
					""",
					"""
					public protocol AuthService {
					    func login(username: String, password: String) async -> User
					}

					@Instantiable(fulfillingAdditionalTypes: [AuthService.self])
					public final class DefaultAuthService: AuthService, Instantiable {
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
					public final class RootViewController: UIViewController, Instantiable {
					    public init(authService: AuthService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
					        self.authService = authService
					        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
					        super.init(nibName: nil, bundle: nil)
					    }

					    @Instantiated let authService: AuthService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithReceivedPropertyThatRefersToCurrentInstantiable_throwsError() async {
		await assertThrowsError(
			"""
			Dependency received in same chain it is instantiated:
			\t@Instantiated authService: AuthService -> @Received authService: AuthService
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public struct User {
					    public init(username: String) {}
					}
					""",
					"""
					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    public init() {}
					}
					""",
					"""
					public protocol AuthService {
					    func login(username: String, password: String) async -> User
					}

					@Instantiable(fulfillingAdditionalTypes: [AuthService.self])
					public final class DefaultAuthService: AuthService, Instantiable {
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
					public final class RootViewController: UIViewController, Instantiable {
					    public init(authService: AuthService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
					        self.authService = authService
					        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
					        super.init(nibName: nil, bundle: nil)
					    }

					    @Instantiated let authService: AuthService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableAliasedReceivedPropertyName_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `networkService2: NetworkService` is not @Instantiated or @Forwarded in chain:
			\tRootViewController -> DefaultAuthService

			Did you mean one of the following available properties?
			\t`networkService: NetworkService`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import Foundation

					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    public init() {}
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    @Instantiated let networkService: NetworkService

					    @Instantiated let authService: AuthService
					}
					""",
					"""
					public protocol AuthService {
					    func login(username: String, password: String) async -> User
					}

					@Instantiable(fulfillingAdditionalTypes: [AuthService.self])
					public final class DefaultAuthService: AuthService, Instantiable {
					    public func login(username: String, password: String) async -> User {
					        User(username: username)
					    }

					    @Received(fulfilledByDependencyNamed: "networkService2", ofType: NetworkService.self) let networking: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableAliasedReceivedPropertyType_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `networkService: NetworkService2` is not @Instantiated or @Forwarded in chain:
			\tRootViewController -> DefaultAuthService

			Did you mean one of the following available properties?
			\t`networkService: NetworkService`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import Foundation

					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    public init() {}
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    @Instantiated let networkService: NetworkService

					    @Instantiated let authService: AuthService
					}
					""",
					"""
					public protocol AuthService {
					    func login(username: String, password: String) async -> User
					}

					@Instantiable(fulfillingAdditionalTypes: [AuthService.self])
					public final class DefaultAuthService: AuthService, Instantiable {
					    public func login(username: String, password: String) async -> User {
					        User(username: username)
					    }

					    @Received(fulfilledByDependencyNamed: "networkService", ofType: NetworkService2.self) let networking: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWhereAliasedReceivedPropertyRefersToCurrentInstantiable_throwsError() async {
		await assertThrowsError(
			"""
			Dependency received in same chain it is instantiated:
			\t@Instantiated authService: AuthService -> @Received authService: AuthService
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public struct User {
					    public init(username: String) {}
					}
					""",
					"""
					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    public init() {}
					}
					""",
					"""
					public protocol AuthService {
					    func login(username: String, password: String) async -> User
					}

					@Instantiable(fulfillingAdditionalTypes: [AuthService.self])
					public final class DefaultAuthService: AuthService, Instantiable {
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
					public final class RootViewController: UIViewController, Instantiable {
					    public init(authService: AuthService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
					        self.authService = authService
					        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
					        super.init(nibName: nil, bundle: nil)
					    }

					    @Instantiated let authService: AuthService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyOnExtendedInstantiatedType_throwsError() async {
		await assertThrowsError(
			"""
			@Received property `urlSession: URLSession` is not @Instantiated or @Forwarded in chain:
			\tRootViewController -> URLSessionWrapper
			""",
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
					public final class RootViewController: UIViewController, Instantiable {
					    @Instantiated let urlSessionWrapper: URLSessionWrapper
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDuplicateInstantiableNames_throwsError() async {
		await assertThrowsError(
			"""
			@Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable
					public final class RootViewController: UIViewController, Instantiable {}
					""",
					"""
					import UIKit

					@Instantiable
					public final class RootViewController: UIViewController, Instantiable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDuplicateInstantiableNamesWhereOneIsRoot_throwsError() async {
		await assertThrowsError(
			"""
			@Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {}
					""",
					"""
					import UIKit

					@Instantiable
					public final class RootViewController: UIViewController, Instantiable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDuplicateInstantiableNamesViaDeclarationAndExtension_throwsError() async {
		await assertThrowsError(
			"""
			@Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable
					public final class RootViewController: UIViewController, Instantiable {}
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
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDuplicateInstantiableNamesViaDeclarationAndExtensionWhereDeclarationIsRoot_throwsError() async {
		await assertThrowsError(
			"""
			@Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {}
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
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDuplicateInstantiableNamesViaDeclarationAndExtensionWhereExtensionIsRoot_throwsError() async {
		await assertThrowsError(
			"""
			@Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable
					public final class RootViewController: UIViewController, Instantiable {}
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
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDuplicateInstantiableNamesViaExtension_throwsError() async {
		await assertThrowsError(
			"""
			@Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `UserDefaults`
			""",
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
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDuplicateInstantiableFulfillment_throwsError() async {
		await assertThrowsError(
			"""
			@Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `UIViewController`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable(isRoot: true, fulfillingAdditionalTypes: [UIViewController.self])
					public final class RootViewController: UIViewController, Instantiable {}
					""",
					"""
					import UIKit

					@Instantiable(fulfillingAdditionalTypes: [UIViewController.self])
					public final class SplashViewController: UIViewController, Instantiable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularPropertyDependenciesImmediatelyInitialized_throwsError() async {
		await assertThrowsError(
			"""
			Dependency cycle detected:
			\tA -> B -> C -> A
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let a: A
					}
					""",
					"""
					@Instantiable
					public final class A: Instantiable {
					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    @Instantiated let a: A
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularPropertyDependenciesImmediatelyInitializedWithMixOfReceivedAndInstantiated_throwsError() async {
		await assertThrowsError(
			"""
			Dependency cycle detected:
			\tA -> C -> B -> A
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
						@Instantiated public let a: A // A -> C -> Received B
						@Instantiated public let b: B // B -> Received A
					}

					@Instantiable
					public final class A: Instantiable {
						@Instantiated let c: C
					}

					@Instantiable
					public final class B: Instantiable {
						@Received public let a: A
					}

					@Instantiable
					public final class C: Instantiable {
						@Received public let b: B
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularPropertyDependenciesImmediatelyInitializedAndReceived_throwsError() async {
		await assertThrowsError(
			"""
			Dependency cycle detected:
			\tA -> B -> C -> A
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let a: A
					}
					""",
					"""
					@Instantiable
					public final class A: Instantiable {
					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    @Received let a: A
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularPropertyDependenciesLazyInitializedAndReceived_throwsError() async {
		await assertThrowsError(
			"""
			Dependency cycle detected! @Instantiated `aBuilder: Instantiator<A>` is @Received in tree created by @Instantiated `aBuilder: Instantiator<A>`. Declare @Received `aBuilder: Instantiator<A>` on `C` as @Instantiated to fix. Full cycle:
			\tInstantiator<A> -> Instantiator<B> -> Instantiator<C> -> Instantiator<A>
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    @Instantiated let cBuilder: Instantiator<C>
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    @Received let aBuilder: Instantiator<A>
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularPropertyDependenciesLazyInitializedAndOnlyIfAvailableReceived_throwsError() async {
		await assertThrowsError(
			"""
			Dependency cycle detected! @Instantiated `aBuilder: Instantiator<A>?` is @Received in tree created by @Instantiated `aBuilder: Instantiator<A>?`. Declare @Received `aBuilder: Instantiator<A>?` on `C` as @Instantiated to fix. Full cycle:
			\tInstantiator<A>? -> Instantiator<B> -> Instantiator<C> -> Instantiator<A>?
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>?
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    @Instantiated let cBuilder: Instantiator<C>
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    @Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularPropertyDependenciesImmediatelyInitializedWithVaryingNames_throwsError() async {
		await assertThrowsError(
			"""
			Dependency cycle detected:
			\tB -> C -> A -> B
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    @Instantiated let a: A
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    @Instantiated let a2: A
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularReceivedDependencies_throwsError() async {
		await assertThrowsError(
			"""
			Dependency received in same chain it is instantiated:
			\t@Instantiated a: A -> @Received b: B -> @Received c: C -> @Received a: A
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    @Instantiated private let a: A
					    @Instantiated private let b: B
					    @Instantiated private let c: C
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    @Received private let b: B
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    @Received private let c: C
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    @Received private let a: A
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularReceivedRenamedDependencies_throwsError() async {
		await assertThrowsError(
			"""
			Dependency received in same chain it is instantiated:
			\t@Instantiated a: A -> @Received renamedB: B -> @Received c: C -> @Received a: A
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    @Instantiated private let a: A
					    @Instantiated private let b: B
					    @Received(fulfilledByDependencyNamed: "b", ofType: B.self) private let renamedB: B
					    @Instantiated private let c: C
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    @Received private let renamedB: B
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    @Received private let c: C
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    @Received private let a: A
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithMultipleCircularReceivedRenamedDependencies_throwsError() async {
		await assertThrowsError(
			"""
			Dependency received in same chain it is instantiated:
			\t@Instantiated c: C -> @Received renamedB: B -> @Received c: C
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    @Instantiated private let a: A
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    @Instantiated private let b: B
					    @Received(fulfilledByDependencyNamed: "b", ofType: B.self) private let renamedB: B
					    @Instantiated private let c: C
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    @Received private let c: C
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    @Received private let renamedB: B
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithOptionalPropertyAliasAndMarkedOnlyIfAvailableAndItIsOnlyAvailableViaCircularDependency_throwsError() async {
		await assertThrowsError(
			"""
			Dependency cycle detected:
				C -> B -> C
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
						public init(aBuilder: Instantiator<A>) {
							fatalError("SafeDI doesn't inspect the initializer body")
						}

						@Instantiated let aBuilder: Instantiator<A>
					}
					""",
					"""
					@Instantiable
					public final class A: Instantiable {
						public init(c: C) {
							fatalError("SafeDI doesn't inspect the initializer body")
						}

						@Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
						public init(cRenamed: CRenamed?) {
							fatalError("SafeDI doesn't inspect the initializer body")
						}

						@Received(fulfilledByDependencyNamed: "c", ofType: C.self, onlyIfAvailable: true) let cRenamed: CRenamed?
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
						public init(b: B) {
							fatalError("SafeDI doesn't inspect the initializer body")
						}

						@Instantiated let b: B
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithIncorrectErasedInstantiatorFirstGeneric_whenInstantiableHasSingleForwardedProperty_throwsError() async {
		await assertThrowsError(
			"""
			Property `loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>` on LoggedInViewController incorrectly configured. Property should instead be of type `ErasedInstantiator<LoggedInViewController.ForwardedProperties, UIViewController>`.
			""",
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
					public final class DefaultAuthService: AuthService, Instantiable {
					    public func login(username: String, password: String) async -> User {
					        User()
					    }

					    @Received let networkService: NetworkService
					}
					""",
					"""
					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    public init() {}
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
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
					public final class LoggedInViewController: UIViewController, Instantiable {
					    @Forwarded private let user: User

					    @Received let networkService: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithIncorrectErasedInstantiatorFirstGeneric_whenInstantiableHasMultipleForwardedProperty_throwsError() async {
		await assertThrowsError(
			"""
			Property `loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>` on LoggedInViewController incorrectly configured. Property should instead be of type `ErasedInstantiator<LoggedInViewController.ForwardedProperties, UIViewController>`.
			""",
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
					public final class DefaultAuthService: AuthService, Instantiable {
					    public func login(username: String, password: String) async -> User {
					        User()
					    }

					    @Received let networkService: NetworkService
					}
					""",
					"""
					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    public init() {}
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
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
					public final class LoggedInViewController: UIViewController, Instantiable {
					    @Forwarded private let user: User

					    @Forwarded private let userManager: UserManager

					    @Received let networkService: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Argument handling error tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func include_throwsErrorWhenCanNotCreateEnumerator() async throws {
		final class FailingFileFinder: FileFinder {
			func enumerator(
				at _: URL,
				includingPropertiesForKeys _: [URLResourceKey]?,
				options _: FileManager.DirectoryEnumerationOptions,
				errorHandler _: ((URL, any Error) -> Bool)?,
			) -> FileManager.DirectoryEnumerator? {
				nil
			}
		}
		let tool = try Generate.parse(["--include", "Fake"])
		await SafeDITool.$fileFinder.withValue(FailingFileFinder()) {
			await assertThrowsError("Could not create file enumerator for directory 'Fake'") {
				let mutableTool = tool
				try await mutableTool.run()
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func include_throwsErrorWhenNoSwiftSourcesFilePathAndNoInclude() async throws {
		let tool = try Generate.parse([])
		await assertThrowsError("Must provide 'swift-sources-file-path' or '--include'.") {
			try await tool.run()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_throwsError_whenOutputDirectoryProvidedWithoutCSV() async throws {
		let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		let tool = try Generate.parse([
			"--include", "SomeDir",
			"--output-directory", outputDirectory.path,
		])
		await assertThrowsError("--output-directory requires 'swift-sources-file-path'.") {
			try await tool.run()
		}
	}

	// MARK: Manifest Validation Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsError_whenManifestListsFileThatDoesNotContainRoot() async throws {
		let swiftFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
		try """
		@Instantiable
		public struct NotRoot: Instantiable {
		    public init() {}
		}
		""".write(to: swiftFile, atomically: true, encoding: .utf8)
		let swiftFileCSV = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try swiftFile.relativePath.write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let manifestFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
		let outputFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
		let manifest = SafeDIToolManifest(dependencyTreeGeneration: [.init(inputFilePath: swiftFile.relativePath, outputFilePath: outputFile.relativePath)])
		try JSONEncoder().encode(manifest).write(to: manifestFile)
		let moduleInfoOutput = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".safedi")

		filesToDelete += [swiftFileCSV, swiftFile, manifestFile, moduleInfoOutput]

		await assertThrowsError(
			"Manifest lists '\(swiftFile.relativePath)' as containing a dependency tree root, but no @Instantiable(isRoot: true) was found in that file.",
		) {
			let tool = try Generate.parse([
				swiftFileCSV.relativePath,
				"--module-info-output", moduleInfoOutput.relativePath,
				"--swift-manifest", manifestFile.relativePath,
			])
			try await tool.run()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsError_whenRootExistsButNotInManifest() async throws {
		let swiftFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
		try """
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(dep: Dep) { self.dep = dep }
		    @Instantiated let dep: Dep
		}
		@Instantiable
		public struct Dep: Instantiable {
		    public init() {}
		}
		""".write(to: swiftFile, atomically: true, encoding: .utf8)
		let swiftFileCSV = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try swiftFile.relativePath.write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let manifestFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
		let manifest = SafeDIToolManifest(dependencyTreeGeneration: [])
		try JSONEncoder().encode(manifest).write(to: manifestFile)
		let moduleInfoOutput = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".safedi")

		filesToDelete += [swiftFileCSV, swiftFile, manifestFile, moduleInfoOutput]

		await assertThrowsError(
			"Found @Instantiable(isRoot: true) in '\(swiftFile.relativePath)', but this file is not listed in the manifest’s dependencyTreeGeneration. Add it to the manifest or remove the isRoot annotation.",
		) {
			let tool = try Generate.parse([
				swiftFileCSV.relativePath,
				"--module-info-output", moduleInfoOutput.relativePath,
				"--swift-manifest", manifestFile.relativePath,
			])
			try await tool.run()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithMultipleSafeDIConfigurations_throwsError() async {
		do {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration()
					""",
					"""
					#SafeDIConfiguration(
					    mockConditionalCompilation: nil
					)
					""",
					"""
					@Instantiable
					public struct SimpleType: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
			Issue.record("Did not throw error!")
		} catch {
			let errorMessage = "\(error)"
			#expect(errorMessage.hasPrefix("Found 2 #SafeDIConfiguration declarations in this module. Each module must have at most one #SafeDIConfiguration. Found in:"))
			#expect(errorMessage.contains("File.swift"))
			#expect(errorMessage.contains("File_2.swift"))
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsError_whenPartiallyLazyInstantiationCycleExists() async {
		await assertThrowsError(
			"""
			Dependency cycle detected. Cycles with a mix of constant and lazy (Instantiator) dependencies cannot be resolved. Make all dependencies in the cycle lazy by using Instantiator:
			\tA -> B -> Instantiator<C> -> A
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(a: A) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let a: A
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(b: B) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(cBuilder: Instantiator<C>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let cBuilder: Instantiator<C>
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    public init(a: A) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let a: A
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete = [URL]()
}
