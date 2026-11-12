# SafeDI

[![CI Status](https://img.shields.io/github/actions/workflow/status/dfed/SafeDI/ci.yml?branch=main)](https://github.com/dfed/SafeDI/actions?query=workflow%3ACI+branch%3Amain)
[![codecov](https://codecov.io/gh/dfed/SafeDI/branch/main/graph/badge.svg)](https://codecov.io/gh/dfed/SafeDI)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://spdx.org/licenses/MIT.html)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fdfed%2FSafeDI%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/dfed/SafeDI)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fdfed%2FSafeDI%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/dfed/SafeDI)

Compile-time-safe dependency injection without the boilerplate. No containers. No service locators. No hand-written DI types.

## Why teams choose SafeDI

- **Dependency injection that feels natural.** Get the simplicity of manual dependency injection without ceremony.
- **Compile-time graph validation.** If the code compiles, the dependency graph is valid.
- **Scoped runtime values.** Make your real logged-in `User` available non-optionally to any type in the subtree with just a single macro decoration.
- **Full-graph mocks.** Generated from your real dependency graph, mocks let you override any of the graph’s objects for easy previews and tests.
- **Architecture-independent.** SwiftUI or UIKit, coordinators or MVVM, one module or hundreds — SafeDI fits what you already have.
- **Clear failures.** SafeDI reports an unsolvable graph as a compiler diagnostic at your declaration, in Xcode and in build logs. It names the declarations involved and offers a fix-it where one exists.

## The core concept

SafeDI reads your code, validates your dependencies, and generates production and mock dependency trees—all during project compilation.

Opting a type into the SafeDI dependency tree is simple: add the `@Instantiable` macro to your type declaration, and decorate each dependency with a macro that indicates its lifecycle. Here is what a notes app might look like in SafeDI:

```swift
// `NotesApp` is the root of the dependency graph. SafeDI generates its `public init()`.
@Instantiable(isRoot: true) @main
public struct NotesApp: App, Instantiable {
    public init(
        userService: UserService,
        nameEntryViewBuilder: Instantiator<NameEntryView>,
        loggedInViewBuilder: Instantiator<LoggedInView>
    ) { … }

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
    @Instantiated private let nameEntryViewBuilder: Instantiator<NameEntryView>
    @Instantiated private let loggedInViewBuilder: Instantiator<LoggedInView>
}

@Instantiable
public struct LoggedInView: View, Instantiable {
    public init(user: User, userService: UserService, noteStorage: NoteStorage) { … }

    public var body: some View { … }

    // `user` is a runtime value forwarded in at this boundary.
    @Forwarded private let user: User
    // `userService` is received from an ancestor in the tree.
    @Received private let userService: UserService
    // `noteStorage` is created by `LoggedInView` and lives for its lifetime.
    @Instantiated private let noteStorage: NoteStorage
}
```

`User` is a runtime-derived value. It is forwarded once at the logged-in boundary and received later by the types that need it—non-optional, scoped to the subtree where it exists.

This is the core SafeDI model:
- write normal Swift types,
- declare dependencies where they live,
- let SafeDI validate and generate the wiring.

For a comprehensive explanation of SafeDI’s macros and their usage, please read [the Macros section of our manual](Documentation/Manual.md#macros).

## Tests and previews from real feature roots

Decorate a type with `@Instantiable(generateMock: true)` and SafeDI generates a `static func mock(…) -> Type` method that builds the full dependency subtree for that type. The same declarations that define the production graph generate the test and preview graphs.

For a `LoggedInView` decorated with `@Instantiable(generateMock: true)`, if every dependency can be mocked, calling `mock()` with no arguments works. The `User` mock below demonstrates how `mockOnly` can supply a default for a forwarded runtime value:

```swift
#Preview {
    LoggedInView.mock()
}

// Declarations can participate only in mock generation via `mockOnly`.
@Instantiable(mockOnly: true)
extension User {
    public static func mock() -> User {
        User(name: "Mock User")
    }
}
```

For previews and tests that need real data, pass forwarded values directly and use `safeDIOverrides` to reach into the subtree:

```swift
#Preview {
    LoggedInView.mock(
        user: User(name: "dfed"),
        safeDIOverrides: .init(
            noteStorage: .init(defaultNote: "dfed says hello")
        )
    )
}
```

`safeDIOverrides` is a generated `struct` whose fields mirror the subtree SafeDI built. SafeDI still wires the rest of the graph around each override, so customizations compose with the subtree instead of replacing it.

## Features

<table>
<tr><td>✓ Thread safe</td><td>✓ Constructor injection</td><td>✓ Dependency inversion support</td><td>✓ Transitive dependency solving</td></tr>
<tr><td>✓ Cycle detection</td><td>✓ Conditional compilation support</td><td>✓ Lazy shared dependencies</td><td>✓ Swift Package Manager, Xcode, Bazel, and Tuist</td></tr>
</table>

## Getting started

To add SafeDI to a Swift package, add `.package(url: "https://github.com/dfed/SafeDI.git", from: "2.2.0")` to its dependencies. The [quick start](Documentation/QuickStart.md) sets up SafeDI in an app of several modules, in a Swift package, an Xcode project, Bazel, or Tuist: adding SafeDI to the build, declaring your types, creating the tree, and using mocks in tests and previews.

Working sample projects live in the [Examples folder](Examples/) — clone, open, and build. The [Manual](Documentation/Manual.md) is the reference for everything else, including [installation](Documentation/Manual.md#installation) in Xcode projects, Swift packages, Bazel, Tuist, and custom build systems.

If you are migrating an existing project to SafeDI, follow our [migration guide](Documentation/Manual.md#migrating-to-safedi), which also covers [adopting SafeDI in a large, multi-module codebase](Documentation/Manual.md#adopting-safedi-in-a-large-codebase). If you are upgrading from SafeDI 1.x, follow the [1.x → 2.x migration guide](Documentation/Manual.md#migrating-from-safedi-1x-to-2x).

## Comparing SafeDI to other DI libraries

SafeDI is closest in spirit to [Needle](https://github.com/uber/needle) and [Weaver](https://github.com/scribd/Weaver): all three validate the dependency graph at compile time and scope dependencies hierarchically, so a runtime value like an authenticated user lives non-optionally inside a subtree. Needle asks you to write a dependency protocol and a component for every scope; SafeDI’s macros on your existing types are the whole integration. Weaver’s maintainers no longer support it.

[Factory](https://github.com/hmlongco/Factory) and [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) take a container/environment approach that shines for scalar dependencies like a `Clock` or a `URLSession`, resolving at runtime. SafeDI is built around the object graph: its hierarchical scoping makes graph-local runtime values (an auth token, a logged-in user) first-class subtree dependencies, received non-optionally where they’re needed. [Swinject](https://github.com/Swinject/Swinject) also resolves at runtime, returning optionals.

SwiftUI’s own `Environment` is a useful mental model for a dependency tree — but without compile-time validation. SafeDI applies that tree shape to the full object graph and guarantees it resolves.

Of these libraries, only SafeDI generates mocks from your real dependency graph — `public` ones, too, which tests in other packages call — and it can generate a module’s tree in that module (`generateDependencyTree: true`), checks `package` and `internal` types when you build, and reports errors at your declaration, with a fix-it where the repair is unambiguous.

## Contributing

I’m glad you’re interested in SafeDI, and I’d love to see where you take it. Please review the [contributing guidelines](Contributing.md) prior to submitting a Pull Request.

Thanks for being part of this journey, and happy injecting!

## Author

SafeDI was created by [Dan Federman](https://github.com/dfed), the architect of Airbnb’s closed-source Swift dependency injection system. Following his tenure at Airbnb, Dan developed SafeDI to share a modern, compile-time-safe dependency injection solution with the Swift community.

Dan has a proven track record of maintaining open-source libraries: he co-created [Valet](https://github.com/square/Valet) and has been maintaining the repo since its debut in 2015.

## Acknowledgements

Special thanks to [@kierajmumick](http://github.com/kierajmumick) for helping shape the early design of SafeDI.
