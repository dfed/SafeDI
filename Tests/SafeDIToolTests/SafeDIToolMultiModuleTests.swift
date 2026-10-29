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

/// How `executeSafeDIToolMultiModuleTest` runs several modules through the tool and the compiler, under each
/// integration, and what the compiler enforces between modules that the tool's own checks do not.
struct SafeDIToolMultiModuleTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Harness

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_generatesRootFromGrandparentDeclarations_whenModuleListsEveryModuleItsTreeNeeds(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.transitiveChain,
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		#expect(output.moduleNames == ["Core", "Middle", "App"])
		for moduleName in output.moduleNames {
			#expect(try #require(output.modules[moduleName]).warnings == [])
		}
		let rootCode = """
		extension Root {
		    public convenience init() {
		        func __safeDI_pump() -> Pump {
		            let engine = Engine()
		            return Pump(engine: engine)
		        }
		        let pump: Pump = __safeDI_pump()
		        self.init(pump: pump)
		    }
		}
		"""
		let expectedGeneratedFiles: [String: [String: String]] = switch integration {
		case .moduleInfo:
			// A combined file repeats the module's imports whether or not it holds code.
			[
				"Core": ["Core.swift": generatedFileHeader],
				"Middle": ["Middle.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n"],
				"App": ["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Middle") + "\n\n" + rootCode],
			]
		case .swiftPackagePlugin:
			[
				"Core": [:],
				"Middle": [:],
				"App": ["Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Middle") + "\n\n" + rootCode],
			]
		}
		#expect(output.modules.mapValues(\.generatedFiles) == expectedGeneratedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_throwsErrorForGrandparentDeclaration_whenModuleInfoListsOnlyTheDirectDependency() async {
		// Bazel lists a target's direct `deps` and a Tuist user lists modules by name, so a module whose tree
		// reaches a declaration two levels down sees it only when that module is listed too.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Middle"]!["Pump.swift"]):8:5: error: No @Instantiable type or extension fulfills `Engine`, which @Instantiated property `engine: Engine` instantiates. Decorate `Engine`, or an extension of it, with @Instantiable; list `Engine` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; or, if such a declaration is in another module, make that module one SafeDI reads for this target.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.transitiveChain[0],
					Self.transitiveChain[1],
					ModuleFixture(
						name: "App",
						packageName: "Pipeline",
						swiftFileContent: [Self.rootInstantiatingPumpContent],
						dependencies: ["Middle"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_compilesEveryModule_whenDependenciesGenerateNothing(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.transitiveChain,
			integration: integration,
			compileVerification: .recordingIssues,
			filesToDelete: &filesToDelete,
		)

		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		#expect(compilation.modules.map(\.moduleName) == ["Core", "Middle", "App"])
		#expect(compilation.modules.map(\.exitCode) == [0, 0, 0])
		#expect(compilation.failure == nil)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_runsGenerateOnlyForModulesWhoseManifestPlansAnOutput_whenIntegrationIsThePlugin(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.transitiveChain,
			integration: integration,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)

		// The plugin adds a build command only for a module whose manifest plans an output; Bazel runs
		// `generate` for every module, since every module's `.safedi` comes from it.
		let expectedGenerateRuns: [String: Bool] = switch integration {
		case .moduleInfo:
			["Core": true, "Middle": true, "App": true]
		case .swiftPackagePlugin:
			["Core": false, "Middle": false, "App": true]
		}
		#expect(output.modules.mapValues(\.generateRan) == expectedGenerateRuns)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_writesModuleInfoDecodingToModuleDeclarations_whenIntegrationIsModuleInfo() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.transitiveChain,
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)

		let middle = try #require(output.modules["Middle"])
		let moduleInfoOutputPath = try #require(middle.moduleInfoOutputPath)
		#expect(FileManager.default.fileExists(atPath: moduleInfoOutputPath))
		let writtenModuleInfo = try ModuleInfo(moduleInfoData: Data(contentsOf: URL(fileURLWithPath: moduleInfoOutputPath)))
		#expect(writtenModuleInfo.instantiables.map(\.concreteInstantiable.asSource) == ["Pump"])
		#expect(try #require(middle.moduleInfo).instantiables.map(\.concreteInstantiable.asSource) == ["Pump"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_writesNoModuleInfo_whenIntegrationIsThePlugin() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.transitiveChain,
			integration: .swiftPackagePlugin,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)

		for moduleName in output.moduleNames {
			let module = try #require(output.modules[moduleName])
			#expect(module.moduleInfo == nil)
			#expect(module.moduleInfoOutputPath == nil)
		}
		let moduleInfoFiles = try #require(FileManager.default.enumerator(atPath: output.fixtureRoot.path)?.allObjects as? [String])
			.filter { $0.hasSuffix(".safedi") }
		#expect(moduleInfoFiles == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_throwsError_whenDependencyNamesLaterModule() async {
		await assertThrowsError("Module App depends on Core, which must be listed before it.") {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "App", packageName: "Pipeline", swiftFileContent: [], dependencies: ["Core"]),
					ModuleFixture(name: "Core", packageName: "Pipeline", swiftFileContent: []),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_throwsError_whenModuleIsDeclaredTwice() async {
		await assertThrowsError("Module Core is declared twice.") {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Pipeline", swiftFileContent: []),
					ModuleFixture(name: "Core", packageName: "Toolkit", swiftFileContent: []),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_throwsErrorNamingModuleAndCitingItsFixture_whenGenerateFails(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			// The path the file was parsed under: the CSV's absolute path under Bazel's invocation, and the
			// compiler's spelling normalized under the plugin's.
			let rootPath = switch integration {
			case .moduleInfo:
				fixtures["App"]!["Root.swift"]
			case .swiftPackagePlugin:
				NormalizedFilePath(fixtures["App"]!.compilerPath(of: "Root.swift")).path
			}
			return """
			\(rootPath):10:5: error: No @Instantiable type or extension fulfills `Missing`, which @Instantiated property `missing: Missing` instantiates. Decorate `Missing`, or an extension of it, with @Instantiable; list `Missing` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; or, if such a declaration is in another module, make that module one SafeDI reads for this target.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.transitiveChain[0],
					ModuleFixture(
						name: "App",
						packageName: "Pipeline",
						swiftFileContent: [
							"""
							import Core

							@Instantiable(isRoot: true)
							public final class Root: Instantiable {
							    public init(engine: Engine, missing: Missing) {
							        self.engine = engine
							        self.missing = missing
							    }
							    @Instantiated let engine: Engine
							    @Instantiated let missing: Missing
							}
							""",
						],
						dependencies: ["Core"],
					),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_regeneratesDependencyRootInConsumer_whenRunUnderThePluginIntegrationOnly(integration: MultiModuleIntegration) async throws {
		// `scan` plans a dependency-tree output for every file in its CSV that declares a root, and the plugin's
		// CSV lists the dependencies' files, so every consumer writes the dependency's root again; Bazel's
		// combined file holds only the module's own roots. This pins that behaviour as it is today.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.dependencyDeclaringRoot,
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let coreRootCode = """
		extension CoreRoot {
		    public convenience init() {
		        let engine = Engine()
		        self.init(engine: engine)
		    }
		}
		"""
		let expectedGeneratedFiles: [String: [String: String]] = switch integration {
		case .moduleInfo:
			[
				"Core": ["Core.swift": generatedFileHeader + coreRootCode],
				"App": ["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + Self.rootInstantiatingEngineCode],
			]
		case .swiftPackagePlugin:
			[
				"Core": ["CoreRoot+SafeDI.swift": generatedFileHeader + coreRootCode],
				"App": [
					"CoreRoot+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + coreRootCode,
					"Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + Self.rootInstantiatingEngineCode,
				],
			]
		}
		#expect(output.modules.mapValues(\.generatedFiles) == expectedGeneratedFiles)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_referencesAliasDeclarationByDirective_whenAliasIsFulfilledByDependencyType(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.transitiveChain[0],
				ModuleFixture(
					name: "App",
					packageName: "Pipeline",
					swiftFileContent: [
						"""
						import Core

						@Instantiable
						public final class Car: Instantiable {
						    public init(motor: Engine) {
						        self.motor = motor
						    }
						    @Received(fulfilledByDependencyNamed: "engine", ofType: Engine.self) let motor: Engine
						}
						""",
						"""
						import Core

						@Instantiable(isRoot: true)
						public final class Root: Instantiable {
						    public init(engine: Engine, car: Car) {
						        self.engine = engine
						        self.car = car
						    }
						    @Instantiated let engine: Engine
						    @Instantiated let car: Car
						}
						""",
					],
					dependencies: ["Core"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		// The directive names the file as the compiler is handed it: the CSV's absolute path under Bazel's
		// invocation, and the reported package directory joined with the CSV's relative path under the plugin's.
		let app = try #require(output.modules["App"])
		let carPath = switch integration {
		case .moduleInfo:
			app.fixtures["Car.swift"]
		case .swiftPackagePlugin:
			app.fixtures.compilerPath(of: "Car.swift")
		}
		let rootCode = """
		extension Root {
		    public convenience init() {
		        let engine = Engine()
		        func __safeDI_car() -> Car {
		            #sourceLocation(file: "\(carPath)", line: 8)
		            let motor: Engine = engine
		            #sourceLocation()
		            return Car(motor: motor)
		        }
		        let car: Car = __safeDI_car()
		        self.init(engine: engine, car: car)
		    }
		}
		"""
		let expectedGeneratedFiles: [String: String] = switch integration {
		case .moduleInfo:
			["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + rootCode]
		case .swiftPackagePlugin:
			["Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + rootCode]
		}
		#expect(app.generatedFiles == expectedGeneratedFiles)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_scansConditionalDeclaration_whenConditionIsActive(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Core",
					packageName: "Pipeline",
					swiftFileContent: [
						"""
						#if FEATURE
						@Instantiable
						public final class Engine: Instantiable {
						    public init() {}
						}
						#endif
						""",
					],
					activeCompilationConditions: ["FEATURE"],
				),
				ModuleFixture(
					name: "App",
					packageName: "Pipeline",
					swiftFileContent: [Self.rootInstantiatingEngineContent],
					dependencies: ["Core"],
					activeCompilationConditions: ["FEATURE"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		// The assertion comes from the files a module parses: the dependency's file under the plugin's CSV, and
		// only the module's own files under Bazel's.
		let expectedGeneratedFiles: [String: [String: String]] = switch integration {
		case .moduleInfo:
			[
				"Core": ["Core.swift": generatedFileHeader + Self.activeConditionAssertion("FEATURE")],
				"App": ["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + Self.rootInstantiatingEngineCode],
			]
		case .swiftPackagePlugin:
			[
				"Core": [:],
				"App": ["Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + Self.activeConditionAssertion("FEATURE") + Self.rootInstantiatingEngineCode],
			]
		}
		#expect(output.modules.mapValues(\.generatedFiles) == expectedGeneratedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_replacesConditionsScanReported_whenBuildSettingsArriveExpanded() async throws {
		// Swift Build expands the plugin's build-setting arguments, and what they report replaces what `scan`
		// was given: `FEATURE` is gone, so the root `scan` planned a file for is inactive, and `Xcode`, from the
		// `-D` among the flags, is active.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "App",
					packageName: "Pipeline",
					swiftFileContent: [
						"""
						#if Xcode
						@Instantiable
						public final class Engine: Instantiable {
						    public init() {}
						}
						#endif
						""",
						"""
						#if FEATURE
						@Instantiable(isRoot: true)
						public final class Root: Instantiable {
						    public init(engine: Engine) {
						        self.engine = engine
						    }
						    @Instantiated let engine: Engine
						}
						#endif
						""",
					],
					activeCompilationConditions: ["FEATURE"],
					buildSettingArguments: swiftBuildExpandedBuildSettingArguments,
					verificationCompilationConditions: ["SWIFT_PACKAGE", "SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE", "Xcode"],
				),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)

		let app = try #require(output.modules["App"])
		#expect(app.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + Self.inactiveConditionAssertion("FEATURE") + Self.activeConditionAssertion("Xcode"),
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_wrapsMocksInConfiguredCondition_whenConfigurationFileNamesOne(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [Self.configuredMockModule],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let mockCode = """
		#if MOCKS
		extension Service {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            engine: (() -> Engine)? = nil
		        ) {
		            self.engine = engine
		        }

		        let engine: (() -> Engine)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let engine = if let safeDIBuilder = safeDIOverrides.engine { safeDIBuilder() } else { Engine() }
		        return Service(engine: engine)
		    }
		}
		#endif
		"""
		let expectedGeneratedFiles: [String: String] = switch integration {
		case .moduleInfo:
			["Services.swift": generatedFileHeader + mockCode]
		case .swiftPackagePlugin:
			[
				"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
				"Service+SafeDIMock.swift": generatedFileHeader + mockCode,
			]
		}
		let services = try #require(output.modules["Services"])
		#expect(services.generatedFiles == expectedGeneratedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_generatesAgainstCheckoutDeclarations_whenConfigurationIncludesCheckoutDirectory() async throws {
		// The plugin leaves a checkout package's files out of the CSV, so a consumer reads its declarations only
		// through `additionalDirectoriesToInclude`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.checkoutShared,
				Self.consumerOfCheckoutShared(swiftFileContentByFilePath: [
					"SafeDIConfiguration.swift": """
					#SafeDIConfiguration(additionalDirectoriesToInclude: ["$FIXTURE_ROOT/checkouts/Toolkit/Sources/Shared"])
					""",
				]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)

		let app = try #require(output.modules["App"])
		#expect(app.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Shared") + "\n\n" + Self.rootInstantiatingEngineCode,
		])
		// A found file outside the package is listed by its normalized path.
		let engineFile = output.fixtureRoot.appendingPathComponent("checkouts/Toolkit/Sources/Shared/Engine.swift")
		#expect(try #require(app.scanManifest).additionalInputFiles == [NormalizedFilePath(engineFile.path).path])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_throwsErrorForCheckoutDeclaration_whenConfigurationDoesNotIncludeCheckoutDirectory() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(NormalizedFilePath(fixtures["App"]!.compilerPath(of: "Root.swift")).path):8:5: error: No @Instantiable type or extension fulfills `Engine`, which @Instantiated property `engine: Engine` instantiates. Decorate `Engine`, or an extension of it, with @Instantiable; list `Engine` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; or, if such a declaration is in another module, make that module one SafeDI reads for this target.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.checkoutShared,
					Self.consumerOfCheckoutShared(swiftFileContentByFilePath: [:]),
				],
				integration: .swiftPackagePlugin,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func queryTestModule_servesQueryWithPathNamedFile_whenConvertedFromModuleFixture() async throws {
		// `Engine` has no mock of its own: the report says one is generated only because the converted module's
		// path-named `SafeDIConfiguration.swift` lists it.
		let output = try await executeSafeDIToolQuery(
			typeName: "Engine",
			modules: [
				Self.transitiveChain[0].queryTestModule,
				ModuleFixture(
					name: "Services",
					packageName: "Pipeline",
					swiftFileContent: [
						"""
						import Core

						@Instantiable
						public final class Service: Instantiable {
						    public init(engine: Engine) {
						        self.engine = engine
						    }
						    @Instantiated let engine: Engine
						}
						""",
					],
					swiftFileContentByFilePath: [
						"SafeDIConfiguration.swift": """
						#SafeDIConfiguration(additionalMocksToGenerate: ["Engine"])
						""",
					],
					dependencies: ["Core"],
				).queryTestModule,
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.formatted == """
		`Engine` is built from declarations in 1 module:

		Core
		  @Instantiable Engine

		@Forwarded parameters of `Engine`:
		  (none)

		Dependencies of `Engine` no @Instantiable declaration fulfills:
		  (none)

		`Engine.mock()` is generated in Services from the same declarations.

		A project without Services generates `Engine.mock()` by listing `Engine` in `additionalMocksToGenerate` of a #SafeDIConfiguration.

		Required @Forwarded parameters of `Engine.mock()`:
		  (none)

		Defaulted @Forwarded parameters of `Engine.mock()`:
		  (none)

		Required parameters of `Engine.mock()` that no @Instantiable declaration removes:
		  (none)
		""")
	}

	// MARK: Tests – Access between modules

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_reportsCompileFailure_whenInternalTypeIsUsedFromAnotherModuleOfItsPackage(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Helpers",
					packageName: "Pipeline",
					swiftFileContent: [
						"""
						struct InternalHelper {
						    init() {}
						}
						""",
					],
				),
				Self.consumer(of: "InternalHelper", inPackage: "Pipeline"),
			],
			integration: integration,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)

		#expect(try #require(output.modules["App"]).generatedFiles.keys.sorted() == Self.consumerGeneratedFileNames(under: integration))
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		#expect(compilation.modules.map(\.moduleName) == ["Helpers", "App"])
		#expect(compilation.modules.map { $0.exitCode == 0 } == [true, false])
		#expect(compilation.modules[0].generatedCodeWarnings.isEmpty)
		let failure = try #require(compilation.failure)
		#expect(failure.moduleName == "App")
		#expect(failure.standardError.contains("cannot find 'InternalHelper' in scope"), "Unexpected compiler output \(failure.standardError)")
		expectInputsFailedOnTheirOwn(failure)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_reportsCompileFailure_whenPackageTypeIsUsedFromAnotherPackage(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.packageHelpers(inPackage: "Toolkit"),
				Self.consumer(of: "PackageHelper", inPackage: "Pipeline"),
			],
			integration: integration,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)

		#expect(try #require(output.modules["App"]).generatedFiles.keys.sorted() == Self.consumerGeneratedFileNames(under: integration))
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		#expect(compilation.modules.map(\.moduleName) == ["Helpers", "App"])
		#expect(compilation.modules.map { $0.exitCode == 0 } == [true, false])
		#expect(compilation.modules[0].generatedCodeWarnings.isEmpty)
		let failure = try #require(compilation.failure)
		#expect(failure.moduleName == "App")
		#expect(failure.standardError.contains("cannot find 'PackageHelper' in scope"), "Unexpected compiler output \(failure.standardError)")
		expectInputsFailedOnTheirOwn(failure)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_compilesEveryModule_whenPackageTypeIsUsedFromAnotherModuleOfItsPackage(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.packageHelpers(inPackage: "Pipeline"),
				Self.consumer(of: "PackageHelper", inPackage: "Pipeline"),
			],
			integration: integration,
			compileVerification: .recordingIssues,
			filesToDelete: &filesToDelete,
		)

		#expect(try #require(output.modules["App"]).generatedFiles.keys.sorted() == Self.consumerGeneratedFileNames(under: integration))
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		#expect(compilation.modules.map(\.moduleName) == ["Helpers", "App"])
		#expect(compilation.modules.map(\.exitCode) == [0, 0])
		#expect(compilation.failure == nil)
	}

	// MARK: Private

	/// The lines a generated file repeats for a fixture's `import <moduleName>`.
	private static func importBlock(_ moduleName: String) -> String {
		"""
		#if canImport(\(moduleName))
		import \(moduleName)
		#endif
		"""
	}

	/// The compile-time assertion a generated file carries for a `#if <condition>` the tool evaluated as active,
	/// ending with the blank line that precedes the code.
	private static func activeConditionAssertion(_ condition: String) -> String {
		"""
		#if !(\(condition))
		#error("SafeDI scanned this module assuming `#if \(condition)` was active, but it is inactive in this compilation. Report the conditions this target compiles with to SafeDITool, as the \\"Reporting active conditions\\" section of the SafeDI manual describes for your build system.")
		#endif

		""" + "\n"
	}

	/// The compile-time assertion a generated file carries for a `#if <condition>` the tool evaluated as inactive,
	/// ending with the blank line that precedes the code.
	private static func inactiveConditionAssertion(_ condition: String) -> String {
		"""
		#if \(condition)
		#error("SafeDI scanned this module assuming `#if \(condition)` was inactive, but it is active in this compilation. Report the conditions this target compiles with to SafeDITool, as the \\"Reporting active conditions\\" section of the SafeDI manual describes for your build system.")
		#endif

		""" + "\n"
	}

	/// The names of the files the `consumer(of:inPackage:)` module generates under `integration`.
	private static func consumerGeneratedFileNames(under integration: MultiModuleIntegration) -> [String] {
		switch integration {
		case .moduleInfo:
			["App.swift"]
		case .swiftPackagePlugin:
			["Consumer+SafeDI.swift"]
		}
	}

	private static let engineContent = """
	@Instantiable
	public final class Engine: Instantiable {
	    public init() {}
	}
	"""

	/// A root in a module that depends on `Core`, instantiating `Core`'s `Engine`.
	private static let rootInstantiatingEngineContent = """
	import Core

	@Instantiable(isRoot: true)
	public final class Root: Instantiable {
	    public init(engine: Engine) {
	        self.engine = engine
	    }
	    @Instantiated let engine: Engine
	}
	"""

	/// The code generated for a root instantiating `Engine` alone.
	private static let rootInstantiatingEngineCode = """
	extension Root {
	    public convenience init() {
	        let engine = Engine()
	        self.init(engine: engine)
	    }
	}
	"""

	/// A root in a module that depends on `Middle`, instantiating `Middle`'s `Pump`.
	private static let rootInstantiatingPumpContent = """
	import Middle

	@Instantiable(isRoot: true)
	public final class Root: Instantiable {
	    public init(pump: Pump) {
	        self.pump = pump
	    }
	    @Instantiated let pump: Pump
	}
	"""

	/// A `Helpers` module of `packageName` declaring a `package` type, which only the package's other modules see.
	private static func packageHelpers(inPackage packageName: String) -> ModuleFixture {
		ModuleFixture(
			name: "Helpers",
			packageName: packageName,
			swiftFileContent: [
				"""
				package struct PackageHelper {
				    package init() {}
				}
				""",
			],
		)
	}

	/// An `App` module of `packageName` depending on `Helpers`, whose root stores a `helperTypeName` value
	/// alongside the dependency the tool builds, so the module both generates code and uses the helper.
	private static func consumer(of helperTypeName: String, inPackage packageName: String) -> ModuleFixture {
		ModuleFixture(
			name: "App",
			packageName: packageName,
			swiftFileContent: [
				engineContent,
				"""
				import Helpers

				@Instantiable(isRoot: true)
				public final class Consumer: Instantiable {
				    public init(engine: Engine) {
				        self.engine = engine
				        helper = \(helperTypeName)()
				    }
				    @Instantiated let engine: Engine
				    private let helper: \(helperTypeName)
				}
				""",
			],
			dependencies: ["Helpers"],
		)
	}

	/// Expects `outcome`'s inputs to have failed on their own, before any generated code.
	private func expectInputsFailedOnTheirOwn(_ outcome: ModuleCompileOutcome, sourceLocation: SourceLocation = #_sourceLocation) {
		switch outcome.failure {
		case .inputsFailedOnTheirOwn:
			break
		case .generatedCodeFailedAlongsideInputs, nil:
			Issue.record("Expected \(outcome.moduleName)'s inputs to fail on their own, but its failure is \(String(describing: outcome.failure)).", sourceLocation: sourceLocation)
		}
	}

	/// Three modules of one package, each depending on the one before it. `App`'s root is built from a
	/// declaration two modules down, so `App` lists `Core` as well as `Middle`, as a Bazel or Tuist user must:
	/// `.moduleInfo` reads only the listed modules' `.safedi`, while the plugin's CSV lists the transitive
	/// closure's files either way.
	private static let transitiveChain = [
		ModuleFixture(
			name: "Core",
			packageName: "Pipeline",
			swiftFileContent: [engineContent],
		),
		ModuleFixture(
			name: "Middle",
			packageName: "Pipeline",
			swiftFileContent: [
				"""
				import Core

				@Instantiable
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
			packageName: "Pipeline",
			swiftFileContent: [rootInstantiatingPumpContent],
			dependencies: ["Middle", "Core"],
		),
	]

	/// A dependency that declares a root of its own, and a consumer whose root builds the same type.
	private static let dependencyDeclaringRoot = [
		ModuleFixture(
			name: "Core",
			packageName: "Pipeline",
			swiftFileContent: [
				engineContent,
				"""
				@Instantiable(isRoot: true)
				public final class CoreRoot: Instantiable {
				    public init(engine: Engine) {
				        self.engine = engine
				    }
				    @Instantiated let engine: Engine
				}
				""",
			],
		),
		ModuleFixture(
			name: "App",
			packageName: "Pipeline",
			swiftFileContent: [rootInstantiatingEngineContent],
			dependencies: ["Core"],
		),
	]

	/// A module whose `SafeDIConfiguration.swift` wraps its mocks in `MOCKS`.
	private static let configuredMockModule = ModuleFixture(
		name: "Services",
		packageName: "Pipeline",
		swiftFileContent: [
			engineContent,
			"""
			@Instantiable(generateMock: true)
			public final class Service: Instantiable {
			    public init(engine: Engine) {
			        self.engine = engine
			    }
			    @Instantiated let engine: Engine
			}
			""",
		],
		swiftFileContentByFilePath: [
			"SafeDIConfiguration.swift": """
			#SafeDIConfiguration(mockConditionalCompilation: "MOCKS")
			""",
		],
		mockConditionalCompilation: "MOCKS",
	)

	/// A module of a checkout package, declaring `Engine`.
	private static let checkoutShared = ModuleFixture(
		name: "Shared",
		packageName: "Toolkit",
		swiftFileContent: [engineContent],
		isCheckoutPackage: true,
	)

	/// An `App` module depending on the checkout's `Shared`, whose root instantiates its `Engine`, with the
	/// given explicitly named files.
	private static func consumerOfCheckoutShared(swiftFileContentByFilePath: [String: String]) -> ModuleFixture {
		ModuleFixture(
			name: "App",
			packageName: "Pipeline",
			swiftFileContent: [
				"""
				import Shared

				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(engine: Engine) {
				        self.engine = engine
				    }
				    @Instantiated let engine: Engine
				}
				""",
			],
			swiftFileContentByFilePath: swiftFileContentByFilePath,
			dependencies: ["Shared"],
		)
	}

	private var filesToDelete: [URL]
}
