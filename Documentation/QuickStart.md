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

Add SafeDI to the package’s dependencies. Add its `SafeDI` library and its `SafeDIGenerator` build tool plugin to each target that declares SafeDI types: here, `Networking`, `Profile`, and `Root`.

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
+            dependencies: ["SafeDI"],
+            plugins: [.plugin(name: "SafeDIGenerator", package: "SafeDI")]
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

When you build, the plugin reads the target’s code and the code of the targets it depends on in your package, checks the dependency tree, and generates the code that builds it. The plugin generates nothing for `Networking`, which declares no root and no type with `generateMock: true`, but with the plugin already there, you don’t edit `Package.swift` when `Networking` gains one.

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

- `@Instantiated`: SafeDI creates a new instance when it creates the type that declares it.
- `@Received`: SafeDI passes in the instance that a type above it in the tree instantiated or forwarded, with the same name and type. Use it to share one instance without passing it through every type in between. If no type above provides it, SafeDI reports an error when you build.
- `@Forwarded`: your code passes the value in when it creates the type, as step 3 shows. Use it for a value that exists only at runtime, such as the signed-in user.

In `AvatarLoader`, mark `apiClient` `@Received`: it receives the one `APIClient` that the root, `RootView`, instantiates in step 3. In `Sources/Profile/AvatarLoader.swift`:

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

In `ProfileView`, mark `user` `@Forwarded`, because a user exists only once someone signs in. Mark `avatarLoader` `@Instantiated`, because each `ProfileView` creates its own. Add `generateMock: true`, so that SafeDI generates `ProfileView.mock(…)`, and add a preview that calls it. [Step 4](#4-use-mocks-in-tests-and-previews) explains mocks. In `Sources/Profile/ProfileView.swift`:

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

Don’t add `apiClient` to `ProfileView`. `AvatarLoader` receives it from `RootView`, above `ProfileView` in the tree, so `ProfileView` doesn’t pass it along.

## 3. Mark the root and build the tree

Mark the root, the type at the top of the tree, `@Instantiable(isRoot: true)`. The root is the one type in the tree that your own code creates, by calling an `init()` with no arguments. SafeDI generates that `init()`, and it builds everything below the root. No type above the root passes it anything, so a root can’t receive or forward a dependency, and the `@Instantiable` macro reports one as you type. Here, the root is `RootView`. In it:

- Replace the hand-written `init()` with an initializer that takes each dependency. The generated `init()` creates the dependencies and calls it.
- Mark `apiClient` `@Instantiated`. `RootView` doesn’t use it itself, but `AvatarLoader`, below it, receives it.
- Replace the code that creates a `ProfileView` with an `@Instantiated` `Instantiator<ProfileView>`, and call its `instantiate(_:)` with the user. `RootView` can’t be given a finished `ProfileView` when it is created, because no user exists until someone signs in. An [`Instantiator`](Manual.md#instantiator) builds a `ProfileView` each time you call `instantiate(_:)`: you pass the forwarded `user`, and SafeDI builds the rest. If a type in the tree declares a plain `@Instantiated` `ProfileView` in place of an `Instantiator<ProfileView>`, SafeDI reports an error when you build.

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

Without its header and imports, the code SafeDI generates for `RootView` is:

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

Leave your app target, which shows `RootView` by calling `RootView()`, as it is. It depends on the package’s `Root` library, and that call reaches the `init()` SafeDI generates in place of the one you removed. The app target declares no SafeDI types, so it needs no plugin.

In your own app, the root can be a view in a module, as here. In a SwiftUI app, you can make the `App` type the root instead, if SafeDI runs on the app target. In a UIKit app, make the root a class that your app delegate creates and stores: the app delegate can’t be the root, because it already has a no-argument `init()` from `NSObject`. See [Creating the root of your dependency tree](Manual.md#creating-the-root-of-your-dependency-tree).

### Access across modules

SafeDI generates the code that builds `RootView`’s tree in `Root`, and `ProfileView`’s mock in `Profile`. That code calls each type’s initializer, so give each type it builds, and the type’s initializer, enough access for that module to call it:

- A type declared in the same module can stay `internal`.
- Within one Swift package, a type from another module needs `package` or `public` access. Here, those types are `public`.
- Outside a Swift package, `package` access works only when every module is compiled with one package name, which each section of [Other build systems](#other-build-systems) says how to set. Otherwise, use `public`.

SafeDI reports each type or initializer that needs wider access, and names the change to make.

## 4. Use mocks in tests and previews

Because `ProfileView` has `generateMock: true`, SafeDI generates `ProfileView.mock(…)`. A mock builds one type and everything below it without a root, so a preview or a test can show `ProfileView` on its own. Pass the mock what it can’t build, here the forwarded `user`. The mock builds the rest, including the `APIClient` that `AvatarLoader` receives, which in the app comes from `RootView`. By default, SafeDI wraps each mock in `#if DEBUG`, so put a preview that calls one inside `#if DEBUG`, as `ProfileView.swift` above does.

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

To change how the mock builds a dependency, such as the `APIClient` that `AvatarLoader` receives, pass `safeDIOverrides`, as [Overriding dependencies](Manual.md#overriding-dependencies) describes.

## Other build systems

Steps 2 to 4 are the same in every build system. Step 1, adding SafeDI to the build, differs, and so does how you set up `package` access. Each section below covers both.

### Xcode projects

If your modules are framework targets in an `.xcodeproj`, choose one of two routes:

- **Move the modules into a local Swift package.** Create a package like the one above, and move each module’s files into `Sources/<module name>`. Keep the app target in the project, add the package to the project, and add the package’s `Root` library to the app target. Choose this route for new work: it has none of the next route’s limits.
- **Keep the framework targets.** Apply the plugin to each target that declares SafeDI types. The Xcode project plugin can’t find the source files of the targets a target depends on, so give each target you apply the plugin to a `SafeDIConfiguration.swift` whose `additionalDirectoriesToInclude` lists the folders of the targets it depends on, as [Xcode project](Manual.md#xcode-project) describes. The plugin also can’t tell which target declares each type, so give each type that another target builds, and its initializer, `package` or `public` access. For `package` access, set `SWIFT_PACKAGE_NAME` to one name on every target. SafeDI reports each declaration that is too narrow. [Limits of the Xcode project plugin](Manual.md#limits-of-the-xcode-project-plugin) lists the plugin’s other limits.

### Bazel

Add SafeDI to your `MODULE.bazel`:

```diff
 bazel_dep(name = "rules_swift", version = "3.6.1")
+bazel_dep(name = "safedi", version = "2.2.0")
```

Declare every module with `safedi_swift_library` in place of `swift_library`, `Networking` included: under Bazel, SafeDI reads only the modules it runs on. Beside each library, `safedi_swift_library` declares a target named after it with `_safedi` added, such as `Networking_safedi`, which runs SafeDI on the module and records the types it declares. In each module, add `@safedi//:SafeDI` to `deps`, and list the `_safedi` target of each module it depends on directly in `safedi_deps`, so that SafeDI reads the types those modules declare.

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

SafeDI’s `SafeDITuist` plugin provides the script that runs SafeDI on each module before the module compiles. Declare the plugin in `Tuist.swift`. Tuist can’t load the plugin by tag, so name the commit of the SafeDI version you use, which `git ls-remote https://github.com/dfed/SafeDI refs/tags/<version>` prints:

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

Depend on the same SafeDI version in `Tuist/Package.swift`, so that `tuist install` fetches the SafeDI library and the prebuilt `SafeDITool` the script runs:

```diff
 let package = Package(
-    name: "MyApp"
+    name: "MyApp",
+    dependencies: [
+        .package(url: "https://github.com/dfed/SafeDI.git", from: "2.2.0"),
+    ]
 )
```

In `Project.swift`, import `SafeDITuist`, and give each module three things: `SafeDI.generatedSource`, the file the script writes the module’s generated code to; `SafeDI.preCompileScript`, the script; and a dependency on SafeDI. Give these to every module, `Networking` included: under Tuist, SafeDI reads only the modules it runs on. In the script’s `dependencies`, list the modules whose types SafeDI reads for that module: the modules it depends on directly, and, for a module that declares a root, every module it depends on through other modules too, because the root’s tree can build their types.

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

Leave the project’s list of modules as it is. With the change above, each module’s `dependencies` also tell its script which modules to read. `Root` depends directly on both modules below it, so its list is complete:

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
