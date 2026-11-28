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

/// The guard enum a seam's module generates beside its initializers, which every call names on the line before it, so that
/// a call generated against another signature fails to compile there. It is a hash of the signature the callers' code
/// depends on: what the generated-only builder struct is shaped by – the levels and the values each binds, the members, the
/// family – and never the readable initializers, the files the declarations are in, or what a caller fills a place with.
/// Each test generates the same fixture – `Home`, a seam in `Feature`, binds `logger` and builds `Detail` through
/// `detailBuilder`, and `Detail`'s `api: any Api` is a place `App` fills with `LiveApi`, which reads `logger` – and a
/// variant of it, and compares the two guards.
struct SafeDIToolSeamGuardTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesTheGuard_whenSeamBindsAnotherValueBeforeThePlacesLevel() async throws {
		// `Home` binds `navigator` before `detailBuilder`, so a field joins `detailBuilder_Values`.
		let base = try await executeSafeDIToolMultiModuleTest(modules: Self.baseModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let variant = try await executeSafeDIToolMultiModuleTest(modules: Self.featureAndApp(feature: Self.feature(home: ["@Instantiated public let logger: Logger", "@Instantiated public let navigator: Navigator", "@Instantiated public let detailBuilder: Instantiator<Detail>"], extraTypes: [seamFixtureType(named: "Navigator", isFinalClass: true, declarations: [])]), app: Self.app()), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(base.modules["Feature"]?.generatedFiles["Feature.swift"] == Self.baseFeatureOutput)
		#expect(base.modules["App"]?.generatedFiles["App.swift"] == Self.baseAppOutput)
		#expect(variant.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: (Logger, Navigator) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Logger, Navigator) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let logger = Logger()
		        let navigator = Navigator()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(logger, navigator)
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, navigator: navigator, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_4D9476E4D069B289 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: { values_logger, values_navigator in __safeDI_apiBuilder_Home_Detail_Scope(logger: values_logger) })
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi(logger: logger)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_4D9476E4D069B289.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		#expect(Self.guardName(in: base) != Self.guardName(in: variant))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesTheGuard_whenLevelIsInsertedBetweenSeamAndPlace() async throws {
		// `Home` builds `Step`, which builds `Detail`: a level is inserted between `Home` and `Detail`.
		let base = try await executeSafeDIToolMultiModuleTest(modules: Self.baseModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let variant = try await executeSafeDIToolMultiModuleTest(modules: Self.featureAndApp(feature: Self.feature(home: ["@Instantiated public let logger: Logger", "@Instantiated public let stepBuilder: Instantiator<Step>"], extraTypes: [seamFixtureType(named: "Step", isFinalClass: true, declarations: ["@Instantiated public let detailBuilder: Instantiator<Detail>"])]), app: Self.app()), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(base.modules["Feature"]?.generatedFiles["Feature.swift"] == Self.baseFeatureOutput)
		#expect(base.modules["App"]?.generatedFiles["App.swift"] == Self.baseAppOutput)
		#expect(variant.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let stepBuilder: (Logger) -> __safeDI_ApiCarrier_Step<__safeDI_Built>

		        public init(stepBuilder: @escaping (Logger) -> __safeDI_ApiCarrier_Step<__safeDI_Built>) {
		            self.stepBuilder = stepBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Step<__safeDI_Built> {
		        public let detailBuilder: __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let logger = Logger()
		        let __safeDI_apiBuilder_stepBuilder = __safeDI_apiBuilder.stepBuilder(logger)
		        @inline(never) func __safeDI_detailBuilder(__safeDI_apiBuilder_detailBuilder: __safeDI_ApiCarrier_Detail<any Api>) -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        @inline(never) func __safeDI_stepBuilder() -> Step {
		            let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder_stepBuilder.detailBuilder
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(__safeDI_apiBuilder_detailBuilder: __safeDI_apiBuilder_detailBuilder)
		            }
		            return Step(detailBuilder: detailBuilder)
		        }
		        let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		        self.init(logger: logger, stepBuilder: stepBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_70AF4E4105299892 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(stepBuilder: { values_logger in __safeDI_apiBuilder_Home_Step_Scope(logger: values_logger) })
		        }
		        func __safeDI_apiBuilder_Home_Step_Scope(logger: Logger) -> Home.__safeDI_ApiCarrier_Step<any Api> {
		            .init(detailBuilder: __safeDI_apiBuilder_Home_Detail_Scope(logger: logger))
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi(logger: logger)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_70AF4E4105299892.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		#expect(Self.guardName(in: base) != Self.guardName(in: variant))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesTheGuard_whenBuilderGainsAMember() async throws {
		// `Detail` gains a second place of `any Api`, `backupApi`, so the builder gains a member.
		let base = try await executeSafeDIToolMultiModuleTest(modules: Self.baseModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let variant = try await executeSafeDIToolMultiModuleTest(modules: Self.featureAndApp(feature: Self.feature(detail: ["@Instantiated public let api: any Api", "@Instantiated public let backupApi: any Api"]), app: Self.app()), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(base.modules["Feature"]?.generatedFiles["Feature.swift"] == Self.baseFeatureOutput)
		#expect(base.modules["App"]?.generatedFiles["App.swift"] == Self.baseAppOutput)
		#expect(variant.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: () -> __safeDI_Built
		        public let backupApi: (any Api) -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built, backupApi: @escaping (any Api) -> __safeDI_Built) {
		            self.api = api
		            self.backupApi = backupApi
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let logger = Logger()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(logger)
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
		            let backupApi: any Api = __safeDI_apiBuilder_detailBuilder.backupApi(api)
		            return Detail(api: api, backupApi: backupApi)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_1A867B1C5760DA8E {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: { values_logger in __safeDI_apiBuilder_Home_Detail_Scope(logger: values_logger) })
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(
		                api: {
		                    let api: any Api = LiveApi(logger: logger)
		                    return api
		                },
		                backupApi: { scope_api in
		                    let backupApi: any Api = LiveApi(logger: logger)
		                    return backupApi
		                }
		            )
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_1A867B1C5760DA8E.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		#expect(Self.guardName(in: base) != Self.guardName(in: variant))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesTheGuard_whenPlaceMovesBeneathSendableInstantiator() async throws {
		// `Home` builds `Detail` through a `SendableInstantiator`, so the place moves to the `@Sendable` family. `LiveApi` reads
		// nothing, since a `@Sendable` builder is handed only what its function binds; what the fill reads does not move the
		// guard (`generate_keepsTheGuard_whenCallerFillsThePlaceWithAnotherType`).
		let base = try await executeSafeDIToolMultiModuleTest(modules: Self.baseModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let variant = try await executeSafeDIToolMultiModuleTest(modules: Self.featureAndApp(feature: Self.feature(home: ["@Instantiated public let logger: Logger", "@Instantiated public let detailBuilder: SendableInstantiator<Detail>"]), app: Self.app(liveApiDeclarations: [])), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(base.modules["Feature"]?.generatedFiles["Feature.swift"] == Self.baseFeatureOutput)
		#expect(base.modules["App"]?.generatedFiles["App.swift"] == Self.baseAppOutput)
		#expect(variant.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let detailBuilder: @Sendable () -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        let logger = Logger()
		        @inline(never) @Sendable nonisolated func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiSendableBuilder_detailBuilder = __safeDI_apiSendableBuilder.detailBuilder()
		            let api: any Api = __safeDI_apiSendableBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        let detailBuilder = SendableInstantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_9EB7819EA43F2884 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(detailBuilder: { __safeDI_apiBuilder_Home_Detail_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope() -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_9EB7819EA43F2884.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		#expect(Self.guardName(in: base) != Self.guardName(in: variant))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesTheGuard_whenSeamGainsSiblingDeclaredAfterTheCarrier() async throws {
		// `Home` gains `tracker`, which its module builds, declared after `detailBuilder` and read by no fill: a sibling that
		// holds no place is built before the carrier, so a field joins `detailBuilder_Values`.
		let base = try await executeSafeDIToolMultiModuleTest(modules: Self.baseModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let variant = try await executeSafeDIToolMultiModuleTest(modules: Self.featureAndApp(feature: Self.feature(home: ["@Instantiated public let logger: Logger", "@Instantiated public let detailBuilder: Instantiator<Detail>", "@Instantiated public let tracker: Tracker"], extraTypes: [seamFixtureType(named: "Tracker", isFinalClass: true, declarations: [])]), app: Self.app()), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(base.modules["Feature"]?.generatedFiles["Feature.swift"] == Self.baseFeatureOutput)
		#expect(base.modules["App"]?.generatedFiles["App.swift"] == Self.baseAppOutput)
		#expect(variant.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: (Logger, Tracker) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Logger, Tracker) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let logger = Logger()
		        let tracker = Tracker()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(logger, tracker)
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder, tracker: tracker)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_39BFF81F0BCF05D7 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: { values_logger, values_tracker in __safeDI_apiBuilder_Home_Detail_Scope(logger: values_logger) })
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi(logger: logger)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_39BFF81F0BCF05D7.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		#expect(Self.guardName(in: base) != Self.guardName(in: variant))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheGuard_whenModuleGeneratesPlainInitializers() async throws {
		// `Feature` sets `generatePlainDependencyTreeInitializers`: the readable initializer is added, and no call changes.
		let base = try await executeSafeDIToolMultiModuleTest(modules: Self.baseModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let variant = try await executeSafeDIToolMultiModuleTest(modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.feature(), swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration), Self.appModule(Self.app())], integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(base.modules["Feature"]?.generatedFiles["Feature.swift"] == Self.baseFeatureOutput)
		#expect(base.modules["App"]?.generatedFiles["App.swift"] == Self.baseAppOutput)
		#expect(variant.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiBuilder: @escaping () -> any Api) {
		        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_Api<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_ApiCarrier<__safeDI_Built> {
		            .init(detailBuilder: { _ in __safeDI_noScope_Home_SafeDICarrierScope_Api_Detail_Scope(__safeDI_builder) })
		        }
		        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_Api_Detail_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_ApiCarrier_Detail<__safeDI_Built> {
		            .init(api: { __safeDI_builder() })
		        }
		        self.init(__safeDI_apiBuilder: __safeDI_noScope_Home_SafeDICarrierScope_Api(apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let logger = Logger()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(logger)
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_6C25FE4006929184 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: { values_logger in __safeDI_apiBuilder_Home_Detail_Scope(logger: values_logger) })
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi(logger: logger)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_6C25FE4006929184.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		#expect(Self.guardName(in: base) == Self.guardName(in: variant))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheGuard_whenSeamGainsSiblingThatReceivesTheCarrier() async throws {
		// `Home` gains `watcher`, whose `Watcher` receives `detailBuilder`: it is bound after the level's values, so no field
		// joins and no builder or parameter changes.
		let base = try await executeSafeDIToolMultiModuleTest(modules: Self.baseModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let variant = try await executeSafeDIToolMultiModuleTest(modules: Self.featureAndApp(feature: Self.feature(home: ["@Instantiated public let logger: Logger", "@Instantiated public let detailBuilder: Instantiator<Detail>", "@Instantiated public let watcher: Watcher"], extraTypes: [seamFixtureType(named: "Watcher", isFinalClass: true, declarations: ["@Received public let detailBuilder: Instantiator<Detail>"])]), app: Self.app()), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(base.modules["Feature"]?.generatedFiles["Feature.swift"] == Self.baseFeatureOutput)
		#expect(base.modules["App"]?.generatedFiles["App.swift"] == Self.baseAppOutput)
		#expect(variant.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let logger = Logger()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(logger)
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        let watcher = Watcher(detailBuilder: detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder, watcher: watcher)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_6C25FE4006929184 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: { values_logger in __safeDI_apiBuilder_Home_Detail_Scope(logger: values_logger) })
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi(logger: logger)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_6C25FE4006929184.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		#expect(Self.guardName(in: base) == Self.guardName(in: variant))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheGuard_whenDeclarationsMoveIntoOneRenamedFile() async throws {
		// `Feature`'s declarations are in one file, `Screens.swift`, in the other order.
		let base = try await executeSafeDIToolMultiModuleTest(modules: Self.baseModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let variant = try await executeSafeDIToolMultiModuleTest(modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Screens.swift": Self.feature().reversed().joined(separator: "\n\n")]), Self.appModule(Self.app())], integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(base.modules["Feature"]?.generatedFiles["Feature.swift"] == Self.baseFeatureOutput)
		#expect(base.modules["App"]?.generatedFiles["App.swift"] == Self.baseAppOutput)
		#expect(variant.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let logger = Logger()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(logger)
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_6C25FE4006929184 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: { values_logger in __safeDI_apiBuilder_Home_Detail_Scope(logger: values_logger) })
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi(logger: logger)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_6C25FE4006929184.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		#expect(Self.guardName(in: base) == Self.guardName(in: variant))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheGuard_whenCallerFillsThePlaceWithAnotherType() async throws {
		// `App` fills the place with `OtherApi`.
		let base = try await executeSafeDIToolMultiModuleTest(modules: Self.baseModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let variant = try await executeSafeDIToolMultiModuleTest(modules: Self.featureAndApp(feature: Self.feature(), app: Self.app(fulfillingTypeName: "OtherApi")), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(base.modules["Feature"]?.generatedFiles["Feature.swift"] == Self.baseFeatureOutput)
		#expect(base.modules["App"]?.generatedFiles["App.swift"] == Self.baseAppOutput)
		#expect(variant.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let logger = Logger()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(logger)
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_6C25FE4006929184 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: { values_logger in __safeDI_apiBuilder_Home_Detail_Scope(logger: values_logger) })
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = OtherApi(logger: logger)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_6C25FE4006929184.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		#expect(Self.guardName(in: base) == Self.guardName(in: variant))
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The fixture every test compares its variant with.
	private static let baseModules = featureAndApp(feature: feature(), app: app())

	/// What `Feature` generates for `baseModules`.
	private static let baseFeatureOutput = generatedFileHeader + """
	extension Home {
	    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
	        public let detailBuilder: (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

	        public init(detailBuilder: @escaping (Logger) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
	            self.detailBuilder = detailBuilder
	        }
	    }

	    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
	        public let api: () -> __safeDI_Built

	        public init(api: @escaping () -> __safeDI_Built) {
	            self.api = api
	        }
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
	    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
	        let logger = Logger()
	        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(logger)
	        @inline(never) func __safeDI_detailBuilder() -> Detail {
	            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
	            return Detail(api: api)
	        }
	        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
	        self.init(logger: logger, detailBuilder: detailBuilder)
	    }
	}

	extension Home {
	    public enum __safeDI_Home_6C25FE4006929184 {}
	}
	"""

	/// What `App` generates for `baseModules`.
	private static let baseAppOutput = generatedFileHeader + """
	#if canImport(Feature)
	import Feature
	#endif

	extension Root {
	    public convenience init() {
	        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
	            .init(detailBuilder: { values_logger in __safeDI_apiBuilder_Home_Detail_Scope(logger: values_logger) })
	        }
	        func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
	            .init(api: {
	                let api: any Api = LiveApi(logger: logger)
	                return api
	            })
	        }
	        func __safeDI_home() -> Home {
	            _ = Home.__safeDI_Home_6C25FE4006929184.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
	            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
	        }
	        let home: Home = __safeDI_home()
	        self.init(home: home)
	    }
	}
	"""

	/// `Feature`'s files: `Home`, a seam declaring `home`, `Detail` declaring `detail`, `Logger`, the protocol `Api`, and
	/// `extraTypes`.
	private static func feature(
		home: [String] = ["@Instantiated public let logger: Logger", "@Instantiated public let detailBuilder: Instantiator<Detail>"],
		detail: [String] = ["@Instantiated public let api: any Api"],
		extraTypes: [String] = [],
	) -> [String] {
		[
			"public protocol Api: AnyObject {}",
			seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Detail", isFinalClass: true, declarations: detail),
		] + extraTypes + [
			seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: home),
		]
	}

	/// `App`'s files: `fulfillingTypeName`, which fills `any Api` and declares `liveApiDeclarations`, and `Root`, which
	/// instantiates `Home`.
	private static func app(fulfillingTypeName: String = "LiveApi", liveApiDeclarations: [String] = ["@Received public let logger: Logger"]) -> [String] {
		[
			seamFixtureType(named: fulfillingTypeName, isFinalClass: true, declarations: liveApiDeclarations, conformances: ", Api")
				.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n"),
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
		]
	}

	/// `Feature`, which declares `feature`'s types, and `App`, which declares `app`'s.
	private static func featureAndApp(feature: [String], app: [String]) -> [ModuleFixture] {
		[ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature), appModule(app)]
	}

	/// `App`, which declares `app`'s types and depends on `Feature`.
	private static func appModule(_ app: [String]) -> ModuleFixture {
		ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"])
	}

	/// The name of the guard enum `output`'s `Feature` generates for `Home`.
	private static func guardName(in output: MultiModuleTestOutput) -> String? {
		output.modules["Feature"]?.generatedFiles["Feature.swift"]?
			.components(separatedBy: "\n")
			.first { $0.contains("public enum __safeDI_Home_") }?
			.trimmingCharacters(in: .whitespaces)
	}
}
