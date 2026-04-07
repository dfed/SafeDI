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
    .package(url: "https://github.com/dfed/SafeDI.git", from: "2.0.0"),
]
```


To install the SafeDI framework into an Xcode project with Swift Package Manager, follow [Apple’s instructions](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) to add `https://github.com/dfed/SafeDI.git` as a dependency.

### Generating your dependency tree

SafeDI provides a code generation plugin named `SafeDIGenerator`. This plugin works out of the box on most project configurations. If your project uses a custom build system, you can configure your build to utilize the `SafeDITool` command-line executable directly.

#### Swift package manager

##### Xcode project

If your first-party code comprises a single module in an `.xcodeproj`, once your Xcode project depends on the SafeDI package you can integrate the Swift Package Plugin simply by going to your target’s `Build Phases`, expanding the `Run Build Tool Plug-ins` drop-down, and adding the `SafeDIGenerator` as a build tool plug-in. You can see this integration in practice in the [ExampleProjectIntegration](Examples/ExampleProjectIntegration) project.

If your Xcode project comprises multiple modules, follow the above steps, and then add a `#SafeDIConfiguration` in your root module to configure SafeDI:

```swift
import SafeDI

#SafeDIConfiguration(
    additionalDirectoriesToInclude: ["Subproject"]
)
```

The `additionalDirectoriesToInclude` parameter specifies folders outside of your root module that SafeDI will scan for Swift source files. Paths must be relative to the project directory. You can see [an example of this configuration](Examples/ExampleMultiProjectIntegration/ExampleMultiProjectIntegration/SafeDIConfiguration.swift) in the [ExampleMultiProjectIntegration](Examples/ExampleMultiProjectIntegration) project.

##### Swift package

If your first-party code is entirely contained in a Swift Package with one or more modules, you can add the following lines to your root target’s definition:

```swift
    plugins: [
        .plugin(name: "SafeDIGenerator", package: "SafeDI")
    ]
```

To also generate mocks for non-root modules, add the plugin to all first-party targets.

You can see this integration in practice in the [Example Package Integration](Examples/Example Package Integration) package.

Unlike the `SafeDIGenerator` Xcode project plugin, the `SafeDIGenerator` Swift package plugin finds source files in dependent modules without additional configuration steps. If you find that SafeDI’s generated dependency tree is missing required imports, you may add a `#SafeDIConfiguration` in your root module with the additional module names:

```swift
import SafeDI

#SafeDIConfiguration(
    additionalImportedModules: ["MyModule"]
)
```

##### Unlocking faster builds with Swift Package Manager plugins

SafeDI vends a `SafeDIPrebuiltGenerator` plugin for both Xcode and Swift package manager. This plugin utilizes a prebuilt binary for dependency tree generation and does not require compiling `SwiftSyntax`. Integrating this plugin will guide you through the one-step process of downloading the binary to the expected location.

#### Additional configurations

`SafeDITool` is designed to integrate into projects of any size or shape. Our [Releases](https://github.com/dfed/SafeDI/releases) page has prebuilt, codesigned release binaries of the `SafeDITool`  that can be downloaded and utilizied directly in a pre-build script ([example](Examples/PrebuildScript/safeditool.sh)). Make sure to set `ENABLE_USER_SCRIPT_SANDBOXING` to `NO` in the target running the pre-build script.

`SafeDITool` can parse all of your Swift files at once, or for even better performance, the tool can be run on each dependent module as part of the build. Run `swift run SafeDITool --help` to see documentation of the tool’s supported arguments.

## Comparing SafeDI to other DI libraries

SafeDI’s compile-time safety and hierarchical dependency scoping make it similar to [Needle](https://github.com/uber/needle) and [Weaver](https://github.com/scribd/Weaver). Unlike Needle, SafeDI does not require defining dependency protocols for each type that can be instantiated within the DI tree. Unlike Weaver, SafeDI does not require defining and maintaining containers that live alongside your regular Swift code.

Other Swift DI libraries, like [Factory](https://github.com/hmlongco/Factory) and [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) do offer compile-time validation of the dependency tree but do not have hierarchical dependency scoping. This means scoped dependencies—like an authentication token in a network layer—can only be optionally injected when using these libraries. Meanwhile, libraries like [Swinject](https://github.com/Swinject/Swinject) do not offer compile-time safety.

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
2. Create a `SafeDIConfiguration.swift` file in your target's source directory
3. Migrate any existing CSV configuration values into the new `#SafeDIConfiguration` macro
4. Delete the obsolete CSV files

### Manual migration

1. Update your `swift-tools-version` to 6.3 or later
2. Update your SafeDI dependency to `from: "2.0.0"`
3. If you have `.safedi/configuration/include.csv` or `.safedi/configuration/additionalImportedModules.csv`, add a `#SafeDIConfiguration` in your root module with the equivalent values and delete the CSV files
4. If you don't have CSV configuration files, add a `#SafeDIConfiguration()` in your root module

### Migrating prebuild scripts or custom build system integrations

If you invoke `SafeDITool` directly (not via the provided SPM plugin), the `--dependency-tree-output` flag has been replaced with `--swift-manifest`. The tool now takes a JSON manifest file that maps input Swift files to output files. See [`SafeDIToolManifest`](Sources/SafeDICore/Models/SafeDIToolManifest.swift) for the expected format.

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
safeditool input.csv --swift-manifest manifest.json
```

## Contributing

I’m glad you’re interested in SafeDI, and I’d love to see where you take it. Please review the [contributing guidelines](Contributing.md) prior to submitting a Pull Request.

Thanks for being part of this journey, and happy injecting!

## Author

SafeDI was created by [Dan Federman](https://github.com/dfed), the architect of Airbnb’s closed-source Swift dependency injection system. Following his tenure at Airbnb, Dan developed SafeDI to share a modern, compile-time-safe dependency injection solution with the Swift community.

Dan has a proven track record of maintaining open-source libraries: he co-created [Valet](https://github.com/square/Valet) and has been maintaining the repo since its debut in 2015.

## Acknowledgements

Special thanks to [@kierajmumick](http://github.com/kierajmumick) for helping shape the early design of SafeDI.
