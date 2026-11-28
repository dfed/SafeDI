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

/// `Screen` instantiates a hole whose label a type in the tree of a dependency `Screen` receives receives as another type,
/// so a public mock would bind the hole's site apart from its label and hand its builders `Screen`'s values by label while
/// it holds two under the hole's. A public mock is rejected, whatever other place it has and in whichever order `Screen`
/// declares its places. An internal mock, and a listed type's, takes the hole's dependency as a parameter under its label
/// and has no site, so it accepts the shape: a deliberate gap. The neighbours that bind no hole apart are generated.
struct SafeDIToolPublicMockHoleBoundApartTests: ~Copyable {
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

	@Test(arguments: HoleBoundApartShape.allShapes)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsHoleBoundApartError_whenPublicMockBindsHoleApart(shape: HoleBoundApartShape) async {
		await assertThrowsError(
			diagnostics: { fixtures in
				shape.diagnostics.map { diagnostic in
					"\(fixtures[diagnostic.fileName]):\(diagnostic.line):\(diagnostic.column): \(diagnostic.severity): \(diagnostic.message)"
				}.joined(separator: "\n")
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: shape.files(caller: .public),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsHoleBoundApartError_whenPromotedTypeReceivesHoleLabelThroughAlias() async {
		// `Settings` receives `gizmo: Widget` through an alias, which the mock takes as a parameter under `gizmo`: the note is at
		// the alias, which receives the label.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Screen.swift"]):8:5: error: SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: Gizmo`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Widget` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: Gizmo` on `Screen` under another label to fix.
				\(fixtures["Settings.swift"]):7:5: note: `gizmo: Widget` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public final class Screen: Instantiable {
					    public init(settingsBuilder: Instantiator<Settings>, gizmo: Gizmo, gadget: Gadget) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let settingsBuilder: Instantiator<Settings>
					    @Instantiated let gizmo: Gizmo
					    @Instantiated let gadget: Gadget
					}

					public final class Gizmo: Instantiable {}

					public final class Gadget: Instantiable {}

					public final class Widget: Instantiable {}
					""",
					"""
					@Instantiable
					public final class Settings: Instantiable {
					    public init(widget: Widget) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received(fulfilledByDependencyNamed: "gizmo", ofType: Widget.self) let widget: Widget
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
	}

	@Test(arguments: [MockCaptureCaller.internal, .listed], HoleBoundApartShape.allShapes)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesMock_whenInternalOrListedMockTakesHolePublicMockBindsApart(caller: MockCaptureCaller, shape: HoleBoundApartShape) async throws {
		// The mock takes `Screen`'s hole as a parameter under its label and names the receive's value apart, so it has no site
		// and hands no builder anything.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: shape.files(caller: caller),
			swiftFileContentByFilePath: caller.configurationFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["DEBUG"],
		)

		let importLines = caller == .listed ? "#if canImport(SafeDI)\nimport SafeDI\n#endif\n\n" : ""
		let expectedMockFile = """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		\(importLines)#if DEBUG
		extension Screen {
		\(shape.internalMockBody)
		}
		#endif
		"""
		#expect(output.mockFiles == ["Screen+SafeDIMock.swift": expectedMockFile])
	}

	@Test(arguments: HoleBoundApartControl.allControls)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesMock_whenPublicMockBindsNoHoleApart(control: HoleBoundApartControl) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: control.files,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["DEBUG"],
		)

		#expect(output.mockFiles == ["Screen+SafeDIMock.swift": control.mock])
	}

	// MARK: Private

	private var filesToDelete: [URL]
}

/// A graph whose public mock of `Screen` would bind a site of one of `Screen`'s holes apart from its label.
struct HoleBoundApartShape: CustomTestStringConvertible, Sendable {
	/// A diagnostic the public mock's generation reports, at a line and column of a fixture file.
	struct Diagnostic: Sendable {
		let fileName: String
		let line: Int
		let column: Int
		let severity: String
		let message: String
	}

	let testDescription: String
	/// The fixture files, `Screen` declared `generateMock: .public`.
	let files: [String]
	/// What a public mock's generation reports.
	let diagnostics: [Diagnostic]
	/// The body of the internal mock of `Screen`, and of the listed one.
	let internalMockBody: String

	/// The fixture files with `Screen` declared by `caller`.
	func files(caller: MockCaptureCaller) -> [String] {
		files.map { $0.replacingOccurrences(of: "@Instantiable(generateMock: .public)", with: caller.attribute) }
	}

	static let allShapes: [HoleBoundApartShape] = [
		HoleBoundApartShape(
			testDescription: "second hole declared before the hole bound apart",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gadget: Gadget, gizmo: LazilyInstantiated<Gizmo>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let settingsBuilder: Instantiator<Settings>
				    @Instantiated let gadget: Gadget
				    @Instantiated let gizmo: LazilyInstantiated<Gizmo>
				}

				public final class Gizmo: Instantiable {
				    public init() {}
				}

				public final class Gadget: Instantiable {
				    public init() {}
				}

				public final class Widget: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let gizmo: Instantiator<Widget>
				}
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 9, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Settings.swift", line: 7, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gadget: Gadget,
			        gizmo: LazilyInstantiated<Gizmo>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gadget: gadget, gizmo: gizmo)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "hole beneath a promoted constant, declared after it",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settings: Settings, gizmo: LazilyInstantiated<Gizmo>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settings: Settings
				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>, thing: Thing) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				    @Instantiated public let thing: Thing
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Widget: Instantiable { public init() {} }
				public final class Thing: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 16, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settings: ((Instantiator<Widget>, Thing) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settings: settings
			            )
			        }

			        var settings: ((Instantiator<Widget>, Thing) -> Settings)? { __safeDI_storage.settings }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settings: ((Instantiator<Widget>, Thing) -> Settings)?
			            ) {
			                self.settings = settings
			            }

			            let settings: ((Instantiator<Widget>, Thing) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gizmo: LazilyInstantiated<Gizmo>,
			        thing: Thing,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settings() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			            return if let safeDIBuilder = safeDIOverrides.settings { safeDIBuilder(gizmo, thing) } else { Settings(gizmo: gizmo, thing: thing) }
			        }
			        let settings: Settings = __safeDI_settings()
			        return Screen(settings: settings, gizmo: gizmo)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "hole beneath a promoted constant, declared before it",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(gizmo: LazilyInstantiated<Gizmo>, settings: Settings) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				    @Received public let settings: Settings
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>, thing: Thing) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				    @Instantiated public let thing: Thing
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Widget: Instantiable { public init() {} }
				public final class Thing: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 7, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 16, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settings: ((Instantiator<Widget>, Thing) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settings: settings
			            )
			        }

			        var settings: ((Instantiator<Widget>, Thing) -> Settings)? { __safeDI_storage.settings }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settings: ((Instantiator<Widget>, Thing) -> Settings)?
			            ) {
			                self.settings = settings
			            }

			            let settings: ((Instantiator<Widget>, Thing) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gizmo: LazilyInstantiated<Gizmo>,
			        thing: Thing,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settings() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			            return if let safeDIBuilder = safeDIOverrides.settings { safeDIBuilder(gizmo, thing) } else { Settings(gizmo: gizmo, thing: thing) }
			        }
			        let settings: Settings = __safeDI_settings()
			        return Screen(gizmo: gizmo, settings: settings)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "hole two types beneath a promoted constant, declared after it",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settings: Settings, gizmo: LazilyInstantiated<Gizmo>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settings: Settings
				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>, inner: Inner) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				    @Instantiated public let inner: Inner
				}
				@Instantiable
				public final class Inner: Instantiable {
				    public init(thing: Thing) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated public let thing: Thing
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Widget: Instantiable { public init() {} }
				public final class Thing: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 16, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settings: Settings.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settings: settings
			            )
			        }

			        var settings: Settings.SafeDIMockConfiguration { __safeDI_storage.settings }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settings: Settings.SafeDIMockConfiguration
			            ) {
			                self.settings = settings
			            }

			            let settings: Settings.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gizmo: LazilyInstantiated<Gizmo>,
			        thing: Thing,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settings() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			            let inner = if let safeDIBuilder = safeDIOverrides.settings.inner { safeDIBuilder(thing) } else { Inner(thing: thing) }
			            return if let safeDIBuilder = safeDIOverrides.settings.safeDIBuilder { safeDIBuilder(gizmo, inner) } else { Settings(gizmo: gizmo, inner: inner) }
			        }
			        let settings: Settings = __safeDI_settings()
			        return Screen(settings: settings, gizmo: gizmo)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "hole two types beneath a promoted constant, declared before it",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(gizmo: LazilyInstantiated<Gizmo>, settings: Settings) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				    @Received public let settings: Settings
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>, inner: Inner) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				    @Instantiated public let inner: Inner
				}
				@Instantiable
				public final class Inner: Instantiable {
				    public init(thing: Thing) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated public let thing: Thing
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Widget: Instantiable { public init() {} }
				public final class Thing: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 7, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 16, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settings: Settings.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settings: settings
			            )
			        }

			        var settings: Settings.SafeDIMockConfiguration { __safeDI_storage.settings }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settings: Settings.SafeDIMockConfiguration
			            ) {
			                self.settings = settings
			            }

			            let settings: Settings.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gizmo: LazilyInstantiated<Gizmo>,
			        thing: Thing,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settings() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			            let inner = if let safeDIBuilder = safeDIOverrides.settings.inner { safeDIBuilder(thing) } else { Inner(thing: thing) }
			            return if let safeDIBuilder = safeDIOverrides.settings.safeDIBuilder { safeDIBuilder(gizmo, inner) } else { Settings(gizmo: gizmo, inner: inner) }
			        }
			        let settings: Settings = __safeDI_settings()
			        return Screen(gizmo: gizmo, settings: settings)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "hole beneath a promoted Instantiator, declared after it",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: LazilyInstantiated<Gizmo>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>, thing: Thing) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				    @Instantiated public let thing: Thing
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Widget: Instantiable { public init() {} }
				public final class Thing: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 16, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gizmo: LazilyInstantiated<Gizmo>,
			        thing: Thing,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo, thing) } else { Settings(gizmo: gizmo, thing: thing) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "hole beneath a promoted Instantiator, declared before it",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(gizmo: LazilyInstantiated<Gizmo>, settingsBuilder: Instantiator<Settings>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				    @Received public let settingsBuilder: Instantiator<Settings>
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>, thing: Thing) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				    @Instantiated public let thing: Thing
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Widget: Instantiable { public init() {} }
				public final class Thing: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 7, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 16, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gizmo: LazilyInstantiated<Gizmo>,
			        thing: Thing,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo, thing) } else { Settings(gizmo: gizmo, thing: thing) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(gizmo: gizmo, settingsBuilder: settingsBuilder)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "hole two types beneath a promoted Instantiator, declared after it",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: LazilyInstantiated<Gizmo>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>, inner: Inner) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				    @Instantiated public let inner: Inner
				}
				@Instantiable
				public final class Inner: Instantiable {
				    public init(gizmo: Instantiator<Widget>, thing: Thing) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				    @Instantiated public let thing: Thing
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Widget: Instantiable { public init() {} }
				public final class Thing: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 16, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settingsBuilder: Settings.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var settingsBuilder: Settings.SafeDIMockConfiguration { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: Settings.SafeDIMockConfiguration
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: Settings.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gizmo: LazilyInstantiated<Gizmo>,
			        thing: Thing,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			            func __safeDI_inner() -> Inner {
			                let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			                return if let safeDIBuilder = safeDIOverrides.settingsBuilder.inner { safeDIBuilder(gizmo, thing) } else { Inner(gizmo: gizmo, thing: thing) }
			            }
			            let inner: Inner = __safeDI_inner()
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder.safeDIBuilder { safeDIBuilder(gizmo, inner) } else { Settings(gizmo: gizmo, inner: inner) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "hole two types beneath a promoted Instantiator, declared before it",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(gizmo: LazilyInstantiated<Gizmo>, settingsBuilder: Instantiator<Settings>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				    @Received public let settingsBuilder: Instantiator<Settings>
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>, inner: Inner) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				    @Instantiated public let inner: Inner
				}
				@Instantiable
				public final class Inner: Instantiable {
				    public init(gizmo: Instantiator<Widget>, thing: Thing) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				    @Instantiated public let thing: Thing
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Widget: Instantiable { public init() {} }
				public final class Thing: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 7, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 16, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settingsBuilder: Settings.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var settingsBuilder: Settings.SafeDIMockConfiguration { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: Settings.SafeDIMockConfiguration
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: Settings.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gizmo: LazilyInstantiated<Gizmo>,
			        thing: Thing,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			            func __safeDI_inner() -> Inner {
			                let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			                return if let safeDIBuilder = safeDIOverrides.settingsBuilder.inner { safeDIBuilder(gizmo, thing) } else { Inner(gizmo: gizmo, thing: thing) }
			            }
			            let inner: Inner = __safeDI_inner()
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder.safeDIBuilder { safeDIBuilder(gizmo, inner) } else { Settings(gizmo: gizmo, inner: inner) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(gizmo: gizmo, settingsBuilder: settingsBuilder)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "hole beneath a promoted Instantiator and a later hole, declared after it",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: LazilyInstantiated<Gizmo>, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>, thing: Thing) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				    @Instantiated public let thing: Thing
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Widget: Instantiable { public init() {} }
				public final class Thing: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 17, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gizmo: LazilyInstantiated<Gizmo>,
			        gadget: Gadget,
			        thing: Thing,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo, thing) } else { Settings(gizmo: gizmo, thing: thing) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo, gadget: gadget)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "hole beneath a promoted Instantiator and a later hole, declared before it",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(gizmo: LazilyInstantiated<Gizmo>, settingsBuilder: Instantiator<Settings>, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>, thing: Thing) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				    @Instantiated public let thing: Thing
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Widget: Instantiable { public init() {} }
				public final class Thing: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 7, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 17, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: ((Instantiator<Widget>, Thing) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gizmo: LazilyInstantiated<Gizmo>,
			        gadget: Gadget,
			        thing: Thing,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo, thing) } else { Settings(gizmo: gizmo, thing: thing) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(gizmo: gizmo, settingsBuilder: settingsBuilder, gadget: gadget)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "two holes bound apart, then a hole",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: LazilyInstantiated<Gizmo>, gear: Gear, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				    @Instantiated public let gear: Gear
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>, gear: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				    @Received public let gear: Instantiator<Widget>
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Widget: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				public final class Gear: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 18, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settingsBuilder: ((Instantiator<Widget>, Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var settingsBuilder: ((Instantiator<Widget>, Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: ((Instantiator<Widget>, Instantiator<Widget>) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: ((Instantiator<Widget>, Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gear_Instantiator__Widget: Instantiator<Widget>,
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gizmo: LazilyInstantiated<Gizmo>,
			        gear: Gear,
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			            let gear: Instantiator<Widget> = gear_Instantiator__Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo, gear) } else { Settings(gizmo: gizmo, gear: gear) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo, gear: gear, gadget: gadget)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "receive only if available, then a hole",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Gizmo, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: Gizmo
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Widget?) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received(onlyIfAvailable: true) public let gizmo: Widget?
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Widget: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: Gizmo`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Widget?` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: Gizmo` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 17, column: 5, severity: "note", message: "`gizmo: Widget?` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settingsBuilder: ((Widget?) -> Settings)? = nil,
			            gizmo_Widget: Widget? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			            self.gizmo_Widget = gizmo_Widget
			        }

			        var settingsBuilder: ((Widget?) -> Settings)? { __safeDI_storage.settingsBuilder }
			        let gizmo_Widget: Widget?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: ((Widget?) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: ((Widget?) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo: Gizmo,
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let gizmo_Widget: Widget? = safeDIOverrides.gizmo_Widget
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Widget? = gizmo_Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo, gadget: gadget)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "receive only if available of a built type, then a hole",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: LazilyInstantiated<Gizmo>, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Widget?) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received(onlyIfAvailable: true) public let gizmo: Widget?
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Widget?` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 17, column: 5, severity: "note", message: "`gizmo: Widget?` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settingsBuilder: ((Widget?) -> Settings)? = nil,
			            gizmo_Widget: Widget? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			            self.gizmo_Widget = gizmo_Widget
			        }

			        var settingsBuilder: ((Widget?) -> Settings)? { __safeDI_storage.settingsBuilder }
			        let gizmo_Widget: Widget?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: ((Widget?) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: ((Widget?) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo: LazilyInstantiated<Gizmo>,
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let gizmo_Widget: Widget? = safeDIOverrides.gizmo_Widget
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Widget? = gizmo_Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo, gadget: gadget)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "erased holes of protocols",
			files: [
				"""
				public protocol GizmoProtocol {}
				public protocol GadgetProtocol {}
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: any GizmoProtocol, gadget: any GadgetProtocol) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: any GizmoProtocol
				    @Instantiated public let gadget: any GadgetProtocol
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 10, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: any GizmoProtocol`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: any GizmoProtocol` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 19, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_GizmoProtocol: any GizmoProtocol,
			        gadget: any GadgetProtocol,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = Instantiator<Widget>(__safeDI_gizmo)
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_GizmoProtocol, gadget: gadget)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "hole beneath a type held in a SendableInstantiator",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Gizmo, panel: SendableInstantiator<Panel>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: Gizmo
				    @Instantiated public let panel: SendableInstantiator<Panel>
				}
				@Instantiable
				public final class Panel: Instantiable {
				    public init(gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Widget: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: Gizmo`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: Gizmo` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 25, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            panel: (@Sendable (Gadget) -> Panel)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var panel: (@Sendable (Gadget) -> Panel)? { __safeDI_storage.panel }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                panel: (@Sendable (Gadget) -> Panel)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.panel = panel
			                self.settingsBuilder = settingsBuilder
			            }

			            let panel: (@Sendable (Gadget) -> Panel)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gizmo: Gizmo,
			        gadget: @autoclosure @escaping @Sendable () -> Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_gadget = gadget
			        let __safeDI_panel__safeDIBuilder = safeDIOverrides.panel
			        @Sendable nonisolated func __safeDI_panel() -> Panel {
			            let gadget = __safeDI_gadget()
			            return if let safeDIBuilder = __safeDI_panel__safeDIBuilder { safeDIBuilder(gadget) } else { Panel(gadget: gadget) }
			        }
			        let panel = SendableInstantiator<Panel>(__safeDI_panel)
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo, panel: panel)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "built Instantiator receive, hole declared after a hole",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gadget: Gadget, gizmo: Gizmo) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gadget: Gadget
				    @Instantiated public let gizmo: Gizmo
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 9, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: Gizmo`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: Gizmo` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 17, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gadget: Gadget,
			        gizmo_Gizmo: Gizmo,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = Instantiator<Widget>(__safeDI_gizmo)
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gadget: gadget, gizmo: gizmo_Gizmo)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "built Instantiator receive, then a hole beneath a type held as itself",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Gizmo, panel: Panel) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: Gizmo
				    @Instantiated public let panel: Panel
				}
				@Instantiable
				public final class Panel: Instantiable {
				    public init(gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: Gizmo`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: Gizmo` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 25, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            panel: ((Gadget) -> Panel)? = nil,
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel,
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var panel: ((Gadget) -> Panel)? { __safeDI_storage.panel }
			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                panel: ((Gadget) -> Panel)?,
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.panel = panel
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let panel: ((Gadget) -> Panel)?
			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Gizmo: Gizmo,
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let panel = if let safeDIBuilder = safeDIOverrides.panel { safeDIBuilder(gadget) } else { Panel(gadget: gadget) }
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = Instantiator<Widget>(__safeDI_gizmo)
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_Gizmo, panel: panel)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "built Instantiator receive, then a hole beneath a type held in an Instantiator",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Gizmo, panel: Instantiator<Panel>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: Gizmo
				    @Instantiated public let panel: Instantiator<Panel>
				}
				@Instantiable
				public final class Panel: Instantiable {
				    public init(gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: Gizmo`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: Gizmo` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 25, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            panel: ((Gadget) -> Panel)? = nil,
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel,
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var panel: ((Gadget) -> Panel)? { __safeDI_storage.panel }
			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                panel: ((Gadget) -> Panel)?,
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.panel = panel
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let panel: ((Gadget) -> Panel)?
			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Gizmo: Gizmo,
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_panel() -> Panel {
			            if let safeDIBuilder = safeDIOverrides.panel { safeDIBuilder(gadget) } else { Panel(gadget: gadget) }
			        }
			        let panel = Instantiator<Panel>(__safeDI_panel)
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = Instantiator<Widget>(__safeDI_gizmo)
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_Gizmo, panel: panel)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "built Instantiator receive, Instantiator hole, then a hole",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Instantiator<Gizmo>, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: Instantiator<Gizmo>
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: Instantiator<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: Instantiator<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 17, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Instantiator__Gizmo: Instantiator<Gizmo>,
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = Instantiator<Widget>(__safeDI_gizmo)
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_Instantiator__Gizmo, gadget: gadget)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "built Instantiator receive, LazilyInstantiated hole, then a hole",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: LazilyInstantiated<Gizmo>, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 17, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_LazilyInstantiated__Gizmo: LazilyInstantiated<Gizmo>,
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = Instantiator<Widget>(__safeDI_gizmo)
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_LazilyInstantiated__Gizmo, gadget: gadget)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "built constant receive, hole held as itself, then a hole",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Gizmo, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: Gizmo
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Widget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Widget
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: Gizmo`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Widget` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: Gizmo` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 17, column: 5, severity: "note", message: "`gizmo: Widget` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Widget) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settingsBuilder: ((Widget) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Widget) -> Settings)?
			            ) {
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Widget) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Gizmo: Gizmo,
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let gizmo = if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_Gizmo, gadget: gadget)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "built Instantiator receive, three holes",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gear: Gear, gizmo: Gizmo, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gear: Gear
				    @Instantiated public let gizmo: Gizmo
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				public final class Gear: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 9, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: Gizmo`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: Gizmo` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 18, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gear: Gear,
			        gizmo_Gizmo: Gizmo,
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = Instantiator<Widget>(__safeDI_gizmo)
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gear: gear, gizmo: gizmo_Gizmo, gadget: gadget)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "built Instantiator receive by a received constant, then a hole",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settings: Settings, gizmo: Gizmo, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settings: Settings
				    @Instantiated public let gizmo: Gizmo
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: Gizmo`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: Gizmo` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 17, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo: (() -> Widget)? = nil,
			            settings: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo: gizmo,
			                settings: settings
			            )
			        }

			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settings: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settings }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo: (() -> Widget)?,
			                settings: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.gizmo = gizmo
			                self.settings = settings
			            }

			            let gizmo: (() -> Widget)?
			            let settings: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Gizmo: Gizmo,
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = Instantiator<Widget>(__safeDI_gizmo)
			        let settings = if let safeDIBuilder = safeDIOverrides.settings { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        return Screen(settings: settings, gizmo: gizmo_Gizmo, gadget: gadget)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "built constant receive, LazilyInstantiated hole, then a hole",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: LazilyInstantiated<Gizmo>, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Widget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Widget
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Widget` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 17, column: 5, severity: "note", message: "`gizmo: Widget` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Widget) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settingsBuilder: ((Widget) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Widget) -> Settings)?
			            ) {
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Widget) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_LazilyInstantiated__Gizmo: LazilyInstantiated<Gizmo>,
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let gizmo = if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_LazilyInstantiated__Gizmo, gadget: gadget)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "built Instantiator receive, hole held as itself, then a hole",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Gizmo, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: Gizmo
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: Gizmo`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: Gizmo` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 17, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Gizmo: Gizmo,
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = Instantiator<Widget>(__safeDI_gizmo)
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_Gizmo, gadget: gadget)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "built Instantiator receive, single hole held as itself",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Gizmo) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: Gizmo
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: Gizmo`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: Gizmo` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 16, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Gizmo: Gizmo,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = Instantiator<Widget>(__safeDI_gizmo)
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_Gizmo)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "built Instantiator receive, single hole held as itself, which a child built as itself receives",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Gizmo, panel: Panel) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: Gizmo
				    @Instantiated public let panel: Panel
				}
				@Instantiable
				public final class Panel: Instantiable {
				    public init(gizmo: Gizmo) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Gizmo
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: Gizmo`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: Gizmo` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 25, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            panel: ((Gizmo) -> Panel)? = nil,
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel,
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var panel: ((Gizmo) -> Panel)? { __safeDI_storage.panel }
			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                panel: ((Gizmo) -> Panel)?,
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.panel = panel
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let panel: ((Gizmo) -> Panel)?
			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Gizmo: Gizmo,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_panel() -> Panel {
			            let gizmo: Gizmo = gizmo_Gizmo
			            return if let safeDIBuilder = safeDIOverrides.panel { safeDIBuilder(gizmo) } else { Panel(gizmo: gizmo) }
			        }
			        let panel: Panel = __safeDI_panel()
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = Instantiator<Widget>(__safeDI_gizmo)
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_Gizmo, panel: panel)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "built Instantiator receive, single hole held in a LazilyInstantiated, which a child built as itself receives",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: LazilyInstantiated<Gizmo>, panel: Panel) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: LazilyInstantiated<Gizmo>
				    @Instantiated public let panel: Panel
				}
				@Instantiable
				public final class Panel: Instantiable {
				    public init(gizmo: LazilyInstantiated<Gizmo>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: LazilyInstantiated<Gizmo>
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo: LazilyInstantiated<Gizmo>`, which `Screen` instantiates, with a builder `mock()` is passed, and `Settings` receives `gizmo: Instantiator<Widget>` with the same label, so the mock holds two values labeled `gizmo` and cannot hand `gizmo` to the builder `mock()` is passed. Declare `gizmo: LazilyInstantiated<Gizmo>` on `Screen` under another label to fix."),
				.init(fileName: "Screen.swift", line: 25, column: 5, severity: "note", message: "`gizmo: Instantiator<Widget>` is received here"),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            panel: ((LazilyInstantiated<Gizmo>) -> Panel)? = nil,
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel,
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var panel: ((LazilyInstantiated<Gizmo>) -> Panel)? { __safeDI_storage.panel }
			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                panel: ((LazilyInstantiated<Gizmo>) -> Panel)?,
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.panel = panel
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let panel: ((LazilyInstantiated<Gizmo>) -> Panel)?
			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_LazilyInstantiated__Gizmo: LazilyInstantiated<Gizmo>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_panel() -> Panel {
			            let gizmo: LazilyInstantiated<Gizmo> = gizmo_LazilyInstantiated__Gizmo
			            return if let safeDIBuilder = safeDIOverrides.panel { safeDIBuilder(gizmo) } else { Panel(gizmo: gizmo) }
			        }
			        let panel: Panel = __safeDI_panel()
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = Instantiator<Widget>(__safeDI_gizmo)
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_LazilyInstantiated__Gizmo, panel: panel)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "hole labeled as a sibling SafeDI names apart",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo_Widget: Gizmo) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo_Widget: Gizmo
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Widget, prefs: Prefs) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Widget
				    @Received public let prefs: Prefs
				}
				@Instantiable
				public final class Prefs: Instantiable {
				    public init(gizmo: Knob) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Knob
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }
				}
				@Instantiable
				public final class Knob: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }
				}
				public final class Gizmo: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo_Widget: Gizmo`, which `Screen` instantiates, with a builder `mock()` is passed, and cannot hand `gizmo_Widget` to the builder `mock()` is passed, because SafeDI names another value of the mock `gizmo_Widget`. Declare `gizmo_Widget: Gizmo` on `Screen` under another label to fix."),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo_Widget: (() -> Widget)? = nil,
			            gizmo_Knob: (() -> Knob)? = nil,
			            prefs: ((Knob) -> Prefs)? = nil,
			            settingsBuilder: ((Widget, Prefs) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo_Widget: gizmo_Widget,
			                gizmo_Knob: gizmo_Knob,
			                prefs: prefs,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var gizmo_Widget: (() -> Widget)? { __safeDI_storage.gizmo_Widget }
			        var gizmo_Knob: (() -> Knob)? { __safeDI_storage.gizmo_Knob }
			        var prefs: ((Knob) -> Prefs)? { __safeDI_storage.prefs }
			        var settingsBuilder: ((Widget, Prefs) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo_Widget: (() -> Widget)?,
			                gizmo_Knob: (() -> Knob)?,
			                prefs: ((Knob) -> Prefs)?,
			                settingsBuilder: ((Widget, Prefs) -> Settings)?
			            ) {
			                self.gizmo_Widget = gizmo_Widget
			                self.gizmo_Knob = gizmo_Knob
			                self.prefs = prefs
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo_Widget: (() -> Widget)?
			            let gizmo_Knob: (() -> Knob)?
			            let prefs: ((Knob) -> Prefs)?
			            let settingsBuilder: ((Widget, Prefs) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Widget_Gizmo: Gizmo,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let gizmo_Widget = if let safeDIBuilder = safeDIOverrides.gizmo_Widget { safeDIBuilder() } else { Widget() }
			        let gizmo_Knob = if let safeDIBuilder = safeDIOverrides.gizmo_Knob { safeDIBuilder() } else { Knob() }
			        func __safeDI_prefs() -> Prefs {
			            let gizmo: Knob = gizmo_Knob
			            return if let safeDIBuilder = safeDIOverrides.prefs { safeDIBuilder(gizmo) } else { Prefs(gizmo: gizmo) }
			        }
			        let prefs: Prefs = __safeDI_prefs()
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Widget = gizmo_Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo, prefs) } else { Settings(gizmo: gizmo, prefs: prefs) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo_Widget: gizmo_Widget_Gizmo)
			    }
			""",
		),
		HoleBoundApartShape(
			testDescription: "hole labeled as a parameter SafeDI names apart",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo_Other: Gizmo) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo_Other: Gizmo
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Other, prefs: Prefs) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Other
				    @Received public let prefs: Prefs
				}
				@Instantiable
				public final class Prefs: Instantiable {
				    public init(gizmo: Another) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Another
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Other: Instantiable { public init() {} }
				public final class Another: Instantiable { public init() {} }
				""",
			],
			diagnostics: [
				.init(fileName: "Screen.swift", line: 8, column: 5, severity: "error", message: "SafeDI cannot generate the public mock of `Screen`: the mock builds `gizmo_Other: Gizmo`, which `Screen` instantiates, with a builder `mock()` is passed, and cannot hand `gizmo_Other` to the builder `mock()` is passed, because SafeDI names another value of the mock `gizmo_Other`. Declare `gizmo_Other: Gizmo` on `Screen` under another label to fix."),
			],
			internalMockBody: """
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            prefs: ((Another) -> Prefs)? = nil,
			            settingsBuilder: ((Other, Prefs) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                prefs: prefs,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var prefs: ((Another) -> Prefs)? { __safeDI_storage.prefs }
			        var settingsBuilder: ((Other, Prefs) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                prefs: ((Another) -> Prefs)?,
			                settingsBuilder: ((Other, Prefs) -> Settings)?
			            ) {
			                self.prefs = prefs
			                self.settingsBuilder = settingsBuilder
			            }

			            let prefs: ((Another) -> Prefs)?
			            let settingsBuilder: ((Other, Prefs) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo_Another: Another,
			        gizmo_Other_: Other,
			        gizmo_Other: Gizmo,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_prefs() -> Prefs {
			            let gizmo: Another = gizmo_Another
			            return if let safeDIBuilder = safeDIOverrides.prefs { safeDIBuilder(gizmo) } else { Prefs(gizmo: gizmo) }
			        }
			        let prefs: Prefs = __safeDI_prefs()
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Other = gizmo_Other_
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo, prefs) } else { Settings(gizmo: gizmo, prefs: prefs) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo_Other: gizmo_Other)
			    }
			""",
		),
	]
}

/// A graph next to `HoleBoundApartShape` that binds no site of a hole apart, which a public mock generates, with the mock
/// it generates.
struct HoleBoundApartControl: CustomTestStringConvertible, Sendable {
	let testDescription: String
	let files: [String]
	/// The whole mock file of `Screen`.
	let mock: String

	static let allControls: [HoleBoundApartControl] = [
		HoleBoundApartControl(
			testDescription: "two holes and no shared label, public caller",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Gizmo, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo: Gizmo
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(widget: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let widget: Instantiator<Widget>
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct gadget_Values {
			            public let widget: Instantiator<Widget>
			            public let settingsBuilder: Instantiator<Settings>
			            public let gizmo: Gizmo
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gadget: (gadget_Values) -> __safeDI_Built

			            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                self.gadget = gadget
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(gadget: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    nonisolated public enum SafeDIMockScope_Gizmo {
			        nonisolated public struct gizmo_Values {
			            public let widget: Instantiator<Widget>
			            public let settingsBuilder: Instantiator<Settings>
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gizmo: (gizmo_Values) -> __safeDI_Built

			            public init(gizmo: @escaping (gizmo_Values) -> __safeDI_Built) {
			                self.gizmo = gizmo
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(gizmo: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            widget: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                widget: widget,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var widget: (() -> Widget)? { __safeDI_storage.widget }
			        public var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                widget: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.widget = widget
			                self.settingsBuilder = settingsBuilder
			            }

			            let widget: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    public static func mock(
			        gadgetBuilder: @escaping () -> Gadget,
			        gizmoBuilder: @escaping () -> Gizmo,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        widget: Instantiator<Widget>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), gizmoBuilder: .init(__safeDI_noScope: gizmoBuilder), settingsBuilder: settingsBuilder, widget: widget, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Screen.SafeDIMockScope_Gadget.__safeDI_Builder<Gadget>,
			        gizmoBuilder __safeDI_gizmoBuilder: Screen.SafeDIMockScope_Gizmo.__safeDI_Builder<Gizmo>,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        widget: Instantiator<Widget>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_widget() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.widget { safeDIBuilder() } else { Widget() }
			        }
			        let widget = if let widget { widget } else { Instantiator<Widget>(__safeDI_widget) }
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(widget) } else { Settings(widget: widget) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { Instantiator<Settings>(__safeDI_settingsBuilder) }
			        let gizmo: Gizmo = __safeDI_gizmoBuilder.gizmo(SafeDIMockScope_Gizmo.gizmo_Values(widget: widget, settingsBuilder: settingsBuilder))
			        let gadget: Gadget = __safeDI_gadgetBuilder.gadget(SafeDIMockScope_Gadget.gadget_Values(widget: widget, settingsBuilder: settingsBuilder, gizmo: gizmo))
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo, gadget: gadget)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_0858B0F05EB62796 {}
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "alias bound apart, then a hole, public caller",
			files: [
				"""
				public protocol Source {}
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, store: Store, gizmo: any Source, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Received public let store: Store
				    @Received(fulfilledByDependencyNamed: "store", ofType: Store.self) public let gizmo: any Source
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Store: Instantiable, Source {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				public final class Widget: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct gadget_Values {
			            public let gizmo: Instantiator<Widget>
			            public let store: Store
			            public let settingsBuilder: Instantiator<Settings>
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gadget: (gadget_Values) -> __safeDI_Built

			            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                self.gadget = gadget
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(gadget: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            store: (() -> Store)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                store: store,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var store: (() -> Store)? { __safeDI_storage.store }
			        public var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                store: (() -> Store)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.store = store
			                self.settingsBuilder = settingsBuilder
			            }

			            let store: (() -> Store)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    public static func mock(
			        gizmo: Instantiator<Widget>,
			        gadgetBuilder: @escaping () -> Gadget,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        store: Store? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gizmo: gizmo, gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), settingsBuilder: settingsBuilder, store: store, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gizmo: Instantiator<Widget>,
			        gadgetBuilder __safeDI_gadgetBuilder: Screen.SafeDIMockScope_Gadget.__safeDI_Builder<Gadget>,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        store: Store? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let store = if let store { store } else if let safeDIBuilder = safeDIOverrides.store { safeDIBuilder() } else { Store() }
			        let gizmo_Source: any Source = store // Declared as Screen.gizmo
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { Instantiator<Settings>(__safeDI_settingsBuilder) }
			        let gadget: Gadget = __safeDI_gadgetBuilder.gadget(SafeDIMockScope_Gadget.gadget_Values(gizmo: gizmo, store: store, settingsBuilder: settingsBuilder))
			        return Screen(settingsBuilder: settingsBuilder, store: store, gizmo: gizmo_Source, gadget: gadget)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_C265A3DD6FF425C2 {}
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "alias bound apart, then a hole beneath a type, public caller",
			files: [
				"""
				public protocol Source {}
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, store: Store, gizmo: any Source, panel: Panel) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Received public let store: Store
				    @Received(fulfilledByDependencyNamed: "store", ofType: Store.self) public let gizmo: any Source
				    @Instantiated public let panel: Panel
				}
				@Instantiable
				public final class Panel: Instantiable {
				    public init(gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Store: Instantiable, Source {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				public final class Widget: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct panel_Values {
			            public let gizmo: Instantiator<Widget>
			            public let store: Store
			            public let settingsBuilder: Instantiator<Settings>
			        }

			        nonisolated public enum Panel_Scope {
			            nonisolated public struct gadget_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let panel: (panel_Values) -> SafeDIMockScope_Gadget.Panel_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(panel: @escaping (panel_Values) -> SafeDIMockScope_Gadget.Panel_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.panel = panel
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(panel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            store: (() -> Store)? = nil,
			            panel: ((Gadget) -> Panel)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                store: store,
			                panel: panel,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var store: (() -> Store)? { __safeDI_storage.store }
			        public var panel: ((Gadget) -> Panel)? { __safeDI_storage.panel }
			        public var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                store: (() -> Store)?,
			                panel: ((Gadget) -> Panel)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.store = store
			                self.panel = panel
			                self.settingsBuilder = settingsBuilder
			            }

			            let store: (() -> Store)?
			            let panel: ((Gadget) -> Panel)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    public static func mock(
			        gizmo: Instantiator<Widget>,
			        gadgetBuilder: @escaping () -> Gadget,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        store: Store? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gizmo: gizmo, gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), settingsBuilder: settingsBuilder, store: store, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gizmo: Instantiator<Widget>,
			        gadgetBuilder __safeDI_gadgetBuilder: Screen.SafeDIMockScope_Gadget.__safeDI_Builder<Gadget>,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        store: Store? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let store = if let store { store } else if let safeDIBuilder = safeDIOverrides.store { safeDIBuilder() } else { Store() }
			        let gizmo_Source: any Source = store // Declared as Screen.gizmo
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { Instantiator<Settings>(__safeDI_settingsBuilder) }
			        let __safeDI_gadgetBuilder_panel = __safeDI_gadgetBuilder.panel(SafeDIMockScope_Gadget.panel_Values(gizmo: gizmo, store: store, settingsBuilder: settingsBuilder))
			        func __safeDI_panel() -> Panel {
			            let gadget: Gadget = __safeDI_gadgetBuilder_panel.gadget(SafeDIMockScope_Gadget.Panel_Scope.gadget_Values())
			            return if let safeDIBuilder = safeDIOverrides.panel { safeDIBuilder(gadget) } else { Panel(gadget: gadget) }
			        }
			        let panel: Panel = __safeDI_panel()
			        return Screen(settingsBuilder: settingsBuilder, store: store, gizmo: gizmo_Source, panel: panel)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_4B2A6C55493EEA0D {}
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "alias bound apart beside a built receive, then a hole, public caller",
			files: [
				"""
				public protocol Source {}
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, store: Store, gizmo: any Source, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Received public let store: Store
				    @Received(fulfilledByDependencyNamed: "store", ofType: Store.self) public let gizmo: any Source
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Store: Instantiable, Source {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct gadget_Values {
			            public let store: Store
			            public let settingsBuilder: Instantiator<Settings>
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gadget: (gadget_Values) -> __safeDI_Built

			            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                self.gadget = gadget
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(gadget: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            store: (() -> Store)? = nil,
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                store: store,
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var store: (() -> Store)? { __safeDI_storage.store }
			        public var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        public var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                store: (() -> Store)?,
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.store = store
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let store: (() -> Store)?
			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    public static func mock(
			        gadgetBuilder: @escaping () -> Gadget,
			        gizmo: Instantiator<Widget>? = nil,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        store: Store? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), gizmo: gizmo, settingsBuilder: settingsBuilder, store: store, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Screen.SafeDIMockScope_Gadget.__safeDI_Builder<Gadget>,
			        gizmo: Instantiator<Widget>? = nil,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        store: Store? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let store = if let store { store } else if let safeDIBuilder = safeDIOverrides.store { safeDIBuilder() } else { Store() }
			        let gizmo_Source: any Source = store // Declared as Screen.gizmo
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = if let gizmo { gizmo } else { Instantiator<Widget>(__safeDI_gizmo) }
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { Instantiator<Settings>(__safeDI_settingsBuilder) }
			        let gadget: Gadget = __safeDI_gadgetBuilder.gadget(SafeDIMockScope_Gadget.gadget_Values(store: store, settingsBuilder: settingsBuilder))
			        return Screen(settingsBuilder: settingsBuilder, store: store, gizmo: gizmo_Source, gadget: gadget)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_7489B2BB1840B923 {}
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "alias not bound apart, then a hole, public caller",
			files: [
				"""
				public protocol Source {}
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, store: Store, gizmo: any Source, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Received public let store: Store
				    @Received(fulfilledByDependencyNamed: "store", ofType: Store.self) public let gizmo: any Source
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Store: Instantiable, Source {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(widget: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let widget: Instantiator<Widget>
				}
				public final class Widget: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct gadget_Values {
			            public let widget: Instantiator<Widget>
			            public let store: Store
			            public let gizmo: any Source
			            public let settingsBuilder: Instantiator<Settings>
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gadget: (gadget_Values) -> __safeDI_Built

			            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                self.gadget = gadget
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(gadget: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            store: (() -> Store)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                store: store,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var store: (() -> Store)? { __safeDI_storage.store }
			        public var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                store: (() -> Store)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.store = store
			                self.settingsBuilder = settingsBuilder
			            }

			            let store: (() -> Store)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    public static func mock(
			        widget: Instantiator<Widget>,
			        gadgetBuilder: @escaping () -> Gadget,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        store: Store? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(widget: widget, gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), settingsBuilder: settingsBuilder, store: store, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        widget: Instantiator<Widget>,
			        gadgetBuilder __safeDI_gadgetBuilder: Screen.SafeDIMockScope_Gadget.__safeDI_Builder<Gadget>,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        store: Store? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let store = if let store { store } else if let safeDIBuilder = safeDIOverrides.store { safeDIBuilder() } else { Store() }
			        let gizmo: any Source = store // Declared as Screen.gizmo
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(widget) } else { Settings(widget: widget) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { Instantiator<Settings>(__safeDI_settingsBuilder) }
			        let gadget: Gadget = __safeDI_gadgetBuilder.gadget(SafeDIMockScope_Gadget.gadget_Values(widget: widget, store: store, gizmo: gizmo, settingsBuilder: settingsBuilder))
			        return Screen(settingsBuilder: settingsBuilder, store: store, gizmo: gizmo, gadget: gadget)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_55452EDAF35997AA {}
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "alias bound apart, then a hole, internal caller",
			files: [
				"""
				public protocol Source {}
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, store: Store, gizmo: any Source, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Received public let store: Store
				    @Received(fulfilledByDependencyNamed: "store", ofType: Store.self) public let gizmo: any Source
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Store: Instantiable, Source {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }


				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				public final class Widget: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            store: (() -> Store)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                store: store,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var store: (() -> Store)? { __safeDI_storage.store }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                store: (() -> Store)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.store = store
			                self.settingsBuilder = settingsBuilder
			            }

			            let store: (() -> Store)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gizmo: Instantiator<Widget>,
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let store = if let safeDIBuilder = safeDIOverrides.store { safeDIBuilder() } else { Store() }
			        let gizmo_Source: any Source = store // Declared as Screen.gizmo
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, store: store, gizmo: gizmo_Source, gadget: gadget)
			    }
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "built child named apart, then a hole, public caller",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Gizmo, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let settingsBuilder: Instantiator<Settings>
				    @Instantiated let gizmo: Gizmo
				    @Instantiated let gadget: Gadget
				}

				@Instantiable
				public final class Gizmo: Instantiable {
				    public init() {}
				}

				public final class Gadget: Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class Widget: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let gizmo: Instantiator<Widget>
				}
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct gadget_Values {
			            public let settingsBuilder: Instantiator<Settings>
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gadget: (gadget_Values) -> __safeDI_Built

			            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                self.gadget = gadget
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(gadget: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            gizmo_Gizmo: (() -> Gizmo)? = nil,
			            gizmo_Widget: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo_Gizmo: gizmo_Gizmo,
			                gizmo_Widget: gizmo_Widget,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var gizmo_Gizmo: (() -> Gizmo)? { __safeDI_storage.gizmo_Gizmo }
			        public var gizmo_Widget: (() -> Widget)? { __safeDI_storage.gizmo_Widget }
			        public var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo_Gizmo: (() -> Gizmo)?,
			                gizmo_Widget: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.gizmo_Gizmo = gizmo_Gizmo
			                self.gizmo_Widget = gizmo_Widget
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo_Gizmo: (() -> Gizmo)?
			            let gizmo_Widget: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    public static func mock(
			        gadgetBuilder: @escaping () -> Gadget,
			        gizmo_Widget: Instantiator<Widget>? = nil,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), gizmo_Widget: gizmo_Widget, settingsBuilder: settingsBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Screen.SafeDIMockScope_Gadget.__safeDI_Builder<Gadget>,
			        gizmo_Widget: Instantiator<Widget>? = nil,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let gizmo_Gizmo = if let safeDIBuilder = safeDIOverrides.gizmo_Gizmo { safeDIBuilder() } else { Gizmo() }
			        func __safeDI_gizmo_Widget() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo_Widget { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo_Widget = if let gizmo_Widget { gizmo_Widget } else { Instantiator<Widget>(__safeDI_gizmo_Widget) }
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { Instantiator<Settings>(__safeDI_settingsBuilder) }
			        let gadget: Gadget = __safeDI_gadgetBuilder.gadget(SafeDIMockScope_Gadget.gadget_Values(settingsBuilder: settingsBuilder))
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_Gizmo, gadget: gadget)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_2139E833CD1129F0 {}
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "built child named apart, then a hole, internal caller",
			files: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Gizmo, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let settingsBuilder: Instantiator<Settings>
				    @Instantiated let gizmo: Gizmo
				    @Instantiated let gadget: Gadget
				}

				@Instantiable
				public final class Gizmo: Instantiable {
				    public init() {}
				}

				public final class Gadget: Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class Widget: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let gizmo: Instantiator<Widget>
				}
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo_Gizmo: (() -> Gizmo)? = nil,
			            gizmo_Widget: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo_Gizmo: gizmo_Gizmo,
			                gizmo_Widget: gizmo_Widget,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var gizmo_Gizmo: (() -> Gizmo)? { __safeDI_storage.gizmo_Gizmo }
			        var gizmo_Widget: (() -> Widget)? { __safeDI_storage.gizmo_Widget }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo_Gizmo: (() -> Gizmo)?,
			                gizmo_Widget: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.gizmo_Gizmo = gizmo_Gizmo
			                self.gizmo_Widget = gizmo_Widget
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo_Gizmo: (() -> Gizmo)?
			            let gizmo_Widget: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let gizmo_Gizmo = if let safeDIBuilder = safeDIOverrides.gizmo_Gizmo { safeDIBuilder() } else { Gizmo() }
			        func __safeDI_gizmo_Widget() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo_Widget { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo_Widget = Instantiator<Widget>(__safeDI_gizmo_Widget)
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_Gizmo, gadget: gadget)
			    }
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "receive passed by name, then a hole, public caller",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Instantiator<Widget>, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let settingsBuilder: Instantiator<Settings>
				    @Received let gizmo: Instantiator<Widget>
				    @Instantiated let gadget: Gadget
				}

				public final class Gadget: Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class Widget: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let gizmo: Instantiator<Widget>
				}
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct gadget_Values {
			            public let gizmo: Instantiator<Widget>
			            public let settingsBuilder: Instantiator<Settings>
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gadget: (gadget_Values) -> __safeDI_Built

			            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                self.gadget = gadget
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(gadget: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        public var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    public static func mock(
			        gadgetBuilder: @escaping () -> Gadget,
			        gizmo: Instantiator<Widget>? = nil,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), gizmo: gizmo, settingsBuilder: settingsBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Screen.SafeDIMockScope_Gadget.__safeDI_Builder<Gadget>,
			        gizmo: Instantiator<Widget>? = nil,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = if let gizmo { gizmo } else { Instantiator<Widget>(__safeDI_gizmo) }
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { Instantiator<Settings>(__safeDI_settingsBuilder) }
			        let gadget: Gadget = __safeDI_gadgetBuilder.gadget(SafeDIMockScope_Gadget.gadget_Values(gizmo: gizmo, settingsBuilder: settingsBuilder))
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo, gadget: gadget)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_9DBAFBBE07B1E7FC {}
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "receive passed by name, then a hole, internal caller",
			files: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Instantiator<Widget>, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let settingsBuilder: Instantiator<Settings>
				    @Received let gizmo: Instantiator<Widget>
				    @Instantiated let gadget: Gadget
				}

				public final class Gadget: Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class Widget: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let gizmo: Instantiator<Widget>
				}
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo: gizmo,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        var gizmo: (() -> Widget)? { __safeDI_storage.gizmo }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.gizmo = gizmo
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    static func mock(
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_gizmo() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo = Instantiator<Widget>(__safeDI_gizmo)
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo, gadget: gadget)
			    }
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "received constant named apart, then a hole, public caller",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Gizmo, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let settingsBuilder: Instantiator<Settings>
				    @Received let gizmo: Gizmo
				    @Instantiated let gadget: Gadget
				}

				@Instantiable
				public final class Gizmo: Instantiable {
				    public init() {}
				}

				public final class Gadget: Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class Widget: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let gizmo: Instantiator<Widget>
				}
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct gadget_Values {
			            public let settingsBuilder: Instantiator<Settings>
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gadget: (gadget_Values) -> __safeDI_Built

			            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                self.gadget = gadget
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(gadget: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            gizmo_Widget: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil,
			            gizmo_Gizmo: (() -> Gizmo)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo_Widget: gizmo_Widget,
			                settingsBuilder: settingsBuilder,
			                gizmo_Gizmo: gizmo_Gizmo
			            )
			        }

			        public var gizmo_Widget: (() -> Widget)? { __safeDI_storage.gizmo_Widget }
			        public var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }
			        public var gizmo_Gizmo: (() -> Gizmo)? { __safeDI_storage.gizmo_Gizmo }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo_Widget: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?,
			                gizmo_Gizmo: (() -> Gizmo)?
			            ) {
			                self.gizmo_Widget = gizmo_Widget
			                self.settingsBuilder = settingsBuilder
			                self.gizmo_Gizmo = gizmo_Gizmo
			            }

			            let gizmo_Widget: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            let gizmo_Gizmo: (() -> Gizmo)?
			        }
			    }

			    public static func mock(
			        gadgetBuilder: @escaping () -> Gadget,
			        gizmo_Gizmo: Gizmo? = nil,
			        gizmo_Widget: Instantiator<Widget>? = nil,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), gizmo_Gizmo: gizmo_Gizmo, gizmo_Widget: gizmo_Widget, settingsBuilder: settingsBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Screen.SafeDIMockScope_Gadget.__safeDI_Builder<Gadget>,
			        gizmo_Gizmo: Gizmo? = nil,
			        gizmo_Widget: Instantiator<Widget>? = nil,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_gizmo_Widget() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo_Widget { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo_Widget = if let gizmo_Widget { gizmo_Widget } else { Instantiator<Widget>(__safeDI_gizmo_Widget) }
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { Instantiator<Settings>(__safeDI_settingsBuilder) }
			        let gizmo_Gizmo = if let gizmo_Gizmo { gizmo_Gizmo } else if let safeDIBuilder = safeDIOverrides.gizmo_Gizmo { safeDIBuilder() } else { Gizmo() }
			        let gadget: Gadget = __safeDI_gadgetBuilder.gadget(SafeDIMockScope_Gadget.gadget_Values(settingsBuilder: settingsBuilder))
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_Gizmo, gadget: gadget)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_F0C458ECC944B14A {}
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "received constant named apart, then a hole, internal caller",
			files: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Gizmo, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let settingsBuilder: Instantiator<Settings>
				    @Received let gizmo: Gizmo
				    @Instantiated let gadget: Gadget
				}

				@Instantiable
				public final class Gizmo: Instantiable {
				    public init() {}
				}

				public final class Gadget: Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class Widget: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let gizmo: Instantiator<Widget>
				}
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo_Widget: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil,
			            gizmo_Gizmo: (() -> Gizmo)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo_Widget: gizmo_Widget,
			                settingsBuilder: settingsBuilder,
			                gizmo_Gizmo: gizmo_Gizmo
			            )
			        }

			        var gizmo_Widget: (() -> Widget)? { __safeDI_storage.gizmo_Widget }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }
			        var gizmo_Gizmo: (() -> Gizmo)? { __safeDI_storage.gizmo_Gizmo }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo_Widget: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?,
			                gizmo_Gizmo: (() -> Gizmo)?
			            ) {
			                self.gizmo_Widget = gizmo_Widget
			                self.settingsBuilder = settingsBuilder
			                self.gizmo_Gizmo = gizmo_Gizmo
			            }

			            let gizmo_Widget: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            let gizmo_Gizmo: (() -> Gizmo)?
			        }
			    }

			    static func mock(
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_gizmo_Widget() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo_Widget { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo_Widget = Instantiator<Widget>(__safeDI_gizmo_Widget)
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        let gizmo_Gizmo = if let safeDIBuilder = safeDIOverrides.gizmo_Gizmo { safeDIBuilder() } else { Gizmo() }
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_Gizmo, gadget: gadget)
			    }
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "received Instantiator named apart, then a hole, public caller",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Instantiator<Gizmo>, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let settingsBuilder: Instantiator<Settings>
				    @Received let gizmo: Instantiator<Gizmo>
				    @Instantiated let gadget: Gadget
				}

				@Instantiable
				public final class Gizmo: Instantiable {
				    public init() {}
				}

				public final class Gadget: Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class Widget: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let gizmo: Instantiator<Widget>
				}
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct gadget_Values {
			            public let settingsBuilder: Instantiator<Settings>
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gadget: (gadget_Values) -> __safeDI_Built

			            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                self.gadget = gadget
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(gadget: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            gizmo_Widget: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil,
			            gizmo_Gizmo: (() -> Gizmo)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo_Widget: gizmo_Widget,
			                settingsBuilder: settingsBuilder,
			                gizmo_Gizmo: gizmo_Gizmo
			            )
			        }

			        public var gizmo_Widget: (() -> Widget)? { __safeDI_storage.gizmo_Widget }
			        public var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }
			        public var gizmo_Gizmo: (() -> Gizmo)? { __safeDI_storage.gizmo_Gizmo }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo_Widget: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?,
			                gizmo_Gizmo: (() -> Gizmo)?
			            ) {
			                self.gizmo_Widget = gizmo_Widget
			                self.settingsBuilder = settingsBuilder
			                self.gizmo_Gizmo = gizmo_Gizmo
			            }

			            let gizmo_Widget: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            let gizmo_Gizmo: (() -> Gizmo)?
			        }
			    }

			    public static func mock(
			        gadgetBuilder: @escaping () -> Gadget,
			        gizmo_Gizmo: Instantiator<Gizmo>? = nil,
			        gizmo_Widget: Instantiator<Widget>? = nil,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), gizmo_Gizmo: gizmo_Gizmo, gizmo_Widget: gizmo_Widget, settingsBuilder: settingsBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Screen.SafeDIMockScope_Gadget.__safeDI_Builder<Gadget>,
			        gizmo_Gizmo: Instantiator<Gizmo>? = nil,
			        gizmo_Widget: Instantiator<Widget>? = nil,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_gizmo_Widget() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo_Widget { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo_Widget = if let gizmo_Widget { gizmo_Widget } else { Instantiator<Widget>(__safeDI_gizmo_Widget) }
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { Instantiator<Settings>(__safeDI_settingsBuilder) }
			        func __safeDI_gizmo_Gizmo() -> Gizmo {
			            if let safeDIBuilder = safeDIOverrides.gizmo_Gizmo { safeDIBuilder() } else { Gizmo() }
			        }
			        let gizmo_Gizmo = if let gizmo_Gizmo { gizmo_Gizmo } else { Instantiator<Gizmo>(__safeDI_gizmo_Gizmo) }
			        let gadget: Gadget = __safeDI_gadgetBuilder.gadget(SafeDIMockScope_Gadget.gadget_Values(settingsBuilder: settingsBuilder))
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_Gizmo, gadget: gadget)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_918F967355B26354 {}
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "received Instantiator named apart, then a hole, internal caller",
			files: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo: Instantiator<Gizmo>, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let settingsBuilder: Instantiator<Settings>
				    @Received let gizmo: Instantiator<Gizmo>
				    @Instantiated let gadget: Gadget
				}

				@Instantiable
				public final class Gizmo: Instantiable {
				    public init() {}
				}

				public final class Gadget: Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class Widget: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let gizmo: Instantiator<Widget>
				}
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gizmo_Widget: (() -> Widget)? = nil,
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil,
			            gizmo_Gizmo: (() -> Gizmo)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo_Widget: gizmo_Widget,
			                settingsBuilder: settingsBuilder,
			                gizmo_Gizmo: gizmo_Gizmo
			            )
			        }

			        var gizmo_Widget: (() -> Widget)? { __safeDI_storage.gizmo_Widget }
			        var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }
			        var gizmo_Gizmo: (() -> Gizmo)? { __safeDI_storage.gizmo_Gizmo }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo_Widget: (() -> Widget)?,
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?,
			                gizmo_Gizmo: (() -> Gizmo)?
			            ) {
			                self.gizmo_Widget = gizmo_Widget
			                self.settingsBuilder = settingsBuilder
			                self.gizmo_Gizmo = gizmo_Gizmo
			            }

			            let gizmo_Widget: (() -> Widget)?
			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            let gizmo_Gizmo: (() -> Gizmo)?
			        }
			    }

			    static func mock(
			        gadget: Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_gizmo_Widget() -> Widget {
			            if let safeDIBuilder = safeDIOverrides.gizmo_Widget { safeDIBuilder() } else { Widget() }
			        }
			        let gizmo_Widget = Instantiator<Widget>(__safeDI_gizmo_Widget)
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        func __safeDI_gizmo_Gizmo() -> Gizmo {
			            if let safeDIBuilder = safeDIOverrides.gizmo_Gizmo { safeDIBuilder() } else { Gizmo() }
			        }
			        let gizmo_Gizmo = Instantiator<Gizmo>(__safeDI_gizmo_Gizmo)
			        return Screen(settingsBuilder: settingsBuilder, gizmo: gizmo_Gizmo, gadget: gadget)
			    }
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "forwarded label, then a hole, public caller",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(gizmo: Gizmo, settingsBuilder: Instantiator<Settings>, gadget: Gadget) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Forwarded public let gizmo: Gizmo
				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gadget: Gadget
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Instantiator<Widget>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Instantiator<Widget>
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Widget: Instantiable { public init() {} }
				public final class Gadget: Instantiable { public init() {} }
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct gadget_Values {
			            public let gizmo: Gizmo
			            public let settingsBuilder: Instantiator<Settings>
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gadget: (gadget_Values) -> __safeDI_Built

			            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                self.gadget = gadget
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(gadget: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            settingsBuilder: ((Instantiator<Widget>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var settingsBuilder: ((Instantiator<Widget>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: ((Instantiator<Widget>) -> Settings)?
			        }
			    }

			    public static func mock(
			        gizmo: Gizmo,
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gadgetBuilder: @escaping () -> Gadget,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gizmo: gizmo, gizmo_Instantiator__Widget: gizmo_Instantiator__Widget, gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), settingsBuilder: settingsBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gizmo: Gizmo,
			        gizmo_Instantiator__Widget: Instantiator<Widget>,
			        gadgetBuilder __safeDI_gadgetBuilder: Screen.SafeDIMockScope_Gadget.__safeDI_Builder<Gadget>,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Instantiator<Widget> = gizmo_Instantiator__Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { Instantiator<Settings>(__safeDI_settingsBuilder) }
			        let gadget: Gadget = __safeDI_gadgetBuilder.gadget(SafeDIMockScope_Gadget.gadget_Values(gizmo: gizmo, settingsBuilder: settingsBuilder))
			        return Screen(gizmo: gizmo, settingsBuilder: settingsBuilder, gadget: gadget)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_E8B098CD58C7D48E {}
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "hole labeled as a sibling SafeDI names apart, renamed by the remedy, public caller",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, screenGizmo: Gizmo) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let screenGizmo: Gizmo
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Widget, prefs: Prefs) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Widget
				    @Received public let prefs: Prefs
				}
				@Instantiable
				public final class Prefs: Instantiable {
				    public init(gizmo: Knob) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Knob
				}
				@Instantiable
				public final class Widget: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }
				}
				@Instantiable
				public final class Knob: Instantiable {
				    public init() {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }
				}
				public final class Gizmo: Instantiable { public init() {} }
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gizmo {
			        nonisolated public struct screenGizmo_Values {
			            public let prefs: Prefs
			            public let settingsBuilder: Instantiator<Settings>
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
			            gizmo_Widget: (() -> Widget)? = nil,
			            gizmo_Knob: (() -> Knob)? = nil,
			            prefs: ((Knob) -> Prefs)? = nil,
			            settingsBuilder: ((Widget, Prefs) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                gizmo_Widget: gizmo_Widget,
			                gizmo_Knob: gizmo_Knob,
			                prefs: prefs,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var gizmo_Widget: (() -> Widget)? { __safeDI_storage.gizmo_Widget }
			        public var gizmo_Knob: (() -> Knob)? { __safeDI_storage.gizmo_Knob }
			        public var prefs: ((Knob) -> Prefs)? { __safeDI_storage.prefs }
			        public var settingsBuilder: ((Widget, Prefs) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                gizmo_Widget: (() -> Widget)?,
			                gizmo_Knob: (() -> Knob)?,
			                prefs: ((Knob) -> Prefs)?,
			                settingsBuilder: ((Widget, Prefs) -> Settings)?
			            ) {
			                self.gizmo_Widget = gizmo_Widget
			                self.gizmo_Knob = gizmo_Knob
			                self.prefs = prefs
			                self.settingsBuilder = settingsBuilder
			            }

			            let gizmo_Widget: (() -> Widget)?
			            let gizmo_Knob: (() -> Knob)?
			            let prefs: ((Knob) -> Prefs)?
			            let settingsBuilder: ((Widget, Prefs) -> Settings)?
			        }
			    }

			    public static func mock(
			        gizmoBuilder: @escaping () -> Gizmo,
			        gizmo_Knob: Knob? = nil,
			        gizmo_Widget: Widget? = nil,
			        prefs: Prefs? = nil,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gizmoBuilder: .init(__safeDI_noScope: gizmoBuilder), gizmo_Knob: gizmo_Knob, gizmo_Widget: gizmo_Widget, prefs: prefs, settingsBuilder: settingsBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gizmoBuilder __safeDI_gizmoBuilder: Screen.SafeDIMockScope_Gizmo.__safeDI_Builder<Gizmo>,
			        gizmo_Knob: Knob? = nil,
			        gizmo_Widget: Widget? = nil,
			        prefs: Prefs? = nil,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let gizmo_Widget = if let gizmo_Widget { gizmo_Widget } else if let safeDIBuilder = safeDIOverrides.gizmo_Widget { safeDIBuilder() } else { Widget() }
			        let gizmo_Knob = if let gizmo_Knob { gizmo_Knob } else if let safeDIBuilder = safeDIOverrides.gizmo_Knob { safeDIBuilder() } else { Knob() }
			        func __safeDI_prefs() -> Prefs {
			            let gizmo: Knob = gizmo_Knob
			            return if let safeDIBuilder = safeDIOverrides.prefs { safeDIBuilder(gizmo) } else { Prefs(gizmo: gizmo) }
			        }
			        let prefs: Prefs = if let prefs { prefs } else { __safeDI_prefs() }
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Widget = gizmo_Widget
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo, prefs) } else { Settings(gizmo: gizmo, prefs: prefs) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { Instantiator<Settings>(__safeDI_settingsBuilder) }
			        let screenGizmo: Gizmo = __safeDI_gizmoBuilder.screenGizmo(SafeDIMockScope_Gizmo.screenGizmo_Values(prefs: prefs, settingsBuilder: settingsBuilder))
			        return Screen(settingsBuilder: settingsBuilder, screenGizmo: screenGizmo)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_E0D64BFAD6AFB10C {}
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "hole labeled as a parameter SafeDI names apart, renamed by the remedy, public caller",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, screenGizmo: Gizmo) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let screenGizmo: Gizmo
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: Other, prefs: Prefs) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Other
				    @Received public let prefs: Prefs
				}
				@Instantiable
				public final class Prefs: Instantiable {
				    public init(gizmo: Another) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: Another
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Other: Instantiable { public init() {} }
				public final class Another: Instantiable { public init() {} }
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gizmo {
			        nonisolated public struct screenGizmo_Values {
			            public let prefs: Prefs
			            public let settingsBuilder: Instantiator<Settings>
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
			            prefs: ((Another) -> Prefs)? = nil,
			            settingsBuilder: ((Other, Prefs) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                prefs: prefs,
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var prefs: ((Another) -> Prefs)? { __safeDI_storage.prefs }
			        public var settingsBuilder: ((Other, Prefs) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                prefs: ((Another) -> Prefs)?,
			                settingsBuilder: ((Other, Prefs) -> Settings)?
			            ) {
			                self.prefs = prefs
			                self.settingsBuilder = settingsBuilder
			            }

			            let prefs: ((Another) -> Prefs)?
			            let settingsBuilder: ((Other, Prefs) -> Settings)?
			        }
			    }

			    public static func mock(
			        gizmo_Another: Another,
			        gizmo_Other: Other,
			        gizmoBuilder: @escaping () -> Gizmo,
			        prefs: Prefs? = nil,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gizmo_Another: gizmo_Another, gizmo_Other: gizmo_Other, gizmoBuilder: .init(__safeDI_noScope: gizmoBuilder), prefs: prefs, settingsBuilder: settingsBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gizmo_Another: Another,
			        gizmo_Other: Other,
			        gizmoBuilder __safeDI_gizmoBuilder: Screen.SafeDIMockScope_Gizmo.__safeDI_Builder<Gizmo>,
			        prefs: Prefs? = nil,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_prefs() -> Prefs {
			            let gizmo: Another = gizmo_Another
			            return if let safeDIBuilder = safeDIOverrides.prefs { safeDIBuilder(gizmo) } else { Prefs(gizmo: gizmo) }
			        }
			        let prefs: Prefs = if let prefs { prefs } else { __safeDI_prefs() }
			        func __safeDI_settingsBuilder() -> Settings {
			            let gizmo: Other = gizmo_Other
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo, prefs) } else { Settings(gizmo: gizmo, prefs: prefs) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { Instantiator<Settings>(__safeDI_settingsBuilder) }
			        let screenGizmo: Gizmo = __safeDI_gizmoBuilder.screenGizmo(SafeDIMockScope_Gizmo.screenGizmo_Values(prefs: prefs, settingsBuilder: settingsBuilder))
			        return Screen(settingsBuilder: settingsBuilder, screenGizmo: screenGizmo)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_3E18B53C797BB09C {}
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "hole labeled as the wrapper an internal mock binds for a LazilyInstantiated, public caller",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, gizmo_lazilyInstantiated: Gizmo) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let gizmo_lazilyInstantiated: Gizmo
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: LazilyInstantiated<Other>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: LazilyInstantiated<Other>
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Other: Instantiable { public init() {} }
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gizmo {
			        nonisolated public struct gizmo_lazilyInstantiated_Values {
			            public let gizmo: LazilyInstantiated<Other>
			            public let settingsBuilder: Instantiator<Settings>
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gizmo_lazilyInstantiated: (gizmo_lazilyInstantiated_Values) -> __safeDI_Built

			            public init(gizmo_lazilyInstantiated: @escaping (gizmo_lazilyInstantiated_Values) -> __safeDI_Built) {
			                self.gizmo_lazilyInstantiated = gizmo_lazilyInstantiated
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(gizmo_lazilyInstantiated: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            settingsBuilder: ((LazilyInstantiated<Other>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var settingsBuilder: ((LazilyInstantiated<Other>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: ((LazilyInstantiated<Other>) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: ((LazilyInstantiated<Other>) -> Settings)?
			        }
			    }

			    public static func mock(
			        gizmo: LazilyInstantiated<Other>,
			        gizmoBuilder: @escaping () -> Gizmo,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gizmo: gizmo, gizmoBuilder: .init(__safeDI_noScope: gizmoBuilder), settingsBuilder: settingsBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gizmo: LazilyInstantiated<Other>,
			        gizmoBuilder __safeDI_gizmoBuilder: Screen.SafeDIMockScope_Gizmo.__safeDI_Builder<Gizmo>,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { Instantiator<Settings>(__safeDI_settingsBuilder) }
			        let gizmo_lazilyInstantiated: Gizmo = __safeDI_gizmoBuilder.gizmo_lazilyInstantiated(SafeDIMockScope_Gizmo.gizmo_lazilyInstantiated_Values(gizmo: gizmo, settingsBuilder: settingsBuilder))
			        return Screen(settingsBuilder: settingsBuilder, gizmo_lazilyInstantiated: gizmo_lazilyInstantiated)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_1D287D3DFAAEF65A {}
			}
			#endif
			""",
		),
		HoleBoundApartControl(
			testDescription: "hole labeled as a LazilyInstantiated SafeDI wraps, renamed by the remedy, public caller",
			files: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(settingsBuilder: Instantiator<Settings>, screenGizmo: Gizmo) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let settingsBuilder: Instantiator<Settings>
				    @Instantiated public let screenGizmo: Gizmo
				}
				@Instantiable
				public final class Settings: Instantiable {
				    public init(gizmo: LazilyInstantiated<Other>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received public let gizmo: LazilyInstantiated<Other>
				}
				public final class Gizmo: Instantiable { public init() {} }
				public final class Other: Instantiable { public init() {} }
				""",
			],
			mock: """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gizmo {
			        nonisolated public struct screenGizmo_Values {
			            public let gizmo: LazilyInstantiated<Other>
			            public let settingsBuilder: Instantiator<Settings>
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
			            settingsBuilder: ((LazilyInstantiated<Other>) -> Settings)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                settingsBuilder: settingsBuilder
			            )
			        }

			        public var settingsBuilder: ((LazilyInstantiated<Other>) -> Settings)? { __safeDI_storage.settingsBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                settingsBuilder: ((LazilyInstantiated<Other>) -> Settings)?
			            ) {
			                self.settingsBuilder = settingsBuilder
			            }

			            let settingsBuilder: ((LazilyInstantiated<Other>) -> Settings)?
			        }
			    }

			    public static func mock(
			        gizmo: LazilyInstantiated<Other>,
			        gizmoBuilder: @escaping () -> Gizmo,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gizmo: gizmo, gizmoBuilder: .init(__safeDI_noScope: gizmoBuilder), settingsBuilder: settingsBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gizmo: LazilyInstantiated<Other>,
			        gizmoBuilder __safeDI_gizmoBuilder: Screen.SafeDIMockScope_Gizmo.__safeDI_Builder<Gizmo>,
			        settingsBuilder: Instantiator<Settings>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_settingsBuilder() -> Settings {
			            if let safeDIBuilder = safeDIOverrides.settingsBuilder { safeDIBuilder(gizmo) } else { Settings(gizmo: gizmo) }
			        }
			        let settingsBuilder = if let settingsBuilder { settingsBuilder } else { Instantiator<Settings>(__safeDI_settingsBuilder) }
			        let screenGizmo: Gizmo = __safeDI_gizmoBuilder.screenGizmo(SafeDIMockScope_Gizmo.screenGizmo_Values(gizmo: gizmo, settingsBuilder: settingsBuilder))
			        return Screen(settingsBuilder: settingsBuilder, screenGizmo: screenGizmo)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_C377E34C7B6C9636 {}
			}
			#endif
			""",
		),
	]
}
