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
@testable import SafeDITool

/// A type no declaration SafeDI reads declares counts as `public` (decision 54): a framework's, a fetched package's, or
/// a first-party module's that does not run SafeDI. A type declared inside an extension counts exactly, at its own level
/// capped by the extended type's; one declared inside an `#if` block counts as `internal` unless a mention raises it; a
/// `typealias` is recorded as any plain declaration is. Without a target graph, the generated file names the types it
/// counts `public` that way in one comment.
struct SafeDIToolUnreadTypeAccessTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A: an unread type counts as `public` on a seam

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTier_whenSeamReceivesIt(integration: MultiModuleIntegration) async throws {
		// A1: `Kit` does not run SafeDI (under the plugin, it is a fetched package), so SafeDI reads no declaration of
		// `Window`, which counts as `public`; `App`, in another package, forwards it through a host.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(receives: ["@Received let window: Window"], hostForwards: ["window: Window"]),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Window"], tiers: """
		    public init(window: Window) {
		        let cache = Cache()
		        self.init(window: window, cache: cache)
		    }
		""", guardHash: "564C5E6539CF6AA0"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTier_whenTypeBeneathSeamReceivesIt(integration: MultiModuleIntegration) async throws {
		// A2: `Badge`, beneath the seam, receives `window`, a pass-through the public tier takes.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(receives: [], instantiates: ["@Instantiated let badge: Badge"], extraFeatureFiles: [
				"Badge.swift": "import Kit\n\n@Instantiable\nstruct Badge: Instantiable {\n    init(window: Window) {\n        self.window = window\n    }\n\n    @Received let window: Window\n}",
			], hostForwards: ["window: Window"]),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Window"], tiers: """
		    public init(window: Window) {
		        let badge = Badge(window: window)
		        let cache = Cache()
		        self.init(badge: badge, cache: cache)
		    }
		""", guardHash: "564C5E6539CF6AA0"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTier_whenSeamForwardsIt() async throws {
		// A3: a forwarded property of an unread type is the public tier's first parameter.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(receives: ["@Forwarded let image: Image", "@Received let window: Window"], hostForwards: nil),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Image", "Window"], tiers: """
		    public init(image: Image, window: Window) {
		        let cache = Cache()
		        self.init(image: image, window: window, cache: cache)
		    }
		""", guardHash: "883DBB4A829093BB"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTierAsOptionalParameter_whenSeamReceivesItOnlyIfAvailable() async throws {
		// A4: received only if available, the unread type is an optional parameter of the public tier, defaulting to `nil`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(receives: ["@Received(onlyIfAvailable: true) let window: Window?"], hostForwards: ["window: Window"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Window"], tiers: """
		    public init(window: Window? = nil) {
		        let cache = Cache()
		        self.init(window: window, cache: cache)
		    }
		""", guardHash: "39C26C2DBA820CDB"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTier_whenSeamReceivesErasedInstantiatorOfUnreadType() async throws {
		// A5: `ErasedInstantiator` is SafeDI's, which no comment names; `Window` is named.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(receives: ["@Received let windowBuilder: ErasedInstantiator<(), Window>"], hostForwards: ["windowBuilder: ErasedInstantiator<(), Window>"], featureImportsSafeDI: true),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Window"], imports: ["Kit", "SafeDI"], tiers: """
		    public init(windowBuilder: ErasedInstantiator<(), Window>) {
		        let cache = Cache()
		        self.init(windowBuilder: windowBuilder, cache: cache)
		    }
		""", guardHash: "00E0E32C7CA70EA2"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTier_whenParameterNamesNestedTypeOfUnreadType() async throws {
		// A6, N3: `Window.Scene` is unread as a whole, and the comment names it as spelled.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(receives: ["@Received let scene: Window.Scene"], hostForwards: ["scene: Window.Scene"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Window.Scene"], tiers: """
		    public init(scene: Window.Scene) {
		        let cache = Cache()
		        self.init(scene: scene, cache: cache)
		    }
		""", guardHash: "8DB59C18389CF5B8"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTier_whenParameterNamesUnreadTypesInsideCollectionClosureTupleAndMetatype() async throws {
		// A7, A9, A10, A13: each type an array, a closure, a tuple and a metatype name is proven on its own; the comment
		// names each unread one once, by spelling.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received let images: [Image]", "@Received let render: (Image) -> Void", "@Received let pair: (Image, Int)", "@Received let kind: Window.Type"],
				hostForwards: ["images: [Image]", "render: @escaping (Image) -> Void", "pair: (Image, Int)", "kind: Window.Type"],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Image", "Window"], tiers: """
		    public init(images: [Image], render: @escaping (Image) -> Void, pair: (Image, Int), kind: Window.Type) {
		        let cache = Cache()
		        self.init(images: images, render: render, pair: pair, kind: kind, cache: cache)
		    }
		""", guardHash: "A4E2907D006619BA"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingGenericArgument_whenArrayOfRecordedPackageTypeIsRequiredOnPublicSeam() async {
		// A8: the generic argument, `Secret`, decides, not the array.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `secrets: [Secret]`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Secret` is declared `package`. Declare `Secret` `public`; declare `Screen` `package`; receive `secrets` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Secret.swift"]):1:1: note: `Secret` is declared `package` here.
			\(fixtures["Feature"]!["Secret.swift"]):1:1-1:8: fixit: public
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `secrets: [Secret]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(receives: ["@Received let secrets: [Secret]"], extraFeatureFiles: ["Secret.swift": "package struct Secret {}"], hostForwards: nil),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTier_whenParameterIsExistentialOrCompositionOfUnreadProtocol() async throws {
		// A11, A12: `any Renderer` names `Renderer`; `Sendable`, a standard protocol, is never named by the comment.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received let renderer: any Renderer", "@Received let sendableRenderer: any Renderer & Sendable"],
				hostForwards: ["renderer: any Renderer", "sendableRenderer: any Renderer & Sendable"],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Renderer"], tiers: """
		    public init(renderer: any Renderer, sendableRenderer: any (Renderer & Sendable)) {
		        let cache = Cache()
		        self.init(renderer: renderer, sendableRenderer: sendableRenderer, cache: cache)
		    }
		""", guardHash: "56F483A97F6A2895"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTier_whenParameterSpellsUnreadModule() async throws {
		// A14: `Kit` is no module SafeDI reads, so `Kit.Window` is unread as spelled.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(receives: ["@Received let window: Kit.Window"], hostForwards: ["window: Kit.Window"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Kit.Window"], tiers: """
		    public init(window: Kit.Window) {
		        let cache = Cache()
		        self.init(window: window, cache: cache)
		    }
		""", guardHash: "81946861C06808EE"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesNoComment_whenPackageSeamTakesUnreadType() async throws {
		// A15, F2: a `package` tier never carries the comment: a type its module can name is at least `package` there.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Kit", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": "package struct Store {\n    package init() {}\n}"], runsSafeDI: false),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(access: "package", receives: ["@Received let store: Store"]),
				], dependencies: ["Kit"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], tiers: """
		    package init(store: Store) {
		        let cache = Cache()
		        self.init(store: store, cache: cache)
		    }
		""", guardHash: "765860960C8098A5"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTier_whenUnspelledExtensionBasedInstantiableExtendsUnreadType() async throws {
		// A17: `Window` is `Kit`'s, so the unspelled `@Instantiable` extension that declares it in `Feature` is bounded by
		// nothing narrower than `public`; `App` builds `Window` with it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(files: ["Window.swift": "public final class Window {\n    public init() {}\n}"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received let window: Window"]),
					"WindowInstantiable.swift": "import Kit\nimport SafeDI\n\n@Instantiable(conformsElsewhere: true)\nextension Window {\n    public static func instantiate() -> Window {\n        Window()\n    }\n}\n\nextension Window: @retroactive Instantiable {}",
				], dependencies: ["Kit"]),
				ModuleFixture(name: "App", packageName: "Store", swiftFileContentByFilePath: [
					"Root.swift": "import Feature\nimport Kit\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let window: Window", "@Instantiated let screen: Screen"]),
				], dependencies: ["Kit", "Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Window"], imports: ["Kit", "SafeDI"], tiers: """
		    public init(window: Window) {
		        let cache = Cache()
		        self.init(window: window, cache: cache)
		    }
		""", guardHash: "564C5E6539CF6AA0"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesInstantiableTypeOnPublicTier_whenItIsDeclaredInExtensionOfUnreadType(integration: MultiModuleIntegration) async throws {
		// A18: `Window.Badge`'s own `public` declaration counts, capped by `Window`, which is unread and so `public`; the
		// comment names `Window`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.badgeInWindowModules(badgeAccess: "public"),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Window"], tiers: """
		    public init(badge: Window.Badge) {
		        let cache = Cache()
		        self.init(badge: badge, cache: cache)
		    }
		""", guardHash: "5532E29B9382037A"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingOwnDeclaration_whenTypeInExtensionOfUnreadTypeIsPackageOnPublicSeam() async {
		// A19: the `package` `Badge` is required on a public seam: its own declaration is what to widen.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `badge: Window.Badge`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Window.Badge` is declared `package`. Declare `Badge` `public`; declare `Screen` `package`; receive `badge` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `badge: Window.Badge` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.badgeInWindowModules(badgeAccess: "package"), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTier_whenHoleScopeFieldIsUnreadType() async throws {
		// A16, E1c: the hole's scope struct holds `image`, which the seam receives, as a `public` field.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received let image: Image"],
				instantiates: ["@Instantiated let service: any UserService"],
				extraFeatureFiles: ["UserService.swift": "import Kit\n\npublic protocol UserService {\n    var image: Image { get }\n}"],
				hostForwards: ["image: Image"],
				appFiles: ["AppUserService.swift": "import Feature\nimport Kit\n\n@Instantiable(fulfillingAdditionalTypes: [UserService.self])\nstruct AppUserService: UserService, Instantiable {\n    init(image: Image) {\n        self.image = image\n    }\n\n    @Received let image: Image\n}"],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Image"], tiers: """
		    public struct SafeDIScope_Screen_service {
		        public let image: Image
		        internal let cache: Cache
		    }

		    public init(image: Image, serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Screen_service) -> any UserService) {
		        let cache = Cache()
		        let service: any UserService = __safeDI_serviceBuilder(SafeDIScope_Screen_service(image: image, cache: cache))
		        self.init(image: image, service: service, cache: cache)
		    }
		""", guardHash: "D84FD5051D793AC9"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderOfUnreadTypeOnPublicTier_whenHoleInstantiatesUnreadProtocol() async throws {
		// A22: the hole's builder returns `any Renderer`, which is unread.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: [],
				instantiates: ["@Instantiated let renderer: any Renderer"],
				hostForwards: [],
				appFiles: ["AppRenderer.swift": "import Kit\n\n@Instantiable(fulfillingAdditionalTypes: [Renderer.self])\nstruct AppRenderer: Renderer, Instantiable {\n    init() {}\n}"],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Renderer"], tiers: """
		    public struct SafeDIScope_Screen_renderer {
		        internal let cache: Cache
		    }

		    {COMMENT}
		    public init(rendererBuilder __safeDI_rendererBuilder: @escaping (SafeDIScope_Screen_renderer) -> any Renderer) {
		        let cache = Cache()
		        let renderer: any Renderer = __safeDI_rendererBuilder(SafeDIScope_Screen_renderer(cache: cache))
		        self.init(renderer: renderer, cache: cache)
		    }
		""", guardHash: "D8E3A9C04E79DB7D"))
		try expectEveryModuleCompiled(output)
	}

	// MARK: E: a `package` type of a module that does not run SafeDI

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPackageTypeOfUnscannedModuleOnPublicTier_whichThenFailsToCompile() async throws {
		// E1: `Kit` is first-party, in `Feature`'s package, and does not run SafeDI, so SafeDI counts its `package` `Store`
		// as `public`: the generated `public` initializer fails to compile, and the comment above it says why.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Kit", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": "package struct Store {\n    package init() {}\n}"], runsSafeDI: false),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received let store: Store"]),
				], dependencies: ["Kit"]),
			],
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Store"], tiers: """
		    public init(store: Store) {
		        let cache = Cache()
		        self.init(store: store, cache: cache)
		    }
		""", guardHash: "19911CF36F34982A"))
		try expectModuleCompilationFails(output, module: "Feature", containing: "initializer cannot be declared public because its parameter uses a package type")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPackageTypeOfUnscannedModuleOnPublicMockTier_whichThenFailsToCompile() async throws {
		// E1b: the public mock's twin: the comment is above `public static func mock(`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Kit", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": "package struct Store {\n    package init() {}\n}"], runsSafeDI: false),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.publicMockScreenSource(receives: ["@Received let store: Store"]),
				], dependencies: ["Kit"]),
			],
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.importLines(["Kit"]) + """
		#if DEBUG
		extension Screen {
		    \(Self.comment(["Store"]))
		    public static func mock(
		        store: Store
		    ) -> Screen {
		        return Screen(store: store)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_EFC364B5B4481EE8 {}
		}
		#endif
		"""])
		try expectModuleCompilationFails(output, module: "Feature", containing: "method cannot be declared public because its parameter uses a package type")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingModuleWithNoInstantiableTypes_whenItRunsSafeDI() async {
		// E3: `Kit` declares no `@Instantiable` type but runs SafeDI, so its `.safedi` records its `package` `Store`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `store: Store`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Store` is declared `package` in module `Kit`. Declare `Store` `public` in module `Kit`; declare `Screen` `package`; receive `store` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Kit"]!["Store.swift"]):1:1: note: `Store` is declared `package` here.
			\(fixtures["Kit"]!["Store.swift"]):1:1-1:8: fixit: public
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `store: Store` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Kit", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": "package struct Store {\n    package init() {}\n}"]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received let store: Store"]),
					], dependencies: ["Kit"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: P: an unread type counts as `public` on a public mock

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicMockTier_whenMockedTypeReceivesIt(integration: MultiModuleIntegration) async throws {
		// P1, F3: the public mock takes `window` on its public tier; `App`, in another package, calls it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.publicMockScreenSource(receives: ["@Received let window: Window"]),
				], dependencies: ["Kit"]),
				ModuleFixture(name: "App", packageName: "Store", swiftFileContentByFilePath: [
					"Preview.swift": "import Feature\nimport Kit\n\n#if DEBUG\nfunc preview() -> Screen {\n    Screen.mock(window: Window())\n}\n#endif",
				], dependencies: ["Kit", "Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let mockCode = """
		#if DEBUG
		extension Screen {
		\(integration == .moduleInfo ? "    \(Self.comment(["Window"]))\n" : "")    public static func mock(
		        window: Window
		    ) -> Screen {
		        return Screen(window: window)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_C012658DE000141A {}
		}
		#endif
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.importLines(["Kit"]) + mockCode])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + Self.importLines(["Kit"]) + mockCode)
		}
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsUnreadTypeWithUnspelledMockOnlyMock_whenPublicMockReceivesIt(integration: MultiModuleIntegration) async throws {
		// P6: `User` is `Kit`'s, so its unspelled `mockOnly` extension in `Feature` needs no level: the public tier takes
		// `user` as an optional parameter and builds it with `User.mock()`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(files: ["User.swift": "public final class User: Sendable {\n    public init(name: String) {\n        self.name = name\n    }\n\n    public let name: String\n}"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"UserMock.swift": "import Kit\n\n@Instantiable(mockOnly: true)\nextension User {\n    public static func mock() -> User {\n        User(name: \"Mock\")\n    }\n}",
					"Screen.swift": Self.publicMockScreenSource(receives: ["@Received let user: User"]),
				], dependencies: ["Kit"]),
				ModuleFixture(name: "App", packageName: "Store", swiftFileContentByFilePath: [
					"Preview.swift": "import Feature\nimport Kit\n\n#if DEBUG\nfunc preview() -> Screen {\n    Screen.mock(user: User(name: \"dfed\"))\n}\n#endif",
				], dependencies: ["Kit", "Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let mockCode = """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            user: (() -> User)? = nil
		        ) {
		            self.user = user
		        }

		        public let user: (() -> User)?
		    }

		\(integration == .moduleInfo ? "    \(Self.comment(["User"]))\n" : "")    public static func mock(
		        user: User? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User.mock() }
		        return Screen(user: user)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_77E7840731A6C4C1 {}
		}
		#endif
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.importLines(["Kit"]) + mockCode])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + Self.importLines(["Kit"]) + mockCode)
		}
		try expectEveryModuleCompiled(output)
	}

	// MARK: EX: a type declared inside an extension counts at its own level, capped by the extended type's

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypeDeclaredInExtensionOnPublicTier_whenExtensionAndTypeArePublic(integration: MultiModuleIntegration) async throws {
		// EX1: Tolan's shape: `ChatService.TurnTakingMode`, declared `public` in an unspelled extension of the `public`
		// `ChatService` in a file without a SafeDI marker, is `public` exactly; no comment, since SafeDI reads it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received let mode: ChatService.TurnTakingMode"],
				extraFeatureFiles: ["ChatService.swift": "public final class ChatService {\n    public init() {}\n}\n\nextension ChatService {\n    public enum TurnTakingMode {\n        case automatic\n        case manual\n    }\n}"],
				hostForwards: ["mode: ChatService.TurnTakingMode"],
			),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: [], tiers: """
		    public init(mode: ChatService.TurnTakingMode) {
		        let cache = Cache()
		        self.init(mode: mode, cache: cache)
		    }
		""", guardHash: "C474C12E18F8A008"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtTypeInExtension_whenItSpellsNoLevel(integration: MultiModuleIntegration) async {
		// EX2: `Space.Config` spells no level in an unspelled extension, so it is `internal`, with a fix-it at it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let spacePath = Self.path(of: "Space.swift", in: "Feature", fixtures, integration)
			return """
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `config: Space.Config`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Space.Config` is declared `internal`. Declare `Space.Config` `public`; declare `Screen` `internal`; receive `config` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(spacePath):4:5: note: `Space.Config` is declared `internal` here.
			\(spacePath):4:5-4:5: fixit: public\(" ")
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):10:5: note: `Screen` receives `config: Space.Config` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(receives: ["@Received let config: Space.Config"], extraFeatureFiles: ["Space.swift": "public enum Space {}\n\nextension Space {\n    struct Config {}\n}"], hostForwards: nil),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingExtendedType_whenPublicTypeInExtensionOfPackageType() async {
		// EX3: `Space.Config` spells `public`, but `Space` is `package`, which caps it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `config: Space.Config`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Space.Config` is `package`: it is declared inside an extension of `Space`, whose own declaration is `package`. Declare `Space` `public`; declare `Screen` `package`; receive `config` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Space.swift"]):1:1: note: `Space` is declared `package` here.
			\(fixtures["Feature"]!["Space.swift"]):1:1-1:8: fixit: public
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `config: Space.Config` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(receives: ["@Received let config: Space.Config"], extraFeatureFiles: ["Space.swift": "package enum Space {}\n\nextension Space {\n    public struct Config {\n        public init() {}\n    }\n}"], hostForwards: nil),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypeOnPackageTier_whenPackageExtensionDeclaresIt(integration: MultiModuleIntegration) async throws {
		// EX4, EX5: `Core`'s `package extension Space`, in a file without a SafeDI marker, declares `Config` and `ID`, which
		// take the extension's `package` level: the public tier passes `nil` for them, the `package` tier takes them.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.spaceInCoreModules(receives: ["@Received(onlyIfAvailable: true) let config: Space.Config?", "@Received(onlyIfAvailable: true) let id: Space.ID?"]),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: [], imports: ["Core"], tiers: """
		    public init() {
		        self.init(config: nil, id: nil)
		    }

		    package init(config: Space.Config? = nil, id: Space.ID? = nil) {
		        let cache = Cache()
		        self.init(config: config, id: id, cache: cache)
		    }
		""", guardHash: "1A021706E12F6E19"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingDeclaringModule_whenPublicSeamRequiresTypePackageExtensionDeclares(integration: MultiModuleIntegration) async {
		// EX4: required on the public seam, `Space.Config` is reported as `Core` declares it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let extensionPath = Self.path(of: "SpaceExtension.swift", in: "Core", fixtures, integration)
			return """
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `config: Space.Config`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Space.Config` is declared `package` in module `Core`. Declare `Space.Config` `public` in module `Core`; declare `Screen` `package`; receive `config` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(extensionPath):1:1: note: The extension that declares `Space.Config` is `package` here.
			\(extensionPath):1:1-1:8: fixit: public
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):10:5: note: `Screen` receives `config: Space.Config` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.spaceInCoreModules(receives: ["@Received let config: Space.Config"]), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypeInExtensionOfUnreadTypeOnPublicTier(integration: MultiModuleIntegration) async throws {
		// EX6: `Window.Badge`, a plain type `Feature` declares in an extension of `Kit`'s `Window`, is `public`, capped by
		// `Window`, which is unread: the comment names `Window`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received let badge: Window.Badge"],
				extraFeatureFiles: ["WindowBadge.swift": "import Kit\n\nextension Window {\n    public struct Badge {\n        public init() {}\n    }\n}"],
				hostForwards: ["badge: Window.Badge"],
			),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Window"], tiers: """
		    public init(badge: Window.Badge) {
		        let cache = Cache()
		        self.init(badge: badge, cache: cache)
		    }
		""", guardHash: "5532E29B9382037A"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenParameterTypeIsNestedThreeDeepInExtensionInMarkerFreeFile(integration: MultiModuleIntegration) async {
		// EX7: `extension Space.Inner { struct Config {} }` is in a file without a SafeDI marker: every name of the mention's
		// chain is demanded, so the file is parsed and `Space.Inner.Config` is recorded.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let configPath = Self.path(of: "Config.swift", in: "Feature", fixtures, integration)
			return """
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `config: Space.Inner.Config`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Space.Inner.Config` is declared `internal`. Declare `Space.Inner.Config` `public`; declare `Screen` `internal`; receive `config` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(configPath):2:5: note: `Space.Inner.Config` is declared `internal` here.
			\(configPath):2:5-2:5: fixit: public\(" ")
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):10:5: note: `Screen` receives `config: Space.Inner.Config` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(
					receives: ["@Received let config: Space.Inner.Config"],
					extraFeatureFiles: ["Space.swift": "public enum Space {\n    public enum Inner {}\n}", "Config.swift": "extension Space.Inner {\n    struct Config {}\n}"],
					hostForwards: nil,
				),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypesDeclaredInExtensionOfPackageInstantiableOnPackageTier() async throws {
		// EX8: `Shelf.Ledger`, which an `@Instantiable` extension declares, and the plain `Shelf.Label` both spell `public`
		// inside an extension of the `package` `@Instantiable` `Shelf`, which caps them: the `package` tier takes them.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received(onlyIfAvailable: true) let ledger: Shelf.Ledger?", "@Received(onlyIfAvailable: true) let label: Shelf.Label?"],
				extraFeatureFiles: ["Shelf.swift": "import SafeDI\n\n@Instantiable\npackage final class Shelf: Instantiable {\n    package init() {}\n}\n\nextension Shelf {\n    public final class Ledger {\n        public init() {}\n    }\n\n    public struct Label {\n        public init() {}\n    }\n}\n\n@Instantiable\nextension Shelf.Ledger: Instantiable {\n    package static func instantiate() -> Shelf.Ledger {\n        Shelf.Ledger()\n    }\n}"],
				hostForwards: nil,
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], imports: ["Kit", "SafeDI"], tiers: """
		    public init() {
		        self.init(ledger: nil, label: nil)
		    }

		    package init(ledger: Shelf.Ledger? = nil, label: Shelf.Label? = nil) {
		        let cache = Cache()
		        self.init(ledger: ledger, label: label, cache: cache)
		    }
		""", guardHash: "7A983275AFD4BE17"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesExtensionBasedInstantiableOnPackageTier_whenItsTypeIsDeclaredInExtensionOfPackageType() async throws {
		// EX9: `Space.Ledger`, which an `@Instantiable` extension declares, spells `public` inside an extension of the
		// `package` `Space`, a plain declaration, which caps it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received(onlyIfAvailable: true) let ledger: Space.Ledger?"],
				extraFeatureFiles: ["Space.swift": "import SafeDI\n\npackage enum Space {}\n\nextension Space {\n    public final class Ledger {\n        public init() {}\n    }\n}\n\n@Instantiable\nextension Space.Ledger: Instantiable {\n    package static func instantiate() -> Space.Ledger {\n        Space.Ledger()\n    }\n}"],
				hostForwards: nil,
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], imports: ["Kit", "SafeDI"], tiers: """
		    public init() {
		        self.init(ledger: nil)
		    }

		    package init(ledger: Space.Ledger? = nil) {
		        let cache = Cache()
		        self.init(ledger: ledger, cache: cache)
		    }
		""", guardHash: "1F00F75275E5B6DA"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesExtensionBasedInstantiableOnPublicTier_whenItsTypeIsDeclaredInExtensionOfUnreadNestedType(integration: MultiModuleIntegration) async throws {
		// EX10: `Window.Scene.Ledger`, which an `@Instantiable` extension declares, spells `public` inside an extension of
		// `Kit`'s `Window.Scene`, which is unread, as `Window` is: the comment names `Window.Scene`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received let ledger: Window.Scene.Ledger"],
				extraFeatureFiles: ["Ledger.swift": "import Kit\nimport SafeDI\n\nextension Window.Scene {\n    public final class Ledger {\n        public init() {}\n    }\n}\n\n@Instantiable\nextension Window.Scene.Ledger: Instantiable {\n    public static func instantiate() -> Window.Scene.Ledger {\n        Window.Scene.Ledger()\n    }\n}"],
				hostForwards: ["ledger: Window.Scene.Ledger"],
			),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Window.Scene"], imports: ["Kit", "SafeDI"], tiers: """
		    public init(ledger: Window.Scene.Ledger) {
		        let cache = Cache()
		        self.init(ledger: ledger, cache: cache)
		    }
		""", guardHash: "CDFBE3593701EF44"))
		try expectEveryModuleCompiled(output)
	}

	// MARK: C: a typealias is recorded as any plain declaration is

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypealiasOnPublicTier_whenSeamsModuleDeclaresItPublic(integration: MultiModuleIntegration) async throws {
		// C1, T1: the `public typealias`, in a file without a SafeDI marker, proves `UserID` `public`; no comment names it,
		// although `String`, which it aliases, is never read.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(receives: ["@Received let userID: UserID"], extraFeatureFiles: ["UserID.swift": "public typealias UserID = String"], hostForwards: ["userID: UserID"]),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: [], tiers: """
		    public init(userID: UserID) {
		        let cache = Cache()
		        self.init(userID: userID, cache: cache)
		    }
		""", guardHash: "60EECB42C345EC34"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtTypealias_whenSeamsModuleDeclaresItInternal(integration: MultiModuleIntegration) async {
		// C2: the `internal` typealias is what to widen, with a fix-it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let aliasPath = Self.path(of: "UserID.swift", in: "Feature", fixtures, integration)
			return """
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `userID: UserID`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `UserID` is declared `internal`. Declare `UserID` `public`; declare `Screen` `internal`; receive `userID` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(aliasPath):1:1: note: `UserID` is declared `internal` here.
			\(aliasPath):1:1-1:1: fixit: public\(" ")
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):10:5: note: `Screen` receives `userID: UserID` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(receives: ["@Received let userID: UserID"], extraFeatureFiles: ["UserID.swift": "typealias UserID = String"], hostForwards: nil),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypealiasOnPackageTier_whenDependencyDeclaresPackageTypealias(integration: MultiModuleIntegration) async throws {
		// C3: `Core`'s `package typealias Token`, in a file without a SafeDI marker, is on the `package` tier.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Token.swift": "package typealias Token = Int"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let token: Token?"], imports: ["Core"]),
				], dependencies: ["Core"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: [], imports: ["Core"], tiers: """
		    public init() {
		        self.init(token: nil)
		    }

		    package init(token: Token? = nil) {
		        let cache = Cache()
		        self.init(token: token, cache: cache)
		    }
		""", guardHash: "16885A1AAD60582A"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingDeclaringModule_whenPublicSeamRequiresDependencysPackageTypealias(integration: MultiModuleIntegration) async {
		// C3: required on a `public` seam, `Core`'s `package typealias Token` is what to widen, with a fix-it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let screenPath = Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)
			let aliasPath = Self.path(of: "Token.swift", in: "Core", fixtures, integration)
			return """
			\(screenPath):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `token: Token`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Token` is declared `package` in module `Core`. Declare `Token` `public` in module `Core`; declare `Screen` `package`; receive `token` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(aliasPath):1:1: note: `Token` is declared `package` here.
			\(aliasPath):1:1-1:8: fixit: public
			\(screenPath):10:5: note: `Screen` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Token.swift": "package typealias Token = Int"]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received let token: Token"], imports: ["Core"]),
					], dependencies: ["Core"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypealiasOnPublicTier_whenTypealiasIsNestedInTypeBody() async throws {
		// C5: `Space.ID` is recorded at its chain, nested in `Space`'s body.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(receives: ["@Received let id: Space.ID"], extraFeatureFiles: ["Space.swift": "public enum Space {\n    public typealias ID = String\n}"], hostForwards: ["id: Space.ID"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], tiers: """
		    public init(id: Space.ID) {
		        let cache = Cache()
		        self.init(id: id, cache: cache)
		    }
		""", guardHash: "D129C3323EC9D95A"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtTypealias_whenHoleBuilderReturnsInternalClosureTypealias() async {
		// HOLE: the builder of a hole typed by an `internal` closure typealias is as visible as the typealias.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `handlerBuilder: @escaping (Screen.SafeDIScope_Screen_handler) -> Handler`, the builder for `Screen`'s `handler: Handler`, which no @Instantiable declaration module `Feature` can see fulfills. `Handler` is declared `internal`. Declare `Handler` `public`; declare `Screen` `internal`; make an @Instantiable declaration that fulfills `Handler` one module `Feature` reads, so `Screen`'s tree builds it; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Handler.swift"]):1:1: note: `Handler` is declared `internal` here.
			\(fixtures["Feature"]!["Handler.swift"]):1:1-1:1: fixit: public\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(receives: [], instantiates: ["@Instantiated let handler: Handler"], extraFeatureFiles: ["Handler.swift": "typealias Handler = () -> Void"], hostForwards: nil),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: N: a type nested in a recorded type SafeDI reads no declaration of counts at the enclosing type's level

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingEnclosingProtocol_whenParameterNamesTypealiasInProtocolBody() async {
		// N1: SafeDI reads no member of a protocol's body, so `Renderer.ID` counts as `Renderer` does.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `id: Renderer.ID`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Renderer.ID` is nested in `Renderer`, which is declared `internal`. Declare `Renderer` `public`; declare `Screen` `internal`; receive `id` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Renderer.swift"]):1:1: note: `Renderer` is declared `internal` here.
			\(fixtures["Feature"]!["Renderer.swift"]):1:1-1:1: fixit: public\(" ")
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `id: Renderer.ID` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(receives: ["@Received let id: Renderer.ID"], extraFeatureFiles: ["Renderer.swift": "protocol Renderer {\n    typealias ID = String\n}"], hostForwards: nil),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingEnclosingProtocolsModule_whenParameterNamesTypealiasInPackageProtocolOfDependency() async {
		// N2: the enclosing protocol is `Core`'s.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `id: Renderer.ID`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Renderer.ID` is nested in `Renderer`, which is declared `package` in module `Core`. Declare `Renderer` `public` in module `Core`; declare `Screen` `package`; receive `id` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Core"]!["Renderer.swift"]):1:1: note: `Renderer` is declared `package` here.
			\(fixtures["Core"]!["Renderer.swift"]):1:1-1:8: fixit: public
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `id: Renderer.ID` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Renderer.swift": "package protocol Renderer {\n    typealias ID = String\n}"]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received let id: Renderer.ID"], imports: ["Core"]),
					], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingEnclosingInstantiable_whenParameterNamesTypeNestedInItThatNoModuleInfoRecords() async {
		// N4: `Base`'s `.safedi` records no declaration of `Shelf.Label`, whose file holds no SafeDI marker and no `package`:
		// it counts as the `package` `@Instantiable` `Shelf` that encloses it does.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `label: Shelf.Label`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Shelf.Label` is nested in `Shelf`, whose own `@Instantiable` declaration is `package`. Declare `Shelf` `public`; declare `Screen` `package`; receive `label` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `label: Shelf.Label` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Base", packageName: "Shop", swiftFileContentByFilePath: [
						"Shelf.swift": "import SafeDI\n\n@Instantiable\npackage final class Shelf: Instantiable {\n    package init() {}\n}",
						"ShelfLabel.swift": "extension Shelf {\n    public struct Label {\n        public init() {}\n    }\n}",
					]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received let label: Shelf.Label"], imports: ["Base"]),
					], dependencies: ["Base"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: D: a module's own declaration of a standard type's name precedes the standard type

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamsModuleShadowsStandardTypeWithPackageDeclaration() async {
		// D1: `Feature`'s own `package struct Result` is what the mention names, not `Swift.Result`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `result: Result`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Result` is declared `package`. Declare `Result` `public`; declare `Screen` `package`; receive `result` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Result.swift"]):1:1: note: `Result` is declared `package` here.
			\(fixtures["Feature"]!["Result.swift"]):1:1-1:8: fixit: public
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `result: Result` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(receives: ["@Received let result: Result"], extraFeatureFiles: ["Result.swift": "package struct Result {\n    package init() {}\n}"], hostForwards: nil),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesQualifiedStandardTypeOnPublicTier_whenSeamsModuleShadowsItsName() async throws {
		// D2: `Swift.Result` names the standard type, whatever `Feature` declares.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received let result: Swift.Result<Int, any Error>"],
				extraFeatureFiles: ["Result.swift": "package struct Result {\n    package init() {}\n}"],
				hostForwards: ["result: Swift.Result<Int, any Error>"],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], tiers: """
		    public init(result: Swift.Result<Int, any Error>) {
		        let cache = Cache()
		        self.init(result: result, cache: cache)
		    }
		""", guardHash: "E5902820E96A4498"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingDeclaringModule_whenDependencyShadowsStandardTypeWithPackageDeclaration() async {
		// D3: `Core`'s `package struct Result` is recorded, and precedes the standard type.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `result: Result`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Result` is declared `package` in module `Core`. Declare `Result` `public` in module `Core`; declare `Screen` `package`; receive `result` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Core"]!["Result.swift"]):1:1: note: `Result` is declared `package` here.
			\(fixtures["Core"]!["Result.swift"]):1:1-1:8: fixit: public
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `result: Result` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Result.swift": "package struct Result {\n    package init() {}\n}"]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received let result: Result"], imports: ["Core"]),
					], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: U: a spelling SafeDI cannot read

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingSpellingIsUnreadable_whenPublicSeamReceivesInlineArray() async {
		// U1: SafeDI cannot read `[3 of Int]`, which counts as `internal`, with the mention remedy alone.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `buffer: [3 of Int]`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `internal` (`Screen.init(buffer:cache:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Screen` `internal`; receive `buffer` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `buffer: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(receives: ["@Received let buffer: [3 of Int]"], hostForwards: nil),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: S: a declaration inside an `#if` block of another module

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTier_whenDependencyDeclaresInternalNamesakeInsideConditionalBlock(integration: MultiModuleIntegration) async throws {
		// S1: `Logs`'s `internal` `DateInterval` inside an `#if` block is no type another module can name, so
		// `Foundation`'s `DateInterval`, which SafeDI does not read, counts as `public`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Logs", packageName: "Shop", swiftFileContentByFilePath: [
					"Journal.swift": "#if DEBUG\nstruct DateInterval {}\n#endif\n\n@Instantiable\npublic struct Journal: Instantiable {\n    public init() {}\n}",
				], activeCompilationConditions: ["DEBUG"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received let interval: DateInterval"], imports: ["Foundation", "Logs"]),
				], dependencies: ["Logs"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["DateInterval"], imports: ["Foundation", "Logs"], tiers: """
		    public init(interval: DateInterval) {
		        let cache = Cache()
		        self.init(interval: interval, cache: cache)
		    }
		""", guardHash: "A40FBF1797F7E662"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenOneDependencyDeclaresTypePublicAndAnotherPackageInsideConditionalBlock(integration: MultiModuleIntegration) async {
		// S2: `Shades`'s `package` `Theme` inside an `#if` block counts as `internal` unless a mention raises it, and it is
		// narrower than `Paints`'s `public` one.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):4:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `theme: Theme`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Theme` is `internal` as far as SafeDI can tell: it is declared inside an `#if` block in module `Shades`, from which SafeDI takes no access level, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `internal` (`Screen.init(theme:cache:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `Theme` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; give `Theme` a `public` `mockOnly` mock (`@Instantiable(mockOnly: true) public extension Theme { public static func mock() -> Theme }`), which proves `Theme` `public`; declare `Screen` `internal`; receive `theme` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):11:5: note: `Screen` receives `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Paints", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "public struct Theme {}"]),
					ModuleFixture(name: "Shades", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "#if DEBUG\npackage struct Theme {}\n#endif"], activeCompilationConditions: ["DEBUG"]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received let theme: Theme"], imports: ["Paints", "Shades"]),
					], dependencies: ["Paints", "Shades"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_countsDependencysConditionallyDeclaredPublicTypeByIntegration_whenOnlyTheSeamsInternalInitializerMentionsIt(integration: MultiModuleIntegration) async throws {
		// `Paints` declares `Theme` `public` inside an `#if` block. The plugin reads `Paints`'s file, so `Theme` counts as
		// `internal` unless a mention raises it, and only `Screen`'s `internal` initializer mentions it; `Paints`'s `.safedi`
		// records only the declarations only its package can name, so under `.moduleInfo` SafeDI reads no declaration of
		// `Theme`, and counts it as `public`. Either compiles: `Theme` is `public` wherever it exists.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Paints", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": unrecordedTypeDeclaration("public struct Theme {}")]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"], imports: ["Paints"]),
				], dependencies: ["Paints"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Theme"], imports: ["Paints"], tiers: """
			    public init(theme: Theme? = nil) {
			        let cache = Cache()
			        self.init(theme: theme, cache: cache)
			    }
			""", guardHash: "717280493A095F31"))
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: [], imports: ["Paints"], tiers: """
			    public init() {
			        self.init(theme: nil)
			    }

			    internal init(theme: Theme? = nil) {
			        let cache = Cache()
			        self.init(theme: theme, cache: cache)
			    }
			""", guardHash: "2163FBB3C02B31CD"))
		}
		try expectEveryModuleCompiled(output)
	}

	// MARK: F: the comment

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesEachUnreadTypeOnceInComment_whenPublicTierNamesSix() async throws {
		// F1: six unread types, received in an order neither their labels nor their names give, are named once each, in
		// the order of their spellings.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received let zebra: Canvas", "@Received let apple: Window.Scene", "@Received let mango: Brush", "@Received let kiwi: Image", "@Received let berry: Palette", "@Received let fig: Window", "@Received let date: [Brush]"],
				hostForwards: ["zebra: Canvas", "apple: Window.Scene", "mango: Brush", "kiwi: Image", "berry: Palette", "fig: Window", "date: [Brush]"],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Brush", "Canvas", "Image", "Palette", "Window", "Window.Scene"], tiers: """
		    public init(zebra: Canvas, apple: Window.Scene, mango: Brush, kiwi: Image, berry: Palette, fig: Window, date: [Brush]) {
		        let cache = Cache()
		        self.init(zebra: zebra, apple: apple, mango: mango, kiwi: kiwi, berry: berry, fig: fig, date: date, cache: cache)
		    }
		""", guardHash: "32C36057D4C81D7E"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesCommentOnlyOnPublicTier_whenNarrowerTierExists() async throws {
		// F5: the `package` tier names `Window` too, but only `public` declarations carry the file's one comment.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received let window: Window", "@Received(onlyIfAvailable: true) let token: Token?"],
				extraFeatureFiles: ["Token.swift": "package struct Token {}"],
				hostForwards: ["window: Window"],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Window"], tiers: """
		    public init(window: Window) {
		        self.init(window: window, token: nil)
		    }

		    package init(window: Window, token: Token? = nil) {
		        let cache = Cache()
		        self.init(window: window, token: token, cache: cache)
		    }
		""", guardHash: "A8DF3FE04EBB7091"))
		try expectEveryModuleCompiled(output)
	}

	// MARK: W: a run that writes a `.safedi` without a target graph keeps only `package` declarations

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesReceivedTypeOnPackageTier_whenDependencysMarkerFreeFileDeclaresItPackageWithModifierBeforeKeyword() async throws {
		// W1: `Core`'s `package final class Palette`, in a file without a SafeDI marker, is recorded for its dependents.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Palette.swift": "package final class Palette {\n    package init() {}\n}"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let palette: Palette?"], imports: ["Core"]),
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], imports: ["Core"], tiers: """
		    public init() {
		        self.init(palette: nil)
		    }

		    package init(palette: Palette? = nil) {
		        let cache = Cache()
		        self.init(palette: palette, cache: cache)
		    }
		""", guardHash: "A9677D0B9731F23E"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPackageTypeNestedInPublicType_whenDependencyWritesModuleInfo() async throws {
		// W2: `Core`'s `package struct Inner` inside its `public enum Outer` is kept, and `Outer`, `public`, is not.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Outer.swift": "public enum Outer {\n    package struct Inner {}\n}"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let inner: Outer.Inner?"], imports: ["Core"]),
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.moduleInfo?.plainTypeDeclarations.map(\.typeDescription.asSource) == ["Outer.Inner"])
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], imports: ["Core"], tiers: """
		    public init() {
		        self.init(inner: nil)
		    }

		    package init(inner: Outer.Inner? = nil) {
		        let cache = Cache()
		        self.init(inner: inner, cache: cache)
		    }
		""", guardHash: "9E4F1AEB56A64027"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesNoPublicDeclarationItsDeclarationsDoNotMention_whenDependencyWritesModuleInfo() async throws {
		// W3: `Core`'s `public struct Palette`, in a file without a SafeDI marker, is not recorded: its dependents count it as
		// `public` anyway, and the comment names it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Palette.swift": "public struct Palette {\n    public init() {}\n}"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received let palette: Palette"], imports: ["Core"]),
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.moduleInfo?.plainTypeDeclarations.isEmpty == true)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Palette"], imports: ["Core"], tiers: """
		    public init(palette: Palette) {
		        let cache = Cache()
		        self.init(palette: palette, cache: cache)
		    }
		""", guardHash: "B31AFC0310819646"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingDeclaringModule_whenCommentSeparatesPackageModifierFromKeyword() async {
		// W4: the text search finds the word `package` wherever it is, so a comment between it and `struct` hides nothing.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `commented: Commented`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Commented` is declared `package` in module `Core`. Declare `Commented` `public` in module `Core`; declare `Screen` `package`; receive `commented` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Core"]!["Commented.swift"]):1:1: note: `Commented` is declared `package` here.
			\(fixtures["Core"]!["Commented.swift"]):1:1-1:8: fixit: public
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `commented: Commented` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Commented.swift": "package /* note */ struct Commented {}"]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received let commented: Commented"], imports: ["Core"]),
					], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesReceivedTypeOnPackageTier_whenDependencysMarkerFreeFileDeclaresPackageTypeWithNameInBackticks() async throws {
		// W5: the text search for a name after its keyword misses `` `Protocol` ``, but the file holds the word `package`, so
		// it is parsed and its declaration recorded.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Protocol.swift": "package struct `Protocol` {}"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let kind: `Protocol`?"], imports: ["Core"]),
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], imports: ["Core"], tiers: """
		    public init() {
		        self.init(kind: nil)
		    }

		    package init(kind: `Protocol`? = nil) {
		        let cache = Cache()
		        self.init(kind: kind, cache: cache)
		    }
		""", guardHash: "85F866D535705A4E"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesReceivedTypeOnPackageTier_whenCommentSeparatesTypeKeywordFromNameInDependencysMarkerFreeFile() async throws {
		// W6: the text search for a name after its keyword misses `Commented` behind a comment, but the file holds the word
		// `package`, so it is parsed and its declaration recorded.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Commented.swift": "package struct /* note */ Commented {}"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let commented: Commented?"], imports: ["Core"]),
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], imports: ["Core"], tiers: """
		    public init() {
		        self.init(commented: nil)
		    }

		    package init(commented: Commented? = nil) {
		        let cache = Cache()
		        self.init(commented: commented, cache: cache)
		    }
		""", guardHash: "C7131F41728A076A"))
		try expectEveryModuleCompiled(output)
	}

	// MARK: B: a declaration inside an `#if` block counts as `internal` unless a mention raises it

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingModule_whenDependencysConditionallyDeclaredPackageTypeIsRequiredOnPublicSeam(integration: MultiModuleIntegration) async {
		// B5: `Core`'s `package struct Token` inside an `#if` block is read, from `Core`'s `.safedi` or its files, and
		// counts as `internal`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `token: Token`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Token` is `internal` as far as SafeDI can tell: it is declared inside an `#if` block in module `Core`, from which SafeDI takes no access level, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `internal` (`Screen.init(token:cache:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `Token` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; give `Token` a `public` `mockOnly` mock (`@Instantiable(mockOnly: true) public extension Token { public static func mock() -> Token }`), which proves `Token` `public`; declare `Screen` `internal`; receive `token` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):10:5: note: `Screen` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Token.swift": unrecordedTypeDeclaration("package struct Token {}")]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received let token: Token"], imports: ["Core"]),
					], dependencies: ["Core"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTier_whenSeamsOwnConditionallyDeclaredInternalTypeIsReceivedOnlyIfAvailable() async throws {
		// B6: `Feature`'s `internal` `Handler` inside an `#if` block is on the `internal` tier only; `App` calls the
		// `public` one, computing the same signature from `Feature`'s `.safedi`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received(onlyIfAvailable: true) let handler: Handler?"],
				extraFeatureFiles: ["Handler.swift": "#if DEBUG\nstruct Handler {}\n#endif"],
				hostForwards: nil,
				featureConditions: ["DEBUG"],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], tiers: """
		    public init() {
		        self.init(handler: nil)
		    }

		    internal init(handler: Handler? = nil) {
		        let cache = Cache()
		        self.init(handler: handler, cache: cache)
		    }
		""", guardHash: "ABC0ED47A0A8DC7D"))
		try expectEveryModuleCompiled(output)
	}

	// MARK: X: a declaration of a module SafeDI knows no name of

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenUnnamedModuleInfoDeclaresPackageTypes() async {
		// X1: `Core`'s `.safedi` names no module, so SafeDI counts its `package` `Store` at its declared level.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `store: Store`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Store` is declared `package` in a module SafeDI knows no name of. Declare `Store` `public` in a module SafeDI knows no name of; name the module that declares `Store` where SafeDI runs on it (`module_name` under Bazel, `--module-name` otherwise); declare `Screen` `package`; receive `store` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Core"]!["Store.swift"]):1:1: note: `Store` is declared `package` here.
			\(fixtures["Core"]!["Store.swift"]):1:1-1:8: fixit: public
			\(fixtures["Feature"]!["Screen.swift"]):11:5: note: `Screen` receives `store: Store` here.
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `token: Token`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Token` is `internal` as far as SafeDI can tell: it is declared inside an `#if` block in a module SafeDI knows no name of, from which SafeDI takes no access level, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `internal` (`Screen.init(store:token:cache:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `Token` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; give `Token` a `public` `mockOnly` mock (`@Instantiable(mockOnly: true) public extension Token { public static func mock() -> Token }`), which proves `Token` `public`; declare `Screen` `internal`; receive `token` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Screen.swift"]):12:5: note: `Screen` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": "package struct Store {\n    package init() {}\n}\n\n#if DEBUG\npackage struct Token {}\n#endif"], activeCompilationConditions: ["DEBUG"], omitsModuleName: true),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received let store: Store", "@Received let token: Token"], imports: ["Core"]),
					], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: SPM: a fetched package's own modules

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsSiblingModuleOfCheckoutPackage_whenSeamsModuleIsFetched() async throws {
		// SPM: `Shop` is fetched, so both its modules are under `checkouts`; the plugin still reads `Core` for `Feature`, a
		// module of the same package, so `Core`'s `package` `Store` is on the `package` tier only. Read as a type of a
		// module SafeDI does not read, it would be `public`, and the `public` tier would not compile. This cell pins only
		// the harness's model of the plugin's rule (`isCheckoutPackage`), and passes without the plugin's fix: the plugin
		// itself is shown by the capture of a `file://` package build in the pull request, before and after the fix.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": "package struct Store {\n    package init() {}\n}"], isCheckoutPackage: true),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let store: Store?"], imports: ["Core"]),
				], dependencies: ["Core"], isCheckoutPackage: true),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.swiftPackagePlugin, comment: [], imports: ["Core"], tiers: """
		    public init() {
		        self.init(store: nil)
		    }

		    package init(store: Store? = nil) {
		        let cache = Cache()
		        self.init(store: store, cache: cache)
		    }
		""", guardHash: "CDA3953F87466B1A"))
		try expectEveryModuleCompiled(output)
	}

	// MARK: A: nested seams

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnBothPublicTiers_whenSeamNestedInAnotherSeamPassesUnreadTypeUp() async throws {
		// A20: `Shell`'s seam reaches `Feature`'s, which receives `window`: each module proves `Window` `public` over its own
		// map, so each public tier takes it, and each module's file carries the comment.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received let window: Window"]),
				], dependencies: ["Kit"]),
				ModuleFixture(name: "Shell", packageName: "Mall", swiftFileContentByFilePath: [
					"Frame.swift": "import Feature\nimport Kit\n\n" + seamFixtureType(named: "Frame", isSeam: true, declarations: ["@Instantiated let screen: Screen"]),
				], dependencies: ["Kit", "Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Window"], tiers: """
		    public init(window: Window) {
		        let cache = Cache()
		        self.init(window: window, cache: cache)
		    }
		""", guardHash: "564C5E6539CF6AA0"))
		#expect(output.modules["Shell"]?.generatedFiles == ["Shell.swift": generatedFileHeader + Self.importLines(["Feature", "Kit"]) + """
		extension Frame {
		    \(Self.comment(["Window"]))
		    public init(window: Window) {
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_564C5E6539CF6AA0.self
		            return Screen(window: window)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(screen: screen)
		    }
		}

		extension Frame {
		    public enum __safeDI_Frame_564C5E6539CF6AA0 {}
		}
		"""])
		try expectEveryModuleCompiled(output)
	}

	// MARK: P: public mocks, continued

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicMockTier_whenMockedTypeForwardsItOrReceivesItOnlyIfAvailable() async throws {
		// P2, P3, P5: a forwarded unread type is a required parameter, first; one received only if available is an optional
		// one; a closure over a nested unread type is named by that type.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": "import Kit\n\n@Instantiable(generateMock: .public)\npublic struct Screen: Instantiable {\n    init(image: Image, window: Window?, render: @escaping (Window.Scene) -> Void) {\n        self.image = image\n        self.window = window\n        self.render = render\n    }\n\n    @Forwarded let image: Image\n    @Received(onlyIfAvailable: true) let window: Window?\n    @Received let render: (Window.Scene) -> Void\n}",
				], dependencies: ["Kit"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.importLines(["Kit"]) + """
		#if DEBUG
		extension Screen {
		    \(Self.comment(["Image", "Window", "Window.Scene"]))
		    public static func mock(
		        image: Image,
		        render: @escaping (Window.Scene) -> Void,
		        window: Window? = nil
		    ) -> Screen {
		        return Screen(image: image, window: window, render: render)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_2D735D0D9A172B6E {}
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicMockTier_whenMockScopeFieldIsUnreadType() async throws {
		// P4: `Badge`, which the mocked type builds through an instantiator, forwards `image` and instantiates `brush`, which
		// no declaration fulfills: the hole's scope struct holds `image` as a `public` field, the first `public` declaration
		// naming `Image`, so the comment is above it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Badge.swift": "import Kit\n\n@Instantiable\nstruct Badge: Instantiable {\n    init(image: Image, brush: Brush) {\n        self.image = image\n        self.brush = brush\n    }\n\n    @Forwarded let image: Image\n    @Instantiated let brush: Brush\n}",
					"Screen.swift": Self.publicMockScreenSource(receives: ["@Instantiated let badgeBuilder: Instantiator<Badge>"], imports: ["SafeDI"]),
				], dependencies: ["Kit"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.importLines(["Kit", "SafeDI"]) + """
		#if DEBUG
		extension Screen {
		    \(Self.comment(["Brush", "Image"]))
		    public struct SafeDIMockScope_Badge_brush {
		        public let image: Image
		    }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init() {
		            self.badgeBuilder = nil
		        }

		        init(
		            badgeBuilder: ((Image, Brush) -> Badge)? = nil
		        ) {
		            self.badgeBuilder = badgeBuilder
		        }

		        let badgeBuilder: ((Image, Brush) -> Badge)?
		    }

		    public static func mock(
		        brushBuilder: @escaping (Screen.SafeDIMockScope_Badge_brush) -> Brush,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_brushBuilder = brushBuilder
		        func __safeDI_badgeBuilder(image: Image) -> Badge {
		            let brush: Brush = __safeDI_brushBuilder(SafeDIMockScope_Badge_brush(image: image))
		            return if let safeDIBuilder = safeDIOverrides.badgeBuilder { safeDIBuilder(image, brush) } else { Badge(image: image, brush: brush) }
		        }
		        let badgeBuilder = Instantiator<Badge> {
		            __safeDI_badgeBuilder(image: $0)
		        }
		        return Screen(badgeBuilder: badgeBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_C9FAA72D066A61CB {}
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesCommentOnlyOnPublicMockTier_whenNarrowerTierExists() async throws {
		// P7: the `package` tier names `Window` too, but only the `public` one carries the file's comment.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Token.swift": "package struct Token {}",
					"Screen.swift": Self.publicMockScreenSource(receives: ["@Received let window: Window", "@Received(onlyIfAvailable: true) let token: Token?"]),
				], dependencies: ["Kit"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.importLines(["Kit"]) + """
		#if DEBUG
		extension Screen {
		    \(Self.comment(["Window"]))
		    public static func mock(
		        window: Window
		    ) -> Screen {
		        Screen.mock(window: window, token: nil)
		    }

		    package static func mock(
		        window: Window,
		        token: Token? = nil
		    ) -> Screen {
		        return Screen(window: window, token: token)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_CD2D6415C7929A32 {}
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesOneComment_whenPublicMockDefaultsParameterOfUnreadType() async throws {
		// P8: `tint`, an unread type defaulting to `nil`, is a parameter of the `public` tier, which the file's one comment
		// names with `window`'s `Window`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": "import Kit\n\n@Instantiable(generateMock: .public)\npublic struct Screen: Instantiable {\n    init(window: Window, tint: Palette? = nil) {\n        self.window = window\n        self.tint = tint\n    }\n\n    @Received let window: Window\n    let tint: Palette?\n}",
				], dependencies: ["Kit"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.importLines(["Kit"]) + """
		#if DEBUG
		extension Screen {
		    \(Self.comment(["Palette", "Window"]))
		    public static func mock(
		        tint: Palette? = nil,
		        window: Window
		    ) -> Screen {
		        return Screen(window: window, tint: tint)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_B9A31506F560228F {}
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesOneCommentAboveProvider_whenPublicMockDefaultsParameterOfUnreadTypeToValue() async throws {
		// P8b: the default of `tint`, an unread type, is evaluated by a `@usableFromInline` provider, the first declaration
		// that names `Palette`, above which the file's one comment is.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": "import Kit\n\n@Instantiable(generateMock: .public)\npublic struct Screen: Instantiable {\n    init(window: Window, tint: Palette? = Palette()) {\n        self.window = window\n        self.tint = tint\n    }\n\n    @Received let window: Window\n    let tint: Palette?\n}",
				], dependencies: ["Kit"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.importLines(["Kit"]) + """
		#if DEBUG
		extension Screen {
		    \(Self.comment(["Palette", "Window"]))
		    // These providers evaluate `Screen`'s own defaults outside any actor, since SafeDI sees no isolation on it. If one
		    // reads the state of an actor `Screen` takes from a conformance or a superclass and does not compile, give its
		    // `@Instantiable` `mockAttributes: "@MainActor"` (or that actor).
		    @usableFromInline nonisolated static func __safeDI_publicMockDefault_tint() -> Palette? { Palette() }

		    public static func mock(
		        tint: Palette? = Screen.__safeDI_publicMockDefault_tint(),
		        window: Window
		    ) -> Screen {
		        return Screen(window: window, tint: tint)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_859133E247EC5581 {}
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicMockTier_whenTypeInMockedTreeReceivesIt() async throws {
		// P1b: `Badge`, in the mocked type's tree, receives `window`, which the public mock takes.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Badge.swift": "import Kit\n\n@Instantiable\nstruct Badge: Instantiable {\n    init(window: Window) {\n        self.window = window\n    }\n\n    @Received let window: Window\n}",
					"Screen.swift": Self.publicMockScreenSource(receives: ["@Instantiated let badge: Badge"], imports: []),
				], dependencies: ["Kit"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.importLines(["Kit"]) + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init() {
		            self.badge = nil
		        }

		        init(
		            badge: ((Window) -> Badge)? = nil
		        ) {
		            self.badge = badge
		        }

		        let badge: ((Window) -> Badge)?
		    }

		    \(Self.comment(["Window"]))
		    public static func mock(
		        window: Window,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let badge = if let safeDIBuilder = safeDIOverrides.badge { safeDIBuilder(window) } else { Badge(window: window) }
		        return Screen(badge: badge)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_3CD7306A9A29A31B {}
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	// MARK: B: continued

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingReceiversInitializer_whenReceiverBeneathSeamReceivesConditionallyDeclaredType() async {
		// B1b: `Badge`, beneath the seam, receives `Token`, declared inside an `#if` block, which only `Badge`'s own
		// `internal` initializer mentions. (Where nothing mentions it, the remedy that leads declares the receive on the
		// seam, whose initializer the compiler checks: `generate_throwsError_whenRequiredAliasesFulfillingTypeIsUnproven`.)
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `token: Token`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Token` is `internal` as far as SafeDI can tell: it is declared inside an `#if` block, from which SafeDI takes no access level, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `internal` (`Badge.init(token:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `Token` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; give `Token` a `public` `mockOnly` mock (`@Instantiable(mockOnly: true) public extension Token { public static func mock() -> Token }`), which proves `Token` `public`; declare `Screen` `internal`; build `token` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(
					receives: [],
					instantiates: ["@Instantiated let badge: Badge"],
					extraFeatureFiles: [
						"Token.swift": unrecordedTypeDeclaration("public struct Token {}"),
						"Badge.swift": "@Instantiable\nstruct Badge: Instantiable {\n    init(token: Token) {\n        self.token = token\n    }\n\n    @Received let token: Token\n}",
					],
					hostForwards: nil,
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: C: continued

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTier_whenGenericTypealiasIsMentionedWithUnreadArgument() async throws {
		// C4: `Pair` is recorded `public`; its argument `Image` is unread, so the comment names `Image` alone.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(receives: ["@Received let pair: Pair<Image>"], extraFeatureFiles: ["Pair.swift": "public typealias Pair<T> = (T, T)"], hostForwards: ["pair: Pair<Image>"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Image"], tiers: """
		    public init(pair: Pair<Image>) {
		        let cache = Cache()
		        self.init(pair: pair, cache: cache)
		    }
		""", guardHash: "A922157A7E1D440B"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_ignoresFilePrivateTypealiasOfAnotherFile_whenUnreadModuleDeclaresTheName(integration: MultiModuleIntegration) async throws {
		// C6: `Helper.swift`'s `private typealias Window` names nothing another file can name, so `Screen`'s `Window` is
		// `Kit`'s, which is unread.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received let window: Window"],
				extraFeatureFiles: ["Helper.swift": "private typealias Window = Int\n\nfunc windowCount() -> Int {\n    let count: Window = 1\n    return count\n}"],
				hostForwards: ["window: Window"],
			),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Window"], tiers: """
		    public init(window: Window) {
		        let cache = Cache()
		        self.init(window: window, cache: cache)
		    }
		""", guardHash: "564C5E6539CF6AA0"))
		try expectEveryModuleCompiled(output)
	}

	// MARK: U: continued

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadableSpellingOnPublicTier_whenPublicInitializerOfReceiverMentionsIt() async throws {
		// U2: `Badge`'s `public` initializer mentions `[3 of Int]`, which proves it `public`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: [],
				instantiates: ["@Instantiated let badge: Badge"],
				extraFeatureFiles: ["Badge.swift": "@available(macOS 26.0, *)\n@Instantiable\npublic struct Badge: Instantiable {\n    public init(buffer: [3 of Int]) {\n        self.buffer = buffer\n    }\n\n    @Received let buffer: [3 of Int]\n}"],
				hostForwards: nil,
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], tiers: """
		    public init(buffer: [3 of Int]) {
		        let badge = Badge(buffer: buffer)
		        let cache = Cache()
		        self.init(badge: badge, cache: cache)
		    }
		""", guardHash: "A0D6A17789F28799"))
		try expectEveryModuleCompiled(output)
	}

	// MARK: X: continued

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_countsDeclarationAtItsLevel_whenAdditionalDirectoryDeclaresPackageType() async {
		// X2: a run that names no module reads `Store` from a file without a SafeDI marker in a directory its configuration
		// adds, whose module SafeDI knows no name of: its `package` level counts as declared, and the public seam cannot take
		// it.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):2:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `store: Store`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Store` is declared `package` in a module SafeDI knows no name of. Declare `Store` `public` in a module SafeDI knows no name of; name the module that declares `Store` where SafeDI runs on it (`module_name` under Bazel, `--module-name` otherwise); declare `Screen` `package`; receive `store` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["AdditionalDirectory/Store.swift"]):1:1: note: `Store` is declared `package` here.
			\(fixtures["AdditionalDirectory/Store.swift"]):1:1-1:8: fixit: public
			\(fixtures["Screen.swift"]):9:5: note: `Screen` receives `store: Store` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$ADDITIONAL_DIRECTORY\"])",
					Self.screenSource(receives: ["@Received let store: Store"], imports: []),
				],
				additionalDirectorySwiftFileContent: ["package struct Store {\n    package init() {}\n}"],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesPlainDeclarationCallersCannotSee_whenUnnamedModuleInfoProvesParameterNarrower() async {
		// X3: `Core`'s `.safedi` names no module, so `Feature`'s callers, which read only named modules, cannot see `Store`
		// and would count it `public`: the error is at `Store`'s declaration.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Store.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: the initializer SafeDI generates for it takes its parameters at the access this declaration of `Store` proves, which is in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see it, so they would count `Store` as `public`, and their calls would not match the initializer. Generate that module's module info with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": "package struct Store {\n    package init() {}\n}"], omitsModuleName: true),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let store: Store?"], imports: ["Core"]),
					], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingExactDeclaration_whenItTiesWithConditionallyDeclaredNamesakeAMentionRaises(integration: MultiModuleIntegration) async {
		// S4: `Base` declares `Theme` `package`, and `Shades` declares it `package` inside an `#if` block, which
		// `Painter`'s `package` initializer raises to `package`: the tie goes to `Base`'s declaration, which the error can
		// point at.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `theme: Theme`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Theme` is declared `package` in module `Base`. Declare `Theme` `public` in module `Base`; declare `Screen` `package`; receive `theme` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(Self.path(of: "Theme.swift", in: "Base", fixtures, integration)):1:1: note: `Theme` is declared `package` here.
			\(Self.path(of: "Theme.swift", in: "Base", fixtures, integration)):1:1-1:8: fixit: public
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):10:5: note: `Screen` receives `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Base", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "package struct Theme {\n    package init() {}\n}"]),
					ModuleFixture(name: "Shades", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "#if DEBUG\npackage struct Theme {}\n#endif"]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received let theme: Theme"], imports: ["Base"]),
						"Painter.swift": "import Base\nimport SafeDI\n\n@Instantiable\npackage struct Painter: Instantiable {\n    package init(theme: Theme) {\n        self.theme = theme\n    }\n\n    @Received let theme: Theme\n}",
					], dependencies: ["Base", "Shades"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingMockOnlyMockOnce_whenPublicMockForwardsConditionallyDeclaredType() async {
		// P9: the remedies offer `Token` a `mockOnly` mock, which proves it and lets the mock build it, once.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `token: Token`, which `Service` forwards, and cannot pass `nil` for it, since it is required. `Token` is `internal` as far as SafeDI can tell: it is declared inside an `#if` block, from which SafeDI takes no access level, and every initializer, `instantiate(…)` and mock method that mentions it in this module or on a type that receives it is `internal` (`Service.init(token:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `Token` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; give `Token` a `public` `mockOnly` mock (`@Instantiable(mockOnly: true) public extension Token { public static func mock() -> Token }`), which proves `Token` `public` and lets the mock build it; make `Service.init(token:)` `public`; or use `generateMock: .internal`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"@Instantiable(generateMock: .public)\npublic struct Service: Instantiable {\n    init(token: Token) {\n        self.token = token\n    }\n\n    @Forwarded let token: Token\n}",
					unrecordedTypeDeclaration("public struct Token {\n    public init() {}\n}"),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingMockOnlyMocksOfBothTypes_whenPublicMockForwardsTypeNestedInConditionallyDeclaredType() async {
		// P10: `Space.Token` is capped by `Space`, declared inside an `#if` block: a `mockOnly` mock of `Space` proves it,
		// and one of `Space.Token` lets the mock build it.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `token: Space.Token`, which `Service` forwards, and cannot pass `nil` for it, since it is required. `Space.Token` is nested in `Space`, which is `internal` as far as SafeDI can tell: it is declared inside an `#if` block, from which SafeDI takes no access level, and no initializer, `instantiate(…)` or mock method SafeDI records mentions it. Mention `Space` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; give `Space` a `public` `mockOnly` mock (`@Instantiable(mockOnly: true) public extension Space { public static func mock() -> Space }`), which proves `Space` `public`; give `Space.Token` a `mockOnly` mock; or use `generateMock: .internal`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"@Instantiable(generateMock: .public)\npublic struct Service: Instantiable {\n    init(token: Space.Token) {\n        self.token = token\n    }\n\n    @Forwarded let token: Space.Token\n}",
					unrecordedTypeDeclaration("public enum Space {}") + "\n\nextension Space {\n    public struct Token {\n        public init() {}\n    }\n}",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesPlainDeclarationCallersCannotSee_whenAdditionalDirectoryProvesParameterNarrowerUnderTargetGraph() async {
		// X4: under the plugin's target graph, `Screen`'s callers compute its signature without the directory its
		// configuration adds, so they would count `Store` as `public`: the error is at `Store`'s declaration.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["AdditionalDirectory/Store.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: the initializer SafeDI generates for it takes its parameters at the access this declaration of `Store` proves, which is in a directory this module's `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see it, so they would count `Store` as `public`, and their calls would not match the initializer. Declare `Store` in a file of this module, or of a module it depends on.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$ADDITIONAL_DIRECTORY\"])",
					Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let store: Store?"], imports: []),
				],
				additionalDirectorySwiftFileContent: ["package struct Store {\n    package init() {}\n}"],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				pluginTargetGraph: Self.featureTargetGraph,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesPlainDeclarationCallersCannotSee_whenAdditionalDirectoryProvesPublicMockParameterNarrowerUnderTargetGraph() async {
		// X5: the public mock's twin of X4.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["AdditionalDirectory/Store.swift"]):1:1: error: SafeDI cannot generate the public mock of `Screen`: it takes its parameters at the access this declaration of `Store` proves, which is in a directory this module's `#SafeDIConfiguration` adds, and the modules that call the mock cannot see it, so they would count `Store` as `public`, and their calls would not match the mock. Declare `Store` in a file of this module, or of a module it depends on.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$ADDITIONAL_DIRECTORY\"])",
					Self.publicMockScreenSource(receives: ["@Received(onlyIfAvailable: true) let store: Store?"], imports: []),
				],
				additionalDirectorySwiftFileContent: ["package struct Store {\n    package init() {}\n}"],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				pluginTargetGraph: Self.featureTargetGraph,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesPlainDeclarationCallersCannotSee_whenUnnamedModuleInfoProvesPublicMockParameterNarrower() async {
		// X6: the public mock's twin of X3.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Store.swift"]):1:1: error: SafeDI cannot generate the public mock of `Screen`: it takes its parameters at the access this declaration of `Store` proves, which is in a module whose SafeDI module info names no module, and the modules that call the mock, which compute its signature from the modules this module's module info names, cannot see it, so they would count `Store` as `public`, and their calls would not match the mock. Generate that module's module info with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": "package struct Store {\n    package init() {}\n}"], omitsModuleName: true),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.publicMockScreenSource(receives: ["@Received(onlyIfAvailable: true) let store: Store?"], imports: ["Core"]),
					], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesEarliestPlainDeclarationCallersCannotSee_whenTwoProveParametersNarrower() async {
		// X7: `Store` and `Token` each prove a parameter the callers would take on the `public` tier: the error is at the
		// earlier declaration by source location, `Token`'s, although `Screen` receives `store` first.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Types.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: the initializer SafeDI generates for it takes its parameters at the access this declaration of `Token` proves, which is in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see it, so they would count `Token` as `public`, and their calls would not match the initializer. Generate that module's module info with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": "package struct Token {\n    package init() {}\n}\n\npackage struct Store {\n    package init() {}\n}"], omitsModuleName: true),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let store: Store?", "@Received(onlyIfAvailable: true) let token: Token?"], imports: ["Core"]),
					], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: F: continued

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNarrowestDeclaration_whenSixModulesDeclareTypeAtDifferentLevels(integration: MultiModuleIntegration) async {
		// F6: of six modules that declare `Theme`, declared in an order neither their names nor their levels give, one
		// declares it `package`: SafeDI takes it, and notes it.
		// A `.safedi` records only the declarations only its package can name, so under `.moduleInfo` SafeDI reads `Cedar`'s
		// alone.
		let levels = ["Ash": "public", "Birch": "public", "Cedar": "package", "Dogwood": "public", "Elm": "public", "Fir": "public"]
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let cedarPath = Self.path(of: "Theme.swift", in: "Cedar", fixtures, integration)
			let declarationsAndRemedies = switch integration {
			case .moduleInfo:
				"`Theme` is declared `package` in module `Cedar`. Declare `Theme` `public` in module `Cedar`;"
			case .swiftPackagePlugin:
				"`Theme` is declared `public` in module `Ash`, `public` in module `Birch`, `package` in module `Cedar`, `public` in module `Dogwood`, `public` in module `Elm`, and `public` in module `Fir`, and SafeDI takes the narrowest. Declare `Theme` `public` in module `Cedar`; spell the type with its module where it is mentioned (`Ash.Theme`), so that it names that module's declaration;"
			}
			return """
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):8:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `theme: Theme`, which `Screen` receives, and cannot pass `nil` for it, since it is required. \(declarationsAndRemedies) declare `Screen` `package`; receive `theme` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(cedarPath):1:1: note: `Theme` is declared `package` here.
			\(cedarPath):1:1-1:8: fixit: public
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):15:5: note: `Screen` receives `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: ["Elm", "Cedar", "Fir", "Ash", "Dogwood", "Birch"].map { name in
					ModuleFixture(name: name, packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "\(levels[name]!) struct Theme {}"])
				} + [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received let theme: Theme"], imports: ["Ash", "Birch", "Cedar", "Dogwood", "Elm", "Fir"]),
					], dependencies: ["Elm", "Cedar", "Fir", "Ash", "Dogwood", "Birch"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A target graph that places the run's own files in module `Feature`, of package `shop`, which depends on nothing.
	private static let featureTargetGraph: @Sendable ([String]) -> PluginTargetGraph = { inputSwiftFilePaths in
		PluginTargetGraph(
			target: PluginTargetGraph.Target(moduleName: "Feature", packageID: "shop", sourceFilePaths: inputSwiftFilePaths, dependencyModuleNames: []),
			dependencyTargets: [],
		)
	}

	/// `Kit`, a module SafeDI does not read: one that does not run SafeDI under `.moduleInfo`, and a fetched package under
	/// the plugin, in package `Toolkit`. Its types are all `public`.
	private static func kit(files: [String: String] = kitFiles) -> ModuleFixture {
		ModuleFixture(name: "Kit", packageName: "Toolkit", swiftFileContentByFilePath: files, isCheckoutPackage: true, runsSafeDI: false)
	}

	private static let kitFiles = [
		"Window.swift": "public struct Window {\n    public init() {}\n\n    public struct Scene {\n        public init() {}\n    }\n}",
		"Image.swift": "public struct Image {\n    public init() {}\n}",
		"Renderer.swift": "public protocol Renderer {}",
		"Brush.swift": "public struct Brush {\n    public init() {}\n}",
		"Canvas.swift": "public struct Canvas {\n    public init() {}\n}",
		"Palette.swift": "public struct Palette {\n    public init() {}\n}",
	]

	/// The source of `Feature`'s seam `Screen`, declared `access`, whose `internal` initializer takes `receives` – each a
	/// property declaration – and the `Cache` it instantiates, with `instantiates` before it.
	private static func screenSource(access: String = "public", receives: [String], instantiates: [String] = [], imports: [String] = ["Kit"]) -> String {
		let declarations = receives + instantiates + ["@Instantiated let cache: Cache"]
		let properties = declarations.map { declaration -> (label: String, type: String) in
			let property = declaration[declaration.range(of: " let ")!.upperBound...]
			return (String(property.prefix { $0 != ":" }), property.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces))
		}
		let parameters = properties.map { "\($0.label): \(GraphFuzzerSpelling.isFunctionType($0.type) ? "@escaping " : "")\($0.type)" }.joined(separator: ", ")
		return imports.map { "import \($0)\n" }.joined() + """

		@Instantiable(generateDependencyTree: true)
		\(access) struct Screen: Instantiable {
		    init(\(parameters)) {
		\(properties.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n"))
		    }

		\(declarations.map { "    \($0)" }.joined(separator: "\n"))
		}

		@Instantiable
		struct Cache: Instantiable {
		    init() {}
		}
		"""
	}

	/// The source of `Feature`'s `Screen`, with `generateMock: .public`, whose `internal` initializer takes `receives`.
	private static func publicMockScreenSource(receives: [String], imports: [String] = ["Kit"]) -> String {
		let properties = receives.map { declaration -> (label: String, type: String) in
			let property = declaration[declaration.range(of: " let ")!.upperBound...]
			return (String(property.prefix { $0 != ":" }), property.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces))
		}
		return imports.map { "import \($0)\n" }.joined() + """

		@Instantiable(generateMock: .public)
		public struct Screen: Instantiable {
		    init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
		\(properties.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n"))
		    }

		\(receives.map { "    \($0)" }.joined(separator: "\n"))
		}
		"""
	}

	/// `Kit`, `Feature` with the seam `Screen` (`screenSource`) and `extraFeatureFiles`, and, unless `hostForwards` is
	/// `nil`, `App`, in another package, whose root builds a `Host` through an instantiator: the host forwards
	/// `hostForwards` and instantiates `Screen`, which `App` builds with its generated `public` initializer.
	private static func screenModules(
		receives: [String],
		instantiates: [String] = [],
		extraFeatureFiles: [String: String] = [:],
		hostForwards: [String]?,
		featureImportsSafeDI: Bool = false,
		featureConditions: [String] = [],
		appFiles: [String: String] = [:],
	) -> [ModuleFixture] {
		var modules = [
			kit(),
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContentByFilePath: ["Screen.swift": screenSource(receives: receives, instantiates: instantiates, imports: featureImportsSafeDI ? ["Kit", "SafeDI"] : ["Kit"])].merging(extraFeatureFiles) { first, _ in first },
				dependencies: ["Kit"],
				activeCompilationConditions: featureConditions,
			),
		]
		if let hostForwards {
			let forwarded = hostForwards.map { forward -> (label: String, type: String) in
				(String(forward.prefix { $0 != ":" }), forward.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces))
			}
			let host = """
			import Feature
			import Kit
			import SafeDI

			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(hostBuilder: Instantiator<Host>) {
			        self.hostBuilder = hostBuilder
			    }

			    @Instantiated let hostBuilder: Instantiator<Host>
			}

			@Instantiable
			public struct Host: Instantiable {
			    public init(\((forwarded.map { "\($0.label): \($0.type)" } + ["screen: Screen"]).joined(separator: ", "))) {
			\((forwarded.map(\.label) + ["screen"]).map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
			    }

			\(forwarded.map { "    @Forwarded let \($0.label): \($0.type.replacingOccurrences(of: "@escaping ", with: ""))" }.joined(separator: "\n"))
			    @Instantiated let screen: Screen
			}
			"""
			modules.append(ModuleFixture(name: "App", packageName: "Store", swiftFileContentByFilePath: ["Host.swift": host].merging(appFiles) { first, _ in first }, dependencies: ["Kit", "Feature"]))
		}
		return modules
	}

	/// `Kit`'s `Window`, `Feature`'s `@Instantiable` `Badge` declared `badgeAccess` inside an extension of it, and the seam
	/// `Screen`, which receives `badge`, which `App`'s root builds.
	private static func badgeInWindowModules(badgeAccess: String) -> [ModuleFixture] {
		[
			kit(),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
				"Screen.swift": screenSource(receives: ["@Received let badge: Window.Badge"]),
				"Badge.swift": "import Kit\n\nextension Window {\n    @Instantiable\n    \(badgeAccess) final class Badge: Instantiable {\n        public init() {}\n    }\n}",
			], dependencies: ["Kit"]),
			ModuleFixture(name: "App", packageName: "Store", swiftFileContentByFilePath: [
				"Root.swift": "import Feature\nimport Kit\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let badge: Window.Badge", "@Instantiated let screen: Screen"]),
			], dependencies: ["Kit", "Feature"]),
		]
	}

	/// `Core`, in `Feature`'s package, with `public enum Space` and a `package extension Space`, in files without a SafeDI
	/// marker, that declares `Config` and `ID`; `Feature`'s seam `Screen` receives `receives`.
	private static func spaceInCoreModules(receives: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: [
				"Space.swift": "public enum Space {}",
				"SpaceExtension.swift": "package extension Space {\n    struct Config {\n        init() {}\n    }\n\n    typealias ID = Int\n}",
			]),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
				"Screen.swift": screenSource(receives: receives, imports: ["Core"]),
			], dependencies: ["Core"]),
		]
	}

	/// The comment the generated file carries above its first `public` declaration that names a type of `names`.
	private static func comment(_ names: [String]) -> String {
		let list = names.map { "`\($0)`" }.joinedAsTestList
		return names.count == 1
			? "// SafeDI counts \(list) as `public`: no module it reads declares it narrower. If \(list) is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies."
			: "// SafeDI counts \(list) as `public`: no module it reads declares them narrower. If one is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies."
	}

	/// `Feature`'s generated files under `integration` for the seam `Screen`, whose extension holds `tiers`, with the
	/// comment naming `comment` above the first tier under `.moduleInfo`, which runs without a target graph.
	private static func screenFiles(_ integration: MultiModuleIntegration, comment names: [String], imports: [String] = ["Kit"], tiers: String, guardHash: String) -> [String: String] {
		let commentLine = integration == .moduleInfo && !names.isEmpty ? "    \(comment(names))\n" : ""
		// The comment is above the first `public` declaration that names one of `names`: the first tier, or where `tiers`
		// marks it.
		let commentedTiers = tiers.contains("    {COMMENT}\n") ? tiers.replacingOccurrences(of: "    {COMMENT}\n", with: commentLine) : commentLine + tiers
		let code = generatedFileHeader + importLines(imports) + """
		extension Screen {
		\(commentedTiers)
		}

		extension Screen {
		    public enum __safeDI_Screen_\(guardHash) {}
		}
		"""
		return [integration == .moduleInfo ? "Feature.swift" : "Screen+SafeDI.swift": code]
	}

	private static func importLines(_ moduleNames: [String]) -> String {
		moduleNames.map { "#if canImport(\($0))\nimport \($0)\n#endif\n" }.joined() + "\n"
	}

	/// The path a diagnostic names `file` of `module` by under `integration`.
	private static func path(of file: String, in module: String, _ fixtures: [String: FixturePaths], _ integration: MultiModuleIntegration) -> String {
		guard let moduleFixtures = fixtures[module] else { return "<\(module) did not run>/\(file)" }
		return switch integration {
		case .moduleInfo:
			moduleFixtures[file]
		case .swiftPackagePlugin:
			NormalizedFilePath(moduleFixtures.compilerPath(of: file)).path
		}
	}

	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.moduleName) == output.moduleNames, sourceLocation: sourceLocation)
		#expect(compilation.failure == nil, sourceLocation: sourceLocation)
	}

	/// Expects every module before `module` to compile, and `module`'s generated code to fail to compile alongside its
	/// inputs with an error containing `text`.
	private func expectModuleCompilationFails(_ output: MultiModuleTestOutput, module: String, containing text: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		let failure = try #require(compilation.failure, sourceLocation: sourceLocation)
		#expect(failure.moduleName == module, sourceLocation: sourceLocation)
		#expect(compilation.modules.dropLast().allSatisfy { $0.failure == nil }, sourceLocation: sourceLocation)
		switch failure.failure {
		case .generatedCodeFailedAlongsideInputs:
			break
		case .inputsFailedOnTheirOwn, nil:
			Issue.record("Expected \(module)'s generated code to fail to compile, but its failure is \(String(describing: failure.failure)).", sourceLocation: sourceLocation)
		}
		#expect(failure.standardError.contains(text), "Unexpected compiler output \(failure.standardError)", sourceLocation: sourceLocation)
	}
}

extension [String] {
	/// The strings as a list: two joined by "and", more with commas and a final "and", as the tool joins them.
	fileprivate var joinedAsTestList: String {
		count > 2 ? "\(dropLast().joined(separator: ", ")), and \(self[count - 1])" : joined(separator: " and ")
	}
}
