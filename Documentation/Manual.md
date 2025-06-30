# SafeDI Manual

This manual provides a detailed guide to using SafeDI effectively in your Swift projects. You’ll learn how to create your dependency tree utilizing SafeDI’s macros, learn recommended approaches to adopting SafeDI, and get a tour of how SafeDI works under the hood.

## Macros

There are a total of four macros in the SafeDI library:

| Macro  | Decorating | Usage |
| ------ | ---------- | ----- |
| [`@Instantiable`](#instantiable) | Type or extension declaration | Makes a type capable of being instantiated by SafeDI. |
| [`@Instantiated`](#instantiated) | Property declaration | Instantiates an instance or value when the enclosing `@Instantiable`-decorated type is instantiated. |
| [`@Forwarded`](#forwarded) | Property declaration | Propagates a runtime-created instance or value (e.g. a `User` object, network response, or customer input) down the dependency tree. |
| [`@Received`](#received) | Property declaration | Receives an instance or value from an `@Instantiated` or `@Forwarded` property further up the dependency tree. |

Let’s walk through each of these macros in detail.

### @Instantiable

Type declarations decorated with [`@Instantiable`](../Sources/SafeDI/Decorators/Instantiable.swift) are able to be instantiated by SafeDI. Types decorated with this macro can instantiate other `@Instantiable` dependencies, forward dependencies injected from outside of SafeDI, or receive dependencies instantiated or forwarded by objects further up the dependency tree.

SafeDI is designed to make instantiating and receiving dependencies _simple_, without requiring developers to think about abstract dependency injection (DI) concepts. That said, for those familiar with other DI systems: each `@Instantiable` type is its own [Scope](https://medium.com/@aarontharris/scope-dependency-injection-6fc25beffc9c). For those unfamiliar with DI terminology, know that each `@Instantiable` type retains its dependencies, and that every `@Instantiated` or `@Forwarded` dependency is available to all transitive child dependencies.  

Every `@Instantiable`-decorated type must be:

1. `public` or `open`

2. Have a `public init(…)` or `open init(…)` that has a parameter for each of its injected properties

The `@Instantiable` macro guides developers through satisfying these requirements with code generation and build-time fix-its.

Here is a sample `UserService` implementation that is `@Instantiable`:

```swift
import SafeDI

@Instantiable
public final class UserService: Instantiable {
    /// Public, memberwise initializer that takes each injected property.
    public init(authService: AuthService, securePersistentStorage: SecurePersistentStorage) {
        self.authService = authService
        self.securePersistentStorage = securePersistentStorage
    }

    public private(set) lazy var user: User? = loadPersistedUser() {
        didSet {
            persistUserData()
        }
    }

    public func login(username: String, password: String) async throws -> User {
        let user = try await authService.login(username: username, password: password)
        self.user = user
        return user
    }

    /// An auth service instance that is instantiated when the `UserService` is instantiated.
    @Instantiated private let authService: AuthService

    /// An instance of secure, persistent storage that is instantiated further up the dependency tree.
    @Received private let securePersistentStorage: SecurePersistentStorage

    private func loadPersistedUser() -> User? {
        securePersistentStorage["user", ofType: User.self]
    }

    private func persistUserData() {
        securePersistentStorage["user"] = user
    }
}
```

#### Creating the root of your dependency tree

Any type decorated with `@Instantiable(isRoot: true)` is a root of a SafeDI dependency tree. SafeDI creates a no-parameter `public init()` initializer that instantiates the dependency tree in an extension on each root type.

#### Making protocols `@Instantiable`

While it is not necessary to utilize protocols with SafeDI, protocol-driven development aids both testability and dependency inversion. The `@Instantiable` macro has a parameter `fulfillingAdditionalTypes` that enables any concrete `@Instantiable` type to fulfill properties that are declared as conforming to a protocol (or superclass) type. Here’s a sample implementation of a protocol-backed, `@Instantiable` `UserService`:

```swift
import SafeDI

/// A protocol that defines a UserService.
public protocol UserService {
    var user: User? { get }
    func login(username: String, password: String) async throws -> User
}

/// A default implementation of `UserService` that can fulfill `@Instantiated`
/// properties of type `UserService` or `DefaultUserService`.
@Instantiable(fulfillingAdditionalTypes: [UserService.self])
public final class DefaultUserService: UserService, Instantiable {
    ... // Same implementation as above.
}
```

#### Making external types `@Instantiable`

Types that are declared outside of your project can be instantiated by SafeDI if there is an extension on the type decorated with the `@Instantiable` macro. Extensions decorated with this macro define how to instantiate the extended type via a `public static func instantiate(…) -> ExtendedType` function. This `instantiate(…)` function can receive dependencies instantiated or forwarded by objects further up the dependency tree by declaring these dependencies as parameters to the `instantiate(…)` function.

Here we have a sample `@Instantiable` `SecurePersistentStorage` whose concrete type is defined in a third-party dependency:

```swift
import SafeDI
import SecurePersistentStorage // A third-party library that provides secure, persistent storage.

@Instantiable
extension SecurePersistentStorage: Instantiable {
    /// A public static function that defines how SafeDI can instantiate the type.
    public static func instantiate() -> SecurePersistentStorage {
        SecurePersistentStorage()
    }
}
```

#### Making generic types `@Instantiable`

Generic types can be instantiated by SafeDI if there is an extension on the type decorated with the `@Instantiable` macro. Extensions decorated with this macro define how to instantiate the extended type via functions of the form `public static func instantiate(…) -> GenericType<ConcreteType>`.

Here we have a sample `Container<T>` wrapper that is `@Instantiable` when `T` is a common Swift type:

```swift
/// A generic container for a settable value.
public final class Container<T> {
    public init(_ value: T) {
        self.value = value
    }

    public var value: T
}

/// An extension on the Container type that tells SafeDI how to instantiate a `Container<T>` where `T` is a common Swift type.
@Instantiable
extension Container: Instantiable {
    public static func instantiate() -> Container<Bool> {
        Container(false)
    }

    public static func instantiate() -> Container<Int> {
        Container(0)
    }

    public static func instantiate() -> Container<String> {
        Container("")
    }

    public static func instantiate() -> Container<URL?> {
        Container(nil)
    }
}
```

Elsewhere, we make the `Container<T>` type `@Instantiable` when creating a `Container<MyEnum>` type:

```swift
public enum MyEnum {
    …
}

/// An extension on the Container type that tells SafeDI how to instantiate a `Container<MyEnum>`. We tell the `@Instantiable` macro that this type already conforms to the `Instantiable` protocol elsewhere to prevent the macro from requiring that this extension declares a conformance to `Instantiable`.
@Instantiable(conformsElsewhere: true)
extension Container {
    public static func instantiate() -> Container<MyEnum> {
        Container(.defaultValue)
    }
}
```

### @Instantiated

Property declarations within `@Instantiable` types decorated with [`@Instantiated`](../Sources/SafeDI/Decorators/Instantiated.swift) are instantiated when its enclosing type is instantiated. `@Instantiated`-decorated properties are available to be `@Received` by objects instantiated further down the dependency tree.

`@Instantiated`-decorated properties must be an `@Instantiable` type, or of an `additionalType` listed in an `@Instantiable(fulfillingAdditionalTypes:)`’s declaration.

### @Forwarded

Property declarations within `@Instantiable` types decorated with [`@Forwarded`](../Sources/SafeDI/Decorators/Forwarded.swift) represent dependencies that come from the runtime, e.g. user input or backend-delivered content. Like an `@Instantiated`-decorated property, a `@Forwarded`-decorated property is available to be `@Received` by objects instantiated further down the dependency tree.

A `@Forwarded` property is forwarded into the SafeDI dependency tree by a [`Instantiator`](#instantiator)’s `instantiate(_ forwardedProperties: T.ForwardedProperties) -> T` function that creates an instance of the property’s enclosing type.

Forwarded property types do not need to be decorated with the `@Instantiable` macro.

### @Received

Property declarations within `@Instantiable` types decorated with [`@Received`](../Sources/SafeDI/Decorators/Received.swift) are injected into the enclosing type’s initializer. Received properties must be `@Instantiated` or `@Forwarded` by an object higher up in the dependency tree.

Here we have a `LoggedInContentView` in which the forwarded `user` property is received by an `UpdateUserService` further down the dependency tree.

```swift
@Instantiable
public struct LoggedInContentView: View, Instantiable {
    public init(user: User, profileViewBuilder: ErasedInstantiator<(), AnyView>) {
        self.user = user
        self.profileViewBuilder = profileViewBuilder
    }

    public var body: some View {
        ... // Instantiates and displays a ProfileView when a button is pressed.
    }

    @Forwarded private let user: User

    @Instantiated(fulfilledByType: "ProfileView", erasedToConcreteExistential: true) private let profileViewBuilder: ErasedInstantiator<(), AnyView>
}

@Instantiable
public struct ProfileView: View, Instantiable {
    public init(updateUserService: UpdateUserService) {
        self.updateUserService = updateUserService
    }

    public var body: some View {
        ... // Allows for updating user information.
    }

    @Instantiated private let updateUserService: UpdateUserService
}

@Instantiable
public final class UpdateUserService: Instantiable {
    public init(user: User) {
        self.user = user
        urlSession = .shared
    }

    public func updateUserName(to newName: String) async {
        // Updates the user name.
    }

    // The user object which is received from the LoggedInContentView.
    @Received private let user: User

    private let urlSession: URLSession
}
```

#### Renaming and retyping dependencies

It is possible to rename or retype a dependency that is `@Instantiated` or `@Forwarded` by an object higher up in the dependency tree with the `@Received(fulfilledByDependencyNamed:ofType:)` macro. Renamed or retyped dependencies are able to be received with their new name and type by objects instantiated further down the dependency tree.

Here we have an example of a `UserManager` type that is received as a `UserVendor` further down the dependency tree.

```swift
public struct User {
    ... // User information.
}

public protocol UserVendor {
    var user: User { get }
}

public protocol UserManager: UserVendor {
    var user: User { get set }
}

public final class DefaultUserManager: UserManager {
    public init(user: User) {
        self.user = user
    }

    public var user: User
}

import SwiftUI

@Instantiable
public struct LoggedInView: View, Instantiable {
    public init(userManager: UserManager, profileViewBuilder: Instantiator<ProfileView>) {
        self.userManager = userManager
        self.profileViewBuilder = profileViewBuilder
    }

    public var body: some View {
        ... // A logged in user experience
    }

    @Forwarded private let userManager: UserManager

    @Instantiated private let profileViewBuilder: Instantiator<ProfileView>
}

@Instantiable
public struct ProfileView: View, Instantiable {
    public init(userVendor: UserVendor, editProfileViewBuilder: Instantiator<EditProfileView>) {
        self.userVendor = userVendor
        self.editProfileViewBuilder = editProfileViewBuilder
    }

    public var body: some View {
        ... // A profile viewing experience
    }

    @Received(fulfilledByDependencyNamed: "userManager", ofType: UserManager.self) private let userVendor: UserVendor

    @Instantiated private let editProfileViewBuilder: Instantiator<EditProfileView>
}

@Instantiable
public struct EditProfileView: View, Instantiable {
    public init(userVendor: UserVendor) {
        self.userVendor = userVendor
    }

    public var body: some View {
        ... // A profile editing experience
    }

    @Received private let userVendor: UserVendor
}
```

#### Conditionally receiving dependencies

It is possible to receive an optional dependency only when that dependency has been `@Instantiated` or `@Forwarded` by an object higher up in the dependency tree with the `@Received(onlyIfAvailable: true)` macro. This functionality is particularly useful when `@Instantiable` types are created by multiple `@Instantiable` parents with different available dependencies.

Here’s an example of a feed view in a social app that optionally receives a `user` object:

```swift
public struct User {
    ... // User information.
}

import SwiftUI

@Instantiable
public struct LoggedOutView: View, Instantiable {
    public init(feedViewBuilder: Instantiator<FeedView>) {
        self.feedViewBuilder = feedViewBuilder
    }

    public var body: some View {
        ... // A logged out user experience that shows a feed
    }

    @Instantiated private let feedViewBuilder: Instantiator<FeedView>
}

@Instantiable
public struct LoggedInView: View, Instantiable {
    public init(user: User, feedViewBuilder: Instantiator<FeedView>) {
        self.user = user
        self.feedViewBuilder = feedViewBuilder
    }

    public var body: some View {
        ... // A logged in user experience that shows a feed customized for this user
    }

    @Forwarded private let user: User

    @Instantiated private let feedViewBuilder: Instantiator<FeedView>
}

@Instantiable
public struct FeedView: View, Instantiable {
    public init(user: User?) {
        self.user = user
    }

    public var body: some View {
        ... // A feed experience that is customized when a user is present.
    }

    @Received(onlyIfAvailable: true) private let user: User?
}
```

## Delayed instantiation

When you want to instantiate a dependency after `init(…)`, you need to declare an `Instantiator<Dependency>`-typed property as `@Instantiated` or `@Received`. Deferred instantiation is useful in situations where a dependency is expensive to create or only required under certain conditions (e.g., creating a detailed view for a selected item in a list).

### Instantiator

The [`Instantiator`](../Sources/SafeDI/DelayedInstantiation/Instantiator.swift) type is how SafeDI enables deferred instantiation of an `@Instantiable` type. `Instantiator` has a single generic that matches the type of the to-be-instantiated instance. Creating an `Instantiator` property is as simple as creating any other property in the SafeDI ecosystem:

```swift
@Instantiable(isRoot: true)
public struct MyApp: App, Instantiable {
    public init(contentViewInstantiator: Instantiator<ContentView>) {
        self.contentViewInstantiator = contentViewInstantiator
    }

    public var body: some Scene {
        WindowGroup {
            // Returns a new instance of a `ContentView`.
            contentViewInstantiator.instantiate()
        }
    }

    /// A private property that knows how to instantiate a content view.
    @Instantiated private let contentViewInstantiator: Instantiator<ContentView>
}
```

An `Instantiator` is not `Sendable`: if you want to be able to share an instantiator across concurrency domains, use a [`SendableInstantiator`](../Sources/SafeDI/DelayedInstantiation/SendableInstantiator.swift).

### Utilizing @Instantiated with type erased properties

When you want to instantiate a type-erased property, you may specify which concrete type you expect to fulfill your property by utilizing `@Instantiated`’s `fulfilledByType` and `erasedToConcreteExistential` parameters.

The `fulfilledByType` parameter takes a string literal identical to the type name of the concrete type that will be assigned to the type-erased property. Representing the type as a string allows for dependency inversion: the code that receives the concrete type does not need to have a dependency on the module that defines the concrete type.

The `erasedToConcreteExistential` parameter takes a boolean value that indicates whether the fulfilling type is being erased to a concrete [existential](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/opaquetypes/#Boxed-Protocol-Types) type. A concrete existential type is a non-protocol type that wraps a protocol and is usually prefixed with `Any`. A fulfilling type does not inherit from a concrete existential type, and therefore when the property’s type is a concrete existential the fulfilling type must be wrapped in the erasing concrete existential type’s initializer before it is returned. When the property’s type is not a concrete existential, the fulfilling type is cast as the property’s type. For example, an `AnyView` is a concrete and existential type-erased form of some `struct MyExampleView: View`, while a `UIViewController` is a concrete but not existential type-erased form of some `final class MyExampleViewController: UIViewController`. This parameter defaults to `false`.

The [`ErasedInstantiator`](../Sources/SafeDI/DelayedInstantiation/ErasedInstantiator.swift) type is how SafeDI enables instantiating any `@Instantiable` type when using type erasure. `ErasedInstantiator` has two generics. The first generic must match the type’s `ForwardedProperties` typealias. The second generic matches the type of the to-be-instantiated instance. An `ErasedInstantiator` is not `Sendable`: if you want to be able to share an erased instantiator across concurrency domains, use a [`SendableErasedInstantiator`](../Sources/SafeDI/DelayedInstantiation/SendableErasedInstantiator.swift).

```swift
import SwiftUI

@Instantiable
public struct ParentView: View, Instantiable {
    public init(childViewBuilder: ErasedInstantiator<(), AnyView>) {
        self.childViewBuilder = childViewBuilder
    }

    public var body: some View {
        VStack {
            Text("Child View")
            childViewBuilder.instantiate()
        }
    }

    // The ErasedInstantiator `instantiate()` function will build a `ChildView` wrapped in a concrete `AnyView`.
    // All that is required for this code to compile is for there to be an
    // `@Instantiable public struct ChildView: View` in the codebase.
    @Instantiated(fulfilledByType: "ChildView", erasedToConcreteExistential: true) private let childViewBuilder: ErasedInstantiator<(), AnyView>
}
```

## Comparing SafeDI and Manual Injection: Key Differences

SafeDI is designed to be simple to adopt and minimize architectural changes required to get the benefits of a compile-time safe DI system. Despite this design goal, there are a few key differences between projects that utilize SafeDI and projects that don’t. As the benefits of this system are clearly outlined in the [Features](../README.md#features) section above, this section outlines the pattern changes required to utilize a DI system like SafeDI.

### Instantiating objects

In a manual DI system it is common to directly call your dependencies’ `init(…)` functions. When utilizing SafeDI, you must rely on `@Instantiated`-decorated properties to instantiate your dependencies for you. Calling a dependency’s `init(…)` function directly effectively exits the SafeDI-built dependency tree, which removes property lifecycle guarantees. Similarly, you must call the generated `init()` function on your dependency tree’s root and not its memberwise `init(…)` function in order to create the SafeDI dependency tree.

To instantiate a dependency after a property’s enclosing type is initialized, you must utilize an instantiated or received [`Instantiator`](#delayed-instantiation).

### SwiftUI

Per Apple’s documentation, it is important to avoid decorating initializer-injected dependencies with the [`@State`](https://developer.apple.com/documentation/swiftui/state) or [`@StateObject`](https://developer.apple.com/documentation/swiftui/stateobject) property wrappers.

The `@State` documentation reads:

> Declare state as private to prevent setting it in a memberwise initializer, which can conflict with the storage management that SwiftUI provides

The `@StateObject` documentation reads:

> Declare state objects as private to prevent setting them from a memberwise initializer, which can conflict with the storage management that SwiftUI provides

`@Instantiated`, `@Forwarded`, or `@Received` objects may be decorated with [`@ObservedObject`](https://developer.apple.com/documentation/swiftui/ObservedObject). Keep in mind that `@Instantiated` objects in a `View` are re-initialized each time the view is recreated by SwiftUI. You can find a deep dive on SwiftUI view lifecycles [here](https://www.donnywals.com/understanding-how-and-when-swiftui-decides-to-redraw-views/).

### Inheritance

In a manual DI system it is simple for superclasses to receive injected dependencies. SafeDI’s utilization of macros means that SafeDI is not aware of dependencies required due to inheritance trees. Due to this limitation, superclass types should not be decorated with `@Instantiable`: instead, subclasses should declare the properties their superclasses need, and pass them upwards via a call to `super.init(…)`.

## Migrating to SafeDI

It is strongly recommended that projects adopting SafeDI start their migration by identifying the root of their dependency tree and making it `@Instantiable(isRoot: true)`. Once your root object has adopted SafeDI, continue migrating dependencies to SafeDI in either a breadth-first or depth-first manner. As your adoption of SafeDI progresses, you’ll find that you are removing more code than you are adding: many of your dependencies are likely being passed through intermediary objects that do not utilize the dependency except to instantiate a dependency deeper in the tree. Once types further down the dependency tree have adopted SafeDI, you will be able to avoid receiving dependencies in intermediary types.

### Selecting a root in SwiftUI applications

SwiftUI applications have a natural root: the `App`-conforming type that is initialized when the binary is launched.

### Selecting a root in UIKit applications

UIKit applications’ natural root is the `UIApplicationDelegate`-conforming app delegate, however, this type inherits from the Objective-C `NSObject` which already has a no-argument `init()`. As such, it is best to create a custom `@Instantiable(isRoot: true) public final class Root: Instantiable` type that is initialized and stored by the application’s app delegate.

## Example applications

We’ve tied everything together with an example multi-user notes application backed by SwiftUI. You can compile and run this code in [an example single-module Xcode project](../Examples/ExampleProjectIntegration). This same multi-user notes app also exists in [an example multi-module Xcode project](../Examples/ExampleMultiProjectIntegration), and also in [an example Xcode project using CocoaPods](../Examples/ExampleCocoaPodsIntegration). We have also created [an example multi-module `Package.swift` that integrates with SafeDI](../Examples/ExamplePackageIntegration).

## Under the hood

SafeDI has a `SafeDITool` executable that the `SafeDIGenerator` plugin utilizes to read code and generate a dependency tree. The tool utilizes Apple’s [SwiftSyntax](https://github.com/apple/swift-syntax) library to parse your code and find your `@Instantiable` types’ initializers and dependencies. With this information, SafeDI generates a graph of your project’s dependencies, validates it during `SafeDITool` execution, and provides clear, human-readable error messages if the graph is invalid. Source code is only generated if the dependency graph is valid.

The executable heavily utilizes asynchronous processing to avoid `SafeDITool` becoming a bottleneck in your build. Additionally, we only parse a Swift file with `SwiftSyntax` when the file contains the string `Instantiable`.

Due to limitations in Apple’s [Swift Package Manager Plugins](https://github.com/apple/swift-package-manager/blob/main/Documentation/Plugins.md), the `SafeDIGenerator` plugin parses all of your first-party Swift files in a single pass. Projects that utilize `SafeDITool` directly can process Swift files on a per-module basis to further reduce the build-time bottleneck.

## Introspecting a SafeDI tree

You can create a [GraphViz DOT file](https://graphviz.org/doc/info/lang.html) to introspect a SafeDI dependency tree by running `swift run SafeDITool` and utilizing the `--dot-file-output` parameter. This command will create a `DOT` file that you can pipe into `GraphViz`’s `dot` command to create a pdf.

Once you have the dot file, you can run:
```bash
dot path_to_dot_file.dot -Tpdf > path_to_pdf_file.pdf
```

You can find instructions for how to install the `dot` command [here](https://graphviz.org/download/).
