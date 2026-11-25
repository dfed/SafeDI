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

/// A mock is passed each `@Instantiated` wrapper it cannot build, and binds it where production declares it, so a `@Sendable`
/// builder function beneath that declaration that reads the wrapper captures it, as production's does: the mock reports
/// production's error at the same receive, for every kind of caller and whether or not the build compiles the mocks.
struct SafeDIToolMockSendableBuilderCaptureTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test(arguments: MockCaptureCaller.allCases, MockCaptureBuild.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsProductionsError_whenSendableBuilderReceivesInstanceOfLazilyInstantiatedMockCannotBuild(caller: MockCaptureCaller, build: MockCaptureBuild) async {
		// `Gizmo` is no `@Instantiable`, so `mock()` takes `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` declares: the
		// `@Sendable` function that builds `Settings` reads its instance, as production's would.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `gizmo: Gizmo` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `gizmo: LazilyInstantiated<Gizmo>` on `Screen`, because `LazilyInstantiated<Gizmo>` is not `Sendable`. Declare `gizmo` on `Screen` as `SendableLazilyInstantiated<Gizmo>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Gizmo`, to be `Sendable`.
				\(fixtures["Screen.swift"]):8:5: note: `gizmo: LazilyInstantiated<Gizmo>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.screenFiles(caller: caller, gizmoType: "LazilyInstantiated<Gizmo>", settingsReceive: "gizmo: Gizmo"),
				swiftFileContentByFilePath: caller.configurationFiles,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: build.activeCompilationConditions,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsSendableCaptureError_whenSendableBuilderReceivesInstanceOfLazilyInstantiatedRootDeclares() async {
		// The production twin of the error above, with `Gizmo` declared `@Instantiable` and `Screen` a root.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `gizmo: Gizmo` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `gizmo: LazilyInstantiated<Gizmo>` on `Screen`, because `LazilyInstantiated<Gizmo>` is not `Sendable`. Declare `gizmo` on `Screen` as `SendableLazilyInstantiated<Gizmo>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Gizmo`, to be `Sendable`.
				\(fixtures["Screen.swift"]):8:5: note: `gizmo: LazilyInstantiated<Gizmo>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Screen: Instantiable {
					    public init(settingsBuilder: SendableInstantiator<Settings>, gizmo: LazilyInstantiated<Gizmo>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					    @Instantiated let gizmo: LazilyInstantiated<Gizmo>
					}

					@Instantiable
					public final class Gizmo: Instantiable, Sendable {
					    public init() {}
					}
					""",
					Self.settingsFile(receive: "gizmo: Gizmo"),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsProductionsError_whenSendableBuilderReceivesLazilyInstantiatedMockCannotBuild() async {
		// The neighbour that receives the wrapper rather than its instance: the error names `Screen`’s declaration, as
		// production’s does, not a value the tree receives from outside it.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `gizmo: LazilyInstantiated<Gizmo>` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `gizmo: LazilyInstantiated<Gizmo>` on `Screen`, because `LazilyInstantiated<Gizmo>` is not `Sendable`. Declare `gizmo` on `Screen`, and this property, as `SendableLazilyInstantiated<Gizmo>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Gizmo`, to be `Sendable`.
				\(fixtures["Screen.swift"]):8:5: note: `gizmo: LazilyInstantiated<Gizmo>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.screenFiles(caller: .internal, gizmoType: "LazilyInstantiated<Gizmo>", settingsReceive: "gizmo: LazilyInstantiated<Gizmo>"),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsProductionsError_whenSendableBuilderReceivesInstantiatorMockCannotBuild() async {
		// The neighbour whose wrapper is an `Instantiator` of a type the mock cannot build.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `gizmo: Instantiator<Gizmo>` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `gizmo: Instantiator<Gizmo>` on `Screen`, because `Instantiator<Gizmo>` is not `Sendable`. Declare `gizmo` on `Screen`, and this property, as `SendableInstantiator<Gizmo>` to fix. `SendableInstantiator<Gizmo>` builds `Gizmo` in a `@Sendable` function, so what the tree of `Gizmo` receives from outside that function must be `Sendable` too.
				\(fixtures["Screen.swift"]):8:5: note: `gizmo: Instantiator<Gizmo>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.screenFiles(caller: .internal, gizmoType: "Instantiator<Gizmo>", settingsReceive: "gizmo: Instantiator<Gizmo>"),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsProductionsError_whenSendableErasedInstantiatorReceivesInstanceOfLazilyInstantiatedMockCannotBuild() async {
		// The neighbour whose `@Sendable` builder function builds an erased instantiator, as the fuzzer’s seed 2760 does.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `gizmo: Gizmo` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settingsBuilder: SendableErasedInstantiator<(), AnySettings>` on `Screen` in a `@Sendable` function, which cannot capture `gizmo: LazilyInstantiated<Gizmo>` on `Screen`, because `LazilyInstantiated<Gizmo>` is not `Sendable`. Declare `gizmo` on `Screen` as `SendableLazilyInstantiated<Gizmo>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Gizmo`, to be `Sendable`.
				\(fixtures["Screen.swift"]):8:5: note: `gizmo: LazilyInstantiated<Gizmo>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(settingsBuilder: SendableErasedInstantiator<(), AnySettings>, gizmo: LazilyInstantiated<Gizmo>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Settings", erasedToConcreteExistential: true) let settingsBuilder: SendableErasedInstantiator<(), AnySettings>
					    @Instantiated let gizmo: LazilyInstantiated<Gizmo>
					}

					public final class Gizmo: Sendable {}

					public final class AnySettings: Sendable {
					    public init(_ value: Settings) {
					        self.value = value
					    }

					    public let value: Settings
					}
					""",
					Self.settingsFile(receive: "gizmo: Gizmo"),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsProductionsError_whenSendableLazilyInstantiatedReceivesInstanceOfLazilyInstantiatedMockCannotBuild() async {
		// The neighbour whose `@Sendable` builder function builds a `SendableLazilyInstantiated`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `gizmo: Gizmo` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settings: SendableLazilyInstantiated<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `gizmo: LazilyInstantiated<Gizmo>` on `Screen`, because `LazilyInstantiated<Gizmo>` is not `Sendable`. Declare `gizmo` on `Screen` as `SendableLazilyInstantiated<Gizmo>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Gizmo`, to be `Sendable`.
				\(fixtures["Screen.swift"]):8:5: note: `gizmo: LazilyInstantiated<Gizmo>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(settings: SendableLazilyInstantiated<Settings>, gizmo: LazilyInstantiated<Gizmo>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let settings: SendableLazilyInstantiated<Settings>
					    @Instantiated let gizmo: LazilyInstantiated<Gizmo>
					}

					public final class Gizmo: Sendable {}
					""",
					Self.settingsFile(receive: "gizmo: Gizmo"),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsProductionsError_whenTypeInMockedTreeDeclaresLazilyInstantiatedMockCannotBuild() async {
		// The neighbour whose wrapper a type beneath the mocked type declares: the error names that type, as production’s
		// does.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `gizmo: Gizmo` cannot be received inside a `@Sendable` function in chain: Screen -> Panel -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Panel` in a `@Sendable` function, which cannot capture `gizmo: LazilyInstantiated<Gizmo>` on `Panel`, because `LazilyInstantiated<Gizmo>` is not `Sendable`. Declare `gizmo` on `Panel` as `SendableLazilyInstantiated<Gizmo>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Gizmo`, to be `Sendable`.
				\(fixtures["Panel.swift"]):8:5: note: `gizmo: LazilyInstantiated<Gizmo>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(panel: Panel) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let panel: Panel
					}

					public final class Gizmo: Sendable {}
					""",
					"""
					@Instantiable
					public final class Panel: Instantiable {
					    public init(settingsBuilder: SendableInstantiator<Settings>, gizmo: LazilyInstantiated<Gizmo>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					    @Instantiated let gizmo: LazilyInstantiated<Gizmo>
					}
					""",
					Self.settingsFile(receive: "gizmo: Gizmo"),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
	}

	@Test(arguments: MockCaptureCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesMock_whenMockedTypeDeclaresSendableLazilyInstantiatedTheErrorSuggests(caller: MockCaptureCaller) async throws {
		// The remedy the errors above state: `Screen` declares `gizmo` as `SendableLazilyInstantiated<Gizmo>`, which the
		// `@Sendable` function may capture.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.screenFiles(caller: caller, gizmoType: "SendableLazilyInstantiated<Gizmo>", settingsReceive: "gizmo: Gizmo"),
			swiftFileContentByFilePath: caller.configurationFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["DEBUG"],
		)

		switch caller {
		case .internal:
			#expect(output.mockFiles == ["Screen+SafeDIMock.swift": """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settingsBuilder: (@Sendable (Gizmo) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var settingsBuilder: (@Sendable (Gizmo) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                settingsBuilder: (@Sendable (Gizmo) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: (@Sendable (Gizmo) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo: SendableLazilyInstantiated<Gizmo>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_settingsBuilder__safeDIBuilder = safeDIOverrides.settingsBuilder
			        @Sendable nonisolated func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = __safeDI_settingsBuilder__safeDIBuilder { safeDIBuilder(gizmo.instance) } else { Settings(gizmo: gizmo.instance) }
			        }
			        let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo)
			    }
			}
			#endif
			"""])
		case .public:
			#expect(output.mockFiles == ["Screen+SafeDIMock.swift": """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDISendableMockScope_Gizmo {
			        nonisolated public struct gizmo_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let gizmo: @Sendable (gizmo_Values) -> __safeDI_Built

			            public init(gizmo: @escaping @Sendable (gizmo_Values) -> __safeDI_Built) {
			                self.gizmo = gizmo
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(gizmo: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            settingsBuilder: (@Sendable (Gizmo) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var settingsBuilder: (@Sendable (Gizmo) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: (@Sendable (Gizmo) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: (@Sendable (Gizmo) -> Settings)?
			        }
			    }

			    public static func mock(
			        gizmoSendableBuilder: @escaping @Sendable () -> Gizmo,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gizmoSendableBuilder: .init(__safeDI_noScope: gizmoSendableBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gizmoSendableBuilder __safeDI_gizmoSendableBuilder: Screen.SafeDISendableMockScope_Gizmo.__safeDI_Builder<Gizmo>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        @Sendable nonisolated func __safeDI_gizmo() -> Gizmo {
			            __safeDI_gizmoSendableBuilder.gizmo(SafeDISendableMockScope_Gizmo.gizmo_Values())
			        }
			        let gizmo = SendableLazilyInstantiated<Gizmo>(__safeDI_gizmo)
			        let __safeDI_settingsBuilder__safeDIBuilder = safeDIOverrides.settingsBuilder
			        @Sendable nonisolated func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = __safeDI_settingsBuilder__safeDIBuilder { safeDIBuilder(gizmo.instance) } else { Settings(gizmo: gizmo.instance) }
			        }
			        let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_CCB04FEA0174F2B9 {}
			}
			#endif
			"""])
		case .listed:
			#expect(output.mockFiles == ["Screen+SafeDIMock.swift": """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settingsBuilder: (@Sendable (Gizmo) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var settingsBuilder: (@Sendable (Gizmo) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                settingsBuilder: (@Sendable (Gizmo) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: (@Sendable (Gizmo) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo: SendableLazilyInstantiated<Gizmo>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_settingsBuilder__safeDIBuilder = safeDIOverrides.settingsBuilder
			        @Sendable nonisolated func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = __safeDI_settingsBuilder__safeDIBuilder { safeDIBuilder(gizmo.instance) } else { Settings(gizmo: gizmo.instance) }
			        }
			        let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo)
			    }
			}
			#endif
			"""])
		}
	}

	@Test(arguments: [MockCaptureCaller.internal, .listed], ["Widget", "Gizmo"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsCaptureError_whenPromotedSiblingReceivesInstantiatorUnderLabelOfLazilyInstantiatedMockCannotBuild(caller: MockCaptureCaller, builtType: String) async {
		// `Screen` receives `settingsBuilder`, which its mock builds at its root, and declares `gizmo` as a
		// `LazilyInstantiated<Gizmo>`, which provides no `Instantiator`: `Settings` receives its `Instantiator` from
		// outside the tree, a parameter of `mock()` that its `@Sendable` builder function cannot capture. A public mock is
		// rejected first, for the hole it would bind apart from its label (the test below).
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `gizmo: Instantiator<\(builtType)>` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `gizmo: Instantiator<\(builtType)>`, which the tree of `Screen` receives from outside it, because `Instantiator<\(builtType)>` is not `Sendable`. Declare `gizmo` as `SendableInstantiator<\(builtType)>` where it is declared and where it is received as `Instantiator<\(builtType)>` to fix. `SendableInstantiator<\(builtType)>` builds `\(builtType)` in a `@Sendable` function, so what the tree of `\(builtType)` receives from outside that function must be `Sendable` too.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.promotedSiblingScreenFiles(caller: caller, gizmoType: "LazilyInstantiated<Gizmo>", settingsReceive: "gizmo: Instantiator<\(builtType)>"),
				swiftFileContentByFilePath: caller.configurationFiles,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
	}

	@Test(arguments: ["Instantiator<Widget>", "Instantiator<Gizmo>", "SendableInstantiator<Widget>"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsHoleBoundApartError_whenPromotedSiblingReceivesWrapperUnderLabelOfLazilyInstantiatedHoleInPublicMock(receivedType: String) async {
		// A public mock would build `Screen`’s `gizmo` at the site of its hole and bind it apart from `Settings`’s `gizmo`,
		// which `mock()` takes under the label, so it is rejected before the capture check runs, whether or not `Settings`
		// receives a `Sendable` wrapper. Its remedy, followed by the capture error’s, is applied in the test after next.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Screen.swift"]):8:5: error: SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: \(receivedType)` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix.
				\(fixtures["Settings.swift"]):7:5: note: `gizmo: \(receivedType)` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.promotedSiblingScreenFiles(caller: .public, gizmoType: "LazilyInstantiated<Gizmo>", settingsReceive: "gizmo: \(receivedType)"),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsCaptureError_whenPublicMockDeclaresHoleUnderAnotherLabelAndPromotedSiblingReceivesInstantiator() async {
		// The hole bound apart's remedy applied: `Screen` declares the hole as `screenGizmo`, so the public mock binds no
		// hole apart, and `Settings`’s `gizmo: Instantiator<Widget>`, which `mock()` takes, meets the capture check.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `gizmo: Instantiator<Widget>` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `gizmo: Instantiator<Widget>`, which the tree of `Screen` receives from outside it, because `Instantiator<Widget>` is not `Sendable`. Declare `gizmo` as `SendableInstantiator<Widget>` where it is declared and where it is received as `Instantiator<Widget>` to fix. `SendableInstantiator<Widget>` builds `Widget` in a `@Sendable` function, so what the tree of `Widget` receives from outside that function must be `Sendable` too.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.promotedSiblingScreenFiles(caller: .public, gizmoLabel: "screenGizmo", gizmoType: "LazilyInstantiated<Gizmo>", settingsReceive: "gizmo: Instantiator<Widget>"),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesMock_whenPublicMockDeclaresHoleUnderAnotherLabelAndPromotedSiblingReceivesSendableInstantiator() async throws {
		// Both remedies applied: `Screen` declares the hole as `screenGizmo`, and `Settings` receives `gizmo` as
		// `SendableInstantiator<Widget>`, a parameter of `mock()` its `@Sendable` builder function may capture.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.promotedSiblingScreenFiles(caller: .public, gizmoLabel: "screenGizmo", gizmoType: "LazilyInstantiated<Gizmo>", settingsReceive: "gizmo: SendableInstantiator<Widget>"),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["DEBUG"],
		)

		#expect(output.mockFiles == ["Screen+SafeDIMock.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    nonisolated public enum SafeDIMockScope_Gizmo {
		        nonisolated public struct screenGizmo_Values {
		            public let gizmo: SendableInstantiator<Widget>
		            public let settingsBuilder: SendableInstantiator<Settings>
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let screenGizmo: (screenGizmo_Values) -> __safeDI_Built

		            public init(screenGizmo: @escaping (screenGizmo_Values) -> __safeDI_Built) {
		                self.screenGizmo = screenGizmo
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(screenGizmo: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                settingsBuilder: settingsBuilder
		            )
		        }

		        public var settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)?
		            ) {
		                self.settingsBuilder = settingsBuilder
		            }

		            let settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)?
		        }
		    }

		    public static func mock(
		        gizmo: SendableInstantiator<Widget>,
		        gizmoBuilder: @escaping () -> Gizmo,
		        settingsBuilder: SendableInstantiator<Settings>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        Screen.__safeDI_mock(gizmo: gizmo, gizmoBuilder: .init(__safeDI_noScope: gizmoBuilder), settingsBuilder: settingsBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        gizmo: SendableInstantiator<Widget>,
		        gizmoBuilder __safeDI_gizmoBuilder: Screen.SafeDIMockScope_Gizmo.__safeDI_Builder<Gizmo>,
		        settingsBuilder: SendableInstantiator<Settings>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_settingsBuilder__safeDIBuilder = safeDIOverrides.settingsBuilder
		        @Sendable nonisolated func __safeDI_settingsBuilder() -> Settings {
		            if let safeDIBuilder = __safeDI_settingsBuilder__safeDIBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
		        }
		        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { SendableInstantiator<Settings>(__safeDI_settingsBuilder) }
		        func __safeDI_screenGizmo() -> Gizmo {
		            __safeDI_gizmoBuilder.screenGizmo(SafeDIMockScope_Gizmo.screenGizmo_Values(gizmo: gizmo, settingsBuilder: settingsBuilder))
		        }
		        let screenGizmo = LazilyInstantiated<Gizmo>(__safeDI_screenGizmo)
		        return Screen(settingsBuilder: settingsBuilder, screenGizmo: screenGizmo)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_16339E378B198D4E {}
		}
		#endif
		"""])
	}

	@Test(arguments: MockCaptureCaller.allCases, ["Widget", "Gizmo"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsCaptureError_whenPromotedSiblingReceivesInstantiatorUnderLabelMockedTypeForwards(caller: MockCaptureCaller, builtType: String) async {
		// `Screen` forwards `gizmo: Gizmo`, which provides no `Instantiator`: `Settings` receives its `Instantiator` from
		// outside the tree, a parameter of `mock()` that its `@Sendable` builder function cannot capture.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `gizmo: Instantiator<\(builtType)>` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `gizmo: Instantiator<\(builtType)>`, which the tree of `Screen` receives from outside it, because `Instantiator<\(builtType)>` is not `Sendable`. Declare `gizmo` as `SendableInstantiator<\(builtType)>` where it is declared and where it is received as `Instantiator<\(builtType)>` to fix. `SendableInstantiator<\(builtType)>` builds `\(builtType)` in a `@Sendable` function, so what the tree of `\(builtType)` receives from outside that function must be `Sendable` too.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.promotedSiblingScreenFiles(caller: caller, gizmoAttribute: "@Forwarded", gizmoType: "Gizmo", settingsReceive: "gizmo: Instantiator<\(builtType)>"),
				swiftFileContentByFilePath: caller.configurationFiles,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
	}

	@Test(arguments: MockCaptureCaller.allCases, ["Widget", "Gizmo"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsCaptureError_whenPromotedSiblingReceivesInstantiatorOnlyIfAvailableUnderLabelMockedTypeForwards(caller: MockCaptureCaller, builtType: String) async {
		// The only-if-available neighbour: the mock binds the optional `Instantiator` at its root, outside the `@Sendable`
		// builder function that builds `Settings`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `gizmo: Instantiator<\(builtType)>?` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `gizmo: Instantiator<\(builtType)>?`, which the tree of `Screen` receives from outside it, because `Instantiator<\(builtType)>` is not `Sendable`. Declare `gizmo` as `SendableInstantiator<\(builtType)>` where it is declared and where it is received as `Instantiator<\(builtType)>` to fix. `SendableInstantiator<\(builtType)>` builds `\(builtType)` in a `@Sendable` function, so what the tree of `\(builtType)` receives from outside that function must be `Sendable` too.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.promotedSiblingScreenFiles(
					caller: caller,
					gizmoAttribute: "@Forwarded",
					gizmoType: "Gizmo",
					settingsReceiveAttribute: "@Received(onlyIfAvailable: true)",
					settingsReceive: "gizmo: Instantiator<\(builtType)>?",
				),
				swiftFileContentByFilePath: caller.configurationFiles,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
	}

	@Test(arguments: MockCaptureCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesMock_whenPromotedSiblingReceivesSendableInstantiatorUnderLabelMockedTypeForwards(caller: MockCaptureCaller) async throws {
		// The remedy the capture error of the forwarded label states: `Settings` receives `gizmo` as
		// `SendableInstantiator<Widget>`, a parameter of `mock()` named apart from `Screen`’s forwarded `gizmo`, which its
		// `@Sendable` builder function may capture.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.promotedSiblingScreenFiles(caller: caller, gizmoAttribute: "@Forwarded", gizmoType: "Gizmo", settingsReceive: "gizmo: SendableInstantiator<Widget>"),
			swiftFileContentByFilePath: caller.configurationFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["DEBUG"],
		)

		let internalMockBody = """
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                settingsBuilder: settingsBuilder
		            )
		        }

		        var settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)?
		            ) {
		                self.settingsBuilder = settingsBuilder
		            }

		            let settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)?
		        }
		    }

		    static func mock(
		        gizmo: Gizmo,
		        gizmo_SendableInstantiator__Widget: SendableInstantiator<Widget>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_settingsBuilder__safeDIBuilder = safeDIOverrides.settingsBuilder
		        @Sendable nonisolated func __safeDI_settingsBuilder() -> Settings {
		            let gizmo: SendableInstantiator<Widget> = gizmo_SendableInstantiator__Widget
		            return if let safeDIBuilder = __safeDI_settingsBuilder__safeDIBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
		        }
		        let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
		        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo)
		    }
		"""
		switch caller {
		case .internal:
			#expect(output.mockFiles == ["Screen+SafeDIMock.swift": """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			\(internalMockBody)
			}
			#endif
			"""])
		case .listed:
			#expect(output.mockFiles == ["Screen+SafeDIMock.swift": """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			\(internalMockBody)
			}
			#endif
			"""])
		case .public:
			#expect(output.mockFiles == ["Screen+SafeDIMock.swift": """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)?
			        }
			    }

			    public static func mock(
			        gizmo: Gizmo,
			        gizmo_SendableInstantiator__Widget: SendableInstantiator<Widget>,
			        settingsBuilder: SendableInstantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gizmo: gizmo, gizmo_SendableInstantiator__Widget: gizmo_SendableInstantiator__Widget, settingsBuilder: settingsBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gizmo: Gizmo,
			        gizmo_SendableInstantiator__Widget: SendableInstantiator<Widget>,
			        settingsBuilder: SendableInstantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_settingsBuilder__safeDIBuilder = safeDIOverrides.settingsBuilder
			        @Sendable nonisolated func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: SendableInstantiator<Widget> = gizmo_SendableInstantiator__Widget
			            return if let safeDIBuilder = __safeDI_settingsBuilder__safeDIBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { SendableInstantiator<Settings>(__safeDI_settingsBuilder) }
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_2A97E17A7A67B617 {}
			}
			#endif
			"""])
		}
	}

	@Test(arguments: MockCaptureCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesMock_whenPromotedSiblingReceivesSendableInstantiatorOnlyIfAvailableUnderLabelMockedTypeForwards(caller: MockCaptureCaller) async throws {
		// The remedy of the only-if-available neighbour: an internal mock binds the optional `SendableInstantiator<Widget>`
		// from an override at its root, and a public mock takes it as a parameter; either may be captured.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.promotedSiblingScreenFiles(
				caller: caller,
				gizmoAttribute: "@Forwarded",
				gizmoType: "Gizmo",
				settingsReceiveAttribute: "@Received(onlyIfAvailable: true)",
				settingsReceive: "gizmo: SendableInstantiator<Widget>?",
			),
			swiftFileContentByFilePath: caller.configurationFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["DEBUG"],
		)

		let internalMockBody = """
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            settingsBuilder: (@Sendable (SendableInstantiator<Widget>?) -> Settings)? = nil,
		            gizmo_SendableInstantiator__Widget: SendableInstantiator<Widget>? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                settingsBuilder: settingsBuilder
		            )
		            self.gizmo_SendableInstantiator__Widget = gizmo_SendableInstantiator__Widget
		        }

		        var settingsBuilder: (@Sendable (SendableInstantiator<Widget>?) -> Settings)? { __safeDI_storage.settingsBuilder }
		        let gizmo_SendableInstantiator__Widget: SendableInstantiator<Widget>?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                settingsBuilder: (@Sendable (SendableInstantiator<Widget>?) -> Settings)?
		            ) {
		                self.settingsBuilder = settingsBuilder
		            }

		            let settingsBuilder: (@Sendable (SendableInstantiator<Widget>?) -> Settings)?
		        }
		    }

		    static func mock(
		        gizmo: Gizmo,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let gizmo_SendableInstantiator__Widget: SendableInstantiator<Widget>? = safeDIOverrides.gizmo_SendableInstantiator__Widget
		        let __safeDI_settingsBuilder__safeDIBuilder = safeDIOverrides.settingsBuilder
		        @Sendable nonisolated func __safeDI_settingsBuilder() -> Settings {
		            let gizmo: SendableInstantiator<Widget>? = gizmo_SendableInstantiator__Widget
		            return if let safeDIBuilder = __safeDI_settingsBuilder__safeDIBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
		        }
		        let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
		        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo)
		    }
		"""
		switch caller {
		case .internal:
			#expect(output.mockFiles == ["Screen+SafeDIMock.swift": """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			\(internalMockBody)
			}
			#endif
			"""])
		case .listed:
			#expect(output.mockFiles == ["Screen+SafeDIMock.swift": """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			\(internalMockBody)
			}
			#endif
			"""])
		case .public:
			#expect(output.mockFiles == ["Screen+SafeDIMock.swift": """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            settingsBuilder: (@Sendable (SendableInstantiator<Widget>?) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var settingsBuilder: (@Sendable (SendableInstantiator<Widget>?) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: (@Sendable (SendableInstantiator<Widget>?) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: (@Sendable (SendableInstantiator<Widget>?) -> Settings)?
			        }
			    }

			    public static func mock(
			        gizmo: Gizmo,
			        gizmo_SendableInstantiator__Widget: SendableInstantiator<Widget>? = nil,
			        settingsBuilder: SendableInstantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gizmo: gizmo, gizmo_SendableInstantiator__Widget: gizmo_SendableInstantiator__Widget, settingsBuilder: settingsBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gizmo: Gizmo,
			        gizmo_SendableInstantiator__Widget: SendableInstantiator<Widget>? = nil,
			        settingsBuilder: SendableInstantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_settingsBuilder__safeDIBuilder = safeDIOverrides.settingsBuilder
			        @Sendable nonisolated func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: SendableInstantiator<Widget>? = gizmo_SendableInstantiator__Widget
			            return if let safeDIBuilder = __safeDI_settingsBuilder__safeDIBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { SendableInstantiator<Settings>(__safeDI_settingsBuilder) }
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_99923DBF3C4DB523 {}
			}
			#endif
			"""])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsProductionsError_whenPromotedSiblingReceivesInstanceOfLazilyInstantiatedMockCannotBuild() async {
		// A promoted sibling of `Screen`’s own declarations gets `Screen`’s `gizmo` by value, which its `@Sendable`
		// builder function reads through the wrapper, as a receive beneath `Screen` does.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `gizmo: Gizmo` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `gizmo: LazilyInstantiated<Gizmo>` on `Screen`, because `LazilyInstantiated<Gizmo>` is not `Sendable`. Declare `gizmo` on `Screen` as `SendableLazilyInstantiated<Gizmo>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Gizmo`, to be `Sendable`.
				\(fixtures["Screen.swift"]):8:5: note: `gizmo: LazilyInstantiated<Gizmo>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.promotedSiblingScreenFiles(caller: .internal, gizmoType: "LazilyInstantiated<Gizmo>", settingsReceive: "gizmo: Gizmo"),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsProductionsError_whenPromotedSiblingReceivesLazilyInstantiatedMockCannotBuild() async {
		// The neighbour that receives the same wrapper kind: the promoted sibling gets `Screen`’s own `gizmo`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `gizmo: LazilyInstantiated<Gizmo>` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `gizmo: LazilyInstantiated<Gizmo>` on `Screen`, because `LazilyInstantiated<Gizmo>` is not `Sendable`. Declare `gizmo` on `Screen`, and this property, as `SendableLazilyInstantiated<Gizmo>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Gizmo`, to be `Sendable`.
				\(fixtures["Screen.swift"]):8:5: note: `gizmo: LazilyInstantiated<Gizmo>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.promotedSiblingScreenFiles(caller: .internal, gizmoType: "LazilyInstantiated<Gizmo>", settingsReceive: "gizmo: LazilyInstantiated<Gizmo>"),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesMock_whenMockedTypeDeclaresSendableLazilyInstantiatedPromotedSiblingReceivesInstanceOf() async throws {
		// The remedy the error above states: `Screen` declares `gizmo` as `SendableLazilyInstantiated<Gizmo>`, whose
		// instance the promoted sibling’s `@Sendable` builder function reads.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.promotedSiblingScreenFiles(caller: .internal, gizmoType: "SendableLazilyInstantiated<Gizmo>", settingsReceive: "gizmo: Gizmo"),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["DEBUG"],
		)

		#expect(output.mockFiles == ["Screen+SafeDIMock.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            settingsBuilder: (@Sendable (Gizmo) -> Settings)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                settingsBuilder: settingsBuilder
		            )
		        }

		        var settingsBuilder: (@Sendable (Gizmo) -> Settings)? { __safeDI_storage.settingsBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                settingsBuilder: (@Sendable (Gizmo) -> Settings)?
		            ) {
		                self.settingsBuilder = settingsBuilder
		            }

		            let settingsBuilder: (@Sendable (Gizmo) -> Settings)?
		        }
		    }

		    static func mock(
		        gizmo: SendableLazilyInstantiated<Gizmo>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_settingsBuilder__safeDIBuilder = safeDIOverrides.settingsBuilder
		        @Sendable nonisolated func __safeDI_settingsBuilder() -> Settings {
		            if let safeDIBuilder = __safeDI_settingsBuilder__safeDIBuilder { safeDIBuilder(gizmo.instance) } else { Settings(gizmo: gizmo.instance) }
		        }
		        let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
		        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo)
		    }
		}
		#endif
		"""])
	}

	@Test(arguments: [MockCaptureCaller.internal, .listed])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesMock_whenPromotedSiblingReceivesSendableInstantiatorTheErrorSuggests(caller: MockCaptureCaller) async throws {
		// The remedy the capture error above states: `Settings` receives `gizmo` as `SendableInstantiator<Widget>`, a
		// parameter of `mock()` named apart from `Screen`’s `gizmo`, which its `@Sendable` builder function may capture. A
		// public mock is rejected for the hole it would bind apart, whose remedy is applied above.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.promotedSiblingScreenFiles(caller: caller, gizmoType: "LazilyInstantiated<Gizmo>", settingsReceive: "gizmo: SendableInstantiator<Widget>"),
			swiftFileContentByFilePath: caller.configurationFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["DEBUG"],
		)

		let importLines = caller == .listed ? "#if canImport(SafeDI)\nimport SafeDI\n#endif\n\n" : ""
		#expect(output.mockFiles == ["Screen+SafeDIMock.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		\(importLines)#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                settingsBuilder: settingsBuilder
		            )
		        }

		        var settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)?
		            ) {
		                self.settingsBuilder = settingsBuilder
		            }

		            let settingsBuilder: (@Sendable (SendableInstantiator<Widget>) -> Settings)?
		        }
		    }

		    static func mock(
		        gizmo_SendableInstantiator__Widget: SendableInstantiator<Widget>,
		        gizmo: LazilyInstantiated<Gizmo>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_settingsBuilder__safeDIBuilder = safeDIOverrides.settingsBuilder
		        @Sendable nonisolated func __safeDI_settingsBuilder() -> Settings {
		            let gizmo: SendableInstantiator<Widget> = gizmo_SendableInstantiator__Widget
		            return if let safeDIBuilder = __safeDI_settingsBuilder__safeDIBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
		        }
		        let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
		        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo)
		    }
		}
		#endif
		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Screen`, mocked as `caller` says, instantiates `settingsBuilder: SendableInstantiator<Settings>` and
	/// `gizmo: <gizmoType>` of `Gizmo`, which is no `@Instantiable`; `Settings` receives `settingsReceive`.
	private static func screenFiles(caller: MockCaptureCaller, gizmoType: String, settingsReceive: String) -> [String] {
		[
			"""
			\(caller.attribute)
			public final class Screen: Instantiable {
			    public init(settingsBuilder: SendableInstantiator<Settings>, gizmo: \(gizmoType)) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
			    @Instantiated let gizmo: \(gizmoType)
			}

			public final class Gizmo: Sendable {}
			""",
			settingsFile(receive: settingsReceive),
		]
	}

	/// `Screen`, mocked as `caller` says, receives `settingsBuilder: SendableInstantiator<Settings>`, which its mock builds
	/// at its root, and declares `<gizmoLabel>: <gizmoType>` of `Gizmo`, which is no `@Instantiable`, with `gizmoAttribute`;
	/// `Settings`, which is not `Sendable`, so that it may hold a wrapper that is not, receives `settingsReceive` with
	/// `settingsReceiveAttribute`. `Widget` is no `@Instantiable` either.
	private static func promotedSiblingScreenFiles(
		caller: MockCaptureCaller,
		gizmoAttribute: String = "@Instantiated",
		gizmoLabel: String = "gizmo",
		gizmoType: String,
		settingsReceiveAttribute: String = "@Received",
		settingsReceive: String,
	) -> [String] {
		[
			"""
			\(caller.attribute)
			public final class Screen: Instantiable {
			    public init(settingsBuilder: SendableInstantiator<Settings>, \(gizmoLabel): \(gizmoType)) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Received let settingsBuilder: SendableInstantiator<Settings>
			    \(gizmoAttribute) let \(gizmoLabel): \(gizmoType)
			}

			public final class Gizmo: Instantiable, Sendable {}

			public final class Widget: Instantiable {}
			""",
			"""
			@Instantiable
			public final class Settings: Instantiable {
			    public init(\(settingsReceive)) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    \(settingsReceiveAttribute) let \(settingsReceive)
			}
			""",
		]
	}

	private static func settingsFile(receive: String) -> String {
		"""
		@Instantiable
		public final class Settings: Instantiable, Sendable {
		    public init(\(receive)) {
		        fatalError("SafeDI doesn't inspect the initializer body")
		    }

		    @Received let \(receive)
		}
		"""
	}
}

/// The kinds of caller whose generated mock builds the tree: an internal mock, a public mock, and a type the module lists in
/// `additionalMocksToGenerate`.
enum MockCaptureCaller: CaseIterable, CustomTestStringConvertible {
	case `internal`
	case `public`
	case listed

	/// The caller’s attribute line.
	var attribute: String {
		switch self {
		case .internal:
			"@Instantiable(generateMock: true)"
		case .public:
			"@Instantiable(generateMock: .public)"
		case .listed:
			"@Instantiable"
		}
	}

	/// The files beside the fixtures that list the caller in `additionalMocksToGenerate`.
	var configurationFiles: [String: String] {
		switch self {
		case .internal, .public:
			[:]
		case .listed:
			["SafeDIConfiguration.swift": "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Screen\"])\n"]
		}
	}

	var testDescription: String {
		switch self {
		case .internal:
			"internal caller"
		case .public:
			"public caller"
		case .listed:
			"listed caller"
		}
	}
}

/// Whether the build tells the tool `DEBUG`, the mock condition: a build that compiles the generated mocks, or one that
/// leaves the condition inactive, as a release build does.
enum MockCaptureBuild: CaseIterable, CustomTestStringConvertible {
	case mockConditionActive
	case mockConditionInactive

	var activeCompilationConditions: [String] {
		switch self {
		case .mockConditionActive:
			["DEBUG"]
		case .mockConditionInactive:
			[]
		}
	}

	var testDescription: String {
		switch self {
		case .mockConditionActive:
			"build that compiles the mocks"
		case .mockConditionInactive:
			"build that leaves the mock condition inactive"
		}
	}
}
