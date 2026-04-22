#  ``SafeDI``

Compile-time-safe dependency injection without the boilerplate. No containers. No service locators. No hand-written DI types.

## Overview

SafeDI reads your code, validates your dependencies, and generates production and mock dependency trees during project compilation. If the code compiles, the dependency graph is valid.

Opting a type into the SafeDI dependency tree is simple: add `@Instantiable` to your type declaration, and decorate each dependency with a macro that indicates its lifecycle. Here is what a notes app might look like in SafeDI:

```swift
// `NotesApp` is the root of the dependency graph. SafeDI generates its public `init()`.
@Instantiable(isRoot: true) @main
public struct NotesApp: App, Instantiable {
    public init(
        userService: UserService,
        stringStorage: StringStorage,
        nameEntryViewBuilder: Instantiator<NameEntryView>,
        loggedInViewBuilder: Instantiator<LoggedInView>
    ) { /* ... */ }

    public var body: some Scene {
        WindowGroup {
            if let user = userService.user {
                // Forward the authenticated user into the logged-in subtree.
                loggedInViewBuilder.instantiate(user)
            } else {
                nameEntryViewBuilder.instantiate()
            }
        }
    }

    @ObservedObject @Instantiated private var userService: UserService
    @Instantiated private let stringStorage: StringStorage
    @Instantiated private let nameEntryViewBuilder: Instantiator<NameEntryView>
    @Instantiated private let loggedInViewBuilder: Instantiator<LoggedInView>
}

@Instantiable
public struct LoggedInView: View, Instantiable {
    public init(user: User, userService: UserService, noteStorage: NoteStorage) { /* ... */ }

    public var body: some View { /* ... */ }

    // `user` is a runtime value forwarded in at this boundary.
    @Forwarded private let user: User
    // `userService` is received from an ancestor in the tree.
    @Received private let userService: UserService
    // `noteStorage` is created by `LoggedInView` and lives for its lifetime.
    @Instantiated private let noteStorage: NoteStorage
}

@Instantiable
public final class NoteStorage: Instantiable {
    public init(user: User, stringStorage: StringStorage, defaultNote: String = "") { /* ... */ }

    // `user` and `stringStorage` are received from ancestors in the tree.
    @Received private let user: User
    @Received private let stringStorage: StringStorage
}
```

`User` is a runtime-derived value. It is forwarded once at the logged-in boundary and received later by the types that need it — non-optional, scoped to the subtree where it exists.

## Getting Started

Three steps to integrate:

1. Add `.package(url: "https://github.com/dfed/SafeDI.git", from: "2.0.0")` to your `Package.swift` dependencies.
2. Attach the `SafeDIGenerator` build tool plugin to your first-party target(s).
3. Decorate your app's root type with `@Instantiable(isRoot: true)` and add `@Instantiable` to the dependencies it reaches.

Working sample projects live in the [Examples folder](https://github.com/dfed/SafeDI/tree/main/Examples) — clone, open, and build. The [Manual](https://github.com/dfed/SafeDI/blob/main/Documentation/Manual.md) covers Xcode projects, multi-module packages, custom build systems, and prebuild scripts in depth.

## Topics

### Decorator macros

- ``Instantiable(isRoot:fulfillingAdditionalTypes:conformsElsewhere:mockOnly:mockAttributes:generateMock:customMockName:)``
- ``Instantiated()``
- ``Instantiated(fulfilledByType:erasedToConcreteExistential:)``
- ``Received(onlyIfAvailable:)``
- ``Received(fulfilledByDependencyNamed:ofType:erasedToConcreteExistential:onlyIfAvailable:)``
- ``Forwarded()``

### Configuration

- ``SafeDIConfiguration(additionalImportedModules:additionalDirectoriesToInclude:additionalMocksToGenerate:mockConditionalCompilation:)``

### Delayed instantiation

- ``Instantiator``
- ``SendableInstantiator``
- ``ErasedInstantiator``
- ``SendableErasedInstantiator``
