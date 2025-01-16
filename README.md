# SafeDI

[![CI Status](https://img.shields.io/github/actions/workflow/status/dfed/SafeDI/ci.yml?branch=main)](https://github.com/dfed/SafeDI/actions?query=workflow%3ACI+branch%3Amain)
[![codecov](https://codecov.io/gh/dfed/SafeDI/branch/main/graph/badge.svg)](https://codecov.io/gh/dfed/SafeDI)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://spdx.org/licenses/MIT.html)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fdfed%2FSafeDI%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/dfed/SafeDI)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fdfed%2FSafeDI%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/dfed/SafeDI)

Compile-time-safe dependency injection for Swift projects. SafeDI provides developers with the safety and simplicity of manual dependency injection, without the overhead of boilerplate code.

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

## The core concept

SafeDI reads your code, validates your dependencies, and generates a dependency tree—all during project compilation. If your code compiles, your dependency tree is valid.

Opting a type into the SafeDI dependency tree is simple: add the `@Instantiable` macro to your type declaration, and decorate your type’s dependencies with macros to indicate the lifecycle of each property. Here is what a `Boiler` in a `CoffeeMaker` might look like in SafeDI:

```swift
// The boiler type is opted into SafeDI because it has been decorated with the `@Instantiable` macro.
@Instantiable
public final class Boiler {
    public init(pump: Pump, waterReservoir: WaterReservoir) {
        self.pump = pump
        self.waterReservoir = waterReservoir
    }

    …

    // The boiler creates, or in SafeDI parlance ‘instantiates’, its pump.
    @Instantiated private let pump: Pump
    // The boiler receives a reference to a water reservoir that has been instantiated by the coffee maker.
    @Received private let waterReservoir: WaterReservoir
}
```

That is all it takes! SafeDI utilizes macro decorations on your existing types to define your dependency tree. For a comprehensive explanation of SafeDI’s macros and their usage, please read [the Macros section of our manual](Documentation/Manual.md#macros).

## Getting started

SafeDI utilizes both Swift macros and a code generation plugin to read your code and generate a dependency tree. To integrate SafeDI, follow these three steps:

1. [Add SafeDI as a dependency to your project](#adding-safedi-as-a-dependency)
1. [Integrate SafeDI’s code generation into your build](#generating-your-dependency-tree)
1. [Create your dependency tree using SafeDI’s macros](Documentation/Manual.md)

You can see sample integrations in the [Examples folder](Examples/). If you are migrating an existing project to SafeDI, follow our [migration guide](Documentation/Manual.md#migrating-to-safedi).

### Adding SafeDI as a Dependency

#### Swift package manager

To add the SafeDI framework as a dependency to a package utilizing [Swift Package Manager](https://github.com/apple/swift-package-manager), add the following lines to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/dfed/SafeDI.git", from: "1.0.0"),
]
```

To install the SafeDI framework into an Xcode project with Swift Package Manager, follow [Apple’s instructions](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) to add `https://github.com/dfed/SafeDI.git` as a dependency.

#### CocoaPods

To add the SafeDI framework as a dependency to a package utilizing [CocoaPods](http://cocoapods.org), add the following to your `Podfile`:

```ruby
pod 'SafeDI', '~> 1.0.0'
```

### Generating your dependency tree

SafeDI provides a code generation plugin named `SafeDIGenerator`. This plugin works out of the box on a limited number of project configurations. If your project does not fall into these well-supported configurations, you can configure your build to utilize the `SafeDITool` command-line executable directly.

#### Swift package manager

##### Xcode projects

If your first-party code comprises a single module in an `.xcodeproj`, once your Xcode project depends on the SafeDI package you can integrate the Swift Package Plugin simply by going to your target’s `Build Phases`, expanding the `Run Build Tool Plug-ins` drop-down, and adding the `SafeDIGenerator` as a build tool plug-in. You can see this integration in practice in the [ExampleProjectIntegration](Examples/ExampleProjectIntegration) project.

If your Xcode project comprises multiple modules, follow the above steps, and then also create a `.safedi/configuration/include.csv` file containing a comma-separated list of folders containing Swift source files in non-root modules to parse. The `.safedi/` folder must be placed in the same folder as your `*.xcodeproj`, and the paths must be relative to the same folder. You can see this integration in practice in the [ExampleMultiProjectIntegration](Examples/ExampleMultiProjectIntegration) project. To ensure that generated SafeDI code includes imports to all of your required modules, you can create a `.safedi/configuration/additionalImportedModules.csv` with a comma-separated list of module to import.

##### Swift package

If your first-party code is entirely contained in a Swift Package with one or more modules, you can add the following lines to your root target’s definition:

```swift
    plugins: [
        .plugin(name: "SafeDIGenerator", package: "SafeDI")
    ]
```

You can see this integration in practice in the [ExamplePackageIntegration](Examples/ExamplePackageIntegration) package.

#### CocoaPods

Use a pre-build script ([example](Examples/ExampleCocoaPodsIntegration/safeditool.sh)) to download the `SafeDITool` binary and generate your SafeDI dependency tree. Make sure to set `ENABLE_USER_SCRIPT_SANDBOXING` to `NO` in the target running the pre-build script.

You can see this integration in practice in the [ExampleCocoaPodsIntegration](Examples/ExampleCocoaPodsIntegration) package. Run `bundle exec pod install --project-directory=Examples/ExampleCocoaPodsIntegration` to create the `ExampleCocoaPodsIntegration.xcworkspace`.

#### Additional configurations

If your first-party code comprises a mix of Xcode Projects and Swift Packages or some other configuration, once your Xcode project depends on the SafeDI package you will need to utilize the `SafeDITool` command-line executable directly in a pre-build script similar to the CocoaPods integration described above.

`SafeDITool` is designed to integrate into projects of any size or shape.

`SafeDITool` can parse all of your Swift files at once, or for even better performance, the tool can be run on each dependent module as part of the build. Run `swift run SafeDITool --help` to see documentation of the tool’s supported arguments.

## Comparing SafeDI to other DI libraries

SafeDI’s compile-time safety and hierarchical dependency scoping make it similar to [Needle](https://github.com/uber/needle) and [Weaver](https://github.com/scribd/Weaver). Unlike Needle, SafeDI does not require defining dependency protocols for each type that can be instantiated within the DI tree. Unlike Weaver, SafeDI does not require defining and maintaining containers that live alongside your regular Swift code.

Other Swift DI libraries, like [Swinject](https://github.com/Swinject/Swinject) and [swift-dependencies](https://github.com/pointfreeco/swift-dependencies), do not offer compile-time safety. Meanwhile, libraries like [Factory](https://github.com/hmlongco/Factory) do offer compile-time validation of the dependency tree, but prevent hierarchical dependency scoping. This means scoped dependencies—like an authentication token in a network layer—can only be optionally injected when using Factory.

## Contributing

I’m glad you’re interested in SafeDI, and I’d love to see where you take it. Please review the [contributing guidelines](Contributing.md) prior to submitting a Pull Request.

Thanks for being part of this journey, and happy injecting!

## Author

SafeDI was created by [Dan Federman](https://github.com/dfed), the architect of Airbnb’s closed-source Swift dependency injection system. Following his tenure at Airbnb, Dan developed SafeDI to share a modern, compile-time-safe dependency injection solution with the Swift community.

Dan has a proven track record of maintaining open-source libraries: he co-created [Valet](https://github.com/square/Valet) and has been maintaining the repo since its debut in 2015.

## Acknowledgements

Special thanks to [@kierajmumick](http://github.com/kierajmumick) for helping shape the early design of SafeDI.
