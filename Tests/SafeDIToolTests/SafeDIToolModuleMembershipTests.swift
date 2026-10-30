// Distributed under the MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import SafeDICore
import Testing
@testable import SafeDITool

/// The module, and the package of that module, that `generate` records for each declaration it reads and for the
/// module it generates code for: from `--module-name`, `--package-name` and `--dependency-module-names` in a run per
/// module, and from the target graph the SafeDIGenerator plugin writes beside its input CSV otherwise.
struct SafeDIToolModuleMembershipTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Integrations

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsModuleAndPackageOfEveryDeclaration_whenModulesSpanTwoPackages(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.twoPackageModules,
			integration: integration,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)

		let generateOutput = try #require(output.modules["App"]?.generateOutput)
		#expect(Self.declaringModules(of: generateOutput.dependentModules.flatMap(\.instantiables) + generateOutput.module.instantiables) == [
			"App": DeclaringModule(moduleName: "App", packageName: "Application"),
			"Engine": DeclaringModule(moduleName: "Core", packageName: "Foundations"),
			"Pump": DeclaringModule(moduleName: "Middle", packageName: "Foundations"),
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsModuleItGeneratesCodeFor_whenModulesSpanTwoPackages(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.twoPackageModules,
			integration: integration,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules.compactMapValues { $0.generateOutput.map { ModuleIdentity($0.module) } } == [
			"Core": ModuleIdentity(moduleName: "Core", packageName: "Foundations", dependencyModuleNames: []),
			"Middle": ModuleIdentity(moduleName: "Middle", packageName: "Foundations", dependencyModuleNames: ["Core"]),
			"App": ModuleIdentity(moduleName: "App", packageName: "Application", dependencyModuleNames: ["Core", "Middle"]),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesModuleItGeneratesCodeForToModuleInfo_whenOptionsNameModulePackageAndDependencies() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.twoPackageModules,
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)

		// Read back from each module's `.safedi`.
		#expect(output.modules.compactMapValues { $0.moduleInfo.map(ModuleIdentity.init) } == [
			"Core": ModuleIdentity(moduleName: "Core", packageName: "Foundations", dependencyModuleNames: []),
			"Middle": ModuleIdentity(moduleName: "Middle", packageName: "Foundations", dependencyModuleNames: ["Core"]),
			"App": ModuleIdentity(moduleName: "App", packageName: "Application", dependencyModuleNames: ["Core", "Middle"]),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesModuleAndPackageOfEachDeclarationToModuleInfo_whenOptionsNameModuleAndPackage() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.twoPackageModules,
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)

		// Read back from each module's `.safedi`.
		#expect(output.modules.compactMapValues { $0.moduleInfo.map { Self.declaringModules(of: $0.instantiables) } } == [
			"Core": ["Engine": DeclaringModule(moduleName: "Core", packageName: "Foundations")],
			"Middle": ["Pump": DeclaringModule(moduleName: "Middle", packageName: "Foundations")],
			"App": ["App": DeclaringModule(moduleName: "App", packageName: "Application")],
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsNoModule_whenDeclarationIsReachedThroughAdditionalDirectoryOfModuleNamedByOptions() async throws {
		// The plugin leaves a checkout package's files out of its CSV, so a consumer reads them only through a
		// configuration's `additionalDirectoriesToInclude`: they belong to another module, which the options do not name.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				#SafeDIConfiguration(
				    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
				)
				""",
				"""
				@Instantiable
				public struct TargetType: Instantiable {
				    public init() {}
				}
				""",
			],
			additionalDirectorySwiftFileContent: [
				"""
				@Instantiable
				public struct AdditionalType: Instantiable {
				    public init() {}
				}
				""",
			],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "Target", "--package-name", "Application"],
		)

		#expect(Self.declaringModules(of: output.moduleInfo.instantiables) == [
			"AdditionalType": DeclaringModule(moduleName: nil, packageName: nil),
			"TargetType": DeclaringModule(moduleName: "Target", packageName: "Application"),
		])
	}

	// MARK: Tests – Target graph

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsNoModule_whenInputFileLiesInNoTargetDirectory() async throws {
		let project = try makePluginProject(
			files: [
				"Sources/App/AppRoot.swift": Self.rootContent,
				"Loose/Loose.swift": Self.instantiableContent(named: "Loose"),
			],
			targets: [Self.appTarget],
		)

		let generateOutput = try await project.scanAndGenerate(reportingProjectRoot: .resolved)

		#expect(Self.declaringModules(of: generateOutput.module.instantiables) == [
			"AppRoot": DeclaringModule(moduleName: "App", packageName: "application"),
			"Loose": DeclaringModule(moduleName: nil, packageName: nil),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsNoModule_whenNoTargetGraphLiesBesideInputCSV() async throws {
		// The Xcode project plugin, a plugin that predates the target graph, or a hand-written manifest.
		let project = try makePluginProject(
			files: [
				"Sources/App/AppRoot.swift": Self.rootContent,
				"Sources/Core/Engine.swift": Self.instantiableContent(named: "Engine"),
			],
			targets: nil,
		)

		let generateOutput = try await project.scanAndGenerate(reportingProjectRoot: .resolved)

		#expect(ModuleIdentity(generateOutput.module) == ModuleIdentity(moduleName: nil, packageName: nil, dependencyModuleNames: []))
		#expect(Self.declaringModules(of: generateOutput.module.instantiables) == [
			"AppRoot": DeclaringModule(moduleName: nil, packageName: nil),
			"Engine": DeclaringModule(moduleName: nil, packageName: nil),
		])
	}

	@Test(arguments: ProjectRootSpelling.allCases, [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsTargetOfEachFile_whenProjectRootIsReportedEitherWay(projectRootSpelling: ProjectRootSpelling, readsScanCache: Bool) async throws {
		// Scan's cache names each file relative to the resolved root, and a fresh parse names it as the CSV does.
		let project = try makePluginProject(
			files: [
				"Sources/App/AppRoot.swift": Self.rootContent,
				"Sources/Core/Engine.swift": Self.instantiableContent(named: "Engine"),
			],
			targets: [Self.appTarget, Self.coreTarget],
		)

		let generateOutput = try await project.scanAndGenerate(reportingProjectRoot: projectRootSpelling, deletingScanCache: !readsScanCache)

		#expect(Self.declaringModules(of: generateOutput.module.instantiables) == [
			"AppRoot": DeclaringModule(moduleName: "App", packageName: "application"),
			"Engine": DeclaringModule(moduleName: "Core", packageName: "foundations"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsModuleOfTargetPluginPlanned_whenTargetGraphLiesBesideInputCSV() async throws {
		let project = try makePluginProject(
			files: [
				"Sources/App/AppRoot.swift": Self.rootContent,
				"Sources/Core/Engine.swift": Self.instantiableContent(named: "Engine"),
			],
			targets: [Self.appTarget, Self.coreTarget],
		)

		let generateOutput = try await project.scanAndGenerate(reportingProjectRoot: .resolved)

		#expect(ModuleIdentity(generateOutput.module) == ModuleIdentity(moduleName: "App", packageName: "application", dependencyModuleNames: ["Core", "SafeDI"]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsMostDeeplyNestedTarget_whenTargetDirectoryLiesInsideAnother() async throws {
		// SwiftPM accepts a target whose directory lies inside another's when the outer target excludes it.
		let project = try makePluginProject(
			files: [
				"Sources/App/AppRoot.swift": Self.rootContent,
				"Sources/Outer/Outer.swift": Self.instantiableContent(named: "Outer"),
				"Sources/Outer/Inner/Inner.swift": Self.instantiableContent(named: "Inner"),
			],
			targets: [
				Self.appTarget,
				TargetDeclaration(moduleName: "Outer", packageID: "application", directory: "Sources/Outer"),
				TargetDeclaration(moduleName: "Inner", packageID: "application", directory: "Sources/Outer/Inner"),
			],
		)

		let generateOutput = try await project.scanAndGenerate(reportingProjectRoot: .resolved)

		#expect(Self.declaringModules(of: generateOutput.module.instantiables) == [
			"AppRoot": DeclaringModule(moduleName: "App", packageName: "application"),
			"Inner": DeclaringModule(moduleName: "Inner", packageName: "application"),
			"Outer": DeclaringModule(moduleName: "Outer", packageName: "application"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsNoModule_whenTwoTargetsShareFilesDirectory() async throws {
		// SwiftPM accepts two targets with one directory that split its files with `sources:`, which the target graph
		// does not list, so no file there can be attributed to either.
		let project = try makePluginProject(
			files: [
				"Sources/App/AppRoot.swift": Self.rootContent,
				"Sources/Shared/First/First.swift": Self.instantiableContent(named: "First"),
				"Sources/Shared/Second/Second.swift": Self.instantiableContent(named: "Second"),
			],
			targets: [
				Self.appTarget,
				TargetDeclaration(moduleName: "FirstTarget", packageID: "application", directory: "Sources/Shared"),
				TargetDeclaration(moduleName: "SecondTarget", packageID: "application", directory: "Sources/Shared"),
			],
		)

		let generateOutput = try await project.scanAndGenerate(reportingProjectRoot: .resolved)

		#expect(Self.declaringModules(of: generateOutput.module.instantiables) == [
			"AppRoot": DeclaringModule(moduleName: "App", packageName: "application"),
			"First": DeclaringModule(moduleName: nil, packageName: nil),
			"Second": DeclaringModule(moduleName: nil, packageName: nil),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsModuleOptionsName_whenOptionsAndTargetGraphAreBothGiven() async throws {
		let project = try makePluginProject(
			files: [
				"Sources/App/AppRoot.swift": Self.rootContent,
				"Sources/Core/Engine.swift": Self.instantiableContent(named: "Engine"),
			],
			targets: [Self.appTarget, Self.coreTarget],
		)

		let generateOutput = try await project.scanAndGenerate(
			reportingProjectRoot: .resolved,
			generateArguments: ["--module-name", "Everything"],
		)

		#expect(ModuleIdentity(generateOutput.module) == ModuleIdentity(moduleName: "Everything", packageName: nil, dependencyModuleNames: []))
		#expect(Self.declaringModules(of: generateOutput.module.instantiables) == [
			"AppRoot": DeclaringModule(moduleName: "Everything", packageName: nil),
			"Engine": DeclaringModule(moduleName: "Everything", packageName: nil),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenTargetGraphCannotBeRead() async throws {
		let project = try makePluginProject(
			files: ["Sources/App/AppRoot.swift": Self.rootContent],
			targets: nil,
		)
		let targetGraphPath = project.swiftFileCSV.path + PluginTargetGraph.fileNameSuffix
		try "{}".write(toFile: targetGraphPath, atomically: true, encoding: .utf8)

		await assertThrowsError("Could not read the target graph the SafeDIGenerator plugin wrote at \(targetGraphPath) as this SafeDITool reads it. A different version of SafeDI most likely wrote this file. To fix this, clean your build (in Xcode: Product > Clean Build Folder) and build again, so that the plugin writes it again.") {
			try await project.scanAndGenerate(reportingProjectRoot: .resolved)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsTargetOfEachFile_whenGenerateScansForItself() async throws {
		// Every cold Swift Build build and every Xcode build of a package runs `generate --output-directory`, which
		// scans for itself with the working directory as its project root.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.rootContent,
				Self.instantiableContent(named: "Engine"),
			],
			pluginInvocation: .scanDuringGenerate(reportsFixtureDirectoryThroughSymbolicLink: false),
			filesToDelete: &filesToDelete,
			pluginTargetGraph: { fixtureDirectory in
				PluginTargetGraph(
					target: PluginTargetGraph.Target(moduleName: "App", packageID: "application", directoryPath: fixtureDirectory + "/", dependencyModuleNames: []),
					dependencyTargets: [],
				)
			},
		)

		#expect(Self.declaringModules(of: output.generateOutput.module.instantiables) == [
			"AppRoot": DeclaringModule(moduleName: "App", packageName: "application"),
			"Engine": DeclaringModule(moduleName: "App", packageName: "application"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func targetGraph_attributesEveryFileOfInputCSV_whenCapturedFromExamplePackageBuild() throws {
		// The files are created, under a directory of their own, because normalization drops a leading `/private` only
		// from a path that names a file, as it did for the plugin.
		let stageDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: stageDirectory, withIntermediateDirectories: true)
		filesToDelete.append(stageDirectory)
		let stage = try realPath(of: stageDirectory)
		let placeholder = "$STAGE"
		var inputSwiftFiles = [String]()
		for entry in Self.capturedExampleInputSwiftFiles {
			let isAbsolute = entry.hasPrefix(placeholder)
			let file = URL(fileURLWithPath: isAbsolute ? stage + entry.dropFirst(placeholder.count) : "\(stage)/Example/\(entry)")
			try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
			try "".write(to: file, atomically: true, encoding: .utf8)
			inputSwiftFiles.append(isAbsolute ? NormalizedFilePath(file.path).path : entry)
		}
		let swiftFileCSV = stageDirectory.appendingPathComponent("InputSwiftFiles.csv")
		try Self.capturedExampleTargetGraph
			.replacingOccurrences(of: placeholder, with: stage)
			.write(toFile: swiftFileCSV.path + PluginTargetGraph.fileNameSuffix, atomically: true, encoding: .utf8)

		let targetGraph = try #require(try PluginTargetGraph(besideInputSourcesFileAt: swiftFileCSV.path))
		// The plugin reports the package directory to `scan` as SwiftPM reports it, with a trailing `/`.
		let projectFilePaths = ProjectFilePaths(projectRoot: "\(stage)/Example/")
		let membership = ModuleMembership(targetGraph: targetGraph, projectFilePaths: projectFilePaths)

		let declaringModules = inputSwiftFiles.map { membership.declaringModule(ofFileAt: projectFilePaths.projectFilePath(of: $0)) }
		#expect(Dictionary(grouping: declaringModules, by: \.self).mapValues(\.count) == [
			DeclaringModule(moduleName: "ChildAModule", packageName: "example"): 1,
			DeclaringModule(moduleName: "ChildBModule", packageName: "example"): 1,
			DeclaringModule(moduleName: "ChildCModule", packageName: "example"): 1,
			DeclaringModule(moduleName: "GrandchildrenModule", packageName: "example"): 3,
			DeclaringModule(moduleName: "RootModule", packageName: "example"): 3,
			DeclaringModule(moduleName: "SafeDI", packageName: "safedi"): 11,
			DeclaringModule(moduleName: "SafeDIMacros", packageName: "safedi"): 45,
			DeclaringModule(moduleName: "SharedModule", packageName: "example"): 2,
			DeclaringModule(moduleName: "SwiftSyntax509", packageName: "swift-syntax"): 1,
			DeclaringModule(moduleName: "SwiftSyntax510", packageName: "swift-syntax"): 1,
			DeclaringModule(moduleName: "SwiftSyntax600", packageName: "swift-syntax"): 1,
			DeclaringModule(moduleName: "SwiftSyntax601", packageName: "swift-syntax"): 1,
			DeclaringModule(moduleName: "SwiftSyntax602", packageName: "swift-syntax"): 1,
			DeclaringModule(moduleName: "SwiftSyntax603", packageName: "swift-syntax"): 1,
		])
		#expect([membership.moduleName, membership.packageName] == ["RootModule", "example"])
		#expect(membership.dependencyModuleNames == ["ChildAModule", "ChildBModule", "ChildCModule", "SafeDI", "SharedModule"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The input CSV the SafeDIGenerator plugin wrote for `RootModule` in a build of the Example Package Integration
	/// (in a directory named `Example`) with SwiftPM's native backend on 2026-10-29, in order. `$STAGE` stands for the
	/// directory that held the package and, beside it, the SafeDI package it depends on by path. The plugin names a file
	/// inside the package relative to it, and any other by its normalized path, which drops a leading `/private`.
	private static let capturedExampleInputSwiftFiles = [
		"Sources/RootModule/EventLogger.swift",
		"Sources/RootModule/LaunchRecorder.swift",
		"Sources/RootModule/Root.swift",
		"$STAGE/example-build-native/checkouts/swift-syntax/Sources/VersionMarkerModules/SwiftSyntax509/Empty.swift",
		"$STAGE/example-build-native/checkouts/swift-syntax/Sources/VersionMarkerModules/SwiftSyntax510/Empty.swift",
		"$STAGE/example-build-native/checkouts/swift-syntax/Sources/VersionMarkerModules/SwiftSyntax600/Empty.swift",
		"$STAGE/example-build-native/checkouts/swift-syntax/Sources/VersionMarkerModules/SwiftSyntax601/Empty.swift",
		"$STAGE/example-build-native/checkouts/swift-syntax/Sources/VersionMarkerModules/SwiftSyntax602/Empty.swift",
		"$STAGE/example-build-native/checkouts/swift-syntax/Sources/VersionMarkerModules/SwiftSyntax603/Empty.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/Macros/InjectableMacro.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/Macros/InstantiableMacro.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/Macros/SafeDIConfigurationMacro.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Errors/DiagnosticError.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Errors/FixableInjectableError.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Errors/FixableInstantiableError.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Extensions/AttributeListSyntaxElementExtensions.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Extensions/AttributeListSyntaxExtensions.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Extensions/AttributeSyntaxExtensions.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Extensions/CollectionExtensions.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Extensions/DeclModifierListSyntaxExtensions.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Extensions/DiagnosticExtensions.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Extensions/ImportDeclSyntaxExtensions.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Extensions/PatternBindingSyntaxExtensions.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Generators/DependencyTreeGenerator.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Generators/ScopeGenerator.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/AccessDeclaration.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/AccessLevel.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/AliasDeclarationReferences.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/ConcreteDeclSyntaxProtocol.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/ConcreteDeclType.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/ConditionalCompilationDecision.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/Dependency.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/ImportStatement.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/Initializer.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/InstantiableStruct.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/OutputFileDeclarations.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/Property.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/ReservedName.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/SafeDIConfiguration.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/SafeDIToolManifest.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/Scope.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/SourceDiagnostic.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/TypeDescription.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/TypeRequirements.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Models/UnorderedEquatingCollection.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Utilities/DeferredRelease.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Utilities/FilePathSpelling.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Utilities/OutputFileNaming.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Visitors/ConditionalCompilationEvaluator.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Visitors/FileVisitor.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Visitors/InstantiableVisitor.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Visitors/SafeDIConfigurationVisitor.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDICore/Visitors/SafeDIContentDetector.swift",
		"$STAGE/SafeDI/Sources/SafeDIMacros/SafeDIMacroPlugin.swift",
		"$STAGE/SafeDI/Sources/SafeDI/Decorators/Forwarded.swift",
		"$STAGE/SafeDI/Sources/SafeDI/Decorators/Instantiable.swift",
		"$STAGE/SafeDI/Sources/SafeDI/Decorators/Instantiated.swift",
		"$STAGE/SafeDI/Sources/SafeDI/Decorators/Received.swift",
		"$STAGE/SafeDI/Sources/SafeDI/Decorators/SafeDIConfiguration.swift",
		"$STAGE/SafeDI/Sources/SafeDI/DelayedInstantiation/ErasedInstantiator.swift",
		"$STAGE/SafeDI/Sources/SafeDI/DelayedInstantiation/Instantiator.swift",
		"$STAGE/SafeDI/Sources/SafeDI/DelayedInstantiation/LazilyInstantiated.swift",
		"$STAGE/SafeDI/Sources/SafeDI/DelayedInstantiation/SendableErasedInstantiator.swift",
		"$STAGE/SafeDI/Sources/SafeDI/DelayedInstantiation/SendableInstantiator.swift",
		"$STAGE/SafeDI/Sources/SafeDI/DelayedInstantiation/SendableLazilyInstantiated.swift",
		"Sources/SharedModule/SharedThing.swift",
		"Sources/SharedModule/UserDefaults.swift",
		"Sources/GrandchildrenModule/Grandchild C/GrandchildC.swift",
		"Sources/GrandchildrenModule/GrandchildA.swift",
		"Sources/GrandchildrenModule/GrandchildB.swift",
		"Sources/ChildAModule/ChildA.swift",
		"Sources/ChildBModule/ChildB.swift",
		"Sources/ChildCModule/ChildC.swift",
	]

	/// The target graph the plugin wrote beside `capturedExampleInputSwiftFiles` in the same build. `$STAGE` stands for
	/// the same directory as SwiftPM reported it, resolved, which kept its leading `/private`.
	private static let capturedExampleTargetGraph = #"""
	{
	  "dependencyTargets" : [
	    {
	      "dependencyModuleNames" : [
	        "GrandchildrenModule",
	        "SafeDI",
	        "SharedModule"
	      ],
	      "directoryPath" : "$STAGE\/Example\/Sources\/ChildAModule\/",
	      "moduleName" : "ChildAModule",
	      "packageID" : "example"
	    },
	    {
	      "dependencyModuleNames" : [
	        "GrandchildrenModule",
	        "SafeDI",
	        "SharedModule"
	      ],
	      "directoryPath" : "$STAGE\/Example\/Sources\/ChildBModule\/",
	      "moduleName" : "ChildBModule",
	      "packageID" : "example"
	    },
	    {
	      "dependencyModuleNames" : [
	        "GrandchildrenModule",
	        "SafeDI",
	        "SharedModule"
	      ],
	      "directoryPath" : "$STAGE\/Example\/Sources\/ChildCModule\/",
	      "moduleName" : "ChildCModule",
	      "packageID" : "example"
	    },
	    {
	      "dependencyModuleNames" : [
	        "SafeDI",
	        "SharedModule"
	      ],
	      "directoryPath" : "$STAGE\/Example\/Sources\/GrandchildrenModule\/",
	      "moduleName" : "GrandchildrenModule",
	      "packageID" : "example"
	    },
	    {
	      "dependencyModuleNames" : [
	        "SafeDIMacros"
	      ],
	      "directoryPath" : "$STAGE\/SafeDI\/Sources\/SafeDI\/",
	      "moduleName" : "SafeDI",
	      "packageID" : "safedi"
	    },
	    {
	      "dependencyModuleNames" : [
	        "SwiftCompilerPlugin",
	        "SwiftDiagnostics",
	        "SwiftParser",
	        "SwiftSyntax",
	        "SwiftSyntaxBuilder",
	        "SwiftSyntaxMacros"
	      ],
	      "directoryPath" : "$STAGE\/SafeDI\/Sources\/SafeDIMacros\/",
	      "moduleName" : "SafeDIMacros",
	      "packageID" : "safedi"
	    },
	    {
	      "dependencyModuleNames" : [
	        "SafeDI"
	      ],
	      "directoryPath" : "$STAGE\/Example\/Sources\/SharedModule\/",
	      "moduleName" : "SharedModule",
	      "packageID" : "example"
	    },
	    {
	      "dependencyModuleNames" : [

	      ],
	      "directoryPath" : "$STAGE\/example-build-native\/checkouts\/swift-syntax\/Sources\/VersionMarkerModules\/SwiftSyntax509\/",
	      "moduleName" : "SwiftSyntax509",
	      "packageID" : "swift-syntax"
	    },
	    {
	      "dependencyModuleNames" : [

	      ],
	      "directoryPath" : "$STAGE\/example-build-native\/checkouts\/swift-syntax\/Sources\/VersionMarkerModules\/SwiftSyntax510\/",
	      "moduleName" : "SwiftSyntax510",
	      "packageID" : "swift-syntax"
	    },
	    {
	      "dependencyModuleNames" : [

	      ],
	      "directoryPath" : "$STAGE\/example-build-native\/checkouts\/swift-syntax\/Sources\/VersionMarkerModules\/SwiftSyntax600\/",
	      "moduleName" : "SwiftSyntax600",
	      "packageID" : "swift-syntax"
	    },
	    {
	      "dependencyModuleNames" : [

	      ],
	      "directoryPath" : "$STAGE\/example-build-native\/checkouts\/swift-syntax\/Sources\/VersionMarkerModules\/SwiftSyntax601\/",
	      "moduleName" : "SwiftSyntax601",
	      "packageID" : "swift-syntax"
	    },
	    {
	      "dependencyModuleNames" : [

	      ],
	      "directoryPath" : "$STAGE\/example-build-native\/checkouts\/swift-syntax\/Sources\/VersionMarkerModules\/SwiftSyntax602\/",
	      "moduleName" : "SwiftSyntax602",
	      "packageID" : "swift-syntax"
	    },
	    {
	      "dependencyModuleNames" : [

	      ],
	      "directoryPath" : "$STAGE\/example-build-native\/checkouts\/swift-syntax\/Sources\/VersionMarkerModules\/SwiftSyntax603\/",
	      "moduleName" : "SwiftSyntax603",
	      "packageID" : "swift-syntax"
	    }
	  ],
	  "target" : {
	    "dependencyModuleNames" : [
	      "ChildAModule",
	      "ChildBModule",
	      "ChildCModule",
	      "SafeDI",
	      "SharedModule"
	    ],
	    "directoryPath" : "$STAGE\/Example\/Sources\/RootModule\/",
	    "moduleName" : "RootModule",
	    "packageID" : "example"
	  }
	}
	"""#

	/// Two modules of the package `Foundations`, `Core` and `Middle`, and the module `App` of the package
	/// `Application`, which depends on both. Every module generates code, so the plugin runs `generate` for each.
	private static let twoPackageModules = [
		ModuleFixture(
			name: "Core",
			packageName: "Foundations",
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Engine: Instantiable {
				    public init() {}
				}
				""",
			],
		),
		ModuleFixture(
			name: "Middle",
			packageName: "Foundations",
			swiftFileContent: [
				"""
				import Core

				@Instantiable(generateMock: true)
				public final class Pump: Instantiable {
				    public init(engine: Engine) {
				        self.engine = engine
				    }
				    @Instantiated let engine: Engine
				}
				""",
			],
			dependencies: ["Core"],
		),
		ModuleFixture(
			name: "App",
			packageName: "Application",
			swiftFileContent: [
				"""
				import Core
				import Middle

				@Instantiable(isRoot: true)
				public final class App: Instantiable {
				    public init(pump: Pump) {
				        self.pump = pump
				    }
				    @Instantiated let pump: Pump
				}
				""",
			],
			dependencies: ["Middle", "Core"],
		),
	]

	private static let rootContent = """
	@Instantiable(isRoot: true)
	public struct AppRoot: Instantiable {
	    public init() {}
	}
	"""

	private static func instantiableContent(named typeName: String) -> String {
		"""
		@Instantiable
		public struct \(typeName): Instantiable {
		    public init() {}
		}
		"""
	}

	private static let appTarget = TargetDeclaration(moduleName: "App", packageID: "application", directory: "Sources/App", dependencyModuleNames: ["Core", "SafeDI"])
	private static let coreTarget = TargetDeclaration(moduleName: "Core", packageID: "foundations", directory: "Sources/Core")

	/// The module and package each of `instantiables` records, by the name of the type it declares.
	private static func declaringModules(of instantiables: [Instantiable]) -> [String: DeclaringModule] {
		Dictionary(uniqueKeysWithValues: instantiables.map {
			($0.concreteInstantiable.asSource, DeclaringModule(moduleName: $0.moduleName, packageName: $0.packageName))
		})
	}

	/// What a module records about the module `generate` generated code for.
	private struct ModuleIdentity: Equatable {
		init(moduleName: String?, packageName: String?, dependencyModuleNames: [String]) {
			self.moduleName = moduleName
			self.packageName = packageName
			self.dependencyModuleNames = dependencyModuleNames
		}

		init(_ moduleInfo: ModuleInfo) {
			self.init(moduleName: moduleInfo.moduleName, packageName: moduleInfo.packageName, dependencyModuleNames: moduleInfo.dependencyModuleNames)
		}

		let moduleName: String?
		let packageName: String?
		let dependencyModuleNames: [String]
	}

	/// How the build system reports the package directory to the plugin, which spells the target graph's directories,
	/// the target's own files, and `scan`'s project root under it.
	enum ProjectRootSpelling: CaseIterable, CustomTestStringConvertible {
		/// Through a symbolic link to the package directory.
		case throughSymbolicLink
		/// As `realpath(3)` resolves it, which is how SwiftPM and Xcode report it.
		case resolved

		var testDescription: String {
			switch self {
			case .throughSymbolicLink:
				"through a symbolic link"
			case .resolved:
				"resolved"
			}
		}
	}

	/// A target as the plugin's target graph describes it, with its directory relative to the package directory.
	private struct TargetDeclaration {
		init(moduleName: String, packageID: String, directory: String, dependencyModuleNames: [String] = []) {
			self.moduleName = moduleName
			self.packageID = packageID
			self.directory = directory
			self.dependencyModuleNames = dependencyModuleNames
		}

		let moduleName: String
		let packageID: String
		let directory: String
		let dependencyModuleNames: [String]
	}

	/// A package whose first target, of `targets`, the plugin plans, with every file in the CSV. The package directory
	/// is the working directory, which the plugin's commands run in: the plugin names each file relative to it, and
	/// `generate` reads the files it parses afresh from there. The fixtures lie under its `.build` directory.
	private struct PluginProject {
		/// The fixture directory relative to the package directory.
		let relativeFixtureDirectory: String
		/// A symbolic link to the package directory.
		let symbolicLink: URL
		/// Each file's path relative to the fixture directory.
		let relativeFilePaths: [String]
		/// The files of the target the plugin plans, relative to the fixture directory.
		let ownRelativeFilePaths: [String]
		let targets: [TargetDeclaration]?
		let swiftFileCSV: URL
		let outputDirectory: URL
		let manifestFile: URL

		/// The package directory as the build system reports it.
		func packageRoot(spelled projectRootSpelling: ProjectRootSpelling) throws -> String {
			switch projectRootSpelling {
			case .throughSymbolicLink:
				symbolicLink.path
			case .resolved:
				try realPath(of: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
			}
		}

		/// Writes the CSV and the target graph beside it as the plugin writes them, runs `scan` as the plugin does
		/// while it plans the build, and runs `generate` with the manifest `scan` wrote.
		/// - Parameters:
		///   - deletingScanCache: Whether `generate` parses the module afresh rather than reading scan's cache.
		///   - generateArguments: Arguments `generate` is given beyond the plugin's.
		@discardableResult
		func scanAndGenerate(
			reportingProjectRoot projectRootSpelling: ProjectRootSpelling,
			deletingScanCache: Bool = false,
			generateArguments: [String] = [],
		) async throws -> Generate.Output {
			let packageRoot = try packageRoot(spelled: projectRootSpelling)
			let reportedFixtureDirectory = "\(packageRoot)/\(relativeFixtureDirectory)"
			try relativeFilePaths
				.map { "\(relativeFixtureDirectory)/\($0)" }
				.joined(separator: ",")
				.write(to: swiftFileCSV, atomically: true, encoding: .utf8)
			if let targets, let builtTarget = targets.first {
				func graphTarget(_ target: TargetDeclaration) -> PluginTargetGraph.Target {
					PluginTargetGraph.Target(
						moduleName: target.moduleName,
						packageID: target.packageID,
						directoryPath: "\(reportedFixtureDirectory)/\(target.directory)/",
						dependencyModuleNames: target.dependencyModuleNames,
					)
				}
				let encoder = JSONEncoder()
				encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
				try encoder.encode(PluginTargetGraph(
					target: graphTarget(builtTarget),
					dependencyTargets: targets.dropFirst().map(graphTarget),
				)).write(to: URL(fileURLWithPath: swiftFileCSV.path + PluginTargetGraph.fileNameSuffix))
			}
			try await Scan.parse([
				"--input-sources-file", swiftFileCSV.path,
				"--project-root", "\(packageRoot)/",
				"--output-directory", outputDirectory.path,
				"--manifest-file", manifestFile.path,
				"--mock-scoped-files",
			] + ownRelativeFilePaths.map { "\(reportedFixtureDirectory)/\($0)" }).run()
			if deletingScanCache {
				try FileManager.default.removeItem(at: scannedModuleInfoURL(forManifestPath: manifestFile.path))
			}
			return try await Generate.parse([
				swiftFileCSV.path,
				"--swift-manifest", manifestFile.path,
			] + generateArguments).generate()
		}
	}

	/// Writes `files` into a new fixture directory under the working directory's `.build` directory, with a symbolic link
	/// to the working directory in a temporary directory.
	/// - Parameters:
	///   - files: Each file's content, by its path relative to the fixture directory.
	///   - targets: The targets of the target graph, the planned target first, each with its directory relative to the
	///     fixture directory, or `nil` to write no target graph. The planned target's files are those in its directory.
	private mutating func makePluginProject(files: [String: String], targets: [TargetDeclaration]?) throws -> PluginProject {
		let relativeFixtureDirectory = ".build/SafeDIToolTestFixtures/\(UUID().uuidString)"
		let fixtureDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(relativeFixtureDirectory)
		filesToDelete.append(fixtureDirectory)
		for (relativePath, content) in files {
			let file = fixtureDirectory.appendingPathComponent(relativePath)
			try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
			try content.write(to: file, atomically: true, encoding: .utf8)
		}
		let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		let outputDirectory = temporaryDirectory.appendingPathComponent("Output")
		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
		filesToDelete.append(temporaryDirectory)
		let symbolicLink = temporaryDirectory.appendingPathComponent("Link")
		try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
		let relativeFilePaths = files.keys.sorted()
		let plannedDirectory = (targets?.first?.directory ?? "Sources/App") + "/"
		return PluginProject(
			relativeFixtureDirectory: relativeFixtureDirectory,
			symbolicLink: symbolicLink,
			relativeFilePaths: relativeFilePaths,
			ownRelativeFilePaths: relativeFilePaths.filter { $0.hasPrefix(plannedDirectory) },
			targets: targets,
			swiftFileCSV: temporaryDirectory.appendingPathComponent("InputSwiftFiles.csv"),
			outputDirectory: outputDirectory,
			manifestFile: temporaryDirectory.appendingPathComponent("SafeDIManifest.json"),
		)
	}
}
