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

/// An internal mock that builds, inside a `@Sendable` builder function, a type whose tree calls other modules' public
/// mocks, passes their unfilled places up as builders it takes, which that function captures, so it takes each of them
/// `@Sendable`, also when two calls' places share one builder.
struct SafeDIToolPublicMockSendablePassedUpBuilderTests: ~Copyable {
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
	mutating func generate_takesTheSharedBuilderSendable_whenTwoPublicMockCallsInASendableFunctionPassUpErasedInstantiatorPlaces() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.erasedHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel", "@Instantiated let panelTwin: PanelTwin"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
		        nonisolated public struct holeBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(holeBuilder: { _ in { _ in __safeDI_builder() } })
		            }
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleBuilder: @escaping () -> AnyHole
		    ) -> Panel {
		        Panel.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleBuilder __safeDI_holeFill_AnyHoleBuilder: Panel.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> Panel {
		        let holeBuilder = ErasedInstantiator<(), AnyHole>(__safeDI_holeFill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_HoleFill_AnyHole.holeBuilder_Values()))
		        return Panel(holeBuilder: holeBuilder)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_E9531DCA567FCD91 {}
		}
		#endif

		#if DEBUG
		extension PanelTwin {
		    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
		        nonisolated public struct holeBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(holeBuilder: { _ in { _ in __safeDI_builder() } })
		            }
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleBuilder: @escaping () -> AnyHole
		    ) -> PanelTwin {
		        PanelTwin.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleBuilder __safeDI_holeFill_AnyHoleBuilder: PanelTwin.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> PanelTwin {
		        let holeBuilder = ErasedInstantiator<(), AnyHole>(__safeDI_holeFill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_HoleFill_AnyHole.holeBuilder_Values()))
		        return PanelTwin(holeBuilder: holeBuilder)
		    }
		}

		extension PanelTwin {
		    public enum __safeDI_PanelTwin_mock_EF93364769284E49 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

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
		        holeFill_AnyHoleSendableBuilder: @escaping @Sendable () -> AnyHole,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_screenBuilder__overrides = safeDIOverrides.screenBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            _ = Panel.__safeDI_Panel_mock_E9531DCA567FCD91.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panel() -> Panel {
		                let holeFill_AnyHoleBuilder: () -> AnyHole = holeFill_AnyHoleSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panel { safeDIBuilder(holeFill_AnyHoleBuilder) } else { Panel.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder)) }
		            }
		            let panel: Panel = __safeDI_panel()
		            _ = PanelTwin.__safeDI_PanelTwin_mock_EF93364769284E49.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelTwin() -> PanelTwin {
		                let holeFill_AnyHoleBuilder: () -> AnyHole = holeFill_AnyHoleSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panelTwin { safeDIBuilder(holeFill_AnyHoleBuilder) } else { PanelTwin.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder)) }
		            }
		            let panelTwin: PanelTwin = __safeDI_panelTwin()
		            return if let safeDIBuilder = __safeDI_screenBuilder__overrides.safeDIBuilder { safeDIBuilder(panel, panelTwin) } else { Screen(panel: panel, panelTwin: panelTwin) }
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Screen {
		    /// Configuration for how this type is constructed within a mock tree.
		    nonisolated struct SafeDIMockConfiguration: Sendable {
		        init(
		            panel: (@Sendable (@escaping () -> AnyHole) -> Panel)? = nil,
		            panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)? = nil,
		            _ safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel,
		                panelTwin: panelTwin,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var panel: (@Sendable (@escaping () -> AnyHole) -> Panel)? { __safeDI_storage.panel }
		        var panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)? { __safeDI_storage.panelTwin }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                panel: (@Sendable (@escaping () -> AnyHole) -> Panel)?,
		                panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)?,
		                safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		            ) {
		                self.panel = panel
		                self.panelTwin = panelTwin
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let panel: (@Sendable (@escaping () -> AnyHole) -> Panel)?
		            let panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)?
		            let safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		        }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTheSharedBuilderSendable_whenTwoPublicMockCallsInASendableFunctionPassUpInstantiatorPlaces() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.instantiatorHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel", "@Instantiated let panelTwin: PanelTwin"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Hole {
		        nonisolated public struct holeBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.init(holeBuilder: { _ in __safeDI_builder })
		            }
		        }
		    }

		    public static func mock(
		        holeBuilder: @escaping Instantiator<Hole>.Builder
		    ) -> Panel {
		        Panel.__safeDI_mock(holeBuilder: .init(__safeDI_noScope: holeBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeBuilder __safeDI_holeBuilder: Panel.SafeDIMockScope_Hole.__safeDI_Builder<Hole>
		    ) -> Panel {
		        let holeBuilder = Instantiator<Hole>(__safeDI_holeBuilder.holeBuilder(SafeDIMockScope_Hole.holeBuilder_Values()))
		        return Panel(holeBuilder: holeBuilder)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_F0F10F2194E82F9F {}
		}
		#endif

		#if DEBUG
		extension PanelTwin {
		    nonisolated public enum SafeDIMockScope_Hole {
		        nonisolated public struct holeBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.init(holeBuilder: { _ in __safeDI_builder })
		            }
		        }
		    }

		    public static func mock(
		        holeBuilder: @escaping Instantiator<Hole>.Builder
		    ) -> PanelTwin {
		        PanelTwin.__safeDI_mock(holeBuilder: .init(__safeDI_noScope: holeBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeBuilder __safeDI_holeBuilder: PanelTwin.SafeDIMockScope_Hole.__safeDI_Builder<Hole>
		    ) -> PanelTwin {
		        let holeBuilder = Instantiator<Hole>(__safeDI_holeBuilder.holeBuilder(SafeDIMockScope_Hole.holeBuilder_Values()))
		        return PanelTwin(holeBuilder: holeBuilder)
		    }
		}

		extension PanelTwin {
		    public enum __safeDI_PanelTwin_mock_7B9FDEC77160773F {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

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
		        holeSendableBuilder: @escaping SendableInstantiator<Hole>.Builder,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_screenBuilder__overrides = safeDIOverrides.screenBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            _ = Panel.__safeDI_Panel_mock_F0F10F2194E82F9F.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panel() -> Panel {
		                let holeBuilder: Instantiator<Hole>.Builder = holeSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panel { safeDIBuilder(holeBuilder) } else { Panel.__safeDI_mock(holeBuilder: .init(__safeDI_noScope: holeBuilder)) }
		            }
		            let panel: Panel = __safeDI_panel()
		            _ = PanelTwin.__safeDI_PanelTwin_mock_7B9FDEC77160773F.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelTwin() -> PanelTwin {
		                let holeBuilder: Instantiator<Hole>.Builder = holeSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panelTwin { safeDIBuilder(holeBuilder) } else { PanelTwin.__safeDI_mock(holeBuilder: .init(__safeDI_noScope: holeBuilder)) }
		            }
		            let panelTwin: PanelTwin = __safeDI_panelTwin()
		            return if let safeDIBuilder = __safeDI_screenBuilder__overrides.safeDIBuilder { safeDIBuilder(panel, panelTwin) } else { Screen(panel: panel, panelTwin: panelTwin) }
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Screen {
		    /// Configuration for how this type is constructed within a mock tree.
		    nonisolated struct SafeDIMockConfiguration: Sendable {
		        init(
		            panel: (@Sendable (@escaping Instantiator<Hole>.Builder) -> Panel)? = nil,
		            panelTwin: (@Sendable (@escaping Instantiator<Hole>.Builder) -> PanelTwin)? = nil,
		            _ safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel,
		                panelTwin: panelTwin,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var panel: (@Sendable (@escaping Instantiator<Hole>.Builder) -> Panel)? { __safeDI_storage.panel }
		        var panelTwin: (@Sendable (@escaping Instantiator<Hole>.Builder) -> PanelTwin)? { __safeDI_storage.panelTwin }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                panel: (@Sendable (@escaping Instantiator<Hole>.Builder) -> Panel)?,
		                panelTwin: (@Sendable (@escaping Instantiator<Hole>.Builder) -> PanelTwin)?,
		                safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		            ) {
		                self.panel = panel
		                self.panelTwin = panelTwin
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let panel: (@Sendable (@escaping Instantiator<Hole>.Builder) -> Panel)?
		            let panelTwin: (@Sendable (@escaping Instantiator<Hole>.Builder) -> PanelTwin)?
		            let safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		        }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTheBuilderSendable_whenOnePublicMockCallInASendableFunctionPassesUpAnErasedInstantiatorPlace() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.erasedHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
		        nonisolated public struct holeBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(holeBuilder: { _ in { _ in __safeDI_builder() } })
		            }
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleBuilder: @escaping () -> AnyHole
		    ) -> Panel {
		        Panel.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleBuilder __safeDI_holeFill_AnyHoleBuilder: Panel.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> Panel {
		        let holeBuilder = ErasedInstantiator<(), AnyHole>(__safeDI_holeFill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_HoleFill_AnyHole.holeBuilder_Values()))
		        return Panel(holeBuilder: holeBuilder)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_E9531DCA567FCD91 {}
		}
		#endif

		#if DEBUG
		extension PanelTwin {
		    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
		        nonisolated public struct holeBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(holeBuilder: { _ in { _ in __safeDI_builder() } })
		            }
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleBuilder: @escaping () -> AnyHole
		    ) -> PanelTwin {
		        PanelTwin.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleBuilder __safeDI_holeFill_AnyHoleBuilder: PanelTwin.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> PanelTwin {
		        let holeBuilder = ErasedInstantiator<(), AnyHole>(__safeDI_holeFill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_HoleFill_AnyHole.holeBuilder_Values()))
		        return PanelTwin(holeBuilder: holeBuilder)
		    }
		}

		extension PanelTwin {
		    public enum __safeDI_PanelTwin_mock_EF93364769284E49 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

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
		        holeFill_AnyHoleSendableBuilder: @escaping @Sendable () -> AnyHole,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_screenBuilder__overrides = safeDIOverrides.screenBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            _ = Panel.__safeDI_Panel_mock_E9531DCA567FCD91.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panel() -> Panel {
		                let holeFill_AnyHoleBuilder: () -> AnyHole = holeFill_AnyHoleSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panel { safeDIBuilder(holeFill_AnyHoleBuilder) } else { Panel.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder)) }
		            }
		            let panel: Panel = __safeDI_panel()
		            return if let safeDIBuilder = __safeDI_screenBuilder__overrides.safeDIBuilder { safeDIBuilder(panel) } else { Screen(panel: panel) }
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Screen {
		    /// Configuration for how this type is constructed within a mock tree.
		    nonisolated struct SafeDIMockConfiguration: Sendable {
		        init(
		            panel: (@Sendable (@escaping () -> AnyHole) -> Panel)? = nil,
		            _ safeDIBuilder: (@Sendable (Panel) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var panel: (@Sendable (@escaping () -> AnyHole) -> Panel)? { __safeDI_storage.panel }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: (@Sendable (Panel) -> Screen)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                panel: (@Sendable (@escaping () -> AnyHole) -> Panel)?,
		                safeDIBuilder: (@Sendable (Panel) -> Screen)?
		            ) {
		                self.panel = panel
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let panel: (@Sendable (@escaping () -> AnyHole) -> Panel)?
		            let safeDIBuilder: (@Sendable (Panel) -> Screen)?
		        }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTheSharedBuilderSendable_whenTwoPublicMockCallsInASendableFunctionPassUpErasedInstantiatorPlacesInAReleaseBuild() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.erasedHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel", "@Instantiated let panelTwin: PanelTwin"], isReleaseConfiguration: true),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
		        nonisolated public struct holeBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(holeBuilder: { _ in { _ in __safeDI_builder() } })
		            }
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleBuilder: @escaping () -> AnyHole
		    ) -> Panel {
		        Panel.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleBuilder __safeDI_holeFill_AnyHoleBuilder: Panel.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> Panel {
		        let holeBuilder = ErasedInstantiator<(), AnyHole>(__safeDI_holeFill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_HoleFill_AnyHole.holeBuilder_Values()))
		        return Panel(holeBuilder: holeBuilder)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_E9531DCA567FCD91 {}
		}
		#endif

		#if DEBUG
		extension PanelTwin {
		    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
		        nonisolated public struct holeBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(holeBuilder: { _ in { _ in __safeDI_builder() } })
		            }
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleBuilder: @escaping () -> AnyHole
		    ) -> PanelTwin {
		        PanelTwin.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleBuilder __safeDI_holeFill_AnyHoleBuilder: PanelTwin.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> PanelTwin {
		        let holeBuilder = ErasedInstantiator<(), AnyHole>(__safeDI_holeFill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_HoleFill_AnyHole.holeBuilder_Values()))
		        return PanelTwin(holeBuilder: holeBuilder)
		    }
		}

		extension PanelTwin {
		    public enum __safeDI_PanelTwin_mock_EF93364769284E49 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

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
		        holeFill_AnyHoleSendableBuilder: @escaping @Sendable () -> AnyHole,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_screenBuilder__overrides = safeDIOverrides.screenBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            _ = Panel.__safeDI_Panel_mock_E9531DCA567FCD91.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panel() -> Panel {
		                let holeFill_AnyHoleBuilder: () -> AnyHole = holeFill_AnyHoleSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panel { safeDIBuilder(holeFill_AnyHoleBuilder) } else { Panel.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder)) }
		            }
		            let panel: Panel = __safeDI_panel()
		            _ = PanelTwin.__safeDI_PanelTwin_mock_EF93364769284E49.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelTwin() -> PanelTwin {
		                let holeFill_AnyHoleBuilder: () -> AnyHole = holeFill_AnyHoleSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panelTwin { safeDIBuilder(holeFill_AnyHoleBuilder) } else { PanelTwin.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder)) }
		            }
		            let panelTwin: PanelTwin = __safeDI_panelTwin()
		            return if let safeDIBuilder = __safeDI_screenBuilder__overrides.safeDIBuilder { safeDIBuilder(panel, panelTwin) } else { Screen(panel: panel, panelTwin: panelTwin) }
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Screen {
		    /// Configuration for how this type is constructed within a mock tree.
		    nonisolated struct SafeDIMockConfiguration: Sendable {
		        init(
		            panel: (@Sendable (@escaping () -> AnyHole) -> Panel)? = nil,
		            panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)? = nil,
		            _ safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel,
		                panelTwin: panelTwin,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var panel: (@Sendable (@escaping () -> AnyHole) -> Panel)? { __safeDI_storage.panel }
		        var panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)? { __safeDI_storage.panelTwin }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                panel: (@Sendable (@escaping () -> AnyHole) -> Panel)?,
		                panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)?,
		                safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		            ) {
		                self.panel = panel
		                self.panelTwin = panelTwin
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let panel: (@Sendable (@escaping () -> AnyHole) -> Panel)?
		            let panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)?
		            let safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		        }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compiles_whenPublicMockCallsInASendableFunctionOfAPublicCallerHaveErasedInstantiatorPlaces() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.erasedHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel", "@Instantiated let panelTwin: PanelTwin"], rootMock: .public),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
		        nonisolated public struct holeBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(holeBuilder: { _ in { _ in __safeDI_builder() } })
		            }
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleBuilder: @escaping () -> AnyHole
		    ) -> Panel {
		        Panel.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleBuilder __safeDI_holeFill_AnyHoleBuilder: Panel.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> Panel {
		        let holeBuilder = ErasedInstantiator<(), AnyHole>(__safeDI_holeFill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_HoleFill_AnyHole.holeBuilder_Values()))
		        return Panel(holeBuilder: holeBuilder)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_E9531DCA567FCD91 {}
		}
		#endif

		#if DEBUG
		extension PanelTwin {
		    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
		        nonisolated public struct holeBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(holeBuilder: { _ in { _ in __safeDI_builder() } })
		            }
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleBuilder: @escaping () -> AnyHole
		    ) -> PanelTwin {
		        PanelTwin.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleBuilder __safeDI_holeFill_AnyHoleBuilder: PanelTwin.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> PanelTwin {
		        let holeBuilder = ErasedInstantiator<(), AnyHole>(__safeDI_holeFill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_HoleFill_AnyHole.holeBuilder_Values()))
		        return PanelTwin(holeBuilder: holeBuilder)
		    }
		}

		extension PanelTwin {
		    public enum __safeDI_PanelTwin_mock_EF93364769284E49 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
		        nonisolated public enum Screen_Scope {
		            nonisolated public struct panel_Values: Sendable {}

		            nonisolated public struct panelTwin_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let panel: (panel_Values) -> Panel.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<__safeDI_Built>
		                public let panelTwin: (panelTwin_Values) -> PanelTwin.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<__safeDI_Built>

		                public init(panel: @escaping (panel_Values) -> Panel.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<__safeDI_Built>, panelTwin: @escaping (panelTwin_Values) -> PanelTwin.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<__safeDI_Built>) {
		                    self.panel = panel
		                    self.panelTwin = panelTwin
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(panel: { _ in .init(__safeDI_noScope: __safeDI_builder) }, panelTwin: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }
		    }

		    nonisolated public enum SafeDISendableMockScope_HoleFill_AnyHole {
		        nonisolated public struct screenBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let screenBuilder: @Sendable (screenBuilder_Values) -> SafeDIMockScope_HoleFill_AnyHole.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(screenBuilder: @escaping @Sendable (screenBuilder_Values) -> SafeDIMockScope_HoleFill_AnyHole.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.screenBuilder = screenBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                self.init(screenBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            screenBuilder: __safeDI_App_Screen_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder
		            )
		        }

		        public var screenBuilder: __safeDI_App_Screen_MockConfiguration { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screenBuilder: __safeDI_App_Screen_MockConfiguration
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: __safeDI_App_Screen_MockConfiguration
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleSendableBuilder: @escaping @Sendable () -> AnyHole,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        Root.__safeDI_mock(holeFill_AnyHoleSendableBuilder: .init(__safeDI_noScope: holeFill_AnyHoleSendableBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleSendableBuilder __safeDI_holeFill_AnyHoleSendableBuilder: Root.SafeDISendableMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_screenBuilder__safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            let __safeDI_holeFill_AnyHoleSendableBuilder_screenBuilder = __safeDI_holeFill_AnyHoleSendableBuilder.screenBuilder(SafeDISendableMockScope_HoleFill_AnyHole.screenBuilder_Values())
		            _ = Panel.__safeDI_Panel_mock_E9531DCA567FCD91.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let panel = Panel.__safeDI_mock(holeFill_AnyHoleBuilder: __safeDI_holeFill_AnyHoleSendableBuilder_screenBuilder.panel(SafeDIMockScope_HoleFill_AnyHole.Screen_Scope.panel_Values()))
		            _ = PanelTwin.__safeDI_PanelTwin_mock_EF93364769284E49.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let panelTwin = PanelTwin.__safeDI_mock(holeFill_AnyHoleBuilder: __safeDI_holeFill_AnyHoleSendableBuilder_screenBuilder.panelTwin(SafeDIMockScope_HoleFill_AnyHole.Screen_Scope.panelTwin_Values()))
		            return Screen.__safeDI_init(panel: panel, panelTwin: panelTwin, safeDIBuilder: __safeDI_screenBuilder__safeDIBuilder)
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder)
		    }
		}

		extension Root {
		    public enum __safeDI_Root_mock_45F27868F9BEC3F4 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Screen` is constructed within the public mock trees of module `App`.
		nonisolated public struct __safeDI_App_Screen_MockConfiguration {
		    public init(
		        _ safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    /// Overrides how `Screen` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		    }
		}

		extension Screen {
		    static func __safeDI_init(panel: Panel, panelTwin: PanelTwin, safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?) -> Screen {
		        if let safeDIBuilder { safeDIBuilder(panel, panelTwin) } else { Screen(panel: panel, panelTwin: panelTwin) }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTheSharedBuilderSendable_whenAnotherModulesListedMockCallsPublicMocksInASendableFunctionThatPassUpErasedInstantiatorPlaces() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.erasedHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel", "@Instantiated let panelTwin: PanelTwin"], rootMock: .listedInAnotherModule),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
		        nonisolated public struct holeBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(holeBuilder: { _ in { _ in __safeDI_builder() } })
		            }
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleBuilder: @escaping () -> AnyHole
		    ) -> Panel {
		        Panel.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleBuilder __safeDI_holeFill_AnyHoleBuilder: Panel.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> Panel {
		        let holeBuilder = ErasedInstantiator<(), AnyHole>(__safeDI_holeFill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_HoleFill_AnyHole.holeBuilder_Values()))
		        return Panel(holeBuilder: holeBuilder)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_E9531DCA567FCD91 {}
		}
		#endif

		#if DEBUG
		extension PanelTwin {
		    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
		        nonisolated public struct holeBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(holeBuilder: { _ in { _ in __safeDI_builder() } })
		            }
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleBuilder: @escaping () -> AnyHole
		    ) -> PanelTwin {
		        PanelTwin.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleBuilder __safeDI_holeFill_AnyHoleBuilder: PanelTwin.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> PanelTwin {
		        let holeBuilder = ErasedInstantiator<(), AnyHole>(__safeDI_holeFill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_HoleFill_AnyHole.holeBuilder_Values()))
		        return PanelTwin(holeBuilder: holeBuilder)
		    }
		}

		extension PanelTwin {
		    public enum __safeDI_PanelTwin_mock_EF93364769284E49 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["AppMocks"]?.generatedFiles == ["AppMocks.swift": generatedFileHeader + """
		#if canImport(App)
		import App
		#endif
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

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
		        holeFill_AnyHoleSendableBuilder: @escaping @Sendable () -> AnyHole,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_screenBuilder__overrides = safeDIOverrides.screenBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            _ = Panel.__safeDI_Panel_mock_E9531DCA567FCD91.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panel() -> Panel {
		                let holeFill_AnyHoleBuilder: () -> AnyHole = holeFill_AnyHoleSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panel { safeDIBuilder(holeFill_AnyHoleBuilder) } else { Panel.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder)) }
		            }
		            let panel: Panel = __safeDI_panel()
		            _ = PanelTwin.__safeDI_PanelTwin_mock_EF93364769284E49.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelTwin() -> PanelTwin {
		                let holeFill_AnyHoleBuilder: () -> AnyHole = holeFill_AnyHoleSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panelTwin { safeDIBuilder(holeFill_AnyHoleBuilder) } else { PanelTwin.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder)) }
		            }
		            let panelTwin: PanelTwin = __safeDI_panelTwin()
		            return if let safeDIBuilder = __safeDI_screenBuilder__overrides.safeDIBuilder { safeDIBuilder(panel, panelTwin) } else { Screen(panel: panel, panelTwin: panelTwin) }
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Screen {
		    /// Configuration for how this type is constructed within a mock tree.
		    nonisolated struct SafeDIMockConfiguration: Sendable {
		        init(
		            panel: (@Sendable (@escaping () -> AnyHole) -> Panel)? = nil,
		            panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)? = nil,
		            _ safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel,
		                panelTwin: panelTwin,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var panel: (@Sendable (@escaping () -> AnyHole) -> Panel)? { __safeDI_storage.panel }
		        var panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)? { __safeDI_storage.panelTwin }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                panel: (@Sendable (@escaping () -> AnyHole) -> Panel)?,
		                panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)?,
		                safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		            ) {
		                self.panel = panel
		                self.panelTwin = panelTwin
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let panel: (@Sendable (@escaping () -> AnyHole) -> Panel)?
		            let panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)?
		            let safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		        }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTheSharedBuilderOfTheSendableWrapper_whenTwoPublicMockCallsInASendableFunctionPassUpSendableErasedInstantiatorPlaces() async throws {
		// The place's wrapper is its own `Sendable` twin, so the builder keeps the place's spelling.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.sendableErasedHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel", "@Instantiated let panelTwin: PanelTwin"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDISendableMockScope_HoleFill_AnyHole {
		        nonisolated public struct holeBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let holeBuilder: @Sendable (holeBuilder_Values) -> SendableErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping @Sendable (holeBuilder_Values) -> SendableErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                self.init(holeBuilder: { _ in { _ in __safeDI_builder() } })
		            }
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleSendableBuilder: @escaping @Sendable () -> AnyHole
		    ) -> Panel {
		        Panel.__safeDI_mock(holeFill_AnyHoleSendableBuilder: .init(__safeDI_noScope: holeFill_AnyHoleSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleSendableBuilder __safeDI_holeFill_AnyHoleSendableBuilder: Panel.SafeDISendableMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> Panel {
		        let holeBuilder = SendableErasedInstantiator<(), AnyHole>(__safeDI_holeFill_AnyHoleSendableBuilder.holeBuilder(SafeDISendableMockScope_HoleFill_AnyHole.holeBuilder_Values()))
		        return Panel(holeBuilder: holeBuilder)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_C648B5018F5B0366 {}
		}
		#endif

		#if DEBUG
		extension PanelTwin {
		    nonisolated public enum SafeDISendableMockScope_HoleFill_AnyHole {
		        nonisolated public struct holeBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let holeBuilder: @Sendable (holeBuilder_Values) -> SendableErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping @Sendable (holeBuilder_Values) -> SendableErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                self.init(holeBuilder: { _ in { _ in __safeDI_builder() } })
		            }
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleSendableBuilder: @escaping @Sendable () -> AnyHole
		    ) -> PanelTwin {
		        PanelTwin.__safeDI_mock(holeFill_AnyHoleSendableBuilder: .init(__safeDI_noScope: holeFill_AnyHoleSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleSendableBuilder __safeDI_holeFill_AnyHoleSendableBuilder: PanelTwin.SafeDISendableMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> PanelTwin {
		        let holeBuilder = SendableErasedInstantiator<(), AnyHole>(__safeDI_holeFill_AnyHoleSendableBuilder.holeBuilder(SafeDISendableMockScope_HoleFill_AnyHole.holeBuilder_Values()))
		        return PanelTwin(holeBuilder: holeBuilder)
		    }
		}

		extension PanelTwin {
		    public enum __safeDI_PanelTwin_mock_DC6B7BFF7D8BDEBA {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

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
		        holeFill_AnyHoleSendableBuilder: @escaping @Sendable () -> AnyHole,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_holeFill_AnyHoleSendableBuilder = holeFill_AnyHoleSendableBuilder
		        let __safeDI_screenBuilder__overrides = safeDIOverrides.screenBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            _ = Panel.__safeDI_Panel_mock_C648B5018F5B0366.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panel() -> Panel {
		                let holeFill_AnyHoleSendableBuilder: @Sendable () -> AnyHole = __safeDI_holeFill_AnyHoleSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panel { safeDIBuilder(holeFill_AnyHoleSendableBuilder) } else { Panel.__safeDI_mock(holeFill_AnyHoleSendableBuilder: .init(__safeDI_noScope: holeFill_AnyHoleSendableBuilder)) }
		            }
		            let panel: Panel = __safeDI_panel()
		            _ = PanelTwin.__safeDI_PanelTwin_mock_DC6B7BFF7D8BDEBA.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelTwin() -> PanelTwin {
		                let holeFill_AnyHoleSendableBuilder: @Sendable () -> AnyHole = __safeDI_holeFill_AnyHoleSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panelTwin { safeDIBuilder(holeFill_AnyHoleSendableBuilder) } else { PanelTwin.__safeDI_mock(holeFill_AnyHoleSendableBuilder: .init(__safeDI_noScope: holeFill_AnyHoleSendableBuilder)) }
		            }
		            let panelTwin: PanelTwin = __safeDI_panelTwin()
		            return if let safeDIBuilder = __safeDI_screenBuilder__overrides.safeDIBuilder { safeDIBuilder(panel, panelTwin) } else { Screen(panel: panel, panelTwin: panelTwin) }
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Screen {
		    /// Configuration for how this type is constructed within a mock tree.
		    nonisolated struct SafeDIMockConfiguration: Sendable {
		        init(
		            panel: (@Sendable (@escaping @Sendable () -> AnyHole) -> Panel)? = nil,
		            panelTwin: (@Sendable (@escaping @Sendable () -> AnyHole) -> PanelTwin)? = nil,
		            _ safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel,
		                panelTwin: panelTwin,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var panel: (@Sendable (@escaping @Sendable () -> AnyHole) -> Panel)? { __safeDI_storage.panel }
		        var panelTwin: (@Sendable (@escaping @Sendable () -> AnyHole) -> PanelTwin)? { __safeDI_storage.panelTwin }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                panel: (@Sendable (@escaping @Sendable () -> AnyHole) -> Panel)?,
		                panelTwin: (@Sendable (@escaping @Sendable () -> AnyHole) -> PanelTwin)?,
		                safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		            ) {
		                self.panel = panel
		                self.panelTwin = panelTwin
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let panel: (@Sendable (@escaping @Sendable () -> AnyHole) -> Panel)?
		            let panelTwin: (@Sendable (@escaping @Sendable () -> AnyHole) -> PanelTwin)?
		            let safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		        }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTheSharedBuilderOfTheSendableWrapper_whenTwoPublicMockCallsInASendableFunctionPassUpSendableInstantiatorPlaces() async throws {
		// The place's wrapper is its own `Sendable` twin, so the builder keeps the place's spelling.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.sendableInstantiatorHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel", "@Instantiated let panelTwin: PanelTwin"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDISendableMockScope_Hole {
		        nonisolated public struct holeBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let holeBuilder: @Sendable (holeBuilder_Values) -> SendableErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping @Sendable (holeBuilder_Values) -> SendableErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.init(holeBuilder: { _ in __safeDI_builder })
		            }
		        }
		    }

		    public static func mock(
		        holeSendableBuilder: @escaping SendableInstantiator<Hole>.Builder
		    ) -> Panel {
		        Panel.__safeDI_mock(holeSendableBuilder: .init(__safeDI_noScope: holeSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeSendableBuilder __safeDI_holeSendableBuilder: Panel.SafeDISendableMockScope_Hole.__safeDI_Builder<Hole>
		    ) -> Panel {
		        let holeBuilder = SendableInstantiator<Hole>(__safeDI_holeSendableBuilder.holeBuilder(SafeDISendableMockScope_Hole.holeBuilder_Values()))
		        return Panel(holeBuilder: holeBuilder)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_72E86CA99351B8EC {}
		}
		#endif

		#if DEBUG
		extension PanelTwin {
		    nonisolated public enum SafeDISendableMockScope_Hole {
		        nonisolated public struct holeBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let holeBuilder: @Sendable (holeBuilder_Values) -> SendableErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping @Sendable (holeBuilder_Values) -> SendableErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.init(holeBuilder: { _ in __safeDI_builder })
		            }
		        }
		    }

		    public static func mock(
		        holeSendableBuilder: @escaping SendableInstantiator<Hole>.Builder
		    ) -> PanelTwin {
		        PanelTwin.__safeDI_mock(holeSendableBuilder: .init(__safeDI_noScope: holeSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeSendableBuilder __safeDI_holeSendableBuilder: PanelTwin.SafeDISendableMockScope_Hole.__safeDI_Builder<Hole>
		    ) -> PanelTwin {
		        let holeBuilder = SendableInstantiator<Hole>(__safeDI_holeSendableBuilder.holeBuilder(SafeDISendableMockScope_Hole.holeBuilder_Values()))
		        return PanelTwin(holeBuilder: holeBuilder)
		    }
		}

		extension PanelTwin {
		    public enum __safeDI_PanelTwin_mock_954835BF964120E0 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

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
		        holeSendableBuilder: @escaping SendableInstantiator<Hole>.Builder,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_holeSendableBuilder = holeSendableBuilder
		        let __safeDI_screenBuilder__overrides = safeDIOverrides.screenBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            _ = Panel.__safeDI_Panel_mock_72E86CA99351B8EC.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panel() -> Panel {
		                let holeSendableBuilder: SendableInstantiator<Hole>.Builder = __safeDI_holeSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panel { safeDIBuilder(holeSendableBuilder) } else { Panel.__safeDI_mock(holeSendableBuilder: .init(__safeDI_noScope: holeSendableBuilder)) }
		            }
		            let panel: Panel = __safeDI_panel()
		            _ = PanelTwin.__safeDI_PanelTwin_mock_954835BF964120E0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelTwin() -> PanelTwin {
		                let holeSendableBuilder: SendableInstantiator<Hole>.Builder = __safeDI_holeSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panelTwin { safeDIBuilder(holeSendableBuilder) } else { PanelTwin.__safeDI_mock(holeSendableBuilder: .init(__safeDI_noScope: holeSendableBuilder)) }
		            }
		            let panelTwin: PanelTwin = __safeDI_panelTwin()
		            return if let safeDIBuilder = __safeDI_screenBuilder__overrides.safeDIBuilder { safeDIBuilder(panel, panelTwin) } else { Screen(panel: panel, panelTwin: panelTwin) }
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Screen {
		    /// Configuration for how this type is constructed within a mock tree.
		    nonisolated struct SafeDIMockConfiguration: Sendable {
		        init(
		            panel: (@Sendable (@escaping SendableInstantiator<Hole>.Builder) -> Panel)? = nil,
		            panelTwin: (@Sendable (@escaping SendableInstantiator<Hole>.Builder) -> PanelTwin)? = nil,
		            _ safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel,
		                panelTwin: panelTwin,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var panel: (@Sendable (@escaping SendableInstantiator<Hole>.Builder) -> Panel)? { __safeDI_storage.panel }
		        var panelTwin: (@Sendable (@escaping SendableInstantiator<Hole>.Builder) -> PanelTwin)? { __safeDI_storage.panelTwin }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                panel: (@Sendable (@escaping SendableInstantiator<Hole>.Builder) -> Panel)?,
		                panelTwin: (@Sendable (@escaping SendableInstantiator<Hole>.Builder) -> PanelTwin)?,
		                safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		            ) {
		                self.panel = panel
		                self.panelTwin = panelTwin
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let panel: (@Sendable (@escaping SendableInstantiator<Hole>.Builder) -> Panel)?
		            let panelTwin: (@Sendable (@escaping SendableInstantiator<Hole>.Builder) -> PanelTwin)?
		            let safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		        }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTheSharedBuilderSendable_whenTwoPublicMockCallsInASendableFunctionPassUpErasedInstantiatorPlacesThatForwardAValue() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.forwardingErasedHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel", "@Instantiated let panelTwin: PanelTwin"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
		        nonisolated public struct holeBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<HoleArguments, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<HoleArguments, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<HoleArguments, __safeDI_Built>.Builder) {
		                self.init(holeBuilder: { _ in __safeDI_builder })
		            }
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleBuilder: @escaping ErasedInstantiator<HoleArguments, AnyHole>.Builder
		    ) -> Panel {
		        Panel.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleBuilder __safeDI_holeFill_AnyHoleBuilder: Panel.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> Panel {
		        let holeBuilder = ErasedInstantiator<HoleArguments, AnyHole>(__safeDI_holeFill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_HoleFill_AnyHole.holeBuilder_Values()))
		        return Panel(holeBuilder: holeBuilder)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_16C4F78E528D62FF {}
		}
		#endif

		#if DEBUG
		extension PanelTwin {
		    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
		        nonisolated public struct holeBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<HoleArguments, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<HoleArguments, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<HoleArguments, __safeDI_Built>.Builder) {
		                self.init(holeBuilder: { _ in __safeDI_builder })
		            }
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleBuilder: @escaping ErasedInstantiator<HoleArguments, AnyHole>.Builder
		    ) -> PanelTwin {
		        PanelTwin.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleBuilder __safeDI_holeFill_AnyHoleBuilder: PanelTwin.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> PanelTwin {
		        let holeBuilder = ErasedInstantiator<HoleArguments, AnyHole>(__safeDI_holeFill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_HoleFill_AnyHole.holeBuilder_Values()))
		        return PanelTwin(holeBuilder: holeBuilder)
		    }
		}

		extension PanelTwin {
		    public enum __safeDI_PanelTwin_mock_72CCDC4E577CFDB7 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

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
		        holeFill_AnyHoleSendableBuilder: @escaping SendableErasedInstantiator<HoleArguments, AnyHole>.Builder,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_screenBuilder__overrides = safeDIOverrides.screenBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            _ = Panel.__safeDI_Panel_mock_16C4F78E528D62FF.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panel() -> Panel {
		                let holeFill_AnyHoleBuilder: ErasedInstantiator<HoleArguments, AnyHole>.Builder = holeFill_AnyHoleSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panel { safeDIBuilder(holeFill_AnyHoleBuilder) } else { Panel.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder)) }
		            }
		            let panel: Panel = __safeDI_panel()
		            _ = PanelTwin.__safeDI_PanelTwin_mock_72CCDC4E577CFDB7.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panelTwin() -> PanelTwin {
		                let holeFill_AnyHoleBuilder: ErasedInstantiator<HoleArguments, AnyHole>.Builder = holeFill_AnyHoleSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panelTwin { safeDIBuilder(holeFill_AnyHoleBuilder) } else { PanelTwin.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder)) }
		            }
		            let panelTwin: PanelTwin = __safeDI_panelTwin()
		            return if let safeDIBuilder = __safeDI_screenBuilder__overrides.safeDIBuilder { safeDIBuilder(panel, panelTwin) } else { Screen(panel: panel, panelTwin: panelTwin) }
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Screen {
		    /// Configuration for how this type is constructed within a mock tree.
		    nonisolated struct SafeDIMockConfiguration: Sendable {
		        init(
		            panel: (@Sendable (@escaping ErasedInstantiator<HoleArguments, AnyHole>.Builder) -> Panel)? = nil,
		            panelTwin: (@Sendable (@escaping ErasedInstantiator<HoleArguments, AnyHole>.Builder) -> PanelTwin)? = nil,
		            _ safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel,
		                panelTwin: panelTwin,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var panel: (@Sendable (@escaping ErasedInstantiator<HoleArguments, AnyHole>.Builder) -> Panel)? { __safeDI_storage.panel }
		        var panelTwin: (@Sendable (@escaping ErasedInstantiator<HoleArguments, AnyHole>.Builder) -> PanelTwin)? { __safeDI_storage.panelTwin }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                panel: (@Sendable (@escaping ErasedInstantiator<HoleArguments, AnyHole>.Builder) -> Panel)?,
		                panelTwin: (@Sendable (@escaping ErasedInstantiator<HoleArguments, AnyHole>.Builder) -> PanelTwin)?,
		                safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		            ) {
		                self.panel = panel
		                self.panelTwin = panelTwin
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let panel: (@Sendable (@escaping ErasedInstantiator<HoleArguments, AnyHole>.Builder) -> Panel)?
		            let panelTwin: (@Sendable (@escaping ErasedInstantiator<HoleArguments, AnyHole>.Builder) -> PanelTwin)?
		            let safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
		        }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTheSharedBuilderSendable_whenTwoPublicMockCallsInASendableFunctionPassUpErasedInstantiatorPlacesUnderTheSwiftPackagePlugin() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.erasedHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel", "@Instantiated let panelTwin: PanelTwin"]),
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == [
			"Panel+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Panel {
			    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
			        nonisolated public struct holeBuilder_Values {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

			            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
			                self.holeBuilder = holeBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(holeBuilder: { _ in { _ in __safeDI_builder() } })
			            }
			        }
			    }

			    public static func mock(
			        holeFill_AnyHoleBuilder: @escaping () -> AnyHole
			    ) -> Panel {
			        Panel.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        holeFill_AnyHoleBuilder __safeDI_holeFill_AnyHoleBuilder: Panel.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
			    ) -> Panel {
			        let holeBuilder = ErasedInstantiator<(), AnyHole>(__safeDI_holeFill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_HoleFill_AnyHole.holeBuilder_Values()))
			        return Panel(holeBuilder: holeBuilder)
			    }
			}

			extension Panel {
			    public enum __safeDI_Panel_mock_E9531DCA567FCD91 {}
			}
			#endif
			""",
			"PanelTwin+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension PanelTwin {
			    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
			        nonisolated public struct holeBuilder_Values {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

			            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
			                self.holeBuilder = holeBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(holeBuilder: { _ in { _ in __safeDI_builder() } })
			            }
			        }
			    }

			    public static func mock(
			        holeFill_AnyHoleBuilder: @escaping () -> AnyHole
			    ) -> PanelTwin {
			        PanelTwin.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        holeFill_AnyHoleBuilder __safeDI_holeFill_AnyHoleBuilder: PanelTwin.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>
			    ) -> PanelTwin {
			        let holeBuilder = ErasedInstantiator<(), AnyHole>(__safeDI_holeFill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_HoleFill_AnyHole.holeBuilder_Values()))
			        return PanelTwin(holeBuilder: holeBuilder)
			    }
			}

			extension PanelTwin {
			    public enum __safeDI_PanelTwin_mock_EF93364769284E49 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif


			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

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
			        holeFill_AnyHoleSendableBuilder: @escaping @Sendable () -> AnyHole,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_screenBuilder__overrides = safeDIOverrides.screenBuilder
			        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
			            _ = Panel.__safeDI_Panel_mock_E9531DCA567FCD91.self // If this line does not compile, add the SafeDI plugin to the target that declares Panel.
			            func __safeDI_panel() -> Panel {
			                let holeFill_AnyHoleBuilder: () -> AnyHole = holeFill_AnyHoleSendableBuilder
			                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panel { safeDIBuilder(holeFill_AnyHoleBuilder) } else { Panel.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder)) }
			            }
			            let panel: Panel = __safeDI_panel()
			            _ = PanelTwin.__safeDI_PanelTwin_mock_EF93364769284E49.self // If this line does not compile, add the SafeDI plugin to the target that declares PanelTwin.
			            func __safeDI_panelTwin() -> PanelTwin {
			                let holeFill_AnyHoleBuilder: () -> AnyHole = holeFill_AnyHoleSendableBuilder
			                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panelTwin { safeDIBuilder(holeFill_AnyHoleBuilder) } else { PanelTwin.__safeDI_mock(holeFill_AnyHoleBuilder: .init(__safeDI_noScope: holeFill_AnyHoleBuilder)) }
			            }
			            let panelTwin: PanelTwin = __safeDI_panelTwin()
			            return if let safeDIBuilder = __safeDI_screenBuilder__overrides.safeDIBuilder { safeDIBuilder(panel, panelTwin) } else { Screen(panel: panel, panelTwin: panelTwin) }
			        }
			        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
			        return Root(screenBuilder: screenBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            panel: (@Sendable (@escaping () -> AnyHole) -> Panel)? = nil,
			            panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)? = nil,
			            _ safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel,
			                panelTwin: panelTwin,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var panel: (@Sendable (@escaping () -> AnyHole) -> Panel)? { __safeDI_storage.panel }
			        var panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)? { __safeDI_storage.panelTwin }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                panel: (@Sendable (@escaping () -> AnyHole) -> Panel)?,
			                panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)?,
			                safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
			            ) {
			                self.panel = panel
			                self.panelTwin = panelTwin
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let panel: (@Sendable (@escaping () -> AnyHole) -> Panel)?
			            let panelTwin: (@Sendable (@escaping () -> AnyHole) -> PanelTwin)?
			            let safeDIBuilder: (@Sendable (Panel, PanelTwin) -> Screen)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Tests – a received value of a passed-up builder’s label and type

	/// A public mock spells its parameters from its plan, so the value `Root` receives keeps the type it declares, though a
	/// `@Sendable` builder function calls `Panel`’s mock, whose builder has its label and type, and hands it the builder of
	/// the hole type from the public mock’s own enums.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTheReceivedValueAsDeclared_whenAPublicCallerReceivesTheLabelAndTypeOfAnInstantiatorBuilderItsSendableFunctionPassesUp() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.instantiatorHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel"], rootDeclarations: ["@Received let holeBuilder: Instantiator<Hole>.Builder"], rootMock: .public),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    nonisolated public enum SafeDIMockScope_Hole {
		        nonisolated public enum Screen_Scope {
		            nonisolated public struct panel_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let panel: (panel_Values) -> Panel.SafeDIMockScope_Hole.__safeDI_Builder<__safeDI_Built>

		                public init(panel: @escaping (panel_Values) -> Panel.SafeDIMockScope_Hole.__safeDI_Builder<__safeDI_Built>) {
		                    self.panel = panel
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder) {
		                    self.init(panel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }
		    }

		    nonisolated public enum SafeDISendableMockScope_Hole {
		        nonisolated public struct screenBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let screenBuilder: @Sendable (screenBuilder_Values) -> SafeDIMockScope_Hole.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(screenBuilder: @escaping @Sendable (screenBuilder_Values) -> SafeDIMockScope_Hole.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.screenBuilder = screenBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.init(screenBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            screenBuilder: __safeDI_App_Screen_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder
		            )
		        }

		        public var screenBuilder: __safeDI_App_Screen_MockConfiguration { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screenBuilder: __safeDI_App_Screen_MockConfiguration
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: __safeDI_App_Screen_MockConfiguration
		        }
		    }

		    public static func mock(
		        holeBuilder: @escaping Instantiator<Hole>.Builder,
		        holeSendableBuilder: @escaping SendableInstantiator<Hole>.Builder,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        Root.__safeDI_mock(holeBuilder: holeBuilder, holeSendableBuilder: .init(__safeDI_noScope: holeSendableBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeBuilder: @escaping Instantiator<Hole>.Builder,
		        holeSendableBuilder __safeDI_holeSendableBuilder: Root.SafeDISendableMockScope_Hole.__safeDI_Builder<Hole>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_screenBuilder__safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            let __safeDI_holeSendableBuilder_screenBuilder = __safeDI_holeSendableBuilder.screenBuilder(SafeDISendableMockScope_Hole.screenBuilder_Values())
		            _ = Panel.__safeDI_Panel_mock_F0F10F2194E82F9F.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let panel = Panel.__safeDI_mock(holeBuilder: __safeDI_holeSendableBuilder_screenBuilder.panel(SafeDIMockScope_Hole.Screen_Scope.panel_Values()))
		            return Screen.__safeDI_init(panel: panel, safeDIBuilder: __safeDI_screenBuilder__safeDIBuilder)
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder, holeBuilder: holeBuilder)
		    }
		}

		extension Root {
		    public enum __safeDI_Root_mock_A5AF0459A085386B {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Screen` is constructed within the public mock trees of module `App`.
		nonisolated public struct __safeDI_App_Screen_MockConfiguration {
		    public init(
		        _ safeDIBuilder: (@Sendable (Panel) -> Screen)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    /// Overrides how `Screen` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: (@Sendable (Panel) -> Screen)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            safeDIBuilder: (@Sendable (Panel) -> Screen)?
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let safeDIBuilder: (@Sendable (Panel) -> Screen)?
		    }
		}

		extension Screen {
		    static func __safeDI_init(panel: Panel, safeDIBuilder: (@Sendable (Panel) -> Screen)?) -> Screen {
		        if let safeDIBuilder { safeDIBuilder(panel) } else { Screen(panel: panel) }
		    }
		}
		#endif

		"""])
	}

	/// The same, where the place is an erased instantiator that forwards nothing, whose builder is a function type.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTheReceivedValueAsDeclared_whenAPublicCallerReceivesTheLabelAndTypeOfAnErasedInstantiatorBuilderItsSendableFunctionPassesUp() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.erasedHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel"], rootDeclarations: ["@Received let holeFill_AnyHoleBuilder: () -> AnyHole"], rootMock: .public),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    nonisolated public enum SafeDIMockScope_HoleFill_AnyHole {
		        nonisolated public enum Screen_Scope {
		            nonisolated public struct panel_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let panel: (panel_Values) -> Panel.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<__safeDI_Built>

		                public init(panel: @escaping (panel_Values) -> Panel.SafeDIMockScope_HoleFill_AnyHole.__safeDI_Builder<__safeDI_Built>) {
		                    self.panel = panel
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(panel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }
		    }

		    nonisolated public enum SafeDISendableMockScope_HoleFill_AnyHole {
		        nonisolated public struct screenBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let screenBuilder: @Sendable (screenBuilder_Values) -> SafeDIMockScope_HoleFill_AnyHole.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(screenBuilder: @escaping @Sendable (screenBuilder_Values) -> SafeDIMockScope_HoleFill_AnyHole.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.screenBuilder = screenBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                self.init(screenBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            screenBuilder: __safeDI_App_Screen_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder
		            )
		        }

		        public var screenBuilder: __safeDI_App_Screen_MockConfiguration { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screenBuilder: __safeDI_App_Screen_MockConfiguration
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: __safeDI_App_Screen_MockConfiguration
		        }
		    }

		    public static func mock(
		        holeFill_AnyHoleBuilder: @escaping () -> AnyHole,
		        holeFill_AnyHoleSendableBuilder: @escaping @Sendable () -> AnyHole,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        Root.__safeDI_mock(holeFill_AnyHoleBuilder: holeFill_AnyHoleBuilder, holeFill_AnyHoleSendableBuilder: .init(__safeDI_noScope: holeFill_AnyHoleSendableBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeFill_AnyHoleBuilder: @escaping () -> AnyHole,
		        holeFill_AnyHoleSendableBuilder __safeDI_holeFill_AnyHoleSendableBuilder: Root.SafeDISendableMockScope_HoleFill_AnyHole.__safeDI_Builder<AnyHole>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_screenBuilder__safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            let __safeDI_holeFill_AnyHoleSendableBuilder_screenBuilder = __safeDI_holeFill_AnyHoleSendableBuilder.screenBuilder(SafeDISendableMockScope_HoleFill_AnyHole.screenBuilder_Values())
		            _ = Panel.__safeDI_Panel_mock_E9531DCA567FCD91.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let panel = Panel.__safeDI_mock(holeFill_AnyHoleBuilder: __safeDI_holeFill_AnyHoleSendableBuilder_screenBuilder.panel(SafeDIMockScope_HoleFill_AnyHole.Screen_Scope.panel_Values()))
		            return Screen.__safeDI_init(panel: panel, safeDIBuilder: __safeDI_screenBuilder__safeDIBuilder)
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder, holeFill_AnyHoleBuilder: holeFill_AnyHoleBuilder)
		    }
		}

		extension Root {
		    public enum __safeDI_Root_mock_BAE028C053013B23 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Screen` is constructed within the public mock trees of module `App`.
		nonisolated public struct __safeDI_App_Screen_MockConfiguration {
		    public init(
		        _ safeDIBuilder: (@Sendable (Panel) -> Screen)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    /// Overrides how `Screen` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: (@Sendable (Panel) -> Screen)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            safeDIBuilder: (@Sendable (Panel) -> Screen)?
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let safeDIBuilder: (@Sendable (Panel) -> Screen)?
		    }
		}

		extension Screen {
		    static func __safeDI_init(panel: Panel, safeDIBuilder: (@Sendable (Panel) -> Screen)?) -> Screen {
		        if let safeDIBuilder { safeDIBuilder(panel) } else { Screen(panel: panel) }
		    }
		}
		#endif

		"""])
	}

	/// The same, where the place is a `Sendable` wrapper, whose builder is `@Sendable` already.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTheReceivedValueAsDeclared_whenAPublicCallerReceivesTheLabelAndTypeOfASendableInstantiatorBuilderItsSendableFunctionPassesUp() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.sendableInstantiatorHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel"], rootDeclarations: ["@Received let holeBuilder: SendableInstantiator<Hole>.Builder"], rootMock: .public),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    nonisolated public enum SafeDISendableMockScope_Hole {
		        nonisolated public struct screenBuilder_Sendable_Values: Sendable {}

		        nonisolated public enum Screen_Scope {
		            nonisolated public struct panel_Sendable_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		                public let panel_Sendable: @Sendable (panel_Sendable_Values) -> Panel.SafeDISendableMockScope_Hole.__safeDI_Builder<__safeDI_Built>

		                public init(panel_Sendable: @escaping @Sendable (panel_Sendable_Values) -> Panel.SafeDISendableMockScope_Hole.__safeDI_Builder<__safeDI_Built>) {
		                    self.panel_Sendable = panel_Sendable
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder) {
		                    self.init(panel_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let screenBuilder_Sendable: @Sendable (screenBuilder_Sendable_Values) -> SafeDISendableMockScope_Hole.Screen_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(screenBuilder_Sendable: @escaping @Sendable (screenBuilder_Sendable_Values) -> SafeDISendableMockScope_Hole.Screen_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.screenBuilder_Sendable = screenBuilder_Sendable
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Hole.ForwardedProperties, __safeDI_Built>.Builder) {
		                self.init(screenBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            screenBuilder: __safeDI_App_Screen_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder
		            )
		        }

		        public var screenBuilder: __safeDI_App_Screen_MockConfiguration { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screenBuilder: __safeDI_App_Screen_MockConfiguration
		            ) {
		                self.screenBuilder = screenBuilder
		            }

		            let screenBuilder: __safeDI_App_Screen_MockConfiguration
		        }
		    }

		    public static func mock(
		        holeBuilder: @escaping SendableInstantiator<Hole>.Builder,
		        holeSendableBuilder: @escaping SendableInstantiator<Hole>.Builder,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        Root.__safeDI_mock(holeBuilder: holeBuilder, holeSendableBuilder: .init(__safeDI_noScope: holeSendableBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        holeBuilder: @escaping SendableInstantiator<Hole>.Builder,
		        holeSendableBuilder __safeDI_holeSendableBuilder: Root.SafeDISendableMockScope_Hole.__safeDI_Builder<Hole>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_screenBuilder__safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            let __safeDI_holeSendableBuilder_screenBuilder_Sendable = __safeDI_holeSendableBuilder.screenBuilder_Sendable(SafeDISendableMockScope_Hole.screenBuilder_Sendable_Values())
		            _ = Panel.__safeDI_Panel_mock_72E86CA99351B8EC.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let panel = Panel.__safeDI_mock(holeSendableBuilder: __safeDI_holeSendableBuilder_screenBuilder_Sendable.panel_Sendable(SafeDISendableMockScope_Hole.Screen_Scope.panel_Sendable_Values()))
		            return Screen.__safeDI_init(panel: panel, safeDIBuilder: __safeDI_screenBuilder__safeDIBuilder)
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder, holeBuilder: holeBuilder)
		    }
		}

		extension Root {
		    public enum __safeDI_Root_mock_2F2C4181ECE81CFB {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Screen` is constructed within the public mock trees of module `App`.
		nonisolated public struct __safeDI_App_Screen_MockConfiguration {
		    public init(
		        _ safeDIBuilder: (@Sendable (Panel) -> Screen)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    /// Overrides how `Screen` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: (@Sendable (Panel) -> Screen)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            safeDIBuilder: (@Sendable (Panel) -> Screen)?
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let safeDIBuilder: (@Sendable (Panel) -> Screen)?
		    }
		}

		extension Screen {
		    static func __safeDI_init(panel: Panel, safeDIBuilder: (@Sendable (Panel) -> Screen)?) -> Screen {
		        if let safeDIBuilder { safeDIBuilder(panel) } else { Screen(panel: panel) }
		    }
		}
		#endif

		"""])
	}

	/// An internal mock takes one value per name, so the value `Root` receives is the builder of the hole type that `Panel`’s
	/// mock is passed, `@Sendable` since a `@Sendable` builder function captures it.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneSendableBuilderForTheReceivedValueAndThePlaces_whenAnInternalCallerReceivesTheLabelAndTypeOfAnInstantiatorBuilderItsSendableFunctionPassesUp() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.instantiatorHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel"], rootDeclarations: ["@Received let holeBuilder: Instantiator<Hole>.Builder"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

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
		        holeSendableBuilder: @escaping SendableInstantiator<Hole>.Builder,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let holeBuilder: Instantiator<Hole>.Builder = holeSendableBuilder
		        let __safeDI_screenBuilder__overrides = safeDIOverrides.screenBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            _ = Panel.__safeDI_Panel_mock_F0F10F2194E82F9F.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panel() -> Panel {
		                let holeBuilder: Instantiator<Hole>.Builder = holeSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panel { safeDIBuilder(holeBuilder) } else { Panel.__safeDI_mock(holeBuilder: .init(__safeDI_noScope: holeBuilder)) }
		            }
		            let panel: Panel = __safeDI_panel()
		            return if let safeDIBuilder = __safeDI_screenBuilder__overrides.safeDIBuilder { safeDIBuilder(panel) } else { Screen(panel: panel) }
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder, holeBuilder: holeBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Screen {
		    /// Configuration for how this type is constructed within a mock tree.
		    nonisolated struct SafeDIMockConfiguration: Sendable {
		        init(
		            panel: (@Sendable (@escaping Instantiator<Hole>.Builder) -> Panel)? = nil,
		            _ safeDIBuilder: (@Sendable (Panel) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var panel: (@Sendable (@escaping Instantiator<Hole>.Builder) -> Panel)? { __safeDI_storage.panel }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: (@Sendable (Panel) -> Screen)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                panel: (@Sendable (@escaping Instantiator<Hole>.Builder) -> Panel)?,
		                safeDIBuilder: (@Sendable (Panel) -> Screen)?
		            ) {
		                self.panel = panel
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let panel: (@Sendable (@escaping Instantiator<Hole>.Builder) -> Panel)?
		            let safeDIBuilder: (@Sendable (Panel) -> Screen)?
		        }
		    }
		}
		#endif

		"""])
	}

	/// The same, for a mock of `Root` that another module lists in `additionalMocksToGenerate`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneSendableBuilderForTheReceivedValueAndThePlaces_whenAnotherModulesListedMockReceivesTheLabelAndTypeOfAnInstantiatorBuilderItsSendableFunctionPassesUp() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(holeProperty: Self.instantiatorHoleProperty, screenDeclarations: ["@Instantiated let panel: Panel"], rootDeclarations: ["@Received let holeBuilder: Instantiator<Hole>.Builder"], rootMock: .listedInAnotherModule),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["AppMocks"]?.generatedFiles == ["AppMocks.swift": generatedFileHeader + """
		#if canImport(App)
		import App
		#endif
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

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
		        holeSendableBuilder: @escaping SendableInstantiator<Hole>.Builder,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let holeBuilder: Instantiator<Hole>.Builder = holeSendableBuilder
		        let __safeDI_screenBuilder__overrides = safeDIOverrides.screenBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            _ = Panel.__safeDI_Panel_mock_F0F10F2194E82F9F.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_panel() -> Panel {
		                let holeBuilder: Instantiator<Hole>.Builder = holeSendableBuilder
		                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.panel { safeDIBuilder(holeBuilder) } else { Panel.__safeDI_mock(holeBuilder: .init(__safeDI_noScope: holeBuilder)) }
		            }
		            let panel: Panel = __safeDI_panel()
		            return if let safeDIBuilder = __safeDI_screenBuilder__overrides.safeDIBuilder { safeDIBuilder(panel) } else { Screen(panel: panel) }
		        }
		        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
		        return Root(screenBuilder: screenBuilder, holeBuilder: holeBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Screen {
		    /// Configuration for how this type is constructed within a mock tree.
		    nonisolated struct SafeDIMockConfiguration: Sendable {
		        init(
		            panel: (@Sendable (@escaping Instantiator<Hole>.Builder) -> Panel)? = nil,
		            _ safeDIBuilder: (@Sendable (Panel) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var panel: (@Sendable (@escaping Instantiator<Hole>.Builder) -> Panel)? { __safeDI_storage.panel }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: (@Sendable (Panel) -> Screen)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                panel: (@Sendable (@escaping Instantiator<Hole>.Builder) -> Panel)?,
		                safeDIBuilder: (@Sendable (Panel) -> Screen)?
		            ) {
		                self.panel = panel
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let panel: (@Sendable (@escaping Instantiator<Hole>.Builder) -> Panel)?
		            let safeDIBuilder: (@Sendable (Panel) -> Screen)?
		        }
		    }
		}
		#endif

		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A hole of an erased instantiator whose fulfilling type no module declares.
	private static let erasedHoleProperty = #"@Instantiated(fulfilledByType: "HoleFill", erasedToConcreteExistential: true) let holeBuilder: ErasedInstantiator<(), AnyHole>"#

	/// A hole of an instantiator of `Hole`, which conforms to `Instantiable` by hand, so no `@Instantiable` declaration
	/// fulfills it.
	private static let instantiatorHoleProperty = "@Instantiated let holeBuilder: Instantiator<Hole>"

	/// A hole of a `Sendable` erased instantiator whose fulfilling type no module declares.
	private static let sendableErasedHoleProperty = #"@Instantiated(fulfilledByType: "HoleFill", erasedToConcreteExistential: true) let holeBuilder: SendableErasedInstantiator<(), AnyHole>"#

	/// A hole of a `Sendable` instantiator of `Hole`, which conforms to `Instantiable` by hand, so no `@Instantiable`
	/// declaration fulfills it.
	private static let sendableInstantiatorHoleProperty = "@Instantiated let holeBuilder: SendableInstantiator<Hole>"

	/// A hole of an erased instantiator that forwards a `HoleArguments` to the type that fills it, which no module declares.
	private static let forwardingErasedHoleProperty = #"@Instantiated(fulfilledByType: "HoleFill", erasedToConcreteExistential: true) let holeBuilder: ErasedInstantiator<HoleArguments, AnyHole>"#

	/// `Core`, in package `Shop`, which declares `AnyHole`, `Hole`, `HoleArguments` and the public mocks `Panel` and `PanelTwin`, each holding
	/// `holeProperty`; and `App`, in package `Other`, whose `Root` mock builds `Screen`, holding `screenDeclarations`, in a
	/// `SendableInstantiator`, beside `rootDeclarations`, each of a function type, which `Root`’s initializer takes `@escaping`.
	private static func modules(holeProperty: String, screenDeclarations: [String], rootDeclarations: [String] = [], rootMock: RootMock = .internal, isReleaseConfiguration: Bool = false) -> [ModuleFixture] {
		var modules = [
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [
				"""
				import SafeDI

				public protocol HoleProtocol: Sendable {}

				public struct AnyHole: HoleProtocol {
				    public init(_ value: any HoleProtocol) {
				        self.value = value
				    }

				    public let value: any HoleProtocol
				}

				public final class Hole: Instantiable, Sendable {
				    public init() {}
				}

				public struct HoleArguments: Sendable {
				    public init() {}
				}
				""",
				publicMockType(named: "Panel", holeProperty: holeProperty),
				publicMockType(named: "PanelTwin", holeProperty: holeProperty),
			], isReleaseConfiguration: isReleaseConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"""
				import Core
				import SafeDI

				\(rootMock.attribute)
				public final class Root: Instantiable {
				    public init(screenBuilder: SendableInstantiator<Screen>\(rootDeclarations.map { ", \(Self.label(of: $0)): @escaping \(Self.type(of: $0))" }.joined())) {
				        self.screenBuilder = screenBuilder
				\(rootDeclarations.map { "        self.\(Self.label(of: $0)) = \(Self.label(of: $0))\n" }.joined())    }

				    @Instantiated let screenBuilder: SendableInstantiator<Screen>
				\(rootDeclarations.map { "    \($0)\n" }.joined())}
				""",
				"""
				import Core
				import SafeDI

				@Instantiable
				public final class Screen: Instantiable, @unchecked Sendable {
				    public init(\(screenDeclarations.map(Self.parameter(of:)).joined(separator: ", "))) {
				\(screenDeclarations.map { "        self.\(Self.label(of: $0)) = \(Self.label(of: $0))" }.joined(separator: "\n"))
				    }

				\(screenDeclarations.map { "    \($0)" }.joined(separator: "\n"))
				}
				""",
			], dependencies: ["Core"], isReleaseConfiguration: isReleaseConfiguration),
		]
		if rootMock == .listedInAnotherModule {
			modules.append(ModuleFixture(
				name: "AppMocks",
				packageName: "Other",
				swiftFileContentByFilePath: ["SafeDIConfiguration.swift": "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"],
				dependencies: ["Core", "App"],
				isReleaseConfiguration: isReleaseConfiguration,
			))
		}
		return modules
	}

	/// Which mock of `Root` is generated, and where.
	private enum RootMock {
		/// `Root`'s own internal mock.
		case `internal`
		/// `Root`'s own public mock.
		case `public`
		/// An internal mock of `Root` that module `AppMocks` lists in `additionalMocksToGenerate`.
		case listedInAnotherModule

		/// The attribute `Root` is declared with.
		var attribute: String {
			switch self {
			case .internal:
				"@Instantiable(generateMock: true)"
			case .public:
				"@Instantiable(generateMock: .public)"
			case .listedInAnotherModule:
				"@Instantiable"
			}
		}
	}

	/// `name`, a final class holding `holeProperty`, whose public mock is generated and whose initializer is `internal`,
	/// so a mock in another module calls its public mock rather than building it.
	private static func publicMockType(named name: String, holeProperty: String) -> String {
		"""
		import SafeDI

		@Instantiable(generateMock: .public)
		public final class \(name): Instantiable, @unchecked Sendable {
		    init(\(parameter(of: holeProperty))) {
		        self.\(label(of: holeProperty)) = \(label(of: holeProperty))
		    }

		    \(holeProperty)
		}
		"""
	}

	/// The label `declaration`, a `let` of a property, declares.
	private static func label(of declaration: String) -> String {
		String(declaration.components(separatedBy: "let ")[1].prefix { $0 != ":" })
	}

	/// The type `declaration`, a `let` of a property, declares.
	private static func type(of declaration: String) -> String {
		declaration.components(separatedBy: "let ")[1].drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
	}

	/// The initializer parameter of `declaration`, a `let` of a property.
	private static func parameter(of declaration: String) -> String {
		declaration.components(separatedBy: "let ")[1]
	}
}
