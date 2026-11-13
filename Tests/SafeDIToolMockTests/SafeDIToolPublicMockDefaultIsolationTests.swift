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

/// A module whose declarations default to the main actor (`-default-isolation MainActor`, which SwiftPM's
/// `defaultIsolation(MainActor.self)` and a new Xcode 26 app target set) puts a declaration on the main actor unless
/// something makes it nonisolated. An `@Instantiable` type is nonisolated there, since `Instantiable` refines
/// `SendableMetatype`, and so is every declaration in its extensions: its `mock()` and its `SafeDIOverrides`. A public
/// mock's module-level configuration is declared at file scope, so only its `nonisolated` keeps it off the main actor,
/// where neither the nonisolated `SafeDIOverrides` initializer's default nor the nonisolated `mock()` could reach it. A
/// public mock's `SafeDIOverrides` is nested in the mocked type, which is on the main actor when it says so, and a
/// configuration in another module holds it with a nonisolated default, so it is declared `nonisolated` too.
struct SafeDIToolPublicMockDefaultIsolationTests: ~Copyable {
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

	@Test(arguments: MultiModuleIntegration.allCases, DefaultIsolationCase.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_publicMockCompilesForCallerInAnotherPackage_whenEitherModuleDefaultsToMainActor(
		integration: MultiModuleIntegration,
		isolation: DefaultIsolationCase,
	) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Core",
					packageName: "pkg",
					swiftFileContentByFilePath: ["Screen.swift": Self.screen],
					compilerSettings: isolation.declaringModuleSettings,
				),
				ModuleFixture(
					name: "App",
					packageName: "app",
					swiftFileContentByFilePath: ["Caller.swift": Self.screenCaller],
					dependencies: ["Core"],
					compilerSettings: isolation.callingModuleSettings,
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Core"]?.generatedFiles == Self.screenFiles(integration: integration))
	}

	@Test(arguments: DefaultIsolationCase.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_publicMockCompiles_whenItsTreeBuildsAnotherModulesTypesAndEitherModuleDefaultsToMainActor(isolation: DefaultIsolationCase) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Core",
					packageName: "pkg",
					swiftFileContentByFilePath: ["Screen.swift": Self.screen],
					compilerSettings: isolation.declaringModuleSettings,
				),
				ModuleFixture(
					name: "App",
					packageName: "app",
					swiftFileContentByFilePath: ["Home.swift": Self.home],
					dependencies: ["Core"],
					compilerSettings: isolation.callingModuleSettings,
				),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.homeFile])
	}

	@Test(arguments: DefaultIsolationCase.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_publicMockCompiles_whenItsConfigurationHoldsOverridesOfMainActorPublicMockAndEitherModuleDefaultsToMainActor(isolation: DefaultIsolationCase) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Core",
					packageName: "pkg",
					swiftFileContentByFilePath: ["Card.swift": Self.card],
					compilerSettings: isolation.declaringModuleSettings,
				),
				ModuleFixture(
					name: "App",
					packageName: "app",
					swiftFileContentByFilePath: ["Page.swift": Self.page],
					dependencies: ["Core"],
					compilerSettings: isolation.callingModuleSettings,
				),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": Self.cardFile])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.pageFile])
	}

	// MARK: Isolation cases

	/// The isolation each of the two modules' declarations default to: the main actor, or none.
	struct DefaultIsolationCase: CustomTestStringConvertible, Sendable {
		static let allCases = [
			DefaultIsolationCase(declaringModuleIsMainActorByDefault: true, callingModuleIsMainActorByDefault: true),
			DefaultIsolationCase(declaringModuleIsMainActorByDefault: true, callingModuleIsMainActorByDefault: false),
			DefaultIsolationCase(declaringModuleIsMainActorByDefault: false, callingModuleIsMainActorByDefault: true),
			DefaultIsolationCase(declaringModuleIsMainActorByDefault: false, callingModuleIsMainActorByDefault: false),
		]

		let declaringModuleIsMainActorByDefault: Bool
		let callingModuleIsMainActorByDefault: Bool

		var declaringModuleSettings: VerificationCompilerSettings {
			VerificationCompilerSettings(defaultIsolation: declaringModuleIsMainActorByDefault ? "MainActor" : nil, prependsSafeDIImport: false)
		}

		var callingModuleSettings: VerificationCompilerSettings {
			VerificationCompilerSettings(defaultIsolation: callingModuleIsMainActorByDefault ? "MainActor" : nil, prependsSafeDIImport: false)
		}

		var testDescription: String {
			"Core \(declaringModuleIsMainActorByDefault ? "on the main actor" : "nonisolated") by default, App \(callingModuleIsMainActorByDefault ? "on the main actor" : "nonisolated") by default"
		}
	}

	// MARK: Fixtures

	private static let screen = """
	import SafeDI

	@Instantiable
	public final class Service: Instantiable {
	    public init(name: String = "service") {
	        self.name = name
	    }

	    public let name: String
	}

	@Instantiable
	public final class Leaf: Instantiable {
	    public init(service: Service) {
	        self.service = service
	    }

	    @Received let service: Service
	}

	@Instantiable(generateMock: .public)
	public final class Screen: Instantiable {
	    public init(service: Service, leaf: Leaf) {
	        self.service = service
	        self.leaf = leaf
	    }

	    @Instantiated let service: Service
	    @Instantiated let leaf: Leaf
	}
	"""

	/// Calls `Screen.mock()` from the main actor and, in a module that does not default to it, from outside any actor.
	private static let screenCaller = """
	import Core

	#if DEBUG
	@MainActor func makeScreenOnTheMainActor() -> Screen {
	    Screen.mock(safeDIOverrides: .init(service: .init(name: "custom")))
	}

	func makeScreen() -> Screen {
	    Screen.mock(safeDIOverrides: .init(service: .init(name: "custom")))
	}
	#endif
	"""

	private static func screenFiles(integration: MultiModuleIntegration) -> [String: String] {
		switch integration {
		case .moduleInfo:
			["Core.swift": screenCombinedFile]
		case .swiftPackagePlugin:
			["Screen+SafeDIMock.swift": screenMockFile, "SafeDIMockConfiguration.swift": screenConfigurationFile]
		}
	}

	private static let screenCombinedFile = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.

	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Screen {
	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            service: __safeDI_Core_Service_MockConfiguration = .init(),
	            leaf: ((Service) -> Leaf)? = nil
	        ) {
	            self.service = service
	            self.leaf = leaf
	        }

	        public private(set) var service: __safeDI_Core_Service_MockConfiguration
	        public private(set) var leaf: ((Service) -> Leaf)?
	    }

	    public static func mock(
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Screen {
	        func __safeDI_service() -> Service {
	            return Service.__safeDI_init(name: safeDIOverrides.service.name, safeDIBuilder: safeDIOverrides.service.safeDIBuilder)
	        }
	        let service: Service = __safeDI_service()
	        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(service) } else { Leaf(service: service) }
	        return Screen(service: service, leaf: leaf)
	    }
	}

	extension Screen {
	    public enum __safeDI_Screen_mock_51799E6AA5E7B634 {}
	}
	#endif

	#if DEBUG
	/// Configuration for how `Service` is constructed within the public mock trees of module `Core`.
	nonisolated public struct __safeDI_Core_Service_MockConfiguration {
	    public init(
	        name: String? = nil,
	        _ safeDIBuilder: ((String) -> Service)? = nil
	    ) {
	        self.name = name
	        self.safeDIBuilder = safeDIBuilder
	    }

	    /// `nil` keeps the default of `Service`'s `name`.
	    public private(set) var name: String?
	    /// Overrides how `Service` is constructed. Parameters match the type’s initializer or custom mock method.
	    public private(set) var safeDIBuilder: ((String) -> Service)?
	}

	extension Service {
	    static func __safeDI_init(name: String?, safeDIBuilder: ((String) -> Service)?) -> Service {
	        let name = name ?? ("service")
	        return if let safeDIBuilder { safeDIBuilder(name) } else { Service(name: name) }
	    }
	}
	#endif

	"""

	private static let screenMockFile = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.

	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Screen {
	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            service: __safeDI_Core_Service_MockConfiguration = .init(),
	            leaf: ((Service) -> Leaf)? = nil
	        ) {
	            self.service = service
	            self.leaf = leaf
	        }

	        public private(set) var service: __safeDI_Core_Service_MockConfiguration
	        public private(set) var leaf: ((Service) -> Leaf)?
	    }

	    public static func mock(
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Screen {
	        func __safeDI_service() -> Service {
	            return Service.__safeDI_init(name: safeDIOverrides.service.name, safeDIBuilder: safeDIOverrides.service.safeDIBuilder)
	        }
	        let service: Service = __safeDI_service()
	        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(service) } else { Leaf(service: service) }
	        return Screen(service: service, leaf: leaf)
	    }
	}

	extension Screen {
	    public enum __safeDI_Screen_mock_51799E6AA5E7B634 {}
	}
	#endif
	"""

	private static let screenConfigurationFile = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.

	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	/// Configuration for how `Service` is constructed within the public mock trees of module `Core`.
	nonisolated public struct __safeDI_Core_Service_MockConfiguration {
	    public init(
	        name: String? = nil,
	        _ safeDIBuilder: ((String) -> Service)? = nil
	    ) {
	        self.name = name
	        self.safeDIBuilder = safeDIBuilder
	    }

	    /// `nil` keeps the default of `Service`'s `name`.
	    public private(set) var name: String?
	    /// Overrides how `Service` is constructed. Parameters match the type’s initializer or custom mock method.
	    public private(set) var safeDIBuilder: ((String) -> Service)?
	}

	extension Service {
	    static func __safeDI_init(name: String?, safeDIBuilder: ((String) -> Service)?) -> Service {
	        let name = name ?? ("service")
	        return if let safeDIBuilder { safeDIBuilder(name) } else { Service(name: name) }
	    }
	}
	#endif

	"""

	private static let home = """
	import Core
	import SafeDI

	@Instantiable(generateMock: .public)
	public final class Home: Instantiable {
	    public init(screen: Screen, title: String = "home") {
	        self.screen = screen
	        self.title = title
	    }

	    @Instantiated let screen: Screen
	    let title: String
	}

	#if DEBUG
	@MainActor func makeHome() -> Home {
	    Home.mock(safeDIOverrides: .init(screen: .init(service: .init(name: "custom"))))
	}
	#endif
	"""

	private static let homeFile = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.

	#if canImport(Core)
	import Core
	#endif
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Home {
	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            screen: __safeDI_App_Screen_MockConfiguration = .init()
	        ) {
	            self.screen = screen
	        }

	        public private(set) var screen: __safeDI_App_Screen_MockConfiguration
	    }

	    public static func mock(
	        title: String? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Home {
	        let title = title ?? ("home")
	        func __safeDI_screen() -> Screen {
	            func __safeDI_service() -> Service {
	                return Service.__safeDI_init(name: safeDIOverrides.screen.service.name, safeDIBuilder: safeDIOverrides.screen.service.safeDIBuilder)
	            }
	            let service: Service = __safeDI_service()
	            let leaf = if let safeDIBuilder = safeDIOverrides.screen.leaf { safeDIBuilder(service) } else { Leaf(service: service) }
	            return Screen.__safeDI_init(service: service, leaf: leaf, safeDIBuilder: safeDIOverrides.screen.safeDIBuilder)
	        }
	        let screen: Screen = __safeDI_screen()
	        return Home(screen: screen, title: title)
	    }
	}

	extension Home {
	    public enum __safeDI_Home_mock_546AE63BE69A02EC {}
	}
	#endif

	#if DEBUG
	/// Configuration for how `Service` is constructed within the public mock trees of module `App`.
	nonisolated public struct __safeDI_App_Service_MockConfiguration {
	    public init(
	        name: String? = nil,
	        _ safeDIBuilder: ((String) -> Service)? = nil
	    ) {
	        self.name = name
	        self.safeDIBuilder = safeDIBuilder
	    }

	    /// `nil` keeps the default of `Service`'s `name`.
	    public private(set) var name: String?
	    /// Overrides how `Service` is constructed. Parameters match the type’s initializer or custom mock method.
	    public private(set) var safeDIBuilder: ((String) -> Service)?
	}

	extension Service {
	    static func __safeDI_init(name: String?, safeDIBuilder: ((String) -> Service)?) -> Service {
	        let name = name ?? ("service")
	        return if let safeDIBuilder { safeDIBuilder(name) } else { Service(name: name) }
	    }
	}

	/// Configuration for how `Screen` is constructed within the public mock trees of module `App`.
	nonisolated public struct __safeDI_App_Screen_MockConfiguration {
	    public init(
	        service: __safeDI_App_Service_MockConfiguration = .init(),
	        leaf: ((Service) -> Leaf)? = nil,
	        _ safeDIBuilder: ((Service, Leaf) -> Screen)? = nil
	    ) {
	        self.service = service
	        self.leaf = leaf
	        self.safeDIBuilder = safeDIBuilder
	    }

	    public private(set) var service: __safeDI_App_Service_MockConfiguration
	    public private(set) var leaf: ((Service) -> Leaf)?
	    /// Overrides how `Screen` is constructed. Parameters match the type’s initializer or custom mock method.
	    public private(set) var safeDIBuilder: ((Service, Leaf) -> Screen)?
	}

	extension Screen {
	    static func __safeDI_init(service: Service, leaf: Leaf, safeDIBuilder: ((Service, Leaf) -> Screen)?) -> Screen {
	        if let safeDIBuilder { safeDIBuilder(service, leaf) } else { Screen(service: service, leaf: leaf) }
	    }
	}
	#endif

	"""

	private static let card = """
	import SafeDI

	@Instantiable
	public final class Theme: Instantiable {
	    public init() {}
	}

	@Instantiable(generateMock: .public)
	@MainActor
	public final class Card: Instantiable {
	    package init(theme: Theme, title: String = "card") {
	        self.theme = theme
	        self.title = title
	    }

	    @Instantiated let theme: Theme
	    let title: String
	}
	"""

	private static let cardFile = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.

	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Card {
	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            theme: (() -> Theme)? = nil
	        ) {
	            self.theme = theme
	        }

	        public private(set) var theme: (() -> Theme)?
	    }

	    public static func mock(
	        title: String? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Card {
	        let title = title ?? ("card")
	        let theme = if let safeDIBuilder = safeDIOverrides.theme { safeDIBuilder() } else { Theme() }
	        return Card(theme: theme, title: title)
	    }
	}

	extension Card {
	    public enum __safeDI_Card_mock_546AE63BE69A02EC {}
	}
	#endif
	"""

	/// `Panel`'s configuration holds `Card`'s overrides, since `App` cannot construct `Card` and calls its public mock.
	private static let page = """
	import Core
	import SafeDI

	@Instantiable
	@MainActor
	public final class Panel: Instantiable {
	    public init(card: Card, name: String = "panel") {
	        self.card = card
	        self.name = name
	    }

	    @Instantiated let card: Card
	    let name: String
	}

	@Instantiable(generateMock: .public)
	@MainActor
	public final class Page: Instantiable {
	    public init(panel: Panel) {
	        self.panel = panel
	    }

	    @Instantiated let panel: Panel
	}

	#if DEBUG
	@MainActor func makePage() -> Page {
	    Page.mock(safeDIOverrides: .init(panel: .init(card: .init(theme: { Theme() }), name: "custom")))
	}
	#endif
	"""

	private static let pageFile = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.

	#if canImport(Core)
	import Core
	#endif
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Page {
	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            panel: __safeDI_App_Panel_MockConfiguration = .init()
	        ) {
	            self.panel = panel
	        }

	        public private(set) var panel: __safeDI_App_Panel_MockConfiguration
	    }

	    public static func mock(
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Page {
	        func __safeDI_panel() -> Panel {
	            _ = Card.__safeDI_Card_mock_546AE63BE69A02EC.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
	            let card = Card.mock(safeDIOverrides: safeDIOverrides.panel.card)
	            return Panel.__safeDI_init(card: card, name: safeDIOverrides.panel.name, safeDIBuilder: safeDIOverrides.panel.safeDIBuilder)
	        }
	        let panel: Panel = __safeDI_panel()
	        return Page(panel: panel)
	    }
	}

	extension Page {
	    public enum __safeDI_Page_mock_51799E6AA5E7B634 {}
	}
	#endif

	#if DEBUG
	/// Configuration for how `Panel` is constructed within the public mock trees of module `App`.
	nonisolated public struct __safeDI_App_Panel_MockConfiguration {
	    public init(
	        card: Card.SafeDIOverrides = .init(),
	        name: String? = nil,
	        _ safeDIBuilder: ((Card, String) -> Panel)? = nil
	    ) {
	        self.card = card
	        self.name = name
	        self.safeDIBuilder = safeDIBuilder
	    }

	    public private(set) var card: Card.SafeDIOverrides
	    /// `nil` keeps the default of `Panel`'s `name`.
	    public private(set) var name: String?
	    /// Overrides how `Panel` is constructed. Parameters match the type’s initializer or custom mock method.
	    public private(set) var safeDIBuilder: ((Card, String) -> Panel)?
	}

	extension Panel {
	    static func __safeDI_init(card: Card, name: String?, safeDIBuilder: ((Card, String) -> Panel)?) -> Panel {
	        let name = name ?? ("panel")
	        return if let safeDIBuilder { safeDIBuilder(card, name) } else { Panel(card: card, name: name) }
	    }
	}
	#endif

	"""

	private var filesToDelete: [URL]
}
