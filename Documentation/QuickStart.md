# SafeDI Quick Start

This guide adds SafeDI to an app whose code is split into modules. It starts from a small app with three modules that does not use SafeDI yet:

- `Networking`, which declares an `APIClient`.
- `Profile`, a feature module, which declares a `ProfileView`, the `AvatarLoader` it uses, and a `User` model.
- `Root`, which declares the app’s root view.

The types below the root view already take their dependencies in their initializers, and the root view creates them by hand. By the end, SafeDI writes the code that creates them.

Each step that changes a file shows the change as a diff. Add the green lines, which start with `+`. Remove the red lines, which start with `-`. The other lines stay as they are, and show where the change goes.

The modules live in a Swift package. [Other build systems](#other-build-systems) covers Xcode projects, Bazel, and Tuist. The [Manual](Manual.md) is the reference for everything this guide touches.

SafeDI needs Swift 6.2 or later, which ships with Xcode 26.

## 1. Add SafeDI to your package

The package has this layout:

```
MyAppPackage/
├── Package.swift
├── Sources/
│   ├── Networking/
│   │   └── APIClient.swift
│   ├── Profile/
│   │   ├── AvatarLoader.swift
│   │   ├── ProfileView.swift
│   │   └── User.swift
│   └── Root/
│       └── RootView.swift
└── Tests/
    └── ProfileTests/
        └── ProfileViewTests.swift
```

Add SafeDI to the package’s dependencies, and its `SafeDI` library to each target that declares SafeDI types. Apply the `SafeDIGenerator` build tool plugin to each target that declares a root or a type with `generateMock: true`. Here, those are `Profile` and `Root`. `Networking` declares neither, so it needs only the library.

In `Package.swift`:

```diff
     products: [
         .library(name: "Root", targets: ["Root"]),
     ],
+    dependencies: [
+        .package(url: "https://github.com/dfed/SafeDI.git", from: "2.2.0"),
+    ],
     targets: [
         .target(
-            name: "Networking"
+            name: "Networking",
+            dependencies: ["SafeDI"]
         ),
         .target(
             name: "Profile",
-            dependencies: ["Networking"]
+            dependencies: ["Networking", "SafeDI"],
+            plugins: [.plugin(name: "SafeDIGenerator", package: "SafeDI")]
         ),
         .target(
             name: "Root",
-            dependencies: ["Networking", "Profile"]
+            dependencies: ["Networking", "Profile", "SafeDI"],
+            plugins: [.plugin(name: "SafeDIGenerator", package: "SafeDI")]
         ),
```

When you build, the plugin reads the target’s code and the code of the targets it depends on in your package, checks the dependency tree, and generates the code that builds it. If you later add `generateMock: true` to a type in `Networking`, add the plugin to `Networking` too.

## 2. Mark the types in your dependency tree

Mark each type you want SafeDI to create with `@Instantiable`. Here, that’s `APIClient`, `AvatarLoader`, and `ProfileView`. For each one:

- Make it conform to `Instantiable`.
- Give it an initializer that takes each of its dependencies, with the property’s label and type. The types here already have one.

`@Instantiable` checks both as you type, and offers a fix-it that adds whatever is missing.

`APIClient` has no dependencies, so it needs only the macro and the conformance. In `Sources/Networking/APIClient.swift`:

```diff
 import Foundation
+import SafeDI
 
-public final class APIClient: Sendable {
+@Instantiable
+public final class APIClient: Instantiable, Sendable {
     public init() {}
```

Leave `User`, in `Profile`, as it is. It is a plain model, not a SafeDI type. SafeDI creates the types in your tree from one another, when the tree is built. A `User` can't be made that way: it holds data that exists only once the app is running and someone signs in, so `RootView` creates it then. Your code creates a value like this and passes it into the tree, as `ProfileView`’s forwarded `user` shows below.

```swift
// Sources/Profile/User.swift
public struct User: Sendable {
    public init(name: String) {
        self.name = name
    }

    public let name: String
}
```

Mark each property that holds a dependency with how it gets its value:

- `@Instantiated`: SafeDI creates it when it creates the type that declares it.
- `@Received`: the type takes the instance that a type above it in the tree instantiated or forwarded, with the same name and type.
- `@Forwarded`: a value your code has only at runtime, such as the signed-in user. The code that creates the type passes it in.

In `AvatarLoader`, mark `apiClient` `@Received`: it takes the `APIClient` that a type above it instantiates. In `Sources/Profile/AvatarLoader.swift`:

```diff
 import Foundation
 import Networking
+import SafeDI
 
-public final class AvatarLoader {
+@Instantiable
+public final class AvatarLoader: Instantiable {
     public init(apiClient: APIClient) {
         self.apiClient = apiClient
     }
 
     public func avatarURL(for user: User) -> URL? {
         apiClient.url(for: "avatars/\(user.name)")
     }
 
-    private let apiClient: APIClient
+    // Received from the type above that instantiates an `APIClient`.
+    @Received private let apiClient: APIClient
 }
```

In `ProfileView`, mark `user` `@Forwarded` and `avatarLoader` `@Instantiated`. Add `generateMock: true` and a preview that calls the mock, which [step 4](#4-use-mocks-in-tests-and-previews) explains. In `Sources/Profile/ProfileView.swift`:

```diff
+import SafeDI
 import SwiftUI
 
-public struct ProfileView: View {
+@Instantiable(generateMock: true)
+public struct ProfileView: View, Instantiable {
     public init(user: User, avatarLoader: AvatarLoader) {
         self.user = user
         self.avatarLoader = avatarLoader
     }
 
     public var body: some View {
         VStack {
             AsyncImage(url: avatarLoader.avatarURL(for: user))
             Text(user.name)
         }
     }
 
-    let user: User
+    // Passed in at runtime by the code that shows this view.
+    @Forwarded let user: User
 
-    let avatarLoader: AvatarLoader
+    // Created when this view is created.
+    @Instantiated let avatarLoader: AvatarLoader
 }
+
+#if DEBUG
+#Preview {
+    ProfileView.mock(user: User(name: "Ada"))
+}
+#endif
```

`ProfileView` never mentions `APIClient`. `AvatarLoader` receives it from the root, above `ProfileView` in the tree, so `ProfileView` does not pass it along.

## 3. Mark the root and build the tree

Mark the root, the type at the top of the tree, `@Instantiable(isRoot: true)`. SafeDI builds the root and everything below it. Here, the root is `RootView`. In it:

- Replace the hand-written `init()` with an initializer that takes its dependencies. SafeDI generates an `init()` that creates them.
- Mark `apiClient` `@Instantiated`.
- Replace the code that creates a `ProfileView` with an `@Instantiated` `Instantiator<ProfileView>`, and call its `instantiate(_:)` with the user.

In `Sources/Root/RootView.swift`:

```diff
 import Networking
 import Profile
+import SafeDI
 import SwiftUI
 
-public struct RootView: View {
-    public init() {
-        apiClient = APIClient()
+@Instantiable(isRoot: true)
+public struct RootView: View, Instantiable {
+    public init(apiClient: APIClient, profileViewBuilder: Instantiator<ProfileView>) {
+        self.apiClient = apiClient
+        self.profileViewBuilder = profileViewBuilder
     }
 
     public var body: some View {
         if let user {
-            ProfileView(user: user, avatarLoader: AvatarLoader(apiClient: apiClient))
+            profileViewBuilder.instantiate(user)
         } else {
             Button("Sign in") {
                 user = User(name: "Ada")
             }
         }
     }
 
-    private let apiClient: APIClient
+    // One `APIClient` for the whole tree. Any type below can receive it.
+    @Instantiated let apiClient: APIClient
 
+    // Builds a `ProfileView` each time `instantiate(_:)` is called with a `User`.
+    @Instantiated let profileViewBuilder: Instantiator<ProfileView>
+
     @State private var user: User?
 }
```

`RootView` never uses `apiClient` itself. It instantiates it because `AvatarLoader`, below it, can receive only what a type above it instantiates or forwards.

SafeDI builds a type that has a `@Forwarded` property, like `ProfileView`, only through an [`Instantiator`](Manual.md#instantiator): `instantiate(_:)` takes the forwarded values, and SafeDI builds the rest.

For a root, SafeDI generates a `public init()` with no parameters, which builds the whole tree. Without its header and imports, the code SafeDI generates for `RootView` is:

```swift
extension RootView {
    public init() {
        let apiClient = APIClient()
        func __safeDI_profileViewBuilder(user: User) -> ProfileView {
            let avatarLoader = AvatarLoader(apiClient: apiClient)
            return ProfileView(user: user, avatarLoader: avatarLoader)
        }
        let profileViewBuilder = Instantiator<ProfileView> {
            __safeDI_profileViewBuilder(user: $0)
        }
        self.init(apiClient: apiClient, profileViewBuilder: profileViewBuilder)
    }
}
```

It creates one `APIClient`. The local function takes a `User` and builds a `ProfileView` with a new `AvatarLoader`, which gets that `APIClient`. The `Instantiator` calls the function each time `instantiate(_:)` runs. Then the `init()` calls the initializer you wrote. [Finding the generated code](Manual.md#finding-the-generated-code) says where to read the whole file.

Leave your app target’s code as it is. The app target depends on the package’s `Root` library, and its `RootView()` now calls the initializer SafeDI generates.

```swift
import Root
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            // `RootView()` is the initializer SafeDI generates. It builds the whole tree.
            RootView()
        }
    }
}
```

The app target declares no SafeDI types, so it needs no plugin.

In your own app, the root can be a view in a module, as here. A SwiftUI app whose app target runs SafeDI can make its `App` type the root instead. A UIKit app makes the root a class that its app delegate creates and stores. See [Creating the root of your dependency tree](Manual.md#creating-the-root-of-your-dependency-tree).

### Access across modules

Make every type in the tree, and its initializer, visible from `Root`, where SafeDI generates the code that builds `RootView`’s tree. Here, the types other modules declare are `public`. Within one Swift package, `package` access is enough, and a type that only its own module builds can stay `internal`. For modules outside a Swift package, such as Xcode framework targets or Bazel and Tuist modules, `package` access works only when you give the modules one package name, as [Access levels](Manual.md#access-levels) describes; otherwise, use `public`. SafeDI reports a type that is not visible enough when you build.

## 4. Use mocks in tests and previews

Call `ProfileView.mock(…)` in previews and tests. SafeDI generates it because `ProfileView` has `generateMock: true`. The mock builds `ProfileView`’s whole tree, including the `APIClient` that `AvatarLoader` receives, and takes `ProfileView`’s forwarded `user` as a parameter. By default, mocks are compiled only in `DEBUG` builds, so put a preview that calls one inside `#if DEBUG`, as `ProfileView.swift` above does.

Call it the same way in a test. The mock is `internal`, so import `Profile` with `@testable`:

```swift
// Tests/ProfileTests/ProfileViewTests.swift
@testable import Profile
import Testing

@MainActor
@Test func profileView_showsTheForwardedUser() {
    let view = ProfileView.mock(user: User(name: "Ada"))
    #expect(view.user.name == "Ada")
}
```

To replace a dependency inside the tree, such as a stub `APIClient`, pass `safeDIOverrides`, as [Overriding dependencies](Manual.md#overriding-dependencies) describes.

## Other build systems

The steps above work the same way in every build system, except for adding SafeDI to the build.

### Xcode projects

If your modules are framework targets in an `.xcodeproj`, choose one of two routes:

- **Move the modules into a local Swift package.** Create a package like the one above, and move each module’s files into `Sources/<module name>`. Keep the app target in the project, add the package to the project, and add the package’s `Root` library to the app target. Choose this route for new work: it has none of the limits below.
- **Keep the framework targets.** Apply the plugin to each target that declares a root or a type with `generateMock: true`, and give each of those targets a `SafeDIConfiguration.swift` that lists the folders of the targets it depends on, as [Xcode project](Manual.md#xcode-project) describes. The Xcode project plugin cannot tell which target declares each type, so give each type that another target builds, and its initializer, `package` or `public` access, and for `package` access set `SWIFT_PACKAGE_NAME` to one name on every target. SafeDI reports a declaration that is too narrow. [Limits of the Xcode project plugin](Manual.md#limits-of-the-xcode-project-plugin) lists the plugin’s other limits.

### Bazel

Add SafeDI to your `MODULE.bazel`:

```diff
 bazel_dep(name = "rules_swift", version = "3.6.1")
+bazel_dep(name = "safedi", version = "2.2.0")
```

Declare each module with `safedi_swift_library` in place of `swift_library`. Under Bazel, SafeDI runs on every module, so `Networking` uses it too. Give each module a `module_name`, so that `import Networking` finds it. In each module, list each module it depends on directly in `deps`, and that module’s `_safedi` target in `safedi_deps`.

In `Networking/BUILD.bazel`:

```diff
-load("@rules_swift//swift:swift.bzl", "swift_library")
+load("@safedi//bazel:safedi.bzl", "safedi_swift_library")
 
-swift_library(
+safedi_swift_library(
     name = "Networking",
     srcs = glob(["*.swift"]),
     module_name = "Networking",
     visibility = ["//visibility:public"],
+    deps = ["@safedi//:SafeDI"],
 )
```

In `Profile/BUILD.bazel`:

```diff
-load("@rules_swift//swift:swift.bzl", "swift_library")
+load("@safedi//bazel:safedi.bzl", "safedi_swift_library")
 
-swift_library(
+safedi_swift_library(
     name = "Profile",
     srcs = glob(["*.swift"]),
     module_name = "Profile",
+    safedi_deps = ["//Networking:Networking_safedi"],
     visibility = ["//visibility:public"],
-    deps = ["//Networking"],
+    deps = [
+        "//Networking",
+        "@safedi//:SafeDI",
+    ],
 )
```

In `Root/BUILD.bazel`:

```diff
-load("@rules_swift//swift:swift.bzl", "swift_library")
+load("@safedi//bazel:safedi.bzl", "safedi_swift_library")
 
-swift_library(
+safedi_swift_library(
     name = "Root",
     srcs = glob(["*.swift"]),
     module_name = "Root",
+    safedi_deps = [
+        "//Networking:Networking_safedi",
+        "//Profile:Profile_safedi",
+    ],
     visibility = ["//visibility:public"],
     deps = [
         "//Networking",
         "//Profile",
+        "@safedi//:SafeDI",
     ],
 )
```

For `package` access, give the three modules the same `package_name`. [Bazel](Manual.md#bazel) has the details.

### Tuist

Declare SafeDI’s `SafeDITuist` plugin in `Tuist.swift`. Tuist cannot load the plugin by tag, so name the commit of the SafeDI version you use, which `git ls-remote https://github.com/dfed/SafeDI refs/tags/<version>` prints:

```diff
 let tuist = Tuist(
-    project: .tuist()
+    project: .tuist(
+        plugins: [
+            .git(url: "https://github.com/dfed/SafeDI", sha: "<commit>", directory: "TuistPlugins/SafeDITuist"),
+        ]
+    )
 )
```

Depend on the same SafeDI version in `Tuist/Package.swift`:

```diff
 let package = Package(
-    name: "MyApp"
+    name: "MyApp",
+    dependencies: [
+        .package(url: "https://github.com/dfed/SafeDI.git", from: "2.2.0"),
+    ]
 )
```

In `Project.swift`, give each module SafeDI’s generated source and its pre-compile script. Under Tuist, SafeDI runs on every module, so `Networking` has them too. In the script’s `dependencies`, list the modules SafeDI reads for that module: the modules it depends on directly, and, for a module that declares a root, every module beneath it.

```diff
 import ProjectDescription
+import SafeDITuist
 
 func module(_ name: String, dependencies: [String] = []) -> Target {
     .target(
         name: name,
         destinations: .iOS,
         product: .framework,
         bundleId: "com.example.\(name)",
         deploymentTargets: .iOS("17.0"),
-        sources: ["\(name)/**/*.swift"],
-        dependencies: dependencies.map { .target(name: $0) }
+        sources: .sourceFilesList(globs: [
+            .glob("\(name)/**/*.swift"),
+            SafeDI.generatedSource,
+        ]),
+        scripts: [
+            SafeDI.preCompileScript(module: name, dependencies: dependencies),
+        ],
+        dependencies: dependencies.map { .target(name: $0) } + [.external(name: "SafeDI")]
     )
 }
```

Leave the project’s list of modules as it is. Each module’s `dependencies` now also tell its script which modules to read:

```swift
let project = Project(
    name: "MyApp",
    targets: [
        module("Networking"),
        module("Profile", dependencies: ["Networking"]),
        module("Root", dependencies: ["Networking", "Profile"]),
    ]
)
```

Then run `tuist install` and `tuist generate`. For `package` access, set `SWIFT_PACKAGE_NAME` to one name in every project. [Tuist](Manual.md#tuist) has the details, and [Which modules to list](Manual.md#which-modules-to-list) says what each script lists.

## Where to look next

The Manual is a reference: look up what you need rather than reading it end to end.

- [Macros](Manual.md#macros): everything `@Instantiable` and the property macros accept, including protocols and types you do not own.
- [Delayed instantiation](Manual.md#delayed-instantiation): `Instantiator` and `LazilyInstantiated`.
- [Mock generation](Manual.md#mock-generation): overriding dependencies in a mock, and mocks other modules call.
- [Adopting SafeDI in a large codebase](Manual.md#adopting-safedi-in-a-large-codebase): adopting SafeDI module by module, and generating a module’s tree in that module.
- [Finding the generated code](Manual.md#finding-the-generated-code): where to read what SafeDI generated.
- [Example applications](Manual.md#example-applications): a working project for each build system.
