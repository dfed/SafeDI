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

/// A mock whose tree calls another module’s public mock, whose tree instantiates a type only if available that nothing
/// its module sees fulfills, so that the public mock takes a builder for it. Where the calling module sees a declaration
/// that fulfills the type, the calling mock fills each place with it, as the same types built inline in one module build
/// it there, and takes an optional builder that replaces the fills; where it sees none, it takes the builder, which
/// defaults to one that returns `nil`, and passes it up.
struct SafeDIToolCallingMockInstantiatedOnlyIfAvailableTests: ~Copyable {
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
	mutating func generate_fillsPlaceWithFulfillingType_whenCallingModuleFulfillsTypeCalledMocksTreeInstantiatesOnlyIfAvailable() async throws {
		let modules = Self.modules(appAddition: Self.analyticsImpl)
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
		            screen: Screen.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: Screen.SafeDIOverrides { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: Screen.SafeDIOverrides
		            ) {
		                self.screen = screen
		            }

		            let screen: Screen.SafeDIOverrides
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(middle: { _ in __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Middle_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(child: { _ in __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Child_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(analytics: { _ in
		                    let analytics: (any Analytics)? = AnalyticsImpl()
		                    return analytics
		                })
		            }
		            _ = Screen.__safeDI_Screen_mock_619EB7E40DC508C0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen(), safeDIOverrides: safeDIOverrides.screen)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Home.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderDefaultingToNilAndPassesItUp_whenCallingModuleFulfillsNoTypeCalledMocksTreeInstantiatesOnlyIfAvailable() async throws {
		let modules = Self.modules(appAddition: "")
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
		            screen: Screen.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: Screen.SafeDIOverrides { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: Screen.SafeDIOverrides
		            ) {
		                self.screen = screen
		            }

		            let screen: Screen.SafeDIOverrides
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: @escaping () -> (any Analytics)? = { nil },
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        let __safeDI_analyticsOptionalBuilder = analyticsOptionalBuilder
		        _ = Screen.__safeDI_Screen_mock_619EB7E40DC508C0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_screen() -> Screen {
		            let analyticsOptionalBuilder: () -> (any Analytics)? = __safeDI_analyticsOptionalBuilder
		            return Screen.__safeDI_mock(analyticsOptionalBuilder: .init(__safeDI_noScope: analyticsOptionalBuilder), safeDIOverrides: safeDIOverrides.screen)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Home.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithFulfillingType_whenCallingMockIsPublic() async throws {
		let modules = Self.modules(homeAttributes: "generateMock: .public", appAddition: Self.analyticsImpl)
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
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            screen: Screen.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        public var screen: Screen.SafeDIOverrides { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: Screen.SafeDIOverrides
		            ) {
		                self.screen = screen
		            }

		            let screen: Screen.SafeDIOverrides
		        }
		    }

		    public static func mock(
		        analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        Home.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        analyticsOptionalBuilder __safeDI_analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(middle: { _ in __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Middle_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(child: { _ in __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Child_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(analytics: { _ in
		                    let analytics: (any Analytics)? = AnalyticsImpl()
		                    return analytics
		                })
		            }
		            _ = Screen.__safeDI_Screen_mock_619EB7E40DC508C0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(analyticsOptionalBuilder: __safeDI_analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen(), safeDIOverrides: safeDIOverrides.screen)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_mock_26626E01916FB9DA {}
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Home.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithFulfillingType_whenCallingTypeInstantiatesAnotherTypeUnderPropertysLabel() async throws {
		let modules = Self.modules(homeDependencies: [("analytics", "AnalyticsClient"), ("screen", "Screen")], appAddition: Self.analyticsImpl + """


		@Instantiable
		public final class AnalyticsClient: Instantiable {
		    public init() {}
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
		            analytics: (() -> AnalyticsClient)? = nil,
		            screen: Screen.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                analytics: analytics,
		                screen: screen
		            )
		        }

		        var analytics: (() -> AnalyticsClient)? { __safeDI_storage.analytics }
		        var screen: Screen.SafeDIOverrides { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                analytics: (() -> AnalyticsClient)?,
		                screen: Screen.SafeDIOverrides
		            ) {
		                self.analytics = analytics
		                self.screen = screen
		            }

		            let analytics: (() -> AnalyticsClient)?
		            let screen: Screen.SafeDIOverrides
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { AnalyticsClient() }
		        func __safeDI_screen() -> Screen {
		            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(middle: { _ in __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Middle_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(child: { _ in __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Child_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(analytics: { _ in
		                    let analytics: (any Analytics)? = AnalyticsImpl()
		                    return analytics
		                })
		            }
		            _ = Screen.__safeDI_Screen_mock_619EB7E40DC508C0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen(), safeDIOverrides: safeDIOverrides.screen)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(analytics: analytics, screen: screen)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Home.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceInsideSendableFunction_whenCallIsMadeInsideSendableFunction() async throws {
		// The fill builds `AnalyticsImpl` inside the `@Sendable` function, as the same types built inline do.
		let modules = Self.modules(homeDependencies: [("screenBuilder", "SendableInstantiator<Screen>")], appAddition: Self.analyticsImpl)
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
		            screenBuilder: (@Sendable () -> Screen.SafeDIOverrides)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder
		            )
		        }

		        var screenBuilder: (@Sendable () -> Screen.SafeDIOverrides)? { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                screenBuilder: (@Sendable () -> Screen.SafeDIOverrides)?
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: (@Sendable () -> Screen.SafeDIOverrides)?
		        }
		    }

		    static func mock(
		        analyticsOptionalSendableBuilder: (@Sendable () -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        let __safeDI_screenBuilder__safeDIBuilder = safeDIOverrides.screenBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(middle: { _ in __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Middle_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(child: { _ in __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Child_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(analytics: { _ in
		                    let analytics: (any Analytics)? = AnalyticsImpl()
		                    return analytics
		                })
		            }
		            _ = Screen.__safeDI_Screen_mock_619EB7E40DC508C0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen(), safeDIOverrides: __safeDI_screenBuilder__safeDIBuilder?() ?? .init())
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Home(screenBuilder: screenBuilder)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Home.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsFulfillingTypesTreeAtPlace_whenFulfillingTypeInstantiatesType() async throws {
		let modules = Self.modules(appAddition: """
		@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
		public final class AnalyticsImpl: Instantiable, Analytics {
		    public init(uploader: Uploader) {
		        self.uploader = uploader
		    }

		    @Instantiated let uploader: Uploader
		}

		@Instantiable
		public final class Uploader: Instantiable {
		    public init() {}
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
		            screen: Screen.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: Screen.SafeDIOverrides { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: Screen.SafeDIOverrides
		            ) {
		                self.screen = screen
		            }

		            let screen: Screen.SafeDIOverrides
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_fillBody_7B18D6D5DA40E2A1() -> (any Analytics)? {
		            func __safeDI_analytics() -> AnalyticsImpl {
		                let uploader = Uploader()
		                return AnalyticsImpl(uploader: uploader)
		            }
		            let analytics: (any Analytics)? = __safeDI_analytics()
		            return analytics
		        }
		        func __safeDI_screen() -> Screen {
		            func __safeDI_analyticsOptionalBuilder_Screen_Child_Scope_analytics(_ scope: Screen.SafeDIMockScope_AnalyticsOptional.Child_Scope.analytics_Values) -> (any Analytics)? {
		                return __safeDI_fillBody_7B18D6D5DA40E2A1()
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(middle: { _ in __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Middle_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(child: { _ in __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Child_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(analytics: { scope in __safeDI_analyticsOptionalBuilder_Screen_Child_Scope_analytics(scope) })
		            }
		            _ = Screen.__safeDI_Screen_mock_619EB7E40DC508C0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen(), safeDIOverrides: safeDIOverrides.screen)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Home.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsFulfillingTypeValueOfPlace_whenFulfillingTypeReceivesValueCalledMocksTreeDeclares() async throws {
		// The same types built inline hand `AnalyticsImpl` the `client` `Middle` builds, which the place’s level carries.
		let modules = Self.modules(
			middleDependencies: [("client", "AnalyticsClient"), ("child", "Child")],
			featureAddition: """
			@Instantiable
			public final class AnalyticsClient: Instantiable {
			    public init() {}
			}
			""",
			appAddition: """
			@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
			public final class AnalyticsImpl: Instantiable, Analytics {
			    public init(client: AnalyticsClient) {
			        self.client = client
			    }

			    @Received let client: AnalyticsClient
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
		            screen: Screen.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: Screen.SafeDIOverrides { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: Screen.SafeDIOverrides
		            ) {
		                self.screen = screen
		            }

		            let screen: Screen.SafeDIOverrides
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(middle: { _ in __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Middle_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(child: { values in __safeDI_analyticsOptionalBuilder_Screen_Child_Scope(client: values.client) })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Child_Scope(client: AnalyticsClient) -> Screen.SafeDIMockScope_AnalyticsOptional.Child_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(analytics: { _ in
		                    let analytics: (any Analytics)? = AnalyticsImpl(client: client)
		                    return analytics
		                })
		            }
		            _ = Screen.__safeDI_Screen_mock_084DD0DC3C71F091.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen(), safeDIOverrides: safeDIOverrides.screen)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Home.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsFulfillingTypeValueOfPlace_whenFulfillingTypeReceivesValueOfTypeOnlyCalledModuleCanBuild() async throws {
		// As above, where the calling module could not build the value the fulfilling type receives at all.
		let modules = Self.modules(
			middleDependencies: [("client", "any ClientProtocol"), ("child", "Child")],
			featureAddition: """
			public protocol ClientProtocol {}

			@Instantiable(fulfillingAdditionalTypes: [ClientProtocol.self])
			final class AnalyticsClient: Instantiable, ClientProtocol {
			    init() {}
			}
			""",
			appAddition: """
			@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
			public final class AnalyticsImpl: Instantiable, Analytics {
			    public init(client: any ClientProtocol) {
			        self.client = client
			    }

			    @Received let client: any ClientProtocol
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
		            screen: Screen.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: Screen.SafeDIOverrides { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: Screen.SafeDIOverrides
		            ) {
		                self.screen = screen
		            }

		            let screen: Screen.SafeDIOverrides
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(middle: { _ in __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Middle_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(child: { values in __safeDI_analyticsOptionalBuilder_Screen_Child_Scope(client: values.client) })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Child_Scope(client: any ClientProtocol) -> Screen.SafeDIMockScope_AnalyticsOptional.Child_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(analytics: { _ in
		                    let analytics: (any Analytics)? = AnalyticsImpl(client: client)
		                    return analytics
		                })
		            }
		            _ = Screen.__safeDI_Screen_mock_E40FAEAEF5797779.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen(), safeDIOverrides: safeDIOverrides.screen)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Home.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsFulfillingTypeCallersValue_whenFulfillingTypeReceivesValueTypeBetweenMockedTypeAndCallDeclares() async throws {
		// The same types built inline hand `AnalyticsImpl` the `config` `Shell` builds, the caller’s own.
		let modules = Self.modules(
			homeDependencies: [("shell", "Shell")],
			appAddition: """
			@Instantiable
			public final class Shell: Instantiable {
			    public init(config: Config, screen: Screen) {
			        self.config = config
			        self.screen = screen
			    }

			    @Instantiated let config: Config
			    @Instantiated let screen: Screen
			}

			@Instantiable
			public final class Config: Instantiable {
			    public init() {}
			}

			@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
			public final class AnalyticsImpl: Instantiable, Analytics {
			    public init(config: Config) {
			        self.config = config
			    }

			    @Received let config: Config
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
		            shell: Shell.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                shell: shell
		            )
		        }

		        var shell: Shell.SafeDIMockConfiguration { __safeDI_storage.shell }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                shell: Shell.SafeDIMockConfiguration
		            ) {
		                self.shell = shell
		            }

		            let shell: Shell.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_shell() -> Shell {
		            let config = if let safeDIBuilder = safeDIOverrides.shell.config { safeDIBuilder() } else { Config() }
		            func __safeDI_screen() -> Screen {
		                func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                    .init(middle: { _ in __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() })
		                }
		                func __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Middle_Scope.__safeDI_Builder<(any Analytics)?> {
		                    .init(child: { _ in __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() })
		                }
		                func __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Child_Scope.__safeDI_Builder<(any Analytics)?> {
		                    .init(analytics: { _ in
		                        let analytics: (any Analytics)? = AnalyticsImpl(config: config)
		                        return analytics
		                    })
		                }
		                _ = Screen.__safeDI_Screen_mock_619EB7E40DC508C0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                return Screen.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen(), safeDIOverrides: safeDIOverrides.shell.screen)
		            }
		            let screen: Screen = __safeDI_screen()
		            return if let safeDIBuilder = safeDIOverrides.shell.safeDIBuilder { safeDIBuilder(config, screen) } else { Shell(config: config, screen: screen) }
		        }
		        let shell: Shell = __safeDI_shell()
		        return Home(shell: shell)
		    }
		}
		#endif

		#if DEBUG
		extension Shell {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            config: (() -> Config)? = nil,
		            screen: Screen.SafeDIOverrides = .init(),
		            _ safeDIBuilder: ((Config, Screen) -> Shell)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                config: config,
		                screen: screen,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var config: (() -> Config)? { __safeDI_storage.config }
		        var screen: Screen.SafeDIOverrides { __safeDI_storage.screen }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Config, Screen) -> Shell)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                config: (() -> Config)?,
		                screen: Screen.SafeDIOverrides,
		                safeDIBuilder: ((Config, Screen) -> Shell)?
		            ) {
		                self.config = config
		                self.screen = screen
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let config: (() -> Config)?
		            let screen: Screen.SafeDIOverrides
		            let safeDIBuilder: ((Config, Screen) -> Shell)?
		        }
		    }
		}
		#endif

		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Home.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEachCallsPlace_whenTwoCalledMocksTreesInstantiateTypeOnlyIfAvailable() async throws {
		// `Screen` and `Screen2` each instantiate `analytics` only if available, so the same types built inline build two
		// `AnalyticsImpl`s, one at each place, and so does the calling mock.
		let modules = Self.modules(
			homeDependencies: [("screen", "Screen"), ("screen2", "Screen2")],
			featureAddition: """
			@Instantiable(generateMock: .public)
			public final class Screen2: Instantiable {
			    init(child: Child) {
			        self.child = child
			    }

			    @Instantiated let child: Child
			}
			""",
			appAddition: Self.analyticsImpl,
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
		            screen: Screen.SafeDIOverrides = .init(),
		            screen2: Screen2.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen,
		                screen2: screen2
		            )
		        }

		        var screen: Screen.SafeDIOverrides { __safeDI_storage.screen }
		        var screen2: Screen2.SafeDIOverrides { __safeDI_storage.screen2 }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: Screen.SafeDIOverrides,
		                screen2: Screen2.SafeDIOverrides
		            ) {
		                self.screen = screen
		                self.screen2 = screen2
		            }

		            let screen: Screen.SafeDIOverrides
		            let screen2: Screen2.SafeDIOverrides
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(middle: { _ in __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Middle_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(child: { _ in __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Child_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(analytics: { _ in
		                    let analytics: (any Analytics)? = AnalyticsImpl()
		                    return analytics
		                })
		            }
		            _ = Screen.__safeDI_Screen_mock_619EB7E40DC508C0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen(), safeDIOverrides: safeDIOverrides.screen)
		        }
		        let screen: Screen = __safeDI_screen()
		        func __safeDI_screen2() -> Screen2 {
		            func __safeDI_analyticsOptionalBuilder_Screen2() -> Screen2.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(child: { _ in __safeDI_analyticsOptionalBuilder_Screen2_Child_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen2_Child_Scope() -> Screen2.SafeDIMockScope_AnalyticsOptional.Child_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(analytics: { _ in
		                    let analytics: (any Analytics)? = AnalyticsImpl()
		                    return analytics
		                })
		            }
		            _ = Screen2.__safeDI_Screen2_mock_3682D4C93D3CCB77.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen2.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen2(), safeDIOverrides: safeDIOverrides.screen2)
		        }
		        let screen2: Screen2 = __safeDI_screen2()
		        return Home(screen: screen, screen2: screen2)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Home.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesFulfillingTypeOverrideDefaultingToNil_whenFulfillingTypeReceivesOnlyIfAvailableValueNothingDeclares() async throws {
		// Nothing declares `token`, so production builds `AnalyticsImpl(token: nil)`. The mock built inline in one module
		// passes its override of `token`, which defaults to `nil`, and so does the fill.
		let modules = Self.modules(appAddition: """
		public final class Token {}

		@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
		public final class AnalyticsImpl: Instantiable, Analytics {
		    public init(token: Token?) {
		        self.token = token
		    }

		    @Received(onlyIfAvailable: true) let token: Token?
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
		            screen: Screen.SafeDIOverrides = .init(),
		            token: Token? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		            self.token = token
		        }

		        var screen: Screen.SafeDIOverrides { __safeDI_storage.screen }
		        let token: Token?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: Screen.SafeDIOverrides
		            ) {
		                self.screen = screen
		            }

		            let screen: Screen.SafeDIOverrides
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        let token: Token? = safeDIOverrides.token
		        func __safeDI_screen() -> Screen {
		            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(middle: { _ in __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Middle_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(child: { _ in __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Child_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(analytics: { _ in
		                    let analytics: (any Analytics)? = AnalyticsImpl(token: token)
		                    return analytics
		                })
		            }
		            _ = Screen.__safeDI_Screen_mock_619EB7E40DC508C0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen(), safeDIOverrides: safeDIOverrides.screen)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Home.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesFulfillingTypeNilAndTakesNoOverride_whenFulfillingTypeReceivesPropertyItFulfillsOnlyIfAvailable() async throws {
		// `AnalyticsImpl` is built as `analytics`, so its own receive of `analytics` reads a property still being built,
		// which the same types built inline pass `nil`: the mock offers no override of it and binds nothing for it.
		let modules = Self.modules(appAddition: """
		@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
		public final class AnalyticsImpl: Instantiable, Analytics {
		    public init(analytics: (any Analytics)?) {
		        self.analytics = analytics
		    }

		    @Received(onlyIfAvailable: true) let analytics: (any Analytics)?
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
		            screen: Screen.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: Screen.SafeDIOverrides { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: Screen.SafeDIOverrides
		            ) {
		                self.screen = screen
		            }

		            let screen: Screen.SafeDIOverrides
		        }
		    }

		    static func mock(
		        analyticsOptionalBuilder: (() -> (any Analytics)?)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_analyticsOptionalBuilder_Screen() -> Screen.SafeDIMockScope_AnalyticsOptional.__safeDI_Builder<(any Analytics)?> {
		                .init(middle: { _ in __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Middle_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Middle_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(child: { _ in __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() })
		            }
		            func __safeDI_analyticsOptionalBuilder_Screen_Child_Scope() -> Screen.SafeDIMockScope_AnalyticsOptional.Child_Scope.__safeDI_Builder<(any Analytics)?> {
		                .init(analytics: { _ in
		                    let analytics: (any Analytics)? = AnalyticsImpl(analytics: nil)
		                    return analytics
		                })
		            }
		            _ = Screen.__safeDI_Screen_mock_619EB7E40DC508C0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(analyticsOptionalBuilder: analyticsOptionalBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_analyticsOptionalBuilder_Screen(), safeDIOverrides: safeDIOverrides.screen)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Home.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCycleErrorAtDeclarations_whenFulfillingTypeInstantiatesCalledType() async {
		// `AnalyticsImpl` instantiates `Screen`, whose tree instantiates `analytics`, which `AnalyticsImpl` fulfills: the
		// cycle the same types built inline report, at declarations a person wrote.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Home.swift"]):18:5: error: Dependency cycle: `Screen` -> `Middle` -> `Child` -> `(any Analytics)?` -> `Screen`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `screen: Screen`, `middle: Middle`, `child: Child`, `analytics: (any Analytics)?` to an instantiator.
			\(fixtures["Feature"]!["Screen.swift"]):5:1: note: `Screen` is part of the cycle
			\(fixtures["Feature"]!["Screen.swift"]):14:1: note: `Middle` is part of the cycle
			\(fixtures["Feature"]!["Screen.swift"]):23:1: note: `Child` is part of the cycle
			\(fixtures["App"]!["Home.swift"]):12:1: note: `Analytics` is part of the cycle
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(appAddition: """
			@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
			public final class AnalyticsImpl: Instantiable, Analytics {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			"""), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let analyticsImpl = """
	@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
	public final class AnalyticsImpl: Instantiable, Analytics {
	    public init() {}
	}
	"""

	/// `Feature`, whose `Screen` has a public mock and an internal initializer, so `App`, in another package, calls the
	/// mock; `Child`, beneath `Screen`, instantiates `analytics` only if available, which nothing in `Feature` fulfills.
	/// `Middle` instantiates `middleDependencies`, and `Feature` also declares `featureAddition`. `App` declares `Home`,
	/// declared with `homeAttributes`, which instantiates `homeDependencies`, and `appAddition`.
	private static func modules(
		homeAttributes: String = "generateMock: true",
		homeDependencies: [(label: String, type: String)] = [("screen", "Screen")],
		middleDependencies: [(label: String, type: String)] = [("child", "Child")],
		featureAddition: String = "",
		appAddition: String,
	) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "shop", swiftFileContentByFilePath: ["Screen.swift": """
			import SafeDI

			public protocol Analytics {}

			@Instantiable(generateMock: .public)
			public final class Screen: Instantiable {
			    init(middle: Middle) {
			        self.middle = middle
			    }

			    @Instantiated let middle: Middle
			}

			@Instantiable
			final class Middle: Instantiable {
			    init(\(middleDependencies.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
			\(middleDependencies.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n"))
			    }

			\(middleDependencies.map { "    @Instantiated let \($0.label): \($0.type)" }.joined(separator: "\n"))
			}

			@Instantiable
			final class Child: Instantiable {
			    init(analytics: (any Analytics)?) {
			        self.analytics = analytics
			    }

			    @Instantiated(onlyIfAvailable: true) let analytics: (any Analytics)?
			}

			""" + featureAddition]),
			ModuleFixture(name: "App", packageName: "other", swiftFileContentByFilePath: ["Home.swift": """
			import Feature
			import SafeDI

			@Instantiable(\(homeAttributes))
			public final class Home: Instantiable {
			    public init(\(homeDependencies.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
			\(homeDependencies.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n"))
			    }

			\(homeDependencies.map { "    @Instantiated public let \($0.label): \($0.type)" }.joined(separator: "\n"))
			}

			""" + appAddition], dependencies: ["Feature"]),
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
