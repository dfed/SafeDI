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
		    nonisolated public enum SafeDIScope_Api {
		        nonisolated public struct detailBuilder_Values {
		            public let logger: Logger
		            public let navigator: Navigator
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let logger = Logger()
		        let navigator = Navigator()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIScope_Api.detailBuilder_Values(logger: logger, navigator: navigator))
		        func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api(SafeDIScope_Api.Detail_Scope.api_Values())
		            return Detail(api: api)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, navigator: navigator, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_4F107D538D5CEFB9 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_4F107D538D5CEFB9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(logger: values.logger) })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(logger: logger)
		                    return api
		                })
		            }
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
		    nonisolated public enum SafeDIScope_Api {
		        nonisolated public struct stepBuilder_Values {
		            public let logger: Logger
		        }

		        nonisolated public enum Step_Scope {
		            nonisolated public struct detailBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.detailBuilder = detailBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let stepBuilder: (stepBuilder_Values) -> SafeDIScope_Api.Step_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(stepBuilder: @escaping (stepBuilder_Values) -> SafeDIScope_Api.Step_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.stepBuilder = stepBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.stepBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let logger = Logger()
		        let __safeDI_apiBuilder_stepBuilder = __safeDI_apiBuilder.stepBuilder(SafeDIScope_Api.stepBuilder_Values(logger: logger))
		        func __safeDI_stepBuilder() -> Step {
		            let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder_stepBuilder.detailBuilder(SafeDIScope_Api.Step_Scope.detailBuilder_Values())
		            func __safeDI_detailBuilder() -> Detail {
		                let api: any Api = __safeDI_apiBuilder_detailBuilder.api(SafeDIScope_Api.Detail_Scope.api_Values())
		                return Detail(api: api)
		            }
		            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		            return Step(detailBuilder: detailBuilder)
		        }
		        let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		        self.init(logger: logger, stepBuilder: stepBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_10036056DB5D92A2 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_10036056DB5D92A2.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(stepBuilder: { values in __safeDI_apiBuilder_Home_Step_Scope(logger: values.logger) })
		            }
		            func __safeDI_apiBuilder_Home_Step_Scope(logger: Logger) -> Home.SafeDIScope_Api.Step_Scope.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { _ in __safeDI_apiBuilder_Home_Detail_Scope(logger: logger) })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(logger: logger)
		                    return api
		                })
		            }
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
		    nonisolated public enum SafeDIScope_Api {
		        nonisolated public struct detailBuilder_Values {
		            public let logger: Logger
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct api_Values {}

		            nonisolated public struct backupApi_Values {
		                public let api: any Api
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built
		                public let backupApi: (backupApi_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built, backupApi: @escaping (backupApi_Values) -> __safeDI_Built) {
		                    self.api = api
		                    self.backupApi = backupApi
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                    self.backupApi = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let logger = Logger()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIScope_Api.detailBuilder_Values(logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api(SafeDIScope_Api.Detail_Scope.api_Values())
		            let backupApi: any Api = __safeDI_apiBuilder_detailBuilder.backupApi(SafeDIScope_Api.Detail_Scope.backupApi_Values(api: api))
		            return Detail(api: api, backupApi: backupApi)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_BFA755DDE09710DE {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_BFA755DDE09710DE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(logger: values.logger) })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(
		                    api: { _ in
		                        let api: any Api = LiveApi(logger: logger)
		                        return api
		                    },
		                    backupApi: { _ in
		                        let backupApi: any Api = LiveApi(logger: logger)
		                        return backupApi
		                    }
		                )
		            }
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
		    nonisolated public enum SafeDIScope_Api {
		        nonisolated public enum Detail_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }
		    }

		    nonisolated public enum SafeDISendableScope_Api {
		        nonisolated public struct detailBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let detailBuilder: @Sendable (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping @Sendable (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
		        let logger = Logger()
		        @Sendable nonisolated func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiSendableBuilder_detailBuilder = __safeDI_apiSendableBuilder.detailBuilder(SafeDISendableScope_Api.detailBuilder_Values())
		            let api: any Api = __safeDI_apiSendableBuilder_detailBuilder.api(SafeDIScope_Api.Detail_Scope.api_Values())
		            return Detail(api: api)
		        }
		        let detailBuilder = SendableInstantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_29126001AA0F4296 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_29126001AA0F4296.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.SafeDISendableScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { _ in __safeDI_apiBuilder_Home_Detail_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope() -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
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
		    nonisolated public enum SafeDIScope_Api {
		        nonisolated public struct detailBuilder_Values {
		            public let logger: Logger
		            public let tracker: Tracker
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let logger = Logger()
		        let tracker = Tracker()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIScope_Api.detailBuilder_Values(logger: logger, tracker: tracker))
		        func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api(SafeDIScope_Api.Detail_Scope.api_Values())
		            return Detail(api: api)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder, tracker: tracker)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_A1C1C95F19438A07 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_A1C1C95F19438A07.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(logger: values.logger) })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(logger: logger)
		                    return api
		                })
		            }
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
		    nonisolated public enum SafeDIScope_Api {
		        nonisolated public struct detailBuilder_Values {
		            public let logger: Logger
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let logger = Logger()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIScope_Api.detailBuilder_Values(logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api(SafeDIScope_Api.Detail_Scope.api_Values())
		            return Detail(api: api)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_F48CB5381D875DB4 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_F48CB5381D875DB4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(logger: values.logger) })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(logger: logger)
		                    return api
		                })
		            }
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
		    nonisolated public enum SafeDIScope_Api {
		        nonisolated public struct detailBuilder_Values {
		            public let logger: Logger
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let logger = Logger()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIScope_Api.detailBuilder_Values(logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api(SafeDIScope_Api.Detail_Scope.api_Values())
		            return Detail(api: api)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        let watcher = Watcher(detailBuilder: detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder, watcher: watcher)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_F48CB5381D875DB4 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_F48CB5381D875DB4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(logger: values.logger) })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(logger: logger)
		                    return api
		                })
		            }
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
		    nonisolated public enum SafeDIScope_Api {
		        nonisolated public struct detailBuilder_Values {
		            public let logger: Logger
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let logger = Logger()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIScope_Api.detailBuilder_Values(logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api(SafeDIScope_Api.Detail_Scope.api_Values())
		            return Detail(api: api)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_F48CB5381D875DB4 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_F48CB5381D875DB4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(logger: values.logger) })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(logger: logger)
		                    return api
		                })
		            }
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
		    nonisolated public enum SafeDIScope_Api {
		        nonisolated public struct detailBuilder_Values {
		            public let logger: Logger
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let logger = Logger()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIScope_Api.detailBuilder_Values(logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api(SafeDIScope_Api.Detail_Scope.api_Values())
		            return Detail(api: api)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(logger: logger, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_F48CB5381D875DB4 {}
		}
		""")
		#expect(variant.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_F48CB5381D875DB4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(logger: values.logger) })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = OtherApi(logger: logger)
		                    return api
		                })
		            }
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
	    nonisolated public enum SafeDIScope_Api {
	        nonisolated public struct detailBuilder_Values {
	            public let logger: Logger
	        }

	        nonisolated public enum Detail_Scope {
	            nonisolated public struct api_Values {}

	            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	                public let api: (api_Values) -> __safeDI_Built

	                public init(api: @escaping (api_Values) -> __safeDI_Built) {
	                    self.api = api
	                }

	                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                    self.api = { _ in __safeDI_builder() }
	                }
	            }
	        }

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

	            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
	                self.detailBuilder = detailBuilder
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
	            }
	        }
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
	    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
	        let logger = Logger()
	        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIScope_Api.detailBuilder_Values(logger: logger))
	        func __safeDI_detailBuilder() -> Detail {
	            let api: any Api = __safeDI_apiBuilder_detailBuilder.api(SafeDIScope_Api.Detail_Scope.api_Values())
	            return Detail(api: api)
	        }
	        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
	        self.init(logger: logger, detailBuilder: detailBuilder)
	    }
	}

	extension Home {
	    public enum __safeDI_Home_F48CB5381D875DB4 {}
	}
	"""

	/// What `App` generates for `baseModules`.
	private static let baseAppOutput = generatedFileHeader + """
	#if canImport(Feature)
	import Feature
	#endif

	extension Root {
	    public convenience init() {
	        func __safeDI_home() -> Home {
	            _ = Home.__safeDI_Home_F48CB5381D875DB4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
	            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
	                .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(logger: values.logger) })
	            }
	            func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
	                .init(api: { _ in
	                    let api: any Api = LiveApi(logger: logger)
	                    return api
	                })
	            }
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
