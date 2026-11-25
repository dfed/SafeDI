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

/// A module that calls another module’s public mock and passes a place up hands what it passes up as the builder a
/// person writes, `() -> T`, or the member of its own builder struct, and decides when generating which places it fills:
/// no closure written by a person is handed a generated scope, and nothing a caller passes up holds a level’s values.
struct SafeDIToolPublicMockStaticCallTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – a place passed up beneath a level that reopens

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderThatTakesNothing_whenCallersPassUpPlaceBeneathLevelThatReopens() async throws {
		// `Shell`, a public mock in `Mid`, builds `Home` and passes its only place up, and `Root` passes it up again. `Screen`
		// reopens beneath `Step`. Neither `Root.mock` nor `Shell.mock` takes a type that names a scope, so a written closure
		// can read no level’s values, and `Shell` hands `Home` the member of its own struct.
		let modules = Self.screenLoopModules(mid: [Self.shell], app: [Self.root(holding: "shell: Shell")])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader])
		#expect(output.modules["Feat"]?.generatedFiles == ["Feat.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Home {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct screen_Values {}

		        nonisolated public enum Screen_Scope {
		            nonisolated public struct stepBuilder_Values {
		                public let cache: Cache
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let stepBuilder: (stepBuilder_Values) -> SafeDIMockScope_Api.Step_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(stepBuilder: @escaping (stepBuilder_Values) -> SafeDIMockScope_Api.Step_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.stepBuilder = stepBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(stepBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Step_Scope {
		            nonisolated public struct api_Values {
		                public let screenBuilder: Instantiator<Screen>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (api_Values) -> __safeDI_Built

		                public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let screen: (screen_Values) -> SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(screen: @escaping (screen_Values) -> SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.screen = screen
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(screen: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            screen: __safeDI_Feat_Screen_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        public var screen: __safeDI_Feat_Screen_MockConfiguration { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: __safeDI_Feat_Screen_MockConfiguration
		            ) {
		                self.screen = screen
		            }

		            let screen: __safeDI_Feat_Screen_MockConfiguration
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        Home.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Home.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        let __safeDI_apiBuilder_screen = __safeDI_apiBuilder.screen(SafeDIMockScope_Api.screen_Values())
		        func __safeDI_screen() -> Screen {
		            let cache = if let safeDIBuilder = safeDIOverrides.screen.cache { safeDIBuilder() } else { Cache() }
		            let __safeDI_apiBuilder_stepBuilder = __safeDI_apiBuilder_screen.stepBuilder(SafeDIMockScope_Api.Screen_Scope.stepBuilder_Values(cache: cache))
		            func __safeDI_stepBuilder() -> Step {
		                func __safeDI_screenBuilder() -> Screen {
		                    let cache = if let safeDIBuilder = safeDIOverrides.screen.cache { safeDIBuilder() } else { Cache() }
		                    let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		                    return Screen.__safeDI_init(cache: cache, stepBuilder: stepBuilder, safeDIBuilder: safeDIOverrides.screen.safeDIBuilder)
		                }
		                let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                let api: any Api = __safeDI_apiBuilder_stepBuilder.api(SafeDIMockScope_Api.Step_Scope.api_Values(screenBuilder: screenBuilder))
		                return Step.__safeDI_init(api: api, screenBuilder: screenBuilder, safeDIBuilder: safeDIOverrides.screen.stepBuilder.safeDIBuilder)
		            }
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            return Screen.__safeDI_init(cache: cache, stepBuilder: stepBuilder, safeDIBuilder: safeDIOverrides.screen.safeDIBuilder)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_mock_4EAD08687C9164E8 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Step` is constructed within the public mock trees of module `Feat`.
		nonisolated public struct __safeDI_Feat_Step_MockConfiguration {
		    public init(
		        _ safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    /// Overrides how `Step` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)?
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)?
		    }
		}

		extension Step {
		    static func __safeDI_init(api: any Api, screenBuilder: Instantiator<Screen>, safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)?) -> Step {
		        if let safeDIBuilder { safeDIBuilder(api, screenBuilder) } else { Step(api: api, screenBuilder: screenBuilder) }
		    }
		}

		/// Configuration for how `Screen` is constructed within the public mock trees of module `Feat`.
		nonisolated public struct __safeDI_Feat_Screen_MockConfiguration {
		    public init(
		        cache: (() -> Cache)? = nil,
		        stepBuilder: __safeDI_Feat_Step_MockConfiguration = .init(),
		        _ safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            cache: cache,
		            stepBuilder: stepBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var cache: (() -> Cache)? { __safeDI_storage.cache }
		    public var stepBuilder: __safeDI_Feat_Step_MockConfiguration { __safeDI_storage.stepBuilder }
		    /// Overrides how `Screen` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            cache: (() -> Cache)?,
		            stepBuilder: __safeDI_Feat_Step_MockConfiguration,
		            safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)?
		        ) {
		            self.cache = cache
		            self.stepBuilder = stepBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let cache: (() -> Cache)?
		        let stepBuilder: __safeDI_Feat_Step_MockConfiguration
		        let safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)?
		    }
		}

		extension Screen {
		    static func __safeDI_init(cache: Cache, stepBuilder: Instantiator<Step>, safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)?) -> Screen {
		        if let safeDIBuilder { safeDIBuilder(cache, stepBuilder) } else { Screen(cache: cache, stepBuilder: stepBuilder) }
		    }
		}
		#endif

		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Shell {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct home_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let home: (home_Values) -> Home.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

		            public init(home: @escaping (home_Values) -> Home.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
		                self.home = home
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(home: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            home: Home.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                home: home
		            )
		        }

		        public var home: Home.SafeDIOverrides { __safeDI_storage.home }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                home: Home.SafeDIOverrides
		            ) {
		                self.home = home
		            }

		            let home: Home.SafeDIOverrides
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shell {
		        Shell.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Shell.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shell {
		        _ = Home.__safeDI_Home_mock_4EAD08687C9164E8.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let home = Home.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.home(SafeDIMockScope_Api.home_Values()), safeDIOverrides: safeDIOverrides.home)
		        return Shell(home: home)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_mock_BCE44FADDA8E6FCF {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(Mid)
		import Mid
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            shell: Shell.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                shell: shell
		            )
		        }

		        var shell: Shell.SafeDIOverrides { __safeDI_storage.shell }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                shell: Shell.SafeDIOverrides
		            ) {
		                self.shell = shell
		            }

		            let shell: Shell.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_apiBuilder = apiBuilder
		        _ = Shell.__safeDI_Shell_mock_BCE44FADDA8E6FCF.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_shell() -> Shell {
		            let apiBuilder: () -> any Api = __safeDI_apiBuilder
		            return Shell.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides.shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        return Root(shell: shell)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsWrittenBuilderOncePerStep_whenCallersPassUpPlaceBeneathLevelThatReopens() async throws {
		// Each of three steps, each in the screen the last one opens, gets its own `Api` from one call of the written builder,
		// as the same declarations built in one module give it. No step’s value is asserted beyond that: each opening of a
		// reopened level getting its own values is later work.
		let modules = Self.screenLoopModules(mid: [Self.shell], app: [Self.root(holding: "shell: Shell"), Self.stubApi, Self.stepsEachHoldTheirOwnApi(home: "Root.mock(apiBuilder: builder).shell.home")])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let probe = DifferentialValueProbe("stepsEachHoldTheirOwnApi()")
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
		let knownRight = try await knownRightDescription(of: modules, keeping: ["Core", "Feat", "Mid"], probeSource: Self.stubApi + "\n\n" + Self.stepsEachHoldTheirOwnApi(home: "Shell.mock(apiBuilder: builder).home"), probe: probe)
		if compileVerificationIsEnabled {
			#expect(knownRight == "probe stepsEachHoldTheirOwnApi()\nString \"builder runs 3, each step its own api true\"\n")
			#expect(feature == knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsNoCacheOfFirstScreen_whenCallersPassUpPlaceBeneathLevelThatReopens() async throws {
		// Holding only the step of the second screen keeps no cache alive, as the same declarations built in one module keep
		// none: the builder `Root` passes up holds no level’s values. Before, the closure over the enum held the first
		// screen’s values, and with them its cache.
		let modules = Self.screenLoopModules(mid: [Self.shell], app: [Self.root(holding: "shell: Shell"), Self.stubApi, Self.cachesWhileSecondStepLives(home: "Root.mock(apiBuilder: { StubApi() }).shell.home")])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let probe = DifferentialValueProbe("cachesWhileSecondStepLives()")
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
		let knownRight = try await knownRightDescription(of: modules, keeping: ["Core", "Feat", "Mid"], probeSource: Self.stubApi + "\n\n" + Self.cachesWhileSecondStepLives(home: "Shell.mock(apiBuilder: { StubApi() }).home"), probe: probe)
		if compileVerificationIsEnabled {
			#expect(knownRight == "probe cachesWhileSecondStepLives()\nString \"Cache 0\"\n")
			#expect(feature == knownRight)
		}
	}

	// MARK: Tests – a caller that fills one place on two routes

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_freesWhatKnownRightFrees_whenPublicCallerFillsEachRouteWithItsNearestToken() async throws {
		// `Shell`, a public mock in `Mid`, fills the route through `Page`, which binds `token`, with `Page`’s `token`, and the
		// route beside `Page` with the `token` its mock takes, which `Root` builds. Everything the probe built is freed when it
		// drops it, as when the same declarations are built in one module.
		let modules = Self.chainModules(app: [Self.root(holding: "shell: Shell"), Self.aliveAfterUse(hub: "Root.mock().shell.hub")])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let probe = DifferentialValueProbe("aliveAfterUse()")
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
		let knownRight = try await knownRightDescription(of: modules, keeping: ["Core", "Feed", "Mid"], probeSource: Self.root(holding: "shell: Shell") + "\n\n" + Self.aliveAfterUse(hub: "Root.mock().shell.hub"), probe: probe)
		if compileVerificationIsEnabled {
			#expect(knownRight == "probe aliveAfterUse()\nString \"\"\n")
			#expect(feature == knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_freesEverythingItBuilt_whenPublicCallerFillsThePlaceItsCallersModuleCouldFillToo() async throws {
		// `Shell` fills both routes with `LiveToken`, which `Mid` sees, as its production twin does, though `App` sees `AppApi`,
		// which receives `Hub`’s navigator. Everything the probe built is freed when it drops it. No one-module build of these
		// declarations exists: `LiveToken` and `AppApi` both fulfill `Api`.
		let modules = Self.chainModules(app: [Self.appApi, Self.root(holding: "shell: Shell"), Self.aliveAfterUse(hub: "Root.mock().shell.hub", pushesModelBesidePage: false)])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("aliveAfterUse()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			#expect(feature == "probe aliveAfterUse()\nString \"\"\n")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_freesWhatKnownRightFrees_whenPublicCallerFillsEachRouteOfPlaceBuiltInSendableFunction() async throws {
		// `Hub` builds `Page` and `Model` in `SendableInstantiator`s, so its builder and `Shell`’s are of the `@Sendable`
		// family; `Shell` fills the route through `Page` with `Page`’s `token`, and the other with the `token` its mock takes,
		// which its `@Sendable` builder function captures. Everything the probe built is freed when it drops it, as when the
		// same declarations are built in one module.
		let modules = Self.chainModules(sendable: true, app: [Self.root(holding: "shell: Shell"), Self.aliveAfterUse(hub: "Root.mock().shell.hub")])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let probe = DifferentialValueProbe("aliveAfterUse()")
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
		let knownRight = try await knownRightDescription(of: modules, keeping: ["Core", "Feed", "Mid"], probeSource: Self.root(holding: "shell: Shell") + "\n\n" + Self.aliveAfterUse(hub: "Root.mock().shell.hub"), probe: probe)
		if compileVerificationIsEnabled {
			#expect(knownRight == "probe aliveAfterUse()\nString \"\"\n")
			#expect(feature == knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_freesWhatKnownRightFrees_whenPublicMockCallsPublicCallerThatFillsEachRoute() async throws {
		// `Outer`, a public mock in `Top`, builds `Shell`, which fills both routes, and hands it the `token` its own mock takes,
		// which `Root` builds. Everything the probe built is freed when it drops it, as when the same declarations are built in
		// one module.
		let modules = Self.chainModules(outer: true, app: [Self.root(holding: "outer: Outer"), Self.aliveAfterUse(hub: "Root.mock().outer.shell.hub")])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let probe = DifferentialValueProbe("aliveAfterUse()")
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
		let knownRight = try await knownRightDescription(of: modules, keeping: ["Core", "Feed", "Mid", "Top"], probeSource: Self.root(holding: "outer: Outer") + "\n\n" + Self.aliveAfterUse(hub: "Root.mock().outer.shell.hub"), probe: probe)
		if compileVerificationIsEnabled {
			#expect(knownRight == "probe aliveAfterUse()\nString \"\"\n")
			#expect(feature == knownRight)
		}
	}

	// MARK: Tests – a fill of a place a calling public mock passes up

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsPassingUpMocksValue_whenFillOfPlaceItPassesUpReceivesValueItHandsOn() async throws {
		// `Outer`, a public mock in `Feature`, builds `logger` and calls `Inner`’s public mock in `Up`, whose `Detail` receives
		// `logger` and holds the place, which `Outer` passes up. `Root`’s fill `LiveApi` receives `logger`: its level function
		// reads it from the values of `Inner`’s level, which hold `Outer`’s.
		let modules = [
			ModuleFixture(name: "Up", packageName: "Up", swiftFileContent: [
				"""
				import SafeDI

				public protocol Api: AnyObject {}

				@Instantiable
				public final class Logger: Instantiable { public init() {} }

				@Instantiable
				public final class Detail: Instantiable {
				    init(logger: Logger, api: any Api) { self.logger = logger; self.api = api }
				    @Received public let logger: Logger
				    @Instantiated public let api: any Api
				}

				@Instantiable(generateMock: .public)
				public final class Inner: Instantiable {
				    init(detail: Detail) { self.detail = detail }
				    @Instantiated public let detail: Detail
				}
				""",
			]),
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				"""
				import SafeDI
				import Up

				@Instantiable(generateMock: .public)
				public final class Outer: Instantiable {
				    init(logger: Logger, inner: Inner) { self.logger = logger; self.inner = inner }
				    @Instantiated public let logger: Logger
				    @Instantiated public let inner: Inner
				}
				""",
			], dependencies: ["Up"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
				"""
				import SafeDI
				import Up
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public final class LiveApi: Instantiable, Api {
				    public init(logger: Logger) { self.logger = logger }
				    @Received public let logger: Logger
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(outer: Outer) { self.outer = outer }
				    @Instantiated public let outer: Outer
				}
				""",
			], dependencies: ["Up", "Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Up"]?.generatedFiles == ["Up.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Inner {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct detail_Values {
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
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detail: (detail_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detail: @escaping (detail_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detail = detail
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(detail: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            logger: (() -> Logger)? = nil,
		            detail: ((Logger, any Api) -> Detail)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                detail: detail
		            )
		        }

		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var detail: ((Logger, any Api) -> Detail)? { __safeDI_storage.detail }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                detail: ((Logger, any Api) -> Detail)?
		            ) {
		                self.logger = logger
		                self.detail = detail
		            }

		            let logger: (() -> Logger)?
		            let detail: ((Logger, any Api) -> Detail)?
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        logger: Logger? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        Inner.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), logger: logger, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Inner.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        logger: Logger? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        let logger = if let logger { logger } else if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        let __safeDI_apiBuilder_detail = __safeDI_apiBuilder.detail(SafeDIMockScope_Api.detail_Values(logger: logger))
		        func __safeDI_detail() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detail.api(SafeDIMockScope_Api.Detail_Scope.api_Values())
		            return if let safeDIBuilder = safeDIOverrides.detail { safeDIBuilder(logger, api) } else { Detail(logger: logger, api: api) }
		        }
		        let detail: Detail = __safeDI_detail()
		        return Inner(detail: detail)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_mock_BAE1F41FF7753381 {}
		}
		#endif
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Up)
		import Up
		#endif

		#if DEBUG
		extension Outer {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct inner_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner: (inner_Values) -> Inner.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

		            public init(inner: @escaping (inner_Values) -> Inner.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
		                self.inner = inner
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(inner: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            logger: (() -> Logger)? = nil,
		            inner: Inner.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                inner: inner
		            )
		        }

		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                inner: Inner.SafeDIOverrides
		            ) {
		                self.logger = logger
		                self.inner = inner
		            }

		            let logger: (() -> Logger)?
		            let inner: Inner.SafeDIOverrides
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        Outer.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Outer.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        _ = Inner.__safeDI_Inner_mock_BAE1F41FF7753381.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let inner = Inner.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.inner(SafeDIMockScope_Api.inner_Values()), logger: logger, safeDIOverrides: safeDIOverrides.inner)
		        return Outer(logger: logger, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_mock_FF10A81DEF4A07EE {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Up)
		import Up
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            outer: Outer.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                outer: outer
		            )
		        }

		        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                outer: Outer.SafeDIOverrides
		            ) {
		                self.outer = outer
		            }

		            let outer: Outer.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_outer() -> Outer {
		            func __safeDI_apiBuilder_Outer() -> Outer.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(inner: { _ in __safeDI_apiBuilder_Inner() })
		            }
		            func __safeDI_apiBuilder_Inner() -> Inner.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(detail: { values in __safeDI_apiBuilder_Inner_Detail_Scope(logger: values.logger) })
		            }
		            func __safeDI_apiBuilder_Inner_Detail_Scope(logger: Logger) -> Inner.SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(logger: logger)
		                    return api
		                })
		            }
		            _ = Outer.__safeDI_Outer_mock_FF10A81DEF4A07EE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Outer(), safeDIOverrides: safeDIOverrides.outer)
		        }
		        let outer: Outer = __safeDI_outer()
		        return Root(outer: outer)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsKnownRightValues_whenCallerDeclaresValueFillReadsAndPassingUpMockDeclaresItToo() async throws {
		// `Root` declares its own `logger` beside `Outer`’s; `LiveApi` gets `Outer`’s, as in the same declarations built in one
		// module.
		let modules = [
			ModuleFixture(name: "Up", packageName: "Up", swiftFileContent: [
				"""
				import SafeDI

				public protocol Api: AnyObject {}

				public enum Stamp {
				    nonisolated(unsafe) private static var lastStamp = 0

				    public static func next() -> Int {
				        lastStamp += 1
				        return lastStamp
				    }
				}

				@Instantiable
				public final class Logger: Instantiable {
				    public init() {}
				    let differentialValueCreationStamp = Stamp.next()
				}

				@Instantiable
				public final class Detail: Instantiable {
				    let differentialValueCreationStamp = Stamp.next()
				    init(logger: Logger, api: any Api) { self.logger = logger; self.api = api }
				    @Received public let logger: Logger
				    @Instantiated public let api: any Api
				}

				@Instantiable(generateMock: .public)
				public final class Inner: Instantiable {
				    let differentialValueCreationStamp = Stamp.next()
				    init(detail: Detail) { self.detail = detail }
				    @Instantiated public let detail: Detail
				}
				""",
			]),
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				"""
				import SafeDI
				import Up

				@Instantiable(generateMock: .public)
				public final class Outer: Instantiable {
				    let differentialValueCreationStamp = Stamp.next()
				    init(logger: Logger, inner: Inner) { self.logger = logger; self.inner = inner }
				    @Instantiated public let logger: Logger
				    @Instantiated public let inner: Inner
				}
				""",
			], dependencies: ["Up"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
				"""
				import SafeDI
				import Up
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public final class LiveApi: Instantiable, Api {
				    let differentialValueCreationStamp = Stamp.next()
				    public init(logger: Logger) { self.logger = logger }
				    @Received public let logger: Logger
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    let differentialValueCreationStamp = Stamp.next()
				    public init(logger: Logger, outer: Outer) { self.logger = logger; self.outer = outer }
				    @Instantiated public let logger: Logger
				    @Instantiated public let outer: Outer
				}
				""",
				Self.loggerProbe,
			], dependencies: ["Up", "Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Up"]?.generatedFiles == ["Up.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Inner {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct detail_Values {
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
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detail: (detail_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detail: @escaping (detail_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detail = detail
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(detail: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            logger: (() -> Logger)? = nil,
		            detail: ((Logger, any Api) -> Detail)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                detail: detail
		            )
		        }

		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var detail: ((Logger, any Api) -> Detail)? { __safeDI_storage.detail }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                detail: ((Logger, any Api) -> Detail)?
		            ) {
		                self.logger = logger
		                self.detail = detail
		            }

		            let logger: (() -> Logger)?
		            let detail: ((Logger, any Api) -> Detail)?
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        logger: Logger? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        Inner.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), logger: logger, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Inner.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        logger: Logger? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        let logger = if let logger { logger } else if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        let __safeDI_apiBuilder_detail = __safeDI_apiBuilder.detail(SafeDIMockScope_Api.detail_Values(logger: logger))
		        func __safeDI_detail() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detail.api(SafeDIMockScope_Api.Detail_Scope.api_Values())
		            return if let safeDIBuilder = safeDIOverrides.detail { safeDIBuilder(logger, api) } else { Detail(logger: logger, api: api) }
		        }
		        let detail: Detail = __safeDI_detail()
		        return Inner(detail: detail)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_mock_BAE1F41FF7753381 {}
		}
		#endif
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Up)
		import Up
		#endif

		#if DEBUG
		extension Outer {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct inner_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner: (inner_Values) -> Inner.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

		            public init(inner: @escaping (inner_Values) -> Inner.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
		                self.inner = inner
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(inner: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            logger: (() -> Logger)? = nil,
		            inner: Inner.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                inner: inner
		            )
		        }

		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                inner: Inner.SafeDIOverrides
		            ) {
		                self.logger = logger
		                self.inner = inner
		            }

		            let logger: (() -> Logger)?
		            let inner: Inner.SafeDIOverrides
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        Outer.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Outer.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        _ = Inner.__safeDI_Inner_mock_BAE1F41FF7753381.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let inner = Inner.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.inner(SafeDIMockScope_Api.inner_Values()), logger: logger, safeDIOverrides: safeDIOverrides.inner)
		        return Outer(logger: logger, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_mock_FF10A81DEF4A07EE {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Up)
		import Up
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            logger: (() -> Logger)? = nil,
		            outer: Outer.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                outer: outer
		            )
		        }

		        var logger: (() -> Logger)? { __safeDI_storage.logger }
		        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                outer: Outer.SafeDIOverrides
		            ) {
		                self.logger = logger
		                self.outer = outer
		            }

		            let logger: (() -> Logger)?
		            let outer: Outer.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        func __safeDI_outer() -> Outer {
		            func __safeDI_apiBuilder_Outer() -> Outer.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(inner: { _ in __safeDI_apiBuilder_Inner() })
		            }
		            func __safeDI_apiBuilder_Inner() -> Inner.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(detail: { values in __safeDI_apiBuilder_Inner_Detail_Scope(logger: values.logger) })
		            }
		            func __safeDI_apiBuilder_Inner_Detail_Scope(logger: Logger) -> Inner.SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(logger: logger)
		                    return api
		                })
		            }
		            _ = Outer.__safeDI_Outer_mock_FF10A81DEF4A07EE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Outer(), safeDIOverrides: safeDIOverrides.outer)
		        }
		        let outer: Outer = __safeDI_outer()
		        return Root(logger: logger, outer: outer)
		    }
		}
		#endif
		"""])
		let probe = DifferentialValueProbe("probeResult()")
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
		let knownRight = try await knownRightDescription(of: modules, keeping: Set(modules.map(\.name)), probeSource: "", probe: probe)
		if compileVerificationIsEnabled {
			#expect(knownRight == "probe probeResult()\nString \"logger is Outer’s: true\"\n")
			#expect(feature == knownRight)
		}
		// Each class is stamped when it is built (`DifferentialValueCreationStamp`), so a value the mock builds earlier than the
		// same declarations built in one module would is marked.
		let orderProbe = DifferentialValueProbe("Root.mock()")
		let featureOrder = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [orderProbe], filesToDelete: &filesToDelete)
		let knownRightOrder = try await knownRightDescription(of: modules, keeping: Set(modules.map(\.name)), probeSource: "", probe: orderProbe)
		if compileVerificationIsEnabled {
			#expect(featureOrder == knownRightOrder)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsKnownRightValues_whenTwoCallingPublicMocksPassThePlaceUpInTurn() async throws {
		// `Outer` builds `logger` and calls `Middle`’s mock, which builds `tag` and calls `Inner`’s, whose `Detail` receives `logger`
		// and, only if available, `tag`. Both pass the place up, and `Root`, which declares its own `logger` and `tag`, fills it:
		// `LiveApi` gets `Outer`’s logger and `Middle`’s tag, as in the same declarations built in one module.
		let modules = [
			ModuleFixture(name: "Up", packageName: "Up", swiftFileContent: [
				"""
				import SafeDI

				public protocol Api: AnyObject {}

				public enum Stamp {
				    nonisolated(unsafe) private static var lastStamp = 0

				    public static func next() -> Int {
				        lastStamp += 1
				        return lastStamp
				    }
				}

				@Instantiable
				public final class Logger: Instantiable {
				    public init() {}
				    let differentialValueCreationStamp = Stamp.next()
				}

				@Instantiable
				public final class Tag: Instantiable {
				    public init() {}
				    let differentialValueCreationStamp = Stamp.next()
				}

				@Instantiable
				public final class Detail: Instantiable {
				    let differentialValueCreationStamp = Stamp.next()
				    init(logger: Logger, tag: Tag?, api: any Api) { self.logger = logger; self.tag = tag; self.api = api }
				    @Received public let logger: Logger
				    @Received(onlyIfAvailable: true) public let tag: Tag?
				    @Instantiated public let api: any Api
				}

				@Instantiable(generateMock: .public)
				public final class Inner: Instantiable {
				    let differentialValueCreationStamp = Stamp.next()
				    init(detailBuilder: Instantiator<Detail>) { self.detailBuilder = detailBuilder }
				    @Instantiated public let detailBuilder: Instantiator<Detail>
				}
				""",
			]),
			ModuleFixture(name: "Mid", packageName: "Mid", swiftFileContent: [
				"""
				import SafeDI
				import Up

				@Instantiable(generateMock: .public)
				public final class Middle: Instantiable {
				    let differentialValueCreationStamp = Stamp.next()
				    init(tag: Tag, inner: Inner) { self.tag = tag; self.inner = inner }
				    @Instantiated public let tag: Tag
				    @Instantiated public let inner: Inner
				}
				""",
			], dependencies: ["Up"]),
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				"""
				import SafeDI
				import Up
				import Mid

				@Instantiable(generateMock: .public)
				public final class Outer: Instantiable {
				    let differentialValueCreationStamp = Stamp.next()
				    init(logger: Logger, middle: Middle) { self.logger = logger; self.middle = middle }
				    @Instantiated public let logger: Logger
				    @Instantiated public let middle: Middle
				}
				""",
			], dependencies: ["Up", "Mid"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
				"""
				import SafeDI
				import Up
				import Mid
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public final class LiveApi: Instantiable, Api {
				    let differentialValueCreationStamp = Stamp.next()
				    public init(logger: Logger, tag: Tag?) { self.logger = logger; self.tag = tag }
				    @Received public let logger: Logger
				    @Received(onlyIfAvailable: true) public let tag: Tag?
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    let differentialValueCreationStamp = Stamp.next()
				    public init(logger: Logger, tag: Tag, outer: Outer) { self.logger = logger; self.tag = tag; self.outer = outer }
				    @Instantiated public let logger: Logger
				    @Instantiated public let tag: Tag
				    @Instantiated public let outer: Outer
				}
				""",
				Self.loggerAndTagProbe,
			], dependencies: ["Up", "Mid", "Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Up"]?.generatedFiles == ["Up.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Inner {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct detailBuilder_Values {
		            public let tag: Tag?
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
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(detailBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            logger: (() -> Logger)? = nil,
		            detailBuilder: ((Logger, Tag?, any Api) -> Detail)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                detailBuilder: detailBuilder
		            )
		        }

		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var detailBuilder: ((Logger, Tag?, any Api) -> Detail)? { __safeDI_storage.detailBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                detailBuilder: ((Logger, Tag?, any Api) -> Detail)?
		            ) {
		                self.logger = logger
		                self.detailBuilder = detailBuilder
		            }

		            let logger: (() -> Logger)?
		            let detailBuilder: ((Logger, Tag?, any Api) -> Detail)?
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        logger: Logger? = nil,
		        tag: Tag? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        Inner.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), logger: logger, tag: tag, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Inner.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        logger: Logger? = nil,
		        tag: Tag? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        let logger = if let logger { logger } else if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIMockScope_Api.detailBuilder_Values(tag: tag, logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api(SafeDIMockScope_Api.Detail_Scope.api_Values())
		            return if let safeDIBuilder = safeDIOverrides.detailBuilder { safeDIBuilder(logger, tag, api) } else { Detail(logger: logger, tag: tag, api: api) }
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Inner(detailBuilder: detailBuilder)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_mock_C8EFD86742C8EB53 {}
		}
		#endif
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Up)
		import Up
		#endif

		#if DEBUG
		extension Middle {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct inner_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner: (inner_Values) -> Inner.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

		            public init(inner: @escaping (inner_Values) -> Inner.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
		                self.inner = inner
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(inner: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            tag: (() -> Tag)? = nil,
		            logger: (() -> Logger)? = nil,
		            inner: Inner.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                tag: tag,
		                logger: logger,
		                inner: inner
		            )
		        }

		        public var tag: (() -> Tag)? { __safeDI_storage.tag }
		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                tag: (() -> Tag)?,
		                logger: (() -> Logger)?,
		                inner: Inner.SafeDIOverrides
		            ) {
		                self.tag = tag
		                self.logger = logger
		                self.inner = inner
		            }

		            let tag: (() -> Tag)?
		            let logger: (() -> Logger)?
		            let inner: Inner.SafeDIOverrides
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        logger: Logger? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Middle {
		        Middle.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), logger: logger, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Middle.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        logger: Logger? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Middle {
		        let tag = if let safeDIBuilder = safeDIOverrides.tag { safeDIBuilder() } else { Tag() }
		        let logger = if let logger { logger } else if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        _ = Inner.__safeDI_Inner_mock_C8EFD86742C8EB53.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let inner = Inner.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.inner(SafeDIMockScope_Api.inner_Values()), logger: logger, tag: tag, safeDIOverrides: safeDIOverrides.inner)
		        return Middle(tag: tag, inner: inner)
		    }
		}

		extension Middle {
		    public enum __safeDI_Middle_mock_A98681C1C44FB67A {}
		}
		#endif
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Mid)
		import Mid
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Up)
		import Up
		#endif

		#if DEBUG
		extension Outer {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct middle_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let middle: (middle_Values) -> Middle.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

		            public init(middle: @escaping (middle_Values) -> Middle.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
		                self.middle = middle
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(middle: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            logger: (() -> Logger)? = nil,
		            middle: Middle.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                middle: middle
		            )
		        }

		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var middle: Middle.SafeDIOverrides { __safeDI_storage.middle }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                middle: Middle.SafeDIOverrides
		            ) {
		                self.logger = logger
		                self.middle = middle
		            }

		            let logger: (() -> Logger)?
		            let middle: Middle.SafeDIOverrides
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        Outer.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Outer.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        _ = Middle.__safeDI_Middle_mock_A98681C1C44FB67A.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let middle = Middle.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.middle(SafeDIMockScope_Api.middle_Values()), logger: logger, safeDIOverrides: safeDIOverrides.middle)
		        return Outer(logger: logger, middle: middle)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_mock_452F19E2C0D1F5E4 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Mid)
		import Mid
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Up)
		import Up
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            logger: (() -> Logger)? = nil,
		            tag: (() -> Tag)? = nil,
		            outer: Outer.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                tag: tag,
		                outer: outer
		            )
		        }

		        var logger: (() -> Logger)? { __safeDI_storage.logger }
		        var tag: (() -> Tag)? { __safeDI_storage.tag }
		        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                tag: (() -> Tag)?,
		                outer: Outer.SafeDIOverrides
		            ) {
		                self.logger = logger
		                self.tag = tag
		                self.outer = outer
		            }

		            let logger: (() -> Logger)?
		            let tag: (() -> Tag)?
		            let outer: Outer.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        let tag = if let safeDIBuilder = safeDIOverrides.tag { safeDIBuilder() } else { Tag() }
		        func __safeDI_outer() -> Outer {
		            func __safeDI_apiBuilder_Outer() -> Outer.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(middle: { _ in __safeDI_apiBuilder_Middle() })
		            }
		            func __safeDI_apiBuilder_Middle() -> Middle.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(inner: { _ in __safeDI_apiBuilder_Inner() })
		            }
		            func __safeDI_apiBuilder_Inner() -> Inner.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { values in __safeDI_apiBuilder_Inner_Detail_Scope(logger: values.logger, tag: values.tag) })
		            }
		            func __safeDI_apiBuilder_Inner_Detail_Scope(logger: Logger, tag: Tag?) -> Inner.SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(logger: logger, tag: tag)
		                    return api
		                })
		            }
		            _ = Outer.__safeDI_Outer_mock_452F19E2C0D1F5E4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Outer(), safeDIOverrides: safeDIOverrides.outer)
		        }
		        let outer: Outer = __safeDI_outer()
		        return Root(logger: logger, tag: tag, outer: outer)
		    }
		}
		#endif
		"""])
		let probe = DifferentialValueProbe("probeResult()")
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
		let knownRight = try await knownRightDescription(of: modules, keeping: Set(modules.map(\.name)), probeSource: "", probe: probe)
		if compileVerificationIsEnabled {
			#expect(knownRight == "probe probeResult()\nString \"logger is Outer’s: true; tag is Middle’s: true; detail.tag is Middle’s: true\"\n")
			#expect(feature == knownRight)
		}
		// Each class is stamped when it is built (`DifferentialValueCreationStamp`), so a value the mock builds earlier than the
		// same declarations built in one module would is marked.
		let orderProbe = DifferentialValueProbe("Root.mock()")
		let featureOrder = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [orderProbe], filesToDelete: &filesToDelete)
		let knownRightOrder = try await knownRightDescription(of: modules, keeping: Set(modules.map(\.name)), probeSource: "", probe: orderProbe)
		if compileVerificationIsEnabled {
			#expect(featureOrder == knownRightOrder)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsKnownRightValues_whenPassingUpMockDeclaresValueFillReadsLazily() async throws {
		// `Outer` declares `logger` lazily and calls `Inner`’s mock, whose `Detail`, built in an instantiator, receives it; `Root`,
		// which declares its own `logger`, fills the place `Outer` passes up. `LiveApi` and `Detail` get `Outer`’s logger.
		let modules = [
			ModuleFixture(name: "Up", packageName: "Up", swiftFileContent: [
				"""
				import SafeDI

				public protocol Api: AnyObject {}

				public enum Stamp {
				    nonisolated(unsafe) private static var lastStamp = 0

				    public static func next() -> Int {
				        lastStamp += 1
				        return lastStamp
				    }
				}

				@Instantiable
				public final class Logger: Instantiable {
				    public init() {}
				    let differentialValueCreationStamp = Stamp.next()
				}

				@Instantiable
				public final class Detail: Instantiable {
				    let differentialValueCreationStamp = Stamp.next()
				    init(logger: Logger, api: any Api) { self.logger = logger; self.api = api }
				    @Received public let logger: Logger
				    @Instantiated public let api: any Api
				}

				@Instantiable(generateMock: .public)
				public final class Inner: Instantiable {
				    let differentialValueCreationStamp = Stamp.next()
				    init(detailBuilder: Instantiator<Detail>) { self.detailBuilder = detailBuilder }
				    @Instantiated public let detailBuilder: Instantiator<Detail>
				}
				""",
			]),
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				"""
				import SafeDI
				import Up

				@Instantiable(generateMock: .public)
				public final class Outer: Instantiable {
				    let differentialValueCreationStamp = Stamp.next()
				    init(logger: LazilyInstantiated<Logger>, inner: Inner) { self.logger = logger; self.inner = inner }
				    @Instantiated public let logger: LazilyInstantiated<Logger>
				    @Instantiated public let inner: Inner
				}
				""",
			], dependencies: ["Up"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
				"""
				import SafeDI
				import Up
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public final class LiveApi: Instantiable, Api {
				    let differentialValueCreationStamp = Stamp.next()
				    public init(logger: Logger) { self.logger = logger }
				    @Received public let logger: Logger
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    let differentialValueCreationStamp = Stamp.next()
				    public init(logger: Logger, outer: Outer) { self.logger = logger; self.outer = outer }
				    @Instantiated public let logger: Logger
				    @Instantiated public let outer: Outer
				}
				""",
				Self.lazyLoggerProbe,
			], dependencies: ["Up", "Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Up"]?.generatedFiles == ["Up.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Inner {
		    nonisolated public enum SafeDIMockScope_Api {
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
		                    self.init(api: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(detailBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            logger: (() -> Logger)? = nil,
		            detailBuilder: ((Logger, any Api) -> Detail)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                detailBuilder: detailBuilder
		            )
		        }

		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var detailBuilder: ((Logger, any Api) -> Detail)? { __safeDI_storage.detailBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                detailBuilder: ((Logger, any Api) -> Detail)?
		            ) {
		                self.logger = logger
		                self.detailBuilder = detailBuilder
		            }

		            let logger: (() -> Logger)?
		            let detailBuilder: ((Logger, any Api) -> Detail)?
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        logger: Logger? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        Inner.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), logger: logger, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Inner.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        logger: Logger? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        let logger = if let logger { logger } else if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIMockScope_Api.detailBuilder_Values(logger: logger))
		        func __safeDI_detailBuilder() -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api(SafeDIMockScope_Api.Detail_Scope.api_Values())
		            return if let safeDIBuilder = safeDIOverrides.detailBuilder { safeDIBuilder(logger, api) } else { Detail(logger: logger, api: api) }
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Inner(detailBuilder: detailBuilder)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_mock_EEEE16888F2B743C {}
		}
		#endif
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Up)
		import Up
		#endif

		#if DEBUG
		extension Outer {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct inner_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner: (inner_Values) -> Inner.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

		            public init(inner: @escaping (inner_Values) -> Inner.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
		                self.inner = inner
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(inner: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            logger: (() -> Logger)? = nil,
		            inner: Inner.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                inner: inner
		            )
		        }

		        public var logger: (() -> Logger)? { __safeDI_storage.logger }
		        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                inner: Inner.SafeDIOverrides
		            ) {
		                self.logger = logger
		                self.inner = inner
		            }

		            let logger: (() -> Logger)?
		            let inner: Inner.SafeDIOverrides
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        Outer.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Outer.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        func __safeDI_logger() -> Logger {
		            if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        }
		        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
		        _ = Inner.__safeDI_Inner_mock_EEEE16888F2B743C.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let inner = Inner.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.inner(SafeDIMockScope_Api.inner_Values()), logger: logger.instance, safeDIOverrides: safeDIOverrides.inner)
		        return Outer(logger: logger, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_mock_08A175DF98100603 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Up)
		import Up
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            logger: (() -> Logger)? = nil,
		            outer: Outer.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                logger: logger,
		                outer: outer
		            )
		        }

		        var logger: (() -> Logger)? { __safeDI_storage.logger }
		        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                logger: (() -> Logger)?,
		                outer: Outer.SafeDIOverrides
		            ) {
		                self.logger = logger
		                self.outer = outer
		            }

		            let logger: (() -> Logger)?
		            let outer: Outer.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
		        func __safeDI_outer() -> Outer {
		            func __safeDI_apiBuilder_Outer() -> Outer.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(inner: { _ in __safeDI_apiBuilder_Inner() })
		            }
		            func __safeDI_apiBuilder_Inner() -> Inner.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { values in __safeDI_apiBuilder_Inner_Detail_Scope(logger: values.logger) })
		            }
		            func __safeDI_apiBuilder_Inner_Detail_Scope(logger: Logger) -> Inner.SafeDIMockScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(logger: logger)
		                    return api
		                })
		            }
		            _ = Outer.__safeDI_Outer_mock_08A175DF98100603.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Outer(), safeDIOverrides: safeDIOverrides.outer)
		        }
		        let outer: Outer = __safeDI_outer()
		        return Root(logger: logger, outer: outer)
		    }
		}
		#endif
		"""])
		let probe = DifferentialValueProbe("probeResult()")
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
		let knownRight = try await knownRightDescription(of: modules, keeping: Set(modules.map(\.name)), probeSource: "", probe: probe)
		if compileVerificationIsEnabled {
			#expect(knownRight == "probe probeResult()\nString \"logger is Outer’s: true; detail.logger is Outer’s: true\"\n")
			#expect(feature == knownRight)
		}
	}

	// MARK: Tests – an override closure that builds a called mock

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsOverrideClosureEscapingBuilders_whenCalledMockTakesBuildersOfErasedInstantiators() async throws {
		// `Host`’s `mock()` takes each builder `@escaping`, as an erased instantiator’s `Builder` names a function, so the
		// override closure of `HostScreen`’s call is handed them `@escaping` too: the closure a person writes passes them on.
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
				"""
				import SafeDI

				public typealias OnTap = @Sendable () -> Void

				public protocol Service: Sendable {}

				public struct AnyService: Service {
				    public init(_ service: any Service) {
				        self.service = service
				    }

				    public let service: any Service
				}

				@Instantiable(generateMock: .public)
				public struct Host: Instantiable {
				    package init(maker: ErasedInstantiator<OnTap, AnyService>, sendableMaker: SendableErasedInstantiator<OnTap, AnyService>) {
				        self.maker = maker
				        self.sendableMaker = sendableMaker
				    }

				    @Instantiated(fulfilledByType: "TapService", erasedToConcreteExistential: true) let maker: ErasedInstantiator<OnTap, AnyService>
				    @Instantiated(fulfilledByType: "TapService", erasedToConcreteExistential: true) let sendableMaker: SendableErasedInstantiator<OnTap, AnyService>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable
				public struct TapService: Service, Instantiable {
				    public init(onTap: @escaping OnTap) {
				        self.onTap = onTap
				    }

				    @Forwarded let onTap: OnTap
				}

				@Instantiable(generateMock: true)
				public struct HostScreen: Instantiable {
				    public init(host: Host) {
				        self.host = host
				    }

				    @Instantiated let host: Host
				}
				""",
				"""
				import Core

				func hostScreenBuildsHostThroughItsOverride() -> String {
				    var calls = 0
				    _ = HostScreen.mock(safeDIOverrides: .init(host: { maker, sendableMaker in
				        calls += 1
				        return Host.mock(tapService_AnyServiceBuilder: maker, tapService_AnyServiceSendableBuilder: sendableMaker)
				    }))
				    return "override called \\(calls)"
				}
				""",
			], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension HostScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            host: ((@escaping ErasedInstantiator<OnTap, AnyService>.Builder, @escaping SendableErasedInstantiator<OnTap, AnyService>.Builder) -> Host)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                host: host
		            )
		        }

		        var host: ((@escaping ErasedInstantiator<OnTap, AnyService>.Builder, @escaping SendableErasedInstantiator<OnTap, AnyService>.Builder) -> Host)? { __safeDI_storage.host }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                host: ((@escaping ErasedInstantiator<OnTap, AnyService>.Builder, @escaping SendableErasedInstantiator<OnTap, AnyService>.Builder) -> Host)?
		            ) {
		                self.host = host
		            }

		            let host: ((@escaping ErasedInstantiator<OnTap, AnyService>.Builder, @escaping SendableErasedInstantiator<OnTap, AnyService>.Builder) -> Host)?
		        }
		    }

		    static func mock(
		        tapService_AnyServiceBuilder: ErasedInstantiator<OnTap, AnyService>.Builder? = nil,
		        tapService_AnyServiceSendableBuilder: SendableErasedInstantiator<OnTap, AnyService>.Builder? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> HostScreen {
		        func __safeDI_host() -> Host {
		            func __safeDI_tapService_AnyServiceBuilder_Host_maker() -> ErasedInstantiator<OnTap, AnyService>.Builder {
		                func __safeDI_maker(onTap: @escaping OnTap) -> TapService {
		                    TapService(onTap: onTap)
		                }
		                return { forwarded in AnyService(__safeDI_maker(onTap: forwarded)) }
		            }
		            @Sendable nonisolated func __safeDI_tapService_AnyServiceSendableBuilder_Host_sendableMaker() -> SendableErasedInstantiator<OnTap, AnyService>.Builder {
		                @Sendable nonisolated func __safeDI_sendableMaker(onTap: @escaping OnTap) -> TapService {
		                    TapService(onTap: onTap)
		                }
		                return { forwarded in AnyService(__safeDI_sendableMaker(onTap: forwarded)) }
		            }
		            func __safeDI_tapService_AnyServiceBuilder_Host() -> Host.SafeDIMockScope_TapService_AnyService.__safeDI_Builder<AnyService> {
		                .init(maker: { _ in __safeDI_tapService_AnyServiceBuilder_Host_maker() })
		            }
		            @Sendable nonisolated func __safeDI_tapService_AnyServiceSendableBuilder_Host() -> Host.SafeDISendableMockScope_TapService_AnyService.__safeDI_Builder<AnyService> {
		                .init(sendableMaker: { _ in __safeDI_tapService_AnyServiceSendableBuilder_Host_sendableMaker() })
		            }
		            _ = Host.__safeDI_Host_mock_7BE7BA53778E487E.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.host { safeDIBuilder(tapService_AnyServiceBuilder ?? __safeDI_tapService_AnyServiceBuilder_Host_maker(), tapService_AnyServiceSendableBuilder ?? __safeDI_tapService_AnyServiceSendableBuilder_Host_sendableMaker()) } else { Host.__safeDI_mock(tapService_AnyServiceBuilder: tapService_AnyServiceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_tapService_AnyServiceBuilder_Host(), tapService_AnyServiceSendableBuilder: tapService_AnyServiceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_tapService_AnyServiceSendableBuilder_Host()) }
		        }
		        let host: Host = __safeDI_host()
		        return HostScreen(host: host)
		    }
		}
		#endif
		"""])
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("hostScreenBuildsHostThroughItsOverride()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			#expect(description == "probe hostScreenBuildsHostThroughItsOverride()\nString \"override called 1\"\n")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsOverrideClosureBuildersThatTakeNothing_whenCalledMockTakesBuildersOfErasedInstantiatorsThatForwardNothing() async throws {
		// `Host`’s `mock()` takes a builder that takes nothing for each erased instantiator of `()`, as for a plain place, so
		// the override closure of `HostScreen`’s call is handed the fill of each place as a closure that calls the erased
		// instantiator’s `Builder` the fill returns with `()`.
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
				"""
				import SafeDI

				public protocol Service: Sendable {}

				public struct AnyService: Service {
				    public init(_ service: any Service) {
				        self.service = service
				    }

				    public let service: any Service
				}

				@Instantiable(generateMock: .public)
				public struct Host: Instantiable {
				    package init(maker: ErasedInstantiator<(), AnyService>, sendableMaker: SendableErasedInstantiator<(), AnyService>) {
				        self.maker = maker
				        self.sendableMaker = sendableMaker
				    }

				    @Instantiated(fulfilledByType: "TapService", erasedToConcreteExistential: true) let maker: ErasedInstantiator<(), AnyService>
				    @Instantiated(fulfilledByType: "TapService", erasedToConcreteExistential: true) let sendableMaker: SendableErasedInstantiator<(), AnyService>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable
				public struct TapService: Service, Instantiable {
				    public init() {}
				}

				@Instantiable(generateMock: true)
				public struct HostScreen: Instantiable {
				    public init(host: Host) {
				        self.host = host
				    }

				    @Instantiated let host: Host
				}
				""",
				"""
				import Core

				func hostScreenBuildsHostThroughItsOverride() -> String {
				    var calls = 0
				    _ = HostScreen.mock(safeDIOverrides: .init(host: { maker, sendableMaker in
				        calls += 1
				        return Host.mock(tapService_AnyServiceBuilder: maker, tapService_AnyServiceSendableBuilder: sendableMaker)
				    }))
				    return "override called \\(calls)"
				}
				""",
			], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension HostScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            host: ((@escaping () -> AnyService, @escaping @Sendable () -> AnyService) -> Host)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                host: host
		            )
		        }

		        var host: ((@escaping () -> AnyService, @escaping @Sendable () -> AnyService) -> Host)? { __safeDI_storage.host }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                host: ((@escaping () -> AnyService, @escaping @Sendable () -> AnyService) -> Host)?
		            ) {
		                self.host = host
		            }

		            let host: ((@escaping () -> AnyService, @escaping @Sendable () -> AnyService) -> Host)?
		        }
		    }

		    static func mock(
		        tapService_AnyServiceBuilder: (() -> AnyService)? = nil,
		        tapService_AnyServiceSendableBuilder: (@Sendable () -> AnyService)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> HostScreen {
		        func __safeDI_host() -> Host {
		            func __safeDI_tapService_AnyServiceBuilder_Host_maker() -> ErasedInstantiator<(), AnyService>.Builder {
		                func __safeDI_maker() -> TapService {
		                    TapService()
		                }
		                return { _ in AnyService(__safeDI_maker()) }
		            }
		            @Sendable nonisolated func __safeDI_tapService_AnyServiceSendableBuilder_Host_sendableMaker() -> SendableErasedInstantiator<(), AnyService>.Builder {
		                @Sendable nonisolated func __safeDI_sendableMaker() -> TapService {
		                    TapService()
		                }
		                return { _ in AnyService(__safeDI_sendableMaker()) }
		            }
		            func __safeDI_tapService_AnyServiceBuilder_Host() -> Host.SafeDIMockScope_TapService_AnyService.__safeDI_Builder<AnyService> {
		                .init(maker: { _ in __safeDI_tapService_AnyServiceBuilder_Host_maker() })
		            }
		            @Sendable nonisolated func __safeDI_tapService_AnyServiceSendableBuilder_Host() -> Host.SafeDISendableMockScope_TapService_AnyService.__safeDI_Builder<AnyService> {
		                .init(sendableMaker: { _ in __safeDI_tapService_AnyServiceSendableBuilder_Host_sendableMaker() })
		            }
		            _ = Host.__safeDI_Host_mock_3255AE3778C05DDE.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.host { safeDIBuilder({ if let tapService_AnyServiceBuilder { tapService_AnyServiceBuilder() } else { __safeDI_tapService_AnyServiceBuilder_Host_maker()(()) } }, { if let tapService_AnyServiceSendableBuilder { tapService_AnyServiceSendableBuilder() } else { __safeDI_tapService_AnyServiceSendableBuilder_Host_sendableMaker()(()) } }) } else { Host.__safeDI_mock(tapService_AnyServiceBuilder: tapService_AnyServiceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_tapService_AnyServiceBuilder_Host(), tapService_AnyServiceSendableBuilder: tapService_AnyServiceSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_tapService_AnyServiceSendableBuilder_Host()) }
		        }
		        let host: Host = __safeDI_host()
		        return HostScreen(host: host)
		    }
		}
		#endif
		"""])
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("hostScreenBuildsHostThroughItsOverride()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			#expect(description == "probe hostScreenBuildsHostThroughItsOverride()\nString \"override called 1\"\n")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsOverrideClosureFunctionOverCallersFill_whenCallerFillsCalledMocksPlace() async throws {
		// `Detail`, a public mock that builds nothing but its place, receives `session` before its tree, so `Root`’s overrides
		// hold a closure that builds `Detail` from the builder a person writes and the session. `Root` fills the place with
		// `Live`, which reads the session: the closure is handed a function over that fill, which a written closure passes on
		// to `Detail.mock` as is.
		let modules = Self.overrideModules(app: [
			Self.live,
			Self.overrideRoot(mockGeneration: "true"),
			"""
			func overrideBuildsDetail() -> String {
			    var calls = 0
			    let session = Session()
			    let root = Root.mock(session: session, safeDIOverrides: .init(detailBuilder: { session, apiBuilder in
			        calls += 1
			        return Detail.mock(session: session, apiBuilder: apiBuilder)
			    }))
			    let detail = root.detailBuilder.instantiate()
			    return "override called \\(calls), api reads the session \\((detail.api as? Live)?.session === session)"
			}
			""",
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("overrideBuildsDetail()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			#expect(description == "probe overrideBuildsDetail()\nString \"override called 1, api reads the session true\"\n")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsOverrideClosureCallersOwnBuilder_whenCallerPassesCalledMocksPlaceUp() async throws {
		// No module fills `Api` but the probe, so `Root`’s mock takes the builder a person writes and hands it as is to the
		// closure its overrides hold, which passes it on to `Detail.mock`.
		let modules = Self.overrideModules(app: [
			Self.overrideRoot(mockGeneration: "true"),
			"""
			final class StubApi: Api {}

			func overrideBuildsDetail() -> String {
			    var calls = 0
			    var builds = 0
			    let root = Root.mock(apiBuilder: {
			        builds += 1
			        return StubApi()
			    }, session: Session(), safeDIOverrides: .init(detailBuilder: { session, apiBuilder in
			        calls += 1
			        return Detail.mock(session: session, apiBuilder: apiBuilder)
			    }))
			    let detail = root.detailBuilder.instantiate()
			    return "override called \\(calls), builder called \\(builds), api is the stub \\(detail.api is StubApi)"
			}
			""",
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("overrideBuildsDetail()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			#expect(description == "probe overrideBuildsDetail()\nString \"override called 1, builder called 1, api is the stub true\"\n")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsOverrideClosureFunctionOverCallersFill_whenPublicCallerFillsCalledMocksPlace() async throws {
		// `Root`, a public mock, fills `Detail`’s place with `Live`, which reads only the session the call passes `Detail`, so
		// its overrides keep the closure that builds `Detail`, handed a function over that fill, which a written closure in
		// `App` passes on to `Detail.mock` as is.
		let valueProbeSource = """
		func apiReadsSession() -> String {
		    let session = Session()
		    let detail = Root.mock(session: session).detailBuilder.instantiate()
		    return "api reads the session \\((detail.api as? Live)?.session === session)"
		}
		"""
		let modules = Self.overrideModules(app: [
			Self.live,
			Self.overrideRoot(mockGeneration: ".public"),
			valueProbeSource,
			"""
			func overrideBuildsDetail() -> String {
			    var calls = 0
			    let session = Session()
			    let root = Root.mock(session: session, safeDIOverrides: .init(detailBuilder: { session, apiBuilder in
			        calls += 1
			        return Detail.mock(session: session, apiBuilder: apiBuilder)
			    }))
			    let detail = root.detailBuilder.instantiate()
			    return "override called \\(calls), api reads the session \\((detail.api as? Live)?.session === session)"
			}
			""",
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Detail {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {
		            public let session: Session
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    public static func mock(
		        session: Session,
		        apiBuilder: @escaping () -> any Api
		    ) -> Detail {
		        Detail.__safeDI_mock(session: session, apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session: Session,
		        apiBuilder __safeDI_apiBuilder: Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api>
		    ) -> Detail {
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values(session: session))
		        return Detail(session: session, api: api)
		    }
		}

		extension Detail {
		    public enum __safeDI_Detail_mock_761E40A8BF1136DD {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            detailBuilder: ((Session, @escaping () -> any Api) -> Detail)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                detailBuilder: detailBuilder
		            )
		        }

		        public var detailBuilder: ((Session, @escaping () -> any Api) -> Detail)? { __safeDI_storage.detailBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                detailBuilder: ((Session, @escaping () -> any Api) -> Detail)?
		            ) {
		                self.detailBuilder = detailBuilder
		            }

		            let detailBuilder: ((Session, @escaping () -> any Api) -> Detail)?
		        }
		    }

		    public static func mock(
		        session: Session,
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        Root.__safeDI_mock(session: session, apiBuilder: apiBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session: Session,
		        apiBuilder __safeDI_apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_detailBuilder() -> Detail {
		            func __safeDI_apiBuilder_Detail_api(session: Session) -> any Api {
		                let api: any Api = Live(session: session)
		                return api
		            }
		            func __safeDI_apiBuilder_Detail() -> Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { values in __safeDI_apiBuilder_Detail_api(session: values.session) })
		            }
		            _ = Detail.__safeDI_Detail_mock_761E40A8BF1136DD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.detailBuilder { safeDIBuilder(session, { if let __safeDI_apiBuilder { __safeDI_apiBuilder() } else { __safeDI_apiBuilder_Detail_api(session: session) } }) } else { Detail.__safeDI_mock(session: session, apiBuilder: __safeDI_apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Detail()) }
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Root(session: session, detailBuilder: detailBuilder)
		    }
		}

		extension Root {
		    public enum __safeDI_Root_mock_FC9E99C87ED246BA {}
		}
		#endif
		"""])
		let overrideDescription = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("overrideBuildsDetail()")], filesToDelete: &filesToDelete)
		let probe = DifferentialValueProbe("apiReadsSession()")
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
		let knownRight = try await knownRightDescription(of: modules, keeping: ["Feature"], probeSource: Self.live + "\n\n" + Self.overrideRoot(mockGeneration: ".public") + "\n\n" + valueProbeSource, probe: probe)
		if compileVerificationIsEnabled {
			#expect(overrideDescription == "probe overrideBuildsDetail()\nString \"override called 1, api reads the session true\"\n")
			#expect(knownRight == "probe apiReadsSession()\nString \"api reads the session true\"\n")
			#expect(feature == knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsEmptyOverridesWithNoClosureForCalledMock_whenPublicCallerPassesCalledMocksPlaceUp() async throws {
		// `Root`, a public mock, passes up the place of `Detail`, which no module fills. Its body holds only the builder struct
		// its caller built, from which it can make no builder a person writes, so its overrides hold no closure that builds
		// `Detail`. They stay, empty, as does its `safeDIOverrides:` parameter: `Host`’s internal mock in `Top` configures
		// `Root` through them, and a person can still pass them.
		let probeSource = """
		func detailOfRoot() -> String {
		    let session = Session()
		    let detail = Root.mock(session: session, apiBuilder: { StubApi() }, safeDIOverrides: Root.SafeDIOverrides()).detailBuilder.instantiate()
		    return "session is the session \\(detail.session === session), api is the stub \\(detail.api is StubApi)"
		}
		"""
		// `Root`’s initializer is internal, so `Host`’s mock calls `Root`’s public mock.
		let root = """
		@Instantiable(generateMock: .public)
		public final class Root: Instantiable {
		    init(session: Session, detailBuilder: Instantiator<Detail>) {
		        self.session = session
		        self.detailBuilder = detailBuilder
		    }

		    @Received public let session: Session
		    @Instantiated public let detailBuilder: Instantiator<Detail>
		}
		"""
		let modules = Self.overrideModules(app: [root], top: [Self.host, Self.stubApi, probeSource])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Detail {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {
		            public let session: Session
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    public static func mock(
		        session: Session,
		        apiBuilder: @escaping () -> any Api
		    ) -> Detail {
		        Detail.__safeDI_mock(session: session, apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session: Session,
		        apiBuilder __safeDI_apiBuilder: Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api>
		    ) -> Detail {
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values(session: session))
		        return Detail(session: session, api: api)
		    }
		}

		extension Detail {
		    public enum __safeDI_Detail_mock_761E40A8BF1136DD {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct detailBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> Detail.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> Detail.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(detailBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init() {}
		    }

		    public static func mock(
		        session: Session,
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        Root.__safeDI_mock(session: session, apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session: Session,
		        apiBuilder __safeDI_apiBuilder: Root.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        _ = Detail.__safeDI_Detail_mock_761E40A8BF1136DD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_detailBuilder() -> Detail {
		            Detail.__safeDI_mock(session: session, apiBuilder: __safeDI_apiBuilder.detailBuilder(SafeDIMockScope_Api.detailBuilder_Values()))
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Root(session: session, detailBuilder: detailBuilder)
		    }
		}

		extension Root {
		    public enum __safeDI_Root_mock_A8AB7F7A25FA7E0C {}
		}
		#endif
		"""])
		#expect(output.modules["Top"]?.generatedFiles == ["Top.swift": generatedFileHeader + """
		#if canImport(App)
		import App
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Host {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            root: Root.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                root: root
		            )
		        }

		        var root: Root.SafeDIOverrides { __safeDI_storage.root }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                root: Root.SafeDIOverrides
		            ) {
		                self.root = root
		            }

		            let root: Root.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: @escaping () -> any Api,
		        session: Session,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Host {
		        let __safeDI_apiBuilder = apiBuilder
		        _ = Root.__safeDI_Root_mock_A8AB7F7A25FA7E0C.self // If this line does not compile, compile the code SafeDI generates for module App into App: under Bazel, add App’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_root() -> Root {
		            let apiBuilder: () -> any Api = __safeDI_apiBuilder
		            return Root.__safeDI_mock(session: session, apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides.root)
		        }
		        let root: Root = __safeDI_root()
		        return Host(root: root)
		    }
		}
		#endif
		"""])
		let probe = DifferentialValueProbe("detailOfRoot()")
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
		let knownRight = try await knownRightDescription(of: modules, keeping: ["Feature", "App"], probeSource: Self.stubApi + "\n\n" + probeSource, probe: probe)
		if compileVerificationIsEnabled {
			#expect(knownRight == "probe detailOfRoot()\nString \"session is the session true, api is the stub true\"\n")
			#expect(feature == knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersNoOverrideClosureForCalledMock_whenInternalCallersFillReadsCalledMocksOtherPlace() async throws {
		// `Root`’s internal mock fills `Detail`’s `api` with `LiveApi`, which reads `store`, another place of `Detail`’s, and
		// passes `store` up. No builder a person writes can hand that fill the store `Detail` builds, so `Root`’s overrides
		// hold no closure that builds `Detail`, though the builder it passes up is its own: they stay, empty. `LiveApi` reads
		// the detail’s own store.
		let modules = Self.storeModules(app: [
			Self.liveApiReadingStore,
			Self.overrideRoot(mockGeneration: "true"),
			"final class StubStore: Store {}",
			Self.apiReadsDetailsStore(root: "Root.mock(session: Session(), storeBuilder: { StubStore() })"),
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Detail {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {
		            public let session: Session
		            public let store: any Store
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    nonisolated public enum SafeDIMockScope_Store {
		        nonisolated public struct store_Values {
		            public let session: Session
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let store: (store_Values) -> __safeDI_Built

		            public init(store: @escaping (store_Values) -> __safeDI_Built) {
		                self.store = store
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(store: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    public static func mock(
		        session: Session,
		        apiBuilder: @escaping () -> any Api,
		        storeBuilder: @escaping () -> any Store
		    ) -> Detail {
		        Detail.__safeDI_mock(session: session, apiBuilder: .init(__safeDI_noScope: apiBuilder), storeBuilder: .init(__safeDI_noScope: storeBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session: Session,
		        apiBuilder __safeDI_apiBuilder: Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        storeBuilder __safeDI_storeBuilder: Detail.SafeDIMockScope_Store.__safeDI_Builder<any Store>
		    ) -> Detail {
		        let store: any Store = __safeDI_storeBuilder.store(SafeDIMockScope_Store.store_Values(session: session))
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values(session: session, store: store))
		        return Detail(session: session, store: store, api: api)
		    }
		}

		extension Detail {
		    public enum __safeDI_Detail_mock_396CF79E0DB1FDB4 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init() {}
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        session: Session,
		        storeBuilder: @escaping () -> any Store,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_storeBuilder = storeBuilder
		        func __safeDI_detailBuilder() -> Detail {
		            func __safeDI_apiBuilder_Detail() -> Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { scope in
		                    let store = scope.store
		                    let api: any Api = LiveApi(store: store)
		                    return api
		                })
		            }
		            _ = Detail.__safeDI_Detail_mock_396CF79E0DB1FDB4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let storeBuilder: () -> any Store = __safeDI_storeBuilder
		            return Detail.__safeDI_mock(session: session, apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Detail(), storeBuilder: .init(__safeDI_noScope: storeBuilder))
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Root(session: session, detailBuilder: detailBuilder)
		    }
		}
		#endif
		"""])
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("apiReadsDetailsStore()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			#expect(description == "probe apiReadsDetailsStore()\nString \"api reads the detail’s store true\"\n")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersNoOverrideClosureForCalledMock_whenPublicCallersFillReadsCalledMocksOtherPlace() async throws {
		// `Root`, a public mock, fills both of `Detail`’s places: `store` with `LiveStore`, which reads nothing, and `api` with
		// `LiveApi`, which reads `store`. No builder a person writes can hand the second fill the store `Detail` builds, so
		// `Root`’s overrides hold no closure that builds `Detail`: they stay, empty. `LiveApi` reads the detail’s own store,
		// as in one module.
		let liveStore = """
		@Instantiable(fulfillingAdditionalTypes: [Store.self])
		public final class LiveStore: Instantiable, Store {
		    public init() {}
		}
		"""
		let modules = Self.storeModules(app: [
			Self.liveApiReadingStore,
			liveStore,
			Self.overrideRoot(mockGeneration: ".public"),
			Self.apiReadsDetailsStore(root: "Root.mock(session: Session())"),
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Detail {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {
		            public let session: Session
		            public let store: any Store
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    nonisolated public enum SafeDIMockScope_Store {
		        nonisolated public struct store_Values {
		            public let session: Session
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let store: (store_Values) -> __safeDI_Built

		            public init(store: @escaping (store_Values) -> __safeDI_Built) {
		                self.store = store
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(store: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    public static func mock(
		        session: Session,
		        apiBuilder: @escaping () -> any Api,
		        storeBuilder: @escaping () -> any Store
		    ) -> Detail {
		        Detail.__safeDI_mock(session: session, apiBuilder: .init(__safeDI_noScope: apiBuilder), storeBuilder: .init(__safeDI_noScope: storeBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session: Session,
		        apiBuilder __safeDI_apiBuilder: Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        storeBuilder __safeDI_storeBuilder: Detail.SafeDIMockScope_Store.__safeDI_Builder<any Store>
		    ) -> Detail {
		        let store: any Store = __safeDI_storeBuilder.store(SafeDIMockScope_Store.store_Values(session: session))
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values(session: session, store: store))
		        return Detail(session: session, store: store, api: api)
		    }
		}

		extension Detail {
		    public enum __safeDI_Detail_mock_396CF79E0DB1FDB4 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init() {}
		    }

		    public static func mock(
		        session: Session,
		        apiBuilder: (() -> any Api)? = nil,
		        storeBuilder: (() -> any Store)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        Root.__safeDI_mock(session: session, apiBuilder: apiBuilder, storeBuilder: storeBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session: Session,
		        apiBuilder __safeDI_apiBuilder: (() -> any Api)? = nil,
		        storeBuilder __safeDI_storeBuilder: (() -> any Store)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_detailBuilder() -> Detail {
		            func __safeDI_apiBuilder_Detail() -> Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { scope in
		                    let store = scope.store
		                    let api: any Api = LiveApi(store: store)
		                    return api
		                })
		            }
		            func __safeDI_storeBuilder_Detail() -> Detail.SafeDIMockScope_Store.__safeDI_Builder<any Store> {
		                .init(store: { _ in
		                    let store: any Store = LiveStore()
		                    return store
		                })
		            }
		            _ = Detail.__safeDI_Detail_mock_396CF79E0DB1FDB4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Detail.__safeDI_mock(session: session, apiBuilder: __safeDI_apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Detail(), storeBuilder: __safeDI_storeBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_storeBuilder_Detail())
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Root(session: session, detailBuilder: detailBuilder)
		    }
		}

		extension Root {
		    public enum __safeDI_Root_mock_BA3832E25D863AD7 {}
		}
		#endif
		"""])
		let probe = DifferentialValueProbe("apiReadsDetailsStore()")
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
		let knownRight = try await knownRightDescription(of: modules, keeping: Set(modules.map(\.name)), probeSource: "", probe: probe)
		if compileVerificationIsEnabled {
			#expect(knownRight == "probe apiReadsDetailsStore()\nString \"api reads the detail’s store true\"\n")
			#expect(feature == knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersNoOverrideClosureForCalledMock_whenCallersFillReadsValueCalledMockRenames() async throws {
		// `Detail` receives `mainSession` under the label `session`, and `Root`’s fill `Live` reads `session`: in `Detail`’s
		// tree that is the main session, which `Root` holds under another label beside a `session` of its own. A closure handed
		// a builder over the value `Root` holds as `session` would build `Live` with the wrong session, so `Root`’s overrides
		// hold no closure that builds `Detail`. `Feature` cannot build a `Session`, so `Detail`’s mock takes no overrides of its
		// own, and `Root`’s are left empty. `Live` holds the main session, as in one module.
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				"""
				import SafeDI

				public protocol Api: AnyObject {}

				public final class Session {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public final class Detail: Instantiable {
				    init(session: Session, api: any Api) {
				        self.session = session
				        self.api = api
				    }

				    @Received(fulfilledByDependencyNamed: "mainSession", ofType: Session.self) public let session: Session
				    @Instantiated public let api: any Api
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
				"""
				import Feature
				import SafeDI

				@Instantiable
				extension Session: Instantiable {
				    public static func instantiate() -> Session {
				        Session()
				    }
				}

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public final class Live: Instantiable, Api {
				    public init(session: Session) {
				        self.session = session
				    }

				    @Received public let session: Session
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(session: Session, mainSession: Session, detail: Detail) {
				        self.session = session
				        self.mainSession = mainSession
				        self.detail = detail
				    }

				    @Instantiated public let session: Session
				    @Instantiated public let mainSession: Session
				    @Instantiated public let detail: Detail
				}

				func sessionOfLive() -> String {
				    let root = Root.mock()
				    let live = root.detail.api as? Live
				    return "live holds the main session \\(live?.session === root.mainSession), live holds the root’s session \\(live?.session === root.session)"
				}
				""",
			], dependencies: ["Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		// `Detail`’s mock binds the renamed value under a `#sourceLocation` that names its fixture by path.
		let detailPath = output.modules["Feature"]?.fixtures["Detail.swift"] ?? ""
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Detail {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {
		            public let mainSession: Session
		            public let session: Session
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    public static func mock(
		        mainSession: Session,
		        apiBuilder: @escaping () -> any Api
		    ) -> Detail {
		        Detail.__safeDI_mock(mainSession: mainSession, apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        mainSession: Session,
		        apiBuilder __safeDI_apiBuilder: Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api>
		    ) -> Detail {
		        #sourceLocation(file: "\(detailPath)", line: 16)
		        let session: Session = mainSession
		        #sourceLocation()
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values(mainSession: mainSession, session: session))
		        return Detail(session: session, api: api)
		    }
		}

		extension Detail {
		    public enum __safeDI_Detail_mock_91637A16F1E1A69C {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            session: (() -> Session)? = nil,
		            mainSession: (() -> Session)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                session: session,
		                mainSession: mainSession
		            )
		        }

		        var session: (() -> Session)? { __safeDI_storage.session }
		        var mainSession: (() -> Session)? { __safeDI_storage.mainSession }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                session: (() -> Session)?,
		                mainSession: (() -> Session)?
		            ) {
		                self.session = session
		                self.mainSession = mainSession
		            }

		            let session: (() -> Session)?
		            let mainSession: (() -> Session)?
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
		        let mainSession = if let safeDIBuilder = safeDIOverrides.mainSession { safeDIBuilder() } else { Session.instantiate() }
		        func __safeDI_detail() -> Detail {
		            func __safeDI_apiBuilder_Detail() -> Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { scope in
		                    let session = scope.session
		                    let api: any Api = Live(session: session)
		                    return api
		                })
		            }
		            _ = Detail.__safeDI_Detail_mock_91637A16F1E1A69C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Detail.__safeDI_mock(mainSession: mainSession, apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Detail())
		        }
		        let detail: Detail = __safeDI_detail()
		        return Root(session: session, mainSession: mainSession, detail: detail)
		    }
		}
		#endif
		"""])
		let probe = DifferentialValueProbe("sessionOfLive()")
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
		let knownRight = try await knownRightDescription(of: modules, keeping: Set(modules.map(\.name)), probeSource: "", probe: probe)
		if compileVerificationIsEnabled {
			#expect(knownRight == "probe sessionOfLive()\nString \"live holds the main session true, live holds the root’s session false\"\n")
			#expect(feature == knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersNoOverrideClosureInConfigurationOfTypeThatCallsMock_whenPublicCallerPassesPlaceUpThroughType() async throws {
		// `Middle`, which generates an internal mock, builds `Detail`; `Root`, a public mock in the same module, builds
		// `Middle` and passes `Detail`’s place up. The call is in `Root`’s body, which holds only the builder struct its caller
		// built, so `Middle`’s configuration in `Root`’s tree holds no closure that builds `Detail`. `Middle`’s own mock passes
		// the place up from its own parameter and keeps the closure.
		let modules = Self.overrideModules(app: [
			"""
			@Instantiable(generateMock: true)
			public final class Middle: Instantiable {
			    public init(session: Session, detailBuilder: Instantiator<Detail>) {
			        self.session = session
			        self.detailBuilder = detailBuilder
			    }

			    @Received public let session: Session
			    @Instantiated public let detailBuilder: Instantiator<Detail>
			}
			""",
			"""
			@Instantiable(generateMock: .public)
			public final class Root: Instantiable {
			    public init(session: Session, middle: Middle) {
			        self.session = session
			        self.middle = middle
			    }

			    @Received public let session: Session
			    @Instantiated public let middle: Middle
			}
			""",
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Detail {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {
		            public let session: Session
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    public static func mock(
		        session: Session,
		        apiBuilder: @escaping () -> any Api
		    ) -> Detail {
		        Detail.__safeDI_mock(session: session, apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session: Session,
		        apiBuilder __safeDI_apiBuilder: Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api>
		    ) -> Detail {
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values(session: session))
		        return Detail(session: session, api: api)
		    }
		}

		extension Detail {
		    public enum __safeDI_Detail_mock_761E40A8BF1136DD {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Middle {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            detailBuilder: ((Session, @escaping () -> any Api) -> Detail)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                detailBuilder: detailBuilder
		            )
		        }

		        var detailBuilder: ((Session, @escaping () -> any Api) -> Detail)? { __safeDI_storage.detailBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                detailBuilder: ((Session, @escaping () -> any Api) -> Detail)?
		            ) {
		                self.detailBuilder = detailBuilder
		            }

		            let detailBuilder: ((Session, @escaping () -> any Api) -> Detail)?
		        }
		    }

		    static func mock(
		        apiBuilder: @escaping () -> any Api,
		        session: Session,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Middle {
		        let __safeDI_apiBuilder = apiBuilder
		        _ = Detail.__safeDI_Detail_mock_761E40A8BF1136DD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_detailBuilder() -> Detail {
		            let apiBuilder: () -> any Api = __safeDI_apiBuilder
		            return if let safeDIBuilder = safeDIOverrides.detailBuilder { safeDIBuilder(session, apiBuilder) } else { Detail.__safeDI_mock(session: session, apiBuilder: .init(__safeDI_noScope: apiBuilder)) }
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Middle(session: session, detailBuilder: detailBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Root {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct middle_Values {
		            public let session: Session
		        }

		        nonisolated public enum Middle_Scope {
		            nonisolated public struct detailBuilder_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let detailBuilder: (detailBuilder_Values) -> Detail.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

		                public init(detailBuilder: @escaping (detailBuilder_Values) -> Detail.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
		                    self.detailBuilder = detailBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(detailBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let middle: (middle_Values) -> SafeDIMockScope_Api.Middle_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(middle: @escaping (middle_Values) -> SafeDIMockScope_Api.Middle_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.middle = middle
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(middle: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            middle: __safeDI_App_Middle_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                middle: middle
		            )
		        }

		        public var middle: __safeDI_App_Middle_MockConfiguration { __safeDI_storage.middle }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                middle: __safeDI_App_Middle_MockConfiguration
		            ) {
		                self.middle = middle
		            }

		            let middle: __safeDI_App_Middle_MockConfiguration
		        }
		    }

		    public static func mock(
		        session: Session,
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        Root.__safeDI_mock(session: session, apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session: Session,
		        apiBuilder __safeDI_apiBuilder: Root.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_apiBuilder_middle = __safeDI_apiBuilder.middle(SafeDIMockScope_Api.middle_Values(session: session))
		        func __safeDI_middle() -> Middle {
		            _ = Detail.__safeDI_Detail_mock_761E40A8BF1136DD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_detailBuilder() -> Detail {
		                Detail.__safeDI_mock(session: session, apiBuilder: __safeDI_apiBuilder_middle.detailBuilder(SafeDIMockScope_Api.Middle_Scope.detailBuilder_Values()))
		            }
		            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		            return Middle.__safeDI_init(session: session, detailBuilder: detailBuilder, safeDIBuilder: safeDIOverrides.middle.safeDIBuilder)
		        }
		        let middle: Middle = __safeDI_middle()
		        return Root(session: session, middle: middle)
		    }
		}

		extension Root {
		    public enum __safeDI_Root_mock_13D6C92EB036F524 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Middle` is constructed within the public mock trees of module `App`.
		nonisolated public struct __safeDI_App_Middle_MockConfiguration {
		    public init(
		        _ safeDIBuilder: ((Session, Instantiator<Detail>) -> Middle)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    /// Overrides how `Middle` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Session, Instantiator<Detail>) -> Middle)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            safeDIBuilder: ((Session, Instantiator<Detail>) -> Middle)?
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let safeDIBuilder: ((Session, Instantiator<Detail>) -> Middle)?
		    }
		}

		extension Middle {
		    static func __safeDI_init(session: Session, detailBuilder: Instantiator<Detail>, safeDIBuilder: ((Session, Instantiator<Detail>) -> Middle)?) -> Middle {
		        if let safeDIBuilder { safeDIBuilder(session, detailBuilder) } else { Middle(session: session, detailBuilder: detailBuilder) }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersNoOverrideClosureForCalledMock_whenCallerFillsTwoPlacesOfOneBuilderWithFillsOfTheirOwn() async throws {
		// `Detail` builds two places of one hole type, `api` and `backupApi`, which `Root` fills with `Live`, one fill each. The
		// called `mock()` takes one builder for both, and no one fill stands for the other’s place, so `Root`’s overrides hold
		// no closure that builds `Detail`: they stay, empty. Each place gets its own `Live`, which reads the session.
		let modules = Self.twoPlaceModules(
			detail: [("api", "any Api"), ("backupApi", "any Api")],
			app: [
				Self.live,
				Self.overrideRoot(mockGeneration: "true"),
				"""
				func apisReadTheSession() -> String {
				    let session = Session()
				    let detail = Root.mock(session: session).detailBuilder.instantiate()
				    return "api reads the session \\((detail.api as? Live)?.session === session), backup api reads the session \\((detail.backupApi as? Live)?.session === session), apis distinct \\(detail.api !== detail.backupApi)"
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Detail {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {
		            public let session: Session
		        }

		        nonisolated public struct backupApi_Values {
		            public let session: Session
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
		                self.init(api: { _ in __safeDI_builder() }, backupApi: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    public static func mock(
		        session: Session,
		        apiBuilder: @escaping () -> any Api
		    ) -> Detail {
		        Detail.__safeDI_mock(session: session, apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session: Session,
		        apiBuilder __safeDI_apiBuilder: Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api>
		    ) -> Detail {
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values(session: session))
		        let backupApi: any Api = __safeDI_apiBuilder.backupApi(SafeDIMockScope_Api.backupApi_Values(session: session, api: api))
		        return Detail(session: session, api: api, backupApi: backupApi)
		    }
		}

		extension Detail {
		    public enum __safeDI_Detail_mock_7CE761B28FACF33D {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init() {}
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        session: Session,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_detailBuilder() -> Detail {
		            func __safeDI_apiBuilder_Detail() -> Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(
		                    api: { scope in
		                        let session = scope.session
		                        let api: any Api = Live(session: session)
		                        return api
		                    },
		                    backupApi: { scope in
		                        let session = scope.session
		                        let backupApi: any Api = Live(session: session)
		                        return backupApi
		                    }
		                )
		            }
		            _ = Detail.__safeDI_Detail_mock_7CE761B28FACF33D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Detail.__safeDI_mock(session: session, apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Detail())
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Root(session: session, detailBuilder: detailBuilder)
		    }
		}
		#endif
		"""])
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("apisReadTheSession()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			#expect(description == "probe apisReadTheSession()\nString \"api reads the session true, backup api reads the session true, apis distinct true\"\n")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsOverrideClosureFunctionOverEachBuildersFill_whenCallerFillsOnePlaceOfEachOfTwoBuilders() async throws {
		// `Detail` builds one place of each of two hole types, which `Root` fills with `Live` and `LiveStore`, each reading the
		// session. Each builder has one fill, so `Root`’s overrides keep the closure, handed a function over each fill, which a
		// written closure passes on to `Detail.mock`.
		let modules = Self.twoPlaceModules(
			detail: [("api", "any Api"), ("store", "any Store")],
			app: [
				Self.live,
				"""
				@Instantiable(fulfillingAdditionalTypes: [Store.self])
				public final class LiveStore: Instantiable, Store {
				    public init(session: Session) {
				        self.session = session
				    }

				    @Received public let session: Session
				}
				""",
				Self.overrideRoot(mockGeneration: "true"),
				"""
				func overrideBuildsDetail() -> String {
				    var calls = 0
				    let session = Session()
				    let root = Root.mock(session: session, safeDIOverrides: .init(detailBuilder: { session, apiBuilder, storeBuilder in
				        calls += 1
				        return Detail.mock(session: session, apiBuilder: apiBuilder, storeBuilder: storeBuilder)
				    }))
				    let detail = root.detailBuilder.instantiate()
				    return "override called \\(calls), api reads the session \\((detail.api as? Live)?.session === session), store reads the session \\((detail.store as? LiveStore)?.session === session)"
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Detail {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {
		            public let session: Session
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    nonisolated public enum SafeDIMockScope_Store {
		        nonisolated public struct store_Values {
		            public let session: Session
		            public let api: any Api
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let store: (store_Values) -> __safeDI_Built

		            public init(store: @escaping (store_Values) -> __safeDI_Built) {
		                self.store = store
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(store: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    public static func mock(
		        session: Session,
		        apiBuilder: @escaping () -> any Api,
		        storeBuilder: @escaping () -> any Store
		    ) -> Detail {
		        Detail.__safeDI_mock(session: session, apiBuilder: .init(__safeDI_noScope: apiBuilder), storeBuilder: .init(__safeDI_noScope: storeBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session: Session,
		        apiBuilder __safeDI_apiBuilder: Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        storeBuilder __safeDI_storeBuilder: Detail.SafeDIMockScope_Store.__safeDI_Builder<any Store>
		    ) -> Detail {
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values(session: session))
		        let store: any Store = __safeDI_storeBuilder.store(SafeDIMockScope_Store.store_Values(session: session, api: api))
		        return Detail(session: session, api: api, store: store)
		    }
		}

		extension Detail {
		    public enum __safeDI_Detail_mock_6C3ED472A6890403 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            detailBuilder: ((Session, @escaping () -> any Api, @escaping () -> any Store) -> Detail)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                detailBuilder: detailBuilder
		            )
		        }

		        var detailBuilder: ((Session, @escaping () -> any Api, @escaping () -> any Store) -> Detail)? { __safeDI_storage.detailBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                detailBuilder: ((Session, @escaping () -> any Api, @escaping () -> any Store) -> Detail)?
		            ) {
		                self.detailBuilder = detailBuilder
		            }

		            let detailBuilder: ((Session, @escaping () -> any Api, @escaping () -> any Store) -> Detail)?
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        session: Session,
		        storeBuilder: (() -> any Store)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_detailBuilder() -> Detail {
		            func __safeDI_apiBuilder_Detail_api(session: Session) -> any Api {
		                let api: any Api = Live(session: session)
		                return api
		            }
		            func __safeDI_storeBuilder_Detail_store(session: Session) -> any Store {
		                let store: any Store = LiveStore(session: session)
		                return store
		            }
		            func __safeDI_apiBuilder_Detail() -> Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { values in __safeDI_apiBuilder_Detail_api(session: values.session) })
		            }
		            func __safeDI_storeBuilder_Detail() -> Detail.SafeDIMockScope_Store.__safeDI_Builder<any Store> {
		                .init(store: { values in __safeDI_storeBuilder_Detail_store(session: values.session) })
		            }
		            _ = Detail.__safeDI_Detail_mock_6C3ED472A6890403.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.detailBuilder { safeDIBuilder(session, { if let apiBuilder { apiBuilder() } else { __safeDI_apiBuilder_Detail_api(session: session) } }, { if let storeBuilder { storeBuilder() } else { __safeDI_storeBuilder_Detail_store(session: session) } }) } else { Detail.__safeDI_mock(session: session, apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Detail(), storeBuilder: storeBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_storeBuilder_Detail()) }
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Root(session: session, detailBuilder: detailBuilder)
		    }
		}
		#endif
		"""])
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("overrideBuildsDetail()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			#expect(description == "probe overrideBuildsDetail()\nString \"override called 1, api reads the session true, store reads the session true\"\n")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesOneConfigurationWithClosureForCalledMock_whenPublicMockBuildsTypeThatCallsMockAtTwoPlaces() async throws {
		// `Root`, a public mock, builds `Middle` itself and again inside `Other`’s instantiator, and each `Middle` calls `Detail`’s
		// public mock, whose place `Root` fills with `Live`. Both places read one module-level configuration of `Middle`, whose
		// closure that builds `Detail` a written override sets at each place.
		let modules = Self.overrideModules(app: [
			Self.live,
			"""
			@Instantiable
			public final class Middle: Instantiable {
			    public init(session: Session, detailBuilder: Instantiator<Detail>) {
			        self.session = session
			        self.detailBuilder = detailBuilder
			    }

			    @Received public let session: Session
			    @Instantiated public let detailBuilder: Instantiator<Detail>
			}
			""",
			"""
			@Instantiable
			public final class Other: Instantiable {
			    public init(middleBuilder: Instantiator<Middle>) {
			        self.middleBuilder = middleBuilder
			    }

			    @Instantiated public let middleBuilder: Instantiator<Middle>
			}
			""",
			"""
			@Instantiable(generateMock: .public)
			public final class Root: Instantiable {
			    public init(session: Session, middle: Middle, other: Other) {
			        self.session = session
			        self.middle = middle
			        self.other = other
			    }

			    @Received public let session: Session
			    @Instantiated public let middle: Middle
			    @Instantiated public let other: Other
			}
			""",
			"""
			func overridesReachBothPlaces() -> String {
			    var calls = 0
			    let session = Session()
			    let detailBuilder: (Session, @escaping () -> any Api) -> Detail = { session, apiBuilder in
			        calls += 1
			        return Detail.mock(session: session, apiBuilder: apiBuilder)
			    }
			    let root = Root.mock(session: session, safeDIOverrides: .init(middle: .init(detailBuilder: detailBuilder), other: .init(middleBuilder: .init(detailBuilder: detailBuilder))))
			    let first = root.middle.detailBuilder.instantiate()
			    let second = root.other.middleBuilder.instantiate().detailBuilder.instantiate()
			    return "override called \\(calls), apis read the session \\((first.api as? Live)?.session === session && (second.api as? Live)?.session === session)"
			}
			""",
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Detail {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {
		            public let session: Session
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    public static func mock(
		        session: Session,
		        apiBuilder: @escaping () -> any Api
		    ) -> Detail {
		        Detail.__safeDI_mock(session: session, apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session: Session,
		        apiBuilder __safeDI_apiBuilder: Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api>
		    ) -> Detail {
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values(session: session))
		        return Detail(session: session, api: api)
		    }
		}

		extension Detail {
		    public enum __safeDI_Detail_mock_761E40A8BF1136DD {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            middle: __safeDI_App_Middle_MockConfiguration = .init(),
		            other: __safeDI_App_Other_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                middle: middle,
		                other: other
		            )
		        }

		        public var middle: __safeDI_App_Middle_MockConfiguration { __safeDI_storage.middle }
		        public var other: __safeDI_App_Other_MockConfiguration { __safeDI_storage.other }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                middle: __safeDI_App_Middle_MockConfiguration,
		                other: __safeDI_App_Other_MockConfiguration
		            ) {
		                self.middle = middle
		                self.other = other
		            }

		            let middle: __safeDI_App_Middle_MockConfiguration
		            let other: __safeDI_App_Other_MockConfiguration
		        }
		    }

		    public static func mock(
		        session: Session,
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        Root.__safeDI_mock(session: session, apiBuilder: apiBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session: Session,
		        apiBuilder __safeDI_apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_middle() -> Middle {
		            func __safeDI_detailBuilder() -> Detail {
		                func __safeDI_apiBuilder_Detail_api(session: Session) -> any Api {
		                    let api: any Api = Live(session: session)
		                    return api
		                }
		                func __safeDI_apiBuilder_Detail() -> Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                    .init(api: { values in __safeDI_apiBuilder_Detail_api(session: values.session) })
		                }
		                _ = Detail.__safeDI_Detail_mock_761E40A8BF1136DD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                return if let safeDIBuilder = safeDIOverrides.middle.detailBuilder { safeDIBuilder(session, { if let __safeDI_apiBuilder { __safeDI_apiBuilder() } else { __safeDI_apiBuilder_Detail_api(session: session) } }) } else { Detail.__safeDI_mock(session: session, apiBuilder: __safeDI_apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Detail()) }
		            }
		            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		            return Middle.__safeDI_init(session: session, detailBuilder: detailBuilder, safeDIBuilder: safeDIOverrides.middle.safeDIBuilder)
		        }
		        let middle: Middle = __safeDI_middle()
		        func __safeDI_other() -> Other {
		            func __safeDI_middleBuilder() -> Middle {
		                func __safeDI_detailBuilder() -> Detail {
		                    func __safeDI_apiBuilder_Detail_api(session: Session) -> any Api {
		                        let api: any Api = Live(session: session)
		                        return api
		                    }
		                    func __safeDI_apiBuilder_Detail() -> Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                        .init(api: { values in __safeDI_apiBuilder_Detail_api(session: values.session) })
		                    }
		                    _ = Detail.__safeDI_Detail_mock_761E40A8BF1136DD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                    return if let safeDIBuilder = safeDIOverrides.other.middleBuilder.detailBuilder { safeDIBuilder(session, { if let __safeDI_apiBuilder { __safeDI_apiBuilder() } else { __safeDI_apiBuilder_Detail_api(session: session) } }) } else { Detail.__safeDI_mock(session: session, apiBuilder: __safeDI_apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Detail()) }
		                }
		                let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		                return Middle.__safeDI_init(session: session, detailBuilder: detailBuilder, safeDIBuilder: safeDIOverrides.other.middleBuilder.safeDIBuilder)
		            }
		            let middleBuilder = Instantiator<Middle>(__safeDI_middleBuilder)
		            return Other.__safeDI_init(middleBuilder: middleBuilder, safeDIBuilder: safeDIOverrides.other.safeDIBuilder)
		        }
		        let other: Other = __safeDI_other()
		        return Root(session: session, middle: middle, other: other)
		    }
		}

		extension Root {
		    public enum __safeDI_Root_mock_FC9E99C87ED246BA {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Middle` is constructed within the public mock trees of module `App`.
		nonisolated public struct __safeDI_App_Middle_MockConfiguration {
		    public init(
		        detailBuilder: ((Session, @escaping () -> any Api) -> Detail)? = nil,
		        _ safeDIBuilder: ((Session, Instantiator<Detail>) -> Middle)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            detailBuilder: detailBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var detailBuilder: ((Session, @escaping () -> any Api) -> Detail)? { __safeDI_storage.detailBuilder }
		    /// Overrides how `Middle` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Session, Instantiator<Detail>) -> Middle)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            detailBuilder: ((Session, @escaping () -> any Api) -> Detail)?,
		            safeDIBuilder: ((Session, Instantiator<Detail>) -> Middle)?
		        ) {
		            self.detailBuilder = detailBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let detailBuilder: ((Session, @escaping () -> any Api) -> Detail)?
		        let safeDIBuilder: ((Session, Instantiator<Detail>) -> Middle)?
		    }
		}

		extension Middle {
		    static func __safeDI_init(session: Session, detailBuilder: Instantiator<Detail>, safeDIBuilder: ((Session, Instantiator<Detail>) -> Middle)?) -> Middle {
		        if let safeDIBuilder { safeDIBuilder(session, detailBuilder) } else { Middle(session: session, detailBuilder: detailBuilder) }
		    }
		}

		/// Configuration for how `Other` is constructed within the public mock trees of module `App`.
		nonisolated public struct __safeDI_App_Other_MockConfiguration {
		    public init(
		        middleBuilder: __safeDI_App_Middle_MockConfiguration = .init(),
		        _ safeDIBuilder: ((Instantiator<Middle>) -> Other)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            middleBuilder: middleBuilder,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var middleBuilder: __safeDI_App_Middle_MockConfiguration { __safeDI_storage.middleBuilder }
		    /// Overrides how `Other` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Instantiator<Middle>) -> Other)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            middleBuilder: __safeDI_App_Middle_MockConfiguration,
		            safeDIBuilder: ((Instantiator<Middle>) -> Other)?
		        ) {
		            self.middleBuilder = middleBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let middleBuilder: __safeDI_App_Middle_MockConfiguration
		        let safeDIBuilder: ((Instantiator<Middle>) -> Other)?
		    }
		}

		extension Other {
		    static func __safeDI_init(middleBuilder: Instantiator<Middle>, safeDIBuilder: ((Instantiator<Middle>) -> Other)?) -> Other {
		        if let safeDIBuilder { safeDIBuilder(middleBuilder) } else { Other(middleBuilder: middleBuilder) }
		    }
		}
		#endif

		"""])
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("overridesReachBothPlaces()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			#expect(description == "probe overridesReachBothPlaces()\nString \"override called 2, apis read the session true\"\n")
		}
	}

	// MARK: Tests – a lazy value on a route, and a mocked type built again in its own tree

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsLazyValueWhenFillReadsIt_whenCallerFillsPlaceBeneathLazilyInstantiatedValues() async throws {
		// `Page`, a public mock in `Feed`, holds `logger` and `detail` lazily, and `Detail` holds `leaf` lazily, whose `api` is
		// the place. `Root` fills it with `LiveLogger`, which reads the page's logger: the logger is built when the leaf's
		// fill reads it, not when the detail opens, and the fill gets the page's own, as in one module.
		let modules = Self.countedModules(
			feed: """
			@Instantiable
			public final class Leaf: Counted, Instantiable {
			    init(api: any Api) {
			        self.api = api
			    }

			    @Instantiated public let api: any Api
			}

			@Instantiable
			public final class Detail: Counted, Instantiable {
			    init(leaf: LazilyInstantiated<Leaf>) {
			        self.leaf = leaf
			    }

			    @Instantiated public let leaf: LazilyInstantiated<Leaf>
			}

			@Instantiable(generateMock: .public)
			public final class Page: Counted, Instantiable {
			    init(navigator: Navigator, logger: LazilyInstantiated<Logger>, detail: LazilyInstantiated<Detail>) {
			        self.navigator = navigator
			        self.logger = logger
			        self.detail = detail
			    }

			    @Instantiated public let navigator: Navigator
			    @Instantiated public let logger: LazilyInstantiated<Logger>
			    @Instantiated public let detail: LazilyInstantiated<Detail>
			}
			""",
			app: [
				"""
				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public final class LiveLogger: Counted, Instantiable, Api {
				    public init(logger: Logger) {
				        self.logger = logger
				    }

				    @Received public let logger: Logger
				}
				""",
				Self.root(holding: "page: Page"),
				"""
				func loggerBuiltWhenLeafReadsIt() -> String {
				    var note = ""
				    do {
				        let page = Root.mock().page
				        let detail = page.detail.instance
				        page.navigator.stack.append(detail)
				        let builtBeforeLeaf = Counted.created["Logger", default: 0]
				        let leaf = detail.leaf.instance
				        page.navigator.stack.append(leaf)
				        note = "loggers built before the leaf \\(builtBeforeLeaf), the leaf’s logger is the page’s \\((leaf.api as? LiveLogger)?.logger === page.logger.instance)"
				    }
				    return note + ", alive after: " + Counted.alive.filter { $0.value != 0 }.sorted { $0.key < $1.key }.map { "\\($0.key) \\($0.value)" }.joined(separator: ", ")
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let probe = DifferentialValueProbe("loggerBuiltWhenLeafReadsIt()")
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
		let knownRight = try await knownRightDescription(of: modules, keeping: Set(modules.map(\.name)), probeSource: "", probe: probe)
		if compileVerificationIsEnabled {
			#expect(knownRight == "probe loggerBuiltWhenLeafReadsIt()\nString \"loggers built before the leaf 0, the leaf’s logger is the page’s true, alive after: \"\n")
			#expect(feature == knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_freesWhatKnownRightFrees_whenPublicMockBuildsItselfAgainAndCallerFillsItsPlace() async throws {
		// `Screen`, a public mock in `Feed`, builds itself again through `screenBuilder` and opens `Leaf`, whose `api` is the
		// place. `Root` fills it with `LiveCache`, which reads the nearest screen's cache. Each leaf reads its own screen's
		// cache, everything the probe built is freed when it drops it, and holding only the third screen keeps no other
		// screen's cache alive, as in one module.
		let modules = Self.countedModules(
			feed: """
			@Instantiable
			public final class Leaf: Counted, Instantiable {
			    init(api: any Api) {
			        self.api = api
			    }

			    @Instantiated public let api: any Api
			}

			@Instantiable(generateMock: .public)
			public final class Screen: Counted, Instantiable {
			    init(cache: Cache, navigator: Navigator, leafBuilder: Instantiator<Leaf>, screenBuilder: Instantiator<Screen>) {
			        self.cache = cache
			        self.navigator = navigator
			        self.leafBuilder = leafBuilder
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let cache: Cache
			    @Instantiated public let navigator: Navigator
			    @Instantiated public let leafBuilder: Instantiator<Leaf>
			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
			app: [
				"""
				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public final class LiveCache: Counted, Instantiable, Api {
				    public init(cache: Cache) {
				        self.cache = cache
				    }

				    @Received public let cache: Cache
				}
				""",
				Self.root(holding: "screen: Screen"),
				"""
				func leavesReadTheirScreensCaches() -> String {
				    var note = ""
				    do {
				        let screen1 = Root.mock().screen
				        let screen2 = screen1.screenBuilder.instantiate()
				        screen1.navigator.stack.append(screen2)
				        let screen3 = screen2.screenBuilder.instantiate()
				        screen2.navigator.stack.append(screen3)
				        let leaf3 = screen3.leafBuilder.instantiate()
				        screen1.navigator.stack.append(leaf3)
				        let leaf2 = screen2.leafBuilder.instantiate()
				        let leaf1 = screen1.leafBuilder.instantiate()
				        let caches = [leaf1, leaf2, leaf3].map { ($0.api as? LiveCache)?.cache }
				        note = "each leaf reads its own screen’s cache \\(caches[0] === screen1.cache && caches[1] === screen2.cache && caches[2] === screen3.cache)"
				    }
				    var screen3: Screen?
				    do {
				        let screen1 = Root.mock().screen
				        let screen2 = screen1.screenBuilder.instantiate()
				        screen3 = screen2.screenBuilder.instantiate()
				        _ = screen2.leafBuilder.instantiate()
				    }
				    let cachesWhileThirdScreenLives = withExtendedLifetime(screen3) { Counted.alive["Cache", default: 0] }
				    screen3 = nil
				    return note + ", caches alive while only the third screen is held \\(cachesWhileThirdScreenLives), alive after: " + Counted.alive.filter { $0.value != 0 }.sorted { $0.key < $1.key }.map { "\\($0.key) \\($0.value)" }.joined(separator: ", ")
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let probe = DifferentialValueProbe("leavesReadTheirScreensCaches()")
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
		let knownRight = try await knownRightDescription(of: modules, keeping: Set(modules.map(\.name)), probeSource: "", probe: probe)
		if compileVerificationIsEnabled {
			#expect(knownRight == "probe leavesReadTheirScreensCaches()\nString \"each leaf reads its own screen’s cache true, caches alive while only the third screen is held 1, alive after: \"\n")
			#expect(feature == knownRight)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Counted` keeps how many instances of each subclass are alive; `Navigator`, `Token` and `Logger` count.
	private static let chainCore = """
	import SafeDI

	public protocol Api: AnyObject {}

	open class Counted {
	    public init() { Counted.alive[String(describing: type(of: self)), default: 0] += 1 }
	    deinit { Counted.alive[String(describing: type(of: self)), default: 0] -= 1 }
	    nonisolated(unsafe) public static var alive = [String: Int]()
	}

	@Instantiable
	public final class Navigator: Counted, Instantiable {
	    public override init() {}
	    public var stack = [AnyObject]()
	}

	@Instantiable
	public final class Token: Counted, Instantiable {
	    public override init() {}
	}

	@Instantiable
	public final class Logger: Counted, Instantiable {
	    public override init() {}
	}
	"""

	/// `Fulfills `Api` in `App`, and receives the navigator of the `Hub` it is built in.
	private static let appApi = """
	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public final class AppApi: Counted, Instantiable, Api {
	    public init(navigator: Navigator) {
	        self.navigator = navigator
	    }

	    @Received public let navigator: Navigator
	}
	"""

	/// One place on two routes: `Model`’s `any Api` is reached through `Page`, which binds `token`, and straight from `Hub`,
	/// a public mock in `Feed`, which does not. `Shell`, a public mock in `Mid`, fills both routes with `LiveToken`, the
	/// second with the `token` its mock takes. With `sendable`, `Hub` builds both in `SendableInstantiator`s. With `outer`,
	/// `Outer`, a public mock in `Top`, builds `Shell`. Then `App`.
	private static func chainModules(sendable: Bool = false, outer: Bool = false, app: [String]) -> [ModuleFixture] {
		let instantiator = sendable ? "SendableInstantiator" : "Instantiator"
		// A `@Sendable` builder function captures the `token` a fill reads of its caller, so it must be `Sendable`.
		var modules = [
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [sendable ? chainCore + "\n\nextension Token: @unchecked Sendable {}\n" : chainCore]),
			ModuleFixture(name: "Feed", packageName: "Feed", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable
				public final class Model: Counted, Instantiable {
				    init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated public let api: any Api
				}

				@Instantiable
				public final class Page: Counted, Instantiable {
				    init(token: Token, modelBuilder: Instantiator<Model>) {
				        self.token = token
				        self.modelBuilder = modelBuilder
				    }

				    @Instantiated public let token: Token
				    @Instantiated public let modelBuilder: Instantiator<Model>
				}

				@Instantiable(generateMock: .public)
				public final class Hub: Counted, Instantiable {
				    init(navigator: Navigator, pageBuilder: \(instantiator)<Page>, modelBuilder: \(instantiator)<Model>) {
				        self.navigator = navigator
				        self.pageBuilder = pageBuilder
				        self.modelBuilder = modelBuilder
				    }

				    @Instantiated public let navigator: Navigator
				    @Instantiated public let pageBuilder: \(instantiator)<Page>
				    @Instantiated public let modelBuilder: \(instantiator)<Model>
				}
				""",
			], dependencies: ["Core"]),
			ModuleFixture(name: "Mid", packageName: "Mid", swiftFileContent: [
				"""
				import Core
				import Feed
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				final class LiveToken: Counted, Instantiable, Api {
				    init(token: Token) {
				        self.token = token
				    }

				    @Received let token: Token
				}

				@Instantiable(generateMock: .public)
				public final class Shell: Counted, Instantiable {
				    init(logger: Logger, hub: Hub) {
				        self.logger = logger
				        self.hub = hub
				    }

				    @Instantiated public let logger: Logger
				    @Instantiated public let hub: Hub
				}
				""",
			], dependencies: ["Core", "Feed"]),
		]
		if outer {
			modules.append(ModuleFixture(name: "Top", packageName: "Top", swiftFileContent: [
				"""
				import Core
				import Feed
				import Mid
				import SafeDI

				@Instantiable(generateMock: .public)
				public final class Outer: Counted, Instantiable {
				    init(shell: Shell) {
				        self.shell = shell
				    }

				    @Instantiated public let shell: Shell
				}
				""",
			], dependencies: ["Core", "Feed", "Mid"]))
		}
		let appDependencies = ["Core", "Feed", "Mid"] + (outer ? ["Top"] : [])
		modules.append(ModuleFixture(name: "App", packageName: "App", swiftFileContent: app.map { appDependencies.map { "import \($0)\n" }.joined() + "import SafeDI\n\n" + $0 }, dependencies: appDependencies))
		return modules
	}

	/// Opens a page and a model beside it on the hub `hub` builds, pushes them on its navigator (the model beside the page
	/// only when `pushesModelBesidePage`, since an `AppApi` there holds the navigator), opens the page’s model and pushes it
	/// too, drops everything, and reports each counted type still alive.
	private static func aliveAfterUse(hub: String, pushesModelBesidePage: Bool = true) -> String {
		"""
		func aliveAfterUse() -> String {
		    do {
		        let hub = \(hub)
		        let page = hub.pageBuilder.instantiate()
		        hub.navigator.stack.append(page)
		        let modelBesidePage = hub.modelBuilder.instantiate()
		        \(pushesModelBesidePage ? "hub.navigator.stack.append(modelBesidePage)" : "_ = modelBesidePage")
		        let modelInPage = page.modelBuilder.instantiate()
		        hub.navigator.stack.append(modelInPage)
		    }
		    return Counted.alive.filter { $0.value != 0 }.sorted { $0.key < $1.key }.map { "\\($0.key) \\($0.value)" }.joined(separator: ", ")
		}
		"""
	}

	/// Reports whether the `LiveApi` that `Root`’s mock builds holds `Outer`’s logger.
	private static let loggerProbe = """
	import Feature
	import SafeDI
	import Up

	func probeResult() -> String {
	    let root = Root.mock()
	    let api = root.outer.inner.detail.api as? LiveApi
	    return "logger is Outer’s: \\(api?.logger === root.outer.logger)"
	}
	"""

	/// Reports whether the `LiveApi` and the `Detail` that `Root`’s mock builds hold `Outer`’s logger and `Middle`’s tag.
	private static let loggerAndTagProbe = """
	import Feature
	import Mid
	import SafeDI
	import Up

	func probeResult() -> String {
	    let root = Root.mock()
	    let detail = root.outer.middle.inner.detailBuilder.instantiate()
	    let api = detail.api as? LiveApi
	    return "logger is Outer’s: \\(api?.logger === root.outer.logger); tag is Middle’s: \\(api?.tag === root.outer.middle.tag); detail.tag is Middle’s: \\(detail.tag === root.outer.middle.tag)"
	}
	"""

	/// Reports whether the `LiveApi` and the `Detail` that `Root`’s mock builds hold the instance of `Outer`’s lazy logger.
	private static let lazyLoggerProbe = """
	import Feature
	import SafeDI
	import Up

	func probeResult() -> String {
	    let root = Root.mock()
	    let detail = root.outer.inner.detailBuilder.instantiate()
	    let api = detail.api as? LiveApi
	    return "logger is Outer’s: \\(api?.logger === root.outer.logger.instance); detail.logger is Outer’s: \\(detail.logger === root.outer.logger.instance)"
	}
	"""

	/// `Live` fulfills `Api` in `App` and receives the session.
	private static let live = """
	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public final class Live: Instantiable, Api {
	    public init(session: Session) {
	        self.session = session
	    }

	    @Received public let session: Session
	}
	"""

	/// `Root`, whose mock, generated as `mockGeneration` says, receives `session`, which its mock cannot build, and builds
	/// `Detail` in an instantiator.
	private static func overrideRoot(mockGeneration: String) -> String {
		"""
		@Instantiable(generateMock: \(mockGeneration))
		public final class Root: Instantiable {
		    public init(session: Session, detailBuilder: Instantiator<Detail>) {
		        self.session = session
		        self.detailBuilder = detailBuilder
		    }

		    @Received public let session: Session
		    @Instantiated public let detailBuilder: Instantiator<Detail>
		}
		"""
	}

	/// `Host`, whose internal mock builds `Root`.
	private static let host = """
	@Instantiable(generateMock: true)
	public final class Host: Instantiable {
	    public init(root: Root) {
	        self.root = root
	    }

	    @Instantiated public let root: Root
	}
	"""

	/// `Detail`, a public mock in `Feature` that receives `session`, which no module builds, and builds nothing but its
	/// place; then `App`, and, where `top` holds any file, `Top`, which depends on both.
	private static func overrideModules(app: [String], top: [String] = []) -> [ModuleFixture] {
		var modules = [
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				"""
				import SafeDI

				public protocol Api: AnyObject {}

				public final class Session {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public final class Detail: Instantiable {
				    init(session: Session, api: any Api) {
				        self.session = session
				        self.api = api
				    }

				    @Received public let session: Session
				    @Instantiated public let api: any Api
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: app.map { "import Feature\nimport SafeDI\n\n" + $0 }, dependencies: ["Feature"]),
		]
		if !top.isEmpty {
			modules.append(ModuleFixture(name: "Top", packageName: "Top", swiftFileContent: top.map { "import App\nimport Feature\nimport SafeDI\n\n" + $0 }, dependencies: ["Feature", "App"]))
		}
		return modules
	}

	/// `Detail`, a public mock in `Feature` that receives `session`, which no module builds, and builds two places, `store`
	/// before `api`; then `App`.
	private static func storeModules(app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				"""
				import SafeDI

				public protocol Api: AnyObject {}

				public protocol Store: AnyObject {}

				public final class Session {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public final class Detail: Instantiable {
				    init(session: Session, store: any Store, api: any Api) {
				        self.session = session
				        self.store = store
				        self.api = api
				    }

				    @Received public let session: Session
				    @Instantiated public let store: any Store
				    @Instantiated public let api: any Api
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: app.map { "import Feature\nimport SafeDI\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// `Detail`, a public mock in `Feature` that receives `session`, which no module builds, and builds a place for each of
	/// `detail`’s labels and types; then `App`.
	private static func twoPlaceModules(detail places: [(label: String, type: String)], app: [String]) -> [ModuleFixture] {
		let parameters = places.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
		let assignments = places.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n")
		let declarations = places.map { "    @Instantiated public let \($0.label): \($0.type)" }.joined(separator: "\n")
		return [
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				"""
				import SafeDI

				public protocol Api: AnyObject {}

				public protocol Store: AnyObject {}

				public final class Session {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public final class Detail: Instantiable {
				    init(session: Session, \(parameters)) {
				        self.session = session
				\(assignments)
				    }

				    @Received public let session: Session
				\(declarations)
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: app.map { "import Feature\nimport SafeDI\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// `LiveApi` fulfills `Api` in `App` and receives the store.
	private static let liveApiReadingStore = """
	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public final class LiveApi: Instantiable, Api {
	    public init(store: any Store) {
	        self.store = store
	    }

	    @Received public let store: any Store
	}
	"""

	/// Reports whether the `LiveApi` of the `Detail` that `root` builds holds that detail’s store.
	private static func apiReadsDetailsStore(root: String) -> String {
		"""
		func apiReadsDetailsStore() -> String {
		    let detail = \(root).detailBuilder.instantiate()
		    return "api reads the detail’s store \\((detail.api as? LiveApi)?.store === detail.store)"
		}
		"""
	}

	/// `Counted` keeps how many instances of each subclass are alive and were built; `Navigator`, `Logger` and `Cache` count.
	private static let countedCore = """
	import SafeDI

	public protocol Api: AnyObject {}

	open class Counted {
	    public init() {
	        Counted.alive[String(describing: type(of: self)), default: 0] += 1
	        Counted.created[String(describing: type(of: self)), default: 0] += 1
	    }

	    deinit { Counted.alive[String(describing: type(of: self)), default: 0] -= 1 }
	    nonisolated(unsafe) public static var alive = [String: Int]()
	    nonisolated(unsafe) public static var created = [String: Int]()
	}

	@Instantiable
	public final class Navigator: Counted, Instantiable {
	    public override init() {}
	    public var stack = [AnyObject]()
	}

	@Instantiable
	public final class Logger: Counted, Instantiable {
	    public override init() {}
	}

	@Instantiable
	public final class Cache: Counted, Instantiable {
	    public override init() {}
	}
	"""

	/// `Core`, holding `countedCore`; `Feed`, holding `feed`; and `App`.
	private static func countedModules(feed: String, app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [countedCore]),
			ModuleFixture(name: "Feed", packageName: "Feed", swiftFileContent: ["import Core\nimport SafeDI\n\n" + feed], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: app.map { "import Core\nimport Feed\nimport SafeDI\n\n" + $0 }, dependencies: ["Core", "Feed"]),
		]
	}

	private static let core = """
	import SafeDI

	public protocol Api: AnyObject {}
	"""

	/// `Shell`, a public mock in `Mid` that builds `Home`.
	private static let shell = """
	@Instantiable(generateMock: .public)
	public final class Shell: Instantiable {
	    init(home: Home) {
	        self.home = home
	    }

	    @Instantiated public let home: Home
	}
	"""

	private static let stubApi = """
	final class StubApi: Api {}
	"""

	/// `Root`, whose internal mock calls the public mock of what it holds, `property`.
	private static func root(holding property: String) -> String {
		"""
		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(\(property)) {
		        self.\(property.prefix { $0 != ":" }) = \(property.prefix { $0 != ":" })
		    }

		    @Instantiated public let \(property)
		}
		"""
	}

	/// Builds three steps of the home `home` builds, from a builder named `builder`, each in the screen the last one opens,
	/// and reports how often the builder ran and whether each step holds its own `Api`.
	private static func stepsEachHoldTheirOwnApi(home: String) -> String {
		"""
		func stepsEachHoldTheirOwnApi() -> String {
		    var runs = 0
		    let builder: () -> any Api = {
		        runs += 1
		        return StubApi()
		    }
		    let home = \(home)
		    let firstStep = home.screen.stepBuilder.instantiate()
		    let secondStep = firstStep.screenBuilder.instantiate().stepBuilder.instantiate()
		    let thirdStep = secondStep.screenBuilder.instantiate().stepBuilder.instantiate()
		    let distinct = firstStep.api !== secondStep.api && secondStep.api !== thirdStep.api && firstStep.api !== thirdStep.api
		    return "builder runs \\(runs), each step its own api \\(distinct)"
		}
		"""
	}

	/// Holds only the step of the second screen of the home `home` builds, and reports the caches alive.
	private static func cachesWhileSecondStepLives(home: String) -> String {
		"""
		func cachesWhileSecondStepLives() -> String {
		    var step: Step?
		    do {
		        let secondScreen = \(home).screen.stepBuilder.instantiate().screenBuilder.instantiate()
		        step = secondScreen.stepBuilder.instantiate()
		    }
		    return withExtendedLifetime(step) { "Cache \\(Cache.alive)" }
		}
		"""
	}

	/// `Home`, a public mock in module `Feat` that builds `Screen`, which builds `cache` and opens `Step`, whose `api` is the
	/// place and which builds `Screen` again; then module `Mid`, and `App`.
	private static func screenLoopModules(mid: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [core]),
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable
				public final class Cache: Instantiable {
				    public init() {
				        Cache.created += 1
				        number = Cache.created
				        Cache.alive += 1
				    }

				    deinit { Cache.alive -= 1 }
				    public let number: Int
				    nonisolated(unsafe) public static var alive = 0
				    nonisolated(unsafe) public static var created = 0
				}

				@Instantiable
				public final class Step: Instantiable {
				    init(api: any Api, screenBuilder: Instantiator<Screen>) {
				        self.api = api
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated public let api: any Api
				    @Instantiated public let screenBuilder: Instantiator<Screen>
				}

				@Instantiable
				public final class Screen: Instantiable {
				    init(cache: Cache, stepBuilder: Instantiator<Step>) {
				        self.cache = cache
				        self.stepBuilder = stepBuilder
				    }

				    @Instantiated public let cache: Cache
				    @Instantiated public let stepBuilder: Instantiator<Step>
				}

				@Instantiable(generateMock: .public)
				public final class Home: Instantiable {
				    init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated public let screen: Screen
				}
				""",
			], dependencies: ["Core"]),
			ModuleFixture(name: "Mid", packageName: "Mid", swiftFileContent: mid.map { "import Core\nimport Feat\nimport SafeDI\n\n" + $0 }, dependencies: ["Core", "Feat"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: app.map { "import Core\nimport Feat\nimport Mid\nimport SafeDI\n\n" + $0 }, dependencies: ["Core", "Feat", "Mid"]),
		]
	}

	/// What `probe` describes in known-right: the declarations of the modules of `modules` named in `keptModuleNames` in one
	/// module, beside `probeSource`, which declares what that module’s probe needs of the other modules’ declarations.
	private mutating func knownRightDescription(of modules: [ModuleFixture], keeping keptModuleNames: Set<String>, probeSource: String, probe: DifferentialValueProbe) async throws -> String? {
		let moduleNames = Set(modules.map(\.name))
		var inlineFiles = [String: String]()
		for module in modules where keptModuleNames.contains(module.name) {
			for (index, content) in module.swiftFileContent.enumerated() {
				inlineFiles["\(module.name)_File\(index).swift"] = content
					.split(separator: "\n", omittingEmptySubsequences: false)
					.filter { line in !moduleNames.contains { line == "import \($0)" } }
					.joined(separator: "\n")
			}
		}
		inlineFiles["Probe.swift"] = "import SafeDI\n\n" + probeSource
		let inlineModules = [ModuleFixture(name: "KnownRight", packageName: "KnownRight", swiftFileContentByFilePath: inlineFiles)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		return try await DifferentialValueOracle.describe(DifferentialValuePath(output: inlineOutput, modules: inlineModules), probes: [probe], filesToDelete: &filesToDelete)
	}
}
