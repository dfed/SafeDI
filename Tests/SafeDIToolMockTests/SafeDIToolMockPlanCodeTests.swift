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
@testable import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The code the type key lays out of a mock root's per-type plan (`MockPlanCodeObservation`): one function per body,
/// declared in `mock()`'s body, each call place a call of the body it calls handed its own configuration.
struct SafeDIToolMockPlanCodeTests: ~Copyable {
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
	mutating func mock_declaresOneFunctionPerBody_whenScreensOpenEachOther() async throws {
		// `Screen` and `Next` open each other beneath `Shell`: the plan has one body of each, whose functions take what their
		// trees read from above, `clock`, and the configuration each call hands.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(clock: Clock, shell: Shell) {
			        self.clock = clock
			        self.shell = shell
			    }

			    @Instantiated public let clock: Clock
			    @Instantiated public let shell: Shell
			}
			""",
			"Screens.swift": Self.clock + """

			@Instantiable
			public final class Shell: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}

			@Instantiable
			public final class Screen: Instantiable {
			    public init(clock: Clock, nextBuilder: Instantiator<Next>) {
			        self.clock = clock
			        self.nextBuilder = nextBuilder
			    }

			    @Received public let clock: Clock
			    @Instantiated public let nextBuilder: Instantiator<Next>
			}

			@Instantiable
			public final class Next: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root": "laidOut"])
		#expect(mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            clock: (() -> Clock)? = nil,
		            shell: Shell.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                clock: clock,
		                shell: shell
		            )
		        }

		        var clock: (() -> Clock)? { __safeDI_storage.clock }
		        var shell: Shell.SafeDIMockConfiguration { __safeDI_storage.shell }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                clock: (() -> Clock)?,
		                shell: Shell.SafeDIMockConfiguration
		            ) {
		                self.clock = clock
		                self.shell = shell
		            }

		            let clock: (() -> Clock)?
		            let shell: Shell.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let clock = if let safeDIBuilder = safeDIOverrides.clock { safeDIBuilder() } else { Clock() }
		        func __safeDI_screenBuilder(clock: Clock, __safeDI_Screen_configuration: Screen.SafeDIMockConfiguration) -> Screen {
		            let nextBuilder = Instantiator<Next> {
		                __safeDI_nextBuilder(clock: clock, __safeDI_Next_configuration: Next.SafeDIMockConfiguration(), __safeDI_Screen_configuration_nearest: __safeDI_Screen_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(clock, nextBuilder) } else { Screen(clock: clock, nextBuilder: nextBuilder) }
		        }
		        func __safeDI_nextBuilder(clock: Clock, __safeDI_Next_configuration: Next.SafeDIMockConfiguration, __safeDI_Screen_configuration_nearest: Screen.SafeDIMockConfiguration?) -> Next {
		            let screenBuilder = Instantiator<Screen> {
		                __safeDI_screenBuilder(clock: clock, __safeDI_Screen_configuration: __safeDI_Screen_configuration_nearest ?? Screen.SafeDIMockConfiguration())
		            }
		            return if let safeDIBuilder = __safeDI_Next_configuration.safeDIBuilder { safeDIBuilder(screenBuilder) } else { Next(screenBuilder: screenBuilder) }
		        }
		        func __safeDI_shell(__safeDI_Shell_configuration: Shell.SafeDIMockConfiguration) -> Shell {
		            let screenBuilder = Instantiator<Screen> {
		                __safeDI_screenBuilder(clock: clock, __safeDI_Screen_configuration: __safeDI_Shell_configuration.screenBuilder)
		            }
		            return if let safeDIBuilder = __safeDI_Shell_configuration.safeDIBuilder { safeDIBuilder(screenBuilder) } else { Shell(screenBuilder: screenBuilder) }
		        }
		        let shell: Shell = __safeDI_shell(__safeDI_Shell_configuration: safeDIOverrides.shell)
		        return Root(clock: clock, shell: shell)
		    }
		}
		#endif
		""")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().shell.screenBuilder.instantiate().nextBuilder.instantiate().screenBuilder.instantiate().clock.tag"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(clock: { Clock.tagged(1) })).shell.screenBuilder.instantiate().nextBuilder.instantiate().screenBuilder.instantiate().clock.tag"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(shell: .init(screenBuilder: .init { clock, nextBuilder in Screen(clock: Clock.tagged(clock.tag + 2), nextBuilder: nextBuilder) }))).shell.screenBuilder.instantiate().nextBuilder.instantiate().screenBuilder.instantiate().clock.tag"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesOverrideClosureAsParameter_whenBodysNodeHasNoConfiguration() async throws {
		// `Badge` has no dependency, so its place reads an override closure: its body's function takes that closure, optional,
		// and the call beneath the cycle hands the nearest `Screen`'s field of it.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
			"Screens.swift": """
			@Instantiable
			public final class Badge: Instantiable, Sendable {
			    public init() {
			        tag = 0
			    }

			    public let tag: Int

			    private init(tag: Int) {
			        self.tag = tag
			    }

			    public static func tagged(_ tag: Int) -> Badge {
			        Badge(tag: tag)
			    }
			}

			@Instantiable
			public final class Screen: Instantiable {
			    public init(badgeBuilder: Instantiator<Badge>, nextBuilder: Instantiator<Next>) {
			        self.badgeBuilder = badgeBuilder
			        self.nextBuilder = nextBuilder
			    }

			    @Instantiated public let badgeBuilder: Instantiator<Badge>
			    @Instantiated public let nextBuilder: Instantiator<Next>
			}

			@Instantiable
			public final class Next: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root": "laidOut"])
		#expect(mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder
		            )
		        }

		        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screenBuilder: Screen.SafeDIMockConfiguration
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_screenBuilder(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration) -> Screen {
		            let badgeBuilder = Instantiator<Badge> {
		                __safeDI_badgeBuilder(__safeDI_Badge_configuration: __safeDI_Screen_configuration.badgeBuilder)
		            }
		            let nextBuilder = Instantiator<Next> {
		                __safeDI_nextBuilder(__safeDI_Next_configuration: Next.SafeDIMockConfiguration(), __safeDI_Screen_configuration_nearest: __safeDI_Screen_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(badgeBuilder, nextBuilder) } else { Screen(badgeBuilder: badgeBuilder, nextBuilder: nextBuilder) }
		        }
		        func __safeDI_nextBuilder(__safeDI_Next_configuration: Next.SafeDIMockConfiguration, __safeDI_Screen_configuration_nearest: Screen.SafeDIMockConfiguration?) -> Next {
		            let screenBuilder = Instantiator<Screen> {
		                __safeDI_screenBuilder(__safeDI_Screen_configuration: __safeDI_Screen_configuration_nearest ?? Screen.SafeDIMockConfiguration())
		            }
		            return if let safeDIBuilder = __safeDI_Next_configuration.safeDIBuilder { safeDIBuilder(screenBuilder) } else { Next(screenBuilder: screenBuilder) }
		        }
		        func __safeDI_badgeBuilder(__safeDI_Badge_configuration: (() -> Badge)?) -> Badge {
		            if let safeDIBuilder = __safeDI_Badge_configuration { safeDIBuilder() } else { Badge() }
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(__safeDI_Screen_configuration: safeDIOverrides.screenBuilder)
		        }
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().screenBuilder.instantiate().nextBuilder.instantiate().screenBuilder.instantiate().badgeBuilder.instantiate().tag"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(screenBuilder: .init(badgeBuilder: { Badge.tagged(1) }))).screenBuilder.instantiate().badgeBuilder.instantiate().tag"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(screenBuilder: .init(badgeBuilder: { Badge.tagged(2) }))).screenBuilder.instantiate().nextBuilder.instantiate().screenBuilder.instantiate().badgeBuilder.instantiate().tag"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsNearestConfigurationThroughBodyBetween_whenCloserClosesOnTypeTwoBodiesOut() async throws {
		// `Charlie` closes on `Alpha`, whose nearest place is two bodies out: `Bravo`'s function takes `Alpha`'s nearest
		// configuration only to hand it to `Charlie`'s.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(clock: Clock, alphaBuilder: Instantiator<Alpha>) {
			        self.clock = clock
			        self.alphaBuilder = alphaBuilder
			    }

			    @Instantiated public let clock: Clock
			    @Instantiated public let alphaBuilder: Instantiator<Alpha>
			}
			""",
			"Cycle.swift": Self.clock + """

			@Instantiable
			public final class Alpha: Instantiable {
			    public init(clock: Clock, bravoBuilder: Instantiator<Bravo>) {
			        self.clock = clock
			        self.bravoBuilder = bravoBuilder
			    }

			    @Received public let clock: Clock
			    @Instantiated public let bravoBuilder: Instantiator<Bravo>
			}

			@Instantiable
			public final class Bravo: Instantiable {
			    public init(charlieBuilder: Instantiator<Charlie>) {
			        self.charlieBuilder = charlieBuilder
			    }

			    @Instantiated public let charlieBuilder: Instantiator<Charlie>
			}

			@Instantiable
			public final class Charlie: Instantiable {
			    public init(alphaBuilder: Instantiator<Alpha>) {
			        self.alphaBuilder = alphaBuilder
			    }

			    @Instantiated public let alphaBuilder: Instantiator<Alpha>
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root": "laidOut"])
		#expect(mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            clock: (() -> Clock)? = nil,
		            alphaBuilder: Alpha.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                clock: clock,
		                alphaBuilder: alphaBuilder
		            )
		        }

		        var clock: (() -> Clock)? { __safeDI_storage.clock }
		        var alphaBuilder: Alpha.SafeDIMockConfiguration { __safeDI_storage.alphaBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                clock: (() -> Clock)?,
		                alphaBuilder: Alpha.SafeDIMockConfiguration
		            ) {
		                self.clock = clock
		                self.alphaBuilder = alphaBuilder
		            }

		            let clock: (() -> Clock)?
		            let alphaBuilder: Alpha.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let clock = if let safeDIBuilder = safeDIOverrides.clock { safeDIBuilder() } else { Clock() }
		        func __safeDI_alphaBuilder(clock: Clock, __safeDI_Alpha_configuration: Alpha.SafeDIMockConfiguration) -> Alpha {
		            let bravoBuilder = Instantiator<Bravo> {
		                __safeDI_bravoBuilder(clock: clock, __safeDI_Bravo_configuration: __safeDI_Alpha_configuration.bravoBuilder, __safeDI_Alpha_configuration_nearest: __safeDI_Alpha_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Alpha_configuration.safeDIBuilder { safeDIBuilder(clock, bravoBuilder) } else { Alpha(clock: clock, bravoBuilder: bravoBuilder) }
		        }
		        func __safeDI_bravoBuilder(clock: Clock, __safeDI_Bravo_configuration: Bravo.SafeDIMockConfiguration, __safeDI_Alpha_configuration_nearest: Alpha.SafeDIMockConfiguration?) -> Bravo {
		            let charlieBuilder = Instantiator<Charlie> {
		                __safeDI_charlieBuilder(clock: clock, __safeDI_Charlie_configuration: __safeDI_Bravo_configuration.charlieBuilder, __safeDI_Alpha_configuration_nearest: __safeDI_Alpha_configuration_nearest)
		            }
		            return if let safeDIBuilder = __safeDI_Bravo_configuration.safeDIBuilder { safeDIBuilder(charlieBuilder) } else { Bravo(charlieBuilder: charlieBuilder) }
		        }
		        func __safeDI_charlieBuilder(clock: Clock, __safeDI_Charlie_configuration: Charlie.SafeDIMockConfiguration, __safeDI_Alpha_configuration_nearest: Alpha.SafeDIMockConfiguration?) -> Charlie {
		            let alphaBuilder = Instantiator<Alpha> {
		                __safeDI_alphaBuilder(clock: clock, __safeDI_Alpha_configuration: __safeDI_Alpha_configuration_nearest ?? Alpha.SafeDIMockConfiguration())
		            }
		            return if let safeDIBuilder = __safeDI_Charlie_configuration.safeDIBuilder { safeDIBuilder(alphaBuilder) } else { Charlie(alphaBuilder: alphaBuilder) }
		        }
		        let alphaBuilder = Instantiator<Alpha> {
		            __safeDI_alphaBuilder(clock: clock, __safeDI_Alpha_configuration: safeDIOverrides.alphaBuilder)
		        }
		        return Root(clock: clock, alphaBuilder: alphaBuilder)
		    }
		}
		#endif
		""")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().alphaBuilder.instantiate().bravoBuilder.instantiate().charlieBuilder.instantiate().alphaBuilder.instantiate().clock.tag"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(alphaBuilder: .init { clock, bravoBuilder in Alpha(clock: Clock.tagged(clock.tag + 5), bravoBuilder: bravoBuilder) })).alphaBuilder.instantiate().bravoBuilder.instantiate().charlieBuilder.instantiate().alphaBuilder.instantiate().clock.tag"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsBodiesPromotedValueAndOverride_whenCycleReceivesPromotedDependencyAndValueOnlyIfAvailable() async throws {
		// `Root` receives `clock`, which its mock promotes to its root, and `Screen` on the cycle receives it; `Screen` also
		// receives `theme` only if available, which the mock offers as an override: each body takes both from above.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(clock: Clock, screenBuilder: Instantiator<Screen>) {
			        self.clock = clock
			        self.screenBuilder = screenBuilder
			    }

			    @Received public let clock: Clock
			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
			"Screens.swift": Self.clock + """

			public final class Theme {}

			@Instantiable
			public final class Screen: Instantiable {
			    public init(clock: Clock, theme: Theme?, nextBuilder: Instantiator<Next>) {
			        self.clock = clock
			        self.theme = theme
			        self.nextBuilder = nextBuilder
			    }

			    @Received public let clock: Clock
			    @Received(onlyIfAvailable: true) public let theme: Theme?
			    @Instantiated public let nextBuilder: Instantiator<Next>
			}

			@Instantiable
			public final class Next: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root": "laidOut"])
		#expect(mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            clock: (() -> Clock)? = nil,
		            screenBuilder: Screen.SafeDIMockConfiguration = .init(),
		            theme: Theme? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                clock: clock,
		                screenBuilder: screenBuilder
		            )
		            self.theme = theme
		        }

		        var clock: (() -> Clock)? { __safeDI_storage.clock }
		        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }
		        let theme: Theme?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                clock: (() -> Clock)?,
		                screenBuilder: Screen.SafeDIMockConfiguration
		            ) {
		                self.clock = clock
		                self.screenBuilder = screenBuilder
		            }

		            let clock: (() -> Clock)?
		            let screenBuilder: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let theme: Theme? = safeDIOverrides.theme
		        let clock = if let safeDIBuilder = safeDIOverrides.clock { safeDIBuilder() } else { Clock() }
		        func __safeDI_screenBuilder(clock: Clock, theme: Theme?, __safeDI_Screen_configuration: Screen.SafeDIMockConfiguration) -> Screen {
		            let nextBuilder = Instantiator<Next> {
		                __safeDI_nextBuilder(clock: clock, theme: theme, __safeDI_Next_configuration: Next.SafeDIMockConfiguration(), __safeDI_Screen_configuration_nearest: __safeDI_Screen_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(clock, theme, nextBuilder) } else { Screen(clock: clock, theme: theme, nextBuilder: nextBuilder) }
		        }
		        func __safeDI_nextBuilder(clock: Clock, theme: Theme?, __safeDI_Next_configuration: Next.SafeDIMockConfiguration, __safeDI_Screen_configuration_nearest: Screen.SafeDIMockConfiguration?) -> Next {
		            let screenBuilder = Instantiator<Screen> {
		                __safeDI_screenBuilder(clock: clock, theme: theme, __safeDI_Screen_configuration: __safeDI_Screen_configuration_nearest ?? Screen.SafeDIMockConfiguration())
		            }
		            return if let safeDIBuilder = __safeDI_Next_configuration.safeDIBuilder { safeDIBuilder(screenBuilder) } else { Next(screenBuilder: screenBuilder) }
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(clock: clock, theme: theme, __safeDI_Screen_configuration: safeDIOverrides.screenBuilder)
		        }
		        return Root(clock: clock, screenBuilder: screenBuilder)
		    }
		}
		#endif
		""")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("{ let root = Root.mock(); let screen = root.screenBuilder.instantiate().nextBuilder.instantiate().screenBuilder.instantiate(); return [screen.clock === root.clock, screen.theme == nil] }()"),
			DifferentialValueProbe("{ let theme = Theme(); return Root.mock(safeDIOverrides: .init(theme: theme)).screenBuilder.instantiate().nextBuilder.instantiate().screenBuilder.instantiate().theme === theme }()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(clock: { Clock.tagged(6) })).screenBuilder.instantiate().nextBuilder.instantiate().screenBuilder.instantiate().clock.tag"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsRootPerPath_whenBodyTakesLabelMockRootBindsInTwoForms() async throws {
		// `Leaf`, beneath `Detail`, requires `value: Value`, so `Detail` is passed `nil` for `value: Draft?` wherever it is
		// built: the mock's root binds `value` in both forms, while a plan answers the label of the bodies that take it with
		// one declaration, so the root keeps the type key's per-path layout.
		let fixtureFiles = [
			"Screen.swift": """
			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(detail: Detail, nextBuilder: Instantiator<Next>) {
			        self.detail = detail
			        self.nextBuilder = nextBuilder
			    }

			    @Instantiated public let detail: Detail
			    @Instantiated public let nextBuilder: Instantiator<Next>
			}
			""",
			"Cycle.swift": """
			@Instantiable
			public final class Value: Instantiable {
			    public init() {}
			}

			public final class Draft {}

			@Instantiable
			public final class Detail: Instantiable {
			    public init(value: Draft?, leaf: Leaf) {
			        self.value = value
			        self.leaf = leaf
			    }

			    @Received(onlyIfAvailable: true) public let value: Draft?
			    @Instantiated public let leaf: Leaf
			}

			@Instantiable
			public final class Leaf: Instantiable {
			    public init(value: Value) {
			        self.value = value
			    }

			    @Received public let value: Value
			}

			@Instantiable
			public final class Next: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Screen": "labelBoundInTwoForms"])
		#expect(mocks.laidOut.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            value: (() -> Value)? = nil,
		            detail: Detail.SafeDIMockConfiguration = .init(),
		            nextBuilder: Next.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                value: value,
		                detail: detail,
		                nextBuilder: nextBuilder
		            )
		        }

		        var value: (() -> Value)? { __safeDI_storage.value }
		        var detail: Detail.SafeDIMockConfiguration { __safeDI_storage.detail }
		        var nextBuilder: Next.SafeDIMockConfiguration { __safeDI_storage.nextBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                value: (() -> Value)?,
		                detail: Detail.SafeDIMockConfiguration,
		                nextBuilder: Next.SafeDIMockConfiguration
		            ) {
		                self.value = value
		                self.detail = detail
		                self.nextBuilder = nextBuilder
		            }

		            let value: (() -> Value)?
		            let detail: Detail.SafeDIMockConfiguration
		            let nextBuilder: Next.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let value = if let safeDIBuilder = safeDIOverrides.value { safeDIBuilder() } else { Value() }
		        func __safeDI_detail(__safeDI_Detail_configuration: Detail.SafeDIMockConfiguration) -> Detail {
		            let leaf = if let safeDIBuilder = __safeDI_Detail_configuration.leaf { safeDIBuilder(value) } else { Leaf(value: value) }
		            return if let safeDIBuilder = __safeDI_Detail_configuration.safeDIBuilder { safeDIBuilder(nil, leaf) } else { Detail(value: nil, leaf: leaf) }
		        }
		        let detail: Detail = __safeDI_detail(__safeDI_Detail_configuration: safeDIOverrides.detail)
		        func __safeDI_nextBuilder(__safeDI_Next_configuration: Next.SafeDIMockConfiguration) -> Next {
		            let screenBuilder = Instantiator<Screen> {
		                __safeDI_screenBuilder(__safeDI_Screen_configuration: __safeDI_Next_configuration.screenBuilder, __safeDI_Next_configuration_nearest: __safeDI_Next_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Next_configuration.safeDIBuilder { safeDIBuilder(screenBuilder) } else { Next(screenBuilder: screenBuilder) }
		        }
		        func __safeDI_screenBuilder(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration, __safeDI_Next_configuration_nearest: Next.SafeDIMockConfiguration?) -> Screen {
		            let detail: Detail = __safeDI_detail(__safeDI_Detail_configuration: __safeDI_Screen_configuration.detail)
		            let nextBuilder = Instantiator<Next> {
		                __safeDI_nextBuilder(__safeDI_Next_configuration: __safeDI_Next_configuration_nearest ?? Next.SafeDIMockConfiguration())
		            }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(detail, nextBuilder) } else { Screen(detail: detail, nextBuilder: nextBuilder) }
		        }
		        let nextBuilder = Instantiator<Next> {
		            __safeDI_nextBuilder(__safeDI_Next_configuration: safeDIOverrides.nextBuilder)
		        }
		        return Screen(detail: detail, nextBuilder: nextBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Screen {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            detail: Detail.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((Detail, Instantiator<Next>) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                detail: detail,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var detail: Detail.SafeDIMockConfiguration { __safeDI_storage.detail }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Detail, Instantiator<Next>) -> Screen)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                detail: Detail.SafeDIMockConfiguration,
		                safeDIBuilder: ((Detail, Instantiator<Next>) -> Screen)?
		            ) {
		                self.detail = detail
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let detail: Detail.SafeDIMockConfiguration
		            let safeDIBuilder: ((Detail, Instantiator<Next>) -> Screen)?
		        }
		    }
		}
		#endif
		""")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("{ let screen = Screen.mock().nextBuilder.instantiate().screenBuilder.instantiate(); return [screen.detail.value == nil, screen.detail.leaf.value === Screen.mock().detail.leaf.value] }()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsRootPerPath_whenTypeOnCycleReceivesInstantiatorBuildingIt() async throws {
		// `Next` receives `screenBuilder`, the instantiator that builds it, so the walk lays the loop out as one text: the root
		// keeps the walk's body whole, as a production root that holds a loop of builders keeps its path key's.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
			"Cycle.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(nextBuilder: Instantiator<Next>) {
			        self.nextBuilder = nextBuilder
			    }

			    @Instantiated public let nextBuilder: Instantiator<Next>
			}

			@Instantiable
			public final class Next: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>?, detailBuilder: Instantiator<Detail>) {
			        self.screenBuilder = screenBuilder
			        self.detailBuilder = detailBuilder
			    }

			    @Received(onlyIfAvailable: true) public let screenBuilder: Instantiator<Screen>?
			    @Instantiated public let detailBuilder: Instantiator<Detail>
			}

			@Instantiable
			public final class Detail: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root": "loopOfBuilders"])
		#expect(mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder
		            )
		        }

		        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screenBuilder: Screen.SafeDIMockConfiguration
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_screenBuilder() -> Screen {
		            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		            func __safeDI_nextBuilder() -> Next {
		                func __safeDI_detailBuilder() -> Detail {
		                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                    return Detail(screenBuilder: screenBuilder)
		                }
		                let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		                return if let safeDIBuilder = safeDIOverrides.screenBuilder.nextBuilder.safeDIBuilder { safeDIBuilder(screenBuilder, detailBuilder) } else { Next(screenBuilder: screenBuilder, detailBuilder: detailBuilder) }
		            }
		            let nextBuilder = Instantiator<Next>(__safeDI_nextBuilder)
		            return if let safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder { safeDIBuilder(nextBuilder) } else { Screen(nextBuilder: nextBuilder) }
		        }
		        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("{ let next = Root.mock().screenBuilder.instantiate().nextBuilder.instantiate(); return [next.screenBuilder == nil, next.detailBuilder.instantiate().screenBuilder.instantiate().nextBuilder.instantiate().screenBuilder == nil] }()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilInEveryBody_whenSiblingsOnCycleReceiveEachOtherOnlyIfAvailable() async throws {
		// `Alpha` and `Bravo` receive each other only if available, so the one built first is passed `nil`, in the body of
		// `Screen` the root builds and in the one `Next` closes on alike.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
			"Cycle.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(alpha: Alpha, bravo: Bravo, nextBuilder: Instantiator<Next>) {
			        self.alpha = alpha
			        self.bravo = bravo
			        self.nextBuilder = nextBuilder
			    }

			    @Instantiated public let alpha: Alpha
			    @Instantiated public let bravo: Bravo
			    @Instantiated public let nextBuilder: Instantiator<Next>
			}

			@Instantiable
			public final class Alpha: Instantiable {
			    public init(bravo: Bravo?) {
			        self.bravo = bravo
			    }

			    @Received(onlyIfAvailable: true) public let bravo: Bravo?
			}

			@Instantiable
			public final class Bravo: Instantiable {
			    public init(alpha: Alpha?) {
			        self.alpha = alpha
			    }

			    @Received(onlyIfAvailable: true) public let alpha: Alpha?
			}

			@Instantiable
			public final class Next: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root": "laidOut"])
		#expect(mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder
		            )
		        }

		        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screenBuilder: Screen.SafeDIMockConfiguration
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_screenBuilder(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration) -> Screen {
		            let bravo = if let safeDIBuilder = __safeDI_Screen_configuration.bravo { safeDIBuilder(nil) } else { Bravo(alpha: nil) }
		            let alpha = if let safeDIBuilder = __safeDI_Screen_configuration.alpha { safeDIBuilder(bravo) } else { Alpha(bravo: bravo) }
		            let nextBuilder = Instantiator<Next> {
		                __safeDI_nextBuilder(__safeDI_Next_configuration: Next.SafeDIMockConfiguration(), __safeDI_Screen_configuration_nearest: __safeDI_Screen_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(alpha, bravo, nextBuilder) } else { Screen(alpha: alpha, bravo: bravo, nextBuilder: nextBuilder) }
		        }
		        func __safeDI_nextBuilder(__safeDI_Next_configuration: Next.SafeDIMockConfiguration, __safeDI_Screen_configuration_nearest: Screen.SafeDIMockConfiguration?) -> Next {
		            let screenBuilder = Instantiator<Screen> {
		                __safeDI_screenBuilder(__safeDI_Screen_configuration: __safeDI_Screen_configuration_nearest ?? Screen.SafeDIMockConfiguration())
		            }
		            return if let safeDIBuilder = __safeDI_Next_configuration.safeDIBuilder { safeDIBuilder(screenBuilder) } else { Next(screenBuilder: screenBuilder) }
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(__safeDI_Screen_configuration: safeDIOverrides.screenBuilder)
		        }
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("{ let screen = Root.mock().screenBuilder.instantiate(); let again = screen.nextBuilder.instantiate().screenBuilder.instantiate(); return [screen.alpha.bravo === screen.bravo, screen.bravo.alpha == nil, again.alpha.bravo === again.bravo, again.bravo.alpha == nil] }()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_marksBodiesSendable_whenCycleIsBuiltInSendableFunctions() async throws {
		// Each body is called inside a `SendableInstantiator`'s builder, so each function is `@Sendable nonisolated` and takes
		// the configurations it reads in the form a `@Sendable` function can capture.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(clock: Clock, screenBuilder: SendableInstantiator<Screen>) {
			        self.clock = clock
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let clock: Clock
			    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
			}
			""",
			"Screens.swift": Self.clock + """

			@Instantiable
			public final class Screen: Instantiable, Sendable {
			    public init(clock: Clock, nextBuilder: SendableInstantiator<Next>) {
			        self.clock = clock
			        self.nextBuilder = nextBuilder
			    }

			    @Received public let clock: Clock
			    @Instantiated public let nextBuilder: SendableInstantiator<Next>
			}

			@Instantiable
			public final class Next: Instantiable, Sendable {
			    public init(screenBuilder: SendableInstantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root": "laidOut"])
		#expect(mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            clock: (() -> Clock)? = nil,
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                clock: clock,
		                screenBuilder: screenBuilder
		            )
		        }

		        var clock: (() -> Clock)? { __safeDI_storage.clock }
		        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                clock: (() -> Clock)?,
		                screenBuilder: Screen.SafeDIMockConfiguration
		            ) {
		                self.clock = clock
		                self.screenBuilder = screenBuilder
		            }

		            let clock: (() -> Clock)?
		            let screenBuilder: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let clock = if let safeDIBuilder = safeDIOverrides.clock { safeDIBuilder() } else { Clock() }
		        @Sendable nonisolated func __safeDI_screenBuilder(clock: Clock, __safeDI_Screen_configuration: Screen.SafeDIMockConfiguration) -> Screen {
		            let nextBuilder = SendableInstantiator<Next> {
		                __safeDI_nextBuilder(clock: clock, __safeDI_Next_configuration: Next.SafeDIMockConfiguration(), __safeDI_Screen_configuration_nearest: __safeDI_Screen_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(clock, nextBuilder) } else { Screen(clock: clock, nextBuilder: nextBuilder) }
		        }
		        @Sendable nonisolated func __safeDI_nextBuilder(clock: Clock, __safeDI_Next_configuration: Next.SafeDIMockConfiguration, __safeDI_Screen_configuration_nearest: Screen.SafeDIMockConfiguration?) -> Next {
		            let screenBuilder = SendableInstantiator<Screen> {
		                __safeDI_screenBuilder(clock: clock, __safeDI_Screen_configuration: __safeDI_Screen_configuration_nearest ?? Screen.SafeDIMockConfiguration())
		            }
		            return if let safeDIBuilder = __safeDI_Next_configuration.safeDIBuilder { safeDIBuilder(screenBuilder) } else { Next(screenBuilder: screenBuilder) }
		        }
		        let __safeDI_screenBuilder____safeDI_Screen_configuration: Screen.SafeDIMockConfiguration = safeDIOverrides.screenBuilder
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(clock: clock, __safeDI_Screen_configuration: __safeDI_screenBuilder____safeDI_Screen_configuration)
		        }
		        return Root(clock: clock, screenBuilder: screenBuilder)
		    }
		}
		#endif
		""")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(clock: { Clock.tagged(7) })).screenBuilder.instantiate().nextBuilder.instantiate().screenBuilder.instantiate().clock.tag"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(screenBuilder: .init { clock, nextBuilder in Screen(clock: Clock.tagged(clock.tag + 8), nextBuilder: nextBuilder) })).screenBuilder.instantiate().nextBuilder.instantiate().screenBuilder.instantiate().clock.tag"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsBodyWithHandWrittenMock_whenTypeOnCycleHasOne() async throws {
		// `Screen` is built with its hand-written mock, whose `title` default its configuration holds: the body's function
		// reads that field of the configuration it is handed, at the place the root builds and the one `Next` closes on.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
			"Screens.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(nextBuilder: Instantiator<Next>) {
			        self.nextBuilder = nextBuilder
			        title = "production"
			    }

			    @Instantiated public let nextBuilder: Instantiator<Next>
			    public let title: String

			    private init(nextBuilder: Instantiator<Next>, title: String) {
			        self.nextBuilder = nextBuilder
			        self.title = title
			    }

			    public static func mock(nextBuilder: Instantiator<Next>, title: String = "mocked") -> Screen {
			        Screen(nextBuilder: nextBuilder, title: title)
			    }
			}

			@Instantiable
			public final class Next: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root": "laidOut"])
		#expect(mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder
		            )
		        }

		        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screenBuilder: Screen.SafeDIMockConfiguration
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_screenBuilder(__safeDI_Screen_mockConfiguration: Screen.SafeDIMockConfiguration) -> Screen {
		            let nextBuilder = Instantiator<Next> {
		                __safeDI_nextBuilder(__safeDI_Next_configuration: Next.SafeDIMockConfiguration(), __safeDI_Screen_mockConfiguration_nearest: __safeDI_Screen_mockConfiguration)
		            }
		            return if let safeDIBuilder = __safeDI_Screen_mockConfiguration.safeDIBuilder { safeDIBuilder(nextBuilder, __safeDI_Screen_mockConfiguration.title) } else { Screen.mock(nextBuilder: nextBuilder, title: __safeDI_Screen_mockConfiguration.title) }
		        }
		        func __safeDI_nextBuilder(__safeDI_Next_configuration: Next.SafeDIMockConfiguration, __safeDI_Screen_mockConfiguration_nearest: Screen.SafeDIMockConfiguration?) -> Next {
		            let screenBuilder = Instantiator<Screen> {
		                __safeDI_screenBuilder(__safeDI_Screen_mockConfiguration: __safeDI_Screen_mockConfiguration_nearest ?? Screen.SafeDIMockConfiguration())
		            }
		            return if let safeDIBuilder = __safeDI_Next_configuration.safeDIBuilder { safeDIBuilder(screenBuilder) } else { Next(screenBuilder: screenBuilder) }
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(__safeDI_Screen_mockConfiguration: safeDIOverrides.screenBuilder)
		        }
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().screenBuilder.instantiate().nextBuilder.instantiate().screenBuilder.instantiate().title"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(screenBuilder: .init(title: \"overridden\"))).screenBuilder.instantiate().nextBuilder.instantiate().screenBuilder.instantiate().title"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsConfigurationOfHandWrittenMocksShape_whenInitializerBuildsTypeBeneathCycleEdge() async throws {
		// `A` has a hand-written mock that returns `AProtocol`, so its configuration takes that mock's shape, while the `A`
		// that `B` closes on beneath the cycle edge is built with its initializer: the body of that `A` reads the
		// configuration it is handed in the initializer's way, its `label` the default the configuration declares.
		let fixtureFiles = [
			"A.swift": """
			public protocol AProtocol {}

			@Instantiable(fulfillingAdditionalTypes: [AProtocol.self], generateMock: true)
			public struct A: AProtocol, Instantiable {
			    public init(bBuilder: Instantiator<B>, label: String = "production") {
			        self.bBuilder = bBuilder
			        self.label = label
			    }

			    @Instantiated public let bBuilder: Instantiator<B>
			    public let label: String
			}

			@Instantiable(fulfillingAdditionalTypes: [AProtocol.self], mockOnly: true, customMockName: "customMock")
			extension A {
			    public static func customMock(label: String = "mock") -> AProtocol {
			        func a() -> A { A(bBuilder: Instantiator<B>(b), label: label) }
			        func b() -> B { B(aBuilder: Instantiator<A>(a)) }
			        return a()
			    }
			}
			""",
			"B.swift": """
			@Instantiable
			public struct B: Instantiable {
			    public init(aBuilder: Instantiator<A>) {
			        self.aBuilder = aBuilder
			    }

			    @Instantiated public let aBuilder: Instantiator<A>
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["A": "laidOut"])
		#expect(mocks.laidOut.mockFiles["A+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension A {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            bBuilder: B.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                bBuilder: bBuilder
		            )
		        }

		        var bBuilder: B.SafeDIMockConfiguration { __safeDI_storage.bBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                bBuilder: B.SafeDIMockConfiguration
		            ) {
		                self.bBuilder = bBuilder
		            }

		            let bBuilder: B.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        label: String = "production",
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> A {
		        func __safeDI_bBuilder(__safeDI_B_configuration: B.SafeDIMockConfiguration) -> B {
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(__safeDI_A_configuration: A.SafeDIMockConfiguration(), __safeDI_B_configuration_nearest: __safeDI_B_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_B_configuration.safeDIBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
		        }
		        func __safeDI_aBuilder(__safeDI_A_configuration: A.SafeDIMockConfiguration, __safeDI_B_configuration_nearest: B.SafeDIMockConfiguration?) -> A {
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(__safeDI_B_configuration: __safeDI_B_configuration_nearest ?? B.SafeDIMockConfiguration())
		            }
		            return if let safeDIBuilder = __safeDI_A_configuration.safeDIBuilder { safeDIBuilder(bBuilder, __safeDI_A_configuration.label) } else { A(bBuilder: bBuilder, label: __safeDI_A_configuration.label) }
		        }
		        let bBuilder = Instantiator<B> {
		            __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
		        }
		        return A(bBuilder: bBuilder, label: label)
		    }
		}
		#endif

		#if DEBUG
		extension A {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            bBuilder: B.SafeDIMockConfiguration = .init(),
		            label: String = "mock",
		            _ safeDIBuilder: ((Instantiator<B>, String) -> A)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                bBuilder: bBuilder,
		                label: label,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var bBuilder: B.SafeDIMockConfiguration { __safeDI_storage.bBuilder }
		        var label: String { __safeDI_storage.label }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Instantiator<B>, String) -> A)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                bBuilder: B.SafeDIMockConfiguration,
		                label: String,
		                safeDIBuilder: ((Instantiator<B>, String) -> A)?
		            ) {
		                self.bBuilder = bBuilder
		                self.label = label
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let bBuilder: B.SafeDIMockConfiguration
		            let label: String
		            let safeDIBuilder: ((Instantiator<B>, String) -> A)?
		        }
		    }
		}
		#endif
		""")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("A.mock().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().label"),
			DifferentialValueProbe("A.mock(label: \"root\", safeDIOverrides: .init(bBuilder: .init { aBuilder in B(aBuilder: aBuilder) })).bBuilder.instantiate().aBuilder.instantiate().label"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsRootPerPath_whenBodyReadsWrapperMockBindsApart() async throws {
		// The mock cannot build `Session`, which forwards its `id`, so it takes the instance and binds the wrapper
		// `Screen` receives apart (`session_lazilyInstantiated`): a name no body's function can take as a label, so the root
		// keeps the walk's body, counted.
		let fixtureFiles = [
			"Session.swift": """
			@Instantiable
			public final class Session: Instantiable {
			    public init(id: String) {
			        self.id = id
			    }

			    @Forwarded public let id: String
			}
			""",
			"Root.swift": """
			@Instantiable(generateMock: true)
			public struct Root: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
			"Screen.swift": """
			@Instantiable
			public struct Screen: Instantiable {
			    public init(session: LazilyInstantiated<Session>, nextBuilder: Instantiator<Next>) {
			        self.session = session
			        self.nextBuilder = nextBuilder
			    }

			    @Received public let session: LazilyInstantiated<Session>
			    @Instantiated public let nextBuilder: Instantiator<Next>
			}
			""",
			"Next.swift": """
			@Instantiable
			public struct Next: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root": "readUnresolved"])
		#expect(mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder
		            )
		        }

		        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screenBuilder: Screen.SafeDIMockConfiguration
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        session: Session,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let session_lazilyInstantiated = LazilyInstantiated<Session> { session }
		        func __safeDI_screenBuilder() -> Screen {
		            func __safeDI_nextBuilder() -> Next {
		                let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                return Next(screenBuilder: screenBuilder)
		            }
		            let nextBuilder = Instantiator<Next>(__safeDI_nextBuilder)
		            return if let safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder { safeDIBuilder(session_lazilyInstantiated, nextBuilder) } else { Screen(session: session_lazilyInstantiated, nextBuilder: nextBuilder) }
		        }
		        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock(session: Session(id: \"a\")).screenBuilder.instantiate().nextBuilder.instantiate().screenBuilder.instantiate().session.instance.id"),
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private struct PlanMocks {
		/// The mocks written from each mock root's plan, where it was laid out.
		let laidOut: TestOutput
		/// The mocks the walk writes, the known-right path.
		let walk: TestOutput
		/// What laying out each mock root's plan came to, by mocked type.
		let outcomes: [String: String]
	}

	/// Generates `fixtureFiles`' mocks twice: written from each mock root's plan where it is laid out, and by the walk.
	private mutating func generatedMocks(of fixtureFiles: [String: String]) async throws -> PlanMocks {
		let (stream, continuation) = AsyncStream.makeStream(of: (String, String).self)
		let laidOut = try await MockPlanCodeObservation.$observer.withValue({ mockedType, _, outcome in
			continuation.yield((mockedType, outcome))
		}) {
			try await MockPlanCodeObservation.$writesPlanCode.withValue(true) {
				try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
		}
		continuation.finish()
		var outcomes = [String: String]()
		for await (mockedType, outcome) in stream {
			outcomes[mockedType] = outcome
		}
		let walk = try await MockLowering.$laysOutWithTypeKey.withValue(false) {
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		return PlanMocks(laidOut: laidOut, walk: walk, outcomes: outcomes)
	}

	/// Compares what the mocks written from the plan build for `probes` with what the walk's build.
	private mutating func expectLaidOutValuesEqualWalks(
		_ mocks: PlanMocks,
		fixtureFiles: [String: String],
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(mocks.laidOut.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(mocks.walk.generatedFiles)),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	private static let clock = """
	@Instantiable
	public final class Clock: Instantiable, Sendable {
	    public init() {
	        tag = 0
	    }

	    public let tag: Int

	    private init(tag: Int) {
	        self.tag = tag
	    }

	    public static func tagged(_ tag: Int) -> Clock {
	        Clock(tag: tag)
	    }
	}
	"""
}
