# SafeDI

[![CI Status](https://img.shields.io/github/actions/workflow/status/dfed/SafeDI/ci.yml?branch=main)](https://github.com/dfed/SafeDI/actions?query=workflow%3ACI+branch%3Amain)
[![codecov](https://codecov.io/gh/dfed/SafeDI/branch/main/graph/badge.svg)](https://codecov.io/gh/dfed/SafeDI)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://spdx.org/licenses/MIT.html)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fdfed%2FSafeDI%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/dfed/SafeDI)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fdfed%2FSafeDI%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/dfed/SafeDI)

Compile-time-safe dependency injection without the boilerplate. No containers. No service locators. No DI-specific types.

## Why teams choose SafeDI

- **Dependency injection that feels natural.** Get the simplicity of manual dependency injection without ceremony.
- **Compile-time graph validation.** If the code compiles, the dependency graph is valid.
- **Scoped runtime values.** Make your real logged-in `User` available non-optionally to any type in the subtree with just a single macro decoration.
- **Full-graph mocks.** Generated from your real dependency graph, `mock()` lets you override any branch for easy previews and tests.
- **Architecture-independent.** SwiftUI or UIKit, coordinators or MVVM, one module or hundreds — SafeDI fits what you already have.
- **Clear failures.** SafeDI flags unsolvable dependency graphs, outlining the problem and suggesting fixes.

## The core concept

SafeDI reads your code, validates your dependencies, and generates production and mock dependency trees—all during project compilation.

Opting a type into the SafeDI dependency tree is simple: add the `@Instantiable` macro to your type declaration, and decorate each dependency with a macro that indicates its lifecycle. Here is what a notes app might look like in SafeDI:

```swift
// `NotesApp` is the root of the dependency graph. SafeDI generates its public `init()`.
@Instantiable(isRoot: true) @main
public struct NotesApp: App, Instantiable {
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
    public var body: some View { … }

    // `user` is a runtime value forwarded in at this boundary.
    @Forwarded private let user: User
    // `userService` is received from an ancestor in the tree.
    @Received private let userService: UserService
    // `noteStorage` is created by `LoggedInView` and lives for its lifetime.
    @Instantiated private let noteStorage: NoteStorage
}

@Instantiable
public final class NoteStorage: Instantiable {
    // `user` and `stringStorage` are received from ancestors in the tree.
    @Received private let user: User
    @Received private let stringStorage: StringStorage
}
```

`User` is a runtime-derived value. It is forwarded once at the logged-in boundary and received later by the types that need it—non-optional, scoped to the subtree where it exists.

This is the core SafeDI model:
- write normal Swift types,
- declare dependencies where they live,
- let SafeDI validate and generate the wiring.

For a comprehensive explanation of SafeDI’s macros and their usage, please read [the Macros section of our manual](Documentation/Manual.md#macros).

## Tests and previews from real feature roots

Decorate a type with `@Instantiable(generateMock: true)` and SafeDI generates an `internal static func mock(…) -> Type` method that builds the full dependency subtree for that type. The same declarations that define the production graph generate the test and preview graphs.

If every dependency can be mocked, calling `mock()` with no arguments works:

```swift
#Preview {
    LoggedInView.mock()
}

// Types that are pure data give SafeDI a mock via `mockOnly`.
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

| | | |
|---|---|---|
| ✓ Compile-time safe | ✓ Thread safe | ✓ Hierarchical dependency scoping |
| ✓ Constructor injection | ✓ Multi-module support | ✓ Dependency inversion support |
| ✓ Transitive dependency solving | ✓ Cycle detection | ✓ Architecture independent |
| ✓ No DI-specific types or generics required | ✓ Full-graph mocks | ✓ Clear errors: never debug generated code |

## Getting started

Three steps to integrate:

1. Add `.package(url: "https://github.com/dfed/SafeDI.git", from: "2.0.0")` to your `Package.swift` dependencies.
2. Attach the `SafeDIGenerator` build tool plugin to your first-party target(s).
3. Decorate your app’s root type with `@Instantiable(isRoot: true)` and add `@Instantiable` to the dependencies it reaches.

Or skip ahead: working sample projects live in the [Examples folder](Examples/) — clone, open, and build. The [Manual](Documentation/Manual.md#installation) covers Xcode projects, multi-module packages, custom build systems, and prebuild scripts in depth.

If you are migrating an existing project to SafeDI, follow our [migration guide](Documentation/Manual.md#migrating-to-safedi). If you are upgrading from SafeDI 1.x, follow the [1.x → 2.x migration guide](Documentation/Manual.md#migrating-from-safedi-1x-to-2x).

## Comparing SafeDI to other DI libraries

SafeDI is closest in spirit to [Needle](https://github.com/uber/needle) and [Weaver](https://github.com/scribd/Weaver): all three validate the dependency graph at compile time and support hierarchical scoping, letting runtime-derived values like an authenticated user live non-optionally inside a subtree. SafeDI drops the per-type dependency protocols Needle requires and the containers Weaver maintains alongside your code — your app types remain your app types.

[Factory](https://github.com/hmlongco/Factory) and [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) take a container/environment approach that excels at scalar dependencies (a `Clock`, a `URLSession`). SafeDI additionally represents graph-local runtime values — an auth token, a logged-in user — as first-class subtree dependencies, so they can be received non-optionally wherever they’re needed. [Swinject](https://github.com/Swinject/Swinject) offers no compile-time validation at all.

SwiftUI’s own `Environment` is a useful mental model for a dependency tree — but without compile-time validation. SafeDI applies that tree shape to the full object graph and guarantees it resolves.

Across all of these, SafeDI is the only Swift DI library that generates full-graph mocks from your real dependency graph, and the only hierarchical DI library whose integration errors surface as Swift macro diagnostics with fix-its directly in your IDE.

## Contributing

I’m glad you’re interested in SafeDI, and I’d love to see where you take it. Please review the [contributing guidelines](Contributing.md) prior to submitting a Pull Request.

Thanks for being part of this journey, and happy injecting!

## Author

SafeDI was created by [Dan Federman](https://github.com/dfed), the architect of Airbnb’s closed-source Swift dependency injection system. Following his tenure at Airbnb, Dan developed SafeDI to share a modern, compile-time-safe dependency injection solution with the Swift community.

Dan has a proven track record of maintaining open-source libraries: he co-created [Valet](https://github.com/square/Valet) and has been maintaining the repo since its debut in 2015.

## Acknowledgements

Special thanks to [@kierajmumick](http://github.com/kierajmumick) for helping shape the early design of SafeDI.
