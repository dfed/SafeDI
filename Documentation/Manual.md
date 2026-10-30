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
    .package(url: "https://github.com/dfed/SafeDI.git", from: "2.1.0"),
]
```

To install the SafeDI framework into an Xcode project with Swift Package Manager, follow [Apple’s instructions](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) to add `https://github.com/dfed/SafeDI.git` as a dependency.

### Generating your dependency tree

SafeDI provides a code generation plugin named `SafeDIGenerator`. This plugin uses a prebuilt binary for fast builds without compiling SwiftSyntax. This plugin works out of the box on most project configurations. If your project uses a custom build system, you can configure your build to utilize the `SafeDITool` command-line executable directly.

#### Xcode project

If your first-party code comprises a single module in an `.xcodeproj`, once your Xcode project depends on the SafeDI package you can integrate the Swift Package Plugin simply by going to your target’s `Build Phases`, expanding the `Run Build Tool Plug-ins` drop-down, and adding the `SafeDIGenerator` as a build tool plug-in. You can see this integration in practice in the [ExampleProjectIntegration](../Examples/ExampleProjectIntegration) project.

If your Xcode project comprises multiple modules, follow the above steps, and then add a `#SafeDIConfiguration` to a file named `SafeDIConfiguration.swift` in your module to configure SafeDI:

```swift
import SafeDI

#SafeDIConfiguration(
    additionalDirectoriesToInclude: ["Subproject"]
)
```

The `additionalDirectoriesToInclude` parameter specifies folders outside of your module that SafeDI will scan for Swift source files. Paths must be relative to the executing directory (the directory containing the `.xcodeproj` for Xcode integrations). Use this parameter to specify the paths to dependent modules’ source directories, since Xcode project plugins cannot discover these automatically. You can see [an example of this configuration](../Examples/ExampleMultiProjectIntegration/ExampleMultiProjectIntegration/SafeDIConfiguration.swift) in the [ExampleMultiProjectIntegration](../Examples/ExampleMultiProjectIntegration) project.

> **Note:** Any SafeDI declaration, roots included, may sit behind a bare condition such as `#if DEBUG`; see [Conditional compilation](#conditional-compilation).

> **Note:** Only the `SafeDIGenerator` build-tool plugin declares the files reached through `additionalDirectoriesToInclude` as build inputs. Under Tuist and Bazel, don't rely on `additionalDirectoriesToInclude`. Tuist may read those files but won't rebuild when they change, and can't read them under user script sandboxing; Bazel can't see them at all. List every Swift source in the build target instead.

##### Installing the prebuilt SafeDITool binary

If you see a build warning that starts with **"SafeDI is planning this target’s generated files with a simpler scanner..."** — installing the prebuilt tool fixes it.

In Xcode, right-click your project in the navigator and choose **SafeDI → Safedi Release Install**. Approve the network-access and write-to-package-directory prompts. Xcode runs the command and downloads the prebuilt SafeDITool release binary for your SafeDI version into `.safedi/<version>/safeditool` next to your `.xcodeproj`. The build plugin picks it up automatically on subsequent builds.

**Why this step is required in Xcode:** Xcode’ implementation of Swift package build-tool plugins does not give plugins access to real tool locations within derived data – paths include placeholders whose values are not available to the plugin. SafeDI's plugin therefore can’t execute the real parser during setup and falls back to a regex-based output scanner. Installing the `SafeDITool` to a well-known location allows the plugin to execute the prebuilt tool. The install command is a one-time step per project (re-run it after a SafeDI version bump if the warning reappears). The plugin only runs inside Xcode — `swift build` users get the prebuilt binary through the default `prebuilt` trait already.

**What to commit:** the install command writes `.safedi/.gitignore` on first run with the single glob `*/safeditool`, which ignores `.safedi/<version>/safeditool` on every machine. **Commit `.safedi/.gitignore` itself.** The binary it ignores is host-specific (arm64 vs x86_64) and per-version, so it's meant to be re-downloaded per-machine. Developers new to the project re-run the install command once after cloning.

#### Swift package

If your first-party code is entirely contained in a Swift Package with one or more modules, you can add the following lines to your root target’s definition:

```swift
    plugins: [
        .plugin(name: "SafeDIGenerator", package: "SafeDI")
    ]
```

To also generate mocks for non-root modules, add the plugin to all first-party targets.

You can see this integration in practice in the [Example Package Integration](../Examples/Example Package Integration) package.

Unlike the `SafeDIGenerator` Xcode project plugin, the `SafeDIGenerator` Swift package plugin finds source files in dependent modules without additional configuration steps. If you find that SafeDI’s generated dependency tree is missing required imports, you may add a `#SafeDIConfiguration` to a file named `SafeDIConfiguration.swift` in your root module with the additional module names:

```swift
import SafeDI

#SafeDIConfiguration(
    additionalImportedModules: ["MyModule"]
)
```

> **Note:** On Swift 6.4 or later, `swift build` can fail for a target with a couple thousand or more input files with `sandbox-exec: data object length … exceeds maximum (65535)`. This is a Swift Package Manager limit on the sandbox profile of a plugin’s command; Xcode is not affected. Build with `swift build --build-system native`, or with `swift build --disable-sandbox`, which turns off sandboxing for every plugin and package manifest in the build.

#### Bazel

Add `bazel_dep(name = "safedi", version = "2.1.0")` to your `MODULE.bazel`, then declare each SafeDI module with `safedi_swift_library` in place of `swift_library`:

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

The macro accepts every `swift_library` attribute and declares two targets: the `swift_library` named `App`, and `App_safedi`, which runs `SafeDITool` over the same `srcs` with the same `defines` and `copts`. List another module’s `<name>_safedi` target in `safedi_deps` to use the `@Instantiable` types it declares, and the module itself in `deps`. You can see this integration in practice in the [ExampleBazelIntegration](../Examples/ExampleBazelIntegration) module.

A module that needs a shape the macro does not offer can declare the `safedi_compile` rule and its `swift_library` separately, adding `[":<rule name>"]` to the library’s `srcs` and giving the rule the library’s `defines` and `copts`; see [`bazel/safedi.bzl`](../bazel/safedi.bzl).

`SafeDITool` runs as the prebuilt binary the SafeDI release publishes for the machine that runs the build – macOS arm64 or x86_64, or Linux x86_64 or arm64 – the same binary the `SafeDIGenerator` plugin and the Tuist plugin run. Bazel downloads it from the release’s GitHub assets the first time a build needs it – so that build needs network access to GitHub, or a [repository cache](https://bazel.build/run/build#repository-cache) that holds the binary – and checks it against the sha256 recorded in the release’s source archive. On any other machine, Bazel builds `SafeDITool` from source. To always build it from source, add this line to your `.bazelrc`:

```
common --@safedi//bazel:prefer_prebuilt_safeditool=false
```

A build that takes SafeDI from a checkout of its repository rather than from a release – through `local_path_override`, `git_override`, or an `archive_override` of a GitHub archive – always builds `SafeDITool` from that checkout, so the rule never runs a binary older than itself.

### Running SafeDITool yourself

Your integration already has a `SafeDITool`. Run it to read its `--help`, [query what a type needs](#querying-what-a-type-needs), or print a `.safedi` file with `dump`.

- **Swift package:** `.build/artifacts/safedi/SafeDIToolBinary/SafeDITool.artifactbundle/SafeDITool-macos-arm64/bin/SafeDITool` from the package’s directory, or `swift run SafeDITool` with the `sourceBuild` trait; writes no `.safedi` files.
- **Xcode project:** `SourcePackages/artifacts/safedi/SafeDIToolBinary/…` in the project’s derived data, or `.safedi/<version>/safeditool` once [installed](#installing-the-prebuilt-safeditool-binary); writes no `.safedi` files.
- **Bazel:** `bazel run @safedi//bazel:safeditool -- <arguments>` from the workspace root, with absolute paths, runs the `SafeDITool` your build runs, prebuilt or built from source; writes `bazel-bin/<package>/<name>_safedi.safedi`.
- **Tuist:** `Tuist/.build/artifacts/safedi/SafeDIToolBinary/SafeDITool.artifactbundle/SafeDITool-macos-arm64/bin/SafeDITool` from the project’s directory; writes `$BUILT_PRODUCTS_DIR/SafeDI/<module>.safedi`.

On an Intel Mac, the bundle’s directory is `SafeDITool-macos-x86_64`.

### Additional configurations

`SafeDITool` is designed to integrate into projects of any size or shape. Our [Releases](https://github.com/dfed/SafeDI/releases) page ships a prebuilt, codesigned `SafeDITool.artifactbundle.zip` that can be downloaded and driven directly from a pre-build script — see the embedded shell in [`TuistPlugins/SafeDITuist/ProjectDescriptionHelpers/SafeDI.swift`](../TuistPlugins/SafeDITuist/ProjectDescriptionHelpers/SafeDI.swift) for a working reference (it locates the binary via SPM, runs `generate --combined-output` for fixed-path Swift output, and supports the cross-module `.safedi` module-info handoff). For a non-SPM build system, swap the binary-location lookup for a `curl` of the artifact bundle. Set `ENABLE_USER_SCRIPT_SANDBOXING` to `NO` in the target running the pre-build script. Pass the target's active compilation conditions to `generate --active-compilation-conditions`, or its `SWIFT_ACTIVE_COMPILATION_CONDITIONS` and `OTHER_SWIFT_FLAGS` build settings to `generate --build-setting-active-compilation-conditions` and `--build-setting-other-swift-flags`, so SafeDITool scans the same `#if` clauses the compiler compiles; see [Conditional compilation](#conditional-compilation).

`SafeDITool` can parse all of your Swift files at once, or for even better performance, the tool can be run on each dependent module as part of the build. Run `SafeDITool` with `--help`, as [Running SafeDITool yourself](#running-safeditool-yourself) describes for your integration, to see documentation of the tool’s supported arguments.

### Finding the generated code

SafeDI writes its output into the build directory rather than your source tree. When you want to read what it generated for a root or a mock, look here:

| Integration | Generated files |
| --- | --- |
| Xcode project with the `SafeDIGenerator` plugin | `<DerivedData>/Build/Intermediates.noindex/BuildToolPluginIntermediates/<Project>.output/<Target>/SafeDIGenerator/SafeDIOutput/` |
| Swift package built with `swift build` | `.build/plugins/outputs/<package>/<target>/destination/SafeDIGenerator/SafeDIOutput/` |
| Bazel (`safedi_swift_library` or `safedi_compile`) | `bazel-bin/<package>/<name>_safedi.swift` for a `safedi_swift_library` named `<name>`, or `bazel-bin/<package>/<rule name>.swift` for a hand-written `safedi_compile`; one combined file per module |
| Tuist (`SafeDITuist` plugin) | `$(DERIVED_FILE_DIR)/SafeDIGenerated.swift` for each target, under the target’s intermediates in DerivedData |
| Custom build system | Wherever your `generate` invocation points `--combined-output` or the manifest’s output paths |

The quickest way to locate them in any layout is:

```bash
find . -name '*+SafeDI*.swift' -not -path '*/checkouts/*'
```

The plugin-based integrations name files `<File>+SafeDI.swift` for the dependency trees of the roots a source file `<File>.swift` declares, `<File>+SafeDIMock.swift` for the mocks of the `generateMock: true` types it declares, `<Type>+SafeDIMock.swift` for each type a `#SafeDIConfiguration` lists in `additionalMocksToGenerate`, and `SafeDIMockConfiguration.swift` for the shared mock configuration. Files whose names would match, ignoring letter case, are prefixed with as many enclosing directories as tell them apart (`FeatureA_Root+SafeDI.swift`), then suffixed `_2`, `_3`, … if a name still matches. A generated file that holds only compile-time assertions belongs to a declaration the build’s conditions leave inactive (see [Declarations that decide which files SafeDI generates](#declarations-that-decide-which-files-safedi-generates)).

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

2. Have a `public init(…)` or `open init(…)` that has a parameter for each of its injected properties.

3. Spell a nested type in a decorated property’s type with its enclosing types, such as `@Forwarded let configuration: Feature.Configuration`: generated code is in an extension where the members of `Feature` are not in scope, and the `@Instantiable` macro warns, with a fix-it, when a type declared inside the decorated type is spelled without it. SafeDI itself qualifies a nested type that an `@Instantiable` declaration fulfills.

The `@Instantiable` macro guides developers through satisfying the first two requirements with code generation and build-time fix-its.

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

SafeDI recognizes its wrapper types – `Instantiator`, `SendableInstantiator`, `ErasedInstantiator`, `SendableErasedInstantiator`, `LazilyInstantiated`, and `SendableLazilyInstantiated` – by name alone, so do not declare types with these names in a project that uses SafeDI.

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

Types that are declared outside of your project can be instantiated by SafeDI if there is an extension on the type decorated with the `@Instantiable` macro. Extensions decorated with this macro define how to instantiate the extended type via a `public static func instantiate(…) -> ExtendedType` function. This `instantiate(…)` function can receive dependencies instantiated or forwarded by objects further up the dependency tree by declaring these dependencies as parameters to the `instantiate(…)` function. A parameter with a default value is not a dependency, as for an initializer: SafeDI calls `instantiate(…)` without it, and a generated mock offers it as an override.

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

To instantiate a dependency later than its enclosing type, declare the property as an [`Instantiator`](#instantiator) or a [`LazilyInstantiated`](#lazilyinstantiated). [Delayed instantiation](#delayed-instantiation) compares the three.

Each `@Instantiated` property is a distinct instance.

`@Instantiated`-decorated properties must be an `@Instantiable` type, or a type listed in an `@Instantiable(fulfillingAdditionalTypes:)` declaration.

An `@Instantiated` property’s type cannot be optional, because SafeDI always creates it; a dependency that may be absent is received with [`@Received(onlyIfAvailable: true)`](#conditionally-receiving-dependencies).

If the enclosing type is a SwiftUI `View`, keep in mind that `@Instantiated` objects are re-initialized each time the view is recreated by SwiftUI. You can find a deep dive on SwiftUI view lifecycles [here](https://www.donnywals.com/understanding-how-and-when-swiftui-decides-to-redraw-views/).

### @Forwarded

Property declarations within `@Instantiable` types decorated with [`@Forwarded`](../Sources/SafeDI/Decorators/Forwarded.swift) represent dependencies that come from the runtime, e.g. user input or backend-delivered content. Like an `@Instantiated`-decorated property, a `@Forwarded`-decorated property is available to be `@Received` by objects instantiated further down the dependency tree.

A `@Forwarded` property is forwarded into the SafeDI dependency tree by an [`Instantiator`](#instantiator)’s `instantiate(_:)` function that creates an instance of the property’s enclosing type.

The [Macros intro](#macros) shows a `LoggedInView` with a `@Forwarded user: User`. The parent side — the root that actually passes the authenticated user in — uses the child’s `Instantiator` to forward the value:

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

### @Received

Property declarations within `@Instantiable` types decorated with [`@Received`](../Sources/SafeDI/Decorators/Received.swift) are injected into the enclosing type’s initializer. A `@Received` property is fulfilled by the nearest `@Instantiated` or `@Forwarded` property above it with the same name and type; if there is none, the build fails.

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

SafeDI ignores `any` when it matches types, so `any SessionsApi` and `SessionsApi` are one type, in renames and `fulfillingAdditionalTypes` too.

#### Renaming and retyping dependencies

Use `@Received(fulfilledByDependencyNamed:ofType:)` to give a dependency an additional name and type. The dependency is the property of that name that the declaring type instantiates, forwards, or itself renames, or, when the declaring type has none, the one a type above it instantiates or forwards. Types further down the tree can then `@Received` the same instance under either name and type.

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

To receive the renamed dependency inside a type-erasing wrapper, add `erasedToConcreteExistential: true`, which wraps it as [`@Instantiated` erasure](#making-protocols-instantiable) does: a property `userVendor: AnyUserVendor` is assigned `AnyUserVendor(userManager)`. With `onlyIfAvailable: true` the property is optional, and the type it wraps does the wrapping: a property `userVendor: AnyUserVendor?` is assigned `AnyUserVendor(userManager)` too.

A rename can also be fulfilled by another rename declared on the same type, as long as the renames do not form a cycle. The rename’s `ofType:` must name exactly the renamed property’s type, or a `LazilyInstantiated` property’s instance type. SafeDI does not check that the retyped property can be fulfilled by the original type; the Swift compiler checks the generated assignment and reports a mismatch at the `@Received` declaration, or in the generated file beside a comment naming it, depending on the build integration (see [Custom build system integration](#custom-build-system-integration)).

The renamed property may keep the original label, but below it that label then names the renamed type. Give the renamed property a label of its own when anything below receives the original; the same holds for an `@Instantiated` or `@Forwarded` property that reuses a label from higher in the tree.

#### Sharing one instance across properties of disparate types

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

#### Conditionally receiving dependencies

Use `@Received(onlyIfAvailable: true)` to receive an optional dependency only when a parent has `@Instantiated` or `@Forwarded` it. This is useful when a type is instantiated by multiple parents with different available dependencies — for example, a `FeedView` used by both a logged-in and logged-out parent:

```swift
@Instantiable
public struct FeedView: Instantiable {
    // Populated when reached from `LoggedInView`; `nil` when reached from `LoggedOutView`.
    @Received(onlyIfAvailable: true) private let user: User?
}
```

A dependency counts as available only if it can be built before the receiver. Receiving still follows the usual rule: a type receives what a type above it instantiates or forwards. Availability depends on the order in which one parent builds the properties it instantiates.

```swift
@Instantiable
public struct Parent: Instantiable {
    @Instantiated let a: A
    @Instantiated let b: B // A type under `B` receives `a`.
}
```

A type under `B` that receives `a` is receiving a property of `Parent`, which is above it, so `Parent` builds `a` before `b`. Nothing reaches into the types under `A`. The receiver gets `nil` in the cases where `a` cannot be built first:

- **The receiver is built inside the dependency, or is the dependency.** A type built inside `a`, or built by `a` when `a` is an `Instantiator`, that receives `a` only if available gets `nil`, because `a` is still being built.
- **Two of a parent’s properties receive each other.** If a type under `B` receives `a` only if available and `A` receives `b`, then `b` is built first and that receiver gets `nil`. If anything under `B` receives `a` without `onlyIfAvailable`, `a` is built first instead, and `A` gets `nil` for `b` when it receives `b` only if available.
- **Both receive each other only if available.** The property declared later is built first and receives `nil`.
- **Nothing is provided below a `nil`.** A property received only if available that is `nil` provides nothing to the types below the receiver, so a type further down that requires the same property needs a type above it to provide it.
- **A renamed dependency is unavailable.** A `@Received(fulfilledByDependencyNamed:ofType:onlyIfAvailable: true)` property whose fulfilling dependency is unavailable is `nil`, and so is that property for anything that receives it in turn with `onlyIfAvailable: true`.
- **A type requires a renamed dependency that is only available sometimes.** A type that receives the renamed property without `onlyIfAvailable` requires it, as with any dependency: an enclosing property of that name stands in when there is one, and otherwise the fulfilling dependency is built first. The build reports at the receiving declaration when neither is possible.

### #SafeDIConfiguration

[`#SafeDIConfiguration`](../Sources/SafeDI/Decorators/SafeDIConfiguration.swift) is a freestanding declaration macro that provides build-time configuration for SafeDI’s code generation plugin. Each module may have at most one `#SafeDIConfiguration` invocation in any one compilation, so the clauses of an `#if` block may each declare a different one. It must appear at the top level of a Swift file (not nested inside a type). All arguments must be literal values. All parameters have defaults, so the simplest valid invocation is `#SafeDIConfiguration()`.

Declare the configuration in a file named `SafeDIConfiguration.swift` in the module’s sources, which SafeDI reads before the rest of the module. A configuration in any other file still works; when it sets a non-default `mockConditionalCompilation`, SafeDI scans the module twice and warns at the `#SafeDIConfiguration`.

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
- `additionalDirectoriesToInclude`: Directories containing Swift files to include, relative to the executing directory. An entry may also name a single Swift file. Only the `SafeDIGenerator` build-tool plugin honors it (see the note under [Xcode project](#xcode-project)). Default: `[]`.
- `additionalMocksToGenerate`: Type names from dependent modules to generate `mock()` methods for in this module. The types must be `@Instantiable` in their home module. See [Cross-module mock generation](#cross-module-mock-generation). Default: `[]`.
- `mockConditionalCompilation`: The conditional compilation flag to wrap generated mock code in (e.g. `"DEBUG"`). Set to `nil` to generate mocks without conditional compilation. Default: `"DEBUG"`.

## Delayed instantiation

When you want to instantiate a dependency after `init(…)`, you need to declare an `Instantiator<Dependency>`-typed property as `@Instantiated` or `@Received`. Deferred instantiation is useful in situations where a dependency is expensive to create or only required under certain conditions (e.g., creating a detailed view for a selected item in a list).

An `Instantiator` creates a new instance each time it is asked for one. When you instead want a single, shared instance that is created only once something needs it, declare a [`LazilyInstantiated<Dependency>`](#lazilyinstantiated)-typed property. The two differ from each other, and from a plain `@Instantiated` property, as follows:

| | `@Instantiated let dependency: Dependency` | `Instantiator<Dependency>` | `LazilyInstantiated<Dependency>` |
| --- | --- | --- | --- |
| An instance is created | When the declaring type is created | Each time `instantiate()` is called | The first time `instance` is read |
| Instances created | One | One per call | One |
| Types further down the tree can receive | The instance | The `Instantiator` | The instance, or the `LazilyInstantiated` |
| `Dependency` can have `@Forwarded` properties | No | Yes | No |
| Can break a dependency cycle | No | Yes | No |
| `Sendable` twin | – | [`SendableInstantiator<Dependency>`](#sendable-wrappers) | [`SendableLazilyInstantiated<Dependency>`](#sendable-wrappers) |

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

An `Instantiator` is also how types create one another: SafeDI accepts a dependency cycle only when the dependency that closes it is an `@Instantiated` `Instantiator` or `ErasedInstantiator`, or a `Sendable` twin, which builds its type each time it is called.

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

An `@Instantiated` erased instantiator must name the type it builds with `fulfilledByType`. An `@Received` or `@Forwarded` one is handed in rather than built, so it names no type: a type below `ParentView` can declare `@Received let childViewBuilder: ErasedInstantiator<(), AnyView>` to receive the instantiator `ParentView` creates. As with any received dependency, the label and the full type must match.

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

A lazily instantiated dependency is created at most once, just like any other `@Instantiated` property that is not an `Instantiator`. SafeDI therefore validates `exportService: LazilyInstantiated<ExportService>` exactly as it validates `exportService: ExportService`: it does not break a dependency cycle, and its type cannot have `@Forwarded` properties. To let types create one another, or to create a type with forwarded properties on demand, use an [`Instantiator`](#instantiator).

A `LazilyInstantiated` property accepts the same `fulfilledByType` and `erasedToConcreteExistential` parameters as any other `@Instantiated` property:

```swift
@Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true)
private let userService: LazilyInstantiated<AnyUserService>
```

A `LazilyInstantiated` is not `Sendable`, and reads of `instance` are not synchronized. To share one across concurrency domains, use its [`Sendable` twin](#sendable-wrappers), `SendableLazilyInstantiated`.

SafeDI validates the dependency tree, not what an initializer does. Do not read `instance` from the initializer of the type that declares the `LazilyInstantiated` or `SendableLazilyInstantiated` property, or from any initializer that runs while that instance is being created, whether directly or through a callback: doing so produces undefined behavior. The guarantees each type provides are stated in the documentation of [`LazilyInstantiated`](../Sources/SafeDI/DelayedInstantiation/LazilyInstantiated.swift) and [`SendableLazilyInstantiated`](../Sources/SafeDI/DelayedInstantiation/SendableLazilyInstantiated.swift).

In a [generated mock](#mock-generation), a lazily instantiated dependency is overridden like any other `@Instantiated` dependency: its `SafeDIOverrides` entry is a closure that returns the instance, and the mock calls that closure the first time the instance is read. A type’s generated mock therefore has the same parameters whether the dependencies it receives are lazily instantiated or not.

### Sendable wrappers

`Instantiator`, `ErasedInstantiator`, and `LazilyInstantiated` are not `Sendable`. To share one across concurrency domains, declare its `Sendable` twin: [`SendableInstantiator`](../Sources/SafeDI/DelayedInstantiation/SendableInstantiator.swift), [`SendableErasedInstantiator`](../Sources/SafeDI/DelayedInstantiation/SendableErasedInstantiator.swift), or [`SendableLazilyInstantiated`](../Sources/SafeDI/DelayedInstantiation/SendableLazilyInstantiated.swift). A `SendableLazilyInstantiated` creates its instance exactly once while holding a lock and requires the instance to be `Sendable`. It is available on macOS 15, iOS 18, tvOS 18, watchOS 11, and visionOS 2 and later; the generated code is not marked `@available`, so use it only in a module whose deployment targets are at least those versions.

A `Sendable` wrapper builds its dependency in a `@Sendable` function, which places two requirements on the dependency’s subtree:

- **What the subtree receives from outside it must be `Sendable`**, even when the receiving type is itself `Sendable`. Declare a wrapper the subtree receives from outside, or whose instance it receives, as its `Sendable` twin. Wrappers instantiated inside the same `Sendable` wrapper are fine. SafeDI reports an error at the receiving property.
- **Every initializer the function calls must be callable synchronously outside any actor**, and so must an extension’s `instantiate(…)` and a hand-written mock method that a generated mock calls there. The initializer’s isolation counts, not the type’s: a `@MainActor` class with a `nonisolated init` is fine when its stored properties are `Sendable`. SafeDI does not check this, and the generated code fails to compile otherwise; declare such an initializer `nonisolated`. `mockAttributes: "@MainActor"` does not help.

Generated mocks follow the same rules, and the `SafeDIMockConfiguration` of a type reached through a `Sendable` wrapper has `@Sendable` closure fields.

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

When a type also has a hand-written mock method, it must have a different name from the generated `mock()` to avoid ambiguity. This applies wherever the hand-written method is declared — in the same declaration or in a separate [`mockOnly` declaration](#splitting-production-and-mock-declarations). Use the `customMockName` parameter to specify the name of your hand-written method. The generated `mock()` will call through to it. With `mockOnly: true`, `customMockName` tells SafeDI which method to use as the mock provider. This is useful when you need custom logic during mock construction — for example, setting up stub behavior, configuring test doubles, or wiring delegates:

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

When the hand-written method returns an additional type the `@Instantiable` declaration fulfills (for example, a protocol declared in `fulfillingAdditionalTypes`), the generated `mock()` method also returns that type. This keeps the signatures type-compatible on extension-based declarations where a concrete `Self` return wouldn’t line up with a protocol-returning `customMock`. Concrete-type declarations are required to return `Self` or the concrete type from their `customMock`.

If you provide a mock method without `generateMock: true`, parent types that instantiate the child will call `ChildType.mock(…)` (or `ChildType.customMock(…)`) instead of `ChildType(…)` when constructing it, threading mock parameters through your custom method.

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

When you provide a `mockOnly` declaration, SafeDI’s mock generator will utilize that mock wherever the declaration’s concrete or fulfilled types appear in a mock dependency tree. This "auto-filling" behavior means you don’t have to manually provide a mock for common types (like `User` or `NetworkClient`) every time you call `mock()` on a parent type. For `@Forwarded` dependencies, the parameter gets a default value so callers don’t need to provide it. For `@Instantiated` dependencies, the type appears in `SafeDIOverrides` with `Type.mock()` as the default, allowing optional override.

`mockOnly` declarations are useful for:

- Protocols that need mocks in your tests and previews
- Types used as `@Forwarded` dependencies (e.g., `String`, `Int`, `UUID`, `User`)
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

When both declarations exist, SafeDI uses the production `@Instantiable` for the dependency tree and the `mockOnly` declaration’s hand-written mock for mock generation. If the production type also has a hand-written `mock()` method, SafeDI emits an error — a type can have at most one hand-written mock. A production type without `generateMock: true` (like the one above) is built in mocks by calling the `mockOnly` declaration’s method, which may be named `mock`. A production type whose `mock()` is generated – by `generateMock: true`, or because another module lists it in `additionalMocksToGenerate` – must name the hand-written method with `customMockName`; its generated `mock()` then calls through to it:

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

Your user-defined `mock()` method must be `public` (or `open`) and must accept parameters for each of the type’s `@Instantiated`, `@Received`, and `@Forwarded` dependencies. Non-dependency parameters must have default values. On concrete type declarations the return type must be `Self` or the type name; on extension-based `@Instantiable` types the return type must match the extended type (e.g. `-> Container<Bool>`) or a `fulfillingAdditionalTypes` entry, mirroring the corresponding `instantiate()` method. The `@Instantiable` macro validates these requirements and provides fix-its for any issues.

```swift
#if DEBUG
#Preview {
    MyView.mock()
}
#endif
```

### Overriding dependencies

It can be helpful to think of a generated `mock()` as having three buckets:

1. Flat `mock()` parameters for values the caller owns directly at the root.
2. The `safeDIOverrides` parameter, whose `SafeDIOverrides` value lets you customize values that SafeDI surfaces through the generated dependency tree.
3. Nested `SafeDIMockConfiguration` values inside `SafeDIOverrides` when a child has its own subtree or default-valued construction inputs.

In practice, that means values that belong directly to the mocked root stay as flat parameters, while values that customize the generated dependency tree flow through `safeDIOverrides`.

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

When a type has `@Instantiated` dependencies, the generated `mock()` accepts a `safeDIOverrides` argument that lets you override any dependency in the tree. Each entry on `SafeDIOverrides` is either a closure whose parameters match the resolved values of that dependency’s own inputs, or a nested `SafeDIMockConfiguration` struct when the dependency has its own `@Instantiated` subtree or default-valued init parameters.

Closure-shaped entries apply when the dependency has nothing further to configure. Pass any closure whose parameters match the dependency's resolved inputs — a literal, or an `init` reference when its signature already matches:

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

`SafeDIMockConfiguration` exposes an optional override for each of the child’s own `@Instantiated` dependencies and each default-valued parameter of its `init` (or `instantiate(…)`), plus a trailing builder closure. Defaults come from the type’s hand-written `mock` method when it has one, and from its `init` (or `instantiate(…)`) otherwise. The builder’s parameters match the type’s hand-written `mock` method signature if one is defined, or its `init` parameters otherwise. When no builder is provided, the generated mock calls the type’s hand-written `mock` method or `init` directly.

Closure fields on `SafeDIMockConfiguration` are plain (non-`@Sendable`) by default, so overrides can capture mutable non-`Sendable` test state; a type reached through a [`Sendable` wrapper](#sendable-wrappers) gets `@Sendable` closure fields instead.

A type gets its own `SafeDIOverrides` struct when at least one dependency belongs there: an `@Instantiated` dependency, a `@Received` dependency the mock can build because an `@Instantiable` declaration fulfills its type or a single concrete type is [erased to](#receiving-a-type-erased-dependency), or a `@Received(onlyIfAvailable: true)` dependency. Every other dependency is a flat `mock()` parameter.

#### Dependency kinds in the generated mock

The table below shows where each dependency kind lands in the three buckets above, and whether the caller has to supply it. The main wrinkle is `@Received(onlyIfAvailable: true)`: it appears on `SafeDIOverrides` and defaults to `nil`.

| Dependency kind | Shape in the mock | Default |
| --- | --- | --- |
| Required `@Received` of a type some `@Instantiable` declaration fulfills (directly or via `fulfillingAdditionalTypes`), or of a type exactly one concrete type is [erased to](#receiving-a-type-erased-dependency) | Entry on `SafeDIOverrides` | Built from the real subtree, exactly like `@Instantiated` |
| Required `@Received` of a type no `@Instantiable` declaration fulfills, including a type [different concrete types are erased to](#receiving-a-type-erased-dependency) | Flat `mock()` parameter | Required |
| Required `@Received` of a type whose `@Instantiable` declaration has `@Forwarded` properties, unless received as an `Instantiator` | Flat `mock()` parameter | Required |
| `@Forwarded` | Flat `mock()` parameter | Required, unless the root provides a default or the forwarded type has a [`mockOnly`](#the-mockonly-parameter) provider (which defaults the parameter to `Type.mock()`) |
| `@Instantiated` | Entry on `SafeDIOverrides` | Built from the real subtree — see [Overriding dependencies](#overriding-dependencies) |
| `@Instantiated` whose fulfilling declaration this module cannot see (`fulfilledByType` in another module) | Flat `mock()` parameter | Required |
| `@Received(onlyIfAvailable: true)` | Entry on `SafeDIOverrides`, typed as optional | `nil` |
| Default-valued non-DI init parameter | Flat `mock()` parameter on a direct mock, or a nested `SafeDIMockConfiguration` field when reached through a parent | The parameter’s original default expression |

A type with `@Forwarded` properties can only be built by an `Instantiator` handed the forwarded values, so when the mocked type’s tree receives such a type as a constant, `mock()` takes the instance as a parameter, even when the type has a hand-written mock. A received `Instantiator` of the type is built as usual.

A type in a mock’s tree can declare an `@Instantiated(fulfilledByType:)` dependency whose `@Instantiable` declaration the mock’s module cannot see, such as a `DefaultUserService` declared in a module only the app imports. Production code is generated where every module is visible; the mock cannot build the dependency, so `mock()` takes it as a parameter, such as `mock(userService:)`. The parameter does not excuse a missing fulfiller: a root in the mock’s module that reaches the type still fails to generate.

A `@Received(onlyIfAvailable: true)` dependency gets no `SafeDIOverrides` entry of its own when the mock already builds that dependency — because the mocked type instantiates it, or because another type in the tree requires it — or when nothing fulfills it and another type in the tree requires it, which makes it a required flat `mock()` parameter. It is an optional entry only when every receiver in the tree, renames included, receives it `onlyIfAvailable`; a receiver built inside the instance is passed `nil`, as in production.

A `@Received` dependency is resolved from its declared type, not from the renames in any particular parent. Take `ProfileView` from [Sharing one instance across properties of disparate types](#sharing-one-instance-across-properties-of-disparate-types): `ProfileView.mock()` can build `crashReporter` itself only when `Telemetry` lists `CrashReporter` in `fulfillingAdditionalTypes`. A composition entry such as `(EventTracker & CrashReporter).self` alone does not cover its members. Otherwise `crashReporter` is a required parameter of `ProfileView.mock()`. Because each received dependency is resolved on its own, a mock that receives both `EventTracker` and `CrashReporter` builds a separate `Telemetry` for each. Pass one instance through `safeDIOverrides` if a test needs them to coincide.

The mock builds the dependencies its tree receives after the mocked type’s own `@Instantiated` dependencies, each after the ones it is built from, in an order set by where you declare properties, never by labels or type names; the `SafeDIOverrides` entries follow that order. Of two that receive each other only if available, the one received later is passed `nil`, as [under a root](#conditionally-receiving-dependencies).

When two flat `mock()` parameters or two entries in the same `SafeDIOverrides` or `SafeDIMockConfiguration` share a label, each is named by its label followed by its type as an identifier: received dependencies named `items` of types `[String]` and `Set<String>` become `items_Array_String` and `items_Set__String`. A mock builds every form in which its tree receives a dependency under one label, a label the mocked type forwards included: when one type requires `x: X` and another requires `x: Instantiator<X>`, the mock builds both, with the entries `x_X` and `x_Instantiator__X`. An optional form beside its non-optional form, and the instance of a `LazilyInstantiated`, are not forms of their own.

#### Receiving a type-erased dependency

A `@Received` dependency of a type no `@Instantiable` declaration fulfills can still be built by a mock when a parent erases a concrete type to it. `NotesApp` in [Making protocols `@Instantiable`](#making-protocols-instantiable) declares `@Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) private var userService: AnyUserService`, so the mock of a type that receives `userService: AnyUserService` gets a `userService` entry on `SafeDIOverrides` that defaults to building a `DefaultUserService` and wrapping it in `AnyUserService`. SafeDI looks at every `@Instantiated` property with `erasedToConcreteExistential: true` in the current module and the modules it depends on, and matches the received dependency by its type: a received `AnyUserService` matches properties of type `AnyUserService`, not an `ErasedInstantiator<…, AnyUserService>`.

When those properties erase different concrete types to the same type — say `NotesApp` erases `DefaultUserService` to `AnyUserService` and another parent erases `OfflineUserService` to it — nothing tells SafeDI which one a mock should build. The dependency is then a required flat `mock()` parameter:

```swift
@Instantiable(generateMock: true)
public struct SettingsView: View, Instantiable {
    // …
    @ObservedObject @Received private var userService: AnyUserService
}

SettingsView.mock(userService: AnyUserService(StubUserService()))
```

The same matching applies to a received erased instantiator: a mock builds a received `childViewBuilder: ErasedInstantiator<(), AnyView>` from a property of that type, such as `ParentView`’s in [ErasedInstantiator](#erasedinstantiator).

### Mock visibility

Generated mocks have `internal` visibility. They are accessible within the module where they are generated but not from other modules. This avoids cross-module extension conflicts when multiple modules generate mocks for the same types.

To use a mock from another module in your tests, see [Cross-module mock generation](#cross-module-mock-generation).

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

Most projects use one of two cross-module mock setups:

1. Add `SafeDIGenerator` to each first-party target that owns types with `@Instantiable(generateMock: true)`. Use this when the module’s own tests or previews need mocks for its own types.
2. Add `additionalMocksToGenerate` in the consuming module. Use this when the current module needs a local generated `mock()` for a type defined in a dependency module.

For the second case, use the `additionalMocksToGenerate` parameter on [`#SafeDIConfiguration`](#safediconfiguration):

```swift
#SafeDIConfiguration(
    additionalMocksToGenerate: [
        "LoggingService",
        "UserStorageService",
    ]
)
```

This generates a `mock()` method for each listed type in the current module, even though the type is defined elsewhere. The type must be `@Instantiable` in its home module, but `generateMock: true` is not required there unless that home module also wants to generate its own mock.

List each type by its declared name, with enclosing types and without the module (`Outer.Inner`, not `MyModule.Outer.Inner`).

**Note:** `additionalDirectoriesToInclude` helps SafeDI scan source from Xcode project dependencies, but it does not generate mocks for those dependency modules. Use `additionalMocksToGenerate` when the current module needs a local mock for a dependency-module type.

## Conditional compilation

SafeDITool scans your source before the compiler runs, so it decides for itself which clauses of an `#if` block are active, using the compilation conditions your build integration reports:

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

- Platform conditions such as `os(iOS)`, `arch(arm64)`, `canImport(UIKit)`, `targetEnvironment(simulator)`, `swift(>=6.0)`, and `compiler(>=6.0)` are left to the compiler. SafeDITool scans every clause one of them could select, so declarations under `#if os(iOS)` and under its `#else` are both visible to code generation.

The reported conditions are taken as complete, so a condition your build defines but your integration does not report would make SafeDITool scan the wrong clause. To keep that from going unnoticed, every generated file begins by asserting each decision SafeDITool made about a block that declares something SafeDI scans for—an `@Instantiable` type, a dependency property, an `instantiate()` method, an initializer SafeDI could select to construct its type, or a `#SafeDIConfiguration`:

```swift
#if !(DEBUG)
#error("SafeDI scanned this module assuming `#if DEBUG` was active, but it is inactive in this compilation. Report the conditions this target compiles with to SafeDITool, as the \"Reporting active conditions\" section of the SafeDI manual describes for your build system.")
#endif
```

The compiler evaluates the same condition with the real build settings, so a mismatch fails the build at the generated file with a message naming the condition instead of producing code for the wrong configuration. Blocks that guard nothing SafeDI reads are not asserted.

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

A declaration that participates only in mock generation—an `@Instantiable(mockOnly: true)` type or extension, or a hand-written `mock()` or `customMockName` method—may be guarded by the module’s `mockConditionalCompilation` condition (`DEBUG` by default) without the build reporting it. SafeDITool evaluates such a block as if that condition were active, because the generated mock code that references the declaration is wrapped in the same `#if`, and emits no assertion for it. This keeps `#if DEBUG` around a `mockOnly` declaration working under every integration, including the Xcode project plugin. Setting `mockConditionalCompilation: nil` disables this exemption, since the generated mocks are then unconditional. The exemption never applies to production declarations, nor to other conditions guarding mock-only declarations.

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

- **From the build settings, when the build runs.** The `SafeDIGenerator` plugin passes `${SWIFT_ACTIVE_COMPILATION_CONDITIONS}` and `${OTHER_SWIFT_FLAGS}` to SafeDITool. A build system that expands them hands SafeDITool exactly the conditions the compiler receives, and SafeDITool uses those instead of any reported another way.
- **From what the plugin can see, while it plans the build.** A Swift package’s build tool plugin can read the target’s `swiftSettings` defines, including those with `.when(configuration:)` conditions, and its trait defines, but not SwiftPM’s implicit `DEBUG`. An Xcode project’s build tool plugin can read no conditions at all. When the build-setting references reach SafeDITool unexpanded, it uses these conditions instead.

| Integration | Conditions SafeDITool generates code with |
|-------------|-------------------------------------------|
| Swift package plugin, `swift build` with the Swift Build backend: the default in Swift 6.4, and `--build-system swiftbuild` in Swift 6.2 | The build settings. Verified with Swift 6.2 and Swift 6.4. |
| Swift package plugin, `swift build` with the native backend: the default in Swift 6.2, which ships with Xcode 26, and `--build-system native` in Swift 6.4. `swift build --help` names your toolchain’s default. | What the plugin can see. To guard a production declaration with `DEBUG`, add `.define("DEBUG", .when(configuration: .debug))` to the target’s `swiftSettings`, as the [Example Package Integration](../Examples/Example Package Integration/Package.swift) does. The define is harmless under the other build systems, which read the build settings instead. |
| Swift package plugin, built by Xcode | The build settings, in every configuration. Xcode hands the plugin a package’s `.when(configuration:)` defines as for a debug build whatever configuration it compiles, so the build settings correct what the plugin sees in Release. |
| Xcode project plugin | The build settings. |
| Tuist plugin and other prebuild scripts | The target’s `SWIFT_ACTIVE_COMPILATION_CONDITIONS` build setting, passed as `generate --active-compilation-conditions`. The Tuist plugin does not forward `-D` flags in `OTHER_SWIFT_FLAGS`; a script can pass both settings with the `--build-setting-…` options instead. |
| Bazel `safedi_swift_library` and `safedi_compile` | `DEBUG` in the `dbg` and `fastbuild` compilation modes, `NDEBUG` in the `opt` compilation mode, the target’s `defines`, each `-D` flag in the target’s `copts` (after Make variable expansion, so `-D$(NAME)` reports the value of `--define=NAME=…`), and each `-D` flag passed with `--@rules_swift//swift:copt` (`--@rules_swift//swift:exec_copt` for a target built in the exec configuration). `safedi_swift_library` gives its `swift_library` and its `<name>_safedi` target the same `defines` and `copts`; a hand-written `safedi_compile` must repeat the `defines` and `copts` of the `swift_library` that compiles its output. Not reported: `defines` propagated from a dependency, `--@rules_swift//swift:per_module_swiftcopt`, and copts configured on a custom Swift toolchain. `--copt` and `--define` alone do not reach the Swift compiler, so they never need reporting. |

The Swift package plugin scans the sources of a target’s dependencies with the target’s own conditions, so a condition that guards a production declaration in a dependency must be active on every target whose dependency tree reaches it.

#### Declarations that decide which files SafeDI generates

Roots, types that set `generateMock: true` or that `additionalMocksToGenerate` lists, and `#SafeDIConfiguration` may sit behind any condition, in every integration: SafeDI plans a generated file for each of them in every clause of every `#if` block, and writes the file with only its compile-time assertions when the build leaves the declaration inactive:

```swift
#if DEBUG
@Instantiable(isRoot: true)
public struct DebugMenu: Instantiable { … }
#endif
```

## Comparing SafeDI and Manual Injection: Key Differences

SafeDI is designed to be simple to adopt and minimize architectural changes required to get the benefits of a compile-time safe DI system. Despite this design goal, there are a few key differences between projects that utilize SafeDI and projects that don’t. As the benefits of this system are outlined in the README’s [Features](../README.md#features) section, this section outlines the pattern changes required to utilize a DI system like SafeDI.

### Instantiating objects

In a manual DI system it is common to directly call your dependencies’ `init(…)` functions. When utilizing SafeDI, you must rely on `@Instantiated`-decorated properties to instantiate your dependencies for you. Calling a dependency’s `init(…)` function directly effectively exits the SafeDI-built dependency tree, which removes property lifecycle guarantees. Similarly, you must call the generated `init()` function on your dependency tree’s root and not its memberwise `init(…)` function in order to create the SafeDI dependency tree.

To instantiate a dependency after a property’s enclosing type is initialized, you must utilize an instantiated or received [`Instantiator`](#delayed-instantiation) or [`LazilyInstantiated`](#lazilyinstantiated).

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
2. Update your SafeDI dependency to `from: "2.1.0"`
3. If you have `.safedi/configuration/include.csv` or `.safedi/configuration/additionalImportedModules.csv`, add a `#SafeDIConfiguration` in your root module with the equivalent values and delete the CSV files
4. If you don’t have CSV configuration files and do not need other SafeDI configuration options, no `#SafeDIConfiguration()` declaration is required

### Plugin changes

The `SafeDIPrebuiltGenerator` plugin has been removed in SafeDI 2.x. `SafeDIGenerator` is now the only build tool plugin and uses a prebuilt binary by default. If you were previously using `SafeDIPrebuiltGenerator`, switch to `SafeDIGenerator`. For users of the Xcode build plugin: the `InstallSafeDITool` command plugin still exists as an Xcode-only helper for the prebuilt-tool install flow described under _Installing the prebuilt SafeDITool binary_ above.

### Migrating prebuild scripts or custom build system integrations

If you invoke `SafeDITool` directly (not via the provided SPM plugin), the 1.x `--dependency-tree-output` flag has been replaced. The simplest migration is `generate --combined-output`, which concatenates every dependency-tree, mock, and mock-configuration body SafeDITool would emit into one statically-known output file — a good fit for any build system that needs rule outputs declared up front.

Before (1.x):
```bash
safeditool input.csv --dependency-tree-output ./generated/SafeDI.swift
```

After (2.x), single module:
```bash
safeditool generate input.csv --combined-output ./generated/SafeDI.swift
```

For multi-module projects, you can add the `--module-info-output` flag so downstream modules can resolve `@Instantiable` types declared upstream without re-parsing the producer's sources. Each producer emits a `.safedi` sidecar; each consumer feeds the producer's `.safedi` back in through `--dependent-module-info-file-path`:

```bash
# Producing module (Subproject):
safeditool generate Subproject.csv \
  --combined-output Subproject/SafeDIGenerated.swift \
  --module-info-output Subproject.safedi

# Consuming module (App), with Subproject already built:
echo "Subproject.safedi" > deps.csv
safeditool generate App.csv \
  --combined-output App/SafeDIGenerated.swift \
  --module-info-output App.safedi \
  --dependent-module-info-file-path deps.csv
```

Given the same input files, `generate` writes the same `.safedi` bytes every time, so a build cache keyed on them stays warm. `query needs --module-info` reads the same files, so a project that writes them can [query what a type needs](#querying-what-a-type-needs) with [the `SafeDITool` its build runs](#running-safeditool-yourself), without parsing its sources again. A `.safedi` file names each file by the path the input CSV gives it, so a CSV of relative paths, like those the Bazel rule and the Tuist plugin write, keeps absolute paths out of it.

A `.safedi` file is binary, and `SafeDITool` reads only those written by a `SafeDITool` that lays them out the same way. After upgrading SafeDI, regenerate each producer’s `.safedi` before its consumers run: a consumer handed one it cannot read fails with an error that names the file.

For working reference implementations, see the Bazel rule and macro at [`bazel/safedi.bzl`](../bazel/safedi.bzl) and the Tuist plugin at [`TuistPlugins/SafeDITuist/ProjectDescriptionHelpers/SafeDI.swift`](../TuistPlugins/SafeDITuist/ProjectDescriptionHelpers/SafeDI.swift). Both invoke `generate --combined-output --module-info-output` per module and pass dependent modules' `.safedi` artifacts via `--dependent-module-info-file-path`.

If you need one generated `.swift` per source file that declares a root instead of a single combined file, use `generate --swift-manifest` with a JSON manifest in the [`SafeDIToolManifest`](../Sources/SafeDICore/Models/SafeDIToolManifest.swift) format. Give each output its own file; SafeDITool rejects a manifest in which two outputs name one file. `--swift-manifest` and `--combined-output` are mutually exclusive — pick whichever maps better onto your build system’s output model.

## Example applications

We’ve tied everything together with an example multi-user notes application backed by SwiftUI. You can compile and run this code in [an example single-module Xcode project](../Examples/ExampleProjectIntegration). This same multi-user notes app also exists in [an example multi-module Xcode project](../Examples/ExampleMultiProjectIntegration). We have also created [an example multi-module `Package.swift` that integrates with SafeDI](../Examples/Example Package Integration).

## Under the hood

SafeDI has a `SafeDITool` executable that the `SafeDIGenerator` plugin utilizes to read code and generate a dependency tree. The executable heavily utilizes asynchronous processing to avoid `SafeDITool` becoming a bottleneck in your build. Additionally, we only parse a Swift file with `SwiftSyntax` when the file contains `@Instantiable` or `#SafeDIConfiguration`.

The `SafeDIGenerator` plugin is the only build tool plugin and uses a prebuilt binary by default for fast builds without compiling SwiftSyntax. Due to limitations in Apple’s [Swift Package Manager Plugins](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/Plugins.md), the plugin parses all of your first-party Swift files in a single pass. Projects that utilize `SafeDITool` directly can process Swift files on a per-module basis to further reduce the build-time bottleneck.

### Custom build system integration

If you are integrating SafeDI with a build system other than SPM (e.g. Bazel, Buck, or a prebuild script), you can invoke `SafeDITool` directly using the `scan` and `generate` subcommands:

- **`generate`** (default): Parses Swift source files, builds a dependency graph, validates it, and generates one `.swift` per source file that declares a root, and mock code. `generate` takes a JSON manifest file describing the desired outputs — the manifest uses the [`SafeDIToolManifest`](../Sources/SafeDICore/Models/SafeDIToolManifest.swift) format, mapping input Swift files containing `@Instantiable(isRoot: true)` to output file paths (relative to the working directory). `generate` writes every output the manifest lists, and writes one without code when its input declares no root under the active compilation conditions. This is the default subcommand, making it backward compatible with existing prebuild scripts that invoke `SafeDITool` without an explicit subcommand.
- **`scan`**: Scans Swift source files and produces a manifest JSON describing the `@Instantiable` types found. This is used by the `SafeDIGenerator` plugin to coordinate builds across modules, and is also useful for per-module scanning in custom build systems.

Both subcommands utilize Apple’s [SwiftSyntax](https://github.com/apple/swift-syntax) library to parse your code and find your `@Instantiable` types’ initializers and dependencies. With this information, SafeDI generates a graph of your project’s dependencies and validates it during `SafeDITool` execution. If the graph is invalid, `SafeDITool` reports each problem as a compiler diagnostic at the declaration that caused it, offers an unambiguous repair as a fix-it, and exits non-zero. Each root's tree, and each mocked type's, reports the first problem it finds, and the problems of all of them are reported together, ordered by file, line, and column. Source code is only generated if the dependency graph is valid.

Generated code points a renamed dependency’s assignment at its `@Received` declaration with a `#sourceLocation` directive only when SafeDITool knows the exact path the compiler is handed for each file: under the `SafeDIGenerator` plugin, or with `generate --compiler-receives-input-paths-unchanged`, which a build system that hands the compiler every Swift file at exactly the path it hands SafeDITool may pass (the vended Bazel rule does). Otherwise each such assignment ends in a comment naming the declaration’s file and line.

SafeDITool prints diagnostics at paths resolved against its working directory, which under Bazel is the action’s sandbox.

Run `SafeDITool`, as [Running SafeDITool yourself](#running-safeditool-yourself) describes for your integration, with `--help`, `scan --help`, or `generate --help` to see documentation of all supported arguments, `query needs --help` for the command that [reports what types need](#querying-what-a-type-needs) (in beta), and `dump --help` for the command that prints a `.safedi` file, or the cache `scan` writes beside its manifest, as JSON.

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

A project whose build already writes `.safedi` [module info files](#custom-build-system-integration) – a Bazel or Tuist project, or any other that runs `generate --module-info-output` per module – can name those files with `--module-info`, instead of or alongside directories, and skip parsing the sources. In a Bazel project:

```bash
bazel run @safedi//bazel:safeditool -- query needs HomeFeature --module-info "$PWD"/bazel-bin/Modules/Foundations/Foundations_safedi.safedi "$PWD"/bazel-bin/Modules/Services/Services_safedi.safedi "$PWD"/bazel-bin/Modules/HomeFeature/HomeFeature_safedi.safedi
```

For each type named, the query builds the type as its `mock()` does, with every dependency it receives provided by an `@Instantiable` declaration, and reports:

- The modules the type is built from in production, each with the declarations that build it.
- The `@Forwarded` parameters of the type.
- The dependencies no `@Instantiable` declaration fulfills, which the project provides by hand, each with its reason.

It then reports the same for the type’s mock. [The `query needs` report](QueryNeeds.md) describes which modules and which mock the report covers, how to name the types, and the JSON that `--json` prints for scripts.
