# SafeDI Manual

SafeDI utilizes both Swift macros and a code generation plugin to read your code and generate a dependency tree. You decorate each type with SafeDI’s macros to declare the dependencies it instantiates, receives, and forwards; when you build, SafeDI validates the tree and generates the code that creates it, along with mocks for your tests and previews.

New to SafeDI? Start with the [quick start](QuickStart.md), which sets up SafeDI in an app of several modules. This manual is the reference: look up what you need rather than reading it end to end.

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

Type declarations decorated with [`@Instantiable`](../Sources/SafeDI/Decorators/Instantiable.swift) are able to be instantiated by SafeDI. Such a type can instantiate other `@Instantiable` dependencies, forward dependencies injected from outside of SafeDI, or receive dependencies instantiated or forwarded by objects further up the dependency tree.

SafeDI is designed to make instantiating and receiving dependencies _simple_, without requiring developers to think about abstract dependency injection (DI) concepts. In DI terms, each `@Instantiable` type is its own [Scope](https://medium.com/@aarontharris/scope-dependency-injection-6fc25beffc9c): it retains its dependencies, and every `@Instantiated` or `@Forwarded` dependency is available to all its transitive children.

Every `@Instantiable`-decorated type must:

1. Be visible, with its initializer, to the code that constructs it. See [Access levels](#access-levels).

2. Have an initializer with a parameter for each of its injected properties, with the property’s label and type. Declare a closure parameter `@escaping`, as Swift requires, also when a typealias names its type: `init(onTap: @escaping OnTap)` takes `let onTap: OnTap`. Any other attribute or specifier that the property does not spell, such as `@autoclosure` or `sending`, makes the parameter a different type.

3. Spell a nested type with its enclosing types when SafeDI cannot do it for you, as in `@Forwarded let configuration: Feature.Configuration`. Generated code lives in extensions outside your type, where a `Configuration` declared inside `Feature` is not in scope by its short name. SafeDI adds the enclosing types for a nested type whose declaration it reads. Write them yourself for a nested type your type inherits from a superclass or a protocol. Under Bazel, Tuist, and a [custom build](#custom-build-system-integration), write them yourself for a nested type another module declares, too.

4. Spell a default value so that it compiles outside the type. Generated code copies a default value, as written, into an extension of the decorated type, where the members of the types that enclose the decorated type are not in scope. Write a type one of them declares with its enclosing types (`mode: Mode = Feature.Mode.fast`), or leave the type out (`= .fast`).

The `@Instantiable` macro offers fix-its for the first two requirements as you type, and for a nested type spelled through `Self` (`Self.Configuration`), which generated code cannot use. For any other nested type generated code cannot find, the compiler reports an error in the generated code. [Access levels](#access-levels) says what SafeDI checks when you build. Do not decorate a superclass with `@Instantiable`; see [Inheritance](#inheritance).

Here is a sample `LoggedInView` implementation that is `@Instantiable`. Like every `@Instantiable` type, it conforms to the `Instantiable` protocol. It is annotated with each of the three dependency-kind macros — `@Forwarded`, `@Received`, and `@Instantiated` — that together describe how dependencies enter a SafeDI scope:

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

- A property decorated with `@Forwarded` holds a runtime-created value, such as the authenticated `User` returned from sign-in, which is forwarded into the tree when this type is instantiated and made available to the rest of this scope and its subtree.
- A property decorated with `@Received` holds a dependency that was instantiated or forwarded further up the tree and is being received here.
- A property decorated with `@Instantiated` holds a dependency that SafeDI instantiates when this type is instantiated. `noteStorage`’s own `@Received` inputs are resolved from this scope’s context.

[@Instantiated](#instantiated), [@Forwarded](#forwarded), [@Received](#received), and [Conditionally receiving dependencies](#conditionally-receiving-dependencies) cover each kind in detail, including `@Instantiated`’s parameters for dependency inversion and `@Received`’s `onlyIfAvailable` option.

#### Creating the root of your dependency tree

Any type decorated with `@Instantiable(isRoot: true)` is a root of a SafeDI dependency tree. In an extension on each root that has dependencies, SafeDI generates a no-parameter `public init()` that instantiates the tree; create the tree by calling that `init()`, not the root’s memberwise initializer. To bind that initializer to a global actor, or give it other attributes, see [Attributes for generated declarations](#attributes-for-generated-declarations).

SafeDI generates a root’s `init()` only in the module that declares the root. Run SafeDI in that module’s target (see [Generating your dependency tree](#generating-your-dependency-tree)), and call the `init()` from any module that depends on it.

A SwiftUI application’s natural root is its `App` type. A UIKit application’s app delegate already has a no-argument `init()`, inherited from `NSObject`, so create a custom `@Instantiable(isRoot: true) public final class Root: Instantiable` that the app delegate initializes and stores.

#### Access levels

Generated code must be able to call each type’s initializer. The access that takes depends on which module builds the type:

- Built in the module that declares it: any access but `private` and `fileprivate` works, so a type and its initializer can stay `internal`.
- Built in another module of the same package: `package`, `public`, or `open`.
- Built in a module of another package: `public` or `open`.

A type is built in the module of the root whose tree contains it, or of the mock that builds it. A [seam](#generating-a-dependency-tree-per-module), covered later, builds its tree in its own module.

The same access applies to every type enclosing the built type, and to whatever generated code calls in place of the initializer: an extension’s `instantiate(…)` method, or a [hand-written mock](#hand-written-mocks) method. SafeDI reports each declaration that needs wider access and names the change to make: the `@Instantiable` macro as you type, and `SafeDITool` when you build.

`package` access requires every module of the package to be compiled with the same `-package-name`. SwiftPM passes one automatically. An Xcode project sets the `SWIFT_PACKAGE_NAME` build setting, and [Bazel](#bazel), [Tuist](#tuist), and a [custom build system](#custom-build-system-integration) set it as their sections describe.

[Access of generated parameters](#access-of-generated-parameters) says how visible the parameters of the initializers and mocks SafeDI generates for other modules are, and [Generated imports](#generated-imports) which access level each generated import has.

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

With this in place, any `@Instantiated private let userService: UserService` elsewhere in the dependency tree builds a `DefaultUserService`, which a `@Received private let userService: UserService` below it receives — no decoration parameters needed.

SwiftUI’s `@ObservedObject` property wrapper requires a concrete `ObservableObject`, which a protocol type like `UserService` is not. To observe a protocol-typed dependency, make the protocol inherit `ObservableObject` and pair it with a concrete type-erasing wrapper (by convention prefixed with `Any`):

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

`AnyUserService` is neither `@Instantiable` nor a superclass of `DefaultUserService`, so tell SafeDI what to build and how to assign it:

```swift
@Instantiable(isRoot: true) @main
public struct NotesApp: App, Instantiable {
    // …

    // Builds a `DefaultUserService`, wraps it in `AnyUserService`, and observes it for SwiftUI updates.
    @ObservedObject @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true)
    private var userService: AnyUserService
}
```

`fulfilledByType` takes a string literal naming the concrete type to construct — here, `"DefaultUserService"`. Representing the type as a string allows for dependency inversion: none of the consuming module’s files needs to import the module that declares the fulfiller, though the consuming module must still depend on that module, and the code SafeDI generates [imports it](#generated-imports). `erasedToConcreteExistential: true` tells SafeDI that the constructed value must be wrapped via the property type’s initializer — here, `AnyUserService(_:)` — rather than assigned directly:

| Parameter | Logic | Example |
| --------- | ----- | ------- |
| `erasedToConcreteExistential: false` | **Cast:** `FulfillingType as PropertyType` | `MyViewController` → `UIViewController` |
| `erasedToConcreteExistential: true` | **Wrap:** `PropertyType(FulfillingType())` | `MyView` → `AnyView(MyView())` |

Wrapping needs a concrete existential, such as `AnyView`, with an initializer that takes the concrete type’s value, non-optional. For an optional dependency, SafeDI calls that initializer only when the value is present. An existential spelled with `any`, such as `any UserService`, or as a composition, such as `UserService & Sendable`, has no initializer: leave out `erasedToConcreteExistential`, and SafeDI assigns the value to it.

#### Making external types `@Instantiable`

Types that are declared outside of your project can be instantiated by SafeDI through an extension decorated with `@Instantiable`, which defines how to instantiate the extended type with a `static func instantiate(…) -> ExtendedType` function. That function must be visible to the code that constructs the type, as [Access levels](#access-levels) describes. Each of its parameters is a dependency it receives from further up the tree, under the parameter’s name: `editor` in `instantiate(for editor: Editor)`. A parameter with a default value is not a dependency: SafeDI calls `instantiate(…)` without it, and a generated mock offers it as an override.

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

Generic types can be instantiated by SafeDI through an extension decorated with `@Instantiable`, with one function of the form `static func instantiate(…) -> GenericType<ConcreteType>` for each concrete type.

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

#### Attributes for generated declarations

SafeDI generates a root’s `init()`, the initializers of a [seam](#generating-a-dependency-tree-per-module) (a type with `generateDependencyTree: true`), and the `mock()` of a type with `generateMock` or listed in a module’s `additionalMocksToGenerate` (see [Mock generation](#mock-generation)). SafeDI cannot tell from your source every attribute these declarations need, such as the global actor of an initializer they call. Three `@Instantiable` arguments add attributes to them:

| Argument | Adds its text to |
| -------- | ---------------- |
| `generatedInitializerAttributes` | The root’s generated `init()`, or every initializer generated for a type with `generateDependencyTree: true`. |
| `mockAttributes` | The generated `mock()`. |
| `generatedAttributes` | Both. |

If a root is not bound to the main actor, and its tree builds a type whose initializer is `@MainActor`, give the root `generatedInitializerAttributes: "@MainActor"`:

```swift
@Instantiable(isRoot: true, generatedInitializerAttributes: "@MainActor")
public final class Root: Instantiable {
    public init(presenter: Presenter) {
        self.presenter = presenter
    }

    /// `Presenter`'s initializer is `@MainActor`.
    @Instantiated private let presenter: Presenter
}
```

SafeDI writes the text before the generated declaration's modifiers, on the same line:

```swift
extension Root {
    @MainActor public convenience init() {
        let presenter = Presenter()
        self.init(presenter: presenter)
    }
}
```

Likewise, if a type is not bound to the main actor, and its own initializer is `@MainActor`, or its tree builds a type whose initializer is, give it `mockAttributes: "@MainActor"`:

```swift
@Instantiable(mockAttributes: "@MainActor", generateMock: true)
public final class MyPresenter: Instantiable {
    @MainActor public init() { … }
}
```

`generatedAttributes` is the shorthand for giving both the same text, and cannot be combined with either of the other two.

```swift
@Instantiable(isRoot: true, generatedAttributes: "@MainActor", generateMock: true)
public final class Root: Instantiable { … }
```

Each argument must be a string literal.

In a module whose declarations default to the main actor (`-default-isolation MainActor`, which new Xcode 26 app targets use), give each type that conforms only to `Instantiable` `generatedAttributes: "@MainActor"`, because otherwise it is inferred `nonisolated` and its generated code cannot call its main-actor dependencies.

When a type’s hand-written mock is in a separate [`mockOnly` declaration](#splitting-production-and-mock-declarations), put `mockAttributes` on the production declaration: the generated `mock()` takes its attributes from there.

### @Instantiated

Property declarations within `@Instantiable` types decorated with [`@Instantiated`](../Sources/SafeDI/Decorators/Instantiated.swift) are instantiated when its enclosing type is instantiated. `@Instantiated`-decorated properties are available to be `@Received` by objects instantiated further down the dependency tree.

To instantiate a dependency later than its enclosing type, declare the property as an [`Instantiator`](#instantiator) or a [`LazilyInstantiated`](#lazilyinstantiated). [Delayed instantiation](#delayed-instantiation) compares the three.

Each `@Instantiated` property is a distinct instance.

`@Instantiated`-decorated properties must be an `@Instantiable` type, or a type listed in an `@Instantiable(fulfillingAdditionalTypes:)` declaration.

An `@Instantiated` property’s type cannot be optional, because SafeDI always creates it; a dependency that may be absent is received with [`@Received(onlyIfAvailable: true)`](#conditionally-receiving-dependencies).

In a SwiftUI `View`, `@Instantiated` objects are re-initialized each time SwiftUI recreates the view; see this [deep dive on SwiftUI view lifecycles](https://www.donnywals.com/understanding-how-and-when-swiftui-decides-to-redraw-views/).

### @Forwarded

Property declarations within `@Instantiable` types decorated with [`@Forwarded`](../Sources/SafeDI/Decorators/Forwarded.swift) represent runtime-created instances or values, such as the authenticated `User` returned from sign-in, a network response, or user input. Like an `@Instantiated`-decorated property, a `@Forwarded`-decorated property is available to be `@Received` by objects instantiated further down the dependency tree.

A `@Forwarded` property is forwarded into the SafeDI dependency tree by an [`Instantiator`](#instantiator)’s `instantiate(_:)` function that creates an instance of the property’s enclosing type. For the `LoggedInView` [above](#instantiable), the root that passes the authenticated user in uses the child’s `Instantiator`:

```swift
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

With more than one `@Forwarded` property, `instantiate(_:)` takes them as one tuple, the generated `ForwardedProperties` typealias (see [Instantiator](#instantiator)).

A forwarded type need not be `@Instantiable`. SafeDI does not build a forwarded value, so it does not look at the dependencies of its type.

Forwarding one of SafeDI’s wrappers – an [`Instantiator`](#instantiator), [`ErasedInstantiator`](#erasedinstantiator), or [`LazilyInstantiated`](#lazilyinstantiated), or one of their [`Sendable` twins](#sendable-wrappers) – is deprecated, and SafeDI 3.0 rejects it. Replace `@Forwarded let detailBuilder: Instantiator<Detail>` with one of:

- `@Instantiated let detailBuilder: Instantiator<Detail>`, with `Detail` `@Instantiable`, and what `Detail` needs forwarded or received. A `LazilyInstantiated` declared this way still builds nothing until its instance is first read.
- `@Received let detailBuilder: Instantiator<Detail>`, provided by a type above that declares it.
- `@Forwarded let detail: Detail`, the value itself, which then exists as soon as this type does.

To build a value SafeDI cannot build, later or more than once, forward a closure that builds it, such as `@Forwarded let makeReport: () -> Report`. Types below can receive the closure and call it. SafeDI treats a closure, or a wrapper type of your own, as a plain forwarded value.

### @Received

Property declarations within `@Instantiable` types decorated with [`@Received`](../Sources/SafeDI/Decorators/Received.swift) are injected into the enclosing type’s initializer. SafeDI fills a `@Received` property from the nearest type above it that instantiates, forwards, or [renames](#renaming-and-retyping-dependencies) a property with the same label. If no type above provides the property, the build fails.

That property must have the received type, with two exceptions:

- An optional receive, `user: User?`, also accepts a non-optional `user: User`.
- A receive of `X` also accepts a [`LazilyInstantiated<X>`](#lazilyinstantiated), and receives its instance.

Continuing the [Macros intro](#macros) example: `LoggedInView` has a `@Forwarded user: User` and an `@Instantiated noteStorage: NoteStorage`. `NoteStorage` can `@Received` the same `user` instance from anywhere in the subtree below `LoggedInView`:

```swift
@Instantiable
public class NoteStorage: Instantiable {
    public init(user: User, stringStorage: StringStorage, defaultNote: String = "") {
        self.user = user
        self.stringStorage = stringStorage
        self.defaultNote = defaultNote
    }

    // Forwarded into the tree by `LoggedInView`.
    @Received private let user: User

    // Instantiated further up the tree.
    @Received private let stringStorage: StringStorage

    private let defaultNote: String
    private var noteKey: String { "note-for-\(user.name)" }
}
```

Receiving a property [only if available](#conditionally-receiving-dependencies) makes nothing available to the types below the receiver. A type further down that requires the same property still needs a type above to provide it.

SafeDI ignores `any` when it matches types: `any SessionsApi` and `SessionsApi` are one type, also in [renames](#renaming-and-retyping-dependencies) and `fulfillingAdditionalTypes`.

A `@Received` property can also receive a dependency only when it is available, as [Conditionally receiving dependencies](#conditionally-receiving-dependencies) describes, or under another name and type, as [Renaming and retyping dependencies](#renaming-and-retyping-dependencies) describes.

### #SafeDIConfiguration

[`#SafeDIConfiguration`](../Sources/SafeDI/Decorators/SafeDIConfiguration.swift) is a freestanding declaration macro that provides build-time configuration for SafeDI’s code generation plugin. A module needs one only to set one of its parameters. Declare it at the top level of a file named `SafeDIConfiguration.swift`, with literal arguments. Declare at most one in any one build of a module. To configure builds differently, declare one in each clause of an `#if` block on compilation conditions such as `DEBUG`; SafeDI reads every clause of a platform condition such as `os(iOS)`, so one in each clause there is an error. Every parameter has a default, so the simplest valid invocation is `#SafeDIConfiguration()`.

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
- `additionalDirectoriesToInclude`: Extra directories, relative to the executing directory, whose Swift files SafeDI reads. An entry may also name a single Swift file. SafeDI does not know which module declares these files, which has the limits [Limits of the Xcode project plugin](#limits-of-the-xcode-project-plugin) lists. Only the `SafeDIGenerator` plugin declares these files as build inputs, so under [Tuist](#tuist) and [Bazel](#bazel), list the files in the build target instead, as their sections say. Default: `[]`.
- `additionalMocksToGenerate`: Type names from dependent modules to generate `mock()` methods for in this module. The types must be `@Instantiable` in their home module. See [Cross-module mock generation](#cross-module-mock-generation). Default: `[]`.
- `mockConditionalCompilation`: The conditional compilation flag to wrap generated mock code in (e.g. `"DEBUG"`). Set to `nil` to generate mocks without conditional compilation. Default: `"DEBUG"`.
- `generatePlainDependencyTreeInitializers`: For each type this module declares with `generateDependencyTree: true`, whether SafeDI pairs each initializer whose labels start with `__safeDI_` with one that has readable labels, for code you write (see [Generating a dependency tree per module](#generating-a-dependency-tree-per-module)). Default: `false`.

## Delayed instantiation

To instantiate a dependency after `init(…)`, declare an `Instantiator<Dependency>`-typed property as `@Instantiated` or `@Received`. Deferred instantiation helps where a dependency is expensive to create or only required under certain conditions (e.g., a detail view for an item selected in a list).

An `Instantiator` creates a new instance each time it is asked for one. For a single, shared instance that is created only once something needs it, declare a [`LazilyInstantiated<Dependency>`](#lazilyinstantiated)-typed property instead. The two differ from each other, and from a plain `@Instantiated` property, as follows:

| | `@Instantiated let dependency: Dependency` | `Instantiator<Dependency>` | `LazilyInstantiated<Dependency>` |
| --- | --- | --- | --- |
| An instance is created | When the declaring type is created | Each time `instantiate()` is called | The first time `instance` is read |
| Instances created | One | One per call | One |
| Types further down the tree can receive | The instance | The `Instantiator` | The instance, or the `LazilyInstantiated` |
| `Dependency` can have `@Forwarded` properties | No | Yes | No |
| Can break a dependency cycle | No | Yes | No |
| `Sendable` twin | – | [`SendableInstantiator<Dependency>`](#sendable-wrappers) | [`SendableLazilyInstantiated<Dependency>`](#sendable-wrappers) |

SafeDI recognizes its wrapper types – `Instantiator`, `SendableInstantiator`, `ErasedInstantiator`, `SendableErasedInstantiator`, `LazilyInstantiated`, and `SendableLazilyInstantiated` – by name alone, so do not declare types with these names in a project that uses SafeDI.

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

#### Dependency cycles

An `Instantiator` also lets types create one another, which forms a dependency cycle. For example, a `ProfileView` can instantiate an `Instantiator<FollowersView>`, and a `FollowersView` an `Instantiator<ProfileView>`. SafeDI accepts a cycle when at least one `@Instantiated` property along it is an `Instantiator`, an `ErasedInstantiator`, or a `Sendable` twin of either. Each time that property builds its type, the other types along the cycle are built again, as new instances.

Inside a cycle, a `@Received` property still takes the nearest declaration above it. Say `Screen` receives `session` and instantiates an `Instantiator<Step>`, and `Step` instantiates its own `session` and an `Instantiator<Screen>`. A `Screen` that `Step` builds receives `Step`’s `session`.

A `@Received` property cannot close a cycle. If `Child` receives `parent`, and that `parent` is the `Parent` still being built above it, SafeDI reports an error. Declare `@Received(onlyIfAvailable: true) let parent: Parent?` instead, and `Child` gets `nil` for it, as [Conditionally receiving dependencies](#conditionally-receiving-dependencies) describes.

In a generated mock, one dependency in each cycle has no `SafeDIOverrides` entry, and neither does anything built through it.

### ErasedInstantiator

For deferred instantiation of a type-erased dependency, use an [`ErasedInstantiator`](../Sources/SafeDI/DelayedInstantiation/ErasedInstantiator.swift), which combines the deferred construction of [`Instantiator`](#instantiator) with the `fulfilledByType` and `erasedToConcreteExistential` parameters covered in [Making protocols `@Instantiable`](#making-protocols-instantiable).

`ErasedInstantiator` has two generics. The first is what you pass to `instantiate(_:)`, the built type’s `@Forwarded` properties:

- `()` when the type has none, as in the example below;
- the property’s type when it has one;
- a tuple of their types, labeled and ordered by label, when it has several, such as `(count: Int, name: String)`.

You can also write the built type’s `ForwardedProperties` typealias. The second generic is the type of the instance it returns. If SafeDI cannot match your spelling, it reports an error that names one it can.

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

An `@Instantiated` erased instantiator must name the type it builds with `fulfilledByType`. A `@Received` one names no type: a type below `ParentView` can declare `@Received let childViewBuilder: ErasedInstantiator<(), AnyView>` to receive the instantiator `ParentView` creates. Spell the received type exactly as the declaration it receives does. If one writes the `ForwardedProperties` typealias and the other writes the tuple it stands for, they do not match.

### LazilyInstantiated

An [`Instantiator`](#instantiator) creates a new instance every time you call `instantiate()`. A [`LazilyInstantiated`](../Sources/SafeDI/DelayedInstantiation/LazilyInstantiated.swift) dependency is created once, the first time its `instance` is read, and every later read returns that same instance. Use it for a dependency that is expensive to create, or that some sessions never need, but that the rest of the dependency tree should still share.

```swift
@Instantiable(isRoot: true) @main
public struct NotesApp: App, Instantiable {
    // …

    // No `ExportService` is created when the app launches.
    @Instantiated private let exportService: LazilyInstantiated<ExportService>
    @Instantiated private let exportViewBuilder: Instantiator<ExportView>
    @Instantiated private let diagnosticsViewBuilder: Instantiator<DiagnosticsView>
}

@Instantiable
public struct ExportView: View, Instantiable {
    // …

    // Receives the instance. The first `ExportView` to be created instantiates the `ExportService`.
    @Received private let exportService: ExportService
}

@Instantiable
public struct DiagnosticsView: View, Instantiable {
    // …

    // Receives the `LazilyInstantiated` itself, so creating a `DiagnosticsView` instantiates nothing.
    // The `ExportService` is created if and when this view reads `exportService.instance`.
    @Received private let exportService: LazilyInstantiated<ExportService>
}
```

A type further down the dependency tree receives a lazily instantiated dependency in one of two ways, and both yield the same instance:

- **As the instance:** `@Received private let exportService: ExportService`. The receiving type is written exactly as it would be if the dependency were not lazy. The dependency is instantiated when the first type that receives it this way is created.
- **As the `LazilyInstantiated`:** `@Received private let exportService: LazilyInstantiated<ExportService>`. The dependency stays uninstantiated until something reads `instance`.

A `LazilyInstantiated` whose instance may be `nil`, such as `LazilyInstantiated<ExportService>?` or `LazilyInstantiated<ExportService?>`, can be received only as the `LazilyInstantiated`, not as its instance.

Receiving the instance creates it. If a type created together with the declaring type receives the instance, the instance is created at once, not lazily, and SafeDI warns at the `LazilyInstantiated` declaration. To keep it lazy, receive the instance only in types created later, typically by an [`Instantiator`](#instantiator), as `ExportView` is above.

A `LazilyInstantiated` property accepts the same `fulfilledByType` and `erasedToConcreteExistential` parameters as any other `@Instantiated` property:

```swift
@Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true)
private let userService: LazilyInstantiated<AnyUserService>
```

Reads of a `LazilyInstantiated`’s `instance` are not synchronized. To share one across concurrency domains, use its [`Sendable` twin](#sendable-wrappers).

SafeDI checks the dependency tree, not what your initializers do. Do not read `instance` from the initializer of the type that declares the `LazilyInstantiated` or `SendableLazilyInstantiated` property, or from any initializer that runs while that instance is being created, directly or through a callback. Doing so is undefined behavior:

```swift
@Instantiable
public final class Exporter: Instantiable {
    public init(exportService: LazilyInstantiated<ExportService>) {
        self.exportService = exportService
        exportService.instance.prepare() // Undefined behavior: `Exporter` declares `exportService`.
    }

    @Instantiated private let exportService: LazilyInstantiated<ExportService>
}
```

Read `instance` after initialization instead, such as in a method or a view’s `body`. The documentation of [`LazilyInstantiated`](../Sources/SafeDI/DelayedInstantiation/LazilyInstantiated.swift) and [`SendableLazilyInstantiated`](../Sources/SafeDI/DelayedInstantiation/SendableLazilyInstantiated.swift) states what each type guarantees.

[Dependency kinds in the generated mock](#dependency-kinds-in-the-generated-mock) says how a mock overrides a lazily instantiated dependency.

### Sendable wrappers

`Instantiator`, `ErasedInstantiator`, and `LazilyInstantiated` are not `Sendable`. To share one across concurrency domains, declare its `Sendable` twin: [`SendableInstantiator`](../Sources/SafeDI/DelayedInstantiation/SendableInstantiator.swift), [`SendableErasedInstantiator`](../Sources/SafeDI/DelayedInstantiation/SendableErasedInstantiator.swift), or [`SendableLazilyInstantiated`](../Sources/SafeDI/DelayedInstantiation/SendableLazilyInstantiated.swift).

A `SendableLazilyInstantiated` creates its instance exactly once, while holding a lock, and requires the instance to be `Sendable`. It is available on macOS 15, iOS 18, tvOS 18, watchOS 11, and visionOS 2 and later. The generated code is not decorated with `@available`, so use it only in a module whose deployment targets are at least those versions.

A `Sendable` wrapper builds its dependency in a `@Sendable` function that runs on no actor. The dependency need not be `Sendable`, but two rules apply to the types the function builds:

- **What they receive from outside the wrapper must be `Sendable`**, since the function captures it. This includes the types a [dependency cycle](#dependency-cycles) builds again inside the wrapper. A SafeDI wrapper they receive from outside, or whose instance they receive, must be a `Sendable` twin; SafeDI reports one that is not and says which declarations to change. Wrappers instantiated inside the same `Sendable` wrapper are fine. For any other value that is not `Sendable`, the compiler reports an error in the generated code.
- **Their initializers must not need an actor.** The function calls each initializer synchronously, on no actor. The same goes for an extension’s `instantiate(…)`, and for a hand-written mock method a generated mock calls there. SafeDI does not check this; the generated code fails to compile.

For example, this does not compile, because `Screen`’s initializer is isolated to the main actor:

```swift
@MainActor
@Instantiable
public final class Screen: Instantiable {
    public init() {}
}

// In another `@Instantiable` type:
@Instantiated private let screenBuilder: SendableInstantiator<Screen>
```

Declare the initializer `public nonisolated init()` to fix it. The initializer’s isolation counts, not the type’s: a `@MainActor` class with a `nonisolated init` is fine when its stored properties are `Sendable`. [Attributes for generated declarations](#attributes-for-generated-declarations) do not help, since the function runs on no actor whatever the generated `init()` or `mock()` around it is isolated to.

**If you need a `@MainActor` initializer**, declare the wrapper as its non-`Sendable` twin – `Instantiator`, `ErasedInstantiator`, or `LazilyInstantiated` – instead. SafeDI builds a non-`Sendable` wrapper’s dependency with the isolation of the generated `init()` or `mock()` around it, so that `init()` or `mock()` must be `@MainActor`: the root or mocked type is, or [attributes for generated declarations](#attributes-for-generated-declarations) say so. This does not work inside a `Sendable` wrapper’s subtree, where nothing runs on an actor.

Generated mocks follow the same rules; [Overriding dependencies](#overriding-dependencies) says what a `Sendable` wrapper changes in a mock.

## Conditionally receiving dependencies

Use `@Received(onlyIfAvailable: true)` to receive an optional dependency only when a parent has `@Instantiated` or `@Forwarded` it. This is useful when a type is instantiated by multiple parents with different available dependencies — for example, a `FeedView` used by both a logged-in and logged-out parent:

```swift
@Instantiable
public struct FeedView: Instantiable {
    // Populated when reached from `LoggedInView`; `nil` when reached from `LoggedOutView`.
    @Received(onlyIfAvailable: true) private let user: User?
}
```

The receiver still receives from the [nearest declaration](#received) of the label above it. SafeDI builds a type’s properties in the order they are declared, but builds a property before an earlier one whose tree receives it, even only if available. When two properties receive each other, one must be built first, as below. A receiver gets `nil` for a dependency that is not built yet. Take a parent that instantiates two properties:

```swift
@Instantiable
public struct Parent: Instantiable {
    @Instantiated let a: A
    @Instantiated let b: B // A type under `B` receives `a`.
}
```

`Parent` builds `a` first, so a type under `B` that receives `a` gets `Parent`’s `a`. A receiver gets `nil` for `a` in two cases:

- **`a` is still being built.** The receiver is `a` itself, or a type `a` builds: one it instantiates, or one it builds as an `Instantiator`.
- **`a` and `b` receive each other.** One of them must be built first, and it gets `nil` for the other:
  - If `A` requires `b`, and `B` receives `a` only if available, SafeDI builds `b` first, and `b` gets `nil` for `a`.
  - If both receive each other only if available, SafeDI builds the property declared later, `b`, first, and `b` gets `nil` for `a`.

A renamed dependency follows the same rules; see [Renaming and retyping dependencies](#renaming-and-retyping-dependencies).

## Renaming and retyping dependencies

Use `@Received(fulfilledByDependencyNamed:ofType:)` to give a dependency a second name and type. `fulfilledByDependencyNamed` names an `@Instantiated` or `@Forwarded` property of this type. If this type has none of that name, SafeDI looks for it above, as for any [`@Received`](#received) property. Types further down the tree can then `@Received` the same instance under either name and type.

Here, a parent instantiates a read-write `UserManager`, and renames it to make it available as a `UserVendor`. A child receives the same instance as the read-only `UserVendor`:

```swift
public protocol UserVendor { var user: User { get } }
public protocol UserManager: UserVendor { var user: User { get set } }

@Instantiable
public struct LoggedInView: Instantiable {
    @Instantiated private let userManager: UserManager
    @Received(fulfilledByDependencyNamed: "userManager", ofType: UserManager.self) private let userVendor: UserVendor
    @Instantiated private let profileViewBuilder: Instantiator<ProfileView>
}

@Instantiable
public struct ProfileView: Instantiable {
    @Received private let userVendor: UserVendor
}
```

`ofType:` must name the renamed property’s type exactly, or, for a `LazilyInstantiated` property, its instance type. SafeDI does not check that the new type can hold the original; the Swift compiler checks the generated assignment and reports a mismatch.

To receive the renamed dependency inside a type-erasing wrapper, add `erasedToConcreteExistential: true`, which wraps it as [`@Instantiated` erasure](#making-protocols-instantiable) does: a property `userVendor: AnyUserVendor` is assigned `AnyUserVendor(userManager)`.

When the renamed dependency is optional (`ofType: UserManager?.self`), declare the property optional too (`let userVendor: UserVendor?`). It is `nil` where the dependency is `nil`.

A rename with `onlyIfAvailable: true` has an optional type. It is `nil` wherever an `onlyIfAvailable` receive of its dependency would be ([Conditionally receiving dependencies](#conditionally-receiving-dependencies)). It is also `nil` where the nearest declaration holds the dependency’s optional form and that is `nil`. Types below that receive the rename’s name get its value, `nil` included. Where one parent builds both the dependency and a type that requires the rename, SafeDI builds the dependency first.

A rename cannot start from another rename on the same type. Start it from the property the first rename starts from.

A rename may keep the original label, to change only the type. A type below `LoggedInView` can declare `@Received(fulfilledByDependencyNamed: "userManager", ofType: UserManager.self) private let userManager: UserVendor`. Types below that type then receive `userManager` only as a `UserVendor`.

### Sharing one instance across properties of disparate types

You can rename the same `@Instantiated` or `@Forwarded` property more than once, so one instance can be received as several types: any type the instance can be assigned to, such as unrelated protocols it conforms to, or a superclass. Instantiate it once, then rename it once per type. Types further down the tree receive whichever type they need, and all of them get the same instance:

```swift
public protocol EventTracker { func track(_ event: String) }
public protocol CrashReporter { func report(_ error: Error) }

@Instantiable
public final class Telemetry: EventTracker, CrashReporter, Instantiable { /* … */ }

@Instantiable
public struct LoggedInView: Instantiable {
    // Instantiated once. Exists only to be renamed below.
    @Instantiated private let telemetryImplementation: Telemetry
    @Received(fulfilledByDependencyNamed: "telemetryImplementation", ofType: Telemetry.self) private let eventTracker: EventTracker
    @Received(fulfilledByDependencyNamed: "telemetryImplementation", ofType: Telemetry.self) private let crashReporter: CrashReporter
    @Instantiated private let profileViewBuilder: Instantiator<ProfileView>
}

@Instantiable
public struct ProfileView: Instantiable {
    // The same `Telemetry` instance that `LoggedInView` created.
    @Received private let crashReporter: CrashReporter
}
```

The instantiated type can also be a protocol composition, with no typealias: `@Instantiated private let telemetry: EventTracker & CrashReporter` is fulfilled by a type that lists `(EventTracker & CrashReporter).self` in `fulfillingAdditionalTypes`, and the renames then use `ofType: (EventTracker & CrashReporter).self`.

Generated mocks resolve `@Received` dependencies from their declared types rather than from these renames. See [Dependency kinds in the generated mock](#dependency-kinds-in-the-generated-mock) for what that means for `ProfileView.mock()`.

## Generating a dependency tree per module

A root’s generated `init()` builds the whole tree in the root’s module. In a large app, every type in the tree must then be visible to that module, and any change regenerates and recompiles the whole tree there.

A seam lets a feature module compile its own part of the tree. Decorate a type at a module’s boundary, such as a feature’s entry point, with `@Instantiable(generateDependencyTree: true)`. That type is a seam. Its own module generates the seam’s tree as an initializer that takes what the tree needs from outside. Trees in other modules call that initializer instead of building the seam’s tree themselves, so a change inside the seam’s tree recompiles only the seam’s module and the calls. Building a tree inline, by contrast, means the caller’s own generated code builds every type in it, as it does without a seam. Unlike a root, a seam may receive and forward dependencies. [Adopting SafeDI in a large codebase](#adopting-safedi-in-a-large-codebase) says where seams go. The Xcode project plugin [builds these trees inline instead](#limits-of-the-xcode-project-plugin).

For example, `Screen` receives a `User` and instantiates a `Cache`, which receives a `Database` and, only if available, a `Logger`:

```swift
// In module Feature.
@Instantiable(generateDependencyTree: true)
public struct Screen: Instantiable {
    public init(user: User, cache: Cache) {
        self.user = user
        self.cache = cache
    }

    @Received private let user: User
    @Instantiated private let cache: Cache
}

@Instantiable
public struct Cache: Instantiable {
    public init(database: Database, logger: Logger?) {
        self.database = database
        self.logger = logger
    }

    @Received private let database: Database
    @Received(onlyIfAvailable: true) private let logger: Logger?
}
```

SafeDI generates, in `Feature`:

```swift
extension Screen {
    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
    public init(__safeDI_user user: User, __safeDI_database: @autoclosure @escaping () -> Database, __safeDI_logger: @autoclosure @escaping () -> Logger?) {
        let database = LazilyInstantiated<Database>(__safeDI_database)
        let logger = LazilyInstantiated<Logger?>(__safeDI_logger)
        let cache = Cache(database: database.instance, logger: logger.instance)
        self.init(user: user, cache: cache)
    }
}

extension Screen {
    public enum __safeDI_Screen_3192EA1C03ABD98F {}
}
```

Its labels each start with `__safeDI_`: as its comment says, only code SafeDI generates calls it, and its shape can change in any release, so do not call it by hand. It takes, in order:

1. The seam’s own `@Received` and `@Forwarded` properties, in declaration order, as the seam declares them.
2. Each property the tree receives that nothing inside the tree provides, in label order. Such a parameter is optional, like `logger: Logger?`, when every type that receives it does so only if available. Otherwise it is required, and its type is optional, like `session: Session?`, when every type that requires it declares it optional.

No parameter has a default. A property the tree receives from outside it by value is an `@autoclosure`, read at most once, when the tree first needs it, so a generated call creates each value where the tree would create it inline. A wrapper the tree receives as itself, and the seam’s own properties, are taken by value.

A seam with no `@Instantiated` or renamed dependency, and nothing to pass through, gets no generated initializer. Callers then call the seam’s own initializer.

To call the seam from code you write, such as code that does not use SafeDI yet, set `generatePlainDependencyTreeInitializers: true` in the seam’s module’s [`#SafeDIConfiguration`](#safediconfiguration). SafeDI then also generates an initializer with readable labels, here `Screen(user:database:logger:)`, which takes every parameter as a plain value. So a hand-written call creates every argument before the call, even one the tree never reads. The seam keeps nothing of the caller but the builders for its holes, described below, which it can call after the initializer returns. To keep a value lazy, receive it inside the seam as `LazilyInstantiated<X>`; the initializer then takes the wrapper.

A tree that reaches the seam passes `nil` for an optional parameter its own tree does not provide, as for `logger` here, by the usual [availability rule](#conditionally-receiving-dependencies). Each type in the seam’s tree gets the value it would get if the caller built the tree inline, except as [Where a seam differs from building its tree inline](#where-a-seam-differs-from-building-its-tree-inline) lists. Here is the call SafeDI generates:

```swift
// Generated in module App, whose root instantiates Screen.
func __safeDI_screen() -> Screen {
    _ = Screen.__safeDI_Screen_3192EA1C03ABD98F.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
    return Screen(__safeDI_user: user, __safeDI_database: database, __safeDI_logger: nil)
}
```

The call’s first line names the enum generated beside the initializers, whose name changes when the initializers’ parameters change. So the line fails to compile when the seam’s module did not generate the initializer this call expects, and its comment says what to fix under your build system.

Because no parameter has a default, a hand-written call of the initializer with readable labels fails to compile when that initializer gains or loses a parameter, or when a parameter’s type changes to one the argument does not convert to. Access levels can keep an added parameter off the initializer a hand-written call names, as described below.

The seam’s generated initializers have the seam’s access, limited by any type that encloses the seam. Each of their parameters is as visible as the types it names ([Access of generated parameters](#access-of-generated-parameters)). When some parameters are narrower than the seam, SafeDI generates a tier of initializers for each access level. For a `public` seam whose tree receives a `package` type from outside only if available:

- the `public` tier takes the `public` parameters, and passes `nil` for the `package` ones;
- the `package` tier takes every parameter.

So a required parameter narrower than the seam is an error at the seam, since a wider tier has no value to pass for it; the error says what to change. Each tree calls the narrowest tier it can reach, and SafeDI checks that it can, as it checks a root’s tree ([Access levels](#access-levels)).

Only the parameters’ types must be as visible as the tier; the types the tree builds keep their own access. Here, in a module that sets `generatePlainDependencyTreeInitializers: true`, `Service` is `public`, and `Badge`, which it instantiates, has a `package` initializer and receives a `public` `Analytics`. `analytics` is a parameter of both of `Service`’s `public` initializers:

```swift
extension Service {
    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained.
    public init(analytics: Analytics) {
        self.init(__safeDI_analytics: analytics)
    }

    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    /// From code you write, call the initializer above instead.
    public init(__safeDI_analytics: @autoclosure @escaping () -> Analytics) {
        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
        let badge = Badge(analytics: analytics.instance)
        self.init(badge: badge)
    }
}
```

Here is what happens when the tree gains a narrower parameter. Suppose `Badge` adds `@Received(onlyIfAvailable: true) let theme: Theme?`, and `Theme` is `package`:

- `Service`’s `public` initializers are unchanged, and pass `nil` for `theme`. So a hand-written `Service(analytics: analytics)`, which calls the `public` initializer with readable labels, keeps compiling, and passes `nil` for `theme`, even in a module that has a `Theme`.
- A new `package` tier takes `analytics` and `theme`. To pass a `Theme` by hand, call `Service(analytics: analytics, theme: theme)`.
- A generated call from a tree that holds a `theme` calls the `package` tier and passes it. A tree that holds one but cannot reach that tier is an error.

A new parameter at least as visible as the seam is on every tier, so hand-written calls stop compiling until they pass it.

A hole is a type the seam’s tree instantiates that no `@Instantiable` declaration visible to the seam’s module fulfills, such as a protocol that only the app implements. The seam’s initializer takes one builder per hole type, named for that type: `serviceBuilder` for `Service`, `urlLoaderBuilder` for `URLLoader`. A builder is a closure that is handed a scope saying which place in the tree wants a value, and returns the value the property holds. So `{ _ in Implementation() }` fills every place of the type.

The scope is an enum, such as `SafeDIScope_Service`:

- It has a case for each place the seam builds the type, named by the labels on the path to it, such as `.profile_userService`. The case’s payload holds the values in scope at that place.
- It has a case for each inner seam that holds places of the type, named by the path to the inner seam, such as `.inner`. The case’s payload is that seam’s enum: `case .inner:` leaves it closed, and `case let .inner(inner):` opens it.

A property held in a wrapper is no different to write: the closure returns the plain value, and the generated initializer builds the `LazilyInstantiated`, `Instantiator` or other wrapper around it. An instantiator calls the closure each time it instantiates, and hands it the value it forwards as the case’s second value, as in `case let .maker(values, name):`. That value’s type is `ErasedInstantiator`’s first generic type, which is left out only when spelled `()` or `Void`, and always `T.ForwardedProperties` for `Instantiator<T>`, since the seam’s module cannot always see whether `T` forwards anything.

Two hole types whose names collide are named apart by the type each returns, so `implBuilder` becomes `impl_ServiceBuilder` beside `impl_AnyServiceBuilder`. A builder, and each value in its scope, is as visible as the types it names, including an inner seam’s enum and a forwarded value’s type.

> **Note:** `@Sendable` functions add builders. Where an inner seam’s enum reaches a `@Sendable` function, a second builder, `serviceSendableBuilder`, takes a `SafeDISendableScope_Service`. A call in a `@Sendable` function gets its case there, as does an inner seam’s own `@Sendable` enum, whose case ends in `_Sendable`. A place the seam builds inside a `@Sendable` function, or holds in a [`Sendable` wrapper](#sendable-wrappers), is staged: it has a builder of its own, `serviceBuilder_<case>`, that works in steps. It is handed the values bound before the first `@Sendable` function, and returns a `@Sendable` closure that is handed the values bound inside it, and so on. The last step returns the value and takes any forwarded value: `{ _ in { _ in Implementation() } }`. A staged place an inner seam holds is passed up as `serviceBuilder_<InnerSeam>_<case>`.

Here, `Service` instantiates a `Profile`, which instantiates a `UserService` that only module `App` implements:

```swift
// Generated in module Feature, where `Profile` instantiates `userService: any UserService`.
extension Service {
    @frozen public enum SafeDIScope_UserService {
        case profile_userService(profile_userService_Values)

        public struct profile_userService_Values {
            public let analytics: Analytics
        }
    }

    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
        let analytics = Analytics()
        func __safeDI_profile() -> Profile {
            let userService: any UserService = __safeDI_userServiceBuilder(.profile_userService(SafeDIScope_UserService.profile_userService_Values(analytics: analytics)))
            return Profile(userService: userService, analytics: analytics)
        }
        let profile: Profile = __safeDI_profile()
        self.init(analytics: analytics, profile: profile)
    }
}
```

A tree that calls the seam fills the builder when its module can see an implementation, as `App`’s does:

```swift
// Generated in module App, which declares `DefaultUserService`, an implementation of `UserService`.
func __safeDI_service() -> Service {
    _ = Service.__safeDI_Service_D8E8DFCE0954DB42.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
    func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
        switch scope {
        case let .profile_userService(scope):
            let analytics = scope.analytics
            let userService: any UserService = DefaultUserService(analytics: analytics)
            return userService
        }
    }
    return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
}
```

The filling module builds the implementation from the case’s values and its own tree. Those types and initializers must be visible there, as a root’s are. A value the implementation receives must be in the case’s values or come from the filling module.

When a tree cannot fill a place: a seam passes it up through its own builder, whose enum holds the inner seam’s in a case, for its caller to fill, and a root reports an error.

A type stops being a hole once the seam’s module reads a declaration that fulfills it ([Which modules to list](#which-modules-to-list)). The seam then builds the type itself, and a hand-written call that passes its builder stops compiling.

A hand-written call fills a builder with a closure that switches over the scope and reads the values in its case:

```swift
// In module Feature, `ExportFeature` instantiates `screenBuilder: Instantiator<ExportScreen>` and `uploader: any Uploader`,
// and `ExportScreen` receives `exportService`. SafeDI generates the hole's enum, whose public members are:
@frozen public enum SafeDIScope_Uploader {
    case uploader(uploader_Values)

    public struct uploader_Values {
        public var exportService: ExportService { … } // For a value a generated call defers, created when first read, as inline.
        public let screenBuilder: Instantiator<ExportScreen>
    }
}

// In module App, which declares `DefaultUploader`, whose `UploadJob`s receive `exportService`, a hand-written call,
// which Feature's `generatePlainDependencyTreeInitializers: true` makes possible:
let feature = ExportFeature(exportService: exportService, uploaderBuilder: { scope in
    switch scope {
    case let .uploader(values):
        DefaultUploader(jobBuilder: Instantiator { UploadJob(exportService: values.exportService) })
    }
})
// `exportService` exists before this call, as every argument of a hand-written call does, whether or not an `UploadJob` is ever built.
// A generated call from a tree that holds the service as a `LazilyInstantiated` creates it when the first `UploadJob` is built, as inline.
```

## Mock generation

SafeDI can automatically generate `mock()` methods for `@Instantiable` types, drastically simplifying testing and SwiftUI previews.

### Enabling mock generation

To generate a `mock()` method for a type, set `generateMock: true` on the `@Instantiable` decorator:

```swift
@Instantiable(fulfillingAdditionalTypes: [UserService.self], generateMock: true)
public final class DefaultUserService: UserService, Instantiable {
    // …

    @Received private let stringStorage: StringStorage
}
```

By default, `generateMock` is `false` and no mock is generated. A mock generated with `generateMock: true` is `internal`; to call it from other modules, see [Cross-module mock generation](#cross-module-mock-generation). Generated mocks are wrapped in `#if DEBUG`, or in the condition your module’s [`#SafeDIConfiguration`](#safediconfiguration) sets as `mockConditionalCompilation`. To bind a generated mock to a global actor, or give it other attributes, see [Attributes for generated declarations](#attributes-for-generated-declarations).

### Using generated mocks

Each `@Instantiable` type with `generateMock: true` gets a generated `mock()` static method that builds its full dependency subtree. When the mock can build every dependency in that subtree, it can be called without arguments, as in `DefaultUserService.mock()` in a test, or in a preview:

```swift
#if DEBUG
#Preview {
    MyView.mock()
}
#endif
```

`mock()` takes as parameters the values it cannot build, such as the mocked type’s `@Forwarded` properties, and lets you replace any dependency it builds, as [Overriding dependencies](#overriding-dependencies) describes.

### Overriding dependencies

It can be helpful to think of a generated `mock()` as having three buckets:

1. Flat `mock()` parameters for values the caller owns directly at the root.
2. The `safeDIOverrides` parameter, whose `SafeDIOverrides` value lets you customize values that SafeDI surfaces through the generated dependency tree.
3. Nested `SafeDIMockConfiguration` values inside `SafeDIOverrides` when a child has its own subtree or default-valued construction inputs.

Here are all three buckets together in one call:

```swift
LoggedInView.mock(
    user: User(name: "dfed"),
    safeDIOverrides: .init(
        noteStorage: .init(defaultNote: "dfed says hello"),
        userService: StubUserService.init
    )
)
```

In that example, `user` is a flat `mock()` parameter, `noteStorage` uses a nested `SafeDIMockConfiguration` because it has its own configurable construction input, and `userService` is overridden directly on `SafeDIOverrides`.

Each entry on `SafeDIOverrides` is either a closure whose parameters match the resolved values of that dependency’s own inputs, or, when the dependency has its own `@Instantiated` subtree or default-valued init parameters, a nested `SafeDIMockConfiguration`. Pass any closure whose parameters match the dependency’s resolved inputs — a literal, or an `init` reference when its signature already matches:

```swift
LoggedInView.mock(
    user: User(name: "dfed"),
    safeDIOverrides: .init(
        // Literal closure — `StringStorage` has no inputs of its own, so its closure has no parameters:
        stringStorage: { InMemoryStorage() },
        // Init reference — `StubUserService.init(stringStorage:)` is already `(StringStorage) -> UserService`:
        userService: StubUserService.init
    )
)
```

`NoteStorage` has a default-valued `defaultNote` init parameter, so its entry is a nested `SafeDIMockConfiguration`:

```swift
// Tweak `defaultNote` without replacing how NoteStorage is built:
LoggedInView.mock(
    user: User(name: "dfed"),
    safeDIOverrides: .init(noteStorage: .init(defaultNote: "Welcome back"))
)

// Replace how NoteStorage itself is built. `StubNoteStorage` is a subclass of
// `NoteStorage` whose `init` matches the signature of `NoteStorage.init`, so we
// can pass its initializer directly as the builder:
LoggedInView.mock(
    user: User(name: "dfed"),
    safeDIOverrides: .init(noteStorage: .init(StubNoteStorage.init))
)
```

`SafeDIMockConfiguration` has an optional field for each of the child’s own `@Instantiated` dependencies and each labeled default-valued parameter of its `init` (or `instantiate(…)`), plus a final, unlabeled builder closure. A default-valued parameter’s field defaults to the default the type’s hand-written `mock` method declares for it, if any, and otherwise to its `init`’s (or `instantiate(…)`’s). The builder’s parameters match the hand-written `mock` method’s signature if one is defined, or the `init`’s otherwise; without a builder, the generated mock calls the hand-written `mock` method or `init` directly.

Outside the generated file, the fields of `SafeDIOverrides` and `SafeDIMockConfiguration` are read-only, because how they are stored may change: an initializer you write in an extension of one calls `self.init(…)` rather than assigning its fields.

> **Note:** Pass the builder in parentheses, as in `.init(StubNoteStorage.init)` above. Swift gives a trailing closure to the first closure field, which may not be the builder.

A labeled default-valued `@autoclosure` parameter, such as `retries: @autoclosure () -> Int = 3`, is evaluated each time the mock builds the type, as in production. You pass a value, as in `Service.mock(retries: 5)`, and a builder closure is handed an `Int`.

Closure fields on `SafeDIMockConfiguration` are not `@Sendable`, so an override can capture mutable test state that is not `Sendable`. Beneath a [`Sendable` wrapper](#sendable-wrappers), what you hand the mock for a type there must be `Sendable`: its override closures are `@Sendable`, and so are its default-valued initializer parameters and the dependencies it instantiates that the mock cannot build. The mock takes each of these values as a `@Sendable` autoclosure, and evaluates it each time it builds the type, as production does. You still write a value, as in `Root.mock(service: MockService())`, but it cannot capture non-`Sendable` test state, such as a `MockService` held in a `let` outside the call.

#### Dependency kinds in the generated mock

A mock builds every dependency it can: a type some `@Instantiable` declaration fulfills, directly or through `fulfillingAdditionalTypes`, or a type exactly one concrete type is [erased to](#receiving-a-type-erased-dependency). It cannot build, and so takes as a flat `mock()` parameter:

- A type no `@Instantiable` declaration fulfills, including a type [different concrete types are erased to](#receiving-a-type-erased-dependency).
- A type whose `@Instantiable` declaration has `@Forwarded` properties, received as itself: only an `Instantiator` handed the forwarded values can build it. A received `Instantiator` of it is built as usual.
- An `@Instantiated(fulfilledByType:)` dependency whose named type the mock’s module cannot see, when nothing it sees fulfills the property’s type. For example, a `DefaultUserService` declared in a module only the app imports, or, under Bazel, Tuist and custom builds, in a module the mock’s module does not [list](#which-modules-to-list). The parameter is only the mock’s: a root in the mock’s module that reaches the type still fails to generate until that module can see a fulfiller.

A type beneath the one that instantiates such a dependency, and receives it, is handed the parameter. Beneath a `Sendable` wrapper, the parameter is a `@Sendable` autoclosure, as [above](#overriding-dependencies).

The table below shows where each dependency kind lands in the three buckets above, and whether the caller has to supply it; a type whose dependencies are all flat parameters has no `SafeDIOverrides`.

| Dependency kind | Shape in the mock | Default |
| --- | --- | --- |
| `@Instantiated` | Entry on `SafeDIOverrides` | Built from the real subtree — see [Overriding dependencies](#overriding-dependencies) |
| `@Instantiated` the mock cannot build | Flat `mock()` parameter | Required |
| Required `@Received` the mock can build | Entry on `SafeDIOverrides` | Built from the real subtree, like `@Instantiated` |
| Required `@Received` the mock cannot build | Flat `mock()` parameter | Required, unless the type has a hand-written mock (below) |
| `@Received(onlyIfAvailable: true)` | Entry on `SafeDIOverrides`, typed as optional | `nil` |
| `@Forwarded` | Flat `mock()` parameter | Required, unless the root provides a default or the type has a hand-written mock (below) |
| Default-valued initializer parameter that is not a dependency | Flat `mock()` parameter on the mocked type, or a nested `SafeDIMockConfiguration` field on a type beneath it | The parameter’s original default expression |

A flat `mock()` parameter defaults to the hand-written mock the tree would build its type with – the type’s own, or a [`mockOnly`](#the-mockonly-parameter) fake’s – when that mock takes no required argument and this module can call it. So a forwarded `service: Service` whose fake is `FakeService` makes `mock(service: Service = FakeService.mock())`.

**Dependencies built with `fulfilledByType:`.** A mock builds an `@Instantiated(fulfilledByType:)` dependency as the app does: as the type `fulfilledByType:` names. So `@Instantiated(fulfilledByType: "DefaultUserService") let userService: any UserService` is built as a `DefaultUserService`, and its `SafeDIOverrides` entry configures `DefaultUserService`, even when another type lists `UserService` in `fulfillingAdditionalTypes`. Two kinds of [`mockOnly`](#the-mockonly-parameter) declaration change this:

- A `mockOnly` type of its own that fulfills `UserService`, such as a fake, replaces `DefaultUserService`.
- A `mockOnly` declaration of `DefaultUserService` supplies its mock.

A `mockOnly` extension of a type that has a production declaration is only that type’s mock. If `CoreUserService` lists `UserService`, a `mockOnly` extension of `CoreUserService` is used where the tree builds a `CoreUserService`, not for `userService`. When the mock’s module cannot see `DefaultUserService`’s declaration, the mock builds the type that fulfills `UserService` instead, or takes the dependency as a parameter when none does.

**One parameter, several types.** `mock()` takes one value for each dependency it cannot build, and hands it to every type in the tree that creates that dependency. When more than one type does, the parameter’s documentation lists them. Say `Profile` and `Settings` each instantiate `userService: AnyUserService` from a `DefaultUserService` the mock’s module cannot see: `Screen.mock(userService:)` hands both the same value, where the app creates one for each. To give one type its own instance, override how that type is built. The override’s closure is passed the value the mock would use, which this one ignores:

```swift
// `profile` gets `a`, and `settings` gets `b`.
Screen.mock(
    userService: a,
    safeDIOverrides: .init(settings: { _ in Settings(userService: b) })
)
```

An override changes only the type you name: a type beneath it that receives the dependency still gets the parameter, so override that type too. The mocked type itself has no entry, so give it its instance through the parameter, and override the others.

To give every type its own instance, as the app does, declare a [`mockOnly`](#the-mockonly-parameter) fake that fulfills the dependency’s type. The parameter goes away: the mock builds one fake for each type that creates the dependency, and `safeDIOverrides` can replace each one the tree has an entry for, as in `safeDIOverrides: .init(settings: .init(userService: { spy }))`. Beneath a `Sendable` wrapper, where the mock takes the parameter as a `@Sendable` autoclosure, nothing is shared: each type there evaluates the argument for an instance of its own.

**Lazily instantiated dependencies.** A [lazily instantiated](#lazilyinstantiated) dependency is overridden like any other `@Instantiated` dependency: its entry is a closure that returns the instance, which the mock calls the first time the instance is read. A type’s generated mock therefore has the same parameters whether the dependencies it receives are lazily instantiated or not.

**Dependencies received only if available.** A `@Received(onlyIfAvailable: true)` dependency gets an optional entry only when every type in the tree that receives it, renames included, receives it only if available. It has no entry of its own when the mock builds it anyway: when the mocked type instantiates it, or another type in the tree requires it. When nothing fulfills it and another type requires it, it is a required flat parameter. Where production passes a receiver `nil`, such as one built inside the instance it receives, the mock passes `nil` too.

**Renames.** A mock resolves each `@Received` dependency from its declared type, not from the renames in any particular parent. Take `ProfileView` from [Sharing one instance across properties of disparate types](#sharing-one-instance-across-properties-of-disparate-types): `ProfileView.mock()` builds `crashReporter` itself only when `Telemetry` lists `CrashReporter` in `fulfillingAdditionalTypes`, and otherwise takes it as a required parameter. An entry for a composition such as `(EventTracker & CrashReporter).self` does not cover its members. So a mock that receives both `EventTracker` and `CrashReporter` builds a separate `Telemetry` for each; pass one instance through `safeDIOverrides` if a test needs them to coincide.

The mocked type’s own renames are the exception. When the mocked type declares a rename, a dependency the mock builds beside it that receives the rename’s label, as the rename’s type or its optional form, has no entry for that label: it gets the rename, as types beneath the mocked type do.

**Names.** When two flat `mock()` parameters, or two entries of one `SafeDIOverrides` or `SafeDIMockConfiguration`, share a label, each is named by its label followed by its type, spelled as an identifier: received dependencies named `items` of types `[String]` and `Set<String>` become `items_Array_String` and `items_Set__String`. A mock builds every form in which its tree receives one label: when one type requires `x: X` and another requires `x: Instantiator<X>`, the mock builds both, as `x_X` and `x_Instantiator__X`. An optional form beside its non-optional form, and the instance of a `LazilyInstantiated`, are not forms of their own.

#### Receiving a type-erased dependency

A mock can build a received dependency of a type no `@Instantiable` declaration fulfills when a parent erases a concrete type to it. `NotesApp` in [Making protocols `@Instantiable`](#making-protocols-instantiable) declares `@Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) private var userService: AnyUserService`. So the mock of a type that receives `userService: AnyUserService` gets a `userService` entry on `SafeDIOverrides` that builds a `DefaultUserService` and wraps it in `AnyUserService`. SafeDI looks for such properties in the current module and the modules it depends on, and matches the whole type: a received `AnyUserService` matches a property of type `AnyUserService`, not an `ErasedInstantiator<…, AnyUserService>`.

When parents erase different concrete types to the same type — say `NotesApp` erases `DefaultUserService` and another parent erases `OfflineUserService` to `AnyUserService` — nothing tells SafeDI which one a mock should build, so the dependency is a required flat `mock()` parameter:

```swift
@Instantiable(generateMock: true)
public struct SettingsView: View, Instantiable {
    // …
    @ObservedObject @Received private var userService: AnyUserService
}

SettingsView.mock(userService: AnyUserService(StubUserService(stringStorage: InMemoryStorage())))
```

A received erased instantiator matches the same way: a mock builds a received `childViewBuilder: ErasedInstantiator<(), AnyView>` from a property of that type, such as `ParentView`’s in [ErasedInstantiator](#erasedinstantiator). When the type it builds has several `@Forwarded` properties, and the first generic argument is a tuple with an element type that is more than a plain type name, such as `Int?` in `ErasedInstantiator<(count: Int?, name: String), AnyView>`, the mock takes the instantiator as a parameter instead of building it. To have the mock build it, spell that argument as the type’s `ForwardedProperties` typealias, both where the instantiator is declared and where it is received.

An entry for an erased dependency, received or instantiated, is a closure that returns the wrapper type, so a caller wraps its stub. The mocked type’s own entry is on `SafeDIOverrides`. Where a type beneath it instantiates the dependency, the entry is on that type’s nested `SafeDIMockConfiguration`, as it would be if `NoteStorage` instantiated `userService`:

```swift
NotesApp.mock(safeDIOverrides: .init(userService: { stringStorage in
    AnyUserService(StubUserService(stringStorage: stringStorage))
}))

LoggedInView.mock(
    user: User(name: "dfed"),
    safeDIOverrides: .init(noteStorage: .init(userService: { stringStorage in
        AnyUserService(StubUserService(stringStorage: stringStorage))
    }))
)
```

When the concrete type has its own `@Instantiated` subtree or default-valued init parameters, the entry is instead the concrete type’s `SafeDIMockConfiguration`: its builder closure returns the concrete type, which the mock wraps.

### Hand-written mocks

A type can provide its own mock method, declared in the body of its `@Instantiable`-decorated declaration (methods in undecorated extensions are not detected) or in a [`mockOnly` declaration](#the-mockonly-parameter). Without `generateMock: true`, the generated mocks of types that instantiate the type call `Type.mock(…)` (or the method `customMockName` names) instead of `Type(…)`, threading mock parameters through your method. The method must:

- Be visible to the generated mocks that call it, as [Access levels](#access-levels) describes.
- Take a parameter for each `@Instantiated`, `@Received`, and `@Forwarded` dependency of the declaration it is on, with a default value for every other parameter. A `mockOnly` declaration declares no dependencies, so its mock gives every parameter a default; [Splitting production and mock declarations](#splitting-production-and-mock-declarations) says which dependencies a generated mock then passes it.
- Be neither `async` nor `throws`.
- Return `Self` or the type name on a type declaration; on an extension-based `@Instantiable` type, the extended type (e.g. `-> Container<Bool>`) or a `fulfillingAdditionalTypes` entry, mirroring the corresponding `instantiate()` method.

The `@Instantiable` macro validates these requirements and provides fix-its for any issues.

When a type also has a generated `mock()`, its hand-written mock method needs another name, wherever it is declared – in the same declaration or in a separate [`mockOnly` declaration](#splitting-production-and-mock-declarations) – or calls of `mock()` are ambiguous. Name your hand-written method with the `customMockName` parameter, and the generated `mock()` calls through to it. With `mockOnly: true`, `customMockName` tells SafeDI which method is the mock. This is useful when you need custom logic during mock construction — for example, setting up stub behavior, configuring test doubles, or wiring delegates:

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

When the hand-written method returns an additional type the `@Instantiable` declaration fulfills (for example, a protocol declared in `fulfillingAdditionalTypes`), the generated `mock()` method also returns that type.

### The `mockOnly` parameter

The `mockOnly` parameter lets you create a declaration that participates only in mock generation. It provides a hand-written `mock()` method without contributing a production instantiation path. Here’s an example that provides a default mock for a protocol:

```swift
@Instantiable(fulfillingAdditionalTypes: [UserManager.self], mockOnly: true)
public final class MockUserManager: UserManager {
    public static func mock() -> MockUserManager {
        .init(user: .init(name: "Mock User"))
    }

    init(user: User) {
        self.user = user
    }

    var user: User
}
```

This also works for types that are used as `@Forwarded` dependencies — for example, an authenticated `User`:

```swift
@Instantiable(mockOnly: true)
public final class User {
    public static func mock() -> User {
        User(name: "Mock User")
    }

    // …
}
```

SafeDI’s mock generator uses a `mockOnly` declaration’s mock wherever the declaration’s concrete or fulfilled types appear in a mock dependency tree, so you don’t have to provide a mock for common types (like `User` or `NetworkClient`) every time you call `mock()` on a parent type. A `mock()` parameter for such a type, such as a `@Forwarded` dependency, defaults to the mock, and an `@Instantiated` one appears in `SafeDIOverrides` with `Type.mock()` as its default. A property built with `fulfilledByType:` is the exception that [Dependency kinds in the generated mock](#dependency-kinds-in-the-generated-mock) describes.

`mockOnly` declarations are useful for:

- Protocols that need mocks in your tests and previews
- Types used as `@Forwarded` dependencies (e.g., `String`, `Int`, `UUID`, `User`)
- Types whose `@Instantiable` declaration is in another module and isn’t in the current module’s dependency tree

A `mockOnly` declaration requires a hand-written `mock()` method (or a method named by `customMockName`). No `init` (type declarations), `instantiate()` (extensions), or `Instantiable` conformance is required.

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

When both declarations exist, SafeDI uses the production `@Instantiable` for the dependency tree and the `mockOnly` declaration’s hand-written mock for mock generation; a type can have at most one hand-written mock. A production type without `generateMock: true`, like the one above, is built in mocks by calling the `mockOnly` declaration’s method, which may be named `mock`. A type whose `mock()` is generated – by `generateMock: true`, or because another module lists it in `additionalMocksToGenerate` – needs the method named apart with `customMockName`, as [Hand-written mocks](#hand-written-mocks) describes:

```swift
@Instantiable(generateMock: true)
public struct MyService: Instantiable {
    public init(database: Database) { … }
    @Instantiated let database: Database
}

@Instantiable(mockOnly: true, customMockName: "preview")
extension MyService {
    public static func preview(database: Database = .mock()) -> MyService {
        MyService(database: database)
    }
}
```

The hand-written mock also decides which of the production declaration’s dependencies a generated mock builds. In the first example, `MyService.mock()` takes no `database`, so the mock of a type that instantiates `MyService` calls `MyService.mock()` without building a `Database`. Declare `mock(database: Database = .mock())` instead to have the generated mock build the `Database` and pass it in.

So the generated mock builds the dependencies your hand-written mock has a parameter for, and passes each to the parameter of the same label. A dependency without a parameter is neither built nor received, and has no entry in `SafeDIOverrides`, unless a dependency the mock is passed receives it.

### Cross-module mock generation

A mock generated with `generateMock: true`, and each `SafeDIMockConfiguration` it uses, is an `internal` member of an extension in the module that generates it, which avoids conflicts when several modules generate mocks for the same types. Each module generates mocks only for the types it declares, so run SafeDI on every target that depends on SafeDI, as [Generating your dependency tree](#generating-your-dependency-tree) says. A module whose tests or previews need a mock of a type another module declares has two options:

1. List the type in its own `additionalMocksToGenerate`, which generates an internal `mock()` of the type there. The mock constructs the type and its tree in that module, so they must be visible to it, as [Access levels](#access-levels) describes.
2. Declare the type with `generateMock: .public` in its own module, which generates a `mock()` that other modules call; the types its tree builds can then stay `package` or `internal`. See [Public mocks](#public-mocks).

For the first, use the `additionalMocksToGenerate` parameter on [`#SafeDIConfiguration`](#safediconfiguration):

```swift
#SafeDIConfiguration(
    additionalMocksToGenerate: [
        "LoggingService",
        "UserStorageService",
    ]
)
```

This generates a `mock()` method for each listed type in the current module, even though the type is defined elsewhere. The type must be `@Instantiable` in its home module, but `generateMock: true` is not required there unless that home module also wants to generate its own mock. A type whose only declaration is [`mockOnly`](#the-mockonly-parameter) cannot be listed, since its hand-written mock is already its mock. To keep existing calls of `mock()` compiling after removing such an entry, name its hand-written method `mock` and drop `customMockName`.

List each type by its declared name, with enclosing types and without the module (`Outer.Inner`, not `MyModule.Outer.Inner`).

**Note:** `additionalDirectoriesToInclude` helps SafeDI scan source from Xcode project dependencies, but it does not generate mocks for those dependency modules; see [Limits of the Xcode project plugin](#limits-of-the-xcode-project-plugin).

### Public mocks

`generateMock: .public` gives other modules, in this package or another, a `mock()` they can call. SafeDI generates that `public` `mock()` in the module that declares the type. (`generateMock: true` is the same as `.internal`.) The type and every type enclosing it must be `public` or `open`, and none of them generic; SafeDI reports otherwise with a fix-it.

```swift
@Instantiable(generateMock: .public)
public struct Service: Instantiable {
    package init(analytics: LazilyInstantiated<Analytics>, session: Session, tokenCache: TokenCache, retries: Int = 3) {
        // …
    }

    @Received private let analytics: LazilyInstantiated<Analytics>
    @Received private let session: Session // `Session` is `package`.
    @Instantiated private let tokenCache: TokenCache
}
```

Each parameter of a public `mock()` is as visible as the types it names. So, like a seam’s initializer, the mock has one [tier](#generating-a-dependency-tree-per-module) per access level among its parameters: a `public` tier that code in any module can call, and a narrower tier that also takes the narrower parameters ([Access of generated parameters](#access-of-generated-parameters)):

```swift
public static func mock(retries: Int? = nil, analytics: Analytics? = nil, safeDIOverrides: SafeDIOverrides = .init()) -> Service {
    Service.mock(retries: retries, analytics: analytics, session: nil, safeDIOverrides: safeDIOverrides)
}

package static func mock(retries: Int? = nil, analytics: Analytics? = nil, session: Session? = nil, safeDIOverrides: SafeDIOverrides = .init()) -> Service {
    // …builds the tree…
}
```

`Service.mock()` builds the whole tree; `Service.mock(analytics: Analytics())` hands the mock a value; `Service.mock(safeDIOverrides: .init(tokenCache: .init(capacity: 5)))` configures a type in the tree.

The parameters come in this order: `@Forwarded` properties; default-valued initializer parameters; the received dependencies the mock cannot build; hole builders; the received dependencies it builds and those received only if available, by label; and `safeDIOverrides`.

**Default-valued parameters.**

- A non-optional default-valued parameter is `T? = nil`, where `nil` means the declaration’s default. A magic literal such as `#fileID` keeps its default.
- An `@autoclosure` one, `retries: @autoclosure () -> Int = 3`, becomes `retries: (() -> Int)? = nil`: pass a closure, which the mock calls each time it builds the type. A field of a type’s configuration takes it the same way.
- An optional-typed default-valued parameter is a `SafeDIOverrides` field with the declaration’s default. It is a parameter of `mock()` instead when the mock has no `SafeDIOverrides`, or when the mock is bound to a global actor, which then evaluates the default in its isolation.
- If a type is on the main actor only through a conformance or superclass, such as a SwiftUI `View` or a `UIViewController` subclass, give it `mockAttributes: "@MainActor"`. SafeDI sees only a global actor the declaration or `mockAttributes` spells. Without it, the type’s optional-typed defaults are evaluated outside the actor, and one that reads the actor’s state does not compile; the comment SafeDI writes there says so. A default in the configuration of a type in the tree that reads global-actor-isolated state does not compile either, as in an internal mock.

**Received dependencies.**

- A received dependency the mock builds is `T? = nil`: pass `nil` to have the mock build it, or a value to use instead. A lazily instantiated one is taken by value, as `analytics` is above.
- A parameter an internal mock [defaults to a hand-written mock](#dependency-kinds-in-the-generated-mock) is `T? = nil` too, and `nil` calls that mock.
- `SafeDIOverrides` is `public`, with each member as visible as the types it names, and an initializer for each access its members have.

**Holes.**

- A [hole](#generating-a-dependency-tree-per-module) – here, a type the tree instantiates that no `@Instantiable` or `mockOnly` declaration the module sees fulfills – takes a required builder, as it does for a seam, with the same labels, cases and stages. Its scope types are nested in the mocked type: `SafeDIMockScope_<Type>`, `SafeDISendableMockScope_<Type>` and `SafeDIStagedMockScope_<Type>_<case>`. A `mockOnly` stub that fulfills the hole’s type, in the module or one it depends on, removes the builder: the mock builds the stub, and production still fills the hole.

Each generated call of a public mock names an empty enum that encodes the mock’s signature, so a call generated against an older signature fails to compile at the call.

#### Calling a public mock from another module

Another module calls a public mock like any `public` method, inside the declaring module’s `mockConditionalCompilation`; a module of another SwiftPM package depends on a [library product](#swift-package) of the declaring package. For `FeedScreen`, which [Adopting SafeDI in a large codebase](#adopting-safedi-in-a-large-codebase) declares with a hole, `service: FeedService`, a test passes a stub:

```swift
// In a package that depends on Feed's library product.
import Feed

struct StubFeedService: FeedService {
    func refresh() async {}
}

#if DEBUG
func makeFeedScreen() -> FeedScreen {
    FeedScreen.mock(feedServiceBuilder: { _ in StubFeedService() })
}
#endif
```

**Generate both modules’ mocks under one `mockConditionalCompilation`**, unless the declaring module’s mocks are unconditional. Under the Swift package plugin, a module that calls another module’s seam must share that module’s `mockConditionalCompilation` too.

A mock that another module generates also calls a public mock when its tree reaches the type. It builds the type inline when it can construct the type’s whole tree, and otherwise calls the type’s public mock, at the narrowest tier its module can reach. Values your mock already holds are shared with the public mock: the call passes what the calling tree holds for that tier’s parameters, `nil` for the rest, and your overrides of the type as `safeDIOverrides`. A dependency the called mocks build that the calling module can construct is built once by the calling mock, and passed to every call, including each call an `Instantiator` makes. Two kinds are not shared:

- A dependency the calling module cannot construct is built by each public mock that builds it, and is `nil` in one that receives it only if available. To share one of a `public` type, declare it with `generateMock: .public` too: the calling mock then builds it once, through its public mock, and passes it to every call.
- A lazily instantiated dependency is passed by value, so it is created when the public mock is called, where a generated call of a seam defers it.

Also:

- A public mock that calls another module’s public mock takes what that call passes as `T? = nil` parameters of its own, so its callers can hand one instance down the chain.
- The calling mock fills a place of a hole of the public mock itself when its module can build an implementation there: it sees a declaration that fulfills the hole’s type, it can build every type in that declaration’s tree, that tree reads nothing but the values of the place’s case, and building it closes no dependency cycle. It builds that tree as its own mock would, with hand-written mocks, and with a `mockOnly` fake when one alone fulfills the hole. Your overrides do not reach it, but a call of another module’s public mock inside it is passed what the calling mock passes any call, unless that mock passes a place up, when this place is passed up too.
- The calling mock passes every other place up. An internal mock takes the called mock’s builder as a required parameter of its own, for the test to supply, named after the called type, as in `serviceBuilder_Panel`, when another parameter, another such builder or a declaration of the mock’s tree has its name. A public mock takes a builder of its own whose enum holds the called mock’s enum in a case, as a seam passes an inner seam’s places up.
- A place the calling mock fills never reaches its caller’s closure, which still lists its case. Generated code that calls that mock fills such a case too where it can, and otherwise passes it up with the rest, so an internal mock can take a builder that is never called.
- A mock tree that reaches a type whose declaring module SafeDI does not know builds it inline where it can, and otherwise fails as [Limits of the Xcode project plugin](#limits-of-the-xcode-project-plugin) describes.

## Installation

Integrating SafeDI is a three-step process: add the package, wire SafeDI’s code generation into your build, and decorate your types with SafeDI’s macros.

[Example applications](#example-applications) lists a sample integration for each build system. The Xcode project and Swift package examples take SafeDI from this repository with the `sourceBuild` trait, which builds `SafeDITool` from source: consumers using a published release do not need to specify `traits`.

### Adding SafeDI as a dependency

#### Swift package manager

To add the SafeDI framework as a dependency to a package utilizing [Swift Package Manager](https://github.com/apple/swift-package-manager), add the following lines to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/dfed/SafeDI.git", from: "2.2.0"),
]
```

To install the SafeDI framework into an Xcode project with Swift Package Manager, follow [Apple’s instructions](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) to add `https://github.com/dfed/SafeDI.git` as a dependency. A [Bazel](#bazel) or [Tuist](#tuist) project declares the dependency as its section below describes.

### Generating your dependency tree

SafeDI’s code generation runs `SafeDITool` in your build. Xcode projects and Swift packages run it through the `SafeDIGenerator` build tool plugin, which uses a prebuilt binary, so your build does not compile SwiftSyntax. An Xcode project also needs a one-time [install of that binary](#installing-the-prebuilt-safeditool-binary); until then, the plugin plans the build with a simpler scanner. [Bazel](#bazel) and [Tuist](#tuist) projects run it once per module through SafeDI’s Bazel rule and Tuist plugin. Any other build runs `SafeDITool` itself, as [Custom build system integration](#custom-build-system-integration) describes.

SafeDI generates code for a type only in the module that declares it: a root’s `init()`, the initializer of a type with `generateDependencyTree: true`, and the `mock()` of a type with `generateMock`. So run SafeDI on every target that depends on the `SafeDI` library, even one that declares none of them yet: a target that gains one later then needs no change to its build.

Under Bazel and Tuist, run SafeDI on every first-party Swift module, even one that declares no `@Instantiable` type, and give each module a list of the modules it depends on, as [Which modules to list](#which-modules-to-list) describes; [Access of generated parameters](#access-of-generated-parameters) says why.

A module needs a `SafeDIConfiguration.swift` only to set one of [its parameters](#safediconfiguration).

#### Xcode project

If your first-party code comprises a single module in an `.xcodeproj`, once your Xcode project depends on the SafeDI package you can integrate the Swift Package Plugin simply by going to your target’s `Build Phases`, expanding the `Run Build Tool Plug-ins` drop-down, and adding the `SafeDIGenerator` as a build tool plug-in. You can see this integration in practice in the [ExampleProjectIntegration](../Examples/ExampleProjectIntegration) project.

If your Xcode project comprises multiple modules, follow the above steps for each target that depends on SafeDI, and then add a `#SafeDIConfiguration` to a file named `SafeDIConfiguration.swift` in your module to configure SafeDI:

```swift
import SafeDI

#SafeDIConfiguration(
    additionalDirectoriesToInclude: ["Subproject"]
)
```

`additionalDirectoriesToInclude` names folders outside your module that SafeDI scans for Swift source files, relative to the executing directory (the directory containing the `.xcodeproj`). Xcode project plugins cannot discover dependent modules’ source directories, so list them here, as the [ExampleMultiProjectIntegration](../Examples/ExampleMultiProjectIntegration) project does in [its configuration](../Examples/ExampleMultiProjectIntegration/ExampleMultiProjectIntegration/SafeDIConfiguration.swift).

When you add a framework target that depends on SafeDI, apply the `SafeDIGenerator` plugin to it as above, and give it a `#SafeDIConfiguration` of its own whose `additionalDirectoriesToInclude` lists the folders of the targets it depends on. Then add the new target’s folder to the root target’s `additionalDirectoriesToInclude`.

> **Note:** Any SafeDI declaration, roots included, may sit behind a bare condition such as `#if DEBUG`; see [Conditional compilation](#conditional-compilation).

##### Limits of the Xcode project plugin

In short: in a multi-target Xcode project, keep each type that generated code builds in another target, and its initializer, at `package` or `public`, and set `SWIFT_PACKAGE_NAME` to one name on every target, as a project-level build setting does. SafeDI reports each declaration that is too narrow, with a fix-it.

The reason is that the Xcode project plugin cannot tell SafeDI which target declares each type. A target knows the files it compiles, but not which target declares a file it reads through `additionalDirectoriesToInclude`, and it reads no other target’s `.safedi` file. So under the Xcode project plugin:

- **Imports of types from other targets that you name only in a string are not added.** A generated file does not import the target of a type it builds through a `fulfilledByType` string or a `fulfillingAdditionalTypes` entry, when another target declares that type: list that module in `additionalImportedModules`, as [Generated imports](#generated-imports) describes.
- **A file that imports the target itself**, read through `additionalDirectoriesToInclude`, gives the compiler’s “ignoring import” warning in generated code.

If you use [seams](#generating-a-dependency-tree-per-module) or [public mocks](#public-mocks):

- **Trees build seams inline.** A tree that reaches a seam builds the seam’s whole tree itself, and the construction ends in a comment saying so. No generated code calls the seam’s generated initializers. So every type in the seam’s tree must be visible to the target that builds it, as above.
- **A seam’s tree has no holes.** Every type a seam’s tree instantiates must be fulfilled by a declaration its target reads. So a seam whose tree instantiates a protocol only the app implements is an error.
- **Generated mocks do not call another target’s public mock.** A mock builds such a type inline when the target can see its whole tree, and otherwise generation fails. Your tests and previews can still call the `public` `mock()` the declaring target generates.
- **A type of a target SafeDI does not read is taken as `public`** ([Access of generated parameters](#access-of-generated-parameters)). So a `package` type of another target, named by a parameter of a seam or public mock, can fail to compile in the generated `public` declaration. Add that target’s directory to `additionalDirectoriesToInclude`, or declare the seam or mock `package`.
- **A missing plugin shows only as compiler errors.** The plugin cannot tell whether another target applies it, so when the declaring target lacks the plugin, a hand-written call of its generated initializer or `mock()` fails with the compiler’s errors alone.

These limits also apply, under every integration, to a type declared in a file read through `additionalDirectoriesToInclude`, since SafeDI does not know its module either. For such a type, SafeDI assumes the module that builds it is in the same package, and accepts a `package` declaration; if it is not, the compiler reports the construction instead.

Seams that generate their own trees, holes in a seam’s tree, and generated calls of public mocks need a build that knows each type’s module: the Swift package plugin, Bazel, or Tuist. (A public mock’s hole builders do work under the Xcode project plugin.) A multi-module Xcode project gets them by moving its modules into a local Swift package that the app target depends on, declaring the root there, and calling the root’s `init()` from the app; the package then adopts SafeDI as [Adopting SafeDI in a large codebase](#adopting-safedi-in-a-large-codebase) describes.

##### Installing the prebuilt SafeDITool binary

If you see a build warning that starts with **"SafeDI is planning this target’s generated files with a simpler scanner..."**, install the prebuilt tool: in Xcode, right-click your project in the navigator, choose **SafeDI → Safedi Release Install**, and approve the network-access and write-to-package-directory prompts. The command downloads the prebuilt SafeDITool release binary for your SafeDI version into `.safedi/<version>/safeditool` next to your `.xcodeproj`, and the build plugin picks it up on later builds. If the download’s SHA-256 differs from the one SafeDI’s release recorded, the command deletes it and fails, printing both hashes; run the command again to retry.

Without the installed tool, the plugin plans the build with a regex-based scanner; `swift build` gets the prebuilt binary through the default `prebuilt` trait already. Run the command once per project, and again after a SafeDI version bump if the warning reappears.

The command writes `.safedi/.gitignore` on first run, with the single glob `*/safeditool`. **Commit `.safedi/.gitignore`.** The binary it ignores is specific to the host (arm64 or x86_64) and the SafeDI version, so each developer re-runs the command once after cloning.

#### Swift package

If your first-party code is entirely contained in a Swift Package with one or more modules, add the following lines to each target that depends on the `SafeDI` library, as [Generating your dependency tree](#generating-your-dependency-tree) says:

```swift
    plugins: [
        .plugin(name: "SafeDIGenerator", package: "SafeDI")
    ]
```

To generate mocks in other modules, see [Cross-module mock generation](#cross-module-mock-generation).

A module that another package uses, such as one that declares a [public mock](#calling-a-public-mock-from-another-module), must be a library product of its package. The other package depends on that product, and needs no SafeDI dependency or plugin of its own to call the mock. A path dependency’s package identity comes from its folder name:

```swift
// In the Package.swift of the package in the folder `FeedKit`, which declares the module `Feed`:
products: [
    .library(name: "Feed", targets: ["Feed"]),
],

// In the Package.swift of the package that uses it:
dependencies: [
    .package(path: "../FeedKit"),
],
targets: [
    .target(
        name: "FeedPreviews",
        dependencies: [
            .product(name: "Feed", package: "FeedKit"),
        ]
    ),
],
```

You can see this integration in practice in the [Example Package Integration](../Examples/Example%20Package%20Integration) package.

Unlike the Xcode project plugin, the Swift package plugin finds the source files of dependent modules itself. It reads the modules of your package and of the packages it depends on by path, but not those of a package it fetches from a URL. To build an `@Instantiable` type a fetched package declares, add the package’s checkout directory to `additionalDirectoriesToInclude` in a `#SafeDIConfiguration`; SafeDI then knows no module for those types, with the limits [Limits of the Xcode project plugin](#limits-of-the-xcode-project-plugin) lists. If SafeDI’s generated code is missing required imports, list the modules in [`additionalImportedModules`](#safediconfiguration).

> **Note:** On Swift 6.4 or later, `swift build` can fail for a target with a couple thousand or more input files with `sandbox-exec: data object length … exceeds maximum (65535)`. Xcode is not affected. Build with `swift build --build-system native`, or with `swift build --disable-sandbox`, which turns off sandboxing for every plugin and package manifest in the build.

#### Bazel

Add `bazel_dep(name = "safedi", version = "2.2.0")` to your `MODULE.bazel`, then declare each first-party Swift module ([Generating your dependency tree](#generating-your-dependency-tree)) with `safedi_swift_library` in place of `swift_library`:

```python
load("@safedi//bazel:safedi.bzl", "safedi_swift_library")

safedi_swift_library(
    name = "App",
    srcs = glob(["**/*.swift"]),
    defines = ["STAGING"],
    safedi_deps = ["//Subproject:Subproject_safedi"],
    deps = [
        "//Subproject",
        "@safedi//:SafeDI",
    ],
)
```

The macro accepts every `swift_library` attribute and declares two targets: the `swift_library` named `App`, and `App_safedi`, which runs `SafeDITool` over the same `srcs` with the same `defines` and `copts`. Both targets take the macro’s `visibility`. For each module you depend on directly, list its `<name>_safedi` target in `safedi_deps` and the module itself in `deps`; [Which modules to list](#which-modules-to-list) says why that is enough. List every Swift source of the module in `srcs`: Bazel cannot see the files an `additionalDirectoriesToInclude` entry names. For `package` access, give the modules of one package the same `package_name`: a module with a different `package_name` is in another package, and a module without one has no package. You can see this integration in practice in the [ExampleBazelIntegration](../Examples/ExampleBazelIntegration) module.

**Only if the macro does not fit** a module, declare the `safedi_compile` rule and the module’s `swift_library` separately, and add `[":<rule name>"]` to the library’s `srcs`. Load the rule with `load("@safedi//bazel:safedi.bzl", "safedi_compile")`. It takes:

- `srcs`, `defines`, `copts`, and `package_name`: the library’s.
- `deps`: the targets `safedi_swift_library` calls `safedi_deps`.
- `visibility`: as on the library, since the modules that list the rule must see it.
- `module_name` (required): the library’s `module_name` attribute, or the name `derive_swift_module_name` from `@rules_swift//swift:module_name.bzl` gives the library’s label.

See [`bazel/safedi.bzl`](../bazel/safedi.bzl).

For [Stardoc](https://github.com/bazelbuild/stardoc) and other `bzl_library` tooling, a `bzl_library` of your own that loads `safedi.bzl` can list `@safedi//bazel:safedi` in its `deps`.

Bazel runs the prebuilt `SafeDITool` from the SafeDI release on macOS (arm64 or x86_64) and Linux (x86_64 or arm64), the same binary the `SafeDIGenerator` plugin and the Tuist plugin run. The first build that needs it downloads it from the release’s GitHub assets, so that build needs network access to GitHub, or a [repository cache](https://bazel.build/run/build#repository-cache) that holds the binary. Bazel checks it against the sha256 recorded in the release’s source archive. On any other machine, Bazel builds `SafeDITool` from source. To always build it from source, add this line to your `.bazelrc`:

```
common --@safedi//bazel:prefer_prebuilt_safeditool=false
```

A build that takes SafeDI from a checkout of its repository rather than from a release – through `local_path_override`, `git_override`, or an `archive_override` of one of GitHub’s generated source archives (`archive/refs/tags/…`) – always builds `SafeDITool` from that checkout. An `archive_override` of the release’s own `SafeDI-<version>.tar.gz` uses the prebuilt tool.

#### Tuist

SafeDI’s `SafeDITuist` plugin runs `SafeDITool` in a script phase of each target, before the target compiles. Declare the plugin in `Tuist.swift`, at the commit of the SafeDI version you depend on, which `git ls-remote https://github.com/dfed/SafeDI refs/tags/<version>` prints:

```swift
let tuist = Tuist(
    project: .tuist(
        plugins: [
            .git(url: "https://github.com/dfed/SafeDI", sha: "<commit>", directory: "TuistPlugins/SafeDITuist"),
        ]
    )
)
```

Tuist cannot load the plugin by `tag:`; declare it by `sha:` as above.

Depend on SafeDI in `Tuist/Package.swift`, so that `tuist install` fetches the SafeDI library and the prebuilt `SafeDITool` the plugin runs:

```swift
dependencies: [
    .package(url: "https://github.com/dfed/SafeDI.git", from: "2.2.0"),
]
```

In `Project.swift`, `import SafeDITuist`, and give each first-party target ([Generating your dependency tree](#generating-your-dependency-tree)) the generated source, the script, and a dependency on SafeDI:

```swift
.target(
    name: "App",
    // …
    sources: .sourceFilesList(globs: [
        .glob("App/**/*.swift"),
        SafeDI.generatedSource,
    ]),
    scripts: [
        SafeDI.preCompileScript(module: "App", dependencies: ["Subproject"]),
    ],
    dependencies: [
        .target(name: "Subproject"),
        .external(name: "SafeDI"),
    ]
),
```

`module` names the directory, under the one that holds `Project.swift`, whose Swift files the script passes to `SafeDITool`. List every Swift source of the target in its `sources`, not in `additionalDirectoriesToInclude`: Tuist does not rebuild when those files change, and cannot read them under user script sandboxing.

`dependencies` lists the module name (`PRODUCT_MODULE_NAME`) of each target whose `.safedi` file the script reads, as [Which modules to list](#which-modules-to-list) describes. Each listed target must run the script too.

Each listed target must also write its `.safedi` file before this target’s script runs. So this target must depend on each one, directly or through another target.

The script reruns when one of the target’s Swift files or one of those `.safedi` files changes. After renaming a module, delete its old `.safedi` from `$BUILT_PRODUCTS_DIR/SafeDI` or clean the build folder: a target that still lists the old name reads the old file.

The script runs the `SafeDITool` that `tuist install` unpacks into `Tuist/.build`, beside the workspace’s `Tuist/Package.swift`. It looks for that file from the directory that holds `Project.swift` upward, so a project in a subdirectory of the workspace, such as `Projects/Feature/Project.swift`, finds it too. The script passes `SafeDITool` the target’s `SWIFT_ACTIVE_COMPILATION_CONDITIONS` and `OTHER_SWIFT_FLAGS` (see [Reporting active conditions](#reporting-active-conditions)), its module name, and its `SWIFT_PACKAGE_NAME` when it sets one.

The script writes the generated code to `SafeDIGenerated.swift`, whose path never changes. So:

- **After changing your SafeDI declarations**, build. No `tuist generate` is needed.
- **After adding a Swift file**, run `tuist generate`, which adds the file to the target’s sources and the script’s inputs. Until then, a target whose `sources` are globs does not compile the file, though the script reads it, so the types it declares fail with `cannot find type` errors, in `SafeDIGenerated.swift` too. A target with buildable folders compiles the file, but the script reads it only when it next runs for another change.
- **After changing SafeDI’s version**, keep the plugin’s commit and the package’s version in step, and run `tuist install` and `tuist generate`.

You can see this integration in practice in the [ExampleTuistIntegration](../Examples/ExampleTuistIntegration) project.

For `package` access, set `SWIFT_PACKAGE_NAME` to one name in every project whose targets use one another’s `package` declarations, the app’s project included, for example in each `Project.swift`: `settings: .settings(base: ["SWIFT_PACKAGE_NAME": "MyApp"])`.

#### Custom build system integration

A build that neither the `SafeDIGenerator` plugin, the Bazel rule, nor the Tuist plugin covers – Buck, or a prebuild script – runs `SafeDITool` itself, from the prebuilt, codesigned `SafeDITool.artifactbundle.zip` on our [Releases](https://github.com/dfed/SafeDI/releases) page. Two working references, each running `generate --combined-output --module-info-output` per module and passing the `.safedi` files of the modules it lists through `--dependent-module-info-file-path`, drive the tool. They are the Tuist plugin’s embedded shell in [`TuistPlugins/SafeDITuist/ProjectDescriptionHelpers/SafeDI.swift`](../TuistPlugins/SafeDITuist/ProjectDescriptionHelpers/SafeDI.swift), which locates the binary via SPM (for a non-SPM build system, swap that lookup for a `curl` of the artifact bundle), and the Bazel rule and macro at [`bazel/safedi.bzl`](../bazel/safedi.bzl).

An Xcode script phase that runs `SafeDITool` can keep `ENABLE_USER_SCRIPT_SANDBOXING` on if it declares the Swift files it passes `SafeDITool` and the `.safedi` files it reads as input files, and each file it writes in those directories as an output file. The sandbox denies the script any other file under the project’s directory, the build’s products, and the target’s derived sources; scratch files in `$TARGET_TEMP_DIR` or the system’s temporary directory need no declaration. Otherwise, set `ENABLE_USER_SCRIPT_SANDBOXING` to `NO` for the target. The Tuist plugin’s script needs the setting off, which is Tuist’s default.

`SafeDITool` has two subcommands for a build. **`scan`** writes a manifest JSON describing the `@Instantiable` types it finds, which the `SafeDIGenerator` plugin uses to coordinate builds across modules. **`generate`**, the default subcommand, parses Swift source files, builds and validates the dependency graph, and generates the code of each root, of each [seam](#generating-a-dependency-tree-per-module) the module declares, and of each mock. It writes the code one of three ways:

| Option | Writes |
| --- | --- |
| `--combined-output <file>` | Everything in one file whose path is known in advance, for a build system that declares rule outputs up front. It cannot be combined with the other two. |
| `--output-directory <existing directory>` | One file per source file, as the `SafeDIGenerator` plugin writes them, named as [Finding the generated code](#finding-the-generated-code) describes. `generate` runs `scan` itself and writes its manifest and cache there. When the input CSV lists files of other modules too, pass the module’s own files to `--mock-scoped-files`. |
| `--swift-manifest <manifest>` | The outputs listed by a manifest you had `scan` write. A manifest you write by hand is deprecated, and `generate` warns. |

`generate` writes every output it plans, without code when its input declares no such type under the active compilation conditions. It also takes:

| Option | Purpose |
| --- | --- |
| `--active-compilation-conditions` | The target’s active compilation conditions, so SafeDITool scans the `#if` clauses the compiler compiles ([Conditional compilation](#conditional-compilation)). |
| `--build-setting-active-compilation-conditions`, `--build-setting-other-swift-flags` | Instead of the above, the target’s `SWIFT_ACTIVE_COMPILATION_CONDITIONS` and `OTHER_SWIFT_FLAGS` build settings. |
| `--module-name` | The Swift module that compiles the files the input CSV and `--include` name, such as an Xcode target’s `PRODUCT_MODULE_NAME`. `--module-info-output` requires it. |
| `--package-name` | That module’s package, exactly as the compiler’s `-package-name` names it, such as an Xcode target’s `SWIFT_PACKAGE_NAME`. Omit it when the compiler receives no `-package-name`. |
| `--module-info-output` | Where to write this module’s `.safedi` file, for the modules that list it. |
| `--dependent-module-info-file-path` | A file listing the `.safedi` file of each module this one [lists](#which-modules-to-list). |
| `--transitive-module-info-file-path` | A file listing the `.safedi` file of every module this one depends on, directly or through other modules, as the Bazel rule passes. |
| `--compiler-receives-input-paths-unchanged` | Better error locations, when your build allows it; see below. |

`--module-name` and `--package-name` tell `SafeDITool` which module and package declare each type it reads, which decides the access its generated code needs ([Access levels](#access-levels)).

`generate --additional-imported-modules` is deprecated and warns: list those modules in the module’s [`#SafeDIConfiguration`](#safediconfiguration) `additionalImportedModules`, which imports them whichever build runs SafeDI.

`SafeDITool` can parse all of your Swift files in one run or, for better performance, run once per module: each producing module writes a `.safedi` file with `--module-info-output`, and each consuming module passes the `.safedi` of each module it [lists](#which-modules-to-list) through `--dependent-module-info-file-path`, so it resolves the types declared upstream without parsing their sources:

```bash
# Producing module (Subproject):
safeditool generate Subproject.csv \
  --combined-output Subproject/SafeDIGenerated.swift \
  --module-info-output Subproject.safedi \
  --module-name Subproject

# Consuming module (App), with Subproject already built:
echo "Subproject.safedi" > deps.csv
safeditool generate App.csv \
  --combined-output App/SafeDIGenerated.swift \
  --module-info-output App.safedi \
  --dependent-module-info-file-path deps.csv \
  --module-name App
```

About `.safedi` files:

- `generate` writes one only when the run succeeds.
- It rewrites a `.safedi` file, or a combined output, only when its bytes change, so the same inputs leave the files untouched.
- A `.safedi` file names each source file by the path the input CSV gives it. A CSV of relative paths, like those the Bazel rule and the Tuist plugin write, keeps absolute paths out of it.
- Its format can change between SafeDI versions. After upgrading SafeDI, regenerate each module’s `.safedi` before the modules that read it run.
- [`query needs`](#querying-what-a-type-needs) can read these files in place of the sources.

Pass `generate --compiler-receives-input-paths-unchanged` if your build hands the compiler every Swift file, including those of the modules whose `.safedi` files the run reads, at exactly the path it hands `SafeDITool`, as the Bazel rule does. Errors then point at better locations: a type mismatch in a renamed dependency is reported at its `@Received` declaration, rather than in generated code with a comment naming that declaration. Without a plugin manifest, `SafeDITool` also prints each error and warning at the path it was handed, as the compiler does (under Bazel, relative to the execution root). The `SafeDIGenerator` plugin needs no flag.

[Running SafeDITool yourself](#running-safeditool-yourself) says how to print each subcommand's help.

#### Which modules to list

Under Bazel, Tuist, and a [custom build](#custom-build-system-integration), each module’s `SafeDITool` run reads its own sources and the `.safedi` files of the modules in its list: its `safedi_deps` under Bazel, the `dependencies` of its `SafeDI.preCompileScript` under Tuist, or the `--dependent-module-info-file-path` file in a custom build. SafeDI builds a type only when one of those declares it. The [Swift package](#swift-package) plugin needs no list: it reads the modules a target depends on itself.

Below, a module is beneath another when the other depends on it, directly or through other modules.

| A module that… | Lists |
| --- | --- |
| Any module | The modules it depends on directly. |
| Declares a root | Under Bazel, nothing more: the rule hands it the `.safedi` files of every module beneath it, and the generated code imports the modules it uses, so your files need not. Under Tuist, every module beneath it. |
| Declares a seam | Under Bazel, nothing more. Under Tuist, each module beneath it whose types the seam’s tree should build: a type from a module it does not list is a [hole](#generating-a-dependency-tree-per-module), which the seam’s initializer takes as a builder. |
| Declares neither, but lists a module that declares a root | Also the modules whose types that root’s tree builds, since a run checks the roots of the modules it reads. |
| Calls another module’s seam or public mock | Nothing more: each `.safedi` carries what a module needs to call them. |

A custom build lists modules as under Tuist, or passes `--transitive-module-info-file-path` a file naming the `.safedi` of every module beneath, as the Bazel rule does.

Generated mocks build only the types of the modules a run reads, and take any other type as a `mock()` parameter. Under Bazel, a run reads the modules its module’s trees need, but no others. To have a mock build a type from a module further down, list that module, which removes that parameter from the `mock()`.

The compiler does not check these lists. SafeDI reports a missing entry in a root’s tree, at the property that instantiates the type, with an error that says what to list. A generated mock that reaches such a type takes it as a required `mock()` parameter instead, as [Dependency kinds in the generated mock](#dependency-kinds-in-the-generated-mock) describes, and SafeDI reports nothing.

A module that uses types another module re-exports with `@_exported import` lists the module that declares them too: SafeDI does not follow the re-export. Under Bazel a tree needs no such entry, since the rule finds the declaring module beneath the one that re-exports it.

### Running SafeDITool yourself

Your integration already has a `SafeDITool`; a [custom build system](#custom-build-system-integration) runs the one it downloads. Run it with `--help`, `scan --help`, or `generate --help` to see documentation of all supported arguments, `query needs --help` for the command that [reports what types need](#querying-what-a-type-needs) (in beta), and `dump --help` for the command that prints a `.safedi` file, or the cache `scan` writes beside its manifest, as JSON. Each integration’s `SafeDITool` is here:

- **Swift package:** `.build/artifacts/safedi/SafeDIToolBinary/SafeDITool.artifactbundle/SafeDITool-macos-arm64/bin/SafeDITool` from the package’s directory, or `swift run SafeDITool` with the `sourceBuild` trait; writes no `.safedi` files.
- **Xcode project:** `SourcePackages/artifacts/safedi/SafeDIToolBinary/…` in the project’s derived data, or `.safedi/<version>/safeditool` once [installed](#installing-the-prebuilt-safeditool-binary); writes no `.safedi` files.
- **Bazel:** `bazel run @safedi//:SafeDITool -- <arguments>` runs the `SafeDITool` your build runs, prebuilt or built from source, in the directory you run it from, so relative paths among the arguments work. A build writes `bazel-bin/<package>/<name>_safedi.safedi`, though when the action’s result comes from a cache, such as `--disk_cache`, only for a build passed `--remote_download_regex='.*\.safedi$'`.
- **Tuist:** `Tuist/.build/artifacts/safedi/SafeDIToolBinary/SafeDITool.artifactbundle/SafeDITool-macos-arm64/bin/SafeDITool` from the directory that holds `Tuist/Package.swift`; a build writes `$BUILT_PRODUCTS_DIR/SafeDI/<PRODUCT_MODULE_NAME>.safedi`.

On an Intel Mac, the bundle’s directory is `SafeDITool-macos-x86_64`.

### Finding the generated code

SafeDI writes its output into the build directory rather than your source tree. When you want to read what it generated for a root or a mock, look here:

| Integration | Generated files |
| --- | --- |
| Xcode project with the `SafeDIGenerator` plugin | `<DerivedData>/Build/Intermediates.noindex/BuildToolPluginIntermediates/<Project>.output/<Target>/SafeDIGenerator/SafeDIOutput/` |
| Swift package built with `swift build` | `.build/plugins/outputs/<package>/<target>/destination/SafeDIGenerator/SafeDIOutput/` |
| Bazel (`safedi_swift_library` or `safedi_compile`) | `bazel-bin/<package>/<name>_safedi.swift` for a `safedi_swift_library` named `<name>`, or `bazel-bin/<package>/<rule name>.swift` for a hand-written `safedi_compile`; one combined file per module |
| Tuist (`SafeDITuist` plugin) | `$(DERIVED_FILE_DIR)/SafeDIGenerated.swift` for each target, under the target’s intermediates in DerivedData |
| Custom build system | Wherever your `generate` invocation points `--combined-output` or `--output-directory` |

In a Swift package built with `swift build`, find them from the package’s directory with:

```bash
find . -name '*+SafeDI*.swift' -not -path '*/checkouts/*'
```

The plugin-based integrations name files `<File>+SafeDI.swift` for the dependency trees of the roots a source file `<File>.swift` declares and for the initializers generated for the types it declares with `generateDependencyTree: true`, `<File>+SafeDIMock.swift` for the mocks of the `generateMock: true` types it declares, `<Type>+SafeDIMock.swift` for each type a `#SafeDIConfiguration` lists in `additionalMocksToGenerate`, and `SafeDIMockConfiguration.swift` for the shared mock configuration. Files whose names would match, ignoring letter case, are prefixed with as many enclosing directories as tell them apart (`FeatureA_Root+SafeDI.swift`), then suffixed `_2`, `_3`, … if a name still matches. A generated file that holds only compile-time assertions belongs to a declaration the build’s conditions leave inactive (see [Declarations that decide which files SafeDI generates](#declarations-that-decide-which-files-safedi-generates)).

## Conditional compilation

SafeDITool scans your source before the compiler runs, so it decides for itself which clauses of an `#if` block are active, using the compilation conditions your build integration [reports](#reporting-active-conditions):

- `true`, `false`, `!`, `&&`, `||`, and parentheses are evaluated.
- A bare condition such as `DEBUG` or `STAGING` is active when the reported conditions include it and inactive otherwise. SafeDITool scans the clause the conditions select and ignores the others.
- Platform conditions such as `os(iOS)`, `arch(arm64)`, `canImport(UIKit)`, `targetEnvironment(simulator)`, `swift(>=6.0)`, and `compiler(>=6.0)` are left to the compiler. SafeDITool scans every clause one of them could select, so declarations under `#if os(iOS)` and under its `#else` are both visible to code generation, as [Platform conditions](#platform-conditions) describes.

So a type declared under `#if DEBUG` and a different type declared under `#else` can both fulfill the same protocol:

```swift
#if DEBUG
@Instantiable(fulfillingAdditionalTypes: [EventLogger.self])
public final class ConsoleEventLogger: EventLogger, Instantiable { … }
#else
@Instantiable(fulfillingAdditionalTypes: [EventLogger.self])
public final class DisabledEventLogger: EventLogger, Instantiable { … }
#endif
```

SafeDITool takes the reported conditions as complete. If your build defines a condition that your integration does not report, SafeDITool scans the wrong clause. To catch that, every generated file begins with an assertion for each `#if` decision that changed what SafeDI generated. An assertion reads:

```swift
#if !(DEBUG)
#error("SafeDI scanned this module assuming `#if DEBUG` was active, but it is inactive in this compilation. Report the conditions this target compiles with to SafeDITool, as the \"Reporting active conditions\" section of the SafeDI manual describes for your build system.")
#endif
```

A mismatch therefore fails the build at the generated file, with a message naming the condition. A block that changes nothing SafeDI generates asserts nothing, such as a `#if DEBUG struct PreviewData` that no SafeDI declaration mentions. Under Bazel, Tuist, and a custom build that writes `.safedi` files, a block that declares a `package` type is asserted too, since another module may name that type.

A debug-only initializer that SafeDI does not call, such as a preview helper that does not take the type’s dependencies, asserts nothing either, so it needs no setup under any integration:

```swift
@Instantiable
public struct ProfileView: Instantiable {
    public init(user: User) { self.user = user }
    @Received let user: User

    #if DEBUG
    init(previewName: String) { self.user = User(name: previewName) }
    #endif
}
```

Neither does an initializer in an `@Instantiable` extension, since the extension’s `instantiate()` method builds the type.

### Platform conditions

SafeDITool generates code before the compiler picks a clause of `#if os(iOS)`, and it generates one call for every platform, so it builds every dependency any clause declares, on every platform. Give a type the same dependencies and the same initializer on every platform: declare them once, outside the `#if`, and put the platform difference inside the type’s body.

- A dependency declared in each clause is an error, wherever generated code builds the type: SafeDITool reports it as declared more than once.
- A dependency declared in only one clause, beside an initializer that does not take it in the other clause, is built on every platform. The build then fails, at the generated call, on each platform whose clause does not declare it.

```swift
// Fails to compile on macOS: the generated code builds `haptics` there too,
// and calls `init(haptics:)`, which macOS does not have.
@Instantiable
public final class Feedback: Instantiable {
    #if os(iOS)
    public init(haptics: Haptics) { self.haptics = haptics }
    @Instantiated private let haptics: Haptics
    #else
    public init() {}
    #endif
}

// Compiles on every platform: one dependency and one initializer,
// with the platform difference inside the body.
@Instantiable
public final class Feedback: Instantiable {
    public init(haptics: Haptics) { self.haptics = haptics }
    @Instantiated private let haptics: Haptics

    public func confirm() {
        #if os(iOS)
        haptics.playSuccess()
        #endif
    }
}
```

`Haptics` then exists on every platform too, and can do nothing where there is nothing to do.

The same holds for types: declare an `@Instantiable` type, or a type that fulfills one, once, outside the `#if`, with the platform difference inside its body or its `instantiate(…)` method. A type declared in each clause is reported as a duplicate, and the error suggests this.

### Declarations that decide which files SafeDI generates

A root, a type with `generateDependencyTree: true` or `generateMock: true`, a type `additionalMocksToGenerate` lists, and a `#SafeDIConfiguration` may each sit behind any condition, under every integration. SafeDI plans a generated file for each of them whichever clause declares it, and when the build leaves the declaration inactive, it writes that file with only its compile-time assertions:

```swift
#if DEBUG
@Instantiable(isRoot: true)
public struct DebugMenu: Instantiable { … }
#endif
```

### Declarations that only feed mock generation

Put a declaration that only feeds mock generation under your module’s `mockConditionalCompilation` (`#if DEBUG` by default), with no further setup. Such a declaration is an `@Instantiable(mockOnly: true)` type or extension, or a hand-written `mock()` or `customMockName` method. SafeDITool reads it as if the condition were active, and asserts nothing about it, since the generated mocks that use it are under the same `#if`. This works under every integration, including a Swift package built with SwiftPM’s native build system ([Reporting active conditions](#reporting-active-conditions)). It applies only under the mock condition itself, and not when `mockConditionalCompilation` is `nil`, since the generated mocks are then unconditional.

A plain type under the mock condition is different, because production code, such as a seam’s generated initializer, can name it, and that code compiles in release builds too. SafeDI takes the narrowest access the type has with the condition active or inactive, so the generated code is the same, and compiles, in debug and release builds. Here `Endpoint` is taken as `package`:

```swift
#if DEBUG
@Instantiable(mockOnly: true)
extension APIClient {
    public static func mock() -> APIClient { APIClient() }
}

public struct Endpoint {}
#else
package struct Endpoint {}
#endif
```

A seam that receives `@Received(onlyIfAvailable: true) let endpoint: Endpoint?` therefore takes it on its `package` tier in every build, and a public mock’s signature reads `Endpoint` the same way.

A type declared only under the mock condition still counts as declared, so generated production code may name it. Declare it for builds without the condition too, for example in another file under `#if !DEBUG`, or that code does not compile there. That `#if !DEBUG` is an ordinary block, which SafeDITool evaluates with the reported conditions and asserts. So under SwiftPM’s native build system, add `.define("DEBUG", .when(configuration: .debug))` to the target’s `swiftSettings`, or debug builds fail at SafeDI’s assertion.

A module that only mock-only declarations need can be imported in its own `#if` block under the mock condition, here the default `DEBUG`:

```swift
#if DEBUG
import NetworkingMocks
#endif

#if DEBUG
@Instantiable(fulfillingAdditionalTypes: [Network.self], mockOnly: true)
extension MockNetwork {
    public static func mock() -> MockNetwork { MockNetwork() }
}
#endif
```

The generated mocks import `NetworkingMocks` whatever conditions the build reports, as do the mocks of a module that depends on this one. The generated dependency tree imports it only when the build reports `DEBUG`. A file that holds both, such as the output of `generate --combined-output`, imports what either needs.

### Reporting active conditions

SafeDITool can read the conditions in two ways:

- **From the build settings, when the build runs.** The `SafeDIGenerator` plugin and the Tuist plugin pass `${SWIFT_ACTIVE_COMPILATION_CONDITIONS}` and `${OTHER_SWIFT_FLAGS}` to SafeDITool. A build system that expands them hands SafeDITool exactly the conditions the compiler receives, and SafeDITool uses those instead of any reported another way.
- **From what the plugin can see, while it plans the build.** A Swift package’s build tool plugin can read the target’s `swiftSettings` defines, including those with `.when(configuration:)` conditions, and its trait defines, but not SwiftPM’s implicit `DEBUG`. An Xcode project’s build tool plugin can read no conditions at all. When the build system passes the build-setting references through unexpanded, SafeDITool uses these conditions instead.

| Integration | Conditions SafeDITool generates code with |
|-------------|-------------------------------------------|
| Swift package plugin, `swift build` with the Swift Build backend: the default in Swift 6.4, and `--build-system swiftbuild` in Swift 6.2 | The build settings. Verified with Swift 6.2 and Swift 6.4. |
| Swift package plugin, `swift build` with the native backend: the default in Swift 6.2, which ships with Xcode 26, and `--build-system native` in Swift 6.4 | What the plugin can see. To guard a production declaration with `DEBUG`, add `.define("DEBUG", .when(configuration: .debug))` to the target’s `swiftSettings`. |
| Swift package plugin, built by Xcode | The build settings, in every configuration. |
| Xcode project plugin | The build settings. |
| Tuist plugin | The build settings: the script’s shell expands them. |
| Other prebuild scripts | What the script passes, as [Custom build system integration](#custom-build-system-integration) describes. |
| Bazel `safedi_swift_library` and `safedi_compile` | The compilation mode, the target’s `defines`, and `-D` flags, as listed below. |

`swift build --help` names your toolchain’s default backend. The `DEBUG` define is harmless under the other build systems, which read the build settings instead; the [Example Package Integration](../Examples/Example%20Package%20Integration/Package.swift) declares it. Xcode hands a package’s plugin its `.when(configuration:)` defines as for a debug build, whatever configuration it compiles, so the build settings correct what the plugin sees in Release.

Under Bazel, SafeDITool generates code with:

- `DEBUG` in the `dbg` and `fastbuild` compilation modes, and `NDEBUG` in the `opt` compilation mode.
- The target’s `defines`.
- Each `-D` flag in the target’s `copts`, after Make variable expansion, so `-D$(NAME)` reports the value of `--define=NAME=…`.
- Each `-D` flag passed with `--@rules_swift//swift:copt`, or `--@rules_swift//swift:exec_copt` for a target built in the exec configuration.

`safedi_swift_library` gives its `swift_library` and its `<name>_safedi` target the same `defines` and `copts`; a hand-written `safedi_compile` must repeat the `defines` and `copts` of the `swift_library` that compiles its output. Bazel does not report `defines` propagated from a dependency, `--@rules_swift//swift:per_module_swiftcopt`, or copts configured on a custom Swift toolchain. `--copt` and `--define` alone do not reach the Swift compiler, so they never need reporting.

The Swift package plugin scans a target’s dependencies with the target’s own conditions, and the target’s generated files assert what SafeDITool decided about the dependencies’ `#if` blocks. So a target must define some conditions its dependencies use. For example, if `Networking` declares, under `#if STAGING`, a production type or a type a seam or public mock names, define `STAGING`:

- on every target whose dependency tree reaches that declaration;
- on every target that calls a seam of `Networking`, or of a module that depends on `Networking`.

A target that calls another module’s seam also shares its `mockConditionalCompilation`, as [Calling a public mock from another module](#calling-a-public-mock-from-another-module) describes.

## Reference

The rules in this section are the detail behind the sections above, which point here where they apply.

### Access of generated parameters

How visible must a type be to appear in a [seam’s](#generating-a-dependency-tree-per-module) generated initializer or a [public mock](#public-mocks)? Each parameter is as visible as the narrowest type it names. SafeDI takes each type’s access from the declaration it reads for it:

- A declaration in the module SafeDI generates the code for, `@Instantiable` or not, `protocol` and `typealias` included.
- A `package` or wider declaration in another module SafeDI reads.

A type declared inside an extension has its own access, capped by the extended type’s. Your module’s own declaration of a name wins over another module’s, as it does for the compiler. If two other modules each declare a type named `Theme`, SafeDI takes the narrower one, unless the code spells the module (`Core.Theme`).

In an `#if` block, a type has the access it has in the clause the reported conditions select. Under a platform condition, it has the narrowest access among the clauses the compiler could select ([Conditional compilation](#conditional-compilation)).

A type SafeDI reads no declaration of is taken as `public`. That is right for a system framework’s type, a type of a package fetched from a URL, and a binary target’s type. Under Bazel or Tuist, it also applies to a first-party module that does not run SafeDI, and there it can be wrong: that module’s `package` type fails to compile at the generated `public` initializer or mock, whose comment names the types SafeDI took as `public`. Run SafeDI on every first-party module, as [Generating your dependency tree](#generating-your-dependency-tree) says.

Where the parameters differ in access, SafeDI generates one tier for each level: the [initializer](#generating-a-dependency-tree-per-module) generated code calls, and, when the module sets `generatePlainDependencyTreeInitializers`, the one for code you write. The narrowest tier takes every parameter and builds the tree. Each wider tier takes the parameters code at its level can name, and calls the next narrower tier with `nil` for the rest. A seam’s own initializer and the types its tree builds keep their access: only the types a tier takes must be as visible as the tier.

SafeDI can take a type as wider than the compiler does. The compiler then reports an error at the tier, in the generated file. That happens for:

- A type of a module your files import below `public` (`internal import UIKit`), or an `@_spi` type. SafeDI takes both as `public`.
- A type SafeDI sees no declaration of: one a macro generates, or one in a file the build does not list for SafeDI. Run SafeDI on the module that declares it and list that module among this module’s SafeDI dependencies ([Which modules to list](#which-modules-to-list)), or, under the Xcode project plugin, add its directory to `additionalDirectoriesToInclude`. For a type a macro generates, name a type SafeDI reads in its place.

### Where a seam differs from building its tree inline

A seam’s generated initializer takes one parameter for each name the tree receives from outside, and passes it to the receivers by name, as a root’s `init()` does, without knowing what its callers pass. So a few trees that build inline are errors at a seam, and a few build differently.

#### Errors at a seam

Each of these errors says what to change.

- **One name received in two forms that one parameter cannot carry.** One type receives `session: Session` and another `session: LazilyInstantiated<Session>?`. The initializer has one `session` parameter, and no one value is both. As inline, some forms provide others: a value provides its optional form, and a required, non-optional `LazilyInstantiated` or `SendableLazilyInstantiated` provides its instance and its own optional form. Two unrelated types under one name, such as `token: Token` and `token: String`, are the same error.
- **A `Sendable` builder inside the seam that reads a wrapper that is not `Sendable`.** Say a `SendableInstantiator` inside the seam builds a type that receives an `Instantiator`, `ErasedInstantiator` or `LazilyInstantiated` the seam takes as a parameter. That is an error, even where inline would pass `nil`: the parameter is declared outside the wrapper’s `@Sendable` builder, which can capture only a `Sendable` value. A deferred value such a builder reads is held in a `SendableLazilyInstantiated`, which needs the deployment targets [Sendable wrappers](#sendable-wrappers) states.
- **A name hidden from its receiver.** A type between the seam and the receiver, the seam included, declares the name with a property that does not provide it.
- **An initializer the generated one would collide with**, such as an initializer in the seam’s body that a call with the readable labels could also reach, in a module that sets `generatePlainDependencyTreeInitializers: true`. Without the setting, the seam can keep such an initializer for the code that already calls it. A tier that takes no argument is `init()` either way, so a hand-written `init()` collides with it.
- **A hole’s implementation that reads a value bound on the way to a seam built again.** When a seam’s tree builds the seam again, directly or through another seam of its module, the builders it took are handed on to that call. So the caller that fills a builder cannot hand its implementation a value the tree declares on that path.
- **A hole’s implementation that reads a value a cycle in the seam’s tree declares again.** Inline, the type an `Instantiator` or lazy cycle builds again receives the values declared along the cycle, but a builder hands its implementation the same values at every level of the cycle.

#### Trees a seam builds differently

A hand-written call of a seam’s initializer creates every argument at the call. A generated call passes each value so that it is created where it would be inline, with one exception. Say a hole’s implementation reads a value a generated call defers, and the implementation’s own tree builds the seam again beneath another declaration of that value’s label. The implementation then reads the value when the implementation is built, where inline its receiver reads it when that receiver is built.

### Generated imports

The files SafeDI generates import the modules that your files declaring `@Instantiable` types or a `#SafeDIConfiguration` import. SafeDI also adds an import a generated file needs that none of those files has:

- the module of a type it builds through a [`fulfilledByType`](#making-protocols-instantiable) string or a `fulfillingAdditionalTypes` entry;
- in a generated mock, the module of a type a flat `mock()` parameter defaults to, of the type an `additionalMocksToGenerate` entry names, and of a `mockOnly` declaration whose hand-written mock it calls.

An added import spells an access level, chosen as described below, when another file of your module imports that module below `public`, even a file with no SafeDI content. It is `@_implementationOnly` when another file’s import of that module is. SafeDI adds no import when your module declares a type of the same name that other files can see, since that is the type the generated code finds.

If a generated file does not compile, or warns:

- **A missing import.** Where SafeDI knows no module for a declaration, as under the [Xcode project plugin](#limits-of-the-xcode-project-plugin) and for a file read through `additionalDirectoriesToInclude`, it adds no import. List the module in [`additionalImportedModules`](#safediconfiguration), or import it in one of your files that declare SafeDI content.
- **An ambiguous name.** An added import brings in the whole module. If your files that declare SafeDI content also import another module with a type of the same name as one the generated file uses, rename one of the types, or stop importing the other module in those files.
- **An unused-import warning.** See below.

A generated import has no access level unless one of your files that declare SafeDI content gives an import one (`internal import Foundation`). Then each generated file gives each import the level its own declarations need, such as `public` where a seam’s initializer or a public mock names one of the module’s types, so it compiles with or without the `InternalImportsByDefault` upcoming feature. Generated mocks, and the configurations of public mocks, compile only under the module’s [`mockConditionalCompilation`](#safediconfiguration). So a level only they need is spelled under that condition, beside the level the rest of the file needs, and a build without the condition, such as a Release build, draws no unused-import warning:

```swift
#if canImport(Foundation)
#if DEBUG
public import Foundation
#else
internal import Foundation
#endif
#endif
```

To pick a level, SafeDI must know which module declares each type a generated declaration names. For a type whose declaration it does not read, it assumes:

- every module your files import at the level of the declaration that names the type, or wider;
- Foundation, for Foundation’s common types;
- for other types, every module that a dependency’s file imports at `package` or wider, when that file’s `@Instantiable` declaration names the type in a dependency or an initializer parameter. An import there that spells no level tells SafeDI nothing: spell it at the level of the declaration that names the type.

This assumption can be too broad. A file whose `public` declaration names a type SafeDI reads no declaration of imports, `public`, every module SafeDI assumes for that type, and the compiler warns at one whose types the file does not name. To silence the warning, import that module below `public` (`internal import Analytics`) in your files that declare SafeDI content, unless one of their `public` declarations needs it.

## Comparing SafeDI and Manual Injection: Key Differences

SafeDI is designed to be simple to adopt and minimize architectural changes required to get the benefits of a compile-time safe DI system. Despite this design goal, there are a few key differences between projects that utilize SafeDI and projects that don’t. As the benefits of this system are outlined in the README’s [Features](../README.md#features) section, this section outlines the pattern changes required to utilize a DI system like SafeDI.

### Instantiating objects

In a manual DI system it is common to directly call your dependencies’ `init(…)` functions. With SafeDI, `@Instantiated` properties instantiate your dependencies for you. Calling a dependency’s `init(…)` directly exits the SafeDI-built dependency tree, which removes property lifecycle guarantees. Likewise, create the tree by calling the root’s generated `init()`, not its memberwise `init(…)`, as [Creating the root of your dependency tree](#creating-the-root-of-your-dependency-tree) describes. To instantiate a dependency later, use an [`Instantiator`](#delayed-instantiation) or [`LazilyInstantiated`](#lazilyinstantiated).

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

It is strongly recommended that projects adopting SafeDI start their migration by identifying the root of their dependency tree, as [Creating the root of your dependency tree](#creating-the-root-of-your-dependency-tree) describes, and making it `@Instantiable(isRoot: true)`. Once your root object has adopted SafeDI, continue migrating dependencies to SafeDI in either a breadth-first or depth-first manner. As your adoption of SafeDI progresses, you’ll find that you are removing more code than you are adding: many of your dependencies are likely being passed through intermediary objects that do not utilize the dependency except to instantiate a dependency deeper in the tree. Once types further down the dependency tree have adopted SafeDI, you will be able to avoid receiving dependencies in intermediary types.

### Adopting SafeDI in a large codebase

A codebase of many modules adopts SafeDI the same way, from the root down. Four features let it do so without making every type `public` or building the whole tree in the root’s module:

- **Types keep their access levels.** A type and its initializer need to be visible only to the module whose generated code builds them, so `internal` and `package` types work. See [Access levels](#access-levels).
- **Each module can generate its own tree.** Decorate the type at a module’s boundary, such as a feature’s entry point, with `@Instantiable(generateDependencyTree: true)`, which makes it a seam. That module then generates the type’s tree as an initializer, and trees in other modules call it. A change inside the module recompiles only that module and the calls. In production, the types built inside need to be visible only in that module. See [Generating a dependency tree per module](#generating-a-dependency-tree-per-module).
- **Implementations can live above the feature.** A module’s tree can instantiate a protocol that only the app implements. The module’s generated initializer then takes a builder for it, and the app’s generated code fills it in, as the example below shows.
- **Mocks cross modules.** A mock in another module builds a seam’s whole tree, so it needs that tree’s types to be visible, unless the seam is declared with `generateMock: .public`. That gives the seam a `public` `mock()`, which tests and previews in any package can call. See [Public mocks](#public-mocks).

For example, a feature module declares its screen as a seam whose tree instantiates a protocol the app implements:

```swift
// In module Feed, which depends on the module that declares `Session`, a `public` @Instantiable type.
public protocol FeedService {
    func refresh() async
}

@Instantiable(generateDependencyTree: true, generateMock: .public)
public final class FeedScreen: Instantiable {
    init(session: Session, service: FeedService) {
        self.session = session
        self.service = service
    }

    @Received private let session: Session
    @Instantiated private let service: FeedService
}
```

`Feed` sees no `@Instantiable` declaration that fulfills `FeedService`. So the initializer `Feed` generates for `FeedScreen` takes `session` and a builder for `service`. The app declares the implementation. When a tree in the app reaches `FeedScreen`, its generated code fills the builder with an `AppFeedService`, built from the `session` the builder is handed:

```swift
// In module App, which depends on Feed.
@Instantiable(fulfillingAdditionalTypes: [FeedService.self])
final class AppFeedService: FeedService, Instantiable {
    init(session: Session) {
        self.session = session
    }

    func refresh() async {}

    @Received private let session: Session
}
```

[Calling a public mock from another module](#calling-a-public-mock-from-another-module) shows a test in another package calling `FeedScreen.mock()`.

A seam needs no root above it. Code that does not use SafeDI yet can call a seam’s generated initializer by hand, so a seam can mark how far adoption has reached. An app target can also call a seam instead of declaring a root: unlike a root, a seam can take `@Forwarded` properties, such as the target’s configuration. These calls need `#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)` in the seam’s module, here in `Feed`’s `SafeDIConfiguration.swift`. Remove it once SafeDI generates every call. [Generating a dependency tree per module](#generating-a-dependency-tree-per-module) says what the compiler checks in a hand-written call.

Seams and public mocks need SafeDI to know which module declares each type, so run it on the modules [Generating your dependency tree](#generating-your-dependency-tree) names. The Xcode project plugin builds every tree inline, seams included, so these features apply there only as [Limits of the Xcode project plugin](#limits-of-the-xcode-project-plugin) describes.

## Migrating from SafeDI 1.x to 2.x

SafeDI 2.x requires Swift 6.2 or later and does not support CocoaPods. Projects using an earlier Swift version or CocoaPods should use SafeDI 1.x.

SafeDI 2.x also removes support for CSV-based configuration files (`.safedi/configuration/include.csv` and `.safedi/configuration/additionalImportedModules.csv`). Configuration is now done via the `#SafeDIConfiguration` macro.

### Automated migration

SafeDI provides a command plugin to automate the migration:

```bash
swift package plugin safedi-v1-to-v2 --target <YourRootTarget>
```

This plugin will:
1. Verify your `swift-tools-version` is 6.2 or later
2. Create a `SafeDIConfiguration.swift` file in your target’s source directory
3. Migrate any existing CSV configuration values into the new `#SafeDIConfiguration` macro
4. Delete the obsolete CSV files

### Manual migration

1. Update your `swift-tools-version` to 6.2 or later
2. Update your SafeDI dependency to `from: "2.2.0"`
3. If you have `.safedi/configuration/include.csv` or `.safedi/configuration/additionalImportedModules.csv`, add a `#SafeDIConfiguration` in your root module with the equivalent values and delete the CSV files
4. If you don’t have CSV configuration files and do not need other SafeDI configuration options, no `#SafeDIConfiguration()` declaration is required

### Plugin changes

The `SafeDIPrebuiltGenerator` plugin has been removed in SafeDI 2.x. `SafeDIGenerator` is now the only build tool plugin and uses a prebuilt binary by default. If you were previously using `SafeDIPrebuiltGenerator`, switch to `SafeDIGenerator`. For users of the Xcode build plugin: the `InstallSafeDITool` command plugin still exists as an Xcode-only helper for the prebuilt-tool install flow described under [Installing the prebuilt SafeDITool binary](#installing-the-prebuilt-safeditool-binary).

### Migrating prebuild scripts or custom build system integrations

If you invoke `SafeDITool` directly (not via the provided SPM plugin), the 1.x `--dependency-tree-output` flag has been replaced by `generate --combined-output`.

Before (1.x):
```bash
safeditool input.csv --dependency-tree-output ./generated/SafeDI.swift
```

After (2.x), single module:
```bash
safeditool generate input.csv --combined-output ./generated/SafeDI.swift
```

[Custom build system integration](#custom-build-system-integration) describes the other options a custom integration passes, including those that run `generate` once per module.

## Example applications

We’ve tied everything together with an example multi-user notes application backed by SwiftUI, which you can compile and run with each build system SafeDI supports:

- [`Examples/ExampleProjectIntegration`](../Examples/ExampleProjectIntegration): a single-module Xcode project.
- [`Examples/ExampleMultiProjectIntegration`](../Examples/ExampleMultiProjectIntegration): a multi-module Xcode project.
- [`Examples/Example Package Integration`](../Examples/Example%20Package%20Integration): a multi-module Swift package.
- [`Examples/ExampleBazelIntegration`](../Examples/ExampleBazelIntegration): a multi-module Bazel workspace whose modules are `safedi_swift_library` targets.
- [`Examples/ExampleTuistIntegration`](../Examples/ExampleTuistIntegration): a Tuist workspace of two projects whose targets use the `SafeDITuist` plugin.

## Under the hood

SafeDI has a `SafeDITool` executable that the `SafeDIGenerator` plugin utilizes to read code and generate a dependency tree. The executable heavily utilizes asynchronous processing to avoid `SafeDITool` becoming a bottleneck in your build. It parses a Swift file with `SwiftSyntax` only when the file contains `@Instantiable` or `#SafeDIConfiguration`, or when a quick text search shows the file may declare a type whose access SafeDI checks, such as a protocol an `@Instantiable` type depends on.

`SafeDITool` utilizes Apple’s [SwiftSyntax](https://github.com/apple/swift-syntax) library to parse your code and find your `@Instantiable` types’ initializers and dependencies. With this information, SafeDI generates a graph of your project’s dependencies and validates it during `SafeDITool` execution. If the graph is invalid, `SafeDITool` reports each problem as a compiler diagnostic, offers a fix-it where the repair is unambiguous, and exits non-zero. Source code is only generated if the dependency graph is valid.

Due to limitations in Apple’s [Swift Package Manager Plugins](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/Plugins.md), the `SafeDIGenerator` plugin parses all of your first-party Swift files in a single pass. The Bazel rule, the Tuist plugin, and other builds that run `SafeDITool` once per module parse each module’s files once. They hand each module’s declarations to the modules that depend on it in a `.safedi` file, as [Custom build system integration](#custom-build-system-integration) describes.

## Introspecting a SafeDI tree

You can create a [GraphViz DOT file](https://graphviz.org/doc/info/lang.html) to introspect a SafeDI dependency tree by running `SafeDITool generate` with the `--dot-file-output` parameter, as [Running SafeDITool yourself](#running-safeditool-yourself) describes for your integration. This command will create a `DOT` file that you can pipe into `GraphViz`’s `dot` command to create a pdf.

Once you have the dot file, you can run:
```bash
dot path_to_dot_file.dot -Tpdf > path_to_pdf_file.pdf
```

You can find instructions for how to install the `dot` command [here](https://graphviz.org/download/).

### Querying what a type needs

> `query needs` is in beta. Its options, text, and JSON may change in any release; the JSON’s `formatVersion` is `0` until the format is stable.

A focused app – one that builds a single feature with mock data instead of the whole product – needs only the modules that feature needs. `SafeDITool query needs` names them. Run `SafeDITool` as [Running SafeDITool yourself](#running-safeditool-yourself) describes, and give it one or more `@Instantiable` types and the directories of the project’s modules, as `generate --include` takes them. In a Swift package:

```bash
.build/artifacts/safedi/SafeDIToolBinary/SafeDITool.artifactbundle/SafeDITool-macos-arm64/bin/SafeDITool query needs HomeFeature SettingsFeature --include Sources/Foundations Sources/Services Sources/HomeFeature Sources/SettingsFeature --active-compilation-conditions DEBUG
```

A project whose build already writes `.safedi` [module info files](#custom-build-system-integration) – a Bazel or Tuist project, or any other that runs `generate --module-info-output` per module – can name those files with `--module-info`, instead of or alongside directories, and skip parsing the sources. In a Bazel project, after a build that writes them to `bazel-bin` ([Running SafeDITool yourself](#running-safeditool-yourself) says when one does):

```bash
bazel run @safedi//:SafeDITool -- query needs HomeFeature --module-info bazel-bin/Modules/Foundations/Foundations_safedi.safedi bazel-bin/Modules/Services/Services_safedi.safedi bazel-bin/Modules/HomeFeature/HomeFeature_safedi.safedi
```

For each type named, the query builds the type as its `mock()` does, with every dependency it receives provided by an `@Instantiable` declaration, and reports:

- The modules the type is built from in production, each with the declarations that build it.
- The `@Forwarded` parameters of the type.
- The dependencies no `@Instantiable` declaration fulfills, which the project provides by hand, each with its reason.

It then reports the same for the type’s mock. [The `query needs` report](QueryNeeds.md) describes which modules and which mock the report covers, how to name the types, and the JSON that `--json` prints for scripts.
