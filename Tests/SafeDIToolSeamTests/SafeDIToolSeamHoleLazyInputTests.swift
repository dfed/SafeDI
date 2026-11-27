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
/// struct the `LazilyInstantiated` it holds the value in, behind a field that reads its instance, and a hand-written
/// implementation, which takes nothing, reads the calling code's own value, as the implementation the app generates
/// reads the app's own declaration of the label, as inline, so the value is created when the implementation uses it. A
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
	mutating func generate_handsHolesStructSeamsMemo_whenGeneratedImplementationReadsDeferredValue(integration: MultiModuleIntegration) async throws {
		// `ExportFeature` defers `exportService` and hands the hole's struct its memo, whose field reads the instance.
		// `Root`'s fill reads `Root`'s own `exportService` inside `jobBuilder`, as inline, and `makeHandBuilt()`'s
		// hand-written fill, which takes nothing, reads the caller's own memo there: each service is created when its
		// `UploadJob` is built.
		let feature = Self.feature()
		let app = Self.app(declarations: Self.uploaderBuildingJobs, handWrittenFill: Self.handWrittenFillReadingCallersMemo)
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app, featureConfiguration: plainDependencyTreeInitializersConfiguration), integration: integration, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			integration == .moduleInfo ? "Feature.swift" : "ExportFeature+SafeDI.swift": generatedFileHeader + """
			extension ExportFeature {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_UploaderCarrier<__safeDI_Built> {
			        public let uploader: (LazilyInstantiated<ExportService>, Instantiator<ExportScreen>) -> __safeDI_Built

			        public init(uploader: @escaping (LazilyInstantiated<ExportService>, Instantiator<ExportScreen>) -> __safeDI_Built) {
			            self.uploader = uploader
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(uploader: { _, _ in __safeDI_builder() })
			        }
			    }

			    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
			    public init(exportService: ExportService, uploaderBuilder: @escaping () -> any Uploader) {
			        self.init(__safeDI_exportService: exportService, __safeDI_uploaderBuilder: .init(__safeDI_noScope: uploaderBuilder))
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// From code you write, call the initializer above instead.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: __safeDI_UploaderCarrier<any Uploader>) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        @inline(never) func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder.uploader(exportService, screenBuilder)
			        self.init(screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_FF2BE1522AF7694B {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_FF2BE1522AF7694B.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope_exportService: LazilyInstantiated<ExportService>, _ scope_screenBuilder: Instantiator<ExportScreen>) -> any Uploader {
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
			            func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderCarrier<any Uploader> {
			                .init(uploader: { scope_exportService, scope_screenBuilder in __safeDI_uploaderBuilder_ExportFeature_uploader(scope_exportService, scope_screenBuilder) })
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsNoValueWhereSeamBuildsHolesStruct_whenImplementationsReadNothing(integration: MultiModuleIntegration) async throws {
		// `DefaultUploader` receives nothing, and `makeHandBuilt()`'s fill ignores its struct: `ExportFeature` hands the
		// struct the memo unread, so each service is created only where an `ExportScreen` reads it, as inline.
		let feature = Self.feature()
		let app = Self.app(declarations: [], handWrittenFill: "{ DefaultUploader() }")
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app, featureConfiguration: plainDependencyTreeInitializersConfiguration), integration: integration, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderCarrier<any Uploader> {
			            .init(uploader: { scope_exportService, scope_screenBuilder in
			                let uploader: any Uploader = DefaultUploader()
			                return uploader
			            })
			        }
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_FF2BE1522AF7694B.self\(Self.pluginComment(integration))
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	// MARK: Sendable functions

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	mutating func generate_readsAppsSendableMemoInsideSendableFill_whenSeamBuildsHoleInsideSendableBuilder(integration: MultiModuleIntegration) async throws {
		// `Panel`, behind `ExportFeature`'s `SendableInstantiator`, builds the hole, so it is a case of the `@Sendable` enum,
		// and `Root`'s fill reads `Root`'s `SendableLazilyInstantiated` inside the `@Sendable` fill, so the service is created
		// when an `UploadJob` reads it, as inline.
		let feature = Self.feature(exportServiceConformances: ", Sendable", seamDeclarations: Self.seamBuildingPanel, additionalTypes: [Self.panel])
		let app = Self.app(declarations: Self.uploaderBuildingJobs, rootDeclarations: ["@Instantiated let exportService: SendableLazilyInstantiated<ExportService>"], handWrittenFill: nil)
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: integration, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			integration == .moduleInfo ? "Feature.swift" : "ExportFeature+SafeDI.swift": generatedFileHeader + """
			extension ExportFeature {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_UploaderCarrier_Panel<__safeDI_Built> {
			        public let uploader: () -> __safeDI_Built

			        public init(uploader: @escaping () -> __safeDI_Built) {
			            self.uploader = uploader
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(uploader: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_UploaderSendableCarrier<__safeDI_Built>: Sendable {
			        public let panelBuilder: @Sendable () -> __safeDI_UploaderCarrier_Panel<__safeDI_Built>

			        public init(panelBuilder: @escaping @Sendable () -> __safeDI_UploaderCarrier_Panel<__safeDI_Built>) {
			            self.panelBuilder = panelBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(panelBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderSendableBuilder: __safeDI_UploaderSendableCarrier<any Uploader>) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        @inline(never) func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        @inline(never) @Sendable nonisolated func __safeDI_panelBuilder() -> Panel {
			            let __safeDI_uploaderSendableBuilder_panelBuilder = __safeDI_uploaderSendableBuilder.panelBuilder()
			            let uploader: any Uploader = __safeDI_uploaderSendableBuilder_panelBuilder.uploader()
			            return Panel(uploader: uploader)
			        }
			        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
			        self.init(screenBuilder: screenBuilder, panelBuilder: panelBuilder)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_D277063526227E2B {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = SendableLazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_D277063526227E2B.self\(Self.pluginComment(integration))
			            @Sendable nonisolated func __safeDI_uploaderSendableBuilder_ExportFeature_Panel_Scope_uploader() -> any Uploader {
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
			            @Sendable nonisolated func __safeDI_uploaderSendableBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderSendableCarrier<any Uploader> {
			                .init(panelBuilder: { __safeDI_uploaderBuilder_ExportFeature_Panel_Scope() })
			            }
			            @Sendable nonisolated func __safeDI_uploaderBuilder_ExportFeature_Panel_Scope() -> ExportFeature.__safeDI_UploaderCarrier_Panel<any Uploader> {
			                .init(uploader: { __safeDI_uploaderSendableBuilder_ExportFeature_Panel_Scope_uploader() })
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderSendableBuilder: __safeDI_uploaderSendableBuilder_ExportFeature())
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSendableFillReadsAppsNonSendableWrapper(integration: MultiModuleIntegration) async {
		// The `@Sendable` place of the cell above, with `Root` holding a plain `LazilyInstantiated`: the `@Sendable` fill would
		// capture it, as `ExportFeature`'s `SendableInstantiator` would inline.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "UploadJob.swift", inModule: "App", fixtures: fixtures, integration: integration)):9:5: error: @Received property `exportService: ExportService` cannot be received inside a `@Sendable` function in chain: Root -> ExportFeature -> DefaultUploader -> UploadJob. `ExportFeature`’s tree builds `uploader: any Uploader` on `Panel` inside a `@Sendable` function, so the function SafeDI generates to fill its builder is `@Sendable` too, and it cannot capture `exportService: LazilyInstantiated<ExportService>` on `Root`, because `LazilyInstantiated<ExportService>` is not `Sendable`. Declare `exportService` on `Root` as `SendableLazilyInstantiated<ExportService>` to fix. A `SendableLazilyInstantiated` requires its instance type, `ExportService`, to be `Sendable`.
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
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = SendableLazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_FF2BE1522AF7694B.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope_exportService: LazilyInstantiated<ExportService>, _ scope_screenBuilder: Instantiator<ExportScreen>) -> any Uploader {
			                func __safeDI_uploader() -> DefaultUploader {
			                    @Sendable nonisolated func __safeDI_jobBuilder() -> UploadJob {
			                        UploadJob(exportService: exportService.instance)
			                    }
			                    let jobBuilder = SendableInstantiator<UploadJob>(__safeDI_jobBuilder)
			                    return DefaultUploader(jobBuilder: jobBuilder)
			                }
			                let uploader: any Uploader = __safeDI_uploader()
			                return uploader
			            }
			            func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderCarrier<any Uploader> {
			                .init(uploader: { scope_exportService, scope_screenBuilder in __safeDI_uploaderBuilder_ExportFeature_uploader(scope_exportService, scope_screenBuilder) })
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			integration == .moduleInfo ? "Feature.swift" : "ExportFeature+SafeDI.swift": generatedFileHeader + """
			extension ExportFeature {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_UploaderCarrier<__safeDI_Built> {
			        public let uploader: (LazilyInstantiated<ExportService>, LazilyInstantiated<Logger>, Analytics, Instantiator<ExportScreen>) -> __safeDI_Built

			        public init(uploader: @escaping (LazilyInstantiated<ExportService>, LazilyInstantiated<Logger>, Analytics, Instantiator<ExportScreen>) -> __safeDI_Built) {
			            self.uploader = uploader
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(uploader: { _, _, _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_logger: @autoclosure @escaping () -> Logger, __safeDI_uploaderBuilder: __safeDI_UploaderCarrier<any Uploader>) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
			        let analytics = Analytics()
			        @inline(never) func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance, logger: logger.instance)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder.uploader(exportService, logger, analytics, screenBuilder)
			        self.init(analytics: analytics, screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_26BF8476637AFB9E {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

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
			            _ = ExportFeature.__safeDI_ExportFeature_26BF8476637AFB9E.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope_exportService: LazilyInstantiated<ExportService>, _ scope_logger: LazilyInstantiated<Logger>, _ scope_analytics: Analytics, _ scope_screenBuilder: Instantiator<ExportScreen>) -> any Uploader {
			                let analytics = scope_analytics
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
			            func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderCarrier<any Uploader> {
			                .init(uploader: { scope_exportService, scope_logger, scope_analytics, scope_screenBuilder in __safeDI_uploaderBuilder_ExportFeature_uploader(scope_exportService, scope_logger, scope_analytics, scope_screenBuilder) })
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_logger: logger.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, logger: logger, exportFeature: exportFeature)
			    }
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			integration == .moduleInfo ? "Feature.swift" : "ExportFeature+SafeDI.swift": generatedFileHeader + """
			extension ExportFeature {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_UploaderCarrier<__safeDI_Built> {
			        public let uploader: (LazilyInstantiated<ExportService>, LazilyInstantiated<Logger?>, Instantiator<ExportScreen>) -> __safeDI_Built

			        public init(uploader: @escaping (LazilyInstantiated<ExportService>, LazilyInstantiated<Logger?>, Instantiator<ExportScreen>) -> __safeDI_Built) {
			            self.uploader = uploader
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(uploader: { _, _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_logger: @autoclosure @escaping () -> Logger?, __safeDI_uploaderBuilder: __safeDI_UploaderCarrier<any Uploader>) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        let logger = LazilyInstantiated<Logger?>(__safeDI_logger)
			        @inline(never) func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance, logger: logger.instance)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder.uploader(exportService, logger, screenBuilder)
			        self.init(screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_13B7298D34DB4439 {}
			}
			""",
		])
		let expectedFiles: [String: String] = switch integration {
		case .moduleInfo:
			[
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension OtherRoot {
				    public convenience init() {
				        func __safeDI_exportService() -> ExportService {
				            ExportService()
				        }
				        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
				        func __safeDI_exportFeature() -> ExportFeature {
				            _ = ExportFeature.__safeDI_ExportFeature_13B7298D34DB4439.self\(Self.pluginComment(integration))
				            func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope_exportService: LazilyInstantiated<ExportService>, _ scope_logger: LazilyInstantiated<Logger?>, _ scope_screenBuilder: Instantiator<ExportScreen>) -> any Uploader {
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
				            func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderCarrier<any Uploader> {
				                .init(uploader: { scope_exportService, scope_logger, scope_screenBuilder in __safeDI_uploaderBuilder_ExportFeature_uploader(scope_exportService, scope_logger, scope_screenBuilder) })
				            }
				            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_logger: nil, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
				        }
				        let exportFeature: ExportFeature = __safeDI_exportFeature()
				        self.init(exportService: exportService, exportFeature: exportFeature)
				    }
				}

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
				            _ = ExportFeature.__safeDI_ExportFeature_13B7298D34DB4439.self\(Self.pluginComment(integration))
				            func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope_exportService: LazilyInstantiated<ExportService>, _ scope_logger: LazilyInstantiated<Logger?>, _ scope_screenBuilder: Instantiator<ExportScreen>) -> any Uploader {
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
				            func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderCarrier<any Uploader> {
				                .init(uploader: { scope_exportService, scope_logger, scope_screenBuilder in __safeDI_uploaderBuilder_ExportFeature_uploader(scope_exportService, scope_logger, scope_screenBuilder) })
				            }
				            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_logger: logger.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
				        }
				        let exportFeature: ExportFeature = __safeDI_exportFeature()
				        self.init(exportService: exportService, logger: logger, exportFeature: exportFeature)
				    }
				}
				""",
			]
		case .swiftPackagePlugin:
			[
				"OtherRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension OtherRoot {
				    public convenience init() {
				        func __safeDI_exportService() -> ExportService {
				            ExportService()
				        }
				        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
				        func __safeDI_exportFeature() -> ExportFeature {
				            _ = ExportFeature.__safeDI_ExportFeature_13B7298D34DB4439.self\(Self.pluginComment(integration))
				            func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope_exportService: LazilyInstantiated<ExportService>, _ scope_logger: LazilyInstantiated<Logger?>, _ scope_screenBuilder: Instantiator<ExportScreen>) -> any Uploader {
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
				            func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderCarrier<any Uploader> {
				                .init(uploader: { scope_exportService, scope_logger, scope_screenBuilder in __safeDI_uploaderBuilder_ExportFeature_uploader(scope_exportService, scope_logger, scope_screenBuilder) })
				            }
				            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_logger: nil, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
				        }
				        let exportFeature: ExportFeature = __safeDI_exportFeature()
				        self.init(exportService: exportService, exportFeature: exportFeature)
				    }
				}
				""",
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

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
				            _ = ExportFeature.__safeDI_ExportFeature_13B7298D34DB4439.self\(Self.pluginComment(integration))
				            func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope_exportService: LazilyInstantiated<ExportService>, _ scope_logger: LazilyInstantiated<Logger?>, _ scope_screenBuilder: Instantiator<ExportScreen>) -> any Uploader {
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
				            func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderCarrier<any Uploader> {
				                .init(uploader: { scope_exportService, scope_logger, scope_screenBuilder in __safeDI_uploaderBuilder_ExportFeature_uploader(scope_exportService, scope_logger, scope_screenBuilder) })
				            }
				            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_logger: logger.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
				        }
				        let exportFeature: ExportFeature = __safeDI_exportFeature()
				        self.init(exportService: exportService, logger: logger, exportFeature: exportFeature)
				    }
				}
				""",
			]
		}
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, expectedFiles)
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app, probes: ["Root()", "OtherRoot()"])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			integration == .moduleInfo ? "Feature.swift" : "ExportFeature+SafeDI.swift": generatedFileHeader + """
			extension ExportFeature {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_UploaderCarrier<__safeDI_Built> {
			        public let uploader: (LazilyInstantiated<ExportService>, Instantiator<Report>, Instantiator<ExportScreen>) -> __safeDI_Built

			        public init(uploader: @escaping (LazilyInstantiated<ExportService>, Instantiator<Report>, Instantiator<ExportScreen>) -> __safeDI_Built) {
			            self.uploader = uploader
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(uploader: { _, _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_reportBuilder reportBuilder: Instantiator<Report>, __safeDI_uploaderBuilder: __safeDI_UploaderCarrier<any Uploader>) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        @inline(never) func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance, reportBuilder: reportBuilder)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder.uploader(exportService, reportBuilder, screenBuilder)
			        self.init(screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_C772DE6862E17433 {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

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
			            _ = ExportFeature.__safeDI_ExportFeature_C772DE6862E17433.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope_exportService: LazilyInstantiated<ExportService>, _ scope_reportBuilder: Instantiator<Report>, _ scope_screenBuilder: Instantiator<ExportScreen>) -> any Uploader {
			                let reportBuilder = scope_reportBuilder
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
			            func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderCarrier<any Uploader> {
			                .init(uploader: { scope_exportService, scope_reportBuilder, scope_screenBuilder in __safeDI_uploaderBuilder_ExportFeature_uploader(scope_exportService, scope_reportBuilder, scope_screenBuilder) })
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_reportBuilder: reportBuilder, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, reportBuilder: reportBuilder, exportFeature: exportFeature)
			    }
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			integration == .moduleInfo ? "Feature.swift" : "ExportFeature+SafeDI.swift": generatedFileHeader + """
			extension ExportFeature {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_UploaderCarrier<__safeDI_Built> {
			        public let uploader: (LazilyInstantiated<ExportService>, Instantiator<ExportScreen>) -> __safeDI_Built

			        public init(uploader: @escaping (LazilyInstantiated<ExportService>, Instantiator<ExportScreen>) -> __safeDI_Built) {
			            self.uploader = uploader
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(uploader: { _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: __safeDI_UploaderCarrier<any Uploader>) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        @inline(never) func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder.uploader(exportService, screenBuilder)
			        self.init(screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_FF2BE1522AF7694B {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_FF2BE1522AF7694B.self\(Self.pluginComment(integration))
			            func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope_exportService: LazilyInstantiated<ExportService>, _ scope_screenBuilder: Instantiator<ExportScreen>) -> any Uploader {
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
			            func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderCarrier<any Uploader> {
			                .init(uploader: { scope_exportService, scope_screenBuilder in __safeDI_uploaderBuilder_ExportFeature_uploader(scope_exportService, scope_screenBuilder) })
			            }
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [integration == .moduleInfo ? "Feature.swift" : "ExportFeature+SafeDI.swift": generatedFileHeader + """
		extension ExportFeature {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_UploaderCarrier<__safeDI_Built> {
		        public let uploader: (any Exporting, Instantiator<ExportScreen>) -> __safeDI_Built

		        public init(uploader: @escaping (any Exporting, Instantiator<ExportScreen>) -> __safeDI_Built) {
		            self.uploader = uploader
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(uploader: { _, _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_exportService __safeDI_exportService_: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: __safeDI_UploaderCarrier<any Uploader>) {
		        #sourceLocation(file: "\(seamPath)", line: 9)
		        let exportService: any Exporting = __safeDI_exportService_()
		        #sourceLocation()
		        @inline(never) func __safeDI_screenBuilder() -> ExportScreen {
		            ExportScreen(exportService: exportService)
		        }
		        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
		        let uploader: any Uploader = __safeDI_uploaderBuilder.uploader(exportService, screenBuilder)
		        self.init(exportService: exportService, screenBuilder: screenBuilder, uploader: uploader)
		    }
		}

		extension ExportFeature {
		    public enum __safeDI_ExportFeature_6A5C265A262ED540 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope_exportService: any Exporting, _ scope_screenBuilder: Instantiator<ExportScreen>) -> any Uploader {
			            return __safeDI_fillBody_7B443D67920E8ADB(exportService: scope_exportService)
			        }
			        func __safeDI_fillBody_7B443D67920E8ADB(exportService: any Exporting) -> any Uploader {
			            func __safeDI_jobBuilder() -> UploadJob {
			                UploadJob(exportService: exportService)
			            }
			            func __safeDI_uploader() -> DefaultUploader {
			                let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                return DefaultUploader(jobBuilder: jobBuilder)
			            }
			            let uploader: any Uploader = __safeDI_uploader()
			            return uploader
			        }
			        func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderCarrier<any Uploader> {
			            .init(uploader: { scope_exportService, scope_screenBuilder in __safeDI_uploaderBuilder_ExportFeature_uploader(scope_exportService, scope_screenBuilder) })
			        }
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_6A5C265A262ED540.self\(Self.pluginComment(integration))
			            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, integration == .moduleInfo ? ["Feature.swift": generatedFileHeader + """
		extension ExportFeature {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_UploaderCarrier<__safeDI_Built> {
		        public let uploader: (LazilyInstantiated<ExportService>, Instantiator<ExportScreen>) -> __safeDI_Built

		        public init(uploader: @escaping (LazilyInstantiated<ExportService>, Instantiator<ExportScreen>) -> __safeDI_Built) {
		            self.uploader = uploader
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(uploader: { _, _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: __safeDI_UploaderCarrier<any Uploader>) {
		        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
		        @inline(never) func __safeDI_screenBuilder() -> ExportScreen {
		            ExportScreen(exportService: exportService.instance)
		        }
		        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
		        let uploader: any Uploader = __safeDI_uploaderBuilder.uploader(exportService, screenBuilder)
		        self.init(screenBuilder: screenBuilder, uploader: uploader)
		    }
		}

		extension ExportFeature {
		    public enum __safeDI_ExportFeature_FF2BE1522AF7694B {}
		}

		extension Shell {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_UploaderCarrier<__safeDI_Built> {
		        public let exportFeature: ExportFeature.__safeDI_UploaderCarrier<__safeDI_Built>

		        public init(exportFeature: ExportFeature.__safeDI_UploaderCarrier<__safeDI_Built>) {
		            self.exportFeature = exportFeature
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(exportFeature: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: __safeDI_UploaderCarrier<any Uploader>) {
		        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
		        @inline(never) func __safeDI_headerBuilder() -> Header {
		            Header(exportService: exportService.instance)
		        }
		        let headerBuilder = Instantiator<Header>(__safeDI_headerBuilder)
		        @inline(never) func __safeDI_exportFeature() -> ExportFeature {
		            _ = ExportFeature.__safeDI_ExportFeature_FF2BE1522AF7694B.self
		            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder.exportFeature)
		        }
		        let exportFeature: ExportFeature = __safeDI_exportFeature()
		        self.init(headerBuilder: headerBuilder, exportFeature: exportFeature)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_BD1CFAC75C7AF53A {}
		}
		"""] : ["ExportFeature+SafeDI.swift": generatedFileHeader + """
		extension ExportFeature {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_UploaderCarrier<__safeDI_Built> {
		        public let uploader: (LazilyInstantiated<ExportService>, Instantiator<ExportScreen>) -> __safeDI_Built

		        public init(uploader: @escaping (LazilyInstantiated<ExportService>, Instantiator<ExportScreen>) -> __safeDI_Built) {
		            self.uploader = uploader
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(uploader: { _, _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: __safeDI_UploaderCarrier<any Uploader>) {
		        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
		        @inline(never) func __safeDI_screenBuilder() -> ExportScreen {
		            ExportScreen(exportService: exportService.instance)
		        }
		        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
		        let uploader: any Uploader = __safeDI_uploaderBuilder.uploader(exportService, screenBuilder)
		        self.init(screenBuilder: screenBuilder, uploader: uploader)
		    }
		}

		extension ExportFeature {
		    public enum __safeDI_ExportFeature_FF2BE1522AF7694B {}
		}
		""", "Shell+SafeDI.swift": generatedFileHeader + """
		extension Shell {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_UploaderCarrier<__safeDI_Built> {
		        public let exportFeature: ExportFeature.__safeDI_UploaderCarrier<__safeDI_Built>

		        public init(exportFeature: ExportFeature.__safeDI_UploaderCarrier<__safeDI_Built>) {
		            self.exportFeature = exportFeature
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(exportFeature: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: __safeDI_UploaderCarrier<any Uploader>) {
		        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
		        @inline(never) func __safeDI_headerBuilder() -> Header {
		            Header(exportService: exportService.instance)
		        }
		        let headerBuilder = Instantiator<Header>(__safeDI_headerBuilder)
		        @inline(never) func __safeDI_exportFeature() -> ExportFeature {
		            _ = ExportFeature.__safeDI_ExportFeature_FF2BE1522AF7694B.self
		            return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder.exportFeature)
		        }
		        let exportFeature: ExportFeature = __safeDI_exportFeature()
		        self.init(headerBuilder: headerBuilder, exportFeature: exportFeature)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_BD1CFAC75C7AF53A {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope_exportService: LazilyInstantiated<ExportService>, _ scope_screenBuilder: Instantiator<ExportScreen>) -> any Uploader {
			            return __safeDI_fillBody_7F8BAC28344D63D6(exportService: scope_exportService)
			        }
			        func __safeDI_fillBody_7F8BAC28344D63D6(exportService: LazilyInstantiated<ExportService>) -> any Uploader {
			            func __safeDI_jobBuilder() -> UploadJob {
			                UploadJob(exportService: exportService.instance)
			            }
			            func __safeDI_uploader() -> DefaultUploader {
			                let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                return DefaultUploader(jobBuilder: jobBuilder)
			            }
			            let uploader: any Uploader = __safeDI_uploader()
			            return uploader
			        }
			        func __safeDI_uploaderBuilder_Shell() -> Shell.__safeDI_UploaderCarrier<any Uploader> {
			            .init(exportFeature: __safeDI_uploaderBuilder_ExportFeature())
			        }
			        func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderCarrier<any Uploader> {
			            .init(uploader: { scope_exportService, scope_screenBuilder in __safeDI_uploaderBuilder_ExportFeature_uploader(scope_exportService, scope_screenBuilder) })
			        }
			        func __safeDI_exportService() -> ExportService {
			            ExportService()
			        }
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        func __safeDI_shell() -> Shell {
			            _ = Shell.__safeDI_Shell_BD1CFAC75C7AF53A.self\(Self.pluginComment(integration, seam: "Shell"))
			            return Shell(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_Shell())
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(exportService: exportService, shell: shell)
			    }
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, integration == .moduleInfo ? [
			"Feature.swift": generatedFileHeader + """
			extension ExportFeature {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_UploaderCarrier<__safeDI_Built> {
			        public let uploader: (LazilyInstantiated<ExportService>, Instantiator<ExportScreen>) -> __safeDI_Built

			        public init(uploader: @escaping (LazilyInstantiated<ExportService>, Instantiator<ExportScreen>) -> __safeDI_Built) {
			            self.uploader = uploader
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(uploader: { _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: __safeDI_UploaderCarrier<any Uploader>) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        @inline(never) func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder.uploader(exportService, screenBuilder)
			        self.init(screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_FF2BE1522AF7694B {}
			}

			#if DEBUG
			extension ExportFeature {
			    nonisolated public enum SafeDIMockScope_Uploader {
			        nonisolated public struct uploader_Values {
			            public let exportService: ExportService
			            public let screenBuilder: Instantiator<ExportScreen>
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let uploader: (uploader_Values) -> __safeDI_Built

			            public init(uploader: @escaping (uploader_Values) -> __safeDI_Built) {
			                self.uploader = uploader
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(uploader: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            exportService: (() -> ExportService)? = nil,
			            screenBuilder: ((ExportService) -> ExportScreen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                exportService: exportService,
			                screenBuilder: screenBuilder
			            )
			        }

			        public var exportService: (() -> ExportService)? { __safeDI_storage.exportService }
			        public var screenBuilder: ((ExportService) -> ExportScreen)? { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                exportService: (() -> ExportService)?,
			                screenBuilder: ((ExportService) -> ExportScreen)?
			            ) {
			                self.exportService = exportService
			                self.screenBuilder = screenBuilder
			            }

			            let exportService: (() -> ExportService)?
			            let screenBuilder: ((ExportService) -> ExportScreen)?
			        }
			    }

			    public static func mock(
			        uploaderBuilder: @escaping () -> any Uploader,
			        exportService: ExportService? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> ExportFeature {
			        ExportFeature.__safeDI_mock(uploaderBuilder: .init(__safeDI_noScope: uploaderBuilder), exportService: exportService, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        uploaderBuilder __safeDI_uploaderBuilder: ExportFeature.SafeDIMockScope_Uploader.__safeDI_Builder<any Uploader>,
			        exportService: ExportService? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> ExportFeature {
			        let exportService = if let exportService { exportService } else if let safeDIBuilder = safeDIOverrides.exportService { safeDIBuilder() } else { ExportService() }
			        func __safeDI_screenBuilder() -> ExportScreen {
			            if let safeDIBuilder = safeDIOverrides.screenBuilder { safeDIBuilder(exportService) } else { ExportScreen(exportService: exportService) }
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder.uploader(SafeDIMockScope_Uploader.uploader_Values(exportService: exportService, screenBuilder: screenBuilder))
			        return ExportFeature(screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_mock_5983C25B8928E9B6 {}
			}
			#endif
			""",
		] : [
			"ExportFeature+SafeDI.swift": generatedFileHeader + """
			extension ExportFeature {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_UploaderCarrier<__safeDI_Built> {
			        public let uploader: (LazilyInstantiated<ExportService>, Instantiator<ExportScreen>) -> __safeDI_Built

			        public init(uploader: @escaping (LazilyInstantiated<ExportService>, Instantiator<ExportScreen>) -> __safeDI_Built) {
			            self.uploader = uploader
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(uploader: { _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_exportService: @autoclosure @escaping () -> ExportService, __safeDI_uploaderBuilder: __safeDI_UploaderCarrier<any Uploader>) {
			        let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			        @inline(never) func __safeDI_screenBuilder() -> ExportScreen {
			            ExportScreen(exportService: exportService.instance)
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder.uploader(exportService, screenBuilder)
			        self.init(screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_FF2BE1522AF7694B {}
			}
			""",
			"ExportFeature+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension ExportFeature {
			    nonisolated public enum SafeDIMockScope_Uploader {
			        nonisolated public struct uploader_Values {
			            public let exportService: ExportService
			            public let screenBuilder: Instantiator<ExportScreen>
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let uploader: (uploader_Values) -> __safeDI_Built

			            public init(uploader: @escaping (uploader_Values) -> __safeDI_Built) {
			                self.uploader = uploader
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(uploader: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            exportService: (() -> ExportService)? = nil,
			            screenBuilder: ((ExportService) -> ExportScreen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                exportService: exportService,
			                screenBuilder: screenBuilder
			            )
			        }

			        public var exportService: (() -> ExportService)? { __safeDI_storage.exportService }
			        public var screenBuilder: ((ExportService) -> ExportScreen)? { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                exportService: (() -> ExportService)?,
			                screenBuilder: ((ExportService) -> ExportScreen)?
			            ) {
			                self.exportService = exportService
			                self.screenBuilder = screenBuilder
			            }

			            let exportService: (() -> ExportService)?
			            let screenBuilder: ((ExportService) -> ExportScreen)?
			        }
			    }

			    public static func mock(
			        uploaderBuilder: @escaping () -> any Uploader,
			        exportService: ExportService? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> ExportFeature {
			        ExportFeature.__safeDI_mock(uploaderBuilder: .init(__safeDI_noScope: uploaderBuilder), exportService: exportService, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        uploaderBuilder __safeDI_uploaderBuilder: ExportFeature.SafeDIMockScope_Uploader.__safeDI_Builder<any Uploader>,
			        exportService: ExportService? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> ExportFeature {
			        let exportService = if let exportService { exportService } else if let safeDIBuilder = safeDIOverrides.exportService { safeDIBuilder() } else { ExportService() }
			        func __safeDI_screenBuilder() -> ExportScreen {
			            if let safeDIBuilder = safeDIOverrides.screenBuilder { safeDIBuilder(exportService) } else { ExportScreen(exportService: exportService) }
			        }
			        let screenBuilder = Instantiator<ExportScreen>(__safeDI_screenBuilder)
			        let uploader: any Uploader = __safeDI_uploaderBuilder.uploader(SafeDIMockScope_Uploader.uploader_Values(exportService: exportService, screenBuilder: screenBuilder))
			        return ExportFeature(screenBuilder: screenBuilder, uploader: uploader)
			    }
			}

			extension ExportFeature {
			    public enum __safeDI_ExportFeature_mock_5983C25B8928E9B6 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """

			""",
		])
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
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope_exportService: LazilyInstantiated<ExportService>, _ scope_screenBuilder: Instantiator<ExportScreen>) -> any Uploader {
			            return __safeDI_fillBody_1A3C0A5558A8DE41(exportService: scope_exportService)
			        }
			        func __safeDI_fillBody_1A3C0A5558A8DE41(exportService: LazilyInstantiated<ExportService>) -> any Uploader {
			            func __safeDI_uploader() -> DefaultUploader {
			                func __safeDI_jobBuilder() -> UploadJob {
			                    UploadJob(exportService: exportService.instance)
			                }
			                let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                func __safeDI_reentry() -> Reentry {
			                    let exportService = ExportService()
			                    func __safeDI_featureBuilder() -> ExportFeature {
			                        _ = ExportFeature.__safeDI_ExportFeature_FF2BE1522AF7694B.self\(Self.pluginComment(integration))
			                        return ExportFeature(__safeDI_exportService: exportService, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
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
			        func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderCarrier<any Uploader> {
			            .init(uploader: { scope_exportService, scope_screenBuilder in __safeDI_uploaderBuilder_ExportFeature_uploader(scope_exportService, scope_screenBuilder) })
			        }
			        let exportService = ExportService()
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_FF2BE1522AF7694B.self\(Self.pluginComment(integration))
			            return ExportFeature(__safeDI_exportService: exportService, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, feature: feature, app: app)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsStructsMemoWhereTreeReadsIt_whenCallInsideFillReentersSeamBeneathLazilyInstantiatedDeclarationOfDeferredLabel(integration: MultiModuleIntegration) async throws {
		// As above, with `Reentry` declaring its service lazily: the fill binds the struct's memo and reads its instance where
		// the inner `UploadJob` is built, so `Reentry`'s service is created only then, as inline.
		let feature = Self.feature()
		let app = Self.app(
			declarations: Self.uploaderBuildingJobs + ["@Instantiated let reentry: Reentry"],
			rootDeclarations: ["@Instantiated let exportService: ExportService"],
			handWrittenFill: nil,
		) + [seamFixtureType(named: "Reentry", isFinalClass: true, declarations: ["@Instantiated let exportService: LazilyInstantiated<ExportService>", "@Instantiated let featureBuilder: Instantiator<ExportFeature>"])]
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: integration, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope_exportService: LazilyInstantiated<ExportService>, _ scope_screenBuilder: Instantiator<ExportScreen>) -> any Uploader {
			            return __safeDI_fillBody_5288686F09B25680(exportService: scope_exportService)
			        }
			        func __safeDI_fillBody_5288686F09B25680(exportService: LazilyInstantiated<ExportService>) -> any Uploader {
			            func __safeDI_uploader() -> DefaultUploader {
			                func __safeDI_jobBuilder() -> UploadJob {
			                    UploadJob(exportService: exportService.instance)
			                }
			                let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
			                func __safeDI_reentry() -> Reentry {
			                    func __safeDI_exportService() -> ExportService {
			                        ExportService()
			                    }
			                    let exportService = LazilyInstantiated<ExportService>(__safeDI_exportService)
			                    func __safeDI_featureBuilder() -> ExportFeature {
			                        _ = ExportFeature.__safeDI_ExportFeature_FF2BE1522AF7694B.self\(Self.pluginComment(integration))
			                        return ExportFeature(__safeDI_exportService: exportService.instance, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
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
			        func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.__safeDI_UploaderCarrier<any Uploader> {
			            .init(uploader: { scope_exportService, scope_screenBuilder in __safeDI_uploaderBuilder_ExportFeature_uploader(scope_exportService, scope_screenBuilder) })
			        }
			        let exportService = ExportService()
			        func __safeDI_exportFeature() -> ExportFeature {
			            _ = ExportFeature.__safeDI_ExportFeature_FF2BE1522AF7694B.self\(Self.pluginComment(integration))
			            return ExportFeature(__safeDI_exportService: exportService, __safeDI_uploaderBuilder: __safeDI_uploaderBuilder_ExportFeature())
			        }
			        let exportFeature: ExportFeature = __safeDI_exportFeature()
			        self.init(exportService: exportService, exportFeature: exportFeature)
			    }
			}
			""",
		])
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

	/// `ExportFeature`'s declarations when it builds the hole in `Panel`, behind a `SendableInstantiator`: a place of the
	/// `@Sendable` enum.
	private static let seamBuildingPanel = ["@Instantiated let screenBuilder: Instantiator<ExportScreen>", "@Instantiated let panelBuilder: SendableInstantiator<Panel>"]

	/// `Panel`, which instantiates `uploader: any Uploader`.
	private static let panel = seamFixtureType(named: "Panel", declarations: ["@Instantiated let uploader: any Uploader"])

	/// `DefaultUploader` instantiating `jobBuilder`, whose `UploadJob` receives `exportService`.
	private static let uploaderBuildingJobs = ["@Instantiated let jobBuilder: Instantiator<UploadJob>"]

	/// A fill that reads the struct's `exportService` where its `jobBuilder` builds an `UploadJob`.
	private static let handWrittenFillReadingCallersMemo = "{ DefaultUploader(jobBuilder: Instantiator { UploadJob(exportService: exportService.instance) }) }"

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
