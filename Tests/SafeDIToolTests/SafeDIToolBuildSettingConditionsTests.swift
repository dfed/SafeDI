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

/// How `generate` uses the compilation conditions a build system expands into the
/// `--build-setting-active-compilation-conditions` and `--build-setting-other-swift-flags`
/// arguments, verified from source to generated output.
///
/// `Root` is unconditional, so the set of files `scan` declares never changes; whether
/// `StagingLogger` or `ProductionLogger` fulfills its `Logger` shows which clause was scanned.
struct SafeDIToolBuildSettingConditionsTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Choosing the conditions

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_scansClauseActiveInBuildSettings_whenScanReportedNoConditions() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			verificationCompilationConditions: ["STAGING"],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.stagingRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_ignoresConditionsScanReported_whenBuildSettingsAreExpanded() async throws {
		// A plugin can report a condition the compiler does not define: Xcode hands build tool plugins
		// a package's debug-configuration defines in Release too. The build settings are what the
		// compiler receives, so they replace what scan recorded rather than adding to it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["STAGING"],
			buildSettingArguments: Self.buildSettingArguments(),
			verificationCompilationConditions: [],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.productionRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_ignoresActiveCompilationConditionsOption_whenBuildSettingsAreExpanded() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["STAGING"],
			buildSettingArguments: Self.buildSettingArguments(),
		)

		#expect(output.moduleInfo.instantiables.map(\.concreteInstantiable.asSource) == ["Root", "ProductionLogger"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_usesConditionsScanReported_whenBuildSettingsAreUnexpandedBraceReferences() async throws {
		// SwiftPM's native build system passes build tool plugin arguments through unexpanded.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["STAGING"],
			buildSettingArguments: Self.buildSettingArguments(
				activeCompilationConditions: "${SWIFT_ACTIVE_COMPILATION_CONDITIONS}",
				otherSwiftFlags: "${OTHER_SWIFT_FLAGS}",
			),
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.stagingRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_usesConditionsScanReported_whenBuildSettingsAreUnexpandedParenthesizedReferences() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["STAGING"],
			buildSettingArguments: Self.buildSettingArguments(
				activeCompilationConditions: "$(SWIFT_ACTIVE_COMPILATION_CONDITIONS)",
				otherSwiftFlags: "$(OTHER_SWIFT_FLAGS)",
			),
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.stagingRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_usesConditionsScanReported_whenOnlyOtherSwiftFlagsIsUnexpanded() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["STAGING"],
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: "${OTHER_SWIFT_FLAGS}"),
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.stagingRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_usesConditionsScanReported_whenOtherSwiftFlagsOptionIsAbsent() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["STAGING"],
			buildSettingArguments: ["--build-setting-active-compilation-conditions=[]"],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.stagingRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenBuildSettingValueIsNotBracketed() async {
		await assertThrowsError("--build-setting-active-compilation-conditions must be wrapped in square brackets, e.g. `--build-setting-active-compilation-conditions=[${SWIFT_ACTIVE_COMPILATION_CONDITIONS}]`.") {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.rootContent, Self.loggerContent],
				filesToDelete: &filesToDelete,
				buildSettingArguments: [
					"--build-setting-active-compilation-conditions=STAGING",
					"--build-setting-other-swift-flags=[]",
				],
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_treatsEveryConditionAsInactive_whenBuildSettingsAreBlank() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["STAGING"],
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: " ", otherSwiftFlags: " "),
			verificationCompilationConditions: [],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.productionRootOutput])
	}

	// MARK: Tests – Reading OTHER_SWIFT_FLAGS

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_activatesCondition_whenOtherSwiftFlagsDefinesItInOneArgument() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: "-Onone -DSTAGING"),
			verificationCompilationConditions: ["STAGING"],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.stagingRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_activatesCondition_whenOtherSwiftFlagsDefinesItInTwoArguments() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: "-D STAGING"),
			verificationCompilationConditions: ["STAGING"],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.stagingRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_activatesCondition_whenOtherSwiftFlagsQuotesTheDefinition() async throws {
		// Xcode passes a project's `OTHER_SWIFT_FLAGS` through with the quotes the project wrote.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: #""-DSTAGING" '-DUNUSED'"#),
			verificationCompilationConditions: ["STAGING"],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.stagingRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotActivateCondition_whenDefinitionIsInsideQuotedArgument() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: #""-I/tmp/a -DSTAGING""#),
			verificationCompilationConditions: [],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.productionRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotActivateCondition_whenDefinitionFollowsEscapedSpace() async throws {
		// SwiftPM's Swift Build backend escapes the spaces inside each flag of a package's `unsafeFlags`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: #"-I/tmp/a\ -DSTAGING"#),
			verificationCompilationConditions: [],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.productionRootOutput])
	}

	@Test(arguments: ["-Xcc", "-Xclang-linker", "-Xfrontend", "-Xlinker", "-Xllvm"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotActivateCondition_whenDefinitionIsPassedToAnotherTool(flag: String) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: "\(flag) -DSTAGING"),
			verificationCompilationConditions: [],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.productionRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assertsConditionOnce_whenBuildSettingsDefineItRepeatedly() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(
				activeCompilationConditions: "STAGING STAGING",
				otherSwiftFlags: "-DSTAGING -D STAGING",
			),
			verificationCompilationConditions: ["STAGING"],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.stagingRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_activatesConditionsTheBuildSystemDefinesImplicitly() async throws {
		// What SwiftPM's Swift Build backend expands for a debug build of a package target with an
		// enabled trait `MyTrait`: conditions SwiftPM never reports to build tool plugins.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.rootContent,
				"""
				public protocol Logger {}

				#if SWIFT_PACKAGE && DEBUG && SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE && Xcode && MyTrait
				@Instantiable(fulfillingAdditionalTypes: [Logger.self])
				public struct StagingLogger: Logger, Instantiable {
				    public init() {}
				}
				#else
				@Instantiable(fulfillingAdditionalTypes: [Logger.self])
				public struct ProductionLogger: Logger, Instantiable {
				    public init() {}
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(
				activeCompilationConditions: " SWIFT_PACKAGE DEBUG SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE MyTrait",
				otherSwiftFlags: " -DXcode -plugin-path /usr/lib/swift/host/plugins/testing",
			),
			verificationCompilationConditions: ["SWIFT_PACKAGE", "DEBUG", "SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE", "Xcode", "MyTrait"],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if !(SWIFT_PACKAGE && DEBUG && SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE && Xcode && MyTrait)
		#error("SafeDI scanned this module assuming `#if SWIFT_PACKAGE && DEBUG && SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE && Xcode && MyTrait` was active, but it is inactive in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
		#endif

		extension Root {
		    public init() {
		        let logger: Logger = StagingLogger()
		        self.init(logger: logger)
		    }
		}
		"""])
	}

	// MARK: Tests – Reusing scan's parse

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesScanParse_whenNoBlockGuardingSafeDIDeclarationsConsultsDifferingCondition() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "SWIFT_PACKAGE DEBUG"),
			swiftFileContentAfterScan: [Self.rootContent, Self.renamedLoggerContent],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.productionRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesScanParse_whenConsultedConditionKeepsItsValue() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			activeCompilationConditions: ["STAGING"],
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING DEBUG"),
			swiftFileContentAfterScan: [Self.rootContent, Self.renamedLoggerContent],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.stagingRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesScanParse_whenDifferingConditionGuardsOnlyDeclarationsSafeDIIgnores() async throws {
		let rootContent = """
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(logger: Logger) {
		        self.logger = logger
		    }

		    @Instantiated let logger: Logger

		    #if DEBUG
		    public func debugDescription() -> String { "" }
		    #endif
		}

		#if DEBUG
		public func debugOnlyFunction() {}
		#endif
		"""
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [rootContent, Self.unconditionalLoggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "DEBUG"),
			swiftFileContentAfterScan: [rootContent, Self.renamedLoggerContent],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.unconditionalRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesScanParse_whenDifferingConditionIsMockConditionGuardingMockOnlyDeclarations() async throws {
		// Mock-only declarations are scanned as if the mock condition were active whatever the build
		// reports, so its value cannot change what the scan found.
		let loggerContent = """
		public protocol Logger {}

		@Instantiable(fulfillingAdditionalTypes: [Logger.self])
		public struct ProductionLogger: Logger, Instantiable {
		    public init() {}

		    #if DEBUG
		    public static func mock() -> ProductionLogger { ProductionLogger() }
		    #endif
		}
		"""
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "DEBUG"),
			swiftFileContentAfterScan: [Self.rootContent, Self.renamedLoggerContent],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.unconditionalRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_walksFileAgain_whenBlockGuardingSafeDIDeclarationsConsultsDifferingCondition() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			verificationCompilationConditions: ["STAGING"],
			swiftFileContentAfterScan: [Self.rootContent, Self.renamedLoggerContent],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.renamedStagingRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesScanOfFileConsultingNoDifferingCondition_whenAnotherFileIsWalkedAgain() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			swiftFileContentAfterScan: [Self.renamedRootContent, Self.loggerContent],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.stagingRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_walksFileAgain_whenBlockGuardingDependenciesConsultsDifferingCondition() async throws {
		func rootContent(propertyName: String) -> String {
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(\(propertyName): Logger) {
			        self.\(propertyName) = \(propertyName)
			    }

			    #if STAGING
			    @Instantiated let \(propertyName): Logger
			    #else
			    @Instantiated let \(propertyName): Logger
			    #endif
			}
			"""
		}
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [rootContent(propertyName: "logger"), Self.unconditionalLoggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			verificationCompilationConditions: ["STAGING"],
			swiftFileContentAfterScan: [rootContent(propertyName: "renamedLogger"), Self.unconditionalLoggerContent],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if !(STAGING)
		#error("SafeDI scanned this module assuming `#if STAGING` was active, but it is inactive in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
		#endif

		extension Root {
		    public init() {
		        let renamedLogger: Logger = ProductionLogger()
		        self.init(renamedLogger: renamedLogger)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_walksFileAgain_whenBlockGuardingMockOnlyDeclarationsConsultsDifferingConditionOtherThanMockCondition() async throws {
		let loggerContent = """
		public protocol Logger {}

		@Instantiable(fulfillingAdditionalTypes: [Logger.self])
		public struct ProductionLogger: Logger, Instantiable {
		    public init() {}

		    #if DEBUG && STAGING
		    public static func mock() -> ProductionLogger { ProductionLogger() }
		    #endif
		}
		"""
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			verificationCompilationConditions: ["STAGING"],
			swiftFileContentAfterScan: [Self.rootContent, Self.renamedUnconditionalLoggerContent],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.renamedUnconditionalRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_findsImportsAgainWithoutWalkingFile_whenBlockGuardingOnlyImportsConsultsDifferingCondition() async throws {
		func rootContent(propertyName: String) -> String {
			"""
			#if STAGING
			import Foundation
			#endif

			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(\(propertyName): Logger) {
			        self.\(propertyName) = \(propertyName)
			    }

			    @Instantiated let \(propertyName): Logger
			}
			"""
		}
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [rootContent(propertyName: "logger"), Self.unconditionalLoggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			swiftFileContentAfterScan: [rootContent(propertyName: "renamedLogger"), Self.unconditionalLoggerContent],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if canImport(Foundation)
		import Foundation
		#endif

		extension Root {
		    public init() {
		        let logger: Logger = ProductionLogger()
		        self.init(logger: logger)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_findsImportsAgain_whenNestedBlockGuardingOnlyImportsConsultsDifferingCondition() async throws {
		let rootContent = """
		import SafeDI
		#if STAGING
		    #if DEBUG
		    import Foundation
		    #endif
		#endif

		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(logger: Logger) {
		        self.logger = logger
		    }

		    @Instantiated let logger: Logger
		}
		"""
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [rootContent, Self.unconditionalLoggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["STAGING"],
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING DEBUG"),
			verificationCompilationConditions: ["STAGING", "DEBUG"],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if canImport(Foundation)
		import Foundation
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public init() {
		        let logger: Logger = ProductionLogger()
		        self.init(logger: logger)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_omitsImportsFoundAgain_whenFileDeclaresNoScannedSafeDIContent() async throws {
		let unscannedContent = """
		#if STAGING
		import Foundation
		#endif

		#if UNDEFINED
		@Instantiable
		public struct Unscanned: Instantiable {
		    public init() {}
		}
		#endif
		"""
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.unconditionalLoggerContent, unscannedContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			verificationCompilationConditions: ["STAGING"],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if UNDEFINED
		#error("SafeDI scanned this module assuming `#if UNDEFINED` was inactive, but it is active in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
		#endif

		extension Root {
		    public init() {
		        let logger: Logger = ProductionLogger()
		        self.init(logger: logger)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_walksFileAgain_whenBlockContainingSyntaxErrorConsultsDifferingCondition() async throws {
		let rootContent = """
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(logger: Logger) {
		        self.logger = logger
		    }

		    @Instantiated let logger: Logger
		}

		#if STAGING
		public struct Broken {
		    :::brokenSyntax
		}
		#endif
		"""
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [rootContent, Self.unconditionalLoggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			swiftFileContentAfterScan: [rootContent, Self.unconditionalLoggerContent],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#error(\"""
		Compiler errors prevented the generation of the dependency tree. Files with errors:
			\(output.fixtures["Root.swift"])
		\""")
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_walksFileAgain_whenBlockInAdditionalDirectoryConsultsDifferingCondition() async throws {
		let configurationContent = """
		#SafeDIConfiguration(additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"])
		"""
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, configurationContent],
			additionalDirectorySwiftFileContent: [Self.loggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			verificationCompilationConditions: ["STAGING"],
			swiftFileContentAfterScan: [Self.rootContent, configurationContent],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": Self.stagingRootOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesModuleAfresh_whenDifferingConditionSelectsAnotherConfiguration() async throws {
		let configurationContent = """
		#if STAGING
		#SafeDIConfiguration(additionalImportedModules: ["Foundation"])
		#else
		#SafeDIConfiguration()
		#endif
		"""
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.unconditionalLoggerContent],
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": configurationContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			verificationCompilationConditions: ["STAGING"],
		)

		// Walking only the configuration's file again would keep the configuration scan found.
		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if canImport(Foundation)
		import Foundation
		#endif

		#if !(STAGING)
		#error("SafeDI scanned this module assuming `#if STAGING` was active, but it is inactive in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
		#endif

		extension Root {
		    public init() {
		        let logger: Logger = ProductionLogger()
		        self.init(logger: logger)
		    }
		}
		"""])
	}

	// MARK: Tests – Declarations that decide which files SafeDI generates

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesRoot_whenBuildSettingsActivateRootThatScanFoundInInactiveClause() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.guardedRootContent, Self.unconditionalLoggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			verificationCompilationConditions: ["STAGING"],
		)

		#expect(output.dependencyTreeFiles == ["StagingRoot+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if !(STAGING)
		#error("SafeDI scanned this module assuming `#if STAGING` was active, but it is inactive in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
		#endif

		extension StagingRoot {
		    public init() {
		        let logger: Logger = ProductionLogger()
		        self.init(logger: logger)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesFileWithoutCode_whenBuildSettingsDeactivateRootThatScanFoundInActiveClause() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.guardedRootContent, Self.unconditionalLoggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["STAGING"],
			buildSettingArguments: Self.buildSettingArguments(),
			verificationCompilationConditions: [],
		)

		#expect(output.dependencyTreeFiles == ["StagingRoot+SafeDI.swift": Self.inactiveStagingOutput])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesMock_whenBuildSettingsActivateMockGeneratingTypeThatScanFoundInInactiveClause() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.mockGeneratingLoggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING DEBUG"),
			verificationCompilationConditions: ["STAGING", "DEBUG"],
		)

		#expect(output.mockFiles == ["StagingLogger+SafeDIMock.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if !(STAGING)
		#error("SafeDI scanned this module assuming `#if STAGING` was active, but it is inactive in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
		#endif

		#if DEBUG
		extension StagingLogger {
		    static func mock() -> StagingLogger {
		        StagingLogger()
		    }
		}
		#endif
		"""])
		#expect(output.mockConfigurationFile == Self.activeStagingOutput)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesMockFilesWithoutCode_whenBuildSettingsDeactivateMockGeneratingTypeThatScanFoundInActiveClause() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.mockGeneratingLoggerContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["STAGING"],
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "DEBUG"),
			verificationCompilationConditions: ["DEBUG"],
		)

		#expect(output.mockFiles == ["StagingLogger+SafeDIMock.swift": Self.inactiveStagingOutput])
		#expect(output.mockConfigurationFile == Self.inactiveStagingOutput)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_appliesConfiguration_whenBuildSettingsActivateConfigurationThatScanFoundInInactiveClause() async throws {
		// Scan's cached walk of the configuration's file found no configuration, so walking only that
		// file again would leave the module's configuration unset and drop the import.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.unconditionalLoggerContent],
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.stagingConfigurationContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			verificationCompilationConditions: ["STAGING"],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if canImport(Foundation)
		import Foundation
		#endif

		#if !(STAGING)
		#error("SafeDI scanned this module assuming `#if STAGING` was active, but it is inactive in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
		#endif

		extension Root {
		    public init() {
		        let logger: Logger = ProductionLogger()
		        self.init(logger: logger)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_ignoresConfiguration_whenBuildSettingsDeactivateConfigurationThatScanFoundInActiveClause() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.unconditionalLoggerContent],
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.stagingConfigurationContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["STAGING"],
			buildSettingArguments: Self.buildSettingArguments(),
			verificationCompilationConditions: [],
		)

		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if STAGING
		#error("SafeDI scanned this module assuming `#if STAGING` was inactive, but it is active in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
		#endif

		extension Root {
		    public init() {
		        let logger: Logger = ProductionLogger()
		        self.init(logger: logger)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesAdditionalMock_whenBuildSettingsSelectConfigurationThatListsIt() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.unconditionalLoggerContent],
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.additionalMockConfigurationContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING DEBUG"),
			verificationCompilationConditions: ["STAGING", "DEBUG"],
		)

		#expect(output.mockFiles == ["ProductionLogger+SafeDIMock.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if !(STAGING)
		#error("SafeDI scanned this module assuming `#if STAGING` was active, but it is inactive in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
		#endif

		#if DEBUG
		extension ProductionLogger {
		    static func mock() -> ProductionLogger {
		        ProductionLogger()
		    }
		}
		#endif
		"""])
		#expect(output.mockConfigurationFile == Self.activeStagingOutput)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesAdditionalMockFileWithoutCode_whenBuildSettingsSelectConfigurationThatDoesNotListIt() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent, Self.unconditionalLoggerContent],
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.additionalMockConfigurationContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["STAGING"],
			buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "DEBUG"),
			verificationCompilationConditions: ["DEBUG"],
		)

		#expect(output.mockFiles == ["ProductionLogger+SafeDIMock.swift": Self.inactiveStagingOutput])
		#expect(output.mockConfigurationFile == Self.inactiveStagingOutput)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_listsRootAndInputsInAdditionalDirectory_whenConfigurationThatIncludesItIsInInactiveClause() async throws {
		let project = try await scannedAdditionalDirectoryProject()

		let manifest = try JSONDecoder().decode(SafeDIToolManifest.self, from: Data(contentsOf: project.manifestFile))
		#expect(manifest.dependencyTreeGeneration.map(\.inputFilePath) == ["\(project.relativeDirectoryPath)/Additional/StagingRoot.swift"])
		#expect(manifest.additionalInputFiles == [project.directory.appendingPathComponent("Additional/StagingRoot.swift").path])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesRootInAdditionalDirectory_whenBuildSettingsActivateConfigurationThatIncludesIt() async throws {
		let project = try await scannedAdditionalDirectoryProject()

		let generatedRoot = try await project.generate(buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"))

		#expect(generatedRoot == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if !(STAGING)
		#error("SafeDI scanned this module assuming `#if STAGING` was active, but it is inactive in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
		#endif

		extension StagingRoot {
		    public init() {
		        let dependency = Dependency()
		        self.init(dependency: dependency)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesFileWithoutCodeForRootInAdditionalDirectory_whenConfigurationThatIncludesItIsInactive() async throws {
		let project = try await scannedAdditionalDirectoryProject()

		let generatedRoot = try await project.generate(buildSettingArguments: Self.buildSettingArguments())

		#expect(generatedRoot == Self.inactiveStagingOutput)
	}

	// MARK: Private

	/// A generated file without code, for a module whose only `#if STAGING` decision found the block inactive.
	private static let inactiveStagingOutput = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.

	#if STAGING
	#error("SafeDI scanned this module assuming `#if STAGING` was inactive, but it is active in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
	#endif

	""" + "\n"

	/// A generated file without code, for a module whose only `#if STAGING` decision found the block active.
	private static let activeStagingOutput = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.

	#if !(STAGING)
	#error("SafeDI scanned this module assuming `#if STAGING` was active, but it is inactive in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
	#endif

	""" + "\n"

	private static let mockGeneratingLoggerContent = """
	public protocol Logger {}

	#if STAGING
	@Instantiable(fulfillingAdditionalTypes: [Logger.self], generateMock: true)
	public struct StagingLogger: Logger, Instantiable {
	    public init() {}
	}
	#else
	@Instantiable(fulfillingAdditionalTypes: [Logger.self])
	public struct ProductionLogger: Logger, Instantiable {
	    public init() {}
	}
	#endif
	"""

	private static let stagingConfigurationContent = """
	#if STAGING
	#SafeDIConfiguration(additionalImportedModules: ["Foundation"])
	#endif
	"""

	private static let additionalMockConfigurationContent = """
	#if STAGING
	#SafeDIConfiguration(additionalMocksToGenerate: ["ProductionLogger"])
	#else
	#SafeDIConfiguration()
	#endif
	"""

	private var filesToDelete: [URL]

	/// A module whose only configuration, in an `#if STAGING` block, includes a directory holding a root.
	private struct AdditionalDirectoryProject {
		/// The fixture directory, under the working directory, which is the project root as with a build tool plugin.
		let directory: URL
		/// `directory` relative to the working directory, which is how the plugin and the configuration name it.
		let relativeDirectoryPath: String
		let swiftFileCSV: URL
		let outputDirectory: URL
		let manifestFile: URL

		/// Runs `generate` with `buildSettingArguments` and returns the root's generated file.
		@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
		func generate(buildSettingArguments: [String]) async throws -> String {
			_ = try await Generate.parse([
				swiftFileCSV.path,
				"--swift-manifest", manifestFile.path,
			] + buildSettingArguments).generate()
			return try String(contentsOf: outputDirectory.appendingPathComponent("StagingRoot+SafeDI.swift"), encoding: .utf8)
		}
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func scannedAdditionalDirectoryProject() async throws -> AdditionalDirectoryProject {
		let relativeDirectoryPath = ".build/SafeDIToolTestFixtures/\(UUID().uuidString)"
		let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
		let directory = currentDirectory.appendingPathComponent(relativeDirectoryPath)
		try FileManager.default.createDirectory(at: directory.appendingPathComponent("Target"), withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: directory.appendingPathComponent("Additional"), withIntermediateDirectories: true)
		try """
		#if STAGING
		#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(relativeDirectoryPath)/Additional"])
		#endif
		""".write(to: directory.appendingPathComponent("Target/SafeDIConfiguration.swift"), atomically: true, encoding: .utf8)
		try """
		@Instantiable(isRoot: true)
		public struct StagingRoot: Instantiable {
		    public init(dependency: Dependency) {
		        self.dependency = dependency
		    }

		    @Instantiated let dependency: Dependency
		}

		@Instantiable
		public struct Dependency: Instantiable {
		    public init() {}
		}
		""".write(to: directory.appendingPathComponent("Additional/StagingRoot.swift"), atomically: true, encoding: .utf8)
		let swiftFileCSV = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try "\(relativeDirectoryPath)/Target/SafeDIConfiguration.swift".write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
		let manifestFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
		filesToDelete += [directory, swiftFileCSV, outputDirectory, manifestFile, scannedModuleInfoURL(forManifestPath: manifestFile.path)]

		try await Scan.parse([
			"--input-sources-file", swiftFileCSV.path,
			"--project-root", currentDirectory.path,
			"--output-directory", outputDirectory.path,
			"--manifest-file", manifestFile.path,
		]).run()
		return AdditionalDirectoryProject(
			directory: directory,
			relativeDirectoryPath: relativeDirectoryPath,
			swiftFileCSV: swiftFileCSV,
			outputDirectory: outputDirectory,
			manifestFile: manifestFile,
		)
	}

	private static func buildSettingArguments(activeCompilationConditions: String = "", otherSwiftFlags: String = "") -> [String] {
		[
			"--build-setting-active-compilation-conditions=[\(activeCompilationConditions)]",
			"--build-setting-other-swift-flags=[\(otherSwiftFlags)]",
		]
	}

	private static let rootContent = """
	@Instantiable(isRoot: true)
	public struct Root: Instantiable {
	    public init(logger: Logger) {
	        self.logger = logger
	    }

	    @Instantiated let logger: Logger
	}
	"""

	private static let renamedRootContent = """
	@Instantiable(isRoot: true)
	public struct Root: Instantiable {
	    public init(renamedLogger: Logger) {
	        self.renamedLogger = renamedLogger
	    }

	    @Instantiated let renamedLogger: Logger
	}
	"""

	private static let guardedRootContent = """
	#if STAGING
	@Instantiable(isRoot: true)
	public struct StagingRoot: Instantiable {
	    public init(logger: Logger) {
	        self.logger = logger
	    }

	    @Instantiated let logger: Logger
	}
	#endif
	"""

	private static let loggerContent = """
	public protocol Logger {}

	#if STAGING
	@Instantiable(fulfillingAdditionalTypes: [Logger.self])
	public struct StagingLogger: Logger, Instantiable {
	    public init() {}
	}
	#else
	@Instantiable(fulfillingAdditionalTypes: [Logger.self])
	public struct ProductionLogger: Logger, Instantiable {
	    public init() {}
	}
	#endif
	"""

	/// `loggerContent` with each logger renamed, which only a fresh parse sees.
	private static let renamedLoggerContent = """
	public protocol Logger {}

	#if STAGING
	@Instantiable(fulfillingAdditionalTypes: [Logger.self])
	public struct RenamedStagingLogger: Logger, Instantiable {
	    public init() {}
	}
	#else
	@Instantiable(fulfillingAdditionalTypes: [Logger.self])
	public struct RenamedProductionLogger: Logger, Instantiable {
	    public init() {}
	}
	#endif
	"""

	private static let unconditionalLoggerContent = """
	public protocol Logger {}

	@Instantiable(fulfillingAdditionalTypes: [Logger.self])
	public struct ProductionLogger: Logger, Instantiable {
	    public init() {}
	}
	"""

	/// `unconditionalLoggerContent` with the logger renamed, which only a fresh parse sees.
	private static let renamedUnconditionalLoggerContent = """
	public protocol Logger {}

	@Instantiable(fulfillingAdditionalTypes: [Logger.self])
	public struct RenamedLogger: Logger, Instantiable {
	    public init() {}
	}
	"""

	private static let stagingRootOutput = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.

	#if !(STAGING)
	#error("SafeDI scanned this module assuming `#if STAGING` was active, but it is inactive in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
	#endif

	extension Root {
	    public init() {
	        let logger: Logger = StagingLogger()
	        self.init(logger: logger)
	    }
	}
	"""

	private static let renamedStagingRootOutput = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.

	#if !(STAGING)
	#error("SafeDI scanned this module assuming `#if STAGING` was active, but it is inactive in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
	#endif

	extension Root {
	    public init() {
	        let logger: Logger = RenamedStagingLogger()
	        self.init(logger: logger)
	    }
	}
	"""

	private static let productionRootOutput = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.

	#if STAGING
	#error("SafeDI scanned this module assuming `#if STAGING` was inactive, but it is active in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
	#endif

	extension Root {
	    public init() {
	        let logger: Logger = ProductionLogger()
	        self.init(logger: logger)
	    }
	}
	"""

	private static let unconditionalRootOutput = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.

	extension Root {
	    public init() {
	        let logger: Logger = ProductionLogger()
	        self.init(logger: logger)
	    }
	}
	"""

	private static let renamedUnconditionalRootOutput = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.

	extension Root {
	    public init() {
	        let logger: Logger = RenamedLogger()
	        self.init(logger: logger)
	    }
	}
	"""
}
