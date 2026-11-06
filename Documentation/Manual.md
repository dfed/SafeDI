# SafeDI Manual

SafeDI utilizes both Swift macros and a code generation plugin to read your code and generate a dependency tree. You decorate each type with SafeDI’s macros to declare the dependencies it instantiates, receives, and forwards; when you build, SafeDI validates the tree and generates the code that creates it, along with mocks for your tests and previews.

This manual first describes the macros and how to design a dependency tree with them, then mock generation, then how to [add SafeDI to your build](#installation) and operate it. The [Reference](#reference) after those holds the detailed rules the earlier sections point to. The sections after it are optional: how SafeDI differs from manual injection, migration guides – including [adopting SafeDI in a large codebase](#adopting-safedi-in-a-large-codebase) – example applications, a tour of how SafeDI works under the hood, and introspecting a tree.

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

2. Have an initializer that has a parameter for each of its injected properties.

3. Spell a nested type in a decorated property’s type with its enclosing types, such as `@Forwarded let configuration: Feature.Configuration` for a `Configuration` declared inside `Feature`, because generated code is in an extension where the members of `Feature` are not in scope. The `@Instantiable` macro warns, with a fix-it, when a type declared inside the decorated type is spelled without them, and SafeDI itself qualifies a nested type that an `@Instantiable` declaration [fulfills](#making-protocols-instantiable).

SafeDI guides you through the first two requirements with fix-its: the `@Instantiable` macro as you type, and `SafeDITool` when you build, for access that only the module constructing the type can judge. Do not decorate a superclass with `@Instantiable`; see [Inheritance](#inheritance).

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

[@Instantiated](#instantiated), [@Forwarded](#forwarded), [@Received](#received), and [Conditionally receiving dependencies](#conditionally-receiving-dependencies) cover each kind in detail, including `@Instantiated`’s parameters for dependency inversion and `@Received`’s `onlyIfAvailable` option.

#### Creating the root of your dependency tree

Any type decorated with `@Instantiable(isRoot: true)` is a root of a SafeDI dependency tree. In an extension on each root that has dependencies, SafeDI generates a no-parameter `public init()` that instantiates the tree; create the tree by calling that `init()`, not the root’s memberwise initializer. To bind that initializer to a global actor, or give it other attributes, see [Attributes for generated declarations](#attributes-for-generated-declarations).

SafeDI generates a root’s `init()` only in the module that declares the root, so run SafeDI in that module’s target (see [Generating your dependency tree](#generating-your-dependency-tree)), and call the `init()` from any module that depends on it. A module that reads another module’s files – as the `SafeDIGenerator` Swift package plugin reads those of every module its module depends on, and `additionalDirectoriesToInclude` reads a directory’s – writes the file it plans for a root it finds there without code. That file’s comment names the module that declares the root, when SafeDI knows it, and says to add the SafeDI plugin to that target if the root’s `init()` is missing.

A SwiftUI application’s natural root is its `App` type. A UIKit application’s app delegate already has a no-argument `init()`, inherited from `NSObject`, so create a custom `@Instantiable(isRoot: true) public final class Root: Instantiable` that the app delegate initializes and stores.

#### Access levels

SafeDI constructs each `@Instantiable` type in code it generates in a file of its own: a root’s `init()` in the root’s module, a `mock()` in the module that generates it, and the initializer generated for a type declared with `generateDependencyTree: true` in that type’s module (see [Generating a dependency tree per module](#generating-a-dependency-tree-per-module)). That code calls the type’s initializer – or an `@Instantiable` extension’s `instantiate(…)` method, or the hand-written mock method a generated mock calls – so the type, that method, and every type enclosing the type must be visible to it:

- Within the module that declares them, any access but `private` and `fileprivate` works, so a type and its initializer can stay `internal`. A type nested in a `private` type, or declared in a `private extension` without an access modifier of its own, is `fileprivate` too.
- From another module of the same package, they must be `package`, `public`, or `open`.
- From a module of another package, they must be `public` or `open`.

A member that spells no access modifier is `internal`, even in a `public` type, and an extension’s member takes the extension’s access. A type’s own initializer can be no wider than the narrowest type its dependencies name and must be as wide as its caller needs, so a type another module builds has its `@Instantiated` children at that access too. A root’s `public init(…)` that takes a `package` dependency must become `package` or `internal`; `internal` is enough.

The `@Instantiable` macro reports a `private` or `fileprivate` type, initializer, `instantiate(…)` method, or hand-written mock method as you type, with a fix-it that removes the modifier. `SafeDITool generate` checks every construction it generates – the type, each type enclosing it, and the type an extension declaring it extends – and reports each that will not compile as an error at the declaration that must change, with a fix-it that gives it the access needed. Where declaring an outer type of another module with `generateDependencyTree: true` would let that module build the type, the error offers that too.

When `SafeDITool` cannot read the file that declares the type, it reports the error without a fix-it, in the constructing module at the line that leads to the construction, such as an `@Instantiated` property, naming the declaration to change and its module:

- Under Bazel, every error about another module’s declaration lands this way. An action run unsandboxed, for example with `--strategy=SafeDI=local`, reports it at the declaration, with a fix-it.
- Under Tuist, an error lands this way when the declaring target is in another project of the workspace, and at the declaration, with a fix-it, when both targets are in one project.

An initializer, `instantiate(…)` method, or mock method that a macro fix-it adds takes the type’s access as far as the macro can see it – in an extension, that of its `instantiate(…)` method or of the extension’s members – capped by each type it is nested in and by each type declared inside the decorated declaration that a parameter names. It spells no modifier where the members beside it have that level without one. The macro cannot see the access of a type declared anywhere else, so where a parameter names a narrower one, the compiler rejects the added declaration: narrow its access, or widen that type’s.

`package` access requires the compiler’s `-package-name`, and every module of a package must be compiled with the same one. SwiftPM passes one automatically; an Xcode project sets the `SWIFT_PACKAGE_NAME` build setting, and [Bazel](#bazel), [Tuist](#tuist), and a [custom build system](#custom-build-system-integration) set it as their sections describe. A module that `SafeDITool` is told the name but not the package of has no package, as a module compiled without `-package-name` has none: a `package` type another module declares needs `public` there. `SafeDITool` reports it with that fix-it, and says to pass the module’s package instead when the module is compiled with `-package-name`; only a `package` declaration gets that second remedy. Where SafeDI knows no module for a declaration, as under the Xcode project plugin, see [Limits of the Xcode project plugin](#limits-of-the-xcode-project-plugin).

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

`fulfilledByType` takes a string literal naming the concrete type to construct — here, `"DefaultUserService"`. Representing the type as a string allows for dependency inversion: the consuming module does not need to import the module that declares the fulfiller. `erasedToConcreteExistential: true` tells SafeDI that the constructed value must be wrapped via the property type’s initializer — here, `AnyUserService(_:)` — rather than assigned directly:

| Parameter | Logic | Example |
| --------- | ----- | ------- |
| `erasedToConcreteExistential: false` | **Cast:** `FulfillingType as PropertyType` | `MyViewController` → `UIViewController` |
| `erasedToConcreteExistential: true` | **Wrap:** `PropertyType(FulfillingType())` | `MyView` → `AnyView(MyView())` |

#### Making external types `@Instantiable`

Types that are declared outside of your project can be instantiated by SafeDI through an extension decorated with `@Instantiable`, which defines how to instantiate the extended type with a `static func instantiate(…) -> ExtendedType` function. That function must be visible to the code that constructs the type, as [Access levels](#access-levels) describes. Its parameters are the dependencies it receives from further up the tree, each named by its parameter’s name (`editor` in `instantiate(for editor: Editor)`), so a dependency parameter cannot be named `_`. A parameter with a default value is not a dependency, as for an initializer: SafeDI calls `instantiate(…)` without it, and a generated mock offers it as an override.

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

SafeDI generates a root’s `init()`, the initializers of a type with `generateDependencyTree: true` (see [Generating a dependency tree per module](#generating-a-dependency-tree-per-module)), and the `mock()` of a type with `generateMock` or listed in a module’s `additionalMocksToGenerate` (see [Mock generation](#mock-generation)). The plugin cannot detect every attribute these need from source – a global actor that the initializers they call are bound to, for example – so three `@Instantiable` arguments add attributes to them:

| Argument | Adds its text to |
| -------- | ---------------- |
| `generatedInitializerAttributes` | The root’s generated `init()`, or every initializer generated for a type with `generateDependencyTree: true`. |
| `mockAttributes` | The generated `mock()`. |
| `generatedAttributes` | Both. |

A root that is not bound to the main actor needs `generatedInitializerAttributes: "@MainActor"` when its tree builds a type whose initializer is:

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

A type that is not bound to the main actor needs `mockAttributes: "@MainActor"` on its generated mock when its own initializer is, or when its tree builds a type whose initializer is:

```swift
@Instantiable(mockAttributes: "@MainActor", generateMock: true)
public final class MyPresenter: Instantiable {
    @MainActor public init() { … }
}
```

When a `generateDependencyTree: true` type’s initializers carry `@MainActor`, the root or other such type whose tree reaches it needs `@MainActor` too. SafeDI does not check this; its generated call of the initializer fails to compile.

`generatedAttributes` is the shorthand for giving both the same text, and cannot be combined with either of the other two.

```swift
@Instantiable(isRoot: true, generatedAttributes: "@MainActor", generateMock: true)
public final class Root: Instantiable { … }
```

Each argument must be a string literal. When a [`mockOnly` declaration](#splitting-production-and-mock-declarations) gives a type with a production declaration its hand-written mock, the generated `mock()` takes the production declaration’s attributes, not the `mockOnly` declaration’s, so the `@Instantiable` macro warns at `mockAttributes` on a `mockOnly` declaration, with a fix-it that removes it.

None of these arguments changes the `@Sendable` function in which SafeDI builds a `Sendable` wrapper’s dependency; see [`Sendable` wrappers](#sendable-wrappers).

### @Instantiated

Property declarations within `@Instantiable` types decorated with [`@Instantiated`](../Sources/SafeDI/Decorators/Instantiated.swift) are instantiated when its enclosing type is instantiated. `@Instantiated`-decorated properties are available to be `@Received` by objects instantiated further down the dependency tree.

To instantiate a dependency later than its enclosing type, declare the property as an [`Instantiator`](#instantiator) or a [`LazilyInstantiated`](#lazilyinstantiated). [Delayed instantiation](#delayed-instantiation) compares the three.

Each `@Instantiated` property is a distinct instance.

`@Instantiated`-decorated properties must be an `@Instantiable` type, or a type listed in an `@Instantiable(fulfillingAdditionalTypes:)` declaration.

An `@Instantiated` property’s type cannot be optional, because SafeDI always creates it; a dependency that may be absent is received with [`@Received(onlyIfAvailable: true)`](#conditionally-receiving-dependencies).

In a SwiftUI `View`, `@Instantiated` objects are re-initialized each time SwiftUI recreates the view; see this [deep dive on SwiftUI view lifecycles](https://www.donnywals.com/understanding-how-and-when-swiftui-decides-to-redraw-views/).

### @Forwarded

Property declarations within `@Instantiable` types decorated with [`@Forwarded`](../Sources/SafeDI/Decorators/Forwarded.swift) represent dependencies that come from the runtime, e.g. user input or backend-delivered content. Like an `@Instantiated`-decorated property, a `@Forwarded`-decorated property is available to be `@Received` by objects instantiated further down the dependency tree.

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

Forwarded property types do not need to be decorated with the `@Instantiable` macro. A forwarded value comes from outside the tree, so SafeDI does not follow the `@Received` dependencies of its type.

Forwarding one of SafeDI’s wrappers – an [`Instantiator`](#instantiator), [`ErasedInstantiator`](#erasedinstantiator), or [`LazilyInstantiated`](#lazilyinstantiated), or one of their [`Sendable` twins](#sendable-wrappers) – is deprecated, and SafeDI 3.0 rejects it; the `@Forwarded` macro warns at such a property. Instead:

- **Let SafeDI build it:** make the type the wrapper builds `@Instantiable`, forward what that type needs, and declare the wrapper `@Instantiated` on this type. A `LazilyInstantiated` declared this way still builds nothing until its instance is first read.
- **Receive it:** declare the wrapper `@Received`, fulfilled by an ancestor that declares it.
- **Forward the value:** forward the value the wrapper builds, which then exists as soon as this type does.

A closure, or a wrapper type of your own, is a plain forwarded value, which the types beneath receive and call or read themselves: forward one to build a value SafeDI cannot build later, or more than once.

### @Received

Property declarations within `@Instantiable` types decorated with [`@Received`](../Sources/SafeDI/Decorators/Received.swift) are injected into the enclosing type’s initializer. A `@Received` property is fulfilled by the nearest property of its label that a type above it instantiates, forwards, or [renames](#renaming-and-retyping-dependencies), which must have the received type, be its non-optional form when the receive is optional, or be a [`LazilyInstantiated`](#lazilyinstantiated) whose instance is received; if there is none, the build fails.

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

A type built again inside a [dependency cycle](#instantiator) receives the same way: a flow whose step instantiates its own `session` and a builder for the screen that built it hands the screen built again the step’s `session`. A property received [only if available](#conditionally-receiving-dependencies) that is `nil` provides nothing to the types below the receiver, so a type further down that requires the same property needs a type above to provide it.

SafeDI ignores `any` when it matches types, so `any SessionsApi` and `SessionsApi` are one type, in [renames](#renaming-and-retyping-dependencies) and `fulfillingAdditionalTypes` too.

A `@Received` property can also receive a dependency only when it is available, as [Conditionally receiving dependencies](#conditionally-receiving-dependencies) describes, or under another name and type, as [Renaming and retyping dependencies](#renaming-and-retyping-dependencies) describes.

### #SafeDIConfiguration

[`#SafeDIConfiguration`](../Sources/SafeDI/Decorators/SafeDIConfiguration.swift) is a freestanding declaration macro that provides build-time configuration for SafeDI’s code generation plugin. A module may have at most one `#SafeDIConfiguration` in any one compilation (the clauses of an `#if` block may each declare a different one), at the top level of a Swift file, with literal arguments; every parameter has a default, so the simplest valid invocation is `#SafeDIConfiguration()`. Declare it in a file named `SafeDIConfiguration.swift`. A configuration in any other file still works, but when it sets a non-default `mockConditionalCompilation`, SafeDI scans the module twice and warns at the `#SafeDIConfiguration`.

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
- `additionalDirectoriesToInclude`: Directories containing Swift files to include, relative to the executing directory. An entry may also name a single Swift file. SafeDI knows no module for the files it reads this way (see [Limits of the Xcode project plugin](#limits-of-the-xcode-project-plugin)). Only the `SafeDIGenerator` build tool plugin declares these files as build inputs, so under Tuist and Bazel list every Swift source in the build target instead: Tuist does not rebuild when those files change and cannot read them under user script sandboxing, and Bazel cannot see them at all. Default: `[]`.
- `additionalMocksToGenerate`: Type names from dependent modules to generate `mock()` methods for in this module. The types must be `@Instantiable` in their home module. See [Cross-module mock generation](#cross-module-mock-generation). Default: `[]`.
- `mockConditionalCompilation`: The conditional compilation flag to wrap generated mock code in (e.g. `"DEBUG"`). Set to `nil` to generate mocks without conditional compilation. Default: `"DEBUG"`.

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

An `Instantiator` is also how types create one another. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an `@Instantiated` `Instantiator` or `ErasedInstantiator`, or a `Sendable` twin, whichever dependency closes the cycle: each time it builds its type, every other type on the cycle is built again too, as a new instance (a lazily instantiated one when its wrapper is first read). A dependency that receives a type still being built closes no cycle: receive it with `onlyIfAvailable: true` instead. [`Sendable` wrappers](#sendable-wrappers) says what a `SendableInstantiator` on a cycle may read from outside its builder.

An `Instantiator` is not `Sendable`. To share one across concurrency domains, use its [`Sendable` twin](#sendable-wrappers), `SendableInstantiator`.

### ErasedInstantiator

For deferred instantiation of a type-erased dependency, use an [`ErasedInstantiator`](../Sources/SafeDI/DelayedInstantiation/ErasedInstantiator.swift), which combines the deferred construction of [`Instantiator`](#instantiator) with the `fulfilledByType` and `erasedToConcreteExistential` parameters covered in [Making protocols `@Instantiable`](#making-protocols-instantiable). `ErasedInstantiator` has two generics: the first must match the built type’s `ForwardedProperties` typealias, and the second matches the type of the to-be-instantiated instance.

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

An `@Instantiated` erased instantiator must name the type it builds with `fulfilledByType`. A `@Received` one names no type (nor does a `@Forwarded` one, which is [deprecated](#forwarded)): a type below `ParentView` can declare `@Received let childViewBuilder: ErasedInstantiator<(), AnyView>` to receive the instantiator `ParentView` creates.

An `ErasedInstantiator` is not `Sendable`. To share one across concurrency domains, use its [`Sendable` twin](#sendable-wrappers), `SendableErasedInstantiator`.

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

An optional `LazilyInstantiated`, or a `LazilyInstantiated<Dependency?>`, can only be received as the `LazilyInstantiated`, since its instance may be `nil`.

Receiving the instance instantiates the dependency, so a `LazilyInstantiated` property is lazy only when every type that receives its instance is created later than the type that declares it – typically because that type is built by an [`Instantiator`](#instantiator). SafeDI warns at the `LazilyInstantiated` declaration when a type created along with the declaring type receives the instance.

A lazily instantiated dependency is created at most once, so SafeDI validates `exportService: LazilyInstantiated<ExportService>` exactly as it validates `exportService: ExportService`. To let types create one another, or to create a type with forwarded properties on demand, use an [`Instantiator`](#instantiator).

A `LazilyInstantiated` property accepts the same `fulfilledByType` and `erasedToConcreteExistential` parameters as any other `@Instantiated` property:

```swift
@Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true)
private let userService: LazilyInstantiated<AnyUserService>
```

A `LazilyInstantiated` is not `Sendable`, and reads of `instance` are not synchronized. To share one across concurrency domains, use its [`Sendable` twin](#sendable-wrappers), `SendableLazilyInstantiated`.

SafeDI validates the dependency tree, not what an initializer does. Do not read `instance` from the initializer of the type that declares the `LazilyInstantiated` or `SendableLazilyInstantiated` property, or from any initializer that runs while that instance is being created, whether directly or through a callback: doing so produces undefined behavior. The guarantees each type provides are stated in the documentation of [`LazilyInstantiated`](../Sources/SafeDI/DelayedInstantiation/LazilyInstantiated.swift) and [`SendableLazilyInstantiated`](../Sources/SafeDI/DelayedInstantiation/SendableLazilyInstantiated.swift).

[Dependency kinds in the generated mock](#dependency-kinds-in-the-generated-mock) says how a mock overrides a lazily instantiated dependency.

### Sendable wrappers

`Instantiator`, `ErasedInstantiator`, and `LazilyInstantiated` are not `Sendable`. To share one across concurrency domains, declare its `Sendable` twin: [`SendableInstantiator`](../Sources/SafeDI/DelayedInstantiation/SendableInstantiator.swift), [`SendableErasedInstantiator`](../Sources/SafeDI/DelayedInstantiation/SendableErasedInstantiator.swift), or [`SendableLazilyInstantiated`](../Sources/SafeDI/DelayedInstantiation/SendableLazilyInstantiated.swift). A `SendableLazilyInstantiated` creates its instance exactly once while holding a lock and requires the instance to be `Sendable`. It is available on macOS 15, iOS 18, tvOS 18, watchOS 11, and visionOS 2 and later; the generated code is not marked `@available`, so use it only in a module whose deployment targets are at least those versions.

A `Sendable` wrapper builds its dependency in a `@Sendable` function, which may return a type that is not `Sendable` but places two requirements on the dependency’s subtree:

- **What the subtree receives from outside it must be `Sendable`**, even when the receiving type is itself `Sendable`, since the function captures it – on a [dependency cycle](#instantiator), each value the types a `SendableInstantiator` builds again receive from outside its builder. Declare a wrapper the subtree receives from outside, or whose instance it receives, as its `Sendable` twin; SafeDI reports an error at the property that receives one that is not. Wrappers instantiated inside the same `Sendable` wrapper are fine. Anything else the subtree receives that is not `Sendable` is rejected by the compiler in the generated code.
- **Every initializer the function calls must be callable synchronously outside any actor**, and so must an extension’s `instantiate(…)` and a hand-written mock method that a generated mock calls there. The initializer’s isolation counts, not the type’s: a `@MainActor` class with a `nonisolated init` is fine when its stored properties are `Sendable`. SafeDI does not check this, and the generated code fails to compile otherwise; declare such an initializer `nonisolated`. The function is not isolated to any actor, whatever the isolation of the generated `init()` or `mock()` around it, so [attributes for generated declarations](#attributes-for-generated-declarations) do not help.

To call a `@MainActor` initializer in the dependency’s subtree, declare the wrapper as its non-`Sendable` twin – `Instantiator`, `ErasedInstantiator`, or `LazilyInstantiated` – instead. SafeDI builds a non-`Sendable` wrapper’s dependency in a plain nested function, which takes the isolation of the generated `init()` or `mock()` around it. That `init()` or `mock()` must be isolated to `@MainActor`, which it is when the root or mocked type is, or when [attributes for generated declarations](#attributes-for-generated-declarations) say so. No `Sendable` wrapper’s subtree may contain the twin either.

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

A dependency counts as available only if it can be built before the receiver, which still receives it from the [nearest declaration](#received) above it. Availability therefore depends on the order in which one parent builds the properties it instantiates:

```swift
@Instantiable
public struct Parent: Instantiable {
    @Instantiated let a: A
    @Instantiated let b: B // A type under `B` receives `a`.
}
```

A type under `B` that receives `a` is receiving a property of `Parent`, which is above it, so `Parent` builds `a` before `b`. Nothing reaches into the types under `A`. The receiver gets `nil` where `a` cannot be built first: when the receiver is built inside `a`, or by `a` when `a` is an `Instantiator`, or is `a` itself, since `a` is still being built; and when two of a parent’s properties receive each other. There a required receive wins: if `A` requires `b`, `b` is built first and the receiver under `B` gets `nil`, and if anything under `B` requires `a`, `a` is built first and `A` gets `nil` for a `b` it receives only if available. When both receive each other only if available, the property declared later is built first and receives `nil`.

A renamed dependency follows the same rules; see [Renaming and retyping dependencies](#renaming-and-retyping-dependencies).

## Renaming and retyping dependencies

Use `@Received(fulfilledByDependencyNamed:ofType:)` to give a dependency an additional name and type. The dependency is the property of that name that the declaring type instantiates or forwards, or, when the declaring type has none, the one a type above it instantiates, forwards, or renames. Types further down the tree can then `@Received` the same instance under either name and type.

Here, a parent instantiates a read-write `UserManager` and also renames the object to make it available a `UserVendor`. A child receives the same instance as the read-only `UserVendor`:

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

To receive the renamed dependency inside a type-erasing wrapper, add `erasedToConcreteExistential: true`, which wraps it as [`@Instantiated` erasure](#making-protocols-instantiable) does: a property `userVendor: AnyUserVendor` is assigned `AnyUserVendor(userManager)`. With `onlyIfAvailable: true` the property is optional and is still assigned `AnyUserVendor(userManager)`. When the renamed dependency is itself optional (`ofType: UserManager?.self`), the property must be optional too, `onlyIfAvailable` or not: it is `nil` where the dependency is, and wraps it otherwise, `(userManager as UserManager?).map { AnyUserVendor($0) }`. The `@Received` macro reports a property that is not optional there, with a fix-it that adds `?`.

A rename declared with `onlyIfAvailable: true` reads its dependency, or the dependency’s optional form, from the nearest declaration of the dependency’s name. It is `nil`, for the declaring type and every type below it, where its dependency cannot be built first, as [Conditionally receiving dependencies](#conditionally-receiving-dependencies) describes, or where only the dependency’s optional form is available and is `nil`. For the types below it, the rename is the nearest declaration of its own name, `nil` included. A type below that requires the rename is built after the dependency where a parent builds both; two of a parent’s properties that need each other that way are an error, and where the dependency is an ancestor still being built, or nothing holds it, the type gets `nil`.

A rename is never fulfilled by another rename that the same type declares: rename the property the first rename starts from instead. SafeDI also reports such a pair where `#if` blocks that are active together hold the two renames, or where clauses of a condition only the compiler decides, such as `#if os(iOS)`, hold them; there, give the first rename another label.

The rename’s `ofType:` must name exactly the renamed property’s type, or a `LazilyInstantiated` property’s instance type. SafeDI does not check that the retyped property can be fulfilled by the original type; the Swift compiler checks the generated assignment and reports a mismatch.

The renamed property may keep the original label, but below it that label then names the renamed type. Give the renamed property a label of its own when anything below receives the original; the same holds for an `@Instantiated` or `@Forwarded` property that reuses a label from higher in the tree.

### Sharing one instance across properties of disparate types

Renaming can be applied more than once to the same `@Instantiated` or `@Forwarded` property, so a single instance can be received as several different types: any type the instance can be assigned to, such as unrelated protocols it conforms to or a superclass. Instantiate it once, then rename it once per type. Types further down the tree receive whichever type they need, and every one of them gets the same instance:

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

A protocol composition works as the instantiated type as well, with no typealias required: `@Instantiated private let telemetry: EventTracker & CrashReporter` is fulfilled by a type that lists `(EventTracker & CrashReporter).self` in `fulfillingAdditionalTypes`, and the renames then use `ofType: (EventTracker & CrashReporter).self`.

Generated mocks resolve `@Received` dependencies from their declared types rather than from these renames. See [Dependency kinds in the generated mock](#dependency-kinds-in-the-generated-mock) for what that means for `ProfileView.mock()`.

## Generating a dependency tree per module

A root’s generated `init()` builds the whole tree in the root’s module, so every type in it must be visible there, and any change regenerates and recompiles the whole tree. A type decorated with `@Instantiable(generateDependencyTree: true)` is a seam: its own module generates its tree as an initializer that takes what the tree needs from outside, and every tree that reaches the seam calls that initializer and treats the seam as a leaf, so a change inside the seam’s tree recompiles only the seam’s module and the calls. A seam may receive and forward dependencies, unlike a root; it may not also be a root or `mockOnly`, and the argument is not permitted on an extension. Mocks do not call the generated initializer, as [Public mocks](#public-mocks) describes. [Adopting SafeDI in a large codebase](#adopting-safedi-in-a-large-codebase) says where seams go.

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
    public init(user: User, database __safeDI_database: @autoclosure @escaping () -> Database, logger __safeDI_logger: @autoclosure @escaping () -> Logger?) {
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

The generated initializer takes:

1. The seam’s own `@Received` and `@Forwarded` properties, in declaration order and as the seam declares them.
2. Then, by label, every property the tree receives that nothing inside the tree provides: required where some receiver requires it, keeping an optional type a receiver declares (`session: Session?`), and optional (`logger: Logger?`) where every receiver receives it only if available, as the seam’s own receive only if available is too.
3. No parameter has a default.
4. A property the tree receives by value is an `@autoclosure`, read at most once, when the tree first needs it, so a `LazilyInstantiated` the caller holds is instantiated where it would be inline. A wrapper the tree receives as itself, and the seam’s own properties, are taken by value.
5. So a hand-written call passes a local, not a property of `self`: the closure holds `self` until the tree first reads the value, a retain cycle when `self` stores the seam.

A tree that reaches the seam calls the generated initializer as it calls any other, passing a property received only if available by the usual [availability rule](#conditionally-receiving-dependencies): `nil` where its own tree does not provide it, as for `logger` here. Receivers get the values they would get inline, except as [Where a seam differs from building its tree inline](#where-a-seam-differs-from-building-its-tree-inline) lists:

```swift
// Generated in module App, whose root instantiates Screen.
func __safeDI_screen() -> Screen {
    _ = Screen.__safeDI_Screen_3192EA1C03ABD98F.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
    return Screen(user: user, database: database, logger: nil)
}
```

Each generated call names the enum generated beside the initializer, and adding a `@Received` property beneath the seam adds a parameter and renames the enum, so a stale generated call fails to compile. A hand-written call writes every argument, so it fails to compile when a parameter is added, changes type, or is removed.

The seam’s module and each caller compute the initializer from the same declarations, those of the seam’s module and the modules it depends on: under the `SafeDIGenerator` plugin from its target graph, and otherwise from the `.safedi` files a [custom build](#custom-build-system-integration) describes. The plugin cannot tell whether the seam’s target applies it, so under the plugin each generated call of another module’s seam carries the comment above. Under Bazel, Tuist or a custom build, the comment says instead to compile the code SafeDI generated for the seam’s module into it: its `safedi_compile` rule in its library’s `srcs`, `SafeDI.generatedSource` in its target’s `sources`, or the file its `generate` run writes. A seam whose module SafeDI does not know is built inline, as [Limits of the Xcode project plugin](#limits-of-the-xcode-project-plugin) describes. A seam whose initializer, or a [public mock](#public-mocks) whose signature, would depend on a declaration its callers cannot see, such as one in its own module’s `additionalDirectoriesToInclude`, is an error when that changes what a call depends on, reported at the seam for a seam. That holds whether the declaration is in the tree or outside it, with an initializer, `instantiate(…)` or mock method that takes a parameter’s type as a dependency.

The seam’s widest initializer has the seam’s access, as its enclosing types limit it. Each parameter is as visible as the types it names, with a narrower initializer, a tier, for each narrower level among them, and each tree calls the narrowest tier it can reach, which SafeDI checks as it checks a root’s tree ([Access levels](#access-levels)). A required parameter narrower than the seam’s type is an error at the seam that says what to narrow or widen; where the seam’s `generateMock: .public` requires it to be `public`, the error leads with the cheapest fixes, such as declaring the parameter’s type `public` or receiving it only if available. A caller whose tree holds a value for a parameter its tier omits is an error too. A seam with no `@Instantiated` or renamed dependency and nothing to pass through gets no generated initializer; its callers call its own. [Access of generated parameters](#access-of-generated-parameters) says how SafeDI counts each type’s level. Here, a public `Analytics` that a type with a `package` initializer receives inside the tree is a parameter of the seam’s `public` initializer:

```swift
extension Service {
    public init(analytics: Analytics) {
        let badge = Badge(analytics: analytics)
        self.init(badge: badge)
    }
}
```

A type the seam’s tree instantiates that no `@Instantiable` declaration its module can see fulfills, such as a protocol whose implementation lives in the app, is a hole. The generated initializer takes a builder for it, `<label>Builder`, for each place the tree builds it: a closure handed a struct of the values in scope there and returning the property’s type. Where `@Sendable` builder functions lie between the seam and that place, the builder is staged: a `@Sendable` closure for the values bound inside the first of them, and so on, the last returning the property’s type. The builder, and each value in the struct, is as visible as the types it names.

A module that can see an implementation fills the builder in the code it generates, building the implementation from the struct’s fields and from its own tree, whose types and initializers must be visible there, as a root’s are; a value the implementation receives must be in the struct, or come from that module. A seam that cannot fill the builder passes it up through its own initializer; a root that cannot is an error, as is a hole in a seam’s tree under the [Xcode project plugin](#limits-of-the-xcode-project-plugin). [Where a seam differs from building its tree inline](#where-a-seam-differs-from-building-its-tree-inline) covers a seam built again inside the tree that fills it.

For a value the seam takes as an `@autoclosure`, a hand-written implementation creates the value when it first reads the struct’s property, as inline. The implementation SafeDI generates reads the caller’s own declaration instead, as the inline tree does, so a `@Sendable` function in it – a `SendableInstantiator`, or a later stage of a staged builder – that reads a `LazilyInstantiated` the caller holds is the error the inline tree gets: declare it `SendableLazilyInstantiated`, which needs the deployment targets [Sendable wrappers](#sendable-wrappers) states.

```swift
// Generated in module Feature, where `Profile` instantiates `userService: any UserService`.
extension Service {
    public struct SafeDIScope_Profile_userService {
        public let analytics: Analytics
    }

    public init(userServiceBuilder __safeDI_userServiceBuilder: @escaping (SafeDIScope_Profile_userService) -> any UserService) {
        let analytics = Analytics()
        func __safeDI_profile() -> Profile {
            let userService: any UserService = __safeDI_userServiceBuilder(SafeDIScope_Profile_userService(analytics: analytics))
            return Profile(userService: userService, analytics: analytics)
        }
        let profile: Profile = __safeDI_profile()
        self.init(analytics: analytics, profile: profile)
    }
}
```

```swift
// Generated in module App, which declares `DefaultUserService`, an implementation of `UserService`.
func __safeDI_service() -> Service {
    _ = Service.__safeDI_Service_80890FC499DC6112.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
    func __safeDI_userServiceBuilder(_ scope: Service.SafeDIScope_Profile_userService) -> any UserService {
        let analytics = scope.analytics
        let userService: any UserService = DefaultUserService(analytics: analytics)
        return userService
    }
    return Service(userServiceBuilder: __safeDI_userServiceBuilder)
}
```

```swift
// In module Feature, `ExportFeature` instantiates `screenBuilder: Instantiator<ExportScreen>` and `uploader: any Uploader`,
// and `ExportScreen` receives `exportService`. SafeDI generates the hole's struct:
public struct SafeDIScope_ExportFeature_uploader {
    public var exportService: ExportService { __safeDI_exportService.instance }
    public let screenBuilder: Instantiator<ExportScreen>
    let __safeDI_exportService: LazilyInstantiated<ExportService>
    // …and the initializer ExportFeature's generated initializer calls with its memo.
}

// In module App, which declares `DefaultUploader`, whose `UploadJob`s receive `exportService`, a hand-written call:
let feature = ExportFeature(exportService: exportService, uploaderBuilder: { scope in
    DefaultUploader(jobBuilder: Instantiator { UploadJob(exportService: scope.exportService) })
})
// The service is created when the first `UploadJob` is built, as it would be inline.
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

Here is all three buckets together in one call:

```swift
LoggedInView.mock(
    user: User(name: "dfed"),
    safeDIOverrides: .init(
        userService: StubUserService.init,
        noteStorage: .init(defaultNote: "dfed says hello")
    )
)
```

In that example, `user` is a flat `mock()` parameter, `userService` is overridden directly on `SafeDIOverrides`, and `noteStorage` uses a nested `SafeDIMockConfiguration` because it has its own configurable construction input.

Each entry on `SafeDIOverrides` is either a closure whose parameters match the resolved values of that dependency’s own inputs, or, when the dependency has its own `@Instantiated` subtree or default-valued init parameters, a nested `SafeDIMockConfiguration`. Pass any closure whose parameters match the dependency’s resolved inputs — a literal, or an `init` reference when its signature already matches:

```swift
LoggedInView.mock(safeDIOverrides: .init(
    // Literal closure — `StringStorage` has no inputs of its own, so its closure has no parameters:
    stringStorage: { InMemoryStorage() },
    // Init reference — `StubUserService.init(stringStorage:)` is already `(StringStorage) -> UserService`:
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
// can pass its initializer directly as the trailing builder:
LoggedInView.mock(safeDIOverrides: .init(
    noteStorage: .init(StubNoteStorage.init)
))
```

`SafeDIMockConfiguration` exposes an optional override for each of the child’s own `@Instantiated` dependencies and each labeled default-valued parameter of its `init` (or `instantiate(…)`), plus a trailing builder closure. A default-valued parameter’s field takes its default from the type’s hand-written `mock` method when it has one, and from its `init` (or `instantiate(…)`) otherwise. The builder’s parameters match the hand-written `mock` method’s signature if one is defined, or the `init`’s otherwise; without a builder, the generated mock calls the hand-written `mock` method or `init` directly.

Closure fields on `SafeDIMockConfiguration` are plain (non-`@Sendable`), so overrides can capture mutable non-`Sendable` test state. The closure fields of a type reached through a [`Sendable` wrapper](#sendable-wrappers) are `@Sendable`, and so are two values the mock takes for it: a labeled default-valued initializer parameter of a type in its subtree, and a dependency the mock cannot build that a type in its subtree instantiates. The mock takes each as a `@Sendable` autoclosure and evaluates it where it builds the type, once per construction, as production does. A caller still passes a value, as in `Root.mock(service: MockService())`, but an argument that captures a non-`Sendable` value, such as a `MockService` held in a `let` outside the call, does not compile.

#### Dependency kinds in the generated mock

The table below shows where each dependency kind lands in the three buckets above, and whether the caller has to supply it; a type whose dependencies are all flat parameters has no `SafeDIOverrides`.

| Dependency kind | Shape in the mock | Default |
| --- | --- | --- |
| Required `@Received` of a type some `@Instantiable` declaration fulfills (directly or via `fulfillingAdditionalTypes`), or of a type exactly one concrete type is [erased to](#receiving-a-type-erased-dependency) | Entry on `SafeDIOverrides` | Built from the real subtree, exactly like `@Instantiated` |
| Required `@Received` of a dependency the mock cannot build (below) | Flat `mock()` parameter | Required, unless the type has a hand-written mock (below) |
| `@Forwarded` | Flat `mock()` parameter | Required, unless the root provides a default or the type has a hand-written mock (below) |
| `@Instantiated` | Entry on `SafeDIOverrides` | Built from the real subtree — see [Overriding dependencies](#overriding-dependencies) |
| `@Instantiated` of a dependency the mock cannot build (below) | Flat `mock()` parameter | Required |
| `@Received(onlyIfAvailable: true)` | Entry on `SafeDIOverrides`, typed as optional | `nil` |
| Default-valued non-DI init parameter | Flat `mock()` parameter on a direct mock, or a nested `SafeDIMockConfiguration` field when reached through a parent | The parameter’s original default expression |

The mock cannot build, and so takes as a flat parameter:

- A type no `@Instantiable` declaration fulfills, including a type [different concrete types are erased to](#receiving-a-type-erased-dependency).
- A type whose `@Instantiable` declaration has `@Forwarded` properties, received other than as an `Instantiator`: only an `Instantiator` handed the forwarded values can build it, so `mock()` takes the instance, and a received `Instantiator` of it is built as usual.
- An `@Instantiated(fulfilledByType:)` dependency whose `@Instantiable` declaration the mock’s module cannot see, such as a `DefaultUserService` declared in a module only the app imports – or, under Bazel, Tuist and custom builds, one declared in a module the mock’s module does not [list](#which-modules-to-list). The parameter does not excuse a missing fulfiller: a root in the mock’s module that reaches the type still fails to generate.

A receive of such a dependency beneath the type that instantiates it is handed that type’s parameter. Beneath a `Sendable` wrapper, the parameter is a `@Sendable` autoclosure, as [above](#overriding-dependencies).

A flat `mock()` parameter for a value the mock does not build defaults to the type’s hand-written mock when that mock takes no required argument and this module can call it, which it cannot when the mock is `internal` to another module. The mock is the one the mock’s tree builds a property of the type with – the type’s own, or a [`mockOnly`](#the-mockonly-parameter) declaration’s, such as a fake that fulfills a protocol – so a forwarded `service: Service` whose fake is `FakeService` makes `mock(service: Service = FakeService.mock())`.

A [lazily instantiated](#lazilyinstantiated) dependency is overridden like any other `@Instantiated` dependency: its entry is a closure that returns the instance, which the mock calls the first time the instance is read. A type’s generated mock therefore has the same parameters whether the dependencies it receives are lazily instantiated or not.

A `@Received(onlyIfAvailable: true)` dependency is an optional entry only when every receiver in the tree, renames included, receives it only if available. It has no entry of its own when the mock already builds it – because the mocked type instantiates it, or another type in the tree requires it – or when nothing fulfills it and another type in the tree requires it, which makes it a required flat `mock()` parameter. As in production, a receiver built inside the instance, or below an `onlyIfAvailable` rename whose dependency cannot be built first, is passed `nil`; an override or parameter under the rename’s name reaches only receivers that are not below the rename.

A `@Received` dependency is resolved from its declared type, not from the renames in any particular parent. Take `ProfileView` from [Sharing one instance across properties of disparate types](#sharing-one-instance-across-properties-of-disparate-types): `ProfileView.mock()` can build `crashReporter` itself only when `Telemetry` lists `CrashReporter` in `fulfillingAdditionalTypes` – an entry for a composition such as `(EventTracker & CrashReporter).self` does not cover its members – and otherwise takes it as a required parameter. Because each received dependency is resolved on its own, a mock that receives both `EventTracker` and `CrashReporter` builds a separate `Telemetry` for each; pass one instance through `safeDIOverrides` if a test needs them to coincide.

The mock builds the dependencies its tree receives after the mocked type’s own `@Instantiated` dependencies, each after the ones it is built from, in an order set by where you declare properties, never by labels or type names, and the `SafeDIOverrides` entries for them follow that order. The flat parameters and `onlyIfAvailable` entries for received dependencies it does not build are listed by label. Of two built dependencies that receive each other only if available, the one received later is passed `nil`, as [under a root](#conditionally-receiving-dependencies).

When two flat `mock()` parameters or two entries in the same `SafeDIOverrides` or `SafeDIMockConfiguration` share a label, each is named by its label followed by its type as an identifier: received dependencies named `items` of types `[String]` and `Set<String>` become `items_Array_String` and `items_Set__String`. A mock builds every form in which its tree receives a dependency under one label, a label the mocked type forwards included: when one type requires `x: X` and another requires `x: Instantiator<X>`, the mock builds both, with the entries `x_X` and `x_Instantiator__X`. An optional form beside its non-optional form, and the instance of a `LazilyInstantiated`, are not forms of their own.

#### Receiving a type-erased dependency

A `@Received` dependency of a type no `@Instantiable` declaration fulfills can still be built by a mock when a parent erases a concrete type to it. `NotesApp` in [Making protocols `@Instantiable`](#making-protocols-instantiable) declares `@Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) private var userService: AnyUserService`, so the mock of a type that receives `userService: AnyUserService` gets a `userService` entry on `SafeDIOverrides` that defaults to building a `DefaultUserService` and wrapping it in `AnyUserService`. SafeDI looks at every `@Instantiated` property with `erasedToConcreteExistential: true` in the current module and the modules it depends on, and matches the received dependency by its full type: a received `AnyUserService` matches properties of type `AnyUserService`, not an `ErasedInstantiator<…, AnyUserService>`.

When parents erase different concrete types to the same type — say `NotesApp` erases `DefaultUserService` and another parent erases `OfflineUserService` to `AnyUserService` — nothing tells SafeDI which one a mock should build, so the dependency is a required flat `mock()` parameter:

```swift
@Instantiable(generateMock: true)
public struct SettingsView: View, Instantiable {
    // …
    @ObservedObject @Received private var userService: AnyUserService
}

SettingsView.mock(userService: AnyUserService(StubUserService()))
```

The same matching applies to a received erased instantiator: a mock builds a received `childViewBuilder: ErasedInstantiator<(), AnyView>` from a property of that type, such as `ParentView`’s in [ErasedInstantiator](#erasedinstantiator).

### Hand-written mocks

A type can provide its own mock method, declared in the body of its `@Instantiable`-decorated declaration (methods in undecorated extensions are not detected) or in a [`mockOnly` declaration](#the-mockonly-parameter). Without `generateMock: true`, the generated mocks of types that instantiate the type call `Type.mock(…)` (or the method `customMockName` names) instead of `Type(…)`, threading mock parameters through your method. The method must:

- Be visible to the generated mocks that call it, as [Access levels](#access-levels) describes.
- Take a parameter for each `@Instantiated`, `@Received`, and `@Forwarded` dependency of the declaration it is on, with a default value for every other parameter. A `mockOnly` declaration declares no dependencies, so its mock defaults every parameter, and those parameters decide which production dependencies a generated mock builds, as [Splitting production and mock declarations](#splitting-production-and-mock-declarations) describes.
- Be neither `async` nor `throws`.
- Return `Self` or the type name on a type declaration; on an extension-based `@Instantiable` type, the extended type (e.g. `-> Container<Bool>`) or a `fulfillingAdditionalTypes` entry, mirroring the corresponding `instantiate()` method.

The `@Instantiable` macro validates these requirements and provides fix-its for any issues.

When a type also has a generated `mock()`, its hand-written mock method must have a different name, wherever it is declared – in the same declaration or in a separate [`mockOnly` declaration](#splitting-production-and-mock-declarations) – or calls of `mock()` are ambiguous. Use the `customMockName` parameter to name your hand-written method, and the generated `mock()` calls through to it. With `mockOnly: true`, `customMockName` tells SafeDI which method to use as the mock provider. This is useful when you need custom logic during mock construction — for example, setting up stub behavior, configuring test doubles, or wiring delegates:

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

SafeDI’s mock generator uses a `mockOnly` declaration’s mock wherever the declaration’s concrete or fulfilled types appear in a mock dependency tree, so you don’t have to provide a mock for common types (like `User` or `NetworkClient`) every time you call `mock()` on a parent type. A `mock()` parameter for such a type, such as a `@Forwarded` dependency, defaults to the mock, as [Dependency kinds in the generated mock](#dependency-kinds-in-the-generated-mock) describes, and an `@Instantiated` one appears in `SafeDIOverrides` with `Type.mock()` as its default.

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

The hand-written mock also decides which of the production declaration’s dependencies a generated mock builds. A parameter of the mock that has a dependency’s label is passed that dependency. A dependency the mock has no parameter for is not built, is not received from further up the tree, and has no entry in `SafeDIOverrides`, unless a dependency the mock is passed receives it. In the first example, `MyService.mock()` takes no `database`, so the mock of a type that instantiates `MyService` calls `MyService.mock()` without building a `Database`. Declare `mock(database: Database = .mock())` instead to have the generated mock build the `Database` and pass it in.

### Cross-module mock generation

A mock generated with `generateMock: true` – each `mock()` a module generates, and each `SafeDIMockConfiguration` its mocks use – is an `internal` member of an extension of the mocked or configured type in that module, which avoids conflicts when several modules generate mocks for the same types. Each module generates mocks only for the types it declares. A module whose tests or previews need a mock of a type another module declares has two options:

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

This generates a `mock()` method for each listed type in the current module, even though the type is defined elsewhere. The type must be `@Instantiable` in its home module, but `generateMock: true` is not required there unless that home module also wants to generate its own mock. Do not list a type whose only declaration SafeDI reads is [`mockOnly`](#the-mockonly-parameter): its hand-written mock is its mock, and SafeDI reports such an entry as an error at the `#SafeDIConfiguration`. Call the hand-written method instead, or name it `mock` and drop `customMockName`, so that existing calls of `mock()` keep compiling.

List each type by its declared name, with enclosing types and without the module (`Outer.Inner`, not `MyModule.Outer.Inner`).

**Note:** `additionalDirectoriesToInclude` helps SafeDI scan source from Xcode project dependencies, but it does not generate mocks for those dependency modules; see [Limits of the Xcode project plugin](#limits-of-the-xcode-project-plugin).

### Public mocks

Mocks never call a seam’s generated initializer: a mock generated in another module builds a [seam’s](#generating-a-dependency-tree-per-module) whole tree beside the mocked type, so the types in it must be visible there, unless the seam is declared with `generateMock: .public`, whose mock that module’s mocks call instead.

`generateMock: .public` generates a `public` `mock()`, in the module that declares the type, that tests and previews in other modules, of this package or another, can call; `generateMock: true` is the same as `.internal`. The type must be declared `public` or `open`, or with no access level directly inside a `public extension`, and be neither generic nor nested in a generic type, which the macro checks with a fix-it; every type enclosing it, and the type an enclosing extension extends, must be `public`, which SafeDITool checks, with a fix-it at the `generateMock:` argument.

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

Each parameter of a public `mock()` is as visible as the types it names, so the mock has a `public` tier, which takes what code in any module can name, and a narrower tier for each narrower level among its parameters, as [Access of generated parameters](#access-of-generated-parameters) describes:

```swift
public static func mock(retries: Int? = nil, analytics: Analytics? = nil, safeDIOverrides: SafeDIOverrides = .init()) -> Service {
    Service.mock(retries: retries, analytics: analytics, session: nil, safeDIOverrides: safeDIOverrides)
}

package static func mock(retries: Int? = nil, analytics: Analytics? = nil, session: Session? = nil, safeDIOverrides: SafeDIOverrides = .init()) -> Service {
    // …builds the tree…
}
```

`Service.mock()` builds the whole tree; `Service.mock(analytics: Analytics())` hands the mock a value; `Service.mock(safeDIOverrides: .init(tokenCache: .init(capacity: 5)))` configures a type in the tree.

The parameters, in order: the type’s `@Forwarded` properties; its construction’s default-valued parameters; the received dependencies the mock cannot build, and its holes’ builders, required unless they default to a hand-written mock; the received dependencies it builds and those received only if available, by label; and `safeDIOverrides`.

- A received dependency the mock builds is `T? = nil`: `nil` builds it as an internal mock does, and a value is used as it is, its override never called. A lazily received dependency is taken by value. A forwarded or received value an internal mock [defaults to a hand-written mock](#dependency-kinds-in-the-generated-mock) is `T? = nil` too, `nil` calling that mock.
- A non-optional default-valued parameter is `T? = nil`, `nil` meaning the declaration’s default; a magic literal (`#fileID`) keeps its default. An optional-typed one is a `SafeDIOverrides` field defaulting to the declaration’s default, or, for a mock with no `SafeDIOverrides` and for a `mock()` bound to a global actor, a parameter with that default, which the latter evaluates in its isolation, as an internal mock does. SafeDI sees only a global actor the declaration or `mockAttributes` spells, not one from a conformance or superclass (a SwiftUI `View`, a `UIViewController` subclass), so such a type’s optional-typed default is evaluated outside the actor, and one that reads isolated state does not compile: give the type `mockAttributes: "@MainActor"`, as the comment SafeDI writes there says. As in an internal mock’s configuration, a configured type’s default that reads global-actor-isolated state cannot be evaluated by the `nonisolated` function that provides it.
- A hole – a type the tree instantiates that no `@Instantiable` or `mockOnly` declaration the module sees fulfills – is a required `<label>Builder`, as a [seam’s](#generating-a-dependency-tree-per-module) is: a closure handed a `public` struct, `<Type>.SafeDIMockScope_<Owner>_<label>`, of the values in scope where the type is built, each as visible as its type, staged the same way beneath a `Sendable` wrapper. A `mockOnly` declaration in the module or one it depends on that fulfills the hole’s type, such as a stub, removes the builder: the mock builds the stub, and production still fills the hole.
- `SafeDIOverrides` is `public`, each member as visible as the types it names, with an initializer for each access its members have.
- The types the mock’s parameters name, the hole builders’ return types among them, are as visible as the tier that takes them; the types the tree builds keep their access.
- A required parameter, such as a `@Forwarded` property, that no `public` tier can take is an error at the `generateMock:` argument, which says how to widen it.

A type in the tree with a configuration of its own is configured by a `public` struct the module’s public mocks share, `__safeDI_<Module>_<Type>_MockConfiguration` (`__safeDI_<Type>_MockConfiguration` where the build names no module), built by a function in the type’s extension that resolves defaults where the declaration does and mirrors the isolation of the initializer it calls. Declared at the module’s top level, the struct qualifies a type nested in the configured type or in a type enclosing it: a `theme: Theme = .light` whose `Theme` is declared inside `Child` is the struct’s `theme: Child.Theme?`. Each public mock also declares an empty `public enum __safeDI_<Type>_mock_<hash>` naming its signature, which every generated call names, so a call generated from an out-of-date signature fails to compile at the call.

#### Calling a public mock from another module

Code in another module calls a public mock as any `public` method, under the declaring module’s `mockConditionalCompilation`, from a module that depends on the feature module. A module of another package reaches only the `public` tier, and under SwiftPM depends on the feature module through a library product of its package; under Bazel another package is a module with a different `package_name`, or none, and under Xcode and Tuist a target with a different `SWIFT_PACKAGE_NAME`, or none. For `FeedScreen`, which [Adopting SafeDI in a large codebase](#adopting-safedi-in-a-large-codebase) declares with a hole, `service: FeedService`, a test passes a stub:

```swift
// In a package that depends on Feed's library product.
import Feed

struct StubFeedService: FeedService {
    func refresh() async {}
}

#if DEBUG
func makeFeedScreen() -> FeedScreen {
    FeedScreen.mock(serviceBuilder: { _ in StubFeedService() })
}
#endif
```

A mock another module generates builds a type it cannot construct – one whose tree names a declaration that module cannot reach – by calling the type’s public mock at the narrowest tier the module can reach, passing what its own tree provides for that tier’s parameters, `nil` for the rest, and its overrides of the type as `safeDIOverrides`. A type it can construct is built inline. So a value the calling tree provides is shared with the public mock’s tree, as inline, and a dependency the called mocks build that the calling module can construct is built once by the calling mock – a lazily instantiated one as its wrapper – and passed to every call, each call an `Instantiator` makes included. Two kinds are not shared:

- A dependency the calling module cannot construct – one it cannot name, or whose tree reaches a construction it cannot – is built by each public mock that builds it, and is `nil` in one that receives it only if available. To share one of a `public` type, declare it with `generateMock: .public` too: the calling mock then builds it once, through its public mock, and passes it to every call that receives it.
- A lazily instantiated dependency the caller holds, or builds for the call, is created when the public mock is built, unlike one a seam’s generated initializer takes, which it defers.

Also:

- Where the tier the module reaches omits a parameter its tree provides, generation fails at the providing declaration, saying how to widen the parameter’s type. A public mock that calls another module’s takes what that call passes as `T? = nil` parameters of its own, so its callers can hand one instance down the chain.
- A calling module that sees a declaration fulfilling a hole passes a function building it from the struct’s values, as a seam’s caller fills a builder, when that is all the declaration’s tree reads and the module can build every type in it. The function builds the tree as the module’s own mock would inline, with hand-written mocks and a `mockOnly` fake that alone fulfills the hole; no override reaches it, but a call of another module’s public mock inside it is passed what the calling mock passes any call. Otherwise, or where building the fulfilling type inline would be a dependency cycle through what it receives, the calling mock takes the builder as a required parameter and passes it on, for the caller’s test to supply.
- Both modules generate their mocks under one `mockConditionalCompilation`, unless the declaring module’s mocks are unconditional. Under the Swift package plugin, a module that calls another module’s seam shares that module’s `mockConditionalCompilation` too.
- A module that reaches a type with a public mock cannot also hold a hand-written method named `mock` for it: name it apart, as [Hand-written mocks](#hand-written-mocks) describes.
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

SafeDI’s code generation runs `SafeDITool` in your build. Xcode projects and Swift packages run it through the `SafeDIGenerator` build tool plugin, which uses a prebuilt binary for fast builds without compiling SwiftSyntax. [Bazel](#bazel) and [Tuist](#tuist) projects run it once per module through SafeDI’s Bazel rule and Tuist plugin. Any other build runs `SafeDITool` itself, as [Custom build system integration](#custom-build-system-integration) describes.

SafeDI generates a root’s `init()`, the initializer of a type with `generateDependencyTree: true`, and the `mock()` of a type with `generateMock` only in the module that declares the type, so run SafeDI on each target that declares one of them. Under Bazel and Tuist, run it on every first-party Swift module, even one that declares no `@Instantiable` type, and list, for each module, the modules it depends on, as [Which modules to list](#which-modules-to-list) describes, or a `package` type of a module SafeDI does not read fails to compile at a generated initializer or mock ([Access of generated parameters](#access-of-generated-parameters)).

#### Xcode project

If your first-party code comprises a single module in an `.xcodeproj`, once your Xcode project depends on the SafeDI package you can integrate the Swift Package Plugin simply by going to your target’s `Build Phases`, expanding the `Run Build Tool Plug-ins` drop-down, and adding the `SafeDIGenerator` as a build tool plug-in. You can see this integration in practice in the [ExampleProjectIntegration](../Examples/ExampleProjectIntegration) project. A target that declares a type with `generateDependencyTree: true` needs the plugin only when hand-written code calls that type’s generated initializer (see [Limits of the Xcode project plugin](#limits-of-the-xcode-project-plugin)).

If your Xcode project comprises multiple modules, follow the above steps, and then add a `#SafeDIConfiguration` to a file named `SafeDIConfiguration.swift` in your module to configure SafeDI:

```swift
import SafeDI

#SafeDIConfiguration(
    additionalDirectoriesToInclude: ["Subproject"]
)
```

`additionalDirectoriesToInclude` names folders outside your module that SafeDI scans for Swift source files, relative to the executing directory (the directory containing the `.xcodeproj`). Xcode project plugins cannot discover dependent modules’ source directories, so list them here, as the [ExampleMultiProjectIntegration](../Examples/ExampleMultiProjectIntegration) project does in [its configuration](../Examples/ExampleMultiProjectIntegration/ExampleMultiProjectIntegration/SafeDIConfiguration.swift).

> **Note:** Any SafeDI declaration, roots included, may sit behind a bare condition such as `#if DEBUG`; see [Conditional compilation](#conditional-compilation).

##### Limits of the Xcode project plugin

To call a seam’s generated initializer or another module’s public mock, SafeDI must know which module declares each type. An Xcode project target knows which files it compiles but not which module declares the files it reads through `additionalDirectoriesToInclude`, and it reads no other target’s `.safedi` file, so SafeDI knows no module for the types it reads. The same holds, under any integration, for a file a `#SafeDIConfiguration` reads from `additionalDirectoriesToInclude`, and, under the Swift package plugin, for a file no target of the plugin’s graph lists. A seam declared in such a file is built inline by every tree that reaches it, and each production construction of it says so in a comment; a mock tree that reaches a type declared there builds it inline where it can, and otherwise generation fails. Where SafeDI knows no module for one side of a construction, and not both packages, it accepts a `package` declaration, and the compiler reports the construction if the two modules are in different packages; such a `package` or wider declaration also counts at its declared level for a generated parameter, whichever package it is in.

Under the Xcode project plugin:

- Every tree a target generates builds the types it reaches inline, a type declared with `generateDependencyTree: true` included: that type’s generated initializer is called only by hand-written code, and each production construction of the type ends in a comment saying that the tree cannot call it. Every type in the tree must be visible to the target that builds it – `package` across targets, with `SWIFT_PACKAGE_NAME` set on every target of the package. SafeDI reports each declaration the target cannot see at the declaration, with its fix-it, and one more error where the target refers to the seam, which says the tree is built inline and names the first such declaration.
- A seam’s tree may not instantiate a type that no `@Instantiable` declaration its target reads fulfills. The error at the property leads with declaring a type that fulfills the property in the target or in one it depends on, or declaring the seam without `generateDependencyTree: true`.
- A mock tree builds the type, another target’s `generateMock: .public` type included, inline where its tree is visible, and otherwise generation fails, saying to build the mocks in a Swift package target or to give the run module info that names the declaring module. The target’s tests and previews still call the `public` `mock()` the declaring target generates.
- A type of another target that the target reads no declaration of counts as `public` (see [Access of generated parameters](#access-of-generated-parameters)). Hand the target the declaring target’s directory with `additionalDirectoriesToInclude`, whose `package` declarations then count at their level, or declare the seam or mock `package`.
- The plugin cannot tell whether another target applies it, so a hand-written call of a generated initializer or of `mock()` fails with the compiler’s errors alone when the declaring target lacks the plugin.
- A target that reads, through `additionalDirectoriesToInclude`, a file that imports the target itself gets the compiler’s “ignoring import” warning in generated code.

A public mock’s hole builders work under the plugin, but per-module trees, builders in a seam’s generated initializer, and generated calls of public mocks need a build that names each module: the Swift package plugin, Bazel, or Tuist. A multi-module Xcode project gets them by moving its modules into a local Swift package that the app target depends on, declaring the root there, and calling the root’s `init()` from the app; the package then adopts SafeDI as [Adopting SafeDI in a large codebase](#adopting-safedi-in-a-large-codebase) describes.

##### Installing the prebuilt SafeDITool binary

If you see a build warning that starts with **"SafeDI is planning this target’s generated files with a simpler scanner..."**, install the prebuilt tool: in Xcode, right-click your project in the navigator, choose **SafeDI → Safedi Release Install**, and approve the network-access and write-to-package-directory prompts. The command downloads the prebuilt SafeDITool release binary for your SafeDI version into `.safedi/<version>/safeditool` next to your `.xcodeproj`, and the build plugin picks it up on later builds.

Without the installed tool, the plugin plans the build with a regex-based scanner; `swift build` gets the prebuilt binary through the default `prebuilt` trait already. Run the command once per project, and again after a SafeDI version bump if the warning reappears.

The command writes `.safedi/.gitignore` on first run, with the single glob `*/safeditool`. **Commit `.safedi/.gitignore`.** The binary it ignores is specific to the host (arm64 or x86_64) and the SafeDI version, so each developer re-runs the command once after cloning.

#### Swift package

If your first-party code is entirely contained in a Swift Package with one or more modules, add the following lines to each target that [Generating your dependency tree](#generating-your-dependency-tree) names:

```swift
    plugins: [
        .plugin(name: "SafeDIGenerator", package: "SafeDI")
    ]
```

To generate mocks in other modules, see [Cross-module mock generation](#cross-module-mock-generation).

A target that declares a type with `generateDependencyTree: true` or `generateMock: .public` needs the plugin even when it declares no root. Without it, every call of that type’s generated initializer or public mock fails to compile in the calling target with `type 'FeedScreen' has no member '__safeDI_FeedScreen_…'`, followed by errors about the call’s arguments; the comment SafeDI writes on the first error’s line names the target to add the plugin to.

You can see this integration in practice in the [Example Package Integration](../Examples/Example%20Package%20Integration) package.

Unlike the Xcode project plugin, the Swift package plugin finds the source files of dependent modules itself: it reads the modules of your package and of the packages it depends on by path, not those of a package it fetches from a URL. A tree that instantiates an `@Instantiable` type a fetched package declares fails as unfulfilled unless a `#SafeDIConfiguration` adds the checkout’s directory to `additionalDirectoriesToInclude`, which makes it a type of no module, with the limits [Limits of the Xcode project plugin](#limits-of-the-xcode-project-plugin) lists; a test that calls such a type’s `mock()` by hand still works. If SafeDI’s generated code is missing required imports, list the modules in [`additionalImportedModules`](#safediconfiguration).

> **Note:** On Swift 6.4 or later, `swift build` can fail for a target with a couple thousand or more input files with `sandbox-exec: data object length … exceeds maximum (65535)`. Xcode is not affected. Build with `swift build --build-system native`, or with `swift build --disable-sandbox`, which turns off sandboxing for every plugin and package manifest in the build.

#### Bazel

Add `bazel_dep(name = "safedi", version = "2.2.0")` to your `MODULE.bazel`, then declare each SafeDI module with `safedi_swift_library` in place of `swift_library`:

```python
load("@safedi//bazel:safedi.bzl", "safedi_swift_library")

safedi_swift_library(
    name = "App",
    srcs = glob(["**/*.swift"]),
    defines = ["STAGING"],
    safedi_deps = ["//Subproject:Subproject_safedi"],
    deps = [
        "//Subproject",
        "@safedi//Sources/SafeDI",
    ],
)
```

The macro accepts every `swift_library` attribute and declares two targets: the `swift_library` named `App`, and `App_safedi`, which runs `SafeDITool` over the same `srcs` with the same `defines` and `copts`. Both targets take the macro’s `visibility`, so a module that can list `App` in its `deps` can list `App_safedi` in its `safedi_deps`. To use the `@Instantiable` types another module declares, list its `<name>_safedi` target in `safedi_deps` and the module itself in `deps`, for each module [Which modules to list](#which-modules-to-list) names. Declare every first-party module with `safedi_swift_library`, as [Generating your dependency tree](#generating-your-dependency-tree) says. You can see this integration in practice in the [ExampleBazelIntegration](../Examples/ExampleBazelIntegration) module.

A change in a module reruns the SafeDI action of each module that lists it, and, when it changes a declaration in a module that declares a seam or public mock, or in a module such a module lists, the actions of the modules above them too. For `package` access, give the modules of one package the same `package_name`: a module with a different `package_name` is in another package, and a module without one has no package.

A module that needs a shape the macro does not offer can declare the `safedi_compile` rule, which `load("@safedi//bazel:safedi.bzl", "safedi_compile")` loads, and its `swift_library` separately. The rule takes `srcs` (the library’s), `deps` (the `<name>_safedi` targets `safedi_swift_library` calls `safedi_deps`), `module_name`, `package_name`, `defines` and `copts` (the library’s), and `visibility` (set it as on the library, since the modules that list the rule must see it); add `[":<rule name>"]` to the library’s `srcs`. `module_name` is required: the library’s `module_name` attribute, or the name `derive_swift_module_name` from `@rules_swift//swift:module_name.bzl` gives the library’s label; see [`bazel/safedi.bzl`](../bazel/safedi.bzl). When a library is compiled without the rule’s output in its `srcs`, every call of its seams and public mocks fails to compile with `type 'Screen' has no member '__safeDI_Screen_…'` (or `has no member 'mock'`).

`SafeDITool` runs as the prebuilt binary the SafeDI release publishes for the machine that runs the build – macOS arm64 or x86_64, or Linux x86_64 or arm64 – the same binary the `SafeDIGenerator` plugin and the Tuist plugin run. Bazel downloads it from the release’s GitHub assets the first time a build needs it, so that build needs network access to GitHub or a [repository cache](https://bazel.build/run/build#repository-cache) that holds the binary, and checks it against the sha256 recorded in the release’s source archive. On any other machine, Bazel builds `SafeDITool` from source. To always build it from source, add this line to your `.bazelrc`:

```
common --@safedi//bazel:prefer_prebuilt_safeditool=false
```

A build that takes SafeDI from a checkout of its repository rather than from a release – through `local_path_override`, `git_override`, or an `archive_override` of a GitHub archive – always builds `SafeDITool` from that checkout.

##### Which modules to list

Under Bazel, Tuist and a [custom build](#custom-build-system-integration), each module’s `SafeDITool` run reads the module’s own sources and the `.safedi` files of the modules it lists – its `safedi_deps` under Bazel, the `dependencies` of its `SafeDI.preCompileScript` under Tuist, the `--dependent-module-info-file-path` file in a custom build – and builds a type only when one of those declares it. So a module lists each module whose types it uses, including the types the code SafeDI generates for its roots and mocks builds, which the module’s own source may never name:

- A module that declares a root lists every module beneath it, since the root’s tree can build a type any of them declares. The module depends on all of them and is rebuilt whenever one of them changes, so listing them costs nothing.
- A module whose generated mocks build a type a deeper module declares lists that module. A mock builds a seam’s tree inline, and a public mock’s tree where it can construct the type, so the types those trees build count.
- A module is never listed only so that SafeDI can compute the initializer another module generates for a [seam](#generating-a-dependency-tree-per-module), or another module’s [public mock](#public-mocks): each module’s `.safedi` carries what those need of the modules beneath it.

Neither the compiler nor Bazel asks for these entries, so only SafeDI notices a missing one:

- When a root’s tree reaches a type declared in a module this module does not list, generation fails at the property that instantiates it. When a listed module’s `.safedi` carries the declaring module’s declarations – it declares a seam or public mock, or is listed by a module that does – the error names the module to list and the listed module this one reaches it through. Otherwise it reports that no `@Instantiable` declaration fulfills the type, and says how to make the declaring module one SafeDI reads.
- When a generated mock’s tree reaches such a type, `mock()` takes it as a required parameter, as [Dependency kinds in the generated mock](#dependency-kinds-in-the-generated-mock) describes, and SafeDI reports nothing.

A module that uses types another module re-exports with `@_exported import` lists the module that declares them too: SafeDI does not follow the re-export. The [Swift package](#swift-package) plugin needs no list: it reads the modules the target depends on itself.

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

In `Project.swift`, `import SafeDITuist`, and give each target that declares SafeDI types the generated source, the script, and a dependency on SafeDI:

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

`module` names the directory, under the one that holds `Project.swift`, whose Swift files the script passes to `SafeDITool`; the target’s `.safedi` file is named after its module (`PRODUCT_MODULE_NAME`), so two projects may name their sources directories alike. `dependencies` lists the module name of each target this target depends on, as [Which modules to list](#which-modules-to-list) describes; the script reads each one’s `.safedi` file, so each must run the script too and be a dependency of this target, so that it writes its `.safedi` file first. Give every first-party target the script, as [Generating your dependency tree](#generating-your-dependency-tree) says.

The script reruns when one of the target’s Swift files or one of those `.safedi` files changes, and `SafeDITool` writes a `.safedi` or `SafeDIGenerated.swift` only when its bytes change. So a change in a module reruns the scripts of the modules that list it – and, when it changes a declaration in a module that declares a seam or public mock, or in a module such a module lists, the scripts of the modules above them – and recompiles only the modules whose generated code changed. After renaming a module, delete its old `.safedi` from `$BUILT_PRODUCTS_DIR/SafeDI` or clean the build folder: a target that still lists the old name reads the old file.

The script runs the `SafeDITool` that `tuist install` unpacks into `Tuist/.build` beside the workspace’s `Tuist/Package.swift`, which it looks for from the directory that holds `Project.swift` upward, so a project in a subdirectory of the workspace, such as `Projects/Feature/Project.swift`, finds it too. The script passes the target’s `SWIFT_ACTIVE_COMPILATION_CONDITIONS` and `OTHER_SWIFT_FLAGS` (see [Reporting active conditions](#reporting-active-conditions)), its module name, and its `SWIFT_PACKAGE_NAME` when it sets one.

The script writes the generated code to `SafeDIGenerated.swift`, whose path never changes, so a change to your SafeDI declarations needs a build, not `tuist generate`. A new Swift file does need `tuist generate`, which lists it among the script’s inputs: a target with buildable folders compiles the file without it, but the script reads the file only when it next runs for another change. Keep the plugin’s commit and the package’s version in step, and run `tuist install` and `tuist generate` after changing them. You can see this integration in practice in the [ExampleTuistIntegration](../Examples/ExampleTuistIntegration) project.

For `package` access, set `SWIFT_PACKAGE_NAME` to one name in every project whose targets use one another’s `package` declarations, for example in each `Project.swift`: `settings: .settings(base: ["SWIFT_PACKAGE_NAME": "MyApp"])`.

#### Custom build system integration

A build that neither the `SafeDIGenerator` plugin, the Bazel rule, nor the Tuist plugin covers – Buck, or a prebuild script – runs `SafeDITool` itself, from the prebuilt, codesigned `SafeDITool.artifactbundle.zip` on our [Releases](https://github.com/dfed/SafeDI/releases) page. Two working references, each running `generate --combined-output --module-info-output` per module and passing the `.safedi` files of the modules it lists through `--dependent-module-info-file-path`, drive the tool. They are the Tuist plugin’s embedded shell in [`TuistPlugins/SafeDITuist/ProjectDescriptionHelpers/SafeDI.swift`](../TuistPlugins/SafeDITuist/ProjectDescriptionHelpers/SafeDI.swift), which locates the binary via SPM (for a non-SPM build system, swap that lookup for a `curl` of the artifact bundle), and the Bazel rule and macro at [`bazel/safedi.bzl`](../bazel/safedi.bzl).

An Xcode script phase that runs `SafeDITool` can keep `ENABLE_USER_SCRIPT_SANDBOXING` on when it declares the Swift files it passes `SafeDITool` and the `.safedi` files it reads as input files, and each file it writes in those directories as an output file. The sandbox denies the script any other file under the project’s directory, the build’s products, and the target’s derived sources; scratch files in `$TARGET_TEMP_DIR` or the system’s temporary directory need no declaration. Otherwise, set `ENABLE_USER_SCRIPT_SANDBOXING` to `NO` for the target. The Tuist plugin’s script runs only with the setting off, as Tuist leaves it unless a project turns it on.

`SafeDITool` has two subcommands for a build:

- **`generate`**, the default subcommand, parses Swift source files, builds and validates the dependency graph, and generates the code of each root, of each type with `generateDependencyTree: true` the module declares, and of each mock. It writes it one of three ways:
  - `--combined-output <file>`: everything in one statically known file, for a build system that declares rule outputs up front. It cannot be combined with the other two.
  - `--output-directory <existing directory>`: one file per source file, as the `SafeDIGenerator` plugin writes them, named as [Finding the generated code](#finding-the-generated-code) describes; `generate` runs `scan` itself and writes its manifest and cache there. Pass `--mock-scoped-files` the module’s own files when the input CSV lists others.
  - `--swift-manifest <manifest>`: the outputs a manifest you had `scan` write lists. A manifest written by hand in the [`SafeDIToolManifest`](../Sources/SafeDICore/Models/SafeDIToolManifest.swift) format is deprecated: `generate` warns when a manifest lacks fields `scan` always writes, SafeDI 3.0 rejects such a manifest, and SafeDITool rejects one in which two outputs name one file.

  `generate` writes every output it plans, without code when its input declares no such type under the active compilation conditions.
- **`scan`** produces a manifest JSON describing the `@Instantiable` types it finds, which the `SafeDIGenerator` plugin uses to coordinate builds across modules.

`generate --additional-imported-modules` is deprecated, warns, and is removed in SafeDI 3.0: list those modules in the module’s [`#SafeDIConfiguration`](#safediconfiguration) `additionalImportedModules`, which imports them whichever build runs SafeDI. Pass the target’s active compilation conditions to `generate --active-compilation-conditions`, or its `SWIFT_ACTIVE_COMPILATION_CONDITIONS` and `OTHER_SWIFT_FLAGS` build settings to `--build-setting-active-compilation-conditions` and `--build-setting-other-swift-flags`, so SafeDITool scans the `#if` clauses the compiler compiles ([Conditional compilation](#conditional-compilation)).

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

A run per module also names the module it runs for, so that `SafeDITool` knows which module and package declare each type it reads, which decides the access its generated code needs ([Access levels](#access-levels)):

- `--module-name` names the Swift module that compiles the files the input CSV and `--include` name, such as an Xcode target’s `PRODUCT_MODULE_NAME`. Generated code never imports the module it is compiled into.
- `--package-name` names that module’s package exactly as the compiler’s `-package-name` names it, such as an Xcode target’s `SWIFT_PACKAGE_NAME`. Omit it when the compiler receives no `-package-name`: a module given `--module-name` and no `--package-name` has no package.

`--module-info-output` requires `--module-name`. The `.safedi` file records the module, its package, and as its dependencies the modules the given `.safedi` files record. It also carries, without line numbers, what a module needs to compute another module’s seam initializer or public mock, so a module is never given a `.safedi` only for that; a note SafeDI attaches at a declaration it reads only this way, such as the receive a seam would pass `nil` to, names no line until you list the declaring module’s `.safedi` too.

Two module infos that describe one module differently, such as a stale file beside a current one, are an error naming both. When no declaration SafeDI read fulfills a type that a property in a file of this module instantiates, the error names the modules that file imports whose `.safedi` the run was not given, any of which may declare the type, and says how to give the run one. Under the `SafeDIGenerator` plugin it names those that are not targets the target depends on, and it names a system framework as it names a first-party module. For a property in another module’s file, it lists every remedy.

Given the same input files, `generate` writes the same `.safedi` bytes, writes the file only when the run succeeds, and writes a `.safedi` or combined output only when its bytes change. [`query needs`](#querying-what-a-type-needs) can read the files in place of the sources. A `.safedi` file names each file by the path the input CSV gives it, so a CSV of relative paths, like those the Bazel rule and the Tuist plugin write, keeps absolute paths out of it. The file is binary, and `SafeDITool` reads only those a `SafeDITool` laying them out the same way wrote: after upgrading SafeDI, regenerate each producer’s `.safedi` before its consumers run, or a consumer fails with an error that names the file.

Generated code points a renamed dependency’s assignment at its `@Received` declaration with a `#sourceLocation` directive only when SafeDITool knows the exact path the compiler is handed for each file: under the `SafeDIGenerator` plugin, or with `generate --compiler-receives-input-paths-unchanged`. A build system that hands the compiler every Swift file at exactly the path it hands SafeDITool may pass that flag, as the Bazel rule does. Otherwise each such assignment ends in a comment naming the declaration’s file and line. With that flag and no plugin manifest, SafeDITool also prints each error and warning at the path it was handed, as the compiler does: under Bazel, relative to the execution root.

[Running SafeDITool yourself](#running-safeditool-yourself) says how to print each subcommand's help.

### Running SafeDITool yourself

Your integration already has a `SafeDITool`; a [custom build system](#custom-build-system-integration) runs the one it downloads. Run it with `--help`, `scan --help`, or `generate --help` to see documentation of all supported arguments, `query needs --help` for the command that [reports what types need](#querying-what-a-type-needs) (in beta), and `dump --help` for the command that prints a `.safedi` file, or the cache `scan` writes beside its manifest, as JSON. Each integration’s `SafeDITool` is here:

- **Swift package:** `.build/artifacts/safedi/SafeDIToolBinary/SafeDITool.artifactbundle/SafeDITool-macos-arm64/bin/SafeDITool` from the package’s directory, or `swift run SafeDITool` with the `sourceBuild` trait; writes no `.safedi` files.
- **Xcode project:** `SourcePackages/artifacts/safedi/SafeDIToolBinary/…` in the project’s derived data, or `.safedi/<version>/safeditool` once [installed](#installing-the-prebuilt-safeditool-binary); writes no `.safedi` files.
- **Bazel:** `bazel run @safedi//bazel:safeditool -- <arguments>` runs the `SafeDITool` your build runs, prebuilt or built from source, in the directory you run it from, so relative paths among the arguments work; writes `bazel-bin/<package>/<name>_safedi.safedi`, though when the action’s result comes from a cache, such as `--disk_cache`, only for a build passed `--remote_download_regex='.*\.safedi$'`.
- **Tuist:** `Tuist/.build/artifacts/safedi/SafeDIToolBinary/SafeDITool.artifactbundle/SafeDITool-macos-arm64/bin/SafeDITool` from the directory that holds `Tuist/Package.swift`; writes `$BUILT_PRODUCTS_DIR/SafeDI/<PRODUCT_MODULE_NAME>.safedi`.

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
- A bare condition such as `DEBUG` or `STAGING` is active when the reported conditions include it and inactive otherwise. SafeDITool scans the clause the conditions select and ignores the others, so a type declared under `#if DEBUG` and a different type declared under `#else` can both fulfill the same protocol:

```swift
#if DEBUG
@Instantiable(fulfillingAdditionalTypes: [EventLogger.self])
public final class ConsoleEventLogger: EventLogger, Instantiable { … }
#else
@Instantiable(fulfillingAdditionalTypes: [EventLogger.self])
public final class DisabledEventLogger: EventLogger, Instantiable { … }
#endif
```

- Platform conditions such as `os(iOS)`, `arch(arm64)`, `canImport(UIKit)`, `targetEnvironment(simulator)`, `swift(>=6.0)`, and `compiler(>=6.0)` are left to the compiler. SafeDITool scans every clause one of them could select, so declarations under `#if os(iOS)` and under its `#else` are both visible to code generation. Declare a dependency once, outside such a block: SafeDITool reports a dependency declared in each clause of a type that generated code builds as declared more than once. Likewise declare an `@Instantiable` type, or a type that fulfills one, once outside such a block, with the platform difference inside its body or its `instantiate(…)` method: SafeDITool reports a type declared in each clause as fulfilled more than once, and, when every duplicate is inside such a block, gives this remedy beside the one for a plain duplicate.

The reported conditions are taken as complete, so a condition your build defines but your integration does not report would make SafeDITool scan the wrong clause. To keep that from going unnoticed, every generated file begins by asserting each decision SafeDITool made about a block that can change what it generates: one that declares an `@Instantiable` type, a dependency, an `instantiate()` method, an initializer SafeDI could select to construct its type, or a `#SafeDIConfiguration`, or a type whose access a generated initializer or mock relies on. Such a type is one a declaration SafeDI reads names, or that is or encloses the type an `@Instantiable` extension extends, and that the module can name, or, under Bazel and Tuist, one declared `package`. An assertion reads:

```swift
#if !(DEBUG)
#error("SafeDI scanned this module assuming `#if DEBUG` was active, but it is inactive in this compilation. Report the conditions this target compiles with to SafeDITool, as the \"Reporting active conditions\" section of the SafeDI manual describes for your build system.")
#endif
```

A mismatch therefore fails the build at the generated file, with a message naming the condition. A `#if DEBUG struct PreviewData` that no declaration SafeDI reads names asserts nothing.

A guarded initializer SafeDI would never select for construction, such as a preview helper that does not take the type’s dependencies, is not asserted, so this works under every integration:

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

Initializers in an `@Instantiable` extension are never asserted, because the extension’s `instantiate()` method constructs the type.

### Declarations that only feed mock generation

A declaration that participates only in mock generation—an `@Instantiable(mockOnly: true)` type or extension, or a hand-written `mock()` or `customMockName` method—may be guarded by the module’s `mockConditionalCompilation` condition (`DEBUG` by default) without the build reporting it. SafeDITool evaluates such a block as if that condition were active, because the generated mock code that references the declaration is wrapped in the same `#if`, and asserts nothing about it. So `#if DEBUG` around a `mockOnly` declaration works under every integration, including a Swift package built with SwiftPM’s native build system ([Reporting active conditions](#reporting-active-conditions)). Setting `mockConditionalCompilation: nil` disables this exemption, since the generated mocks are then unconditional. The exemption never applies to production declarations, nor to other conditions guarding mock-only declarations.

Production code, such as a seam’s generated initializer, can name a plain type declared in such a block, and compiles where the mock condition is inactive too. So for plain types SafeDITool reads the mock condition as it reads a platform condition: it reads the clauses the block selects with the condition active and with it inactive, and a type counts at the narrowest level any of them declares it at, so the generated code is the same, and compiles, in debug and release builds:

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

A seam that receives `@Received(onlyIfAvailable: true) let endpoint: Endpoint?` takes it on its `package` tier, one that requires `endpoint: Endpoint` reports the error any `package` type does, and a public mock’s signature reads `Endpoint` the same way, although the mock compiles only where the condition is active. A type that a block declares only where the condition is active counts as declared, so declare it for builds where the condition is inactive too, such as in another file under `#if !DEBUG`, or the code that names it does not compile there. That `#if !DEBUG` is an ordinary block, which SafeDITool evaluates with the reported conditions and asserts, so under SwiftPM’s native build system add `.define("DEBUG", .when(configuration: .debug))` to the target’s `swiftSettings`, or debug builds fail at SafeDI’s assertion.

Imports follow the code that needs them. An `#if` block that holds only imports is evaluated twice: with the reported conditions for the generated dependency tree, and as if the mock condition were active for the generated mocks, which compile only where it is. A module that a mock-only declaration needs can therefore be imported under its own `#if DEBUG`:

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

The generated mocks import `NetworkingMocks` whatever conditions the build reports, as do the mocks of a module that depends on this one, while the generated dependency tree imports it only when the build reports `DEBUG`. A file that holds both, such as the output of `generate --combined-output`, imports what either needs.

### Reporting active conditions

SafeDITool can read the conditions in two ways:

- **From the build settings, when the build runs.** The `SafeDIGenerator` plugin and the Tuist plugin pass `${SWIFT_ACTIVE_COMPILATION_CONDITIONS}` and `${OTHER_SWIFT_FLAGS}` to SafeDITool. A build system that expands them hands SafeDITool exactly the conditions the compiler receives, and SafeDITool uses those instead of any reported another way.
- **From what the plugin can see, while it plans the build.** A Swift package’s build tool plugin can read the target’s `swiftSettings` defines, including those with `.when(configuration:)` conditions, and its trait defines, but not SwiftPM’s implicit `DEBUG`. An Xcode project’s build tool plugin can read no conditions at all. When the build-setting references the plugin passes reach SafeDITool unexpanded, it uses these conditions instead.

| Integration | Conditions SafeDITool generates code with |
|-------------|-------------------------------------------|
| Swift package plugin, `swift build` with the Swift Build backend: the default in Swift 6.4, and `--build-system swiftbuild` in Swift 6.2 | The build settings. Verified with Swift 6.2 and Swift 6.4. |
| Swift package plugin, `swift build` with the native backend: the default in Swift 6.2, which ships with Xcode 26, and `--build-system native` in Swift 6.4. `swift build --help` names your toolchain’s default. | What the plugin can see. To guard a production declaration with `DEBUG`, add `.define("DEBUG", .when(configuration: .debug))` to the target’s `swiftSettings`, as the [Example Package Integration](../Examples/Example%20Package%20Integration/Package.swift) does. The define is harmless under the other build systems, which read the build settings instead. |
| Swift package plugin, built by Xcode | The build settings, in every configuration. Xcode hands the plugin a package’s `.when(configuration:)` defines as for a debug build whatever configuration it compiles, so the build settings correct what the plugin sees in Release. |
| Xcode project plugin | The build settings. |
| Tuist plugin | The build settings, as for the Xcode project plugin: the script’s shell expands them. |
| Other prebuild scripts | What the script passes: the build settings through the `--build-setting-…` options, as the Tuist plugin does, or the conditions it lists in `generate --active-compilation-conditions`. |
| Bazel `safedi_swift_library` and `safedi_compile` | `DEBUG` in the `dbg` and `fastbuild` compilation modes, `NDEBUG` in the `opt` compilation mode, the target’s `defines`, each `-D` flag in the target’s `copts` (after Make variable expansion, so `-D$(NAME)` reports the value of `--define=NAME=…`), and each `-D` flag passed with `--@rules_swift//swift:copt` (`--@rules_swift//swift:exec_copt` for a target built in the exec configuration). `safedi_swift_library` gives its `swift_library` and its `<name>_safedi` target the same `defines` and `copts`; a hand-written `safedi_compile` must repeat the `defines` and `copts` of the `swift_library` that compiles its output. Not reported: `defines` propagated from a dependency, `--@rules_swift//swift:per_module_swiftcopt`, and copts configured on a custom Swift toolchain. `--copt` and `--define` alone do not reach the Swift compiler, so they never need reporting. |

The Swift package plugin scans the sources of a target’s dependencies with the target’s own conditions, and the target’s generated files assert the decisions SafeDITool made about the dependency’s blocks, as the dependency’s own generated files do. So a condition that guards a production declaration in a dependency, or declares a type a seam or public mock names, must be active on every target whose dependency tree reaches it, or that calls a seam of that module or of a module depending on it. A target that calls another module’s seam also shares its `mockConditionalCompilation`, as [Calling a public mock from another module](#calling-a-public-mock-from-another-module) describes.

#### Declarations that decide which files SafeDI generates

Roots, types that set `generateDependencyTree: true` (in the module that declares them) or `generateMock: true` or that `additionalMocksToGenerate` lists, and `#SafeDIConfiguration` may sit behind any condition, in every integration: SafeDI plans a generated file for each of them in every clause of every `#if` block, and writes the file with only its compile-time assertions when the build leaves the declaration inactive:

```swift
#if DEBUG
@Instantiable(isRoot: true)
public struct DebugMenu: Instantiable { … }
#endif
```

## Reference

The rules in this section are the detail behind the sections above, which point here where they apply.

### Access of generated parameters

Each parameter of a [seam’s](#generating-a-dependency-tree-per-module) generated initializer or of a [public mock](#public-mocks) is as visible as the narrowest type it names, as far as SafeDI can prove from the declarations it reads. Those are a type’s own declaration (`@Instantiable` or not, `protocol` and `typealias` included) in the seam’s module, or a `package` or wider one in another module SafeDI reads, as a `.safedi` file records it. A type declared inside an extension counts at its own access level, capped by the extended type’s. Of two modules’ types of one name, SafeDI takes the narrower, unless the mention is spelled with its module (`Core.Theme`).

A type SafeDI reads no declaration of counts as `public`: a system framework’s, a package’s fetched from a URL, a binary target’s, or, under Bazel or Tuist, a first-party module’s that does not run SafeDI. This is exact except for a first-party module of the same package that does not run SafeDI: its `package` type fails to compile at the generated `public` initializer or mock, whose comment names the types counted `public`. Run SafeDI on every first-party module, as [Generating your dependency tree](#generating-your-dependency-tree) says.

In an `#if` block, a type counts at the level the clause the reported conditions select gives it, or, under a platform condition, at the narrowest level among the clauses that condition could select ([Conditional compilation](#conditional-compilation)). A type declared only in clauses the reported conditions skip counts as no declaration SafeDI reads.

A type whose spelling SafeDI cannot read counts as `internal`, unless an initializer, `instantiate(…)` method or mock method in the seam’s module, or on a type that receives the parameter, takes it as a dependency at a wider level; a mention elsewhere does not count. The type of an `@Instantiable` extension, `mockOnly` or not, counts as its declaration does. A nested type an `@Instantiable` extension declares, and SafeDI reads no declaration of, counts at the level the extension spells, capped by the type directly enclosing it, or as `internal` when the extension spells none, raised by any initializer, `instantiate(…)` method or mock method SafeDI records that takes it as a dependency at a wider level. The spelled level counts only where SafeDI reads that enclosing type’s declaration.

Where the parameters differ in access, SafeDI generates one declaration for each level, a tier: the narrowest tier builds the tree, and each wider tier takes the parameters code at its level can name and calls the next narrower tier, passing `nil` for the rest. A seam’s own initializer and the types its tree builds keep their access; only the types a tier’s parameters name, and the fields of a builder’s struct that the filling module reads, must be as visible as the tier. A seam reached through another seam passes the inner seam’s parameters on, each as visible as its types prove in the outer seam’s module; a parameter the outer seam’s module cannot pass on is taken by none of its initializers, and a caller holding a value for it is told so.

The compiler reports, in the generated file, a tier made wider than it accepts by:

- An access-level import, a system framework’s included, or an `@_spi` type, which read as `public`.
- A type SafeDI is handed no declaration of: one a macro generates, or one in a file the build does not list for SafeDI.
- A type a module declares in some clauses of a platform-conditioned block and another module declares narrower, which is taken as the module’s own; the compiler reports it where it selects a clause without it.
- A type whose name follows a comment after its keyword, in a file that mentions neither `@Instantiable` nor `#SafeDIConfiguration`: SafeDI reads such a file only when a text search finds a type’s keyword followed by a name it looks for, or, under Bazel and Tuist, the word `package`.

The construction check in [Access levels](#access-levels) reads these declarations too. For a type an extension declares, inside it or as an `@Instantiable` extension’s type, `SafeDITool` checks the extended type’s declaration in the extension’s module, a plain `enum`, `struct`, `class` or `actor` used as a namespace included, and reports one narrower than the constructing module can see at its declaration. It checks a namespace declared inside an extension too, and each type such an extension extends in turn, a `typealias` included, while it is declared in the extension’s module, but not one declared in another module. The compiler reports what SafeDI does not check.

### Where a seam differs from building its tree inline

The generated initializer passes each dependency to its receivers by label, as a root’s `init()` does, without knowing what its callers pass, so SafeDI reports an error at the seam, saying what to change, where one parameter per label cannot reproduce what the tree reads or the initializer cannot be declared:

- One label received in forms no single parameter provides: a by-value receive beside an optional wrapper receive, two wrapper kinds, or the seam’s own receive beside a form it does not provide. As inline, a required non-optional `LazilyInstantiated` or `SendableLazilyInstantiated` provides the by-value forms and the optional form of its kind, and a by-value property its optional form.
- A receive whose label a type between the seam and the receiver, the seam included, declares with a property that does not provide it: the hidden-label error the tree gets inline once a caller provides the property.
- An initializer in the seam’s body that a call with a generated initializer’s argument labels can reach – its labels hold those in order, and every other argument has a default value.
- A `@Sendable` builder function inside the seam that reads a parameter of a non-`Sendable` wrapper type (`Instantiator`, `ErasedInstantiator`, or `LazilyInstantiated`), even where inline would pass `nil`, since the parameter is declared outside every builder function: receive the label inside the seam as the `Sendable` wrapper of that kind, and declare it so where the caller declares it. A parameter taken as an `@autoclosure` that such a function reads is a `@Sendable` closure held in a `SendableLazilyInstantiated`, which needs the deployment targets [Sendable wrappers](#sendable-wrappers) states, and a caller that would hand it the instance of a wrapper that is not `Sendable` is an error, as the capture is inline.

A rename declared `onlyIfAvailable` inside the seam, of one of its parameters, is bound from that parameter and is `nil` where the caller passes `nil`, so every type beneath reads the value it reads inline. When a type in the seam’s tree requires such a rename, the caller builds its dependency before the seam, as inline builds it before that type’s branch.

For a seam built again inside the tree that fills it, or inside its own tree:

- A hole’s implementation that reads a value the seam takes as an `@autoclosure`, where the implementation’s own tree builds the seam again beneath another declaration of the value’s label, reads the struct’s property when the implementation is built. Inline, its receiver reads the value when that receiver is built.
- A seam whose tree instantiates the seam again, directly or through another seam of its module, hands the builders it took on to that call; a value the implementation reads that such a path binds is an error, as for a builder passed up.

### Generated imports

The files SafeDI generates import the modules that your files declaring `@Instantiable` types or a `#SafeDIConfiguration` import, with no access level unless one of your module’s files gives an import one (`internal import Foundation`). Then every generated file gives each of its imports the level its own declarations need, and compiles with or without the `InternalImportsByDefault` upcoming feature:

- `public` when a `public` declaration of the file, such as a seam’s initializer or a public mock, names one of the module’s types, or when the import is `@_exported`;
- `package` when a `package` declaration names one – but where your files import that module at no level below `public`, only under `InternalImportsByDefault`, and with no level otherwise;
- `internal` when one of your module’s files imports that module below `public`;
- no level otherwise.

Generated mocks, and the configurations of public mocks, compile only under the module’s [`mockConditionalCompilation`](#safediconfiguration), so a level only they need is spelled under that condition, beside the level the rest of the file needs, and a build without the condition, such as a Release build, draws no unused-import warning:

```swift
#if canImport(Foundation)
#if DEBUG
public import Foundation
#else
internal import Foundation
#endif
#endif
```

SafeDI attributes a type to the module whose declaration of it it reads, and its own types to SafeDI. A type it reads no declaration of is attributed to Foundation when it is one of Foundation’s common types, and to every module your files import at the level of the declaration that names it or wider. A type a dependency’s `@Instantiable` declaration names, in a dependency or an initializer parameter, is attributed to every module that declaration’s file imports `package` or wider, Foundation’s common types aside. An import there that spells no level tells SafeDI nothing: spell it at the level of the declaration that names the type.

A file whose `public` declaration names a type SafeDI reads no declaration of therefore imports each module it attributes the type to `public`, and the compiler warns at one whose types it does not name: import that module below `public` in your files that declare SafeDI content if none of their `public` declarations needs it.

## Comparing SafeDI and Manual Injection: Key Differences

SafeDI is designed to be simple to adopt and minimize architectural changes required to get the benefits of a compile-time safe DI system. Despite this design goal, there are a few key differences between projects that utilize SafeDI and projects that don’t. As the benefits of this system are outlined in the README’s [Features](../README.md#features) section, this section outlines the pattern changes required to utilize a DI system like SafeDI.

### Instantiating objects

In a manual DI system it is common to directly call your dependencies’ `init(…)` functions. With SafeDI, `@Instantiated` properties instantiate your dependencies for you: calling a dependency’s `init(…)` directly exits the SafeDI-built dependency tree, which removes property lifecycle guarantees. Likewise, create the tree with the root’s generated `init()`, not its memberwise `init(…)`, as [Creating the root of your dependency tree](#creating-the-root-of-your-dependency-tree) describes, and instantiate a dependency later with an [`Instantiator`](#delayed-instantiation) or [`LazilyInstantiated`](#lazilyinstantiated).

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

- **Types keep their access levels.** A type and its initializer need be visible only to the module that constructs them: `package` when another module of their package does, `internal` when only their own module does. When generated code cannot reach a declaration, the build names it, with a fix-it. See [Access levels](#access-levels).
- **Each module can generate its own tree.** Decorate the type at a module’s boundary – a feature’s entry point, or the top of a package – with `generateDependencyTree: true`: a change inside the module then recompiles only the module and the calls into it, and in production the types built inside need be visible only there. See [Generating a dependency tree per module](#generating-a-dependency-tree-per-module).
- **Implementations can live above the feature.** When a module’s tree instantiates a protocol whose implementation only the app can see, the module’s generated initializer takes a builder for it, which the app’s generated code fills. See the builder example in [Generating a dependency tree per module](#generating-a-dependency-tree-per-module).
- **Mocks cross modules.** Declare the seam with `generateMock: .public`, and a mock in another module that cannot build its tree calls the `public` `mock()` its own module generates, which tests and previews in other packages can call too, without seeing the types it builds. See [Public mocks](#public-mocks).

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

No `@Instantiable` declaration `Feed` sees fulfills `FeedService`, so the initializer `Feed` generates for `FeedScreen` takes `session` and a builder for `service`. The app declares the implementation, and the code it generates for a tree that reaches `FeedScreen` fills the builder with it, built from the `session` the builder is handed:

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

A seam needs no root above it, so it can also mark how far adoption has reached: code that does not use SafeDI yet calls the seam’s generated initializer by hand, and an app target can call a seam whose `@Forwarded` properties carry the target’s configuration instead of declaring a root of its own. [Generating a dependency tree per module](#generating-a-dependency-tree-per-module) says what the compiler checks in a hand-written call.

Seams and public mocks need a build that knows which module declares each type: run SafeDI on the targets [Generating your dependency tree](#generating-your-dependency-tree) names, which under Bazel and Tuist is every first-party module, each listing the modules it depends on. A target the Xcode project plugin builds knows no module and builds every tree inline, seams included; [Limits of the Xcode project plugin](#limits-of-the-xcode-project-plugin) says how to keep a seam’s tree narrow there.

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

If you invoke `SafeDITool` directly (not via the provided SPM plugin), the 1.x `--dependency-tree-output` flag has been replaced by `generate --combined-output`. A script that also passes `--additional-imported-modules` should list those modules in the module’s [`#SafeDIConfiguration`](#safediconfiguration) `additionalImportedModules` instead: the option is [deprecated](#custom-build-system-integration).

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

- [`Examples/ExampleProjectIntegration`](../Examples/ExampleProjectIntegration): a single-module Xcode project with the `SafeDIGenerator` plugin.
- [`Examples/ExampleMultiProjectIntegration`](../Examples/ExampleMultiProjectIntegration): a multi-module Xcode project, whose app module reads its other module through `additionalDirectoriesToInclude` and both of whose targets apply the plugin.
- [`Examples/Example Package Integration`](../Examples/Example%20Package%20Integration): a multi-module Swift package with the `SafeDIGenerator` plugin on each target.
- [`Examples/ExampleBazelIntegration`](../Examples/ExampleBazelIntegration): two Bazel modules declared with `safedi_swift_library`, the app module reading the other’s `.safedi` file.
- [`Examples/ExampleTuistIntegration`](../Examples/ExampleTuistIntegration): two Tuist projects, the framework’s in a subdirectory of the workspace, whose targets each run the `SafeDITuist` plugin’s script, the app target reading the framework’s `.safedi` file.

## Under the hood

SafeDI has a `SafeDITool` executable that the `SafeDIGenerator` plugin utilizes to read code and generate a dependency tree. The executable heavily utilizes asynchronous processing to avoid `SafeDITool` becoming a bottleneck in your build. It parses a Swift file with `SwiftSyntax` only when the file contains `@Instantiable` or `#SafeDIConfiguration`, or when a text search shows it may declare a type whose declaration SafeDI reads. Such a type is one an `@Instantiable` extension, or an extension holding an `@Instantiable` type, extends, one a declaration’s dependencies mention, or, in a run that writes a `.safedi` file, one another module can name ([Access of generated parameters](#access-of-generated-parameters)).

`SafeDITool` utilizes Apple’s [SwiftSyntax](https://github.com/apple/swift-syntax) library to parse your code and find your `@Instantiable` types’ initializers and dependencies. With this information, SafeDI generates a graph of your project’s dependencies and validates it during `SafeDITool` execution. If the graph is invalid, `SafeDITool` reports each problem as a compiler diagnostic at the declaration that caused it, offers an unambiguous repair as a fix-it, and exits non-zero. Each root's tree, and each mocked type's, reports the first problem it finds, and the problems of all of them are reported together, ordered by file, line, and column. Source code is only generated if the dependency graph is valid.

Due to limitations in Apple’s [Swift Package Manager Plugins](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/Plugins.md), the `SafeDIGenerator` plugin parses all of your first-party Swift files in a single pass. The Bazel rule, the Tuist plugin, and other builds that run `SafeDITool` once per module parse each module’s files once, and hand its declarations to the modules that depend on it in a `.safedi` file, as [Custom build system integration](#custom-build-system-integration) describes.

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
bazel run @safedi//bazel:safeditool -- query needs HomeFeature --module-info bazel-bin/Modules/Foundations/Foundations_safedi.safedi bazel-bin/Modules/Services/Services_safedi.safedi bazel-bin/Modules/HomeFeature/HomeFeature_safedi.safedi
```

For each type named, the query builds the type as its `mock()` does, with every dependency it receives provided by an `@Instantiable` declaration, and reports:

- The modules the type is built from in production, each with the declarations that build it.
- The `@Forwarded` parameters of the type.
- The dependencies no `@Instantiable` declaration fulfills, which the project provides by hand, each with its reason.

It then reports the same for the type’s mock. [The `query needs` report](QueryNeeds.md) describes which modules and which mock the report covers, how to name the types, and the JSON that `--json` prints for scripts.
