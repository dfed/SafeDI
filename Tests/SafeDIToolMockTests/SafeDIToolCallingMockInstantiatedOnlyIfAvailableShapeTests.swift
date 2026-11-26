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

/// The neighbors of the shape `SafeDIToolCallingMockInstantiatedOnlyIfAvailableTests` pins: a mock in one module whose
/// tree calls another module’s public mock, whose tree instantiates a type only if available that nothing its module
/// sees fulfills. These vary what that suite holds fixed: the integration that runs the tool, the module that fulfills
/// the type (a third one, or none, with a public mock between), the declaration that fulfills it (a `mockOnly` fake, an
/// extension), how the property’s type is spelled (a class, a nested protocol), the place’s level (the called mock’s
/// root), and a calling type that also instantiates the label only if available. Each compares its values with the
/// same types’ mocks built inline in one module.
struct SafeDIToolCallingMockInstantiatedOnlyIfAvailableShapeTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithFulfillingType_whenSwiftPackagePluginGeneratesCallingModule() async throws {
		let modules = Self.modules(packageOfApp: "shop", app: Self.home + Self.analyticsImpl)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .swiftPackagePlugin, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == [
			"Home+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Home {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            screen: ((@escaping () -> (any Analytics)?) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                screen: screen
			            )
			        }

			        var screen: ((@escaping () -> (any Analytics)?) -> Screen)? { __safeDI_storage.screen }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                screen: ((@escaping () -> (any Analytics)?) -> Screen)?
			            ) {
			                self.screen = screen
			            }

			            let screen: ((@escaping () -> (any Analytics)?) -> Screen)?
			        }
			    }

			    static func mock(
			        analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Home {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_analyticsOptionalBuilder_Screen_analytics() -> (any Analytics)? {
			                let analytics: (any Analytics)? = AnalyticsImpl()
			                return analytics
			            }
			            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
			                .init(analytics: { _ in __safeDI_analyticsOptionalBuilder_Screen_analytics() })
			            }
			            _ = Screen.__safeDI_Screen_mock_6C25C81712F913A1.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
			            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder({ if let analyticsOptionalBuilder { analyticsOptionalBuilder() } else { __safeDI_analyticsOptionalBuilder_Screen_analytics() } }) } else { Screen.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen()) }
			        }
			        let screen: Screen = __safeDI_screen()
			        return Home(screen: screen)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif


			""",
		])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Home.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderDefaultingToNilAndPassesItUp_whenSwiftPackagePluginGeneratesCallingModule() async throws {
		let modules = Self.modules(packageOfApp: "shop", app: Self.home)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .swiftPackagePlugin, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == [
			"Home+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Home {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            screen: ((@escaping () -> (any Analytics)?) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                screen: screen
			            )
			        }

			        var screen: ((@escaping () -> (any Analytics)?) -> Screen)? { __safeDI_storage.screen }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                screen: ((@escaping () -> (any Analytics)?) -> Screen)?
			            ) {
			                self.screen = screen
			            }

			            let screen: ((@escaping () -> (any Analytics)?) -> Screen)?
			        }
			    }

			    static func mock(
			        analyticsOptionalBuilder: @escaping () -> (any Analytics)? = { nil },
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Home {
			        let __safeDI_analyticsOptionalBuilder = analyticsOptionalBuilder
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_mock_6C25C81712F913A1.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
			            let analyticsOptionalBuilder: () -> (any Analytics)? = __safeDI_analyticsOptionalBuilder
			            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder(analyticsOptionalBuilder) } else { Screen.__safeDI_mock(analyticsOptionalBuilder: .init(__safeDI_noScope: analyticsOptionalBuilder)) }
			        }
			        let screen: Screen = __safeDI_screen()
			        return Home(screen: screen)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif


			""",
		])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Home.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithFake_whenOnlyMockOnlyDeclarationOfCallingModuleFulfillsType() async throws {
		let modules = Self.modules(app: Self.home + """

		@Instantiable(fulfillingAdditionalTypes: [Analytics.self], mockOnly: true)
		public final class AnalyticsFake: Instantiable, Analytics {
		    public init() {}

		    public static func mock() -> AnalyticsFake {
		        AnalyticsFake()
		    }
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen: ((@escaping () -> (any Analytics)?) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: ((@escaping () -> (any Analytics)?) -> Screen)? { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: ((@escaping () -> (any Analytics)?) -> Screen)?
		            ) {
		                self.screen = screen
		            }

		            let screen: ((@escaping () -> (any Analytics)?) -> Screen)?
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_analyticsOptionalBuilder_Screen_analytics() -> (any Analytics)? {
		                let analytics: (any Analytics)? = AnalyticsFake.mock()
		                return analytics
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(analytics: { _ in __safeDI_analyticsOptionalBuilder_Screen_analytics() })
		            }
		            _ = Screen.__safeDI_Screen_mock_6C25C81712F913A1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder({ if let analyticsOptionalBuilder { analyticsOptionalBuilder() } else { __safeDI_analyticsOptionalBuilder_Screen_analytics() } }) } else { Screen.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen()) }
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Home.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithExtensionsType_whenExtensionInCallingModuleFulfillsType() async throws {
		let modules = Self.modules(app: Self.home + """

		public final class AnalyticsService: Instantiable, Analytics {
		    init() {}
		}

		@Instantiable(fulfillingAdditionalTypes: [Analytics.self], conformsElsewhere: true)
		extension AnalyticsService {
		    public static func instantiate() -> AnalyticsService {
		        AnalyticsService()
		    }
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen: ((@escaping () -> (any Analytics)?) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: ((@escaping () -> (any Analytics)?) -> Screen)? { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: ((@escaping () -> (any Analytics)?) -> Screen)?
		            ) {
		                self.screen = screen
		            }

		            let screen: ((@escaping () -> (any Analytics)?) -> Screen)?
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_analyticsOptionalBuilder_Screen_analytics() -> (any Analytics)? {
		                let analytics: (any Analytics)? = AnalyticsService.instantiate()
		                return analytics
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(analytics: { _ in __safeDI_analyticsOptionalBuilder_Screen_analytics() })
		            }
		            _ = Screen.__safeDI_Screen_mock_6C25C81712F913A1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder({ if let analyticsOptionalBuilder { analyticsOptionalBuilder() } else { __safeDI_analyticsOptionalBuilder_Screen_analytics() } }) } else { Screen.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen()) }
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Home.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithSubclass_whenPropertysTypeIsClassOfCalledModule() async throws {
		let modules = Self.modules(
			feature: """
			import SafeDI

			open class Analytics {
			    public init() {}
			}

			""" + Self.screen(propertyType: "Analytics?"),
			app: Self.home + """

			@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
			public final class AnalyticsImpl: Analytics, Instantiable {
			    public override init() {}
			}
			""",
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen: ((@escaping () -> Analytics?) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: ((@escaping () -> Analytics?) -> Screen)? { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: ((@escaping () -> Analytics?) -> Screen)?
		            ) {
		                self.screen = screen
		            }

		            let screen: ((@escaping () -> Analytics?) -> Screen)?
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: (() -> Analytics?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_analyticsOptionalBuilder_Screen_analytics() -> Analytics? {
		                let analytics: Analytics? = AnalyticsImpl()
		                return analytics
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<Analytics?> {
		                .init(analytics: { _ in __safeDI_analyticsOptionalBuilder_Screen_analytics() })
		            }
		            _ = Screen.__safeDI_Screen_mock_6C25C81712F913A1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder({ if let analyticsOptionalBuilder { analyticsOptionalBuilder() } else { __safeDI_analyticsOptionalBuilder_Screen_analytics() } }) } else { Screen.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen()) }
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Home.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithFulfillingType_whenPropertysTypeIsNestedProtocol() async throws {
		let modules = Self.modules(
			feature: """
			import SafeDI

			public enum Tracking {
			    public protocol Analytics {}
			}

			""" + Self.screen(propertyType: "(any Tracking.Analytics)?"),
			app: Self.home + """

			@Instantiable(fulfillingAdditionalTypes: [Tracking.Analytics.self])
			public final class AnalyticsImpl: Instantiable, Tracking.Analytics {
			    public init() {}
			}
			""",
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen: ((@escaping () -> (any Tracking.Analytics)?) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: ((@escaping () -> (any Tracking.Analytics)?) -> Screen)? { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: ((@escaping () -> (any Tracking.Analytics)?) -> Screen)?
		            ) {
		                self.screen = screen
		            }

		            let screen: ((@escaping () -> (any Tracking.Analytics)?) -> Screen)?
		        }
		    }

		    static func mock(
		        tracking_AnalyticsOptionalBuilder: (() -> (any Tracking.Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_tracking_AnalyticsOptionalBuilder_Screen_analytics() -> (any Tracking.Analytics)? {
		                let analytics: (any Tracking.Analytics)? = AnalyticsImpl()
		                return analytics
		            }
		            func __safeDI_tracking_AnalyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_Tracking_AnalyticsOptional.__safeDI_Builder<(any Tracking.Analytics)?> {
		                .init(analytics: { _ in __safeDI_tracking_AnalyticsOptionalBuilder_Screen_analytics() })
		            }
		            _ = Screen.__safeDI_Screen_mock_B3D39BB11242968E.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder({ if let tracking_AnalyticsOptionalBuilder { tracking_AnalyticsOptionalBuilder() } else { __safeDI_tracking_AnalyticsOptionalBuilder_Screen_analytics() } }) } else { Screen.__safeDI_mock(tracking_AnalyticsOptionalBuilder: tracking_AnalyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_tracking_AnalyticsOptionalBuilder_Screen()) }
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Home.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOwnOverrideBesideBuilderItPassesUp_whenCallingTypeAlsoInstantiatesLabelOnlyIfAvailable() async throws {
		let modules = Self.modules(app: """
		import Feature
		import SafeDI

		@Instantiable(generateMock: true)
		public final class Home: Instantiable {
		    public init(analytics: (any Analytics)?, screen: Screen) {
		        self.analytics = analytics
		        self.screen = screen
		    }

		    @Instantiated(onlyIfAvailable: true) public let analytics: (any Analytics)?
		    @Instantiated public let screen: Screen
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen: ((@escaping () -> (any Analytics)?) -> Screen)? = nil,
		            analytics: (any Analytics)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		            self.analytics = analytics
		        }

		        var screen: ((@escaping () -> (any Analytics)?) -> Screen)? { __safeDI_storage.screen }
		        let analytics: (any Analytics)?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: ((@escaping () -> (any Analytics)?) -> Screen)?
		            ) {
		                self.screen = screen
		            }

		            let screen: ((@escaping () -> (any Analytics)?) -> Screen)?
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: @escaping () -> (any Analytics)? = { nil },
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        let __safeDI_analyticsOptionalBuilder = analyticsOptionalBuilder
		        let analytics: (any Analytics)? = safeDIOverrides.analytics
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_mock_6C25C81712F913A1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let analyticsOptionalBuilder: () -> (any Analytics)? = __safeDI_analyticsOptionalBuilder
		            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder(analyticsOptionalBuilder) } else { Screen.__safeDI_mock(analyticsOptionalBuilder: .init(__safeDI_noScope: analyticsOptionalBuilder)) }
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(analytics: analytics, screen: screen)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Home.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceBeneathPublicCallingMock_whenOutermostCallingModuleFulfillsType() async throws {
		let modules = Self.threeModules(app: Self.shelfHome + Self.analyticsImpl)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["Shelf"]?.generatedFiles == ["Shelf.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_AnalyticsOptional {
		        nonisolated public struct screen_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let screen: (screen_Values) -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<__safeDI_Built>

		            public init(screen: @escaping (screen_Values) -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<__safeDI_Built>) {
		                self.screen = screen
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(screen: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init() {}
		    }

		    public static func mock(
		        analyticsOptionalBuilder: @escaping () -> (any Analytics)? = { nil },
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        Panel.__safeDI_mock(analyticsOptionalBuilder: .init(__safeDI_noScope: analyticsOptionalBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        analyticsOptionalBuilder __safeDI_analyticsOptionalBuilder: Panel.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> = .init(__safeDI_noScope: { nil }),
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        _ = Screen.__safeDI_Screen_mock_6C25C81712F913A1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let screen = Screen.__safeDI_mock(analyticsOptionalBuilder: __safeDI_analyticsOptionalBuilder.screen(SafeDIMockScope_AnalyticsOptional.screen_Values()))
		        return Panel(screen: screen)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_24B606DDA22B1C0C {}
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
		#if canImport(Shelf)
		import Shelf
		#endif

		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            panel: Panel.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel
		            )
		        }

		        var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                panel: Panel.SafeDIOverrides
		            ) {
		                self.panel = panel
		            }

		            let panel: Panel.SafeDIOverrides
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_panel() -> Panel {
		            func __safeDI_analyticsOptionalBuilder_Panel() -> Panel.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(screen: { _ in __safeDI_analyticsOptionalBuilder_Screen() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(analytics: { _ in
		                    let analytics: (any Analytics)? = AnalyticsImpl()
		                    return analytics
		                })
		            }
		            _ = Panel.__safeDI_Panel_mock_24B606DDA22B1C0C.self // If this line does not compile, compile the code SafeDI generates for module Shelf into Shelf: under Bazel, add Shelf’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Panel.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Panel(), safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Home(panel: panel)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Home.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderUpThroughPublicCallingMock_whenNoModuleFulfillsType() async throws {
		let modules = Self.threeModules(app: Self.shelfHome)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Shelf)
		import Shelf
		#endif

		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            panel: Panel.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel
		            )
		        }

		        var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                panel: Panel.SafeDIOverrides
		            ) {
		                self.panel = panel
		            }

		            let panel: Panel.SafeDIOverrides
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: @escaping () -> (any Analytics)? = { nil },
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        let __safeDI_analyticsOptionalBuilder = analyticsOptionalBuilder
		        func __safeDI_panel() -> Panel {
		            _ = Panel.__safeDI_Panel_mock_24B606DDA22B1C0C.self // If this line does not compile, compile the code SafeDI generates for module Shelf into Shelf: under Bazel, add Shelf’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let analyticsOptionalBuilder: () -> (any Analytics)? = __safeDI_analyticsOptionalBuilder
		            return Panel.__safeDI_mock(analyticsOptionalBuilder: .init(__safeDI_noScope: analyticsOptionalBuilder), safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Home(panel: panel)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Home.mock()")])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Screen`, a `Feature` type with a public mock and an internal initializer, so that a module beside it calls the
	/// mock, which instantiates `analytics` of `propertyType` only if available at its root.
	private static func screen(propertyType: String) -> String {
		"""
		@Instantiable(generateMock: .public)
		public final class Screen: Instantiable {
		    init(analytics: \(propertyType)) {
		        self.analytics = analytics
		    }

		    @Instantiated(onlyIfAvailable: true) let analytics: \(propertyType)
		}

		"""
	}

	private static let feature = """
	import SafeDI

	public protocol Analytics {}

	""" + screen(propertyType: "(any Analytics)?")

	private static let home = """
	import Feature
	import SafeDI

	@Instantiable(generateMock: true)
	public final class Home: Instantiable {
	    public init(screen: Screen) {
	        self.screen = screen
	    }

	    @Instantiated public let screen: Screen
	}

	"""

	private static let analyticsImpl = """

	@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
	public final class AnalyticsImpl: Instantiable, Analytics {
	    public init() {}
	}
	"""

	/// `Home`, in `App`, which builds `Shelf`’s `Panel`.
	private static let shelfHome = """
	import Feature
	import SafeDI
	import Shelf

	@Instantiable(generateMock: true)
	public final class Home: Instantiable {
	    public init(panel: Panel) {
	        self.panel = panel
	    }

	    @Instantiated public let panel: Panel
	}

	"""

	/// `Feature`, holding `feature`, and `App`, in package `packageOfApp`, holding `app`.
	private static func modules(feature: String = feature, packageOfApp: String = "other", app: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "shop", swiftFileContentByFilePath: ["Screen.swift": feature]),
			ModuleFixture(name: "App", packageName: packageOfApp, swiftFileContentByFilePath: ["Home.swift": app], dependencies: ["Feature"]),
		]
	}

	/// `Feature`; `Shelf`, in a package of its own, whose `Panel` has a public mock and an internal initializer and
	/// builds `Screen`, and which declares no type that fulfills `Analytics`; and `App`, in a third package, holding `app`.
	private static func threeModules(app: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "shop", swiftFileContentByFilePath: ["Screen.swift": feature]),
			ModuleFixture(name: "Shelf", packageName: "shelf", swiftFileContentByFilePath: ["Panel.swift": """
			import Feature
			import SafeDI

			@Instantiable(generateMock: .public)
			public final class Panel: Instantiable {
			    init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}

			"""], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "other", swiftFileContentByFilePath: ["Home.swift": app], dependencies: ["Feature", "Shelf"]),
		]
	}

	/// Compiles `output` and the same types built in one module, with every public mock an internal one, and compares what
	/// `probes` build in each.
	private mutating func expectValuesAgreeWithInlineMocks(
		of modules: [ModuleFixture],
		output: MultiModuleTestOutput,
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let moduleNames = Set(modules.map(\.name))
		func inline(_ source: String) -> String {
			source
				.split(separator: "\n", omittingEmptySubsequences: false)
				.filter { line in !moduleNames.contains { line == "import \($0)" } }
				.joined(separator: "\n")
				.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")
		}
		var inlineFiles = [String: String]()
		for module in modules {
			for (fileName, content) in module.swiftFileContentByFilePath {
				inlineFiles["\(module.name)_\(fileName)"] = inline(content)
			}
		}
		let inlineModules = [ModuleFixture(name: modules[0].name, packageName: modules[0].packageName, swiftFileContentByFilePath: inlineFiles)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		func path(of modules: [ModuleFixture], output: MultiModuleTestOutput) throws -> DifferentialValuePath {
			try DifferentialValuePath(modules: modules.map { module in
				try DifferentialValueModule(
					name: module.name,
					packageName: module.packageName,
					dependencyModuleNames: module.dependencies,
					fixtureFiles: module.swiftFileContentByFilePath,
					generatedFiles: #require(output.modules[module.name], sourceLocation: sourceLocation).generatedFiles,
				)
			})
		}
		try await expectDifferentialValuesAgree(
			feature: path(of: modules, output: output),
			knownRight: path(of: inlineModules, output: inlineOutput),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
