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

/// A public mock whose own tree builds the mocked type again, inline, through an `Instantiator` of it, with a place beneath:
/// the case on the way back to the mocked type holds the mock's root enum, as a seam's case that builds the seam again holds
/// the seam's.
struct SafeDIToolPublicMockSelfRecursiveTests: ~Copyable {
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
	mutating func generate_holdsTheRootEnumInTheCaseThatBuildsTheMockedTypeAgain_whenPublicMockInstantiatesItself() async throws {
		try await expectOutput(
			of: Self.modules(feature: Self.featureOpeningItself),
			probes: [DifferentialValueProbe("FeatureScreen.mock().feature.next.instantiate().next.instantiate()")],
			expectedFeature: """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Feature {
			    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
			    @frozen public enum SafeDIMockScope_Api {
			        case service(service_Values)
			        indirect case next(next_Values, SafeDIMockScope_Api)

			        public struct service_Values {}

			        public struct next_Values {
			            public let service: any Api
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            next: __safeDI_Feature_Feature_MockConfiguration = .init()
			        ) {
			            self.next = next
			        }

			        public let next: __safeDI_Feature_Feature_MockConfiguration
			    }

			    public static func mock(
			        apiBuilder: @escaping (Feature.SafeDIMockScope_Api) -> any Api,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Feature {
			        let __safeDI_apiBuilder = apiBuilder
			        let service: any Api = __safeDI_apiBuilder(.service(SafeDIMockScope_Api.service_Values()))
			        let __safeDI_apiValues_next = SafeDIMockScope_Api.next_Values(service: service)
			        func __safeDI_next() -> Feature {
			            let service: any Api = __safeDI_apiBuilder(.next(__safeDI_apiValues_next, .service(SafeDIMockScope_Api.service_Values())))
			            let next = Instantiator<Feature>(__safeDI_next)
			            return Feature.__safeDI_init(service: service, next: next, safeDIBuilder: safeDIOverrides.next.safeDIBuilder)
			        }
			        let next = Instantiator<Feature>(__safeDI_next)
			        return Feature(service: service, next: next)
			    }
			}

			extension Feature {
			    public enum __safeDI_Feature_mock_DA0A926AB64C214F {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Feature` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Feature_MockConfiguration {
			    public init(
			        _ safeDIBuilder: ((any Api, Instantiator<Feature>) -> Feature)? = nil
			    ) {
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// Overrides how `Feature` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((any Api, Instantiator<Feature>) -> Feature)?
			}

			extension Feature {
			    static func __safeDI_init(service: any Api, next: Instantiator<Feature>, safeDIBuilder: ((any Api, Instantiator<Feature>) -> Feature)?) -> Feature {
			        if let safeDIBuilder { safeDIBuilder(service, next) } else { Feature(service: service, next: next) }
			    }
			}
			#endif

			""",
			expectedApp: """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension FeatureScreen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            feature: Feature.SafeDIOverrides = .init()
			        ) {
			            self.feature = feature
			        }

			        let feature: Feature.SafeDIOverrides
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> FeatureScreen {
			        func __safeDI_feature() -> Feature {
			            func __safeDI_apiBuilder_Feature(_ scope: Feature.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case .service:
			                    let service: any Api = LiveApi()
			                    return service
			                case let .next(_, scope): return __safeDI_apiBuilder_Feature(scope)
			                }
			            }
			            _ = Feature.__safeDI_Feature_mock_DA0A926AB64C214F.self\(Self.featureCallComment)
			            return Feature.mock(apiBuilder: __safeDI_apiBuilder_Feature, safeDIOverrides: safeDIOverrides.feature)
			        }
			        let feature: Feature = __safeDI_feature()
			        return FeatureScreen(feature: feature)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsTheRootEnumInTheCaseThatBuildsTheMockedTypeAgain_whenATypeThePublicMockBuildsInstantiatesTheMockedType() async throws {
		try await expectOutput(
			of: Self.modules(feature: Self.featureOpeningAStepThatOpensIt),
			probes: [DifferentialValueProbe("FeatureScreen.mock().feature.step.featureBuilder.instantiate().step.featureBuilder.instantiate()")],
			expectedFeature: """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Feature {
			    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
			    @frozen public enum SafeDIMockScope_Api {
			        case service(service_Values)
			        indirect case step(step_Values, SafeDIMockScope_Api.Step_Scope)

			        public struct service_Values {}

			        public struct step_Values {
			            public let service: any Api
			        }

			        @frozen public enum Step_Scope {
			            indirect case featureBuilder(featureBuilder_Values, SafeDIMockScope_Api)

			            public struct featureBuilder_Values {}
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            step: __safeDI_Feature_Step_MockConfiguration = .init()
			        ) {
			            self.step = step
			        }

			        public let step: __safeDI_Feature_Step_MockConfiguration
			    }

			    public static func mock(
			        apiBuilder: @escaping (Feature.SafeDIMockScope_Api) -> any Api,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Feature {
			        let __safeDI_apiBuilder = apiBuilder
			        let service: any Api = __safeDI_apiBuilder(.service(SafeDIMockScope_Api.service_Values()))
			        let __safeDI_apiValues_step = SafeDIMockScope_Api.step_Values(service: service)
			        func __safeDI_step() -> Step {
			            let __safeDI_apiValues_featureBuilder = SafeDIMockScope_Api.Step_Scope.featureBuilder_Values()
			            func __safeDI_featureBuilder() -> Feature {
			                let service: any Api = __safeDI_apiBuilder(.step(__safeDI_apiValues_step, .featureBuilder(__safeDI_apiValues_featureBuilder, .service(SafeDIMockScope_Api.service_Values()))))
			                let step: Step = __safeDI_step()
			                return Feature.__safeDI_init(service: service, step: step, safeDIBuilder: nil)
			            }
			            let featureBuilder = Instantiator<Feature>(__safeDI_featureBuilder)
			            return Step.__safeDI_init(featureBuilder: featureBuilder, safeDIBuilder: safeDIOverrides.step.safeDIBuilder)
			        }
			        let step: Step = __safeDI_step()
			        return Feature(service: service, step: step)
			    }
			}

			extension Feature {
			    public enum __safeDI_Feature_mock_5E9967E7AEA6037D {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Feature` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Feature_MockConfiguration {
			    public init(
			        step: __safeDI_Feature_Step_MockConfiguration = .init(),
			        _ safeDIBuilder: ((any Api, Step) -> Feature)? = nil
			    ) {
			        self.step = step
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public let step: __safeDI_Feature_Step_MockConfiguration
			    /// Overrides how `Feature` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((any Api, Step) -> Feature)?
			}

			extension Feature {
			    static func __safeDI_init(service: any Api, step: Step, safeDIBuilder: ((any Api, Step) -> Feature)?) -> Feature {
			        if let safeDIBuilder { safeDIBuilder(service, step) } else { Feature(service: service, step: step) }
			    }
			}

			/// Configuration for how `Step` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Step_MockConfiguration {
			    public init(
			        _ safeDIBuilder: ((Instantiator<Feature>) -> Step)? = nil
			    ) {
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// Overrides how `Step` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Instantiator<Feature>) -> Step)?
			}

			extension Step {
			    static func __safeDI_init(featureBuilder: Instantiator<Feature>, safeDIBuilder: ((Instantiator<Feature>) -> Step)?) -> Step {
			        if let safeDIBuilder { safeDIBuilder(featureBuilder) } else { Step(featureBuilder: featureBuilder) }
			    }
			}
			#endif

			""",
			expectedApp: """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension FeatureScreen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            feature: Feature.SafeDIOverrides = .init()
			        ) {
			            self.feature = feature
			        }

			        let feature: Feature.SafeDIOverrides
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> FeatureScreen {
			        func __safeDI_feature() -> Feature {
			            func __safeDI_apiBuilder_Feature(_ scope: Feature.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case .service:
			                    let service: any Api = LiveApi()
			                    return service
			                case let .step(_, scope): return __safeDI_apiBuilder_Feature_Step_Scope(scope)
			                }
			            }
			            func __safeDI_apiBuilder_Feature_Step_Scope(_ scope: Feature.SafeDIMockScope_Api.Step_Scope) -> any Api {
			                switch scope {
			                case let .featureBuilder(_, scope): return __safeDI_apiBuilder_Feature(scope)
			                }
			            }
			            _ = Feature.__safeDI_Feature_mock_5E9967E7AEA6037D.self\(Self.featureCallComment)
			            return Feature.mock(apiBuilder: __safeDI_apiBuilder_Feature, safeDIOverrides: safeDIOverrides.feature)
			        }
			        let feature: Feature = __safeDI_feature()
			        return FeatureScreen(feature: feature)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsEachRootEnumInTheCasesThatBuildTheMockedTypeAgain_whenPublicMockInstantiatesItselfInSendableFunction() async throws {
		try await expectOutput(
			of: Self.modules(feature: Self.featureOpeningItselfInSendableFunction, api: Self.sendableApi),
			probes: [DifferentialValueProbe("FeatureScreen.mock().feature.next.instantiate().next.instantiate()")],
			expectedFeature: """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Feature {
			    @frozen public enum SafeDIMockScope_Api {
			        case service(service_Values)

			        public struct service_Values {}
			    }

			    @frozen public enum SafeDISendableMockScope_Api {
			        case next(SafeDIMockScope_Api)
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            next: __safeDI_Feature_Feature_MockConfiguration = .init()
			        ) {
			            self.next = next
			        }

			        public let next: __safeDI_Feature_Feature_MockConfiguration
			    }

			    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
			    public static func mock(
			        apiBuilder: @escaping (Feature.SafeDIMockScope_Api) -> any Api,
			        apiSendableBuilder: @escaping @Sendable (Feature.SafeDISendableMockScope_Api) -> any Api,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Feature {
			        let __safeDI_apiBuilder = apiBuilder
			        let __safeDI_apiSendableBuilder = apiSendableBuilder
			        let service: any Api = __safeDI_apiBuilder(.service(SafeDIMockScope_Api.service_Values()))
			        let __safeDI_next__safeDIBuilder = safeDIOverrides.next.safeDIBuilder
			        @Sendable func __safeDI_next() -> Feature {
			            let service: any Api = __safeDI_apiSendableBuilder(.next(.service(SafeDIMockScope_Api.service_Values())))
			            let next = SendableInstantiator<Feature>(__safeDI_next)
			            return Feature.__safeDI_init(service: service, next: next, safeDIBuilder: __safeDI_next__safeDIBuilder)
			        }
			        let next = SendableInstantiator<Feature>(__safeDI_next)
			        return Feature(service: service, next: next)
			    }
			}

			extension Feature {
			    public enum __safeDI_Feature_mock_5234A20B60065AF6 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Feature` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Feature_MockConfiguration {
			    public init(
			        _ safeDIBuilder: (@Sendable (any Api, SendableInstantiator<Feature>) -> Feature)? = nil
			    ) {
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// Overrides how `Feature` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: (@Sendable (any Api, SendableInstantiator<Feature>) -> Feature)?
			}

			extension Feature {
			    static func __safeDI_init(service: any Api, next: SendableInstantiator<Feature>, safeDIBuilder: (@Sendable (any Api, SendableInstantiator<Feature>) -> Feature)?) -> Feature {
			        if let safeDIBuilder { safeDIBuilder(service, next) } else { Feature(service: service, next: next) }
			    }
			}
			#endif

			""",
			expectedApp: """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension FeatureScreen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            feature: Feature.SafeDIOverrides = .init()
			        ) {
			            self.feature = feature
			        }

			        let feature: Feature.SafeDIOverrides
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> FeatureScreen {
			        func __safeDI_feature() -> Feature {
			            @Sendable func __safeDI_apiBuilder_Feature(_ scope: Feature.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case .service:
			                    let service: any Api = LiveApi()
			                    return service
			                }
			            }
			            @Sendable func __safeDI_apiSendableBuilder_Feature(_ scope: Feature.SafeDISendableMockScope_Api) -> any Api {
			                switch scope {
			                case let .next(scope): return __safeDI_apiBuilder_Feature(scope)
			                }
			            }
			            _ = Feature.__safeDI_Feature_mock_5234A20B60065AF6.self\(Self.featureCallComment)
			            return Feature.mock(apiBuilder: __safeDI_apiBuilder_Feature, apiSendableBuilder: __safeDI_apiSendableBuilder_Feature, safeDIOverrides: safeDIOverrides.feature)
			        }
			        let feature: Feature = __safeDI_feature()
			        return FeatureScreen(feature: feature)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEachBuildOfTheMockedTypeWithThatBuildsValues_whenPublicMockInstantiatesItself() async throws {
		try await expectOutput(
			of: Self.modules(feature: Self.featureBindingATokenAndOpeningItself, api: Self.apiAndToken, liveApi: Self.liveApiReceivingAToken),
			probes: [DifferentialValueProbe("FeatureScreen.mock().feature.next.instantiate().next.instantiate()")],
			expectedFeature: """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Feature {
			    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
			    @frozen public enum SafeDIMockScope_Api {
			        case service(service_Values)
			        indirect case next(next_Values, SafeDIMockScope_Api)

			        public struct service_Values {
			            public let token: Token
			        }

			        public struct next_Values {
			            public let token: Token
			            public let service: any Api
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            token: (() -> Token)? = nil,
			            next: __safeDI_Feature_Feature_MockConfiguration = .init()
			        ) {
			            self.token = token
			            self.next = next
			        }

			        public let token: (() -> Token)?
			        public let next: __safeDI_Feature_Feature_MockConfiguration
			    }

			    public static func mock(
			        apiBuilder: @escaping (Feature.SafeDIMockScope_Api) -> any Api,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Feature {
			        let __safeDI_apiBuilder = apiBuilder
			        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
			        let service: any Api = __safeDI_apiBuilder(.service(SafeDIMockScope_Api.service_Values(token: token)))
			        let __safeDI_apiValues_next = SafeDIMockScope_Api.next_Values(token: token, service: service)
			        func __safeDI_next() -> Feature {
			            let token = if let safeDIBuilder = safeDIOverrides.next.token { safeDIBuilder() } else { Token() }
			            let service: any Api = __safeDI_apiBuilder(.next(__safeDI_apiValues_next, .service(SafeDIMockScope_Api.service_Values(token: token))))
			            let next = Instantiator<Feature>(__safeDI_next)
			            return Feature.__safeDI_init(token: token, service: service, next: next, safeDIBuilder: safeDIOverrides.next.safeDIBuilder)
			        }
			        let next = Instantiator<Feature>(__safeDI_next)
			        return Feature(token: token, service: service, next: next)
			    }
			}

			extension Feature {
			    public enum __safeDI_Feature_mock_F1CA998906409999 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Feature` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Feature_MockConfiguration {
			    public init(
			        token: (() -> Token)? = nil,
			        _ safeDIBuilder: ((Token, any Api, Instantiator<Feature>) -> Feature)? = nil
			    ) {
			        self.token = token
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public let token: (() -> Token)?
			    /// Overrides how `Feature` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Token, any Api, Instantiator<Feature>) -> Feature)?
			}

			extension Feature {
			    static func __safeDI_init(token: Token, service: any Api, next: Instantiator<Feature>, safeDIBuilder: ((Token, any Api, Instantiator<Feature>) -> Feature)?) -> Feature {
			        if let safeDIBuilder { safeDIBuilder(token, service, next) } else { Feature(token: token, service: service, next: next) }
			    }
			}
			#endif

			""",
			expectedApp: """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension FeatureScreen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            feature: Feature.SafeDIOverrides = .init()
			        ) {
			            self.feature = feature
			        }

			        let feature: Feature.SafeDIOverrides
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> FeatureScreen {
			        func __safeDI_feature() -> Feature {
			            func __safeDI_apiBuilder_Feature(_ scope: Feature.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case let .service(scope):
			                    let token = scope.token
			                    let service: any Api = LiveApi(token: token)
			                    return service
			                case let .next(_, scope): return __safeDI_apiBuilder_Feature(scope)
			                }
			            }
			            _ = Feature.__safeDI_Feature_mock_F1CA998906409999.self\(Self.featureCallComment)
			            return Feature.mock(apiBuilder: __safeDI_apiBuilder_Feature, safeDIOverrides: safeDIOverrides.feature)
			        }
			        let feature: Feature = __safeDI_feature()
			        return FeatureScreen(feature: feature)
			    }
			}
			#endif
			""",
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The comment a generated call of `Feature`'s public mock carries.
	private static let featureCallComment = MultiModuleIntegration.moduleInfo.seamCallComment(type: "Feature", declaringModule: "Feature")

	/// Expects `Feature`'s and `App`'s generated files to be exactly `expectedFeature` and `expectedApp`, each after the file
	/// header, every module to compile, and `App`'s mock to build, for each of `probes`, the values the same graph's mock
	/// builds inline: every declaration in one module, every public mock internal.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectOutput(
		of modules: [ModuleFixture],
		probes: [DifferentialValueProbe],
		expectedFeature: String,
		expectedApp: String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		for (module, expected) in [("Feature", expectedFeature), ("App", expectedApp)] {
			let generated = output.modules[module]?.generatedFiles["\(module).swift"]
			#expect(generated == generatedFileHeader + expected, sourceLocation: sourceLocation)
			if let generated, generated != generatedFileHeader + expected {
				Issue.record(Comment(rawValue: "=== \(module).swift\n" + generated.dropFirst(generatedFileHeader.count)), sourceLocation: sourceLocation)
			}
		}
		guard compileVerificationIsEnabled else { return }
		let inlineModules = [ModuleFixture(
			name: "Feature",
			packageName: "feature",
			swiftFileContent: modules.flatMap(\.swiftFileContent).map {
				$0.replacingOccurrences(of: "import Core\n", with: "")
					.replacingOccurrences(of: "import Feature\n", with: "")
					.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")
			},
		)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// `Core`, which declares the hole's protocol, `api`; `Feature`, which declares the public mock in `feature`; and `App`,
	/// another package, whose `FeatureScreen` mock calls it and whose `LiveApi` fills every place of it.
	private static func modules(feature: String, api: String = api, liveApi: String = liveApi) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "core", swiftFileContent: [api]),
			ModuleFixture(name: "Feature", packageName: "feature", swiftFileContent: [feature], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [featureScreen, liveApi], dependencies: ["Core", "Feature"]),
		]
	}

	private static let api = """
	public protocol Api {}
	"""

	/// A public mock that builds itself again through `next`, with a place, `service`, nothing in `Feature` fulfills.
	private static let featureOpeningItself = """
	import Core
	import SafeDI

	@Instantiable(generateMock: .public)
	public final class Feature: Instantiable {
	    init(service: any Api, next: Instantiator<Feature>) {
	        self.service = service
	        self.next = next
	    }

	    @Instantiated let service: any Api
	    @Instantiated let next: Instantiator<Feature>
	}
	"""

	/// `api`, its protocol `Sendable`, so that a `Sendable` type can hold an `Api`.
	private static let sendableApi = """
	public protocol Api: Sendable {}
	"""

	/// `featureOpeningItself`, building itself again inside the `@Sendable` function of a `SendableInstantiator`.
	private static let featureOpeningItselfInSendableFunction = """
	import Core
	import SafeDI

	@Instantiable(generateMock: .public)
	public final class Feature: Instantiable, Sendable {
	    init(service: any Api, next: SendableInstantiator<Feature>) {
	        self.service = service
	        self.next = next
	    }

	    @Instantiated let service: any Api
	    @Instantiated let next: SendableInstantiator<Feature>
	}
	"""

	/// A public mock with a place, `service`, that builds a `Step` whose `featureBuilder` builds the mocked type again.
	private static let featureOpeningAStepThatOpensIt = """
	import Core
	import SafeDI

	@Instantiable
	public final class Step: Instantiable {
	    init(featureBuilder: Instantiator<Feature>) {
	        self.featureBuilder = featureBuilder
	    }

	    @Instantiated let featureBuilder: Instantiator<Feature>
	}

	@Instantiable(generateMock: .public)
	public final class Feature: Instantiable {
	    init(service: any Api, step: Step) {
	        self.service = service
	        self.step = step
	    }

	    @Instantiated let service: any Api
	    @Instantiated let step: Step
	}
	"""

	/// `api`, and a `Token`, a class, so that two builds of it differ by identity.
	private static let apiAndToken = """
	import SafeDI

	public protocol Api {}

	@Instantiable
	public final class Token: Instantiable {
	    public init() {}
	}
	"""

	/// `featureOpeningItself`, binding a `Token` of its own before its place, which reads it.
	private static let featureBindingATokenAndOpeningItself = """
	import Core
	import SafeDI

	@Instantiable(generateMock: .public)
	public final class Feature: Instantiable {
	    init(token: Token, service: any Api, next: Instantiator<Feature>) {
	        self.token = token
	        self.service = service
	        self.next = next
	    }

	    @Instantiated let token: Token
	    @Instantiated let service: any Api
	    @Instantiated let next: Instantiator<Feature>
	}
	"""

	/// A type in `App` whose mock calls `Feature`'s public mock.
	private static let featureScreen = """
	import Core
	import Feature
	import SafeDI

	@Instantiable(generateMock: true)
	public struct FeatureScreen: Instantiable {
	    public init(feature: Feature) {
	        self.feature = feature
	    }

	    @Instantiated let feature: Feature
	}
	"""

	/// `App`'s fulfiller of `Api`, which fills every place of `Feature`'s mock.
	private static let liveApi = """
	import Core
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public struct LiveApi: Api, Instantiable {
	    public init() {}
	}
	"""

	/// `liveApi`, receiving the `Token` of the build of `Feature` whose place it fills, which it stores.
	private static let liveApiReceivingAToken = """
	import Core
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public struct LiveApi: Api, Instantiable {
	    public init(token: Token) {
	        self.token = token
	    }

	    @Received let token: Token
	}
	"""
}
