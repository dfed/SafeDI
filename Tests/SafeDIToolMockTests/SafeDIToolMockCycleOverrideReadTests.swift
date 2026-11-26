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

/// A type a cycle of instantiators builds again has no `SafeDIOverrides` entry of its own, since its parent's
/// configuration has no field for the property that closes the cycle. It reads the overrides of the nearest type of its
/// kind above it, and so do the types it builds, so a mock's overrides hold however many times a test goes around the
/// loop (`MockLowering+CycleOverrides.swift`).
struct SafeDIToolMockCycleOverrideReadTests: ~Copyable {
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

	/// A `Screen` a `Step` builds again through `screenBuilder` reads the overrides of the `Screen` above it, as do the
	/// types it builds: its configuration has no field for `screenBuilder`, which closes the cycle.
	@Test
	mutating func mock_reopenedTypeReadsNearestSameTypeAncestorsOverrides_whenInstantiatorCycleBuildsItAgain() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Home: Instantiable {
				    public init(screen: Screen) { self.screen = screen }
				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable
				public struct Screen: Instantiable {
				    public init(cache: Cache, stepBuilder: Instantiator<Step>) {
				        self.cache = cache
				        self.stepBuilder = stepBuilder
				    }
				    @Instantiated let cache: Cache
				    @Instantiated let stepBuilder: Instantiator<Step>
				}
				""",
				"""
				@Instantiable
				public struct Step: Instantiable {
				    public init(model: Model, screenBuilder: Instantiator<Screen>) {
				        self.model = model
				        self.screenBuilder = screenBuilder
				    }
				    @Instantiated let model: Model
				    @Instantiated let screenBuilder: Instantiator<Screen>
				}
				""",
				"""
				@Instantiable
				public struct Model: Instantiable {
				    public init(cache: Cache) { self.cache = cache }
				    @Received let cache: Cache
				}
				""",
				"""
				@Instantiable
				public struct Cache: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Home+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: Screen.SafeDIMockConfiguration { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: Screen.SafeDIMockConfiguration
		            ) {
		                self.screen = screen
		            }

		            let screen: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_screen(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration, __safeDI_Step_configuration_nearest: Step.SafeDIMockConfiguration?) -> Screen {
		            let cache = if let safeDIBuilder = __safeDI_Screen_configuration.cache { safeDIBuilder() } else { Cache() }
		            let stepBuilder = Instantiator<Step> {
		                __safeDI_stepBuilder(cache: cache, __safeDI_Step_configuration: __safeDI_Step_configuration_nearest ?? __safeDI_Screen_configuration.stepBuilder, __safeDI_Screen_configuration_nearest: __safeDI_Screen_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(cache, stepBuilder) } else { Screen(cache: cache, stepBuilder: stepBuilder) }
		        }
		        func __safeDI_stepBuilder(cache: Cache, __safeDI_Step_configuration: Step.SafeDIMockConfiguration, __safeDI_Screen_configuration_nearest: Screen.SafeDIMockConfiguration?) -> Step {
		            let model = if let safeDIBuilder = __safeDI_Step_configuration.model { safeDIBuilder(cache) } else { Model(cache: cache) }
		            let screenBuilder = Instantiator<Screen> {
		                __safeDI_screen(__safeDI_Screen_configuration: __safeDI_Screen_configuration_nearest ?? Screen.SafeDIMockConfiguration(), __safeDI_Step_configuration_nearest: __safeDI_Step_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Step_configuration.safeDIBuilder { safeDIBuilder(model, screenBuilder) } else { Step(model: model, screenBuilder: screenBuilder) }
		        }
		        let screen: Screen = __safeDI_screen(__safeDI_Screen_configuration: safeDIOverrides.screen, __safeDI_Step_configuration_nearest: nil)
		        return Home(screen: screen)
		    }
		}
		#endif
		""")
	}

	/// Inside `@Sendable` builder functions the reopened `Screen` reads the same overrides, through the locals read before
	/// the outermost such function.
	@Test
	mutating func mock_reopenedTypeReadsNearestSameTypeAncestorsOverrides_whenSendableInstantiatorCycleBuildsItAgain() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Home: Instantiable, Sendable {
				    public init(screen: Screen) { self.screen = screen }
				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable
				public struct Screen: Instantiable, Sendable {
				    public init(cache: Cache, stepBuilder: SendableInstantiator<Step>) {
				        self.cache = cache
				        self.stepBuilder = stepBuilder
				    }
				    @Instantiated let cache: Cache
				    @Instantiated let stepBuilder: SendableInstantiator<Step>
				}
				""",
				"""
				@Instantiable
				public struct Step: Instantiable, Sendable {
				    public init(model: Model, screenBuilder: SendableInstantiator<Screen>) {
				        self.model = model
				        self.screenBuilder = screenBuilder
				    }
				    @Instantiated let model: Model
				    @Instantiated let screenBuilder: SendableInstantiator<Screen>
				}
				""",
				"""
				@Instantiable
				public struct Model: Instantiable, Sendable {
				    public init(cache: Cache) { self.cache = cache }
				    @Received let cache: Cache
				}
				""",
				"""
				@Instantiable
				public struct Cache: Instantiable, Sendable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Home+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: Screen.SafeDIMockConfiguration { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                screen: Screen.SafeDIMockConfiguration
		            ) {
		                self.screen = screen
		            }

		            let screen: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        @Sendable nonisolated func __safeDI_stepBuilder(cache: Cache, __safeDI_Step_configuration: Step.SafeDIMockConfiguration, __safeDI_Screen_configuration_nearest: Screen.SafeDIMockConfiguration?) -> Step {
		            let model = if let safeDIBuilder = __safeDI_Step_configuration.model { safeDIBuilder(cache) } else { Model(cache: cache) }
		            let screenBuilder = SendableInstantiator<Screen> {
		                __safeDI_screenBuilder(__safeDI_Screen_configuration: __safeDI_Screen_configuration_nearest ?? Screen.SafeDIMockConfiguration(), __safeDI_Step_configuration_nearest: __safeDI_Step_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Step_configuration.safeDIBuilder { safeDIBuilder(model, screenBuilder) } else { Step(model: model, screenBuilder: screenBuilder) }
		        }
		        @Sendable nonisolated func __safeDI_screenBuilder(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration, __safeDI_Step_configuration_nearest: Step.SafeDIMockConfiguration?) -> Screen {
		            let cache = if let safeDIBuilder = __safeDI_Screen_configuration.cache { safeDIBuilder() } else { Cache() }
		            let stepBuilder = SendableInstantiator<Step> {
		                __safeDI_stepBuilder(cache: cache, __safeDI_Step_configuration: __safeDI_Step_configuration_nearest ?? __safeDI_Screen_configuration.stepBuilder, __safeDI_Screen_configuration_nearest: __safeDI_Screen_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(cache, stepBuilder) } else { Screen(cache: cache, stepBuilder: stepBuilder) }
		        }
		        func __safeDI_screen(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration, __safeDI_Step_configuration_nearest: Step.SafeDIMockConfiguration?) -> Screen {
		            let cache = if let safeDIBuilder = __safeDI_Screen_configuration.cache { safeDIBuilder() } else { Cache() }
		            let __safeDI_stepBuilder____safeDI_Step_configuration: Step.SafeDIMockConfiguration = __safeDI_Step_configuration_nearest ?? __safeDI_Screen_configuration.stepBuilder
		            let stepBuilder = SendableInstantiator<Step> {
		                __safeDI_stepBuilder(cache: cache, __safeDI_Step_configuration: __safeDI_stepBuilder____safeDI_Step_configuration, __safeDI_Screen_configuration_nearest: __safeDI_Screen_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(cache, stepBuilder) } else { Screen(cache: cache, stepBuilder: stepBuilder) }
		        }
		        let screen: Screen = __safeDI_screen(__safeDI_Screen_configuration: safeDIOverrides.screen, __safeDI_Step_configuration_nearest: nil)
		        return Home(screen: screen)
		    }
		}
		#endif
		""")
	}

	/// Two properties of `Step` build `Screen` again, and both read the `Screen` above them outside `Step`'s configuration: each override is read into one local, which both construction functions read.
	@Test
	mutating func mock_readsEachOverrideIntoOneLocal_whenTwoSendablePropertiesBuildTypeAgainOutsideConfigurationPath() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Home: Instantiable, Sendable {
				    public init(screen: Screen) { self.screen = screen }
				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable
				public struct Screen: Instantiable, Sendable {
				    public init(cache: Cache, stepBuilder: SendableInstantiator<Step>) {
				        self.cache = cache
				        self.stepBuilder = stepBuilder
				    }
				    @Instantiated let cache: Cache
				    @Instantiated let stepBuilder: SendableInstantiator<Step>
				}
				""",
				"""
				@Instantiable
				public struct Step: Instantiable, Sendable {
				    public init(model: Model, screenBuilder: SendableInstantiator<Screen>, otherScreenBuilder: SendableInstantiator<Screen>) {
				        self.model = model
				        self.screenBuilder = screenBuilder
				        self.otherScreenBuilder = otherScreenBuilder
				    }
				    @Instantiated let model: Model
				    @Instantiated let screenBuilder: SendableInstantiator<Screen>
				    @Instantiated let otherScreenBuilder: SendableInstantiator<Screen>
				}
				""",
				"""
				@Instantiable
				public struct Model: Instantiable, Sendable {
				    public init(cache: Cache) { self.cache = cache }
				    @Received let cache: Cache
				}
				""",
				"""
				@Instantiable
				public struct Cache: Instantiable, Sendable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Home+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: Screen.SafeDIMockConfiguration { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                screen: Screen.SafeDIMockConfiguration
		            ) {
		                self.screen = screen
		            }

		            let screen: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        @Sendable nonisolated func __safeDI_stepBuilder(cache: Cache, __safeDI_Step_configuration: Step.SafeDIMockConfiguration, __safeDI_Screen_configuration_nearest: Screen.SafeDIMockConfiguration?) -> Step {
		            let model = if let safeDIBuilder = __safeDI_Step_configuration.model { safeDIBuilder(cache) } else { Model(cache: cache) }
		            let screenBuilder = SendableInstantiator<Screen> {
		                __safeDI_screenBuilder(__safeDI_Screen_configuration: __safeDI_Screen_configuration_nearest ?? Screen.SafeDIMockConfiguration(), __safeDI_Step_configuration_nearest: __safeDI_Step_configuration)
		            }
		            let otherScreenBuilder = SendableInstantiator<Screen> {
		                __safeDI_screenBuilder(__safeDI_Screen_configuration: __safeDI_Screen_configuration_nearest ?? Screen.SafeDIMockConfiguration(), __safeDI_Step_configuration_nearest: __safeDI_Step_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Step_configuration.safeDIBuilder { safeDIBuilder(model, screenBuilder, otherScreenBuilder) } else { Step(model: model, screenBuilder: screenBuilder, otherScreenBuilder: otherScreenBuilder) }
		        }
		        @Sendable nonisolated func __safeDI_screenBuilder(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration, __safeDI_Step_configuration_nearest: Step.SafeDIMockConfiguration?) -> Screen {
		            let cache = if let safeDIBuilder = __safeDI_Screen_configuration.cache { safeDIBuilder() } else { Cache() }
		            let stepBuilder = SendableInstantiator<Step> {
		                __safeDI_stepBuilder(cache: cache, __safeDI_Step_configuration: __safeDI_Step_configuration_nearest ?? __safeDI_Screen_configuration.stepBuilder, __safeDI_Screen_configuration_nearest: __safeDI_Screen_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(cache, stepBuilder) } else { Screen(cache: cache, stepBuilder: stepBuilder) }
		        }
		        func __safeDI_screen(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration, __safeDI_Step_configuration_nearest: Step.SafeDIMockConfiguration?) -> Screen {
		            let cache = if let safeDIBuilder = __safeDI_Screen_configuration.cache { safeDIBuilder() } else { Cache() }
		            let __safeDI_stepBuilder____safeDI_Step_configuration: Step.SafeDIMockConfiguration = __safeDI_Step_configuration_nearest ?? __safeDI_Screen_configuration.stepBuilder
		            let stepBuilder = SendableInstantiator<Step> {
		                __safeDI_stepBuilder(cache: cache, __safeDI_Step_configuration: __safeDI_stepBuilder____safeDI_Step_configuration, __safeDI_Screen_configuration_nearest: __safeDI_Screen_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(cache, stepBuilder) } else { Screen(cache: cache, stepBuilder: stepBuilder) }
		        }
		        let screen: Screen = __safeDI_screen(__safeDI_Screen_configuration: safeDIOverrides.screen, __safeDI_Step_configuration_nearest: nil)
		        return Home(screen: screen)
		    }
		}
		#endif
		""")
	}

	/// A public mock hands the reopened `Screen`'s construction function the overrides of the `Screen` above it.
	@Test
	mutating func publicMock_reopenedTypeReadsNearestSameTypeAncestorsOverrides_whenInstantiatorCycleBuildsItAgain() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Home: Instantiable {
				    public init(screen: Screen) { self.screen = screen }
				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable
				public struct Screen: Instantiable {
				    public init(cache: Cache, stepBuilder: Instantiator<Step>) {
				        self.cache = cache
				        self.stepBuilder = stepBuilder
				    }
				    @Instantiated let cache: Cache
				    @Instantiated let stepBuilder: Instantiator<Step>
				}
				""",
				"""
				@Instantiable
				public struct Step: Instantiable {
				    public init(model: Model, screenBuilder: Instantiator<Screen>) {
				        self.model = model
				        self.screenBuilder = screenBuilder
				    }
				    @Instantiated let model: Model
				    @Instantiated let screenBuilder: Instantiator<Screen>
				}
				""",
				"""
				@Instantiable
				public struct Model: Instantiable {
				    public init(cache: Cache) { self.cache = cache }
				    @Received let cache: Cache
				}
				""",
				"""
				@Instantiable
				public struct Cache: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Home+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            screen: __safeDI_Screen_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        public var screen: __safeDI_Screen_MockConfiguration { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: __safeDI_Screen_MockConfiguration
		            ) {
		                self.screen = screen
		            }

		            let screen: __safeDI_Screen_MockConfiguration
		        }
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        Home.__safeDI_mock(safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_screen() -> Screen {
		            let cache = if let safeDIBuilder = safeDIOverrides.screen.cache { safeDIBuilder() } else { Cache() }
		            func __safeDI_stepBuilder(cache: Cache) -> Step {
		                let model = if let safeDIBuilder = safeDIOverrides.screen.stepBuilder.model { safeDIBuilder(cache) } else { Model(cache: cache) }
		                func __safeDI_screenBuilder() -> Screen {
		                    let cache = if let safeDIBuilder = safeDIOverrides.screen.cache { safeDIBuilder() } else { Cache() }
		                    let stepBuilder = Instantiator<Step> {
		                        __safeDI_stepBuilder(cache: cache)
		                    }
		                    return Screen.__safeDI_init(cache: cache, stepBuilder: stepBuilder, safeDIBuilder: safeDIOverrides.screen.safeDIBuilder)
		                }
		                let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                return Step.__safeDI_init(model: model, screenBuilder: screenBuilder, safeDIBuilder: safeDIOverrides.screen.stepBuilder.safeDIBuilder)
		            }
		            let stepBuilder = Instantiator<Step> {
		                __safeDI_stepBuilder(cache: cache)
		            }
		            return Screen.__safeDI_init(cache: cache, stepBuilder: stepBuilder, safeDIBuilder: safeDIOverrides.screen.safeDIBuilder)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_mock_51799E6AA5E7B634 {}
		}
		#endif
		""")
	}

	/// Of two `Screen`s the mocked type builds, each one the cycle builds again reads the overrides of its own nearest
	/// `Screen`, never the other property's.
	@Test
	mutating func mock_eachReopenedTypeReadsItsOwnNearestAncestorsOverrides_whenTwoPropertiesBuildTheCycle() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Home: Instantiable {
				    public init(primary: Screen, secondary: Screen) {
				        self.primary = primary
				        self.secondary = secondary
				    }
				    @Instantiated let primary: Screen
				    @Instantiated let secondary: Screen
				}
				""",
				"""
				@Instantiable
				public struct Screen: Instantiable {
				    public init(cache: Cache, stepBuilder: Instantiator<Step>) {
				        self.cache = cache
				        self.stepBuilder = stepBuilder
				    }
				    @Instantiated let cache: Cache
				    @Instantiated let stepBuilder: Instantiator<Step>
				}
				""",
				"""
				@Instantiable
				public struct Step: Instantiable {
				    public init(model: Model, screenBuilder: Instantiator<Screen>) {
				        self.model = model
				        self.screenBuilder = screenBuilder
				    }
				    @Instantiated let model: Model
				    @Instantiated let screenBuilder: Instantiator<Screen>
				}
				""",
				"""
				@Instantiable
				public struct Model: Instantiable {
				    public init(cache: Cache) { self.cache = cache }
				    @Received let cache: Cache
				}
				""",
				"""
				@Instantiable
				public struct Cache: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Home+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            primary: Screen.SafeDIMockConfiguration = .init(),
		            secondary: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                primary: primary,
		                secondary: secondary
		            )
		        }

		        var primary: Screen.SafeDIMockConfiguration { __safeDI_storage.primary }
		        var secondary: Screen.SafeDIMockConfiguration { __safeDI_storage.secondary }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                primary: Screen.SafeDIMockConfiguration,
		                secondary: Screen.SafeDIMockConfiguration
		            ) {
		                self.primary = primary
		                self.secondary = secondary
		            }

		            let primary: Screen.SafeDIMockConfiguration
		            let secondary: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_primary(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration, __safeDI_Step_configuration_nearest: Step.SafeDIMockConfiguration?) -> Screen {
		            let cache = if let safeDIBuilder = __safeDI_Screen_configuration.cache { safeDIBuilder() } else { Cache() }
		            let stepBuilder = Instantiator<Step> {
		                __safeDI_stepBuilder(cache: cache, __safeDI_Step_configuration: __safeDI_Step_configuration_nearest ?? __safeDI_Screen_configuration.stepBuilder, __safeDI_Screen_configuration_nearest: __safeDI_Screen_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(cache, stepBuilder) } else { Screen(cache: cache, stepBuilder: stepBuilder) }
		        }
		        func __safeDI_stepBuilder(cache: Cache, __safeDI_Step_configuration: Step.SafeDIMockConfiguration, __safeDI_Screen_configuration_nearest: Screen.SafeDIMockConfiguration?) -> Step {
		            let model = if let safeDIBuilder = __safeDI_Step_configuration.model { safeDIBuilder(cache) } else { Model(cache: cache) }
		            let screenBuilder = Instantiator<Screen> {
		                __safeDI_primary(__safeDI_Screen_configuration: __safeDI_Screen_configuration_nearest ?? Screen.SafeDIMockConfiguration(), __safeDI_Step_configuration_nearest: __safeDI_Step_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Step_configuration.safeDIBuilder { safeDIBuilder(model, screenBuilder) } else { Step(model: model, screenBuilder: screenBuilder) }
		        }
		        let primary: Screen = __safeDI_primary(__safeDI_Screen_configuration: safeDIOverrides.primary, __safeDI_Step_configuration_nearest: nil)
		        let secondary: Screen = __safeDI_primary(__safeDI_Screen_configuration: safeDIOverrides.secondary, __safeDI_Step_configuration_nearest: nil)
		        return Home(primary: primary, secondary: secondary)
		    }
		}
		#endif
		""")
	}

	/// A `Ping` that `otherPingBuilder` builds and its `Pong` builds again reads the overrides of the `Ping` above it,
	/// through the locals read before the outermost `@Sendable` function: each override is read into one local, however
	/// many places read it.
	@Test
	mutating func mock_readsEachOverrideIntoOneLocal_whenSendableCycleBuildsTypeAgainBeneathSecondEntry() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Ping: Instantiable, Sendable {
				    public nonisolated init(label: String = "ping", pongBuilder: SendableInstantiator<Pong>) {
				        self.label = label
				        self.pongBuilder = pongBuilder
				    }

				    public let label: String
				    @Instantiated public let pongBuilder: SendableInstantiator<Pong>
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Pong: Instantiable, Sendable {
				    public nonisolated init(label: String = "pong", pingBuilder: SendableInstantiator<Ping>) {
				        self.label = label
				        self.pingBuilder = pingBuilder
				    }

				    public let label: String
				    @Instantiated public let pingBuilder: SendableInstantiator<Ping>
				}
				""",
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Game: Instantiable {
				    public init(pingBuilder: SendableInstantiator<Ping>, otherPingBuilder: SendableInstantiator<Ping>) {
				        self.pingBuilder = pingBuilder
				        self.otherPingBuilder = otherPingBuilder
				    }

				    @Instantiated let pingBuilder: SendableInstantiator<Ping>
				    @Instantiated let otherPingBuilder: SendableInstantiator<Ping>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Game+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Game {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            pingBuilder: Ping.SafeDIMockConfiguration = .init(),
		            otherPingBuilder: Ping.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                pingBuilder: pingBuilder,
		                otherPingBuilder: otherPingBuilder
		            )
		        }

		        var pingBuilder: Ping.SafeDIMockConfiguration { __safeDI_storage.pingBuilder }
		        var otherPingBuilder: Ping.SafeDIMockConfiguration { __safeDI_storage.otherPingBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                pingBuilder: Ping.SafeDIMockConfiguration,
		                otherPingBuilder: Ping.SafeDIMockConfiguration
		            ) {
		                self.pingBuilder = pingBuilder
		                self.otherPingBuilder = otherPingBuilder
		            }

		            let pingBuilder: Ping.SafeDIMockConfiguration
		            let otherPingBuilder: Ping.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Game {
		        @Sendable nonisolated func __safeDI_pingBuilder(__safeDI_Ping_configuration: Ping.SafeDIMockConfiguration, __safeDI_Pong_configuration_nearest: Pong.SafeDIMockConfiguration?) -> Ping {
		            let pongBuilder = SendableInstantiator<Pong> {
		                __safeDI_pongBuilder(__safeDI_Pong_configuration: __safeDI_Pong_configuration_nearest ?? __safeDI_Ping_configuration.pongBuilder, __safeDI_Ping_configuration_nearest: __safeDI_Ping_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Ping_configuration.safeDIBuilder { safeDIBuilder(__safeDI_Ping_configuration.label(), pongBuilder) } else { Ping(label: __safeDI_Ping_configuration.label(), pongBuilder: pongBuilder) }
		        }
		        @Sendable nonisolated func __safeDI_pongBuilder(__safeDI_Pong_configuration: Pong.SafeDIMockConfiguration, __safeDI_Ping_configuration_nearest: Ping.SafeDIMockConfiguration?) -> Pong {
		            let pingBuilder = SendableInstantiator<Ping> {
		                __safeDI_pingBuilder(__safeDI_Ping_configuration: __safeDI_Ping_configuration_nearest ?? Ping.SafeDIMockConfiguration(), __safeDI_Pong_configuration_nearest: __safeDI_Pong_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Pong_configuration.safeDIBuilder { safeDIBuilder(__safeDI_Pong_configuration.label(), pingBuilder) } else { Pong(label: __safeDI_Pong_configuration.label(), pingBuilder: pingBuilder) }
		        }
		        let __safeDI_pingBuilder____safeDI_Ping_configuration: Ping.SafeDIMockConfiguration = safeDIOverrides.pingBuilder
		        let pingBuilder = SendableInstantiator<Ping> {
		            __safeDI_pingBuilder(__safeDI_Ping_configuration: __safeDI_pingBuilder____safeDI_Ping_configuration, __safeDI_Pong_configuration_nearest: nil)
		        }
		        let __safeDI_pingBuilder____safeDI_Ping_configuration_: Ping.SafeDIMockConfiguration = safeDIOverrides.otherPingBuilder
		        let otherPingBuilder = SendableInstantiator<Ping> {
		            __safeDI_pingBuilder(__safeDI_Ping_configuration: __safeDI_pingBuilder____safeDI_Ping_configuration_, __safeDI_Pong_configuration_nearest: nil)
		        }
		        return Game(pingBuilder: pingBuilder, otherPingBuilder: otherPingBuilder)
		    }
		}
		#endif
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
