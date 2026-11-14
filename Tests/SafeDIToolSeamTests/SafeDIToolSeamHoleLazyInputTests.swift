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
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// What a hole's implementation is handed for a value the seam takes as an `@autoclosure`: the seam hands the hole's
/// struct the `LazilyInstantiated` it holds the value in, behind a field that reads its instance, so a hand-written
/// implementation creates the value when it reads the field, and the implementation the app generates reads the
/// app's own declaration of the label, as inline, so the value is created when the implementation uses it. A
/// `@Sendable` function in the implementation that reads a wrapper the app declares is reported, as inline.
struct SafeDIToolSeamHoleLazyInputTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Generated and hand-written implementations

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsHolesStructSeamsMemo_whenGeneratedAndHandWrittenImplementationsReadDeferredValue(integration: MultiModuleIntegration) async throws {
		// `ExportFeature` defers `exportService` and hands the hole's struct its memo, whose field reads the instance.
		// `Root`'s fill reads `Root`'s own `exportService` inside `jobBuilder`, as inline, and `makeHandBuilt()`'s
		// hand-written fill reads the struct's field there: each service is created when its `UploadJob` is built.
		let feature = Self.feature()
		let app = Self.app(declarations: Self.uploaderBuildingJobs, handWrittenFill: Self.handWrittenFillReadingField)
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app, featureConfiguration: plainDependencyTreeInitializersConfiguration), integration: integration, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", integration: integration, imports: [], rootFiles: [
			"ExportFeature": """
			extension ExportFeature {
			    @frozen public enum SafeDIScope_Uploader {
			        case uploader(uploader_Values)

			        public struct uploader_Values {
			            public var exportService: ExportService { __safeDI_exportService.instance }
			            public let screenBuilder: Instantiator<ExportScreen>
			            let __safeDI_exportService: LazilyInstantiated<ExportService>

			            init(exportService: LazilyInstantiated<ExportService>, screenBuilder: Instantiator<ExportScreen>) {
			                __safeDI_exportService = exportService
			                self.screenBuilder = screenBuilder
			            }
			        }
			    }

			    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
			    public init(exportService: ExportService, uploaderBuilder: @escaping (SafeDIScope_Uploader) -> any Uploader) {
			        self.init(__safeDI_exportService: exportService, __safeDI_uploaderBuilder: uploaderBuilder)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// From code you write, call the initializer above instead.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: @escaping (SafeDIScope_Uploader) -> any Uploader) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder(.uploader(SafeDIScope_Uploader.uploader_Values(exportService: exportService, screenBuilder: screenBuilder)))
			        self.init(screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_446917FA996AE016 {}
			}
			""",
		]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Root": """
			extension Root {
			    public convenience init() {
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_446917FA996AE016.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature(_ scope: ExportFeature.SafeDIScope_Uploader) -> any Uploader {
			                switch scope {
			                case .uploader:
			                    func __safeDI_uploader() -> DefaultUploader {
			                        func __safeDI_jobBuilder() -> UploadJob {
			                            UploadJob(exportService: exportService.instance)
			                        }
			                        let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                        return DefaultUploader(jobBuilder: jobBuilder)
			                    }
			                    let uploader: any Uploader = __safeDI_uploader()
			                    return uploader
			                }
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature)
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		]))
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsNoValueWhereSeamBuildsHolesStruct_whenImplementationsReadNothing(integration: MultiModuleIntegration) async throws {
		// `DefaultUploader` receives nothing, and `makeHandBuilt()`'s fill ignores its struct: `ExportFeature` hands the
		// struct the memo unread, so each service is created only where an `ExportScreen` reads it, as inline.
		let feature = Self.feature()
		let app = Self.app(declarations: [], handWrittenFill: "{ _ in DefaultUploader() }")
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app, featureConfiguration: plainDependencyTreeInitializersConfiguration), integration: integration, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Root": """
			extension Root {
			    public convenience init() {
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_446917FA996AE016.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature(_ scope: ExportFeature.SafeDIScope_Uploader) -> any Uploader {
			                switch scope {
			                case .uploader:
			                    let uploader: any Uploader = DefaultUploader()
			                    return uploader
			                }
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature)
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		]))
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	// MARK: Sendable functions

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	mutating func generate_readsAppsSendableMemoInsideFillsSendableStage_whenSeamBuildsHoleInsideSendableBuilder(integration: MultiModuleIntegration) async throws {
		// `Panel`, behind `ExportFeature`'s `SendableInstantiator`, builds the hole, so its builder is staged: the first stage
		// call hands the outer struct the memo, and `Root`'s fill reads `Root`'s `SendableLazilyInstantiated` inside its
		// `@Sendable` inner stage, so the service is created when an `UploadJob` reads it, as inline.
		let feature = Self.feature(exportServiceConformances: ", Sendable", seamDeclarations: Self.seamBuildingPanel, additionalTypes: [Self.panel])
		let app = Self.app(declarations: Self.uploaderBuildingJobs, rootDeclarations: ["@Instantiated let exportService: SendableLazilyInstantiated<ExportService>"], handWrittenFill: nil)
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: integration, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", integration: integration, imports: [], rootFiles: [
			"ExportFeature": """
			extension ExportFeature {
			    public enum SafeDIStagedScope_Uploader_panelBuilder_uploader {
			        public struct Stage1 {
			            public var exportService: ExportService { __safeDI_exportService.instance }
			            public let screenBuilder: Instantiator<ExportScreen>
			            let __safeDI_exportService: LazilyInstantiated<ExportService>

			            init(exportService: LazilyInstantiated<ExportService>, screenBuilder: Instantiator<ExportScreen>) {
			                __safeDI_exportService = exportService
			                self.screenBuilder = screenBuilder
			            }
			        }

			        public struct Stage2 {}
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder_panelBuilder_uploader: @escaping (SafeDIStagedScope_Uploader_panelBuilder_uploader.Stage1) -> @Sendable (SafeDIStagedScope_Uploader_panelBuilder_uploader.Stage2) -> any Uploader) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let __safeDI_uploaderBuilder_panelBuilder_uploader_Stage2 = __safeDI_uploaderBuilder_panelBuilder_uploader(SafeDIStagedScope_Uploader_panelBuilder_uploader.Stage1(exportService: exportService, screenBuilder: screenBuilder))
			        @Sendable func __safeDI_panelBuilder() -> Panel {
			            let uploader: any Uploader = __safeDI_uploaderBuilder_panelBuilder_uploader_Stage2(SafeDIStagedScope_Uploader_panelBuilder_uploader.Stage2())
			            return Panel(uploader: uploader)
			        }
			        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
			        self.init(screenBuilder: screenBuilder, panelBuilder: panelBuilder)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_29F6DE7C0A1F158C {}
			}
			""",
		]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Root": """
			extension Root {
			    public convenience init() {
			        @Sendable func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = SendableLazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_29F6DE7C0A1F158C.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_panelBuilder_uploader(_ scope: ExportFeature.SafeDIStagedScope_Uploader_panelBuilder_uploader.Stage1) -> @Sendable (ExportFeature.SafeDIStagedScope_Uploader_panelBuilder_uploader.Stage2) -> any Uploader {
			                @Sendable func __safeDI_uploaderBuilder_panelBuilder_uploader_Stage2(_ scope: ExportFeature.SafeDIStagedScope_Uploader_panelBuilder_uploader.Stage2) -> any Uploader {
			                    func __safeDI_uploader() -> DefaultUploader {
			                        func __safeDI_jobBuilder() -> UploadJob {
			                            UploadJob(exportService: exportService.instance)
			                        }
			                        let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                        return DefaultUploader(jobBuilder: jobBuilder)
			                    }
			                    let uploader: any Uploader = __safeDI_uploader()
			                    return uploader
			                }
			                return __safeDI_uploaderBuilder_panelBuilder_uploader_Stage2
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder_panelBuilder_uploader: __safeDI_uploaderBuilder_panelBuilder_uploader)
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		]))
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenFillsSendableStageReadsAppsNonSendableWrapper(integration: MultiModuleIntegration) async {
		// The staged hole of the cell above, with `Root` holding a plain `LazilyInstantiated`: the fill's inner stage would
		// capture it, as `ExportFeature`'s `SendableInstantiator` would inline.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "UploadJob.swift", inModule: "App", fixtures: fixtures, integration: integration)):9:5: error: @Received property `exportService: ExportService` cannot be received inside a `@Sendable` function in chain: Root -> ExportFeature -> DefaultUploader -> UploadJob. `ExportFeature`'s tree builds `uploader: any Uploader` on `Panel` inside a `@Sendable` function, so the function SafeDI generates to fill its builder is `@Sendable` too, and it cannot capture `exportService: LazilyInstantiated<ExportService>` on `Root`, because `LazilyInstantiated<ExportService>` is not `Sendable`. Declare `exportService` on `Root` as `SendableLazilyInstantiated<ExportService>` to fix. A `SendableLazilyInstantiated` requires its instance type, `ExportService`, to be `Sendable`.
			\(Self.path(of: "Root.swift", inModule: "App", fixtures: fixtures, integration: integration)):12:5: note: `exportService: LazilyInstantiated<ExportService>` is declared here
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: Self.feature(exportServiceConformances: ", Sendable", seamDeclarations: Self.seamBuildingPanel, additionalTypes: [Self.panel]),
					app: Self.app(declarations: Self.uploaderBuildingJobs, handWrittenFill: nil),
				),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	mutating func generate_readsAppsSendableMemoInsideImplementationsSendableBuilder_whenAppHoldsSendableLazilyInstantiated(integration: MultiModuleIntegration) async throws {
		// `DefaultUploader` builds `UploadJob` behind a `SendableInstantiator`, whose `@Sendable` builder function reads
		// `Root`'s `SendableLazilyInstantiated`, as inline: the service is created when an `UploadJob` is built.
		let feature = Self.feature(exportServiceConformances: ", Sendable")
		let app = Self.app(declarations: ["@Instantiated let jobBuilder: SendableInstantiator<UploadJob>"], rootDeclarations: ["@Instantiated let exportService: SendableLazilyInstantiated<ExportService>"], handWrittenFill: nil)
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: integration, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Root": """
			extension Root {
			    public convenience init() {
			        @Sendable func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = SendableLazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_446917FA996AE016.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature(_ scope: ExportFeature.SafeDIScope_Uploader) -> any Uploader {
			                switch scope {
			                case .uploader:
			                    func __safeDI_uploader() -> DefaultUploader {
			                        @Sendable func __safeDI_jobBuilder() -> UploadJob {
			                            UploadJob(exportService: exportService.instance)
			                        }
			                        let jobBuilder = SendableInstantiator<UploadJob>(__safeDI_jobBuilder)
			                        return DefaultUploader(jobBuilder: jobBuilder)
			                    }
			                    let uploader: any Uploader = __safeDI_uploader()
			                    return uploader
			                }
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature)
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		]))
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsInlinesError_whenImplementationsSendableBuilderReadsAppsNonSendableWrapper(integration: MultiModuleIntegration) async {
		// The cell above with `Root` holding a plain `LazilyInstantiated`: `jobBuilder`'s `@Sendable` builder function would
		// capture it, which SafeDI reports with the error it reports for the tree built inline.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "UploadJob.swift", inModule: "App", fixtures: fixtures, integration: integration)):9:5: error: @Received property `exportService: ExportService` cannot be received inside a `@Sendable` function in chain: Root -> ExportFeature -> DefaultUploader -> UploadJob. SafeDI builds `jobBuilder: SendableInstantiator<UploadJob>` on `DefaultUploader` in a `@Sendable` function, which cannot capture `exportService: LazilyInstantiated<ExportService>` on `Root`, because `LazilyInstantiated<ExportService>` is not `Sendable`. Declare `exportService` on `Root` as `SendableLazilyInstantiated<ExportService>` to fix. A `SendableLazilyInstantiated` requires its instance type, `ExportService`, to be `Sendable`.
			\(Self.path(of: "Root.swift", inModule: "App", fixtures: fixtures, integration: integration)):12:5: note: `exportService: LazilyInstantiated<ExportService>` is declared here
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: Self.feature(exportServiceConformances: ", Sendable"),
					app: Self.app(declarations: ["@Instantiated let jobBuilder: SendableInstantiator<UploadJob>"], handWrittenFill: nil),
				),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Fields

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsEachDeferredValuesMemoBesideValueField_whenStructCarriesTwoDeferredValuesAndOneByValue(integration: MultiModuleIntegration) async throws {
		// `ExportFeature` defers `exportService` and `logger`, and instantiates `analytics`: the struct holds two memos
		// and `analytics` by value, and `Root`'s fill binds only `analytics` from it.
		let feature = Self.feature(
			screenDeclarations: ["@Received let exportService: ExportService", "@Received let logger: Logger"],
			seamDeclarations: ["@Instantiated let analytics: Analytics"] + Self.seamDeclarations,
			additionalTypes: [seamFixtureType(named: "Logger", isFinalClass: true, declarations: []), seamFixtureType(named: "Analytics", isFinalClass: true, declarations: [])],
		)
		let app = Self.app(
			declarations: Self.uploaderBuildingJobs,
			jobDeclarations: ["@Received let exportService: ExportService", "@Received let logger: Logger", "@Received let analytics: Analytics"],
			rootDeclarations: ["@Instantiated let exportService: LazilyInstantiated<ExportService>", "@Instantiated let logger: LazilyInstantiated<Logger>"],
			handWrittenFill: nil,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: integration, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", integration: integration, imports: [], rootFiles: [
			"ExportFeature": """
			extension ExportFeature {
			    @frozen public enum SafeDIScope_Uploader {
			        case uploader(uploader_Values)

			        public struct uploader_Values {
			            public var exportService: ExportService { __safeDI_exportService.instance }
			            public var logger: Logger { __safeDI_logger.instance }
			            public let analytics: Analytics
			            public let screenBuilder: Instantiator<ExportScreen>
			            let __safeDI_exportService: LazilyInstantiated<ExportService>
			            let __safeDI_logger: LazilyInstantiated<Logger>

			            init(exportService: LazilyInstantiated<ExportService>, logger: LazilyInstantiated<Logger>, analytics: Analytics, screenBuilder: Instantiator<ExportScreen>) {
			                __safeDI_exportService = exportService
			                __safeDI_logger = logger
			                self.analytics = analytics
			                self.screenBuilder = screenBuilder
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_logger: @autoclosure @escaping () -> Logger, __safeDI_uploaderBuilder: @escaping (SafeDIScope_Uploader) -> any Uploader) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
			        let analytics = Analytics()
			        func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance, logger: logger.instance)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder(.uploader(SafeDIScope_Uploader.uploader_Values(exportService: exportService, logger: logger, analytics: analytics, screenBuilder: screenBuilder)))
			        self.init(analytics: analytics, screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_5648D1BBCDF4F203 {}
			}
			""",
		]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Root": """
			extension Root {
			    public convenience init() {
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_logger() -> Logger {
			            Logger()
			        }
			        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_5648D1BBCDF4F203.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature(_ scope: ExportFeature.SafeDIScope_Uploader) -> any Uploader {
			                switch scope {
			                case let .uploader(scope):
			                    let analytics = scope.analytics
			                    func __safeDI_uploader() -> DefaultUploader {
			                        func __safeDI_jobBuilder() -> UploadJob {
			                            UploadJob(exportService: exportService.instance, logger: logger.instance, analytics: analytics)
			                        }
			                        let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                        return DefaultUploader(jobBuilder: jobBuilder)
			                    }
			                    let uploader: any Uploader = __safeDI_uploader()
			                    return uploader
			                }
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_logger: logger.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature)
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, logger: logger, exportFeature: exportFeature)
			    }
			}
			""",
		]))
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsOptionalMemo_whenSeamTakesPassThroughReceivedOnlyIfAvailable(integration: MultiModuleIntegration) async throws {
		// Every receiver takes `logger` only if available: the struct's optional field reads a `LazilyInstantiated<Logger?>`,
		// and each fill reads its root's declaration – `Root`'s memo, and `nil` in `OtherRoot`, which holds none.
		let feature = Self.feature(
			screenDeclarations: ["@Received let exportService: ExportService", "@Received(onlyIfAvailable: true) let logger: Logger?"],
			additionalTypes: [seamFixtureType(named: "Logger", isFinalClass: true, declarations: [])],
		)
		let app = Self.app(
			declarations: Self.uploaderBuildingJobs,
			jobDeclarations: ["@Received let exportService: ExportService", "@Received(onlyIfAvailable: true) let logger: Logger?"],
			rootDeclarations: ["@Instantiated let exportService: LazilyInstantiated<ExportService>", "@Instantiated let logger: LazilyInstantiated<Logger>"],
			handWrittenFill: nil,
		) + [Self.stamped(seamFixtureType(named: "OtherRoot", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let exportService: LazilyInstantiated<ExportService>", "@Instantiated let exportFeature: ExportFeature"]))]
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: integration, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", integration: integration, imports: [], rootFiles: [
			"ExportFeature": """
			extension ExportFeature {
			    @frozen public enum SafeDIScope_Uploader {
			        case uploader(uploader_Values)

			        public struct uploader_Values {
			            public var exportService: ExportService { __safeDI_exportService.instance }
			            public var logger: Logger? { __safeDI_logger.instance }
			            public let screenBuilder: Instantiator<ExportScreen>
			            let __safeDI_exportService: LazilyInstantiated<ExportService>
			            let __safeDI_logger: LazilyInstantiated<Logger?>

			            init(exportService: LazilyInstantiated<ExportService>, logger: LazilyInstantiated<Logger?>, screenBuilder: Instantiator<ExportScreen>) {
			                __safeDI_exportService = exportService
			                __safeDI_logger = logger
			                self.screenBuilder = screenBuilder
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_logger: @autoclosure @escaping () -> Logger?, __safeDI_uploaderBuilder: @escaping (SafeDIScope_Uploader) -> any Uploader) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        let logger = LazilyInstantiated<Logger?>(__safeDI_logger)
			        func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance, logger: logger.instance)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder(.uploader(SafeDIScope_Uploader.uploader_Values(exportService: exportService, logger: logger, screenBuilder: screenBuilder)))
			        self.init(screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_535C4E406B5C5750 {}
			}
			""",
		]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"OtherRoot": """
			extension OtherRoot {
			    public convenience init() {
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_535C4E406B5C5750.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature(_ scope: ExportFeature.SafeDIScope_Uploader) -> any Uploader {
			                switch scope {
			                case .uploader:
			                    func __safeDI_uploader() -> DefaultUploader {
			                        func __safeDI_jobBuilder() -> UploadJob {
			                            UploadJob(exportService: exportService.instance, logger: nil)
			                        }
			                        let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                        return DefaultUploader(jobBuilder: jobBuilder)
			                    }
			                    let uploader: any Uploader = __safeDI_uploader()
			                    return uploader
			                }
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_logger: nil, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature)
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
			"Root": """
			extension Root {
			    public convenience init() {
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_logger() -> Logger {
			            Logger()
			        }
			        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_535C4E406B5C5750.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature(_ scope: ExportFeature.SafeDIScope_Uploader) -> any Uploader {
			                switch scope {
			                case .uploader:
			                    func __safeDI_uploader() -> DefaultUploader {
			                        func __safeDI_jobBuilder() -> UploadJob {
			                            UploadJob(exportService: exportService.instance, logger: logger.instance)
			                        }
			                        let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                        return DefaultUploader(jobBuilder: jobBuilder)
			                    }
			                    let uploader: any Uploader = __safeDI_uploader()
			                    return uploader
			                }
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_logger: logger.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature)
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, logger: logger, exportFeature: exportFeature)
			    }
			}
			""",
		]))
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app, probes: ["Root()", "OtherRoot()"])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsOptionalMemo_whenSeamTakesImplicitlyUnwrappedPassThrough(integration: MultiModuleIntegration) async throws {
		// Every receiver takes `logger: Logger!`, which no generic argument can spell: the struct's field keeps the
		// implicitly unwrapped type and reads a `LazilyInstantiated<Logger?>`, as the seam's tree holds the value.
		let feature = Self.feature(
			screenDeclarations: ["@Received let exportService: ExportService", "@Received let logger: Logger!"],
			additionalTypes: [seamFixtureType(named: "Logger", isFinalClass: true, declarations: [])],
		)
		let app = Self.app(
			declarations: Self.uploaderBuildingJobs,
			jobDeclarations: ["@Received let exportService: ExportService", "@Received let logger: Logger!"],
			rootDeclarations: [
				"@Instantiated let exportService: LazilyInstantiated<ExportService>",
				"@Instantiated let currentLogger: Logger",
				#"@Received(fulfilledByDependencyNamed: "currentLogger", ofType: Logger.self) let logger: Logger!"#,
			],
			handWrittenFill: nil,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: integration, filesToDelete: &filesToDelete)
		let rootPath = try #require(output.modules["App"]).fixtures.compilerPath(of: "Root.swift")
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", integration: integration, imports: [], rootFiles: [
			"ExportFeature": """
			extension ExportFeature {
			    @frozen public enum SafeDIScope_Uploader {
			        case uploader(uploader_Values)

			        public struct uploader_Values {
			            public var exportService: ExportService { __safeDI_exportService.instance }
			            public var logger: Logger! { __safeDI_logger.instance }
			            public let screenBuilder: Instantiator<ExportScreen>
			            let __safeDI_exportService: LazilyInstantiated<ExportService>
			            let __safeDI_logger: LazilyInstantiated<Logger?>

			            init(exportService: LazilyInstantiated<ExportService>, logger: LazilyInstantiated<Logger?>, screenBuilder: Instantiator<ExportScreen>) {
			                __safeDI_exportService = exportService
			                __safeDI_logger = logger
			                self.screenBuilder = screenBuilder
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_logger: @autoclosure @escaping () -> Logger?, __safeDI_uploaderBuilder: @escaping (SafeDIScope_Uploader) -> any Uploader) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        let logger = LazilyInstantiated<Logger?>(__safeDI_logger)
			        func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance, logger: logger.instance)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder(.uploader(SafeDIScope_Uploader.uploader_Values(exportService: exportService, logger: logger, screenBuilder: screenBuilder)))
			        self.init(screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_5958B573451EB652 {}
			}
			""",
		]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Root": """
			extension Root {
			    public convenience init() {
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        let currentLogger = Logger()
			        #sourceLocation(file: "\(rootPath)", line: 16)
			        let logger: Logger! = currentLogger
			        #sourceLocation()
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_5958B573451EB652.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature(_ scope: ExportFeature.SafeDIScope_Uploader) -> any Uploader {
			                switch scope {
			                case .uploader:
			                    func __safeDI_uploader() -> DefaultUploader {
			                        func __safeDI_jobBuilder() -> UploadJob {
			                            UploadJob(exportService: exportService.instance, logger: logger)
			                        }
			                        let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                        return DefaultUploader(jobBuilder: jobBuilder)
			                    }
			                    let uploader: any Uploader = __safeDI_uploader()
			                    return uploader
			                }
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_logger: logger, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature)
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, currentLogger: currentLogger, logger: logger, exportFeature: exportFeature)
			    }
			}
			""",
		]))
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsInstantiatorPassThroughByValue_whenSeamTakesItAsItself(integration: MultiModuleIntegration) async throws {
		// `ExportFeature` takes `reportBuilder` by value, as the tree receives it as itself: its field stays a stored
		// property, which the fill binds from the struct, beside the deferred `exportService`'s memo.
		let feature = Self.feature(
			screenDeclarations: ["@Received let exportService: ExportService", "@Received let reportBuilder: Instantiator<Report>"],
			additionalTypes: [seamFixtureType(named: "Report", isFinalClass: true, declarations: [])],
		)
		let app = Self.app(
			declarations: Self.uploaderBuildingJobs,
			jobDeclarations: ["@Received let exportService: ExportService", "@Received let reportBuilder: Instantiator<Report>"],
			rootDeclarations: ["@Instantiated let exportService: LazilyInstantiated<ExportService>", "@Instantiated let reportBuilder: Instantiator<Report>"],
			handWrittenFill: nil,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: integration, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", integration: integration, imports: [], rootFiles: [
			"ExportFeature": """
			extension ExportFeature {
			    @frozen public enum SafeDIScope_Uploader {
			        case uploader(uploader_Values)

			        public struct uploader_Values {
			            public var exportService: ExportService { __safeDI_exportService.instance }
			            public let reportBuilder: Instantiator<Report>
			            public let screenBuilder: Instantiator<ExportScreen>
			            let __safeDI_exportService: LazilyInstantiated<ExportService>

			            init(exportService: LazilyInstantiated<ExportService>, reportBuilder: Instantiator<Report>, screenBuilder: Instantiator<ExportScreen>) {
			                __safeDI_exportService = exportService
			                self.reportBuilder = reportBuilder
			                self.screenBuilder = screenBuilder
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_reportBuilder reportBuilder: Instantiator<Report>, __safeDI_uploaderBuilder: @escaping (SafeDIScope_Uploader) -> any Uploader) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance, reportBuilder: reportBuilder)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder(.uploader(SafeDIScope_Uploader.uploader_Values(exportService: exportService, reportBuilder: reportBuilder, screenBuilder: screenBuilder)))
			        self.init(screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_03939A0052FE861E {}
			}
			""",
		]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Root": """
			extension Root {
			    public convenience init() {
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_reportBuilder() -> Report {
			            Report()
			        }
			        let reportBuilder = Instantiator<Report>(__safeDI_reportBuilder)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_03939A0052FE861E.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature(_ scope: ExportFeature.SafeDIScope_Uploader) -> any Uploader {
			                switch scope {
			                case let .uploader(scope):
			                    let reportBuilder = scope.reportBuilder
			                    func __safeDI_uploader() -> DefaultUploader {
			                        func __safeDI_jobBuilder() -> UploadJob {
			                            UploadJob(exportService: exportService.instance, reportBuilder: reportBuilder)
			                        }
			                        let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                        return DefaultUploader(jobBuilder: jobBuilder)
			                    }
			                    let uploader: any Uploader = __safeDI_uploader()
			                    return uploader
			                }
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_reportBuilder: reportBuilder, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature)
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, reportBuilder: reportBuilder, exportFeature: exportFeature)
			    }
			}
			""",
		]))
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsImplementationCallersWrapper_whenImplementationReceivesDeferredLabelAsLazilyInstantiated(integration: MultiModuleIntegration) async throws {
		// `UploadJob` receives `exportService` as the `LazilyInstantiated` `Root` holds, while `ExportFeature` takes the
		// value deferred: `Root`'s fill hands `UploadJob` `Root`'s own wrapper, as inline, which the struct's by-value
		// field could not, so the service is created when an `UploadJob` reads it.
		let feature = Self.feature()
		let app = Self.app(
			declarations: Self.uploaderBuildingJobs,
			jobDeclarations: ["@Received let exportService: LazilyInstantiated<ExportService>"],
			handWrittenFill: nil,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: integration, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", integration: integration, imports: [], rootFiles: [
			"ExportFeature": """
			extension ExportFeature {
			    @frozen public enum SafeDIScope_Uploader {
			        case uploader(uploader_Values)

			        public struct uploader_Values {
			            public var exportService: ExportService { __safeDI_exportService.instance }
			            public let screenBuilder: Instantiator<ExportScreen>
			            let __safeDI_exportService: LazilyInstantiated<ExportService>

			            init(exportService: LazilyInstantiated<ExportService>, screenBuilder: Instantiator<ExportScreen>) {
			                __safeDI_exportService = exportService
			                self.screenBuilder = screenBuilder
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: @escaping (SafeDIScope_Uploader) -> any Uploader) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder(.uploader(SafeDIScope_Uploader.uploader_Values(exportService: exportService, screenBuilder: screenBuilder)))
			        self.init(screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_446917FA996AE016 {}
			}
			""",
		]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Root": """
			extension Root {
			    public convenience init() {
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_446917FA996AE016.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature(_ scope: ExportFeature.SafeDIScope_Uploader) -> any Uploader {
			                switch scope {
			                case .uploader:
			                    func __safeDI_uploader() -> DefaultUploader {
			                        func __safeDI_jobBuilder() -> UploadJob {
			                            UploadJob(exportService: exportService)
			                        }
			                        let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                        return DefaultUploader(jobBuilder: jobBuilder)
			                    }
			                    let uploader: any Uploader = __safeDI_uploader()
			                    return uploader
			                }
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature)
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		]))
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsOwnAliasByValue_whenSeamRetypesDeferredLabelKeepingIt(integration: MultiModuleIntegration) async throws {
		// `ExportFeature`'s own alias keeps `exportService`'s label and reads the autoclosure where inline reads `Root`'s
		// memo, at the seam's construction: the struct carries the alias by value, and the fill binds it from there.
		let feature = Self.feature(
			exportServiceConformances: ", Exporting",
			screenDeclarations: ["@Received let exportService: any Exporting"],
			seamDeclarations: [#"@Received(fulfilledByDependencyNamed: "exportService", ofType: ExportService.self) let exportService: any Exporting"#] + Self.seamDeclarations,
			additionalTypes: ["public protocol Exporting {}"],
		)
		let app = Self.app(declarations: Self.uploaderBuildingJobs, jobDeclarations: ["@Received let exportService: any Exporting"], handWrittenFill: nil)
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: integration, filesToDelete: &filesToDelete)
		let seamPath = try #require(output.modules["Feature"]).fixtures.compilerPath(of: "ExportFeature.swift")
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", integration: integration, imports: [], rootFiles: [
			"ExportFeature": """
			extension ExportFeature {
			    @frozen public enum SafeDIScope_Uploader {
			        case uploader(uploader_Values)

			        public struct uploader_Values {
			            public let exportService: any Exporting
			            public let screenBuilder: Instantiator<ExportScreen>
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_exportService __safeDI_exportService_: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: @escaping (SafeDIScope_Uploader) -> any Uploader) {
			        #sourceLocation(file: "\(seamPath)", line: 9)
			        let exportService: any Exporting = __safeDI_exportService_()
			        #sourceLocation()
			        func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder(.uploader(SafeDIScope_Uploader.uploader_Values(exportService: exportService, screenBuilder: screenBuilder)))
			        self.init(exportService: exportService, screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_13794DFBF69DD645 {}
			}
			""",
		]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Root": """
			extension Root {
			    public convenience init() {
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_13794DFBF69DD645.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature(_ scope: ExportFeature.SafeDIScope_Uploader) -> any Uploader {
			                switch scope {
			                case let .uploader(scope):
			                    let exportService = scope.exportService
			                    func __safeDI_uploader() -> DefaultUploader {
			                        func __safeDI_jobBuilder() -> UploadJob {
			                            UploadJob(exportService: exportService)
			                        }
			                        let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                        return DefaultUploader(jobBuilder: jobBuilder)
			                    }
			                    let uploader: any Uploader = __safeDI_uploader()
			                    return uploader
			                }
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature)
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		]))
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	// MARK: Nested seams, public mocks and re-entry

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesMemoThroughOuterSeam_whenOuterSeamPassesHoleUp(integration: MultiModuleIntegration) async throws {
		// `Shell` defers `exportService` into `ExportFeature`'s autoclosure and passes the hole up; `ExportFeature` hands
		// the struct its own memo, and `Root`'s fill reads `Root`'s.
		let feature = Self.feature(additionalTypes: [
			seamFixtureType(named: "Header", declarations: ["@Received let exportService: ExportService"]),
			seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let headerBuilder: Instantiator<Header>", "@Instantiated let exportFeature: ExportFeature"]),
		])
		let app = Self.app(declarations: Self.uploaderBuildingJobs, rootChild: "@Instantiated let shell: Shell", handWrittenFill: nil)
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: integration, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", integration: integration, imports: [], rootFiles: [
			"ExportFeature": """
			extension ExportFeature {
			    @frozen public enum SafeDIScope_Uploader {
			        case uploader(uploader_Values)

			        public struct uploader_Values {
			            public var exportService: ExportService { __safeDI_exportService.instance }
			            public let screenBuilder: Instantiator<ExportScreen>
			            let __safeDI_exportService: LazilyInstantiated<ExportService>

			            init(exportService: LazilyInstantiated<ExportService>, screenBuilder: Instantiator<ExportScreen>) {
			                __safeDI_exportService = exportService
			                self.screenBuilder = screenBuilder
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: @escaping (SafeDIScope_Uploader) -> any Uploader) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder(.uploader(SafeDIScope_Uploader.uploader_Values(exportService: exportService, screenBuilder: screenBuilder)))
			        self.init(screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_446917FA996AE016 {}
			}
			""",
			"Shell": """
			extension Shell {
			    @frozen public enum SafeDIScope_Uploader {
			        case exportFeature(ExportFeature.SafeDIScope_Uploader)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: @escaping (SafeDIScope_Uploader) -> any Uploader) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_headerBuilder() -> Header {
			            Header(exportService: exportService.instance)
			        }
			        let headerBuilder = Instantiator<Header>(__safeDI_headerBuilder)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_446917FA996AE016.self
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: { __safeDI_uploaderBuilder(.exportFeature($0)) })
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(headerBuilder: headerBuilder, exportFeature: exportFeature)
			    }
			}

			extension Shell {
			    public enum __safeDI_Shell_DF7335D3AA0E9B15 {}
			}
			""",
		]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Root": """
			extension Root {
			    public convenience init() {
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_shell() -> Shell {
			            _ = Shell.__safeDI_Shell_DF7335D3AA0E9B15.self\(Self.pluginComment(integration, seam: "Shell"))
			            func __safeDI_uploaderBuilder_Shell(_ scope: Shell.SafeDIScope_Uploader) -> any Uploader {
			                switch scope {
			                case let .exportFeature(scope): return __safeDI_uploaderBuilder_ExportFeature(scope)
			                }
			            }
			            func __safeDI_uploaderBuilder_ExportFeature(_ scope: ExportFeature.SafeDIScope_Uploader) -> any Uploader {
			                switch scope {
			                case .uploader:
			                    func __safeDI_uploader() -> DefaultUploader {
			                        func __safeDI_jobBuilder() -> UploadJob {
			                            UploadJob(exportService: exportService.instance)
			                        }
			                        let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                        return DefaultUploader(jobBuilder: jobBuilder)
			                    }
			                    let uploader: any Uploader = __safeDI_uploader()
			                    return uploader
			                }
			            }
			            return Shell(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_Shell)
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(exportService: exportService, shell: shell)
			    }
			}
			""",
		]))
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsPublicMocksValueByValue_whenSeamWithDeferredFieldHasPublicMock(integration: MultiModuleIntegration) async throws {
		// A public mock builds its tree beside the mocked type and takes no autoclosure: its hole's struct holds the
		// value the mock is passed, while the seam's struct holds the seam's memo.
		let feature = Self.feature().map { $0.replacingOccurrences(of: "@Instantiable(generateDependencyTree: true)", with: "@Instantiable(generateDependencyTree: true, generateMock: .public)") }
		let app = Self.app(declarations: Self.uploaderBuildingJobs, handWrittenFill: nil)
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: integration, filesToDelete: &filesToDelete)
		let seam = """
		extension ExportFeature {
		    @frozen public enum SafeDIScope_Uploader {
		        case uploader(uploader_Values)

		        public struct uploader_Values {
		            public var exportService: ExportService { __safeDI_exportService.instance }
		            public let screenBuilder: Instantiator<ExportScreen>
		            let __safeDI_exportService: LazilyInstantiated<ExportService>

		            init(exportService: LazilyInstantiated<ExportService>, screenBuilder: Instantiator<ExportScreen>) {
		                __safeDI_exportService = exportService
		                self.screenBuilder = screenBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: @escaping (SafeDIScope_Uploader) -> any Uploader) {
		        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
		        func __safeDI_screenBuilder() -> ExportScreen {
		            ExportScreen(exportService: exportService.instance)
		        }
		        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
		        let uploader: any Uploader = __safeDI_uploaderBuilder(.uploader(SafeDIScope_Uploader.uploader_Values(exportService: exportService, screenBuilder: screenBuilder)))
		        self.init(screenBuilder: screenBuilder, uploader: uploader)
		    }
		}

		extension ExportFeature {
		    public enum __safeDI_ExportFeature_446917FA996AE016 {}
		}
		"""
		let mock = """
		#if DEBUG
		extension ExportFeature {
		    @frozen public enum SafeDIMockScope_Uploader {
		        case uploader(uploader_Values)

		        public struct uploader_Values {
		            public let exportService: ExportService
		            public let screenBuilder: Instantiator<ExportScreen>
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            exportService: (() -> ExportService)? = nil,
		            screenBuilder: ((ExportService) -> ExportScreen)? = nil
		        ) {
		            self.exportService = exportService
		            self.screenBuilder = screenBuilder
		        }

		        public let exportService: (() -> ExportService)?
		        public let screenBuilder: ((ExportService) -> ExportScreen)?
		    }

		    public static func mock(
		        uploaderBuilder: @escaping (ExportFeature.SafeDIMockScope_Uploader) -> any Uploader,
		        exportService: ExportService? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> ExportFeature {
		        let __safeDI_uploaderBuilder = uploaderBuilder
		        let exportService = if let exportService { exportService } else if let safeDIBuilder = safeDIOverrides.exportService { safeDIBuilder() } else { ExportService() }
		        func __safeDI_screenBuilder() -> ExportScreen {
		            if let safeDIBuilder = safeDIOverrides.screenBuilder { safeDIBuilder(exportService) } else { ExportScreen(exportService: exportService) }
		        }
		        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
		        let uploader: any Uploader = __safeDI_uploaderBuilder(.uploader(SafeDIMockScope_Uploader.uploader_Values(exportService: exportService, screenBuilder: screenBuilder)))
		        return ExportFeature(screenBuilder: screenBuilder, uploader: uploader)
		    }
		}

		extension ExportFeature {
		    public enum __safeDI_ExportFeature_mock_E057F9BDDBAF41A6 {}
		}
		#endif
		"""
		let expectedFeatureFiles = switch integration {
		case .moduleInfo:
			["Feature.swift": generatedFileHeader + seam + "\n\n" + mock]
		case .swiftPackagePlugin:
			[
				"ExportFeature+SafeDI.swift": generatedFileHeader + seam,
				"ExportFeature+SafeDIMock.swift": generatedFileHeader + mock,
				"SafeDIMockConfiguration.swift": generatedFileHeader,
			]
		}
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, expectedFeatureFiles)
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsStructsField_whenCallInsideFillReentersSeamBeneathAnotherDeclarationOfDeferredLabel(integration: MultiModuleIntegration) async throws {
		// `DefaultUploader`'s `Reentry` instantiates `exportService` and `ExportFeature` again, which it hands its own
		// service: the fill, one function, would read `Root`'s for both calls, so it reads the struct's field, and the
		// inner `UploadJob` gets `Reentry`'s service, as inline.
		let feature = Self.feature()
		let app = Self.app(
			declarations: Self.uploaderBuildingJobs + ["@Instantiated let reentry: Reentry"],
			rootDeclarations: ["@Instantiated let exportService: ExportService"],
			handWrittenFill: nil,
		) + [seamFixtureType(named: "Reentry", isFinalClass: true, declarations: ["@Instantiated let exportService: ExportService", "@Instantiated let featureBuilder: Instantiator<ExportFeature>"])]
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: integration, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Root": """
			extension Root {
			    public convenience init() {
			        let exportService = ExportService()
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_446917FA996AE016.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature(_ scope: ExportFeature.SafeDIScope_Uploader) -> any Uploader {
			                switch scope {
			                case let .uploader(scope):
			                    let exportService = scope.exportService
			                    func __safeDI_uploader() -> DefaultUploader {
			                        func __safeDI_jobBuilder() -> UploadJob {
			                            UploadJob(exportService: exportService)
			                        }
			                        let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                        func __safeDI_reentry() -> Reentry {
			                            let exportService = ExportService()
			                            func __safeDI_featureBuilder() -> ExportFeature {
			                                _ = ExportFeature.__safeDI_ExportFeature_446917FA996AE016.self\(Self.pluginComment(integration))
			                                return ExportFeature(__safeDI_exportService: exportService, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature)
			                            }
			                            let featureBuilder = Instantiator<ExportFeature>(__safeDI_featureBuilder)
			                            return Reentry(exportService: exportService, featureBuilder: featureBuilder)
			                        }
			                        let reentry: Reentry = __safeDI_reentry()
			                        return DefaultUploader(jobBuilder: jobBuilder, reentry: reentry)
			                    }
			                    let uploader: any Uploader = __safeDI_uploader()
			                    return uploader
			                }
			            }
			            return ExportFeature(__safeDI_exportService: exportService, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature)
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		]))
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	// MARK: Fixtures

	/// `Feature`: `ExportService`, `Uploader`, a protocol only `App` implements, `ExportScreen`, which receives
	/// `exportService`, and the seam `ExportFeature`, which instantiates `screenBuilder` and `uploader: any Uploader`, a
	/// hole, beside `seamDeclarations`.
	private static func feature(
		exportServiceConformances: String = "",
		screenDeclarations: [String] = ["@Received let exportService: ExportService"],
		seamDeclarations: [String] = seamDeclarations,
		additionalTypes: [String] = [],
	) -> [String] {
		[
			"public protocol Uploader {}\n\n" + DifferentialValueCreationStamp.counterDeclaration(named: "Stamp"),
			stamped(seamFixtureType(named: "ExportService", isFinalClass: true, declarations: [], conformances: exportServiceConformances)),
			seamFixtureType(named: "ExportScreen", declarations: screenDeclarations),
			seamFixtureType(named: "ExportFeature", isSeam: true, declarations: seamDeclarations),
		] + additionalTypes
	}

	/// `ExportFeature`'s declarations: `screenBuilder`, and `uploader: any Uploader`, the hole.
	private static let seamDeclarations = ["@Instantiated let screenBuilder: Instantiator<ExportScreen>", "@Instantiated let uploader: any Uploader"]

	/// `ExportFeature`'s declarations when it builds the hole in `Panel`, behind a `SendableInstantiator`: a staged hole.
	private static let seamBuildingPanel = ["@Instantiated let screenBuilder: Instantiator<ExportScreen>", "@Instantiated let panelBuilder: SendableInstantiator<Panel>"]

	/// `Panel`, which instantiates `uploader: any Uploader`.
	private static let panel = seamFixtureType(named: "Panel", declarations: ["@Instantiated let uploader: any Uploader"])

	/// `DefaultUploader` instantiating `jobBuilder`, whose `UploadJob` receives `exportService`.
	private static let uploaderBuildingJobs = ["@Instantiated let jobBuilder: Instantiator<UploadJob>"]

	/// A fill that reads the struct's `exportService` where its `jobBuilder` builds an `UploadJob`.
	private static let handWrittenFillReadingField = "{ scope in switch scope { case let .uploader(values): DefaultUploader(jobBuilder: Instantiator { UploadJob(exportService: values.exportService) }) } }"

	/// `App`: `DefaultUploader`, with `declarations`, `UploadJob`, which receives `jobDeclarations`, `Root`, which holds
	/// `rootDeclarations` and `rootChild`, and `makeHandBuilt()`, which calls `ExportFeature` with `handWrittenFill`
	/// and a `LazilyInstantiated` service it keeps beside the seam.
	private static func app(
		declarations: [String],
		jobDeclarations: [String] = ["@Received let exportService: ExportService"],
		rootDeclarations: [String] = ["@Instantiated let exportService: LazilyInstantiated<ExportService>"],
		rootChild: String = "@Instantiated let exportFeature: ExportFeature",
		handWrittenFill: String?,
		handWrittenArguments: String = "exportService: exportService.instance",
	) -> [String] {
		[
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUploader", fulfilling: "Uploader", declarations: declarations),
			seamFixtureType(named: "UploadJob", declarations: jobDeclarations),
			stamped(seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: rootDeclarations + [rootChild])),
		] + (handWrittenFill.map { [handBuilt(arguments: handWrittenArguments, fill: $0)] } ?? [])
	}

	/// `HandBuilt`, which keeps a `LazilyInstantiated` service beside the `ExportFeature` a hand-written call builds
	/// with it, passing `arguments` and, when `fill` is given, `fill` as the builder.
	private static func handBuilt(arguments: String, fill: String?) -> String {
		let builder = fill.map { ", uploaderBuilder: \($0)" } ?? ""
		return """
		public final class HandBuilt {
		    \(DifferentialValueCreationStamp.property(counterNamed: "Stamp"))

		    public init(exportService: LazilyInstantiated<ExportService>, exportFeature: ExportFeature) {
		        self.exportService = exportService
		        self.exportFeature = exportFeature
		    }

		    public let exportService: LazilyInstantiated<ExportService>
		    public let exportFeature: ExportFeature
		}

		public func makeHandBuilt() -> HandBuilt {
		    let exportService = LazilyInstantiated<ExportService> { ExportService() }
		    return HandBuilt(exportService: exportService, exportFeature: ExportFeature(\(arguments)\(builder)))
		}
		"""
	}

	/// `classSource`, a final class, storing a creation stamp from `Feature`'s `Stamp`, so the comparator marks an
	/// instance of it built before the probe's value (see `DifferentialValueCreationStamp`).
	private static func stamped(_ classSource: String) -> String {
		classSource.replacingOccurrences(of: "{\n    public init(", with: "{\n    \(DifferentialValueCreationStamp.property(counterNamed: "Stamp"))\n\n    public init(")
	}

	/// The files `integration` generates for `module` (see `SafeDIToolSeamBuilderParameterTests.generatedFiles`).
	private static func generatedFiles(module: String, integration: MultiModuleIntegration, imports: [String], rootFiles: [String: String]) -> [String: String] {
		SafeDIToolSeamBuilderParameterTests.generatedFiles(module: module, integration: integration, imports: imports, rootFiles: rootFiles)
	}

	/// The path of `fileName` in `moduleName` as a diagnostic reports it under `integration`: the plugin reports paths as
	/// the parse normalized them.
	private static func path(of fileName: String, inModule moduleName: String, fixtures: [String: FixturePaths], integration: MultiModuleIntegration) -> String {
		switch integration {
		case .moduleInfo:
			fixtures[moduleName]![fileName]
		case .swiftPackagePlugin:
			NormalizedFilePath(fixtures[moduleName]!.compilerPath(of: fileName)).path
		}
	}

	/// The comment a call to `seam`, a seam of `Feature`, carries under `integration`.
	private static func pluginComment(_ integration: MultiModuleIntegration, seam: String = "ExportFeature") -> String {
		SafeDIToolSeamBuilderParameterTests.pluginComment(integration, seam: seam)
	}

	// MARK: Assertions

	/// Expects the values `output`, the run of `feature` and `app`, builds for `probes` – and for `makeHandBuilt()`, when
	/// `app` declares it – to equal those the visible build builds: the same graph with `App`'s types but its roots and
	/// `HandBuilt` in `Feature`, where no hole is left, and `makeHandBuilt()` calling the seam without a builder.
	private mutating func expectValuesEqualVisibleBuild(
		_ output: MultiModuleTestOutput,
		feature: [String],
		app: [String],
		probes: [String] = ["Root()"],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		guard compileVerificationIsEnabled else { return }
		let hasHandBuilt = app.contains { $0.contains("public func makeHandBuilt()") }
		// A hand-built call needs the plain initializer, in the seam build and in the visible one.
		let featureConfiguration = hasHandBuilt ? plainDependencyTreeInitializersConfiguration : [:]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app, featureConfiguration: featureConfiguration)
		let movedTypes = app.filter { !$0.contains("(isRoot: true)") && !$0.contains("public func makeHandBuilt()") }
		let staying = app.filter { !movedTypes.contains($0) }.map { file in
			// The visible build's seam takes no builder.
			file.replacingOccurrences(of: #", uploaderBuilder: \{.*\}\)\)"#, with: "))", options: .regularExpression)
		}
		let visibleModules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature + movedTypes, app: staying, featureConfiguration: featureConfiguration)
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visibleModules),
			probes: (probes + (hasHandBuilt ? ["makeHandBuilt()"] : [])).map(DifferentialValueProbe.init),
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// Expects `generatedFiles` to equal `expected`, recording the files generated when they do not, so a failure shows
	/// the output in full.
	private func expectGeneratedFiles(_ generatedFiles: [String: String]?, _ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
