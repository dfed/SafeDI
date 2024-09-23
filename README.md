# SafeDI

[![CI Status](https://img.shields.io/github/actions/workflow/status/dfed/SafeDI/ci.yml?branch=main)](https://github.com/dfed/SafeDI/actions?query=workflow%3ACI+branch%3Amain)
[![codecov](https://codecov.io/gh/dfed/SafeDI/branch/main/graph/badge.svg)](https://codecov.io/gh/dfed/SafeDI)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://spdx.org/licenses/MIT.html)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fdfed%2FSafeDI%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/dfed/SafeDI)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fdfed%2FSafeDI%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/dfed/SafeDI)

Compile-time safe dependency injection for Swift projects. SafeDI is built for engineers who want the safety and simplicity of manual dependency injection without the overhead of boilerplate code.

## Features

- [x] Compile-time safe

- [x] Thread safe

- [x] Hierarchical dependency scoping

- [x] Constructor injection

- [x] Multi-module support

- [x] Dependency inversion support

- [x] Transitive dependency solving

- [x] Cycle detection

- [x] Architecture independent

- [x] Simple integration: no DI-specific types or generics required

- [x] Easy testing: every type has a memberwise initializer

- [x] Clear error messages: never debug generated code

## Using SafeDI

SafeDI utilizes Swift Macros and Swift Package Manager plugins to read your code and generate a dependency tree that is validated at compile time. Dependencies can either be instantiated by SafeDI or forwarded into the SafeDI dependency tree.

Opting a type into the SafeDI dependency tree is straightforward: add the `@Instantiable` macro to your type declaration, and decorate your type‘s dependencies with macros that signal the lifecycle of each property. If a type is declared in third-party code, you can opt it into SafeDI by declaring an extension of the type in your code and decorating it with the same `@Instantiable` macro.

There are a total of four macros in the SafeDI library:

| Macro  | Decorating | Usage |
| ------ | ----------- | ----- |
| [`@Instantiable`](#instantiable) | Type or extension declaration | Makes a type capable of being instantiated by SafeDI. |
| [`@Instantiated`](#instantiated) | Property declaration | Instantiates an instance or value when the enclosing `@Instantiable`-decorated type is instantiated. |
| [`@Forwarded`](#forwarded) | Property declaration | Propagates a runtime-created instance or value (e.g. a User object, network response, or customer input) down the dependency tree. |
| [`@Received`](#received) | Property declaration | Receives an instance or value from an `@Instantiated` or `@Forwarded` property further up the dependency tree. |

Let‘s walk through each of these macros in detail.

### @Instantiable

Type declarations decorated with [`@Instantiable`](Sources/SafeDI/PropertyDecoration/Instantiable.swift) are able to be instantiated by SafeDI. Types decorated with this macro can instantiate other `@Instantiable` dependencies, forward dependencies injected from outside of SafeDI, or receive dependencies instantiated or forwarded by objects further up the dependency tree.

SafeDI is designed to make instantiating and receiving dependencies _simple_, without requiring engineers to think about abstract dependency injection (DI) concepts. That said, for those familiar with other DI systems: each `@Instantiable` type is its own [Scope](https://medium.com/@aarontharris/scope-dependency-injection-6fc25beffc9c). For those unfamiliar with DI terminology, know that each `@Instantiable` type is responsible for retaining its dependencies, and that every `@Instantiated` or `@Forwarded` dependency is available to all transitive child dependencies.  

Every `@Instantiable`-decorated type must be:

1. `public` or `open`

2. Have a `public init(…)` or `open init(…)` that has an argument for every injectable property and no other arguments

The `@Instantiable` macro guides engineers through satisfying these requirements with code generation and build-time FixIts.

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

    /// An instance of secure, persistent storage that is instantiated further up the SafeDI dependency tree.
    @Received private let securePersistentStorage: SecurePersistentStorage

    private func loadPersistedUser() -> User? {
        securePersistentStorage["user", ofType: User.self]
    }

    private func persistUserData() {
        securePersistentStorage["user"] = user
    }
}
```

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

Types that are declared outside of your project can be instantiated by SafeDI if there is an extension on the type decorated with the `@Instantiable` macro. Extensions decorated with this macro define how to instantiate the extended type via a `public static func instantiate(…) -> ExtendedType` function. This `instantiate(…)` function can receive dependencies instantiated or forwarded by objects further up the dependency tree by declaring these dependencies as arguments to the `instantiate(…)` function.

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

### @Instantiated

Property declarations within `@Instantiable` types decorated with [`@Instantiated`](Sources/SafeDI/PropertyDecoration/Instantiated.swift) are instantiated when its enclosing type is instantiated. `@Instantiated`-decorated properties are available to be `@Received` by objects instantiated further down the dependency tree.

`@Instantiated`-decorated properties must be an `@Instantiable` type, or of an `additionalType` listed in an `@Instantiable(fulfillingAdditionalTypes:)`‘s declaration.

### @Forwarded

Property declarations within `@Instantiable` types decorated with [`@Forwarded`](Sources/SafeDI/PropertyDecoration/Forwarded.swift) represent dependencies that come from the runtime, e.g. user input or backend-delivered content. Like an `@Instantiated`-decorated property, a `@Forwarded`-decorated property is available to be `@Received` by objects instantiated further down the dependency tree.

A `@Forwarded` property is forwarded into the SafeDI dependency tree by a [`Instantiator`](#instantiator)’s `instantiate(_ forwardedProperties: T.ForwardedProperties) -> T` function that creates an instance of the property’s enclosing type.

Forwarded property types do not need to be decorated with the `@Instantiable` macro.

### @Received

Property declarations within `@Instantiable` types decorated with [`@Received`](Sources/SafeDI/PropertyDecoration/Received.swift) are injected into the enclosing type‘s initializer. Received properties must be `@Instantiated` or `@Forwarded` by an object higher up in the dependency tree.

Here we have a `LoggedInContentView` whose forwarded `user` property is received by an `UpdateUserService` further down the dependency tree.

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

### Delayed instantiation

When you want to instantiate a dependency after `init(…)`, you need to declare an `Instantiator<Dependency>`-typed property as `@Instantiated` or `@Received`.

#### Instantiator

The [`Instantiator`](Sources/SafeDI/DelayedInstantiation/Instantiator.swift) type is how SafeDI enables deferred instantiation of an `@Instantiable` type. `Instantiator` has a single generic that matches the type of the to-be-instantiated instance. Creating an `Instantiator` property is as simple as creating any other property in the SafeDI ecosystem:

```swift
@Instantiable
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

An `Instantiator` is not `Sendable` – if you want to be able to share an instantiator across concurrency domains, use a [`SendableInstantiator`](Sources/SafeDI/DelayedInstantiation/SendableInstantiator.swift).

#### Utilizing @Instantiated with type erased properties

When you want to instantiate a type-erased property, you may specify which concrete type you expect to fulfill your property by utilizing `@Instantiated`‘s `fulfilledByType` and `erasedToConcreteExistential` parameters.

The `fulfilledByType` parameter takes a `String` identical to the type name of the concrete type that will be assigned to the type-erased property. Representing the type as a string literal allows for dependency inversion: the code that receives the concrete type does not need to have a dependency on the module that defines the concrete type.

The `erasedToConcreteExistential` parameter takes a boolean value that indicates whether the fulfilling type is being erased to a concrete [existential](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/opaquetypes/#Boxed-Protocol-Types) type. A concrete existential type is a non-protocol type that wraps a protocol and is usually prefixed with `Any`. A fulfilling type does not inherit from a concrete existential type, and therefore when the property‘s type is a concrete existential the fulfilling type must be wrapped in the erasing concrete existential type‘s initializer before it is returned. When the property‘s type is not a concrete existential, the fulfilling type is cast as the property‘s type. For example, an `AnyView` is a concrete and existential type-erased form of some `struct MyExampleView: View`, while a `UIViewController` is a concrete but not existential type-erased form of some `final class MyExampleViewController: UIViewController`. This parameter defaults to `false`.

The [`ErasedInstantiator`](Sources/SafeDI/DelayedInstantiation/ErasedInstantiator.swift) type is how SafeDI enables instantiating any `@Instantiable` type when using type erasure. `ErasedInstantiator` has two generics. The first generic must match the type’s `ForwardedProperties` typealias. The second generic matches the type of the to-be-instantiated instance. An `ErasedInstantiator` is not `Sendable` – if you want to be able to share an erased instantiator across concurrency domains, use a [`SendableErasedInstantiator`](Sources/SafeDI/DelayedInstantiation/SendableErasedInstantiator.swift).

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

### Creating the root of your dependency tree

SafeDI automatically finds the root(s) of your dependency tree, and creates an extension on each root that contains a `public init()` function that instantiates the dependency tree.

An `@Instantiable` type qualifies as the root of a dependency tree if and only if:

1. The type‘s SafeDI-injected properties are all `@Instantiated` or `@Received(fulfilledByDependencyNamed:ofType:)`
2. The type‘s `@Received(fulfilledByDependencyNamed:ofType:)` properties can be fulfilled by `@Instantiated` or `@Received(fulfilledByDependencyNamed:ofType:)` properties declared on this type
3. The type is not instantiated by another `@Instantiable` type

### Comparing SafeDI and Manual Injection: Key Differences

SafeDI is designed to be simple to adopt and minimize architectural changes required to get the benefits of a compile-time safe DI system. Despite this design goal, there are a few key differences between projects that utilize SafeDI and projects that don‘t. As the benefits of this system are clearly outlined in the [Features](#features) section above, this section outlines the pattern changes required to utilize a DI system like SafeDI.

#### Instantiating objects

In a manual DI system it is common to directly call your dependencies‘ `init(…)` functions. When utilizing SafeDI, you must rely on `@Instantiated`-decorated properties to instantiate your dependencies for you. Calling a dependency‘s `init(…)` function directly effectively exits the SafeDI-built dependency tree, which removes property lifecycle guarantees. Similarly, you must call the generated `init()` function on your dependency tree‘s root and not its memberwise `init(…)` function in order to create the SafeDI dependency tree.

To instantiate a dependency after a property‘s enclosing type is initialized, you must utilize an instantiated or received `Instantiator` or `ForwardingInstantiator` instance.  

#### SwiftUI

Per Apple‘s documentation, it is important to avoid decorating initializer-injected dependencies with the [`@State`](https://developer.apple.com/documentation/swiftui/state) or [`@StateObject`](https://developer.apple.com/documentation/swiftui/stateobject) property wrappers.

The `@State` documentation reads:

> Declare state as private to prevent setting it in a memberwise initializer, which can conflict with the storage management that SwiftUI provides

The `@StateObject` documentation reads:

> Declare state objects as private to prevent setting them from a memberwise initializer, which can conflict with the storage management that SwiftUI provides

`@Instantiated`, `@Forwarded`, or `@Received` objects may be decorated with [`@ObservedObject`](https://developer.apple.com/documentation/swiftui/ObservedObject). Note that `@Instantiated` objects declared on a `View` will be re-initialized when the view is re-initialized. You can find a deep dive on SwiftUI view lifecycles [here](https://www.donnywals.com/understanding-how-and-when-swiftui-decides-to-redraw-views/).

#### Inheritance

In a manual DI system it is simple for superclasses to receive injected dependencies. SafeDI‘s utilization of macros means that SafeDI is not aware of dependencies required due to inheritance trees. Due to this limitation, superclass types should not be decorated with `@Instantiable`: instead, subclasses should declare the properties their superclasses need, and pass them upwards via a call to `super.init(…)`.

#### Nested types

While manually written dependency injection code can work seamlessly with [nested types](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/nestedtypes/), SafeDI currently prevents nested types from being decorated with the `@Instantiable` macro.

### Migrating to SafeDI

It is strongly recommended that projects adopting SafeDI start their migration by identifying the root of their dependency tree and making it `@Instantiable`. Once your root object has adopted SafeDI, continue migrating dependencies to SafeDI in either a breadth-first or depth-first manner. As your adoption of SafeDI progresses, you‘ll find that you are removing more code than you are adding: many of your dependencies are likely being passed through intermediary objects that do not utilize the dependency except to instantiate a dependency deeper in the tree. Once types further down the dependency tree have adopted SafeDI, you will be able to avoid receiving dependencies in intermediary types.

## Example App

We‘ve tied everything together with an example multi-user notes application backed by SwiftUI. You compile and run this code in Xcode in the included [ExampleProjectIntegration](Examples/ExampleProjectIntegration) project.

## Integrating SafeDI

To integrate SafeDI into your codebase, you must both depend on the SafeDI framework that defines the core macros and instantiators, and also add the code generation step to your build process. You can see sample integrations in the [Examples](Examples/) folder.

### SafeDI Framework

To install the SafeDI framework into your package with [Swift Package Manager](https://github.com/apple/swift-package-manager), add the following lines to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/dfed/SafeDI", from: "0.9.0"),
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

for faster builds, you can install a release version of `SafeDITool` [rather than a debug version](https://github.com/apple/swift-package-manager/issues/7233) via `swift`:

```zsh
swift package --allow-network-connections all --allow-writing-to-package-directory safedi-release-install
```

#### Other configurations

If your first-party code comprises multiple modules in Xcode, or a mix of Xcode Projects and Swift Packages, or some other configuration not listed above, once your Xcode project depends on the SafeDI package you will need to utilize the `SafeDITool` command-line executable directly in a pre-build script.

```sh
set -e

VERSION='<<VERSION>>'
DESTINATION="$BUILD_DIR/SafeDITool-Release/$VERSION/safeditool"

if [ -f "$DESTINATION" ]; then
    if [ ! -x "$DESTINATION" ]; then
        chmod +x "$DESTINATION"
    fi
else
    mkdir -p "$(dirname "$DESTINATION")"

    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
        ARCH_PATH="SafeDITool-arm64"
    elif [ "$ARCH" = "x86_64" ]; then
        ARCH_PATH="SafeDITool-x86_64"
    else
        echo "Unsupported architecture: $ARCH"
        exit 1
    fi
    curl -L -o "$DESTINATION" "https://github.com/dfed/SafeDI/releases/download/$VERSION/$ARCH_PATH"
    chmod +x "$DESTINATION"
fi

$DESTINATION --include "$PROJECT_DIR/<<RELATIVE_PATH_TO_SOURCE_FILES>>" "$PROJECT_DIR/<<RELATIVE_PATH_TO_MORE_SOURCE_FILES>>" --dependency-tree-output "$PROJECT_DIR/<<RELATIVE_PATH_TO_WRITE_OUTPUT_FILE>>"
```

Make sure to set `ENABLE_USER_SCRIPT_SANDBOXING` to `NO` in your target, and to replace the `<<VERSION>>`, `<<RELATIVE_PATH_TO_SOURCE_FILES>>`, `<<RELATIVE_PATH_TO_MORE_SOURCE_FILES>>`, and `<<RELATIVE_PATH_TO_WRITE_OUTPUT_FILE>>` with the appropriate values.

You can see this in integration in practice in the [ExampleMultiProjectIntegration](Examples/ExampleMultiProjectIntegration) package.

The `SafeDITool` utility is designed to able to be integrated into projects of any size or shape.

The `SafeDITool` can parse all of your Swift files at once, or for even better performance, the tool can be run on each dependent module as part of the build. Running this tool on each dependent module is currently left as an exercise to the reader.

### Requirements

* Xcode 16.0 or later
* iOS 13 or later
* tvOS 13 or later
* watchOS 6 or later
* macOS 10.13 or later

## Under the hood

SafeDI has a `SafeDITool` executable that the `SafeDIGenerator` plugin utilizes to read code and generate a dependency tree. The tool utilizes Apple‘s [SwiftSyntax](https://github.com/apple/swift-syntax) library to parse your code and find your `@Instantiable` types‘ initializers and dependencies. With this information, SafeDI creates a graph of your project‘s dependencies. This graph is validated as part of the `SafeDITool`‘s execution, and the tool emits human-readible errors if the dependency graph is not valid. Source code is only generated if the dependency graph is valid.

The executable heavily utilizes asynchronous processing to avoid `SafeDITool` becoming a bottleneck in your build. Additionally, we only parse a Swift file with `SwiftSyntax` when the file contains the string `Instantiable`.

Due to limitations in Apple‘s [Swift Package Manager Plugins](https://github.com/apple/swift-package-manager/blob/main/Documentation/Plugins.md), the `SafeDIGenerator` plugin parses all of your first-party Swift files in a single pass. Projects that utilize `SafeDITool` directly can process Swift files on a per-module basis to further reduce the build-time bottleneck.

## Comparing SafeDI to other DI libraries

SafeDI‘s compile-time-safe design makes it similar to [Needle](https://github.com/uber/needle) and [Weaver](https://github.com/scribd/Weaver). Unlike Needle, SafeDI does not require defining dependency protocols for each DI-tree-instantiable type. SafeDI‘s capabilities are quite similar to Weaver‘s, with the biggest difference being that SafeDI supports codebases with multiple modules. Beyond those differences, SafeDI vs Needle vs Weaver is a matter of personal preference.

Other Swift DI libraries like [Swinject](https://github.com/Swinject/Swinject) and [Cleanse](https://github.com/square/Cleanse) do not offer compile-time safety, though other features are similar. A primary benefit of the SafeDI library is that compilation validates your dependency tree.

## Introspecting a SafeDI tree

You can utilize the `safeditool` to create a [GraphViz DOT file](https://graphviz.org/doc/info/lang.html) to introspect a SafeDI dependency tree by utilizing the `--dot-file-output` parameter on `safeditool`. This command will create a `DOT` file that you can pipe into `GraphViz`‘s `dot` command to create a pdf.

Once you have a the dot file, you can run:
```bash
dot path_to_dot_file.dot -Tpdf > path_to_pdf_file.pdf
```

You can find instructions for how to install the `dot` command [here](https://graphviz.org/download/).

## Acknowledgements

Huge thanks to [@kierajmumick](http://github.com/kierajmumick) for helping hone the early design of SafeDI.

## Developing

Double-click on the `Package.swift` file in the root of the repository to open the package in Xcode.

## Contributing

I’m glad you’re interested in SafeDI, and we‘d love to see where you take it. Please read the [contributing guidelines](Contributing.md) prior to submitting a Pull Request.

Thanks, and happy injecting!
