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
	mutating func generate_throwsError_whenBuildSettingValueIsNotBracketed() async throws {
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

	// MARK: Tests – Declarations scan cannot see

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenBuildSettingsActivateRootScanDidNotFind() async throws {
		await assertThrowsError(diagnostics: { Self.rootNotInManifestMessage(path: $0["StagingRoot.swift"]) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.guardedRootContent, Self.unconditionalLoggerContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenBuildSettingsDeactivateRootScanFound() async throws {
		await assertThrowsError(diagnostics: { Self.noRootFoundMessage(path: $0["StagingRoot.swift"]) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.guardedRootContent, Self.unconditionalLoggerContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["STAGING"],
				buildSettingArguments: Self.buildSettingArguments(),
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenBuildSettingsActivateMockGeneratingTypeScanDidNotFind() async throws {
		await assertThrowsError(diagnostics: { Self.mockNotInManifestMessage(type: "StagingLogger", path: $0["StagingLogger.swift"]) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.rootContent,
					"""
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
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenBuildSettingsActivateConfigurationScanDidNotFind() async throws {
		await assertThrowsError(diagnostics: { Self.configurationNotInManifestMessage(path: $0["SafeDIConfiguration.swift"]) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.rootContent, Self.unconditionalLoggerContent],
				swiftFileContentByFilePath: ["SafeDIConfiguration.swift": """
				#if STAGING
				#SafeDIConfiguration(additionalImportedModules: ["Foundation"])
				#endif
				"""],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenBuildSettingsDeactivateConfigurationScanFound() async throws {
		await assertThrowsError(diagnostics: { Self.noConfigurationFoundMessage(path: $0["SafeDIConfiguration.swift"]) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.rootContent, Self.unconditionalLoggerContent],
				swiftFileContentByFilePath: ["SafeDIConfiguration.swift": """
				#if !STAGING
				#SafeDIConfiguration(additionalImportedModules: ["Foundation"])
				#endif
				"""],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenBuildSettingsSelectConfigurationWithOtherAdditionalMocks() async throws {
		await assertThrowsError(diagnostics: { fixtures in
			"The #SafeDIConfiguration in '\(fixtures["SafeDIConfiguration.swift"])' lists [\"ProductionLogger\"] in additionalMocksToGenerate, but the manifest lists []. If an `#if` block declares the configuration, \(Self.planningExplanation) Declare the configuration outside the `#if` block."
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.rootContent, Self.unconditionalLoggerContent],
				swiftFileContentByFilePath: ["SafeDIConfiguration.swift": """
				#if STAGING
				#SafeDIConfiguration(additionalMocksToGenerate: ["ProductionLogger"])
				#else
				#SafeDIConfiguration()
				#endif
				"""],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				buildSettingArguments: Self.buildSettingArguments(activeCompilationConditions: "STAGING"),
			)
		}
	}

	// MARK: Private

	private static func configurationNotInManifestMessage(path: String) -> String {
		"Found #SafeDIConfiguration in '\(path)', but this file is not listed in the manifest’s configurationFilePaths. If an `#if` block declares the configuration, \(planningExplanation) Declare the configuration outside the `#if` block."
	}

	private static func noConfigurationFoundMessage(path: String) -> String {
		"Manifest lists '\(path)' as declaring a #SafeDIConfiguration, but none was found in that file. If an `#if` block declares the configuration, \(planningExplanation) Declare the configuration outside the `#if` block."
	}

	private var filesToDelete: [URL]

	private static func buildSettingArguments(activeCompilationConditions: String = "", otherSwiftFlags: String = "") -> [String] {
		[
			"--build-setting-active-compilation-conditions=[\(activeCompilationConditions)]",
			"--build-setting-other-swift-flags=[\(otherSwiftFlags)]",
		]
	}

	private static let planningExplanation = "SafeDI evaluated it differently when it decided which files to generate, which happens before the build with only the compilation conditions the build tool plugin can see, such as a target’s `swiftSettings` defines but not SwiftPM’s `DEBUG`."

	private static func rootNotInManifestMessage(path: String) -> String {
		"Found @Instantiable(isRoot: true) in '\(path)', but this file is not listed in the manifest’s dependencyTreeGeneration. If an `#if` block declares the root, \(planningExplanation) Declare the root outside the `#if` block. A hand-written manifest must list the file, or the type must not be a root."
	}

	private static func noRootFoundMessage(path: String) -> String {
		"Manifest lists '\(path)' as containing a dependency tree root, but no @Instantiable(isRoot: true) was found in that file. If an `#if` block declares the root, \(planningExplanation) Declare the root outside the `#if` block."
	}

	private static func mockNotInManifestMessage(type: String, path: String) -> String {
		"Found @Instantiable(generateMock: true) on `\(type)` in '\(path)', but this file is not listed in the manifest’s mockGeneration. If an `#if` block declares the type, \(planningExplanation) Declare the type outside the `#if` block, or remove `generateMock: true`."
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
