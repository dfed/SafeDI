# SafeDI

[![CI Status](https://img.shields.io/github/actions/workflow/status/dfed/SafeDI/ci.yml?branch=main)](https://github.com/dfed/SafeDI/actions?query=workflow%3ACI+branch%3Amain)
[![Swift Package Manager compatible](https://img.shields.io/badge/SPM-✓-4BC51D.svg?style=flat)](https://github.com/apple/swift-package-manager)
[![codecov](https://codecov.io/gh/dfed/SafeDI/branch/main/graph/badge.svg)](https://codecov.io/gh/dfed/SafeDI)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://spdx.org/licenses/MIT.html)

Compile-time safe dependency injection for Swift projects.

## Features

✅ Compile-time safe

✅ Thread safe

✅ Hierarchical dependency scoping

✅ Constructor injection

✅ Multi-module support

✅ Dependency inversion support

✅ Transitive dependency solving

✅ Cycle detection

✅ Architecture independent

✅ Simple integration: no DI-specific types or generics required

✅ Easy testing: every type has a memberwise initializer

✅ Clear error messages: never debug generated code

## Using SafeDI

SafeDI utilizes Swift Macros and Swift Package Manager plugins to read your code and generate a dependency tree that is validated at compile time. Dependencies can either be instantiated by SafeDI or forwarded into the SafeDI dependency tree.

Opting a type into the SafeDI dependency tree is straightforward: add the `@Instantiable` macro to your type declaration, and decorate your type‘s dependencies with macros that signal the lifecycle of each property. Decorate a property with `@Instantiated` if you want to initialize it when the enclosing type is initialized; `@Forwarded` if you want to propagate a runtime-determine value down the dependency tree; or `@Received` if you want to receive the property from an `@Instantiated` or `@Forwarded` property further up the dependency tree.

If a type is declared in third-party code, you can declare an extension the type in your code and decorate it with the `@ExternalInstantiable` macro to opt it into SafeDI.

Let‘s walk through each of these macros in detail.

### @Instantiable

Type declarations decorated with the [`@Instantiable` macro](Sources/SafeDI/PropertyDecoration/Instantiable.swift) are able to be instantiated by SafeDI. Types decorated with this macro can instantiate other `@Instantiable` dependencies, forward dependencies injected from outside of SafeDI, or receive dependencies instantiated or forwarded by objects further up the dependency tree.

Every `@Instantiable`-decorated type must be:

1. `public` or `open`

2. Have a `public init(…)` or `open init(…)` method that receives every injectable property

The `@Instantiable` guides engineers through satisfying these requirements with build-time FixIts.

#### Example

Here is a sample `UserService` implementation that is `@Instantiable`:

```swift
import SafeDI

/// A protocol that defines a UserService.
/// It is not necessary to utilize protocols with SafeDI, but since
/// protocol-driven development aids both testability and dependency
/// inversion, our examples show how protocols can be used with SafeDI.
public protocol UserService {
    var user: User? { get }
    func login(username: String, password: String) async throws -> User
}

/// A default implementation of `UserService` that can fulfill `@Instantiated`
/// properties of type `UserService` or `DefaultUserService`.
@Instantiable(fulfillingAdditionalTypes: [UserService.self])
public final class DefaultUserService: UserService {

    // MARK: Initialization

    /// Public, memberwise initializer that takes each injected property.
    public init(authService: AuthService, securePersistentStorage: SecurePersistentStorage) {
        self.authService = authService
        self.securePersistentStorage = securePersistentStorage
    }

    // MARK: UserService

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

    // MARK: Private

    /// An auth service instance that is instantiated when the `DefaultUserService` is instantiated.
    @Instantiated
    private let authService: AuthService

    /// An instance of secure, persistent storage that is instantiated further up the SafeDI dependency tree.
    @Received
    private let securePersistentStorage: SecurePersistentStorage

    private func loadPersistedUser() -> User? {
        securePersistentStorage["user", ofType: User.self]
    }

    private func persistUserData() {
        securePersistentStorage["user"] = user
    }
}
```

### @ExternalInstantiable

Types that are declared outside of your project can be instantiated by SafeDI if there is an extension on the type decorated with the [`@ExternalInstantiable` macro](Sources/SafeDI/PropertyDecoration/ExternalInstantiable.swift). Extensions decorated with this macro define how to instantiate the extended type via a `public func instantiate(…) -> ExtendedType` method. This `instantiate(…)` method can receive dependencies instantiated or forwarded by objects further up the dependency tree by declaring these dependencies as method arguments.

#### Example

Here is a sample `SecurePersistentStorage` protocol whose concrete type is defined in a third-party dependency, and therefore is `@ExternalInstantiable`:

```swift
import Foundation
import SafeDI
import Valet // A Keychain wrapper that can be used to implement secure, persistent storage. github.com/square/valet

/// A protocol defining how to interact with secure, persistent storage.
/// It is not necessary to utilize protocols with SafeDI, but since
/// protocol-driven development aids both testability and dependency
/// inversion, our examples show how protocols can be used with SafeDI.
protocol SecurePersistentStorage {
    subscript<CodableType: Codable>(_ key: String, ofType type: CodableType.Type) -> CodableType? { get }
    subscript<CodableType: Codable>(_ key: String) -> CodableType? { get set }
}

/// A default implementation of `SecurePersistentStorage` that can fulfill
/// `@Instantiated` properties of type `Valet` or `SecurePersistentStorage`.
@ExternalInstantiable(fulfillingAdditionalTypes: [SecurePersistentStorage.self])
extension Valet: SecurePersistentStorage {

    /// A public initializer defines how SafeDI can instantiate a Valet object.
    public static func instantiate() -> Valet {
        Valet.valet(
            with: Identifier(nonEmpty: "SafeDIExample")!,
            accessibility: .afterFirstUnlock
        )
    }

    subscript<CodableType: Codable>(_ key: String, ofType type: CodableType.Type) -> CodableType? {
        guard let data = try? object(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    subscript<CodableType: Codable>(key: String) -> CodableType? {
        get {
            self[key, ofType: CodableType.self]
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                try? setObject(data, forKey: key)
            } else {
                try? removeObject(forKey: key)
            }
        }
    }
}
```

### @Instantiated

Property declarations within [`@Instantiable`](#instantiable) types decorated with the [`@Instantiated` macro](Sources/SafeDI/PropertyDecoration/Instantiated.swift) are instantiated when its enclosing type is instantiated. `@Instantiated`-decorated properties are available to be [`@Received`](#received) by objects instantiated further down the dependency tree.

`@Instantiated`-decorated properties must declared as an `@Instantiable` type, or of an `additionalType` listed in a `@Instantiable(fulfillingAdditionalTypes:)`‘s declaration.

#### Utilizing @Instantiated with type erased properties

When you want to instantiate a type-erased property, you may specify which concrete type you expect to fulfill your property by utilizing `@Instantiated`‘s `fulfilledByType` parameter.

The `fulfilledByType` parameter takes a `String` of the name of the concrete type that will be assigned to the type-erased property. Representing the type as a string literal allows for dependency inversion: the code that receives the concrete type does not need to have a dependency on the module that defines the concrete type.

```swift
import SwiftUI

@Instantiable
public struct ParentView: View {
    public var body: some View {
        VStack {
            Text("Child View")
            childViewBuilder.instantiate()
        }
    }

    public init(childViewBuilder: Instantiator<some View>) {
        self.childViewBuilder = childViewBuilder
    }

    // The Instantiator‘s `instantiate()` method will build a view of type `ChildView`.
    // Because the type is passed in as a string literal, this code does not need to
    // have a dependency on the module that defines `ChildView`. All that is required
    // for this code to compile is for there to be an
    // `@Instantiable public struct ChildView: View` in the codebase.
    @Instantiated(fulfilledByType: "ChildView")
    private let childViewBuilder: Instantiator<some View>
}
```

### @Forwarded

Property declarations within [`@Instantiable`](#instantiable) types decorated with the [`@Forwarded` macro](Sources/SafeDI/PropertyDecoration/Forwarded.swift) are forwarded into the SafeDI dependency tree by a [`ForwardingInstantiator`](Sources/SafeDI/DelayedInstantiation/ForwardingInstantiator.swift) instance’s `instantiate(…)` method. A `@Forwarded`-decorated property is available to be [`@Received`](#received) by objects instantiated further down the dependency tree.

A single `@Instantiable` type may have at most one `@Forwarded`-decorated property.

### @Received

Property declarations within [`@Instantiable`](#instantiable) types decorated with the [`@Received` macro](Sources/SafeDI/PropertyDecoration/Received.swift) are injected into the enclosing type‘s initializer. Received properties must be [`@Instantiated`](#instantiated) or [`@Forwarded`](#forwarded) by an object higher up in the dependency tree.

### Delayed instantiation

When you want to instantiate a dependency after your `init(…)`, you need to declare an `Instantiator<Dependency>`-typed property as `@Instantiated` or `@Received`.

#### Instantiator

The `Instantiator` type is how SafeDI enables deferred instantiation of an `@Instantiable` type. `Instantiator` has a single generic that matches the type of the to-be-instantiated instance. Creating an `Instantiator` property is as simple as creating any other property in the SafeDI ecosystem:

```swift
@Instantiable
public struct MyApp: App {
    public var body: some Scene {
        WindowGroup {
            // Returns a new instance of a `ContentView`.
            contentViewInstantiator.instantiate()
        }
    }

    public init(contentViewInstantiator: Instantiator<ContentView>) {
        self.contentViewInstantiator = contentViewInstantiator
    }

    /// A private property that knows how to instantiate a content view.
    @Instantiated
    private let contentViewInstantiator: Instantiator<ContentView>
}
```

It is possible to write a `Instantiator` with a type-erased generic by utilizing `@Instantiated`‘s `fulfilledByType` parameter.

#### ForwardingInstantiator

The `ForwardingInstantiator` type is how SafeDI enables instantiating any `@Instantiable` type with a `@Forwarded` property. `ForwardingInstantiator` has two generics. The first generic must match the type of the `@Forwarded` property. The second generic matches the type of the to-be-instantiated instance.

```swift
@Instantiable
public struct MyApp: App {
    public var body: some Scene {
        WindowGroup {
            if let user = userService.user {
                // Returns a new instance of a `LoggedInContentView`.
                loggedInContentViewInstantiator.instantiate(user)
            } else {
                // Returns a new instance of a `LoggedOutContentView`.
                loggedOutContentViewInstantiator.instantiate()
            }
        }
    }

    public init(loggedInContentViewInstantiator: ForwardingInstantiator<User, LoggedOutContentView>, loggedOutContentViewInstantiator: Instantiator<LoggedOutContentView>, userService: UserService) {
        self.loggedInContentViewInstantiator = loggedInContentViewInstantiator
        self.loggedOutContentViewInstantiator = loggedOutContentViewInstantiator
        self.userService = userService
    }

    /// A private property that knows how to instantiate a logged-in content view.
    @Instantiated
    private let loggedInContentViewInstantiator: ForwardingInstantiator<User, LoggedOutContentView>

    /// A private property that knows how to instantiate a logged-out content view.
    @Instantiated
    private let loggedOutContentViewInstantiator: Instantiator<LoggedOutContentView>

    @ObservedObject
    @Instantiated
    private var userService: UserService
}
```

It is possible to write a `ForwardingInstantiator` with a type-erased second generic by utilizing `@Instantiated`‘s `fulfilledByType` parameter.

### Creating the root of your dependency tree

SafeDI automatically finds the root(s) of your dependency tree, and creates an extension on each root that contains a `public init()` method that instantiates the dependency tree.

An `@Instantiable` type qualifies as the root of a dependency tree if and only if:

1. The type‘s SafeDI-injected properties are all `@Instantiated`
2. The type is not instantiated by another `@Instantiable` type

### Comparing SafeDI and Manual Injection: Key Differences

SafeDI is designed to be simple to adopt and minimize architectural changes required to get the benefits of a compile-time safe DI system. Despite this design goal, there are a few key differences between projects that utilize SafeDI and projects that don‘t. As the benefits of this system are clearly outlined in the [Features](#features) section above, this section outlines the pattern changes required to utilize a DI system like SafeDI.

#### Instantiating objects

In a manual DI system, it is common to directly call your dependencies‘ `init(…)` methods. When utilizing SafeDI, you must rely on `@Instantiated`-decorated properties to instantiate your dependencies for you. Calling a dependency‘s `init(…)` method directly effectively exits the SafeDI-built dependency tree.

To instantiate a dependency after a property‘s enclosing type is initialized, you must utilize an instantiated or received `Instantiator` or `ForwardingInstantiator` instance.  

#### SwiftUI

It is important to avoid decorating initializer-injected dependencies with the [`@State`](https://developer.apple.com/documentation/swiftui/state) and [`@StateObject`](https://developer.apple.com/documentation/swiftui/stateobject) property wrappers. Apple‘s documentation for both of these property wrappers makes it clear.

The `@State` documentation reads:

> Declare state as private to prevent setting it in a memberwise initializer, which can conflict with the storage management that SwiftUI provides

The `@StateObject` documentation reads:

> Declare state objects as private to prevent setting them from a memberwise initializer, which can conflict with the storage management that SwiftUI provides

`@Instantiated`, `@Forwarded`, or `@Received` objects may be decorated with [`@ObservedObject`](https://developer.apple.com/documentation/swiftui/ObservedObject) instead of `@StateObject`. Note that `@Instantiated` objects will be re-initialized when a view‘s parent view is invalidated.

### Migrating to SafeDI

It is strongly recommended that projects adopting SafeDI start their migration by identifying the root of their dependency tree and making it `@Instantiable`. Once your root object has adopted SafeDI, continue migrating dependencies to SafeDI in either a breadth-first or depth-first manner. As your adoption of SafeDI progression, you‘ll find that you are removing more code than you are adding: many of your dependencies are likely being passed through intermediary objects that do not utilize the dependency except to instantiate a dependency deeper in the tree. Once types further down the dependency tree have adopted SafeDI, you will be able to avoid receiving dependencies in intermediary types.

## Example App

We‘ve tied everything together with an example multi-user notes application backed by SwiftUI. You compile and run this code in Xcode in the included [ExampleProjectIntegration](Examples/ExampleProjectIntegration) project.

## Integrating SafeDI

To integrate SafeDI into your codebase, you must both depend on the SafeDI framework that defines the core macros and instantiators, and also add the code generation step to your build process. You can see sample integrations in the [Examples](Examples/) folder.

### SafeDI Framework

To install the SafeDI framework into your package with [Swift Package Manager](https://github.com/apple/swift-package-manager), add the following lines to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/dfed/SafeDI", from: "0.1.0"),
]
```

To install the SafeDI framework into an Xcode project with Swift Package Manager, follow [Apple‘s instructions](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) to add the `https://github.com/dfed/SafeDI` dependency to your application.

### SafeDI Code Generation

SafeDI vends a code generation plugin named `SafeDIGenerator`. This plugin works out of the box on a limited number of project configurations. If your project does not fall into these well-supported configurations, you can configure your build to utilize the `SafeDITool` command-line executable directly.

#### Single-module Xcode projects

If your first-party code comprises a single module in an `.xcodeproj`, once your Xcode project depends on the SafeDI package you can integrate the Swift Package Plugin simply by going to your target‘s `Build Phases`, expanding the `Run Build Tool Plug-ins` drop-down, and adding the `SafeDIGenerator` as a build tool plug-in. You can see this integration in practice in the [ExampleProjectIntegration](Examples/ExampleProjectIntegration) project.

#### Swift Package

If your first-party code is entirely contained in a Swift Package with one or more modules, you can add the following lines to your root target‘s definition:

```swift
    plugins: [
        .plugin(name: "SafeDIGenerator", package: "SafeDI")
    ]
```

You can see this in integration in practice in the [ExamplePackageIntegration](Examples/ExamplePackageIntegration) package.

#### Other configurations

If your first-party code comprises multiple modules in Xcode, or a mix of Xcode Projects and Swift Packages, or some other configuration not listed above, you will need to utilize the `SafeDITool` command-line executable directly.

The `SafeDITool` utility is designed to able to be integrated into projects of any size or shape.

You can build the SafeDI tool locally by running the following command at the root of this repository:
```zsh
swift build -c release
```

Once you‘ve built the tool, you can see the tool‘s expected arguments by running:
```zsh
$(swift build -c release --target SafeDITool --show-bin-path)/SafeDITool --help
```

The `SafeDITool` can parse all of your Swift files at once, or for better performance the tool can be run on each dependent module as part of the build. Integrating this tool into your project is currently left as an exercise to the reader. SafeDI would welcome a better documented approach or tool for integrating SafeDI into currently unsupported projects.

### Requirements

* Xcode 15.0 or later
* iOS 13 or later
* tvOS 13 or later
* watchOS 6 or later
* macOS 10.13 or later

## Under the hood

SafeDI has a `SafeDITool` executable that the `SafeDIGenerator` plugin utilizes to read code and generate a dependency tree. The tool utilizes Apple‘s [SwiftSyntax](https://github.com/apple/swift-syntax) library to parse your code and find your `@Instantiable` types‘ initializers and dependencies. With this information, SafeDI creates a directed, acyclic graph of your project‘s dependencies. This graph is validated as part of the `SafeDITool`‘s execution, and the tool emits human-readible errors if the dependency graph is not valid. Source code is only generated if the dependency graph is valid.

The executable heavily utilizes asynchronous processing to avoid `SafeDITool` becoming a bottleneck in your build. Additionally, we only parse a Swift file with `SwiftSyntax` when the file contains the string `Instantiable`.

Due to limitations in Apple‘s [Swift Package Manager Plugins](https://github.com/apple/swift-package-manager/blob/main/Documentation/Plugins.md), the `SafeDIGenerator` plugin parses all of your first-party Swift files in a single pass. Projects that utilize `SafeDITool` directly can process Swift files on a per-module basis to further reduce the build-time bottleneck.

## Comparing SafeDI to other DI libraries

SafeDI‘s compile-time-safe design makes it similar to [Needle](https://github.com/uber/needle) and [Weaver](https://github.com/scribd/Weaver). Unlike Needle, SafeDI does not require defining dependency protocols for each DI-tree-instantiable type. SafeDI‘s capabilities are quite similar to Weaver‘s, with the biggest difference being that SafeDI supports codebases with multiple modules. Beyond those differences, SafeDI vs Needle vs Weaver is a matter of personal preference.

Other Swift DI libraries like [Swinject](https://github.com/Swinject/Swinject) and [Cleanse](https://github.com/square/Cleanse) do not offer compile-time safety, though other features are similar. A primary benefit of the SafeDI library is that compilation validates your dependency tree.

## Acknowledgements

Huge thanks to [@kierajmumick](http://github.com/kierajmumick) for helping hone the early design of SafeDI.

## Developing

Double-click on the `Package.swift` file in the root of the repository to open the package in Xcode.

## Contributing

I’m glad you’re interested in SafeDI, and we‘d love to see where you take it. Please read the [contributing guidelines](Contributing.md) prior to submitting a Pull Request.

Thanks, and happy injecting!
