# SafeDI Manual

This manual provides a detailed guide to using SafeDI effectively in your Swift projects. You’ll learn how to integrate SafeDI into your build, create your dependency tree utilizing SafeDI’s macros, learn recommended approaches to adopting SafeDI, and get a tour of how SafeDI works under the hood.

## Installation

SafeDI utilizes both Swift macros and a code generation plugin to read your code and generate a dependency tree. Integrating SafeDI is a three-step process: add the package, wire the `SafeDIGenerator` plugin into your build, and decorate your types with SafeDI’s macros.

You can see sample integrations in the [Examples folder](../Examples/). Note that the example projects use the `sourceBuild` trait to build `SafeDITool` from source: consumers using a published release do not need to specify `traits`.

### Adding SafeDI as a dependency

#### Swift package manager

To add the SafeDI framework as a dependency to a package utilizing [Swift Package Manager](https://github.com/apple/swift-package-manager), add the following lines to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/dfed/SafeDI.git", from: "2.0.0"),
]
```

To install the SafeDI framework into an Xcode project with Swift Package Manager, follow [Apple’s instructions](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) to add `https://github.com/dfed/SafeDI.git` as a dependency.

### Generating your dependency tree

SafeDI provides a code generation plugin named `SafeDIGenerator`. This plugin uses a prebuilt binary for fast builds without compiling SwiftSyntax. This plugin works out of the box on most project configurations. If your project uses a custom build system, you can configure your build to utilize the `SafeDITool` command-line executable directly.

#### Xcode project

If your first-party code comprises a single module in an `.xcodeproj`, once your Xcode project depends on the SafeDI package you can integrate the Swift Package Plugin simply by going to your target’s `Build Phases`, expanding the `Run Build Tool Plug-ins` drop-down, and adding the `SafeDIGenerator` as a build tool plug-in. You can see this integration in practice in the [ExampleProjectIntegration](../Examples/ExampleProjectIntegration) project.

If your Xcode project comprises multiple modules, follow the above steps, and then add a `#SafeDIConfiguration` to your module to configure SafeDI:

```swift
import SafeDI

#SafeDIConfiguration(
    additionalDirectoriesToInclude: ["Subproject"]
)
```

The `additionalDirectoriesToInclude` parameter specifies folders outside of your module that SafeDI will scan for Swift source files. Paths must be relative to the project directory. Use this parameter to specify the paths to dependent modules' source directories, since Xcode project plugins cannot discover these automatically. You can see [an example of this configuration](../Examples/ExampleMultiProjectIntegration/ExampleMultiProjectIntegration/SafeDIConfiguration.swift) in the [ExampleMultiProjectIntegration](../Examples/ExampleMultiProjectIntegration) project.

#### Swift package

If your first-party code is entirely contained in a Swift Package with one or more modules, you can add the following lines to your root target’s definition:

```swift
    plugins: [
        .plugin(name: "SafeDIGenerator", package: "SafeDI")
    ]
```

To also generate mocks for non-root modules, add the plugin to all first-party targets.

You can see this integration in practice in the [Example Package Integration](../Examples/Example Package Integration) package.

Unlike the `SafeDIGenerator` Xcode project plugin, the `SafeDIGenerator` Swift package plugin finds source files in dependent modules without additional configuration steps. If you find that SafeDI’s generated dependency tree is missing required imports, you may add a `#SafeDIConfiguration` in your root module with the additional module names:

```swift
import SafeDI

#SafeDIConfiguration(
    additionalImportedModules: ["MyModule"]
)
```

### Additional configurations

`SafeDITool` is designed to integrate into projects of any size or shape. Our [Releases](https://github.com/dfed/SafeDI/releases) page has prebuilt, codesigned release binaries of the `SafeDITool` that can be downloaded and utilized directly in a pre-build script ([example](../Examples/PrebuildScript/safeditool.sh)). Make sure to set `ENABLE_USER_SCRIPT_SANDBOXING` to `NO` in the target running the pre-build script.

`SafeDITool` can parse all of your Swift files at once, or for even better performance, the tool can be run on each dependent module as part of the build. Run `swift run SafeDITool --help` to see documentation of the tool’s supported arguments.

## Macros

There are a total of five macros in the SafeDI library:

| Macro  | Decorating | Usage |
| ------ | ---------- | ----- |
| [`@Instantiable`](#instantiable) | Type or extension declaration | Makes a type capable of being instantiated by SafeDI. |
| [`@Instantiated`](#instantiated) | Property declaration | Instantiates an instance or value when the enclosing `@Instantiable`-decorated type is instantiated. |
| [`@Forwarded`](#forwarded) | Property declaration | Propagates a runtime-created instance or value (e.g. a `User` object, network response, or customer input) down the dependency tree. |
| [`@Received`](#received) | Property declaration | Receives an instance or value from an `@Instantiated` or `@Forwarded` property further up the dependency tree. |
| [`#SafeDIConfiguration`](#safediconfiguration) | Freestanding declaration | Provides build-time configuration for SafeDI’s code generation plugin. |

Let’s walk through each of these macros in detail.

### @Instantiable

Type declarations decorated with [`@Instantiable`](../Sources/SafeDI/Decorators/Instantiable.swift) are able to be instantiated by SafeDI. Types decorated with this macro can instantiate other `@Instantiable` dependencies, forward dependencies injected from outside of SafeDI, or receive dependencies instantiated or forwarded by objects further up the dependency tree.

SafeDI is designed to make instantiating and receiving dependencies _simple_, without requiring developers to think about abstract dependency injection (DI) concepts. That said, for those familiar with other DI systems: each `@Instantiable` type is its own [Scope](https://medium.com/@aarontharris/scope-dependency-injection-6fc25beffc9c). For those unfamiliar with DI terminology, know that each `@Instantiable` type retains its dependencies, and that every `@Instantiated` or `@Forwarded` dependency is available to all transitive child dependencies.  

Every `@Instantiable`-decorated type must be:

1. `public` or `open`

2. Have a `public init(…)` or `open init(…)` that has a parameter for each of its injected properties

The `@Instantiable` macro guides developers through satisfying these requirements with code generation and build-time fix-its.

Here is a sample `LoggedInView` implementation that is `@Instantiable`. It is annotated with each of the three dependency-kind macros — `@Forwarded`, `@Received`, and `@Instantiated` — that together describe how dependencies enter a SafeDI scope:

```swift
import SafeDI
import SwiftUI

@Instantiable
public struct LoggedInView: Instantiable, View {
    /// Public, memberwise initializer that takes each injected property.
    public init(user: User, userService: UserService, noteStorage: NoteStorage) {
        self.user = user
        self.userService = userService
        self.noteStorage = noteStorage
    }

    public var body: some View {
        VStack {
            Text("\(user.name)’s note")
            // …
        }
    }

    /// The authenticated user, forwarded in from the parent scope at runtime.
    @Forwarded private let user: User

    /// Shared user state, instantiated further up the dependency tree.
    @Received private let userService: UserService

    /// A note storage instance created by SafeDI when this view is created.
    @Instantiated private let noteStorage: NoteStorage
}
```

- `@Forwarded` marks a dependency that is passed in at runtime (e.g., the authenticated `User` returned from sign-in) and made available to the rest of this scope and its subtree.
- `@Received` marks a dependency that was already created further up the tree and is being received here.
- `@Instantiated` marks a dependency that SafeDI constructs when this type is instantiated. `noteStorage`’s own `@Received` inputs are resolved from this scope’s context.

The exact semantics of each dependency kind — including `@Instantiated`’s configuration parameters for dependency inversion, and `@Received`’s `onlyIfAvailable` option — are covered in [@Instantiated](#instantiated), [@Received](#received), and [@Forwarded](#forwarded).

#### Creating the root of your dependency tree

Any type decorated with `@Instantiable(isRoot: true)` is a root of a SafeDI dependency tree. SafeDI creates a no-parameter `public init()` initializer that instantiates the dependency tree in an extension on each root type.

#### Making protocols `@Instantiable`

While it is not necessary to utilize protocols with SafeDI, protocol-driven development aids both testability and dependency inversion. The `@Instantiable` macro has a parameter `fulfillingAdditionalTypes` that enables any concrete `@Instantiable` type to fulfill properties that are declared as conforming to a protocol (or superclass) type.

So far we have been treating `UserService` as a concrete type. Let’s consider what we need to do if `UserService` is instead a protocol:

```swift
import SafeDI

/// A protocol that defines a UserService.
public protocol UserService {
    var user: User? { get set }
}

/// A default implementation of `UserService`. `fulfillingAdditionalTypes`
/// registers `DefaultUserService` as a valid fulfiller for any `UserService`
/// property anywhere in the dependency tree.
@Instantiable(fulfillingAdditionalTypes: [UserService.self])
public final class DefaultUserService: UserService, Instantiable {
    public init(stringStorage: StringStorage) {
        self.stringStorage = stringStorage
    }

    public var user: User? {
        get { /* read from stringStorage */ }
        set { /* write to stringStorage */ }
    }

    @Received private let stringStorage: StringStorage
}
```

With this in place, any `@Instantiated private let userService: UserService` or `@Received private let userService: UserService` elsewhere in the dependency tree will be wired to a `DefaultUserService` — no decoration parameters needed.

SwiftUI’s `@ObservedObject` property wrapper requires a concrete `ObservableObject` — a protocol type like `UserService` won’t satisfy that constraint. To observe a protocol-typed dependency, upgrade the protocol to inherit `ObservableObject` and pair it with a concrete type-erasing wrapper (by convention prefixed with `Any`):

```swift
import Combine
import SwiftUI

/// The protocol now inherits `ObservableObject` so conformers can publish changes.
public protocol UserService: ObservableObject {
    var user: User? { get set }
}

/// A concrete [existential](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/opaquetypes/#Boxed-Protocol-Types) wrapper around `UserService` — a non-protocol type that boxes any `UserService` and is itself an `ObservableObject`.
public final class AnyUserService: UserService, ObservableObject {
    public init(_ userService: some UserService) {
        self.userService = userService
        objectWillChange = userService.objectWillChange
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    public var user: User? {
        get { userService.user }
        set { userService.user = newValue }
    }

    public let objectWillChange: AnyPublisher<Void, Never>

    private let userService: any UserService
}
```

`AnyUserService` isn’t itself `@Instantiable` and isn’t a superclass of `DefaultUserService`, so SafeDI can’t wire this up on its own — you need to tell it what to build and how to assign it:

```swift
@Instantiable(isRoot: true) @main
public struct NotesApp: App, Instantiable {
    // …

    // Builds a `DefaultUserService`, wraps it in `AnyUserService`, and observes it for SwiftUI updates.
    @ObservedObject @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true)
    private var userService: AnyUserService
}
```

`fulfilledByType` takes a string literal naming the concrete type to construct — here, `"DefaultUserService"`. Representing the type as a string allows for dependency inversion: the consuming module does not need to import the module that declares the fulfiller. `erasedToConcreteExistential: true` tells SafeDI that the constructed value must be wrapped via the property type’s initializer — here, `AnyUserService(_:)` — rather than assigned directly:

| Parameter | Logic | Example |
| --------- | ----- | ------- |
| `erasedToConcreteExistential: false` | **Cast:** `FulfillingType as PropertyType` | `MyViewController` → `UIViewController` |
| `erasedToConcreteExistential: true` | **Wrap:** `PropertyType(FulfillingType())` | `MyView` → `AnyView(MyView())` |

#### Making external types `@Instantiable`

Types that are declared outside of your project can be instantiated by SafeDI if there is an extension on the type decorated with the `@Instantiable` macro. Extensions decorated with this macro define how to instantiate the extended type via a `public static func instantiate(…) -> ExtendedType` function. This `instantiate(…)` function can receive dependencies instantiated or forwarded by objects further up the dependency tree by declaring these dependencies as parameters to the `instantiate(…)` function.

Here we have a sample `@Instantiable` extension on `UserDefaults` that adopts a first-party `StringStorage` protocol so SafeDI can instantiate it in place of a hand-rolled storage type:

```swift
import Foundation
import SafeDI

public protocol StringStorage {
    func string(forKey key: String) -> String?
    func setString(_ string: String?, forKey key: String)
}

@Instantiable(fulfillingAdditionalTypes: [StringStorage.self])
extension UserDefaults: @retroactive Instantiable, StringStorage {
    /// A public static function that defines how SafeDI can instantiate the type.
    public static func instantiate() -> UserDefaults {
        .standard
    }

    public func string(forKey key: String) -> String? {
        object(forKey: key) as? String
    }

    public func setString(_ string: String?, forKey key: String) {
        set(string, forKey: key)
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

/// An extension on the Container type that tells SafeDI how to instantiate a `Container<MyEnum>`.
/// We tell the `@Instantiable` macro that this type already conforms to the `Instantiable` protocol elsewhere to prevent the macro from requiring that this extension declares a conformance to `Instantiable`.
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

If the enclosing type is a SwiftUI `View`, keep in mind that `@Instantiated` objects are re-initialized each time the view is recreated by SwiftUI. You can find a deep dive on SwiftUI view lifecycles [here](https://www.donnywals.com/understanding-how-and-when-swiftui-decides-to-redraw-views/).

### @Forwarded

Property declarations within `@Instantiable` types decorated with [`@Forwarded`](../Sources/SafeDI/Decorators/Forwarded.swift) represent dependencies that come from the runtime, e.g. user input or backend-delivered content. Like an `@Instantiated`-decorated property, a `@Forwarded`-decorated property is available to be `@Received` by objects instantiated further down the dependency tree.

A `@Forwarded` property is forwarded into the SafeDI dependency tree by an [`Instantiator`](#instantiator)’s `instantiate(_:)` function that creates an instance of the property’s enclosing type.

Forwarded property types do not need to be decorated with the `@Instantiable` macro.

Here’s an example showing how to forward a runtime value — an authenticated `User` — into an `@Instantiable` type:

```swift
// A view that requires a runtime value (the authenticated user).
@Instantiable
public struct LoggedInView: View, Instantiable {
    public init(user: User) {
        self.user = user
    }

    // …

    @Forwarded private let user: User
}

// The app’s root type forwards the authenticated `user` into the logged-in subtree.
@Instantiable(isRoot: true) @main
public struct NotesApp: App, Instantiable {
    public var body: some Scene {
        WindowGroup {
            if let user = userService.user {
                // Pass the forwarded property when instantiating.
                loggedInViewBuilder.instantiate(user)
            } else {
                nameEntryViewBuilder.instantiate()
            }
        }
    }

    @Instantiated private let userService: UserService
    @Instantiated private let nameEntryViewBuilder: Instantiator<NameEntryView>
    @Instantiated private let loggedInViewBuilder: Instantiator<LoggedInView>
}
```

### @Received

Property declarations within `@Instantiable` types decorated with [`@Received`](../Sources/SafeDI/Decorators/Received.swift) are injected into the enclosing type’s initializer. Received properties must be `@Instantiated` or `@Forwarded` by an object higher up in the dependency tree.

Here we have a `LoggedInView` in which the forwarded `user` property is received by a `NoteStorage` further down the dependency tree:

```swift
@Instantiable
public struct LoggedInView: View, Instantiable {
    // …

    @Forwarded private let user: User

    // NoteStorage is instantiated by LoggedInView, so it lives for the
    // lifetime of the logged-in subtree.
    @Instantiated private let noteStorage: NoteStorage
}

@Instantiable
public class NoteStorage: Instantiable {
    public init(user: User, stringStorage: StringStorage, defaultNote: String = "") {
        self.user = user
        self.stringStorage = stringStorage
        self.defaultNote = defaultNote
    }

    public var note: String {
        get { stringStorage.string(forKey: noteKey) ?? defaultNote }
        set { stringStorage.setString(newValue, forKey: noteKey) }
    }

    // The user object is received from the LoggedInView.
    @Received private let user: User

    // The string storage is received from further up the tree.
    @Received private let stringStorage: StringStorage

    private let defaultNote: String
    private var noteKey: String { "note-for-\(user.name)" }
}
```

#### Renaming and retyping dependencies

Use `@Received(fulfilledByDependencyNamed:ofType:)` to rename or retype a dependency that was `@Instantiated` or `@Forwarded` higher up the tree. Types further down the tree can then `@Received` the dependency under its new name and type.

Here, a parent forwards a read-write `UserManager`; a child receives the same instance as the read-only `UserVendor` protocol:

```swift
public protocol UserVendor { var user: User { get } }
public protocol UserManager: UserVendor { var user: User { get set } }

@Instantiable
public struct LoggedInView: Instantiable {
    @Forwarded private let userManager: UserManager
    @Instantiated private let profileViewBuilder: Instantiator<ProfileView>
}

@Instantiable
public struct ProfileView: Instantiable {
    @Received(fulfilledByDependencyNamed: "userManager", ofType: UserManager.self)
    private let userVendor: UserVendor
}
```

#### Conditionally receiving dependencies

Use `@Received(onlyIfAvailable: true)` to receive an optional dependency only when a parent has `@Instantiated` or `@Forwarded` it. This is useful when a type is instantiated by multiple parents with different available dependencies — for example, a `FeedView` used by both a logged-in and logged-out parent:

```swift
@Instantiable
public struct FeedView: Instantiable {
    // Populated when reached from `LoggedInView`; `nil` when reached from `LoggedOutView`.
    @Received(onlyIfAvailable: true) private let user: User?
}
```

### #SafeDIConfiguration

[`#SafeDIConfiguration`](../Sources/SafeDI/Decorators/SafeDIConfiguration.swift) is a freestanding declaration macro that provides build-time configuration for SafeDI’s code generation plugin. Each module may have at most one `#SafeDIConfiguration` invocation. It must appear at the top level of a Swift file (not nested inside a type). All arguments must be literal values. All parameters have defaults, so the simplest valid invocation is `#SafeDIConfiguration()`.

```swift
#SafeDIConfiguration(
    additionalImportedModules: ["MyModule", "OtherModule"],
    additionalDirectoriesToInclude: ["Sources/OtherModule"],
    additionalMocksToGenerate: ["LoggingService"],
    mockConditionalCompilation: "DEBUG"
)
```

**Parameters:**

- `additionalImportedModules`: Module names to import in the generated dependency tree, in addition to the import statements found in files that declare `@Instantiable` types. Default: `[]`.
- `additionalDirectoriesToInclude`: Directories containing Swift files to include, relative to the executing directory. This parameter only applies to SafeDI repos that utilize the SPM plugin via an Xcode project. Default: `[]`.
- `additionalMocksToGenerate`: Type names from dependent modules to generate `mock()` methods for in this module. The types must be `@Instantiable` in their home module. See [Cross-module mock generation](#cross-module-mock-generation). Default: `[]`.
- `mockConditionalCompilation`: The conditional compilation flag to wrap generated mock code in (e.g. `"DEBUG"`). Set to `nil` to generate mocks without conditional compilation. Default: `"DEBUG"`.

## Delayed instantiation

When you want to instantiate a dependency after `init(…)`, you need to declare an `Instantiator<Dependency>`-typed property as `@Instantiated` or `@Received`. Deferred instantiation is useful in situations where a dependency is expensive to create or only required under certain conditions (e.g., creating a detailed view for a selected item in a list).

### Instantiator

The [`Instantiator`](../Sources/SafeDI/DelayedInstantiation/Instantiator.swift) type is how SafeDI enables deferred instantiation of an `@Instantiable` type. `Instantiator` has a single generic that matches the type of the to-be-instantiated instance. Creating an `Instantiator` property is as simple as creating any other property in the SafeDI ecosystem:

```swift
@Instantiable(isRoot: true) @main
public struct NotesApp: App, Instantiable {
    // …

    // The two child views are built lazily via `Instantiator`:
    // `nameEntryViewBuilder.instantiate()` and `loggedInViewBuilder.instantiate(user)`.
    @Instantiated private let nameEntryViewBuilder: Instantiator<NameEntryView>
    @Instantiated private let loggedInViewBuilder: Instantiator<LoggedInView>
}
```

SafeDI generates a `ForwardedProperties` typealias for every `@Instantiable` type. This typealias is a tuple containing all properties decorated with `@Forwarded`. `Instantiator.instantiate(_:)` takes a `ForwardedProperties` argument, ensuring that you provide all required runtime dependencies when instantiating the type.

An `Instantiator` is not `Sendable`: if you want to be able to share an instantiator across concurrency domains, use a [`SendableInstantiator`](../Sources/SafeDI/DelayedInstantiation/SendableInstantiator.swift).

### ErasedInstantiator

For deferred instantiation of a type-erased dependency, use `ErasedInstantiator` — it combines the deferred construction of [`Instantiator`](#instantiator) with the `fulfilledByType` / `erasedToConcreteExistential` parameters covered in [Making protocols `@Instantiable`](#making-protocols-instantiable).

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

## Mock generation

SafeDI can automatically generate `mock()` methods for `@Instantiable` types, drastically simplifying testing and SwiftUI previews. Mock generation is controlled per type via `@Instantiable(generateMock: true)`.

### Enabling mock generation

To generate a `mock()` method for a type, set `generateMock: true` on the `@Instantiable` decorator:

```swift
@Instantiable(generateMock: true, fulfillingAdditionalTypes: [UserService.self])
public final class DefaultUserService: UserService, Instantiable {
    // …

    @Received private let stringStorage: StringStorage
}
```

By default, `generateMock` is `false` and no mock is generated. Generated mocks are wrapped in `#if DEBUG` by default. To customize the conditional compilation flag, set the `mockConditionalCompilation` parameter in your module’s [`#SafeDIConfiguration`](#safediconfiguration).

### Using generated mocks

Each `@Instantiable` type with `generateMock: true` gets a generated `mock()` static method that builds its full dependency subtree. The hand-written mock method must be in the same `@Instantiable`-decorated declaration body — methods in undecorated extensions are not detected. To provide a mock from a separate extension, use `@Instantiable(mockOnly: true)` on that extension instead.

When a type also has a hand-written mock method, it must have a different name from the generated `mock()` to avoid ambiguity. Use the `customMockName` parameter to specify the name of your hand-written method. The generated `mock()` will call through to it. With `mockOnly: true`, `customMockName` tells SafeDI which method to use as the mock provider. This is useful when you need custom logic during mock construction — for example, setting up stub behavior, configuring test doubles, or wiring delegates:

```swift
@Instantiable(generateMock: true, customMockName: "customMock")
public struct NetworkClient: Instantiable {
    public init(session: URLSession, logger: Logger) {
        self.session = session
        self.logger = logger
    }
    @Instantiated let session: URLSession
    @Instantiated let logger: Logger

    public static func customMock(
        session: URLSession = .mockSession(returning: Data()),
        logger: Logger = .noop
    ) -> NetworkClient {
        NetworkClient(session: session, logger: logger)
    }
}
```

The `customMockName` parameter requires `generateMock: true` or `mockOnly: true`.

If you provide a mock method without `generateMock: true`, parent types that instantiate the child will call `ChildType.mock(…)` (or `ChildType.customMock(…)`) instead of `ChildType(…)` when constructing it, threading mock parameters through your custom method.

### The `mockOnly` parameter

The `mockOnly` parameter lets you provide a hand-written `mock()` method for types that don’t need full `@Instantiable` infrastructure. Here’s an example providing a mock for a third-party type:

```swift
@Instantiable(mockOnly: true)
extension ExternalService {
    public static func mock() -> ExternalService {
        ExternalService(apiKey: "test-key")
    }
}
```

This also works for types that are pure data and used as `@Forwarded` dependencies — for example, an authenticated `User`:

```swift
@Instantiable(mockOnly: true)
extension User {
    public static func mock() -> User {
        User(name: "Mock User")
    }
}
```

When you provide a `mockOnly` extension for a type, SafeDI’s mock generator will utilize that mock wherever the type appears in a mock dependency tree. This "auto-filling" behavior means you don’t have to manually provide a mock for common types (like `User` or `NetworkClient`) every time you call `mock()` on a parent type. For `@Forwarded` dependencies, the parameter gets a default value so callers don’t need to provide it. For `@Instantiated` dependencies, the type appears in `SafeDIOverrides` with `Type.mock()` as the default, allowing optional override.

`mockOnly` is useful for:

- Types defined in other modules (e.g., third-party dependencies) that need mocks in your tests
- Primitive or Foundation types used as `@Forwarded` dependencies (e.g., `String`, `Int`, `UUID`)
- Types whose `@Instantiable` declaration is in another module and isn’t in the current module’s dependency tree

A `mockOnly` declaration requires a hand-written `mock()` method (or a method named by `customMockName`). No `init` (type declarations), `instantiate()` (extensions), or `Instantiable` conformance is required. `mockOnly` is mutually exclusive with `generateMock` and `isRoot`. `conformsElsewhere` has no effect when `mockOnly` is true.

#### Splitting production and mock declarations

A type may have `@Instantiable` on both its declaration and an extension, with one being `mockOnly: true`. This lets you keep production behavior in one declaration and a hand-written mock in the other:

```swift
// Production declaration in this or another module:
@Instantiable
public struct MyService: Instantiable {
    public init(database: Database) { … }
    @Instantiated let database: Database
}

// Mock-only extension in this module:
@Instantiable(mockOnly: true)
extension MyService {
    public static func mock() -> MyService {
        MyService(database: .mock())
    }
}
```

When both declarations exist, SafeDI uses the production `@Instantiable` for the dependency tree and the `mockOnly` declaration’s hand-written mock for mock generation. If the production type also has a hand-written `mock()` method, SafeDI emits an error — a type can have at most one hand-written mock. A `generateMock: true` production type that lacks a hand-written mock will use the `mockOnly` declaration’s mock, since hand-written mocks take priority over generated ones.

Your user-defined `mock()` method must be `public` (or `open`) and must accept parameters for each of the type’s `@Instantiated`, `@Received`, and `@Forwarded` dependencies. Non-dependency parameters must have default values. On concrete type declarations the return type must be `Self` or the type name; on extension-based `@Instantiable` types the return type must match the extended type (e.g. `-> Container<Bool>`) or a `fulfillingAdditionalTypes` entry, mirroring the corresponding `instantiate()` method. The `@Instantiable` macro validates these requirements and provides fix-its for any issues.

```swift
#if DEBUG
#Preview {
    MyView.mock()
}
#endif
```

### Overriding dependencies

When a type has `@Instantiated` dependencies, the generated `mock()` accepts a `safeDIOverrides` argument that lets you override any dependency in the tree. Each entry on `SafeDIOverrides` is either a closure whose parameters match the resolved values of that dependency’s own inputs, or a nested `SafeDIMockConfiguration` struct when the dependency has its own `@Instantiated` subtree or default-valued init parameters.

Closure-shaped entries apply when the dependency has nothing further to configure:

```swift
// Override a leaf dependency — UserDefaults.instantiate() takes nothing, so its closure takes nothing:
LoggedInView.mock(safeDIOverrides: .init(
    stringStorage: { InMemoryStorage() }
))

// `StubUserService.init(stringStorage:)` already matches the override closure's shape
// — `(StringStorage) -> UserService` — so the initializer can be passed directly:
LoggedInView.mock(safeDIOverrides: .init(
    userService: StubUserService.init
))
```

`NoteStorage` has a default-valued `defaultNote` init parameter, so its entry is a nested `SafeDIMockConfiguration`:

```swift
// Tweak `defaultNote` without replacing how NoteStorage is built:
LoggedInView.mock(safeDIOverrides: .init(
    noteStorage: .init(defaultNote: "Welcome back")
))

// Replace how NoteStorage itself is built. `StubNoteStorage` is a subclass of
// `NoteStorage` whose `init` matches the signature of `NoteStorage.init`, so we
// can pass its initializer directly as the `safeDIBuilder`:
LoggedInView.mock(safeDIOverrides: .init(
    noteStorage: .init(safeDIBuilder: StubNoteStorage.init)
))
```

`SafeDIMockConfiguration` exposes an optional override for each of the child’s own `@Instantiated` dependencies and each default-valued init parameter, plus a trailing `safeDIBuilder` closure. The `safeDIBuilder` parameters match the type’s `customMockName` method signature if one is defined, or its `init` parameters otherwise. When no `safeDIBuilder` is provided, the generated mock calls the type’s `customMockName` method or `init` directly.

A type generates its own `SafeDIOverrides` struct when it has `@Instantiated` dependencies or `@Received(onlyIfAvailable: true)` dependencies. A type whose only dependencies are required `@Received` or `@Forwarded` uses flat parameters on its `mock()` method.

### Mock visibility

Generated mocks have `internal` visibility. They are accessible within the module where they are generated but not from other modules. This avoids cross-module extension conflicts when multiple modules generate mocks for the same types.

To use a mock from another module in your tests, see [Cross-module mock generation](#cross-module-mock-generation).

### @Forwarded properties in mocks

`@Forwarded` properties become parameters on the mock method since they represent runtime input. By default they are required (no default value):

```swift
let view = LoggedInView.mock(user: User(name: "dfed"))
```

A forwarded parameter gets a default value when:
- The root type’s own initializer or custom mock provides a default for the parameter
- The forwarded type has a `mockOnly` provider — the parameter defaults to `Type.mock()` (or the `customMockName` method)

### Default-valued init parameters in mocks

If an `@Instantiable` type’s initializer has parameters with default values that are not annotated with `@Instantiated`, `@Received`, or `@Forwarded`, those parameters are automatically exposed in the generated mock. This lets you override values like seed data or feature flags in tests and previews while keeping the original defaults for production code.

```swift
@Instantiable(generateMock: true)
public class NoteStorage: Instantiable {
    public init(user: User, stringStorage: StringStorage, defaultNote: String = "") { … }
    @Received let user: User
    @Received let stringStorage: StringStorage
}
```

When mocking `NoteStorage` directly, pass the override as a flat parameter:

```swift
NoteStorage.mock(
    user: User(name: "dfed"),
    stringStorage: InMemoryStorage(),
    defaultNote: "dfed says hello"
)
```

When mocking a parent of `NoteStorage`, the default-valued parameter appears on `NoteStorage`’s nested `SafeDIMockConfiguration`:

```swift
LoggedInView.mock(
    user: User(name: "dfed"),
    safeDIOverrides: .init(
        noteStorage: .init(defaultNote: "dfed says hello")
    )
)
```

When no override is provided, the original default expression (`""`) is used.

Default-valued parameters do **not** bubble through `Instantiator`, `SendableInstantiator`, `ErasedInstantiator`, or `SendableErasedInstantiator` boundaries, since those represent user-provided closures that control construction at runtime.

### `@Received(onlyIfAvailable: true)` properties in mocks

When a type has a `@Received(onlyIfAvailable: true)` dependency, the generated mock places that dependency inside the `SafeDIOverrides` struct as a plain optional property (defaulting to `nil`) rather than exposing it as a top-level `mock()` parameter. When `nil`, the dependency is absent. When provided (e.g., `.mock()`), the value is used.

```swift
@Instantiable(generateMock: true)
public struct ImageService: Instantiable {
    public init(cacheService: CacheService?) {
        self.cacheService = cacheService
    }
    @Received(onlyIfAvailable: true) let cacheService: CacheService?
}
```

Provide the dependency via `SafeDIOverrides`:

```swift
ImageService.mock(safeDIOverrides: .init(
    cacheService: .mock()
))
```

When no value is provided, the dependency defaults to `nil`.

### The `mockAttributes` parameter

When a type’s initializer is bound to a global actor that the plugin cannot detect (e.g. inherited `@MainActor`), use `mockAttributes` to annotate the generated mock:

```swift
@Instantiable(mockAttributes: "@MainActor")
public final class MyPresenter: Instantiable { … }
```

### Multi-module mock generation

To generate mocks for non-root modules, add the `SafeDIGenerator` plugin to all first-party targets in your `Package.swift`. Each module’s mocks are scoped to its own types to avoid duplicates.

Each type that should have a mock must be decorated with `@Instantiable(generateMock: true)`.

**Note:** Mock generation only creates mocks for types defined in the current module. Types from dependent modules are not mocked by default — each module must have its own `SafeDIGenerator` plugin to generate mocks for its types.

### Cross-module mock generation

When a module needs to use the generated `mock()` method of a type defined in a dependent module, use the `additionalMocksToGenerate` parameter on [`#SafeDIConfiguration`](#safediconfiguration):

```swift
#SafeDIConfiguration(
    additionalMocksToGenerate: [
        "LoggingService",
        "UserStorageService",
    ]
)
```

This generates a `mock()` method for each listed type in the current module, even though the type is defined elsewhere. The type must be `@Instantiable` in its home module (though `generateMock: true` is not required there).

**Note:** Mock generation only creates mocks for types defined in the current module. Types from dependent modules or `additionalDirectoriesToInclude` are not mocked — each module must have its own `SafeDIGenerator` plugin to generate mocks for its types.

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

`@Instantiated`, `@Forwarded`, or `@Received` objects may be decorated with [`@ObservedObject`](https://developer.apple.com/documentation/swiftui/ObservedObject).

### Inheritance

In a manual DI system it is simple for superclasses to receive injected dependencies. SafeDI’s utilization of macros means that SafeDI is not aware of dependencies required due to inheritance trees. Due to this limitation, superclass types should not be decorated with `@Instantiable`: instead, subclasses should declare the properties their superclasses need, and pass them upwards via a call to `super.init(…)`.

## Migrating to SafeDI

It is strongly recommended that projects adopting SafeDI start their migration by identifying the root of their dependency tree and making it `@Instantiable(isRoot: true)`. Once your root object has adopted SafeDI, continue migrating dependencies to SafeDI in either a breadth-first or depth-first manner. As your adoption of SafeDI progresses, you’ll find that you are removing more code than you are adding: many of your dependencies are likely being passed through intermediary objects that do not utilize the dependency except to instantiate a dependency deeper in the tree. Once types further down the dependency tree have adopted SafeDI, you will be able to avoid receiving dependencies in intermediary types.

### Selecting a root in SwiftUI applications

SwiftUI applications have a natural root: the `App`-conforming type that is initialized when the binary is launched.

### Selecting a root in UIKit applications

UIKit applications’ natural root is the `UIApplicationDelegate`-conforming app delegate, however, this type inherits from the Objective-C `NSObject` which already has a no-argument `init()`. As such, it is best to create a custom `@Instantiable(isRoot: true) public final class Root: Instantiable` type that is initialized and stored by the application’s app delegate.

## Migrating from SafeDI 1.x to 2.x

SafeDI 2.x requires Swift 6.3 or later and does not support CocoaPods. Projects using an earlier Swift version or CocoaPods should use SafeDI 1.x.

SafeDI 2.x also removes support for CSV-based configuration files (`.safedi/configuration/include.csv` and `.safedi/configuration/additionalImportedModules.csv`). Configuration is now done via the `#SafeDIConfiguration` macro.

### Automated migration

SafeDI provides a command plugin to automate the migration:

```bash
swift package plugin safedi-v1-to-v2 --target <YourRootTarget>
```

This plugin will:
1. Verify your `swift-tools-version` is 6.3 or later
2. Create a `SafeDIConfiguration.swift` file in your target’s source directory
3. Migrate any existing CSV configuration values into the new `#SafeDIConfiguration` macro
4. Delete the obsolete CSV files

### Manual migration

1. Update your `swift-tools-version` to 6.3 or later
2. Update your SafeDI dependency to `from: "2.0.0"`
3. If you have `.safedi/configuration/include.csv` or `.safedi/configuration/additionalImportedModules.csv`, add a `#SafeDIConfiguration` in your root module with the equivalent values and delete the CSV files
4. If you don’t have CSV configuration files, add a `#SafeDIConfiguration()` in your root module

### Plugin changes

The `SafeDIPrebuiltGenerator` plugin and `InstallSafeDITool` command plugin have been removed in SafeDI 2.x. `SafeDIGenerator` is now the only build tool plugin and uses a prebuilt binary by default. If you were previously using `SafeDIPrebuiltGenerator` or the `safedi-release-install` command, switch to `SafeDIGenerator`.

### Migrating prebuild scripts or custom build system integrations

If you invoke `SafeDITool` directly (not via the provided SPM plugin), the `--dependency-tree-output` flag has been replaced with `generate --swift-manifest`. The tool now takes a JSON manifest file that maps input Swift files to output files. See [`SafeDIToolManifest`](../Sources/SafeDICore/Models/SafeDIToolManifest.swift) for the expected format.

Before (1.x):
```bash
safeditool input.csv --dependency-tree-output ./generated/SafeDI.swift
```

After (2.x):
```bash
# Create a manifest mapping root files to outputs
cat > manifest.json << 'EOF'
{
  "dependencyTreeGeneration": [
    {
      "inputFilePath": "Sources/App/Root.swift",
      "outputFilePath": "generated/Root+SafeDI.swift"
    }
  ]
}
EOF
safeditool generate input.csv --swift-manifest manifest.json
```

## Example applications

We’ve tied everything together with an example multi-user notes application backed by SwiftUI. You can compile and run this code in [an example single-module Xcode project](../Examples/ExampleProjectIntegration). This same multi-user notes app also exists in [an example multi-module Xcode project](../Examples/ExampleMultiProjectIntegration). We have also created [an example multi-module `Package.swift` that integrates with SafeDI](../Examples/Example Package Integration).

## Under the hood

SafeDI has a `SafeDITool` executable that the `SafeDIGenerator` plugin utilizes to read code and generate a dependency tree. The tool has two subcommands:

- **`generate`** (default): Parses Swift source files, builds a dependency graph, validates it, and generates per-root output files and mock code. `generate` takes a JSON manifest file describing the desired outputs — the manifest uses the [`SafeDIToolManifest`](../Sources/SafeDICore/Models/SafeDIToolManifest.swift) format, mapping input Swift files containing `@Instantiable(isRoot: true)` to output file paths (relative to the working directory). This is the default subcommand, making it backward compatible with existing prebuild scripts that invoke `SafeDITool` without an explicit subcommand.
- **`scan`**: Scans Swift source files and produces a manifest JSON describing the `@Instantiable` types found. This is used by the `SafeDIGenerator` plugin to coordinate builds across modules, and is also useful for per-module scanning in custom build systems.

Both subcommands utilize Apple’s [SwiftSyntax](https://github.com/apple/swift-syntax) library to parse your code and find your `@Instantiable` types’ initializers and dependencies. With this information, SafeDI generates a graph of your project’s dependencies, validates it during `SafeDITool` execution, and provides clear, human-readable error messages if the graph is invalid. Source code is only generated if the dependency graph is valid.

The executable heavily utilizes asynchronous processing to avoid `SafeDITool` becoming a bottleneck in your build. Additionally, we only parse a Swift file with `SwiftSyntax` when the file contains the string `Instantiable`.

The `SafeDIGenerator` plugin is the only build tool plugin and uses a prebuilt binary by default for fast builds without compiling SwiftSyntax. Due to limitations in Apple’s [Swift Package Manager Plugins](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/Plugins.md), the plugin parses all of your first-party Swift files in a single pass. Projects that utilize `SafeDITool` directly can process Swift files on a per-module basis to further reduce the build-time bottleneck.

### Custom build system integration

If you are integrating SafeDI with a build system other than SPM (e.g. Bazel, Buck, or a prebuild script), you can invoke `SafeDITool` directly using the `scan` and `generate` subcommands described above. See the [example prebuild script](../Examples/PrebuildScript/safeditool.sh) for a working example.

Run `swift run SafeDITool --help`, `swift run SafeDITool scan --help`, or `swift run SafeDITool generate --help` to see documentation of all supported arguments.

## Introspecting a SafeDI tree

You can create a [GraphViz DOT file](https://graphviz.org/doc/info/lang.html) to introspect a SafeDI dependency tree by running `swift run SafeDITool` and utilizing the `--dot-file-output` parameter. This command will create a `DOT` file that you can pipe into `GraphViz`’s `dot` command to create a pdf.

Once you have the dot file, you can run:
```bash
dot path_to_dot_file.dot -Tpdf > path_to_pdf_file.pdf
```

You can find instructions for how to install the `dot` command [here](https://graphviz.org/download/).
