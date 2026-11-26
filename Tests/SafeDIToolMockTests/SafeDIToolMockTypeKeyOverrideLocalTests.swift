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
import Testing
@testable import SafeDICore
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// A `@Sendable` builder function of an internal mock reads the overrides beneath it into locals before the function
/// (`SendableOverrideExtractor`). Under the type key's layout, such a place is laid out where every place beneath it is
/// recorded: its call binds what it hands the function before it calls (`PassedArgument.bindsBeforeCall`), as the
/// walk binds the locals. A place beneath it that keeps the walk's text keeps the walk's body for the whole root. Each
/// cell compares the values the laid-out mock builds with the walk's.
struct SafeDIToolMockTypeKeyOverrideLocalTests: ~Copyable {
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
	mutating func mock_laysOutSendableBuilderOfConfiguredNode_whenEveryPlaceBeneathIsRecorded() async throws {
		let mocks = try await generatedMocks(of: Self.configuredNodeFixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""
		let walk = mocks.walk.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
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

		        private final class __safeDI_Storage: Sendable {
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
		        @Sendable nonisolated func __safeDI_screenBuilder(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration) -> Screen {
		            let leaf = if let safeDIBuilder = __safeDI_Screen_configuration.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(leaf, __safeDI_Screen_configuration.title()) } else { Screen(leaf: leaf, title: __safeDI_Screen_configuration.title()) }
		        }
		        let __safeDI_screenBuilder____safeDI_Screen_configuration: Screen.SafeDIMockConfiguration = safeDIOverrides.screenBuilder
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(__safeDI_Screen_configuration: __safeDI_screenBuilder____safeDI_Screen_configuration)
		        }
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.configuredNodeFixture, probes: [
			DifferentialValueProbe("Root.mock().screenBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(screenBuilder: .init(leaf: { Leaf.tagged(1) }, title: \"overridden\"))).screenBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(screenBuilder: .init(leaf: nil) { leaf, _ in Screen(leaf: leaf, title: \"built\") })).screenBuilder.instantiate()"),
		])
		#expect(walk != laidOut)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutSendableBuilderReadingOverrideClosure_whenNodeHasNoConfiguration() async throws {
		let mocks = try await generatedMocks(of: Self.overrideClosureFixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""
		let walk = mocks.walk.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            leafBuilder: (@Sendable () -> Leaf)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                leafBuilder: leafBuilder
		            )
		        }

		        var leafBuilder: (@Sendable () -> Leaf)? { __safeDI_storage.leafBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                leafBuilder: (@Sendable () -> Leaf)?
		            ) {
		                self.leafBuilder = leafBuilder
		            }

		            let leafBuilder: (@Sendable () -> Leaf)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        @Sendable nonisolated func __safeDI_leafBuilder(__safeDI_Leaf_configuration: (@Sendable () -> Leaf)?) -> Leaf {
		            if let safeDIBuilder = __safeDI_Leaf_configuration { safeDIBuilder() } else { Leaf() }
		        }
		        let __safeDI_leafBuilder____safeDI_Leaf_configuration: (@Sendable () -> Leaf)? = safeDIOverrides.leafBuilder
		        let leafBuilder = SendableInstantiator<Leaf> {
		            __safeDI_leafBuilder(__safeDI_Leaf_configuration: __safeDI_leafBuilder____safeDI_Leaf_configuration)
		        }
		        return Root(leafBuilder: leafBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.overrideClosureFixture, probes: [
			DifferentialValueProbe("Root.mock().leafBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(leafBuilder: { Leaf.tagged(2) })).leafBuilder.instantiate()"),
		])
		#expect(walk != laidOut)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutSendableAutoclosureBinding_whenTypeBeneathSendableBuilderInstantiatesUncoveredDependency() async throws {
		let mocks = try await generatedMocks(of: Self.sendableAutoclosureFixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""
		let walk = mocks.walk.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
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

		        private final class __safeDI_Storage: Sendable {
		            init(
		                screenBuilder: Screen.SafeDIMockConfiguration
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        missing: @autoclosure @escaping @Sendable () -> Missing,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_missing = missing
		        @Sendable nonisolated func __safeDI_panel(__safeDI_Panel_configuration: Panel.SafeDIMockConfiguration) -> Panel {
		            let missing = __safeDI_missing()
		            let leaf = if let safeDIBuilder = __safeDI_Panel_configuration.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = __safeDI_Panel_configuration.safeDIBuilder { safeDIBuilder(leaf, missing) } else { Panel(leaf: leaf, missing: missing) }
		        }
		        @Sendable nonisolated func __safeDI_screenBuilder(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration) -> Screen {
		            let panel: Panel = __safeDI_panel(__safeDI_Panel_configuration: __safeDI_Screen_configuration.panel)
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(panel) } else { Screen(panel: panel) }
		        }
		        let __safeDI_screenBuilder____safeDI_Screen_configuration: Screen.SafeDIMockConfiguration = safeDIOverrides.screenBuilder
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(__safeDI_Screen_configuration: __safeDI_screenBuilder____safeDI_Screen_configuration)
		        }
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.sendableAutoclosureFixture, probes: [
			DifferentialValueProbe("Root.mock(missing: Missing(tag: 1)).screenBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(missing: Missing(tag: 2), safeDIOverrides: .init(screenBuilder: .init(panel: .init(leaf: { Leaf.tagged(3) })))).screenBuilder.instantiate()"),
			DifferentialValueProbe(name: "autoclosure evaluated once per construction", expression: "{ let builder = Root.mock(missing: Missing.next()).screenBuilder; return [builder.instantiate().panel.missing.tag, builder.instantiate().panel.missing.tag] }()"),
		])
		#expect(walk != laidOut)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutReceiverBindings_whenTypeBuiltTwiceReceivesFlatParameterNamedApart() async throws {
		let mocks = try await generatedMocks(of: Self.receiverBindingFixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""
		let walk = mocks.walk.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            first: ((Service) -> User)? = nil,
		            second: ((Service) -> User)? = nil,
		            named: ((String) -> NamedUser)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                first: first,
		                second: second,
		                named: named
		            )
		        }

		        var first: ((Service) -> User)? { __safeDI_storage.first }
		        var second: ((Service) -> User)? { __safeDI_storage.second }
		        var named: ((String) -> NamedUser)? { __safeDI_storage.named }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                first: ((Service) -> User)?,
		                second: ((Service) -> User)?,
		                named: ((String) -> NamedUser)?
		            ) {
		                self.first = first
		                self.second = second
		                self.named = named
		            }

		            let first: ((Service) -> User)?
		            let second: ((Service) -> User)?
		            let named: ((String) -> NamedUser)?
		        }
		    }

		    static func mock(
		        service_Service: Service,
		        service_String: String,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_first(__safeDI_User_configuration: ((Service) -> User)?) -> User {
		            let service: Service = service_Service
		            return if let safeDIBuilder = __safeDI_User_configuration { safeDIBuilder(service) } else { User(service: service) }
		        }
		        let first: User = __safeDI_first(__safeDI_User_configuration: safeDIOverrides.first)
		        let second: User = __safeDI_first(__safeDI_User_configuration: safeDIOverrides.second)
		        func __safeDI_named(__safeDI_NamedUser_configuration: ((String) -> NamedUser)?) -> NamedUser {
		            let service: String = service_String
		            return if let safeDIBuilder = __safeDI_NamedUser_configuration { safeDIBuilder(service) } else { NamedUser(service: service) }
		        }
		        let named: NamedUser = __safeDI_named(__safeDI_NamedUser_configuration: safeDIOverrides.named)
		        return Root(first: first, second: second, named: named)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.receiverBindingFixture, probes: [
			DifferentialValueProbe("{ let root = Root.mock(service_Service: Service(tag: 1), service_String: \"named\"); return [String(root.first.service.tag), String(root.second.service.tag), root.named.service] }()"),
		])
		#expect(walk != laidOut)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsLoopMembersTheirConfigurations_whenLoopOfBuildersSitsBeneathSendableBuilder() async throws {
		let mocks = try await generatedMocks(of: Self.loopBeneathSendableBuilderFixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
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

		        private final class __safeDI_Storage: Sendable {
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
		        @Sendable nonisolated func __safeDI_aBuilder(leaf: Leaf, __safeDI_A_configuration: (@Sendable (Instantiator<B>) -> A)?, __safeDI_Screen_loopConfiguration: Screen.SafeDIMockConfiguration) -> A {
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(leaf: leaf, __safeDI_B_configuration: __safeDI_Screen_loopConfiguration.bBuilder, __safeDI_Screen_loopConfiguration: __safeDI_Screen_loopConfiguration)
		            }
		            return if let safeDIBuilder = __safeDI_A_configuration { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
		        }
		        @Sendable nonisolated func __safeDI_bBuilder(leaf: Leaf, __safeDI_B_configuration: (@Sendable (Instantiator<A>, Leaf) -> B)?, __safeDI_Screen_loopConfiguration: Screen.SafeDIMockConfiguration) -> B {
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(leaf: leaf, __safeDI_A_configuration: __safeDI_Screen_loopConfiguration.aBuilder, __safeDI_Screen_loopConfiguration: __safeDI_Screen_loopConfiguration)
		            }
		            return if let safeDIBuilder = __safeDI_B_configuration { safeDIBuilder(aBuilder, leaf) } else { B(aBuilder: aBuilder, leaf: leaf) }
		        }
		        @Sendable nonisolated func __safeDI_screenBuilder(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration) -> Screen {
		            let leaf = if let safeDIBuilder = __safeDI_Screen_configuration.leaf { safeDIBuilder() } else { Leaf() }
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(leaf: leaf, __safeDI_A_configuration: __safeDI_Screen_configuration.aBuilder, __safeDI_Screen_loopConfiguration: __safeDI_Screen_configuration)
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(leaf: leaf, __safeDI_B_configuration: __safeDI_Screen_configuration.bBuilder, __safeDI_Screen_loopConfiguration: __safeDI_Screen_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(leaf, aBuilder, bBuilder) } else { Screen(leaf: leaf, aBuilder: aBuilder, bBuilder: bBuilder) }
		        }
		        let __safeDI_screenBuilder____safeDI_Screen_configuration: Screen.SafeDIMockConfiguration = safeDIOverrides.screenBuilder
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(__safeDI_Screen_configuration: __safeDI_screenBuilder____safeDI_Screen_configuration)
		        }
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.loopBeneathSendableBuilderFixture, probes: [
			DifferentialValueProbe("Root.mock().screenBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().leaf.tag"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(screenBuilder: .init(leaf: { Leaf.tagged(3) }))).screenBuilder.instantiate().leaf.tag"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutRootSharingOneFunctionPerType_whenRootEntersMockedLazyCycle() async throws {
		// Which edge of the cycle `computeCycleEdges` prunes follows the types' names, and so does whether a place of a type
		// is built or closes the cycle: both call the one function of the type, handing it the nearest configuration of its
		// type above, else what the walk hands it there.
		let mocks = try await generatedMocks(of: Self.mockedLazyCycleFixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            alphaBuilder: Alpha.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                alphaBuilder: alphaBuilder
		            )
		        }

		        var alphaBuilder: Alpha.SafeDIMockConfiguration { __safeDI_storage.alphaBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                alphaBuilder: Alpha.SafeDIMockConfiguration
		            ) {
		                self.alphaBuilder = alphaBuilder
		            }

		            let alphaBuilder: Alpha.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_alphaBuilder(__safeDI_Alpha_configuration: Alpha.SafeDIMockConfiguration) -> Alpha {
		            let bravoBuilder = Instantiator<Bravo> {
		                __safeDI_bravoBuilder(__safeDI_Bravo_configuration: __safeDI_Alpha_configuration.bravoBuilder, __safeDI_Alpha_configuration_nearest: __safeDI_Alpha_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Alpha_configuration.safeDIBuilder { safeDIBuilder(bravoBuilder) } else { Alpha(bravoBuilder: bravoBuilder) }
		        }
		        func __safeDI_bravoBuilder(__safeDI_Bravo_configuration: Bravo.SafeDIMockConfiguration, __safeDI_Alpha_configuration_nearest: Alpha.SafeDIMockConfiguration?) -> Bravo {
		            let alphaBuilder = Instantiator<Alpha> {
		                __safeDI_alphaBuilder(__safeDI_Alpha_configuration: __safeDI_Alpha_configuration_nearest ?? Alpha.SafeDIMockConfiguration())
		            }
		            let badge: Badge = __safeDI_badge(__safeDI_Badge_configuration: __safeDI_Bravo_configuration.badge)
		            return if let safeDIBuilder = __safeDI_Bravo_configuration.safeDIBuilder { safeDIBuilder(alphaBuilder, badge) } else { Bravo(alphaBuilder: alphaBuilder, badge: badge) }
		        }
		        func __safeDI_badge(__safeDI_Badge_configuration: Badge.SafeDIMockConfiguration) -> Badge {
		            if let safeDIBuilder = __safeDI_Badge_configuration.safeDIBuilder { safeDIBuilder(__safeDI_Badge_configuration.title) } else { Badge(title: __safeDI_Badge_configuration.title) }
		        }
		        let alphaBuilder = Instantiator<Alpha> {
		            __safeDI_alphaBuilder(__safeDI_Alpha_configuration: safeDIOverrides.alphaBuilder)
		        }
		        return Root(alphaBuilder: alphaBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		for file in ["Alpha+SafeDIMock.swift", "Bravo+SafeDIMock.swift", "Root+SafeDIMock.swift"] {
			#expect(mocks.laidOut.mockFiles[file] != mocks.walk.mockFiles[file], "\(file)")
		}
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.mockedLazyCycleFixture, probes: [
			DifferentialValueProbe("Root.mock().alphaBuilder.instantiate().bravoBuilder.instantiate().badge.title"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(alphaBuilder: .init(bravoBuilder: .init(badge: .init(title: \"root\"))))).alphaBuilder.instantiate().bravoBuilder.instantiate().alphaBuilder.instantiate().bravoBuilder.instantiate().badge.title"),
			DifferentialValueProbe("Bravo.mock(safeDIOverrides: .init(badge: .init(title: \"bravo\"))).alphaBuilder.instantiate().bravoBuilder.instantiate().badge.title"),
			DifferentialValueProbe("Alpha.mock(safeDIOverrides: .init(bravoBuilder: .init(badge: .init(title: \"alpha\")))).bravoBuilder.instantiate().alphaBuilder.instantiate().bravoBuilder.instantiate().badge.title"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutRoot_whenRootEntersMockedLazyCycleUnderAnotherLabelThanTheCyclesOwn() async throws {
		// `Root` holds `Alpha` as `entryBuilder`, which the cycle holds as `alphaBuilder`, so no closer closes on `Root`'s
		// place: `Bravo` builds `Alpha` again, which reads the configuration of the `Alpha` above, handed down as the nearest.
		var fixture = Self.mockedLazyCycleFixture
		fixture["Root.swift"] = """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(entryBuilder: Instantiator<Alpha>) {
		        self.entryBuilder = entryBuilder
		    }

		    @Instantiated public let entryBuilder: Instantiator<Alpha>
		}
		"""
		let mocks = try await generatedMocks(of: fixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            entryBuilder: Alpha.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                entryBuilder: entryBuilder
		            )
		        }

		        var entryBuilder: Alpha.SafeDIMockConfiguration { __safeDI_storage.entryBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                entryBuilder: Alpha.SafeDIMockConfiguration
		            ) {
		                self.entryBuilder = entryBuilder
		            }

		            let entryBuilder: Alpha.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_entryBuilder(__safeDI_Alpha_configuration: Alpha.SafeDIMockConfiguration, __safeDI_Bravo_configuration_nearest: Bravo.SafeDIMockConfiguration?) -> Alpha {
		            let bravoBuilder = Instantiator<Bravo> {
		                __safeDI_bravoBuilder(__safeDI_Bravo_configuration: __safeDI_Bravo_configuration_nearest ?? __safeDI_Alpha_configuration.bravoBuilder, __safeDI_Alpha_configuration_nearest: __safeDI_Alpha_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Alpha_configuration.safeDIBuilder { safeDIBuilder(bravoBuilder) } else { Alpha(bravoBuilder: bravoBuilder) }
		        }
		        func __safeDI_bravoBuilder(__safeDI_Bravo_configuration: Bravo.SafeDIMockConfiguration, __safeDI_Alpha_configuration_nearest: Alpha.SafeDIMockConfiguration?) -> Bravo {
		            let alphaBuilder = Instantiator<Alpha> {
		                __safeDI_entryBuilder(__safeDI_Alpha_configuration: __safeDI_Alpha_configuration_nearest ?? Alpha.SafeDIMockConfiguration(), __safeDI_Bravo_configuration_nearest: __safeDI_Bravo_configuration)
		            }
		            let badge: Badge = __safeDI_badge(__safeDI_Badge_configuration: __safeDI_Bravo_configuration.badge)
		            return if let safeDIBuilder = __safeDI_Bravo_configuration.safeDIBuilder { safeDIBuilder(alphaBuilder, badge) } else { Bravo(alphaBuilder: alphaBuilder, badge: badge) }
		        }
		        func __safeDI_badge(__safeDI_Badge_configuration: Badge.SafeDIMockConfiguration) -> Badge {
		            if let safeDIBuilder = __safeDI_Badge_configuration.safeDIBuilder { safeDIBuilder(__safeDI_Badge_configuration.title) } else { Badge(title: __safeDI_Badge_configuration.title) }
		        }
		        let entryBuilder = Instantiator<Alpha> {
		            __safeDI_entryBuilder(__safeDI_Alpha_configuration: safeDIOverrides.entryBuilder, __safeDI_Bravo_configuration_nearest: nil)
		        }
		        return Root(entryBuilder: entryBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		#expect(laidOut != mocks.walk.mockFiles["Root+SafeDIMock.swift"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixture, probes: [
			DifferentialValueProbe("Root.mock().entryBuilder.instantiate().bravoBuilder.instantiate().badge.title"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(entryBuilder: .init(bravoBuilder: .init(badge: .init(title: \"root\"))))).entryBuilder.instantiate().bravoBuilder.instantiate().alphaBuilder.instantiate().bravoBuilder.instantiate().alphaBuilder.instantiate().bravoBuilder.instantiate().badge.title"),
			DifferentialValueProbe(name: "the override of the entry builds the Alpha the cycle builds again", expression: "{ () -> Int in var count = 0; let root = Root.mock(safeDIOverrides: .init(entryBuilder: .init { bravoBuilder in count += 1; return Alpha(bravoBuilder: bravoBuilder) })); _ = root.entryBuilder.instantiate().bravoBuilder.instantiate().alphaBuilder.instantiate(); return count }()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutRoot_whenTypeOfMockedLazyCycleInstantiatesItself() async throws {
		// The closer is in the function of the type it closes on, so it hands that function its own configuration on.
		let fixture = [
			"Node.swift": """
			@Instantiable(generateMock: true)
			public final class Node: Instantiable {
			    public init(nodeBuilder: Instantiator<Node>) {
			        self.nodeBuilder = nodeBuilder
			    }

			    @Instantiated public let nodeBuilder: Instantiator<Node>
			}
			""",
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(nodeBuilder: Instantiator<Node>) {
			        self.nodeBuilder = nodeBuilder
			    }

			    @Instantiated public let nodeBuilder: Instantiator<Node>
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            nodeBuilder: Node.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                nodeBuilder: nodeBuilder
		            )
		        }

		        var nodeBuilder: Node.SafeDIMockConfiguration { __safeDI_storage.nodeBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                nodeBuilder: Node.SafeDIMockConfiguration
		            ) {
		                self.nodeBuilder = nodeBuilder
		            }

		            let nodeBuilder: Node.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_nodeBuilder(__safeDI_Node_configuration: Node.SafeDIMockConfiguration) -> Node {
		            let nodeBuilder = Instantiator<Node> {
		                __safeDI_nodeBuilder(__safeDI_Node_configuration: __safeDI_Node_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Node_configuration.safeDIBuilder { safeDIBuilder(nodeBuilder) } else { Node(nodeBuilder: nodeBuilder) }
		        }
		        let nodeBuilder = Instantiator<Node> {
		            __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
		        }
		        return Root(nodeBuilder: nodeBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixture, probes: [
			DifferentialValueProbe(name: "the override of the root's node builds every node beneath it", expression: "{ () -> Int in var count = 0; let root = Root.mock(safeDIOverrides: .init(nodeBuilder: .init { nodeBuilder in count += 1; return Node(nodeBuilder: nodeBuilder) })); _ = root.nodeBuilder.instantiate().nodeBuilder.instantiate().nodeBuilder.instantiate(); return count }()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutRootReturningThePropertysType_whenMockedLazyCycleBuildsItsTypeAgainUnderAProtocol() async throws {
		// `Bravo` builds `Alpha` again as `AlphaProtocol`, beneath the edge the mock's configurations leave out, so the
		// override that place tries is the nearest `Alpha`'s, and the function it is built in returns the property's type.
		let fixture = [
			"Alpha.swift": """
			public protocol AlphaProtocol {}

			@Instantiable(generateMock: true)
			public final class Alpha: Instantiable, AlphaProtocol {
			    public init(bravoBuilder: Instantiator<Bravo>) {
			        self.bravoBuilder = bravoBuilder
			    }

			    @Instantiated public let bravoBuilder: Instantiator<Bravo>
			}
			""",
			"Bravo.swift": """
			@Instantiable(generateMock: true)
			public final class Bravo: Instantiable {
			    public init(alpha: ErasedInstantiator<(), AlphaProtocol>) {
			        self.alpha = alpha
			    }

			    @Instantiated(fulfilledByType: "Alpha") public let alpha: ErasedInstantiator<(), AlphaProtocol>
			}
			""",
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(alphaBuilder: Instantiator<Alpha>) {
			        self.alphaBuilder = alphaBuilder
			    }

			    @Instantiated public let alphaBuilder: Instantiator<Alpha>
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            alphaBuilder: Alpha.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                alphaBuilder: alphaBuilder
		            )
		        }

		        var alphaBuilder: Alpha.SafeDIMockConfiguration { __safeDI_storage.alphaBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                alphaBuilder: Alpha.SafeDIMockConfiguration
		            ) {
		                self.alphaBuilder = alphaBuilder
		            }

		            let alphaBuilder: Alpha.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_bravoBuilder(__safeDI_Bravo_configuration: Bravo.SafeDIMockConfiguration, __safeDI_Alpha_configuration_nearest: Alpha.SafeDIMockConfiguration?) -> Bravo {
		            let alpha = ErasedInstantiator<(), AlphaProtocol> {
		                __safeDI_alpha(__safeDI_Alpha_configuration: __safeDI_Alpha_configuration_nearest ?? Alpha.SafeDIMockConfiguration(), __safeDI_Bravo_configuration_nearest: __safeDI_Bravo_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Bravo_configuration.safeDIBuilder { safeDIBuilder(alpha) } else { Bravo(alpha: alpha) }
		        }
		        func __safeDI_alpha(__safeDI_Alpha_configuration: Alpha.SafeDIMockConfiguration, __safeDI_Bravo_configuration_nearest: Bravo.SafeDIMockConfiguration?) -> AlphaProtocol {
		            let bravoBuilder = Instantiator<Bravo> {
		                __safeDI_bravoBuilder(__safeDI_Bravo_configuration: __safeDI_Bravo_configuration_nearest ?? __safeDI_Alpha_configuration.bravoBuilder, __safeDI_Alpha_configuration_nearest: __safeDI_Alpha_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Alpha_configuration.safeDIBuilder { safeDIBuilder(bravoBuilder) } else { Alpha(bravoBuilder: bravoBuilder) }
		        }
		        func __safeDI_alphaBuilder(__safeDI_Alpha_configuration: Alpha.SafeDIMockConfiguration, __safeDI_Bravo_configuration_nearest: Bravo.SafeDIMockConfiguration?) -> Alpha {
		            let bravoBuilder = Instantiator<Bravo> {
		                __safeDI_bravoBuilder(__safeDI_Bravo_configuration: __safeDI_Bravo_configuration_nearest ?? __safeDI_Alpha_configuration.bravoBuilder, __safeDI_Alpha_configuration_nearest: __safeDI_Alpha_configuration)
		            }
		            return if let safeDIBuilder = __safeDI_Alpha_configuration.safeDIBuilder { safeDIBuilder(bravoBuilder) } else { Alpha(bravoBuilder: bravoBuilder) }
		        }
		        let alphaBuilder = Instantiator<Alpha> {
		            __safeDI_alphaBuilder(__safeDI_Alpha_configuration: safeDIOverrides.alphaBuilder, __safeDI_Bravo_configuration_nearest: nil)
		        }
		        return Root(alphaBuilder: alphaBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixture, probes: [
			DifferentialValueProbe(name: "the override of the root's Alpha builds the Alpha the cycle builds again", expression: "{ () -> Int in var count = 0; let root = Root.mock(safeDIOverrides: .init(alphaBuilder: .init { bravoBuilder in count += 1; return Alpha(bravoBuilder: bravoBuilder) })); _ = root.alphaBuilder.instantiate().bravoBuilder.instantiate().alpha.instantiate(); return count }()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutRootReadingTheOverridesTheWalkReads_whenTypeBeneathLeftOutEdgesOfTwoLazyCyclesInstantiatesALabelAgain() async throws {
		// `W` and `U` instantiate one another, and so do `U` and `P`, and a mock's configurations leave one edge of each
		// cycle out: `W`'s has no `uBuilder` and `U`'s no `pBuilder`. `P`, built beneath both, has no `P` above it, so it is
		// handed a configuration built afresh, and the `l` it instantiates again reads no override, as in the walk's body.
		let fixture = [
			"L.swift": """
			@Instantiable
			public final class L: Instantiable {
			    public init(title: String = "default") {
			        self.title = title
			    }

			    public let title: String
			}
			""",
			"P.swift": """
			@Instantiable
			public final class P: Instantiable {
			    public init(l: L, uBuilder: Instantiator<U>) {
			        self.l = l
			        self.uBuilder = uBuilder
			    }

			    @Instantiated public let l: L
			    @Instantiated public let uBuilder: Instantiator<U>
			}
			""",
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(l: L, wBuilder: Instantiator<W>) {
			        self.l = l
			        self.wBuilder = wBuilder
			    }

			    @Instantiated public let l: L
			    @Instantiated public let wBuilder: Instantiator<W>
			}
			""",
			"U.swift": """
			@Instantiable
			public final class U: Instantiable {
			    public init(pBuilder: Instantiator<P>, wBuilder: Instantiator<W>) {
			        self.pBuilder = pBuilder
			        self.wBuilder = wBuilder
			    }

			    @Instantiated public let pBuilder: Instantiator<P>
			    @Instantiated public let wBuilder: Instantiator<W>
			}
			""",
			"V.swift": """
			@Instantiable
			public final class V: Instantiable {
			    public init(l: L) {
			        self.l = l
			    }

			    @Received public let l: L
			}
			""",
			"W.swift": """
			@Instantiable
			public final class W: Instantiable {
			    public init(uBuilder: Instantiator<U>, vBuilder: Instantiator<V>) {
			        self.uBuilder = uBuilder
			        self.vBuilder = vBuilder
			    }

			    @Instantiated public let uBuilder: Instantiator<U>
			    @Instantiated public let vBuilder: Instantiator<V>
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            l: L.SafeDIMockConfiguration = .init(),
		            wBuilder: W.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                l: l,
		                wBuilder: wBuilder
		            )
		        }

		        var l: L.SafeDIMockConfiguration { __safeDI_storage.l }
		        var wBuilder: W.SafeDIMockConfiguration { __safeDI_storage.wBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                l: L.SafeDIMockConfiguration,
		                wBuilder: W.SafeDIMockConfiguration
		            ) {
		                self.l = l
		                self.wBuilder = wBuilder
		            }

		            let l: L.SafeDIMockConfiguration
		            let wBuilder: W.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_l(__safeDI_L_configuration: L.SafeDIMockConfiguration) -> L {
		            if let safeDIBuilder = __safeDI_L_configuration.safeDIBuilder { safeDIBuilder(__safeDI_L_configuration.title) } else { L(title: __safeDI_L_configuration.title) }
		        }
		        let l: L = __safeDI_l(__safeDI_L_configuration: safeDIOverrides.l)
		        func __safeDI_wBuilder(l: L, __safeDI_W_configuration: W.SafeDIMockConfiguration) -> W {
		            let uBuilder = Instantiator<U> {
		                __safeDI_uBuilder(l: l, __safeDI_U_configuration: U.SafeDIMockConfiguration(), __safeDI_W_configuration_nearest: __safeDI_W_configuration)
		            }
		            let vBuilder = Instantiator<V> {
		                __safeDI_vBuilder(l: l, __safeDI_V_configuration: __safeDI_W_configuration.vBuilder)
		            }
		            return if let safeDIBuilder = __safeDI_W_configuration.safeDIBuilder { safeDIBuilder(uBuilder, vBuilder) } else { W(uBuilder: uBuilder, vBuilder: vBuilder) }
		        }
		        func __safeDI_uBuilder(l: L, __safeDI_U_configuration: U.SafeDIMockConfiguration, __safeDI_W_configuration_nearest: W.SafeDIMockConfiguration?) -> U {
		            let pBuilder = Instantiator<P> {
		                __safeDI_pBuilder(__safeDI_P_configuration: P.SafeDIMockConfiguration(), __safeDI_W_configuration_nearest: __safeDI_W_configuration_nearest, __safeDI_U_configuration_nearest: __safeDI_U_configuration)
		            }
		            let wBuilder = Instantiator<W> {
		                __safeDI_wBuilder(l: l, __safeDI_W_configuration: __safeDI_W_configuration_nearest ?? W.SafeDIMockConfiguration())
		            }
		            return if let safeDIBuilder = __safeDI_U_configuration.safeDIBuilder { safeDIBuilder(pBuilder, wBuilder) } else { U(pBuilder: pBuilder, wBuilder: wBuilder) }
		        }
		        func __safeDI_pBuilder(__safeDI_P_configuration: P.SafeDIMockConfiguration, __safeDI_W_configuration_nearest: W.SafeDIMockConfiguration?, __safeDI_U_configuration_nearest: U.SafeDIMockConfiguration?) -> P {
		            let l: L = __safeDI_l(__safeDI_L_configuration: __safeDI_P_configuration.l)
		            let uBuilder = Instantiator<U> {
		                __safeDI_uBuilder(l: l, __safeDI_U_configuration: __safeDI_U_configuration_nearest ?? U.SafeDIMockConfiguration(), __safeDI_W_configuration_nearest: __safeDI_W_configuration_nearest)
		            }
		            return if let safeDIBuilder = __safeDI_P_configuration.safeDIBuilder { safeDIBuilder(l, uBuilder) } else { P(l: l, uBuilder: uBuilder) }
		        }
		        func __safeDI_vBuilder(l: L, __safeDI_V_configuration: ((L) -> V)?) -> V {
		            if let safeDIBuilder = __safeDI_V_configuration { safeDIBuilder(l) } else { V(l: l) }
		        }
		        let wBuilder = Instantiator<W> {
		            __safeDI_wBuilder(l: l, __safeDI_W_configuration: safeDIOverrides.wBuilder)
		        }
		        return Root(l: l, wBuilder: wBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		#expect(laidOut != mocks.walk.mockFiles["Root+SafeDIMock.swift"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixture, probes: [
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(l: .init(title: \"root\"))).wBuilder.instantiate().vBuilder.instantiate().l.title"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(l: .init(title: \"root\"))).wBuilder.instantiate().uBuilder.instantiate().pBuilder.instantiate().l.title"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(l: .init(title: \"root\"))).wBuilder.instantiate().uBuilder.instantiate().pBuilder.instantiate().uBuilder.instantiate().wBuilder.instantiate().vBuilder.instantiate().l.title"),
			DifferentialValueProbe(name: "the override of the root's W builds every W the cycles build again", expression: "{ () -> Int in var count = 0; let root = Root.mock(safeDIOverrides: .init(wBuilder: .init(vBuilder: nil, { uBuilder, vBuilder in count += 1; return W(uBuilder: uBuilder, vBuilder: vBuilder) }))); _ = root.wBuilder.instantiate().uBuilder.instantiate().pBuilder.instantiate().uBuilder.instantiate().wBuilder.instantiate(); return count }()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_evaluatesDefaultOncePerConstruction_whenSendableBuilderIsLaidOut() async throws {
		let mocks = try await generatedMocks(of: Self.sideEffectingDefaultFixture)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""
		let walk = mocks.walk.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(laidOut == generatedFileHeader + """
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

		        private final class __safeDI_Storage: Sendable {
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
		        @Sendable nonisolated func __safeDI_screenBuilder(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration) -> Screen {
		            let leaf = if let safeDIBuilder = __safeDI_Screen_configuration.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(leaf, __safeDI_Screen_configuration.stamp()) } else { Screen(leaf: leaf, stamp: __safeDI_Screen_configuration.stamp()) }
		        }
		        let __safeDI_screenBuilder____safeDI_Screen_configuration: Screen.SafeDIMockConfiguration = safeDIOverrides.screenBuilder
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(__safeDI_Screen_configuration: __safeDI_screenBuilder____safeDI_Screen_configuration)
		        }
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(laidOut)")
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: Self.sideEffectingDefaultFixture, probes: [
			DifferentialValueProbe(name: "two instances, each stamped once", expression: "{ let builder = Root.mock().screenBuilder; return [builder.instantiate(), builder.instantiate()] }()"),
		])
		#expect(walk != laidOut)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsWalksBody_whenProductionsRecordFunctionThrowsAtPlaceBuiltWithHandWrittenMockThatTakesNoDependency() async throws {
		// `MyService`'s hand-written mock takes no `database`, so the mock's scope leaves it out, and production's
		// initializer, which takes it, names an argument the scope does not declare.
		let fixtureFiles = [
			"Parent.swift": """
			@Instantiable(generateMock: true)
			public struct Parent: Instantiable {
			    public init(service: MyService) {
			        self.service = service
			    }
			    @Instantiated let service: MyService
			}
			""",
			"Database.swift": """
			@Instantiable
			public struct Database: Instantiable {
			    public init() {}
			}
			""",
			"MyService.swift": """
			@Instantiable
			public struct MyService: Instantiable {
			    public init(database: Database) {
			        self.database = database
			    }
			    @Instantiated let database: Database
			}
			""",
			"MyServiceMock.swift": """
			@Instantiable(mockOnly: true)
			extension MyService {
			    public static func mock() -> MyService { MyService(database: Database()) }
			}
			""",
		]
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		let mocks = try await MockLowering.$typeKeyLayoutObserver.withValue({ mockedType, outcome in continuation.yield("\(mockedType): \(outcome)") }) {
			try await generatedMocks(of: fixtureFiles)
		}
		continuation.finish()
		var outcomes = [String]()
		for await outcome in stream {
			outcomes.append(outcome)
		}

		#expect(outcomes == ["Parent: unrecorded:threw:unexpectedArgument:configuredConstruction"])
		#expect(mocks.laidOut.mockFiles == mocks.walk.mockFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutWithTypeKey_whenNothingSetsWhetherMocksAreLaidOut() async throws {
		let fixtureFiles = [
			"Parent.swift": """
			@Instantiable(generateMock: true)
			public struct Parent: Instantiable {
			    public init(child: Child) {
			        self.child = child
			    }
			    @Instantiated let child: Child
			}
			""",
			"Child.swift": """
			@Instantiable
			public struct Child: Instantiable {
			    public init() {}
			}
			""",
		]
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		// No value of `MockLowering.$laysOutWithTypeKey` is set here, as none is where SafeDITool runs.
		_ = try await MockLowering.$typeKeyLayoutObserver.withValue({ mockedType, outcome in continuation.yield("\(mockedType): \(outcome)") }) {
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var outcomes = [String]()
		for await outcome in stream {
			outcomes.append(outcome)
		}

		#expect(outcomes == ["Parent: laidOut"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenPlaceReadsInstanceOfLazyWrapperMockNamesApart() async throws {
		// `Root`'s tree receives `x` as the `LazilyInstantiated<X>` `A` reads, as the `Instantiator<X>` `E` reads, and as the
		// `Draft?` `C` reads only if available, so the mock binds the first two apart (`x_LazilyInstantiated__X`,
		// `x_Instantiator__X`). `N` receives `x: X?` only if available, which is the instance of the wrapper named apart.
		let fixtureFiles = [
			"Root.swift": seamFixtureType(named: "Root", isFinalClass: true, declarations: ["@Instantiated let n: N", "@Instantiated let e: E", "@Instantiated let a: A"])
				.replacingOccurrences(of: "@Instantiable", with: "@Instantiable(generateMock: true)"),
			"N.swift": seamFixtureType(named: "N", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?", "@Instantiated let c: C"]),
			"C.swift": seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: Draft?"]),
			"E.swift": seamFixtureType(named: "E", isFinalClass: true, declarations: ["@Received let x: Instantiator<X>"]),
			"A.swift": seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let x: LazilyInstantiated<X>"]),
			"X.swift": seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			"Draft.swift": """
			public final class Draft {
			    public init() {}
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("{ let x = X(); return Root.mock(safeDIOverrides: .init(x_LazilyInstantiated__X: { x })).n.x === x }()"),
			DifferentialValueProbe("{ let root = Root.mock(); return root.n.x === root.a.x.instance }()"),
			DifferentialValueProbe("{ let draft = Draft(); return Root.mock(safeDIOverrides: .init(x: draft)).n.c.x === draft }()"),
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Root`'s mock as the type key lays it out, and as the walk writes it.
	private mutating func generatedMocks(of fixtureFiles: [String: String]) async throws -> (laidOut: TestOutput, walk: TestOutput) {
		let laidOut = try await MockLowering.$laysOutWithTypeKey.withValue(true) {
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let walk = try await MockLowering.$laysOutWithTypeKey.withValue(false) {
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		return (laidOut, walk)
	}

	/// Compares what the laid-out mock builds for `probes` with what the walk's builds, the walk being the known-right path.
	private mutating func expectLaidOutValuesEqualWalks(
		_ mocks: (laidOut: TestOutput, walk: TestOutput),
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

	private static let leaf = """
	@Instantiable
	public final class Leaf: Instantiable, Sendable {
	    public init() {
	        tag = 0
	    }

	    public let tag: Int

	    private init(tag: Int) {
	        self.tag = tag
	    }

	    public static func tagged(_ tag: Int) -> Leaf {
	        Leaf(tag: tag)
	    }
	}
	"""

	private static let screen = """
	@Instantiable
	public final class Screen: Instantiable, Sendable {
	    public init(leaf: Leaf, title: String = "default") {
	        self.leaf = leaf
	        self.title = title
	    }

	    @Instantiated public let leaf: Leaf
	    public let title: String
	}
	"""

	private static let configuredNodeFixture = [
		"Leaf.swift": leaf,
		"Screen.swift": screen,
		"Root.swift": """
		@Instantiable(generateMock: true)
		public struct Root: Instantiable {
		    public init(screenBuilder: SendableInstantiator<Screen>) {
		        self.screenBuilder = screenBuilder
		    }

		    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
		}
		""",
	]

	private static let overrideClosureFixture = [
		"Leaf.swift": leaf,
		"Root.swift": """
		@Instantiable(generateMock: true)
		public struct Root: Instantiable {
		    public init(leafBuilder: SendableInstantiator<Leaf>) {
		        self.leafBuilder = leafBuilder
		    }

		    @Instantiated public let leafBuilder: SendableInstantiator<Leaf>
		}
		""",
	]

	/// `Panel` instantiates `Missing`, which no declaration fulfills, inside `screenBuilder`'s `@Sendable` function, so
	/// `mock()` takes it as a `@Sendable` autoclosure that `Panel`'s function binds at its top.
	private static let sendableAutoclosureFixture = [
		"Leaf.swift": leaf,
		"Missing.swift": """
		public struct Missing: Sendable {
		    public init(tag: Int) {
		        self.tag = tag
		    }

		    public let tag: Int

		    public static func next() -> Missing {
		        count += 1
		        return Missing(tag: count)
		    }

		    // The probe builds on one thread.
		    nonisolated(unsafe) private static var count = 0
		}
		""",
		"Panel.swift": """
		@Instantiable
		public struct Panel: Instantiable, Sendable {
		    public init(leaf: Leaf, missing: Missing) {
		        self.leaf = leaf
		        self.missing = missing
		    }

		    @Instantiated public let leaf: Leaf
		    @Instantiated public let missing: Missing
		}
		""",
		"Screen.swift": """
		@Instantiable
		public final class Screen: Instantiable, Sendable {
		    public init(panel: Panel) {
		        self.panel = panel
		    }

		    @Instantiated public let panel: Panel
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public struct Root: Instantiable {
		    public init(screenBuilder: SendableInstantiator<Screen>) {
		        self.screenBuilder = screenBuilder
		    }

		    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
		}
		""",
	]

	/// `Root` builds `User` twice and `NamedUser` once, which receive `service` as two types that nothing builds, so
	/// `mock()` takes each under a name of its own, which each builder function binds under the label at its top.
	private static let receiverBindingFixture = [
		"Service.swift": """
		public struct Service {
		    public init(tag: Int) {
		        self.tag = tag
		    }

		    public let tag: Int
		}
		""",
		"User.swift": """
		@Instantiable
		public struct User: Instantiable {
		    public init(service: Service) {
		        self.service = service
		    }

		    @Received public let service: Service
		}
		""",
		"NamedUser.swift": """
		@Instantiable
		public struct NamedUser: Instantiable {
		    public init(service: String) {
		        self.service = service
		    }

		    @Received public let service: String
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public struct Root: Instantiable {
		    public init(first: User, second: User, named: NamedUser) {
		        self.first = first
		        self.second = second
		        self.named = named
		    }

		    @Instantiated public let first: User
		    @Instantiated public let second: User
		    @Instantiated public let named: NamedUser
		}
		""",
	]

	/// `Screen`, built in `screenBuilder`'s `@Sendable` function, instantiates `aBuilder` and `bBuilder`, which receive one
	/// another: a loop of builders, whose functions rebind each other at their tops, closers that hand each member the
	/// configurations `Screen`'s function was handed, which it reads before no `@Sendable` closure captures them.
	private static let loopBeneathSendableBuilderFixture = [
		"Leaf.swift": leaf,
		"A.swift": """
		@Instantiable
		public final class A: Instantiable {
		    public init(bBuilder: Instantiator<B>) {
		        self.bBuilder = bBuilder
		    }

		    @Received public let bBuilder: Instantiator<B>
		}
		""",
		"B.swift": """
		@Instantiable
		public final class B: Instantiable {
		    public init(aBuilder: Instantiator<A>, leaf: Leaf) {
		        self.aBuilder = aBuilder
		        self.leaf = leaf
		    }

		    @Received public let aBuilder: Instantiator<A>
		    @Received public let leaf: Leaf
		}
		""",
		"Screen.swift": """
		@Instantiable
		public final class Screen: Instantiable {
		    public init(leaf: Leaf, aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
		        self.leaf = leaf
		        self.aBuilder = aBuilder
		        self.bBuilder = bBuilder
		    }

		    @Instantiated public let leaf: Leaf
		    @Instantiated public let aBuilder: Instantiator<A>
		    @Instantiated public let bBuilder: Instantiator<B>
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public struct Root: Instantiable {
		    public init(screenBuilder: SendableInstantiator<Screen>) {
		        self.screenBuilder = screenBuilder
		    }

		    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
		}
		""",
	]

	/// `Screen`'s default stamps each value it makes, so a default evaluated twice for one construction, or once for
	/// two, builds other stamps than the walk's.
	private static let sideEffectingDefaultFixture = [
		"Leaf.swift": leaf,
		"Stamp.swift": """
		public final class Stamp: Sendable {
		    public init() {
		        Stamp.count += 1
		        value = Stamp.count
		    }

		    public let value: Int

		    // The probe builds on one thread.
		    nonisolated(unsafe) private static var count = 0
		}
		""",
		"Screen.swift": """
		@Instantiable
		public final class Screen: Instantiable, Sendable {
		    public init(leaf: Leaf, stamp: Stamp = Stamp()) {
		        self.leaf = leaf
		        self.stamp = stamp
		    }

		    @Instantiated public let leaf: Leaf
		    public let stamp: Stamp
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public struct Root: Instantiable {
		    public init(screenBuilder: SendableInstantiator<Screen>) {
		        self.screenBuilder = screenBuilder
		    }

		    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
		}
		""",
	]

	private static let mockedLazyCycleFixture = [
		"Alpha.swift": """
		@Instantiable(generateMock: true)
		public final class Alpha: Instantiable {
		    public init(bravoBuilder: Instantiator<Bravo>) {
		        self.bravoBuilder = bravoBuilder
		    }

		    @Instantiated public let bravoBuilder: Instantiator<Bravo>
		}
		""",
		"Badge.swift": """
		@Instantiable
		public final class Badge: Instantiable {
		    public init(title: String = "default") {
		        self.title = title
		    }

		    public let title: String
		}
		""",
		"Bravo.swift": """
		@Instantiable(generateMock: true)
		public final class Bravo: Instantiable {
		    public init(alphaBuilder: Instantiator<Alpha>, badge: Badge) {
		        self.alphaBuilder = alphaBuilder
		        self.badge = badge
		    }

		    @Instantiated public let alphaBuilder: Instantiator<Alpha>
		    @Instantiated public let badge: Badge
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(alphaBuilder: Instantiator<Alpha>) {
		        self.alphaBuilder = alphaBuilder
		    }

		    @Instantiated public let alphaBuilder: Instantiator<Alpha>
		}
		""",
	]
}
