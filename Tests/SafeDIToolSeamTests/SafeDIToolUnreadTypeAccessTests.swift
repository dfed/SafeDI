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

/// A type no declaration SafeDI reads declares counts as `public` (decision 54): a framework's, a fetched package's, or
/// a first-party module's that does not run SafeDI. A type declared inside an extension counts exactly, at its own level
/// capped by the extended type's; one declared inside an `#if` block counts as the clauses SafeDI scans declare it, as
/// `@Instantiable` content does; a `typealias` is recorded as any plain declaration is. Without a target graph, the generated file names the types it
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_window window: Window) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_window: @autoclosure @escaping () -> Window) {
		        let window = LazilyInstantiated<Window>(__safeDI_window)
		        let badge = Badge(window: window.instance)
		        let cache = Cache()
		        self.init(badge: badge, cache: cache)
		    }
		""", guardHash: "48814468D463AD3C"))
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_image image: Image, __safeDI_window window: Window) {
		        let cache = Cache()
		        self.init(image: image, window: window, cache: cache)
		    }
		""", guardHash: "883DBB4A829093BB"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTierAsOptionalParameter_whenSeamReceivesItOnlyIfAvailable() async throws {
		// A4: received only if available, the unread type is an optional parameter of the public tier.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(receives: ["@Received(onlyIfAvailable: true) let window: Window?"], hostForwards: ["window: Window"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Window"], tiers: """
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_window window: Window?) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_windowBuilder windowBuilder: ErasedInstantiator<(), Window>) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_scene scene: Window.Scene) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_images images: [Image], __safeDI_render render: @escaping (Image) -> Void, __safeDI_pair pair: (Image, Int), __safeDI_kind kind: Window.Type) {
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
	mutating func generate_throwsErrorNamingGenericArgument_whenGenericArgumentOfEnclosingTypeIsRecordedPackageTypeRequiredOnPublicSeam() async {
		// `Box<Secret>.Bar` names `Secret`, as `[Secret]` does: the compiler checks it against the initializer's access.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `token: Box<Secret>.Bar`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Secret` is declared `package`. Declare `Secret` `public`; declare `Screen` `package`; receive `token` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Secret.swift"]):1:1: note: `Secret` is declared `package` here.
			\(fixtures["Feature"]!["Secret.swift"]):1:1-1:8: fixit: public
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `token: Box<Secret>.Bar` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(receives: ["@Received let token: Box<Secret>.Bar"], extraFeatureFiles: ["Secret.swift": "package struct Secret {}", "Box.swift": "public struct Box<T> {\n    public struct Bar {}\n}"], hostForwards: nil),
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_renderer renderer: any Renderer, __safeDI_sendableRenderer sendableRenderer: any (Renderer & Sendable)) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_window window: Kit.Window) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_store store: Store) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_window window: Window) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_badge badge: Window.Badge) {
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
		    @frozen public enum SafeDIScope_UserService {
		        case service(service_Values)

		        public struct service_Values {
		            public let image: Image
		            internal let cache: Cache
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_image image: Image, __safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let cache = Cache()
		        let service: any UserService = __safeDI_userServiceBuilder(.service(SafeDIScope_UserService.service_Values(image: image, cache: cache)))
		        self.init(image: image, service: service, cache: cache)
		    }
		""", guardHash: "3EA8086D06C81EDC"))
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
		    @frozen public enum SafeDIScope_Renderer {
		        case renderer(renderer_Values)

		        public struct renderer_Values {
		            internal let cache: Cache
		        }
		    }

		    {COMMENT}
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_rendererBuilder: @escaping (SafeDIScope_Renderer) -> any Renderer) {
		        let cache = Cache()
		        let renderer: any Renderer = __safeDI_rendererBuilder(.renderer(SafeDIScope_Renderer.renderer_Values(cache: cache)))
		        self.init(renderer: renderer, cache: cache)
		    }
		""", guardHash: "16232CF7C01DA9E6"))
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_store store: Store) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_mode mode: ChatService.TurnTakingMode) {
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
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_config: nil, __safeDI_id: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_config config: Space.Config?, __safeDI_id id: Space.ID?) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_badge badge: Window.Badge) {
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
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_ledger: nil, __safeDI_label: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_ledger ledger: Shelf.Ledger?, __safeDI_label label: Shelf.Label?) {
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
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_ledger: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_ledger ledger: Space.Ledger?) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_ledger ledger: Window.Scene.Ledger) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_userID userID: UserID) {
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
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_token: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_token token: Token?) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_id id: Space.ID) {
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
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `handlerBuilder: @escaping (SafeDIScope_Handler) -> Handler`, the builder for `Screen`'s `handler: Handler`, which no @Instantiable declaration that module `Feature` can see fulfills. `Handler` is declared `internal`. Declare `Handler` `public`; declare `Screen` `internal`; make an @Instantiable declaration that fulfills `Handler` one module `Feature` reads, so `Screen`'s tree builds it; or declare the dependency tree on an `internal` type that instantiates `Screen`.
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_result result: Swift.Result<Int, any Error>) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_interval interval: DateInterval) {
		        let cache = Cache()
		        self.init(interval: interval, cache: cache)
		    }
		""", guardHash: "A40FBF1797F7E662"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenOneDependencyDeclaresTypePublicAndAnotherPackageInsideConditionalBlock(integration: MultiModuleIntegration) async {
		// S2: `Shades`'s `package` `Theme` inside the clause `DEBUG` selects, which both runs report, is narrower than
		// `Paints`'s `public` one. `Paints`'s `.safedi` keeps no `public` declaration nothing in it mentions, so only the
		// plugin, which reads `Paints`'s files, names both.
		let cause = switch integration {
		case .moduleInfo:
			"`Theme` is declared `package` in module `Shades`. Declare `Theme` `public` in module `Shades`;"
		case .swiftPackagePlugin:
			"`Theme` is declared `public` in module `Paints` and `package` in module `Shades`, and SafeDI takes the narrower. Declare `Theme` `public` in module `Shades`; spell the type with its module where it is mentioned (`Paints.Theme`), so that it names that module's declaration;"
		}
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):4:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `theme: Theme`, which `Screen` receives, and cannot pass `nil` for it, since it is required. \(cause) declare `Screen` `package`; receive `theme` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(Self.path(of: "Theme.swift", in: "Shades", fixtures, integration)):2:1: note: `Theme` is declared `package` here.
			\(Self.path(of: "Theme.swift", in: "Shades", fixtures, integration)):2:1-2:8: fixit: public
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):11:5: note: `Screen` receives `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Paints", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "public struct Theme {}"]),
					ModuleFixture(name: "Shades", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "#if DEBUG\npackage struct Theme {}\n#endif"], activeCompilationConditions: ["DEBUG"]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received let theme: Theme"], imports: ["Paints", "Shades"]),
					], dependencies: ["Paints", "Shades"], activeCompilationConditions: ["DEBUG"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypeOnPublicTier_whenPlatformBlockDeclaresItPublicInOneClause(integration: MultiModuleIntegration) async throws {
		// IF8: `Paints` declares `Theme` `public` inside a platform block, every clause of which SafeDI reads: the plugin
		// reads the `public` record, and `Paints`'s `.safedi` keeps no `public` one, so `.moduleInfo` reads no declaration of
		// `Theme`, which counts as `public` too. Both put `theme` on the public tier.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Paints", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": platformConditionedDeclaration("public struct Theme {}")]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"], imports: ["Paints"]),
				], dependencies: ["Paints"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Theme"], imports: ["Paints"], tiers: """
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_theme theme: Theme?) {
		        let cache = Cache()
		        self.init(theme: theme, cache: cache)
		    }
		""", guardHash: "717280493A095F31"))
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_zebra zebra: Canvas, __safeDI_apple apple: Window.Scene, __safeDI_mango mango: Brush, __safeDI_kiwi kiwi: Image, __safeDI_berry berry: Palette, __safeDI_fig fig: Window, __safeDI_date date: [Brush]) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_window window: Window) {
		        self.init(__safeDI_window: window, __safeDI_token: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_window window: Window, __safeDI_token token: Token?) {
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
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_palette: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_palette palette: Palette?) {
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
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_inner: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_inner inner: Outer.Inner?) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_palette palette: Palette) {
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

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesReceivedTypeOnPackageTier_whenDependencysMarkerFreeFileDeclaresPackageTypeWithNameInBackticks(integration: MultiModuleIntegration) async throws {
		// W5, D3.9: the text search for a name after its keyword finds `` `Protocol` ``, so the file is parsed and its
		// declaration recorded, under the plugin, which reads `Core`'s files for `Feature`, as under Bazel, which parses a
		// file that holds the word `package` whatever names the search finds.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Protocol.swift": "package struct `Protocol` {}"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let kind: `Protocol`?"], imports: ["Core"]),
				], dependencies: ["Core"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: [], imports: ["Core"], tiers: """
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_kind: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_kind kind: `Protocol`?) {
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
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_commented: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_commented commented: Commented?) {
		        let cache = Cache()
		        self.init(commented: commented, cache: cache)
		    }
		""", guardHash: "C7131F41728A076A"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_omitsReceivedTypeFromPublicTier_whenDependencysMarkerFreeFileDeclaresPackageTypeWithNameNeedlesslyInBackticks(integration: MultiModuleIntegration) async throws {
		// D3.1a: the text search finds `` `Token` ``, and the declaration in backticks and the mention without them name one
		// type, which is `package`, so the `public` tier omits `token`, where it took it, counting `Token` `public`, and
		// failed to compile.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.tokenModules(declaration: "package struct `Token` {}", receive: "@Received(onlyIfAvailable: true) let token: Token?"),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: [], imports: ["Core"], tiers: """
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_token: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_token token: Token?) {
		        let cache = Cache()
		        self.init(token: token, cache: cache)
		    }
		""", guardHash: "16885A1AAD60582A"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingDeclaringModule_whenPublicSeamRequiresPackageTypeDependencyDeclaresWithNameNeedlesslyInBackticks(integration: MultiModuleIntegration) async {
		// D3.1b: the receive is required, so the `public` tier cannot omit it, where the compiler rejected the generated
		// initializer. The error names the type as its declaration spells it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `token: Token`, which `Screen` receives, and cannot pass `nil` for it, since it is required. ``Token`` is declared `package` in module `Core`. Declare ``Token`` `public` in module `Core`; declare `Screen` `package`; receive `token` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(Self.path(of: "Token.swift", in: "Core", fixtures, integration)):1:1: note: ``Token`` is declared `package` here.
			\(Self.path(of: "Token.swift", in: "Core", fixtures, integration)):1:1-1:8: fixit: public
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):10:5: note: `Screen` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.tokenModules(declaration: "package struct `Token` {}", receive: "@Received let token: Token"),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesNoTypeInComment_whenSeamsModuleDeclaresPublicTypeWithNameNeedlesslyInBackticksInMarkerFreeFile() async throws {
		// D3.2: `Token` is read, `public`, so the comment that names the types SafeDI counts `public` is gone.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [Self.featureDeclaringToken("public struct `Token` {}")],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], imports: [], tiers: """
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_token token: Token) {
		        let cache = Cache()
		        self.init(token: token, cache: cache)
		    }
		""", guardHash: "1EB503BFA23A82BA"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesTypeInComment_whenSeamsModuleDeclaresItAfterCommentFollowingKeywordInMarkerFreeFile() async throws {
		// D3.3: a stated limit: the text search does not find `Token` behind a comment, so SafeDI reads no declaration of
		// it, counts it `public`, and names it in the comment.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [Self.featureDeclaringToken("public struct /* note */ Token {}")],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Token"], imports: [], tiers: """
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_token token: Token) {
		        let cache = Cache()
		        self.init(token: token, cache: cache)
		    }
		""", guardHash: "1EB503BFA23A82BA"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_omitsReceivedTypeFromWiderTiers_whenSeamsModuleDeclaresInternalTypeWithNameNeedlesslyInBackticksInFileWithMarker(integration: MultiModuleIntegration) async throws {
		// D3.5: a file that mentions `@Instantiable` is parsed whatever the text search finds, and the declaration in
		// backticks proves the mention, `internal`, as one in a file without a marker does.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [Self.featureDeclaringToken("// Read by SafeDI: it mentions @Instantiable.\nstruct `Token` {}", receive: "@Received(onlyIfAvailable: true) let token: Token?")],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: [], imports: [], tiers: """
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_token: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    internal init(__safeDI_token token: Token?) {
		        let cache = Cache()
		        self.init(token: token, cache: cache)
		    }
		""", guardHash: "BEC07F255DE644F9"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assertsDecisionSelectingDeclaration_whenDependencysMarkerFreeFileDeclaresTypeWithNameNeedlesslyInBackticksInSelectedClause() async throws {
		// D3.7: under the plugin, `Feature` reads `Core`'s file, whose `FLAG` clause declares the `package` `Token` its tiers
		// rely on, so `Feature`'s generated code asserts the decision, whichever way the name is spelled.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.tokenModules(
				declaration: "#if FLAG\npackage struct `Token` {}\n#else\nstruct `Token` {}\n#endif",
				receive: "@Received(onlyIfAvailable: true) let token: Token?",
				conditions: ["FLAG"],
			),
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.swiftPackagePlugin, comment: [], imports: ["Core"], assertions: Self.activeAssertion("FLAG"), tiers: """
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_token: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_token token: Token?) {
		        let cache = Cache()
		        self.init(token: token, cache: cache)
		    }
		""", guardHash: "16885A1AAD60582A"))
		try expectEveryModuleCompiled(output)
	}

	// MARK: B: a declaration inside an `#if` block counts as the clause SafeDI reads declares it

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingModule_whenDependencysConditionallyDeclaredPackageTypeIsRequiredOnPublicSeam(integration: MultiModuleIntegration) async {
		// B5: `Core`'s `package struct Token` inside a platform-conditioned block is read, from `Core`'s `.safedi` or its
		// files, at its declared level.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `token: Token`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Token` is declared `package` in module `Core`. Declare `Token` `public` in module `Core`; declare `Screen` `package`; receive `token` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(Self.path(of: "Token.swift", in: "Core", fixtures, integration)):2:1: note: `Token` is declared `package` here.
			\(Self.path(of: "Token.swift", in: "Core", fixtures, integration)):2:1-2:8: fixit: public
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):10:5: note: `Screen` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Token.swift": platformConditionedDeclaration("package struct Token {}")]),
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
		// B6: `Feature`'s `internal` `Handler` inside the clause `DEBUG` selects is on the `internal` tier only, and the
		// tool asserts `DEBUG`; `App` calls the `public` one, computing the same signature from `Feature`'s `.safedi`.
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
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], assertions: Self.activeAssertion("DEBUG"), tiers: """
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_handler: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    internal init(__safeDI_handler handler: Handler?) {
		        let cache = Cache()
		        self.init(handler: handler, cache: cache)
		    }
		""", guardHash: "ABC0ED47A0A8DC7D"))
		try expectEveryModuleCompiled(output)
	}

	// MARK: X: a declaration of a module SafeDI knows no name of

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
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_store: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_store store: Store?) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_window window: Window) {
		        let cache = Cache()
		        self.init(window: window, cache: cache)
		    }
		""", guardHash: "564C5E6539CF6AA0"))
		#expect(output.modules["Shell"]?.generatedFiles == ["Shell.swift": generatedFileHeader + Self.importLines(["Feature", "Kit"]) + """
		extension Frame {
		    \(Self.comment(["Window"]))
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_window: @autoclosure @escaping () -> Window) {
		        let window = LazilyInstantiated<Window>(__safeDI_window)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_564C5E6539CF6AA0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen(__safeDI_window: window.instance)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(screen: screen)
		    }
		}

		extension Frame {
		    public enum __safeDI_Frame_48814468D463AD3C {}
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
		    @frozen public enum SafeDIMockScope_Brush {
		        case badgeBuilder_brush(badgeBuilder_brush_Values)

		        public struct badgeBuilder_brush_Values {
		            public let image: Image
		        }
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
		        brushBuilder: @escaping (Screen.SafeDIMockScope_Brush) -> Brush,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_brushBuilder = brushBuilder
		        func __safeDI_badgeBuilder(image: Image) -> Badge {
		            let brush: Brush = __safeDI_brushBuilder(.badgeBuilder_brush(SafeDIMockScope_Brush.badgeBuilder_brush_Values(image: image)))
		            return if let safeDIBuilder = safeDIOverrides.badgeBuilder { safeDIBuilder(image, brush) } else { Badge(image: image, brush: brush) }
		        }
		        let badgeBuilder = Instantiator<Badge> {
		            __safeDI_badgeBuilder(image: $0)
		        }
		        return Screen(badgeBuilder: badgeBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_79375297172AEAB4 {}
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
	mutating func generate_throwsErrorNamingReceiversInitializer_whenReceiverBeneathSeamReceivesTypeSafeDICannotRead() async {
		// B1b: `Badge`, beneath the seam, receives `[3 of Int]`, whose spelling SafeDI cannot read, which only `Badge`'s own
		// `internal` initializer mentions. (Where nothing mentions it, the remedy that leads declares the receive on the
		// seam, whose initializer the compiler checks: `generate_throwsError_whenRequiredAliasesFulfillingTypeIsUnproven`.)
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `token: [3 of Int]`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `internal` (`Badge.init(token:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Screen` `internal`; build `token` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `token: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(
					receives: [],
					instantiates: ["@Instantiated let badge: Badge"],
					extraFeatureFiles: [
						"Badge.swift": "@Instantiable\nstruct Badge: Instantiable {\n    init(token: [3 of Int]) {\n        self.token = token\n    }\n\n    @Received let token: [3 of Int]\n}",
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_pair pair: Pair<Image>) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_window window: Window) {
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_buffer: @autoclosure @escaping () -> [3 of Int]) {
		        let buffer = LazilyInstantiated<[3 of Int]>(__safeDI_buffer)
		        let badge = Badge(buffer: buffer.instance)
		        let cache = Cache()
		        self.init(badge: badge, cache: cache)
		    }
		""", guardHash: "5BD700ACBBEE0733"))
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

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingFirstDeclaration_whenItTiesWithConditionallyDeclaredNamesake(integration: MultiModuleIntegration) async {
		// S4: `Base` declares `Theme` `package`, and `Shades` declares it `package` inside an `#if` block, which SafeDI
		// reads exactly too: the tie goes to the first declaration, `Base`'s, which the error points at.
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
	mutating func generate_namesEarliestPlainDeclarationCallersCannotSee_whenAdditionalDirectoryProvesSixParametersNarrowerUnderTargetGraph() async {
		// X4 with six parameters, each proved `package` by a declaration in a file of its own in the directory the
		// configuration adds: the error is at the earliest declaration by source location, `T1`'s, which is the third
		// parameter by label, not the first or the last.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["AdditionalDirectory/T1.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: the initializer SafeDI generates for it takes its parameters at the access this declaration of `T1` proves, which is in a directory this module's `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see it, so they would count `T1` as `public`, and their calls would not match the initializer. Declare `T1` in a file of this module, or of a module it depends on.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$ADDITIONAL_DIRECTORY\"])",
					Self.screenSource(
						receives: [
							"@Received(onlyIfAvailable: true) let alpha: T4?",
							"@Received(onlyIfAvailable: true) let beta: T2?",
							"@Received(onlyIfAvailable: true) let delta: T1?",
							"@Received(onlyIfAvailable: true) let echo: T6?",
							"@Received(onlyIfAvailable: true) let gamma: T3?",
							"@Received(onlyIfAvailable: true) let zeta: T5?",
						],
						imports: [],
					),
				],
				additionalDirectorySwiftFileContent: (1...6).map { "package struct T\($0) {\n    package init() {}\n}" },
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

	// MARK: IF: a plain declaration inside an `#if` block counts as the clause SafeDI selects declares it

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypeAtSpelledLevel_whenFlagSelectsClauseDeclaringIt(integration: MultiModuleIntegration) async {
		// IF1: `FLAG` is reported, so the clause that declares `Theme` `package` is selected, and `Theme` is `package`
		// exactly, with the note and fix-it at its declaration inside the block.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let themePath = Self.path(of: "Theme.swift", in: "Core", fixtures, integration)
			return """
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `theme: Theme`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Theme` is declared `package` in module `Core`. Declare `Theme` `public` in module `Core`; declare `Screen` `package`; receive `theme` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(themePath):2:1: note: `Theme` is declared `package` here.
			\(themePath):2:1-2:8: fixit: public
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):10:5: note: `Screen` receives `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.coreAndFeatureModules(coreTheme: "#if FLAG\npackage struct Theme {}\n#endif", receives: ["@Received let theme: Theme"], conditions: ["FLAG"]),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_countsTypeUnread_whenFlagSkipsClauseDeclaringIt(integration: MultiModuleIntegration) async throws {
		// IF2: `FLAG` is not reported, so `Core`'s only declaration of `Theme` is in a clause SafeDI skips: `Theme` is no
		// type SafeDI reads a declaration of, and `Kit`'s `Theme` counts as `public`. The run that reads `Core`'s file
		// asserts that `FLAG` is inactive: the plugin's run of `Feature`, or `Core`'s own under `.moduleInfo`.
		var modules = Self.coreAndFeatureModules(coreTheme: "#if FLAG\npackage struct Theme {}\n#endif", receives: ["@Received let theme: Theme"], conditions: [], featureImports: ["Core", "Kit"])
		modules.insert(Self.kit(files: Self.kitFilesWithTheme), at: 0)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: integration, filesToDelete: &filesToDelete)
		let assertions = integration == .swiftPackagePlugin ? Self.inactiveAssertion("FLAG") : ""
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Theme"], imports: ["Core", "Kit"], assertions: assertions, tiers: """
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_theme theme: Theme) {
		        let cache = Cache()
		        self.init(theme: theme, cache: cache)
		    }
		""", guardHash: "DD923990A48765D6"))
		if integration == .moduleInfo {
			#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + Self.inactiveAssertion("FLAG")])
		}
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesElseClause_whenFlagIsNotReported(integration: MultiModuleIntegration) async throws {
		// IF3: without `FLAG`, the `#else` clause declares `Theme` `public`. A run that writes `Core`'s `.safedi` keeps no
		// `public` record, so under `.moduleInfo` `Feature` reads no declaration of `Theme`, which counts as `public` too.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.coreAndFeatureModules(coreTheme: Self.themeInEachClauseOfFlag, receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"], conditions: []),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let assertions = integration == .swiftPackagePlugin ? Self.inactiveAssertion("FLAG") : ""
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Theme"], imports: ["Core"], assertions: assertions, tiers: """
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_theme theme: Theme?) {
		        let cache = Cache()
		        self.init(theme: theme, cache: cache)
		    }
		""", guardHash: "717280493A095F31"))
		if integration == .moduleInfo {
			#expect(output.modules["Core"]?.moduleInfo?.plainTypeDeclarations.isEmpty == true)
		}
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesIfClause_whenFlagIsReported(integration: MultiModuleIntegration) async throws {
		// IF3: with `FLAG`, the `#if` clause declares `Theme` `package`: the `package` tier takes it, and `Core`'s `.safedi`
		// records that declaration alone.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.coreAndFeatureModules(coreTheme: Self.themeInEachClauseOfFlag, receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"], conditions: ["FLAG"]),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let assertions = integration == .swiftPackagePlugin ? Self.activeAssertion("FLAG") : ""
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: [], imports: ["Core"], assertions: assertions, tiers: """
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_theme: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_theme theme: Theme?) {
		        let cache = Cache()
		        self.init(theme: theme, cache: cache)
		    }
		""", guardHash: "27F6F01DC5D0EF8E"))
		if integration == .moduleInfo {
			#expect(output.modules["Core"]?.moduleInfo?.plainTypeDeclarations.map(\.access.level) == [.package])
			#expect(output.modules["Core"]?.moduleInfo?.plainTypeDeclarations.map(\.access.declarationStartLocation?.line) == [2])
		}
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: [[String](), ["B"], ["A", "B"]])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesFirstSettledClause_whenElseIfChainDeclaresTypeInEachClause(conditions: [String]) async throws {
		// IF4: an `#elseif` chain is selected as it is for `@Instantiable` content: the first clause whose condition holds,
		// or `#else`. Each condition evaluated is asserted; one after the settled clause is not evaluated.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"],
				extraFeatureFiles: ["Theme.swift": "#if A\nstruct Theme {}\n#elseif B\npackage struct Theme {}\n#else\npublic struct Theme {}\n#endif"],
				hostForwards: nil,
				featureConditions: conditions,
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		let expected: [String: String] = switch conditions {
		case ["A", "B"]:
			Self.screenFiles(.moduleInfo, comment: [], assertions: Self.activeAssertion("A"), tiers: """
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        self.init(__safeDI_theme: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    internal init(__safeDI_theme theme: Theme?) {
			        let cache = Cache()
			        self.init(theme: theme, cache: cache)
			    }
			""", guardHash: "2163FBB3C02B31CD")
		case ["B"]:
			Self.screenFiles(.moduleInfo, comment: [], assertions: Self.inactiveAssertion("A") + Self.activeAssertion("B"), tiers: """
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        self.init(__safeDI_theme: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    package init(__safeDI_theme theme: Theme?) {
			        let cache = Cache()
			        self.init(theme: theme, cache: cache)
			    }
			""", guardHash: "27F6F01DC5D0EF8E")
		default:
			Self.screenFiles(.moduleInfo, comment: [], assertions: Self.inactiveAssertion("A") + Self.inactiveAssertion("B"), tiers: """
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_theme theme: Theme?) {
			        let cache = Cache()
			        self.init(theme: theme, cache: cache)
			    }
			""", guardHash: "717280493A095F31")
		}
		#expect(output.modules["Feature"]?.generatedFiles == expected)
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNarrowest_whenFlagBlockNestedInPlatformBlockDeclaresNarrower(integration: MultiModuleIntegration) async throws {
		// IF5: every clause of the platform block is read, and `FLAG`, nested in its first, selects the `package`
		// declaration: the narrowest of the two, which the `package` tier takes on every platform.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.screenModules(
				receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"],
				extraFeatureFiles: ["Theme.swift": "#if os(Linux)\n#if FLAG\npackage struct Theme {}\n#endif\n#else\npublic struct Theme {}\n#endif"],
				hostForwards: nil,
				featureConditions: ["FLAG"],
			),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: [], assertions: Self.activeAssertion("FLAG"), tiers: """
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_theme: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_theme theme: Theme?) {
		        let cache = Cache()
		        self.init(theme: theme, cache: cache)
		    }
		""", guardHash: "27F6F01DC5D0EF8E"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsPlatformClauses_whenPlatformBlockNestedInFlagBlock(isFlagReported: Bool) async throws {
		// IF6: with `FLAG`, both clauses of the platform block nested in it are read, and `Feature`'s own `package` `Theme`
		// is the one the `package` tier takes; without it, neither is, and `Kit`'s `Theme` counts as `public`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(files: Self.kitFilesWithTheme),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"]),
					"Theme.swift": "#if FLAG\n#if os(Linux)\npackage struct Theme {}\n#else\npackage struct Theme {}\n#endif\n#endif",
				], dependencies: ["Kit"], activeCompilationConditions: isFlagReported ? ["FLAG"] : []),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		let expected = if isFlagReported {
			Self.screenFiles(.moduleInfo, comment: [], assertions: Self.activeAssertion("FLAG"), tiers: """
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        self.init(__safeDI_theme: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    package init(__safeDI_theme theme: Theme?) {
			        let cache = Cache()
			        self.init(theme: theme, cache: cache)
			    }
			""", guardHash: "27F6F01DC5D0EF8E")
		} else {
			Self.screenFiles(.moduleInfo, comment: ["Theme"], assertions: Self.inactiveAssertion("FLAG"), tiers: """
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_theme theme: Theme?) {
			        let cache = Cache()
			        self.init(theme: theme, cache: cache)
			    }
			""", guardHash: "717280493A095F31")
		}
		#expect(output.modules["Feature"]?.generatedFiles == expected)
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesTypeOnce_whenEveryPlatformClauseDeclaresItAtOneLevel(integration: MultiModuleIntegration) async {
		// IF7: both clauses of the platform block declare `Theme` `package`: the error names `Core` once, with a note at
		// each declaration.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let themePath = Self.path(of: "Theme.swift", in: "Core", fixtures, integration)
			return """
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `theme: Theme`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Theme` is declared `package` in module `Core`. Declare `Theme` `public` in module `Core`; declare `Screen` `package`; receive `theme` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(themePath):2:1: note: `Theme` is declared `package` here.
			\(themePath):2:1-2:8: fixit: public
			\(themePath):4:1: note: `Theme` is declared `package` here.
			\(themePath):4:1-4:8: fixit: public
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):10:5: note: `Screen` receives `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.coreAndFeatureModules(coreTheme: "#if os(Linux)\npackage struct Theme {}\n#else\npackage struct Theme {}\n#endif", receives: ["@Received let theme: Theme"], conditions: []),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNarrowestPlatformClause_whenClausesDeclareTypeAtDifferentLevels(integration: MultiModuleIntegration) async {
		// IF9: the compiler may select either clause, so `Theme` takes the narrower level, `package`, with the note at that
		// declaration alone.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let themePath = Self.path(of: "Theme.swift", in: "Core", fixtures, integration)
			return """
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `theme: Theme`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Theme` is declared `package` in module `Core`. Declare `Theme` `public` in module `Core`; declare `Screen` `package`; receive `theme` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(themePath):2:1: note: `Theme` is declared `package` here.
			\(themePath):2:1-2:8: fixit: public
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):10:5: note: `Screen` receives `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.coreAndFeatureModules(coreTheme: "#if os(Linux)\npackage struct Theme {}\n#else\npublic struct Theme {}\n#endif", receives: ["@Received let theme: Theme"], conditions: []),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesModuleOnce_whenTwoModulesDeclareTypeAcrossPlatformClauses() async {
		// IF10: `Core` declares `Theme` in both clauses of a platform block, and `Paints` declares it `public`: each module
		// is named once, at its narrowest. The plugin reads every record, while a `.safedi` keeps no `public` one.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let themePath = Self.path(of: "Theme.swift", in: "Core", fixtures, .swiftPackagePlugin)
			return """
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, .swiftPackagePlugin)):4:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `theme: Theme`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Theme` is declared `package` in module `Core` and `public` in module `Paints`, and SafeDI takes the narrower. Declare `Theme` `public` in module `Core`; spell the type with its module where it is mentioned (`Paints.Theme`), so that it names that module's declaration; declare `Screen` `package`; receive `theme` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(themePath):2:1: note: `Theme` is declared `package` here.
			\(themePath):2:1-2:8: fixit: public
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, .swiftPackagePlugin)):11:5: note: `Screen` receives `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "#if os(Linux)\npackage struct Theme {}\n#else\npublic struct Theme {}\n#endif"]),
					ModuleFixture(name: "Paints", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "public struct Theme {}"]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received let theme: Theme"], imports: ["Core", "Paints"]),
					], dependencies: ["Core", "Paints"]),
				],
				integration: .swiftPackagePlugin,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assertsMockCondition_whenPlainTypeUnderItIsNotReported() async throws {
		// IF11: a plain declaration is not mock-only content, so `#if DEBUG` around it is read with the reported conditions:
		// without `DEBUG`, `Theme` is unread, and the public mock that names it asserts `DEBUG` inactive, which a compile
		// under `DEBUG` rejects with SafeDI's message.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Theme.swift": "#if DEBUG\npackage struct Theme {}\n#endif",
					"Screen.swift": Self.publicMockScreenSource(receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"]),
				], dependencies: ["Kit"]),
			],
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.importLines(["Kit"]) + Self.inactiveAssertion("DEBUG") + """
		#if DEBUG
		extension Screen {
		    \(Self.comment(["Theme"]))
		    public static func mock(
		        theme: Theme? = nil
		    ) -> Screen {
		        return Screen(theme: theme)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_2E3EA54CCF203E28 {}
		}
		#endif
		"""])
		try expectModuleCompilationFails(output, module: "Feature", containing: "assuming `#if DEBUG` was inactive")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsPlainTypeUnderForcedMockCondition_whenItSharesBlockWithMockOnlyExtension() async throws {
		// IF11b: a block that holds a `mockOnly` extension is read as if the mock condition were active for its mock-only
		// content, and for its plain declarations both ways: `Theme` is `package` where `DEBUG` is active, and a build where
		// it is inactive declares nothing here, so the `package` tier takes it, and nothing asserts `DEBUG`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Fake.swift": "public struct Fake {}\n\n#if DEBUG\n@Instantiable(mockOnly: true)\nextension Fake {\n    public static func mock() -> Fake {\n        Fake()\n    }\n}\n\npackage struct Theme {}\n#endif",
					"Screen.swift": Self.publicMockScreenSource(receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"]),
				], dependencies: ["Kit"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.importLines(["Kit"]) + """
		#if DEBUG
		extension Screen {
		    public static func mock() -> Screen {
		        Screen.mock(theme: nil)
		    }

		    package static func mock(
		        theme: Theme? = nil
		    ) -> Screen {
		        return Screen(theme: theme)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_68FAB8E0F700DD87 {}
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	// MARK: IFM: a plain declaration in a block that guards mock-only declarations

	// SafeDI reads such a block as if the mock condition were active, for its mock-only content, and, for its plain
	// declarations, reads that condition as it reads a platform condition: the clauses selected where it is active and
	// those selected where it is inactive, a type counting as the narrowest level any of them declares it at. Each cell
	// runs as a debug build, which reports `DEBUG`, and as a release build, which does not, and compiles both.

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPublicTier_whenAnotherFileDeclaresTypeWhereMockConditionIsInactive(integration: MultiModuleIntegration) async throws {
		// IFM15 (Dan's shape): `Core`'s mock-only block declares `Endpoint` with no `#else`, and another file declares it
		// under `#if !DEBUG`, both `public`: every build declares it `public`, so the seam's `public` initializer requires it.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured(Self.coreAndFeatureModules(
					coreFiles: ["DebugSupport.swift": Self.mockOnlyBlock(declaring: "public struct Endpoint {}"), "Release.swift": Self.releaseEndpoint],
					receives: ["@Received let endpoint: Endpoint"],
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Endpoint"], imports: ["Core"], assertions: Self.releaseEndpointAssertion(integration, isReleaseConfiguration: isReleaseConfiguration), tiers: """
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_endpoint endpoint: Endpoint) {
			        let cache = Cache()
			        self.init(endpoint: endpoint, cache: cache)
			    }
			""", guardHash: "F321CFD3D66D9F0E"))
			try expectEveryModuleCompiled(output)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPublicTier_whenAnotherFileDeclaresTypeWhereMockConditionIsInactiveAndSeamReceivesItOnlyIfAvailable(integration: MultiModuleIntegration) async throws {
		// IFM16: IFM15 with an optional receive.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured(Self.coreAndFeatureModules(
					coreFiles: ["DebugSupport.swift": Self.mockOnlyBlock(declaring: "public struct Endpoint {}"), "Release.swift": Self.releaseEndpoint],
					receives: ["@Received(onlyIfAvailable: true) let endpoint: Endpoint?"],
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Endpoint"], imports: ["Core"], assertions: Self.releaseEndpointAssertion(integration, isReleaseConfiguration: isReleaseConfiguration), tiers: """
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_endpoint endpoint: Endpoint?) {
			        let cache = Cache()
			        self.init(endpoint: endpoint, cache: cache)
			    }
			""", guardHash: "15EDDFEBDF684859"))
			try expectEveryModuleCompiled(output)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPublicTier_whenSeamsOwnModuleDeclaresTypeInMockOnlyBlockAndUnderNegatedMockCondition() async throws {
		// IFM17: IFM15 with `Endpoint`'s two declarations in the seam's own module, whose files every run reads.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured(Self.screenModules(
					receives: ["@Received let endpoint: Endpoint"],
					extraFeatureFiles: ["DebugSupport.swift": Self.mockOnlyBlock(declaring: "public struct Endpoint {}"), "Release.swift": Self.releaseEndpoint],
					hostForwards: nil,
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], assertions: isReleaseConfiguration ? Self.activeAssertion("!DEBUG") : Self.inactiveAssertion("!DEBUG"), tiers: """
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_endpoint endpoint: Endpoint) {
			        let cache = Cache()
			        self.init(endpoint: endpoint, cache: cache)
			    }
			""", guardHash: "F321CFD3D66D9F0E"))
			try expectEveryModuleCompiled(output)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPublicTier_whenOtherClauseOfMockOnlyBlockDeclaresTypeAtSameLevel(integration: MultiModuleIntegration) async throws {
		// IFM8: the block's `#else` declares `Theme` as its `#if` clause does, `public`.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured(Self.coreAndFeatureModules(
					coreFiles: ["Theme.swift": Self.mockOnlyBlock(declaring: "public struct Theme {}", elseDeclaring: "public struct Theme {}")],
					receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"],
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Theme"], imports: ["Core"], tiers: """
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_theme theme: Theme?) {
			        let cache = Cache()
			        self.init(theme: theme, cache: cache)
			    }
			""", guardHash: "717280493A095F31"))
			try expectEveryModuleCompiled(output)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPackageTier_whenOtherClauseOfMockOnlyBlockDeclaresTypeMoreWidely(integration: MultiModuleIntegration) async throws {
		// IFM9: the `#if` clause declares `Theme` `package` and the `#else` clause `public`: the narrowest is `package`.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured(Self.coreAndFeatureModules(
					coreFiles: ["Theme.swift": Self.mockOnlyBlock(declaring: "package struct Theme {}", elseDeclaring: "public struct Theme {}")],
					receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"],
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["Feature"]?.generatedFiles == Self.packageThemeTiers(integration))
			try expectEveryModuleCompiled(output)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPackageTier_whenOtherClauseOfMockOnlyBlockDeclaresTypeNarrower(integration: MultiModuleIntegration) async throws {
		// IFM1 (Probe D across modules): the `#if` clause declares `Theme` `public` and the `#else` clause `package`, which a
		// release build compiles: the seam takes `Theme` on its `package` tier, in debug and release alike.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured(Self.coreAndFeatureModules(
					coreFiles: ["Theme.swift": Self.mockOnlyBlock(declaring: "public struct Theme {}", elseDeclaring: "package struct Theme {}")],
					receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"],
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["Feature"]?.generatedFiles == Self.packageThemeTiers(integration))
			try expectEveryModuleCompiled(output)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsAccessError_whenPublicSeamRequiresTypeOtherClauseOfMockOnlyBlockDeclaresNarrower(integration: MultiModuleIntegration) async {
		// IFM18 (Probe D, required): IFM1 with a required receive gets the error any `package` type does, at the seam.
		for isReleaseConfiguration in [false, true] {
			await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
				"""
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `theme: Theme`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Theme` is declared `package` in module `Core`. Declare `Theme` `public` in module `Core`; declare `Screen` `package`; receive `theme` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
				\(Self.path(of: "Theme.swift", in: "Core", fixtures, integration)):13:1: note: `Theme` is declared `package` here.
				\(Self.path(of: "Theme.swift", in: "Core", fixtures, integration)):13:1-13:8: fixit: public
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):10:5: note: `Screen` receives `theme: Theme` here.
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(
					modules: Self.configured(Self.coreAndFeatureModules(
						coreFiles: ["Theme.swift": Self.mockOnlyBlock(declaring: "public struct Theme {}", elseDeclaring: "package struct Theme {}")],
						receives: ["@Received let theme: Theme"],
					), isReleaseConfiguration: isReleaseConfiguration),
					integration: integration,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesLevelOfClauseFlagSelects_whenMockOnlyBlockHasElseIfFlag(integration: MultiModuleIntegration) async throws {
		// IFM19: where `DEBUG` is inactive, `FLAG` selects between a `public` and a `package` `Theme`: with `FLAG` reported
		// the seam takes `Theme` on its `public` tier, and without it on its `package` tier.
		for isReleaseConfiguration in [false, true] {
			for conditions in [["FLAG"], []] {
				let output = try await executeSafeDIToolMultiModuleTest(
					modules: Self.configured(Self.coreAndFeatureModules(
						coreFiles: ["Theme.swift": Self.mockOnlyBlock(declaring: "public struct Theme {}", elseIfFlagDeclaring: "public struct Theme {}", elseDeclaring: "package struct Theme {}")],
						receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"],
						conditions: conditions,
					), isReleaseConfiguration: isReleaseConfiguration),
					integration: integration,
					filesToDelete: &filesToDelete,
				)
				// The plugin reads `Core`'s file and asserts the decision a mention of `Theme` resolves by.
				let assertions = integration == .swiftPackagePlugin ? (conditions.isEmpty ? Self.inactiveAssertion("FLAG") : Self.activeAssertion("FLAG")) : ""
				let expectedFiles = conditions.isEmpty ? Self.packageThemeTiers(integration, assertions: assertions) : Self.screenFiles(integration, comment: ["Theme"], imports: ["Core"], assertions: assertions, tiers: """
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_theme theme: Theme?) {
				        let cache = Cache()
				        self.init(theme: theme, cache: cache)
				    }
				""", guardHash: "717280493A095F31")
				#expect(output.modules["Feature"]?.generatedFiles == expectedFiles)
				try expectEveryModuleCompiled(output)
			}
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPackageTier_whenOtherClauseOfMockOnlyBlockDeclaresEnclosingAndNestedTypeNarrower(integration: MultiModuleIntegration) async throws {
		// IFM11: `Space` and `Space.Config` are both declared in the block, and the `#else` clause declares both `package`.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured(Self.coreAndFeatureModules(
					coreFiles: ["Theme.swift": Self.mockOnlyBlock(declaring: "public enum Space { public struct Config {} }", elseDeclaring: "package enum Space { package struct Config {} }")],
					receives: ["@Received(onlyIfAvailable: true) let config: Space.Config?"],
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["Feature"]?.generatedFiles == Self.packageConfigTiers(integration))
			try expectEveryModuleCompiled(output)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPackageTier_whenOtherClauseOfMockOnlyBlockDeclaresOnlyNestedTypeNarrower(integration: MultiModuleIntegration) async throws {
		// IFM12: the `#else` clause declares `Space` `public`, as the `#if` clause does, and only `Space.Config` `package`.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured(Self.coreAndFeatureModules(
					coreFiles: ["Theme.swift": Self.mockOnlyBlock(declaring: "public enum Space { public struct Config {} }", elseDeclaring: "public enum Space { package struct Config {} }")],
					receives: ["@Received(onlyIfAvailable: true) let config: Space.Config?"],
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["Feature"]?.generatedFiles == Self.packageConfigTiers(integration))
			try expectEveryModuleCompiled(output)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPackageTier_whenExtensionOutsideMockOnlyBlockDeclaresTypeInTypeItsOtherClauseDeclaresNarrower(integration: MultiModuleIntegration) async throws {
		// IFM3: `Space.Config` is declared outside the block, in an extension of `Space`, which the `#else` clause declares
		// `package`: that caps `Space.Config` there.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured(Self.coreAndFeatureModules(
					coreFiles: ["Theme.swift": Self.mockOnlyBlock(declaring: "public enum Space {}", elseDeclaring: "package enum Space {}") + "\n\nextension Space {\n    public struct Config {}\n}"],
					receives: ["@Received(onlyIfAvailable: true) let config: Space.Config?"],
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["Feature"]?.generatedFiles == Self.packageConfigTiers(integration))
			try expectEveryModuleCompiled(output)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsAccessErrorAtBuilder_whenHoleBuilderReturnsTypeOtherClauseOfMockOnlyBlockDeclaresNarrower() async {
		// IFM4: the seam's tree instantiates `any Painter`, which no `@Instantiable` fulfills, so its initializer takes a
		// builder that returns it, which every tier takes: the `#else` clause declares `Painter` `package`, which the
		// `public` initializer cannot name.
		for isReleaseConfiguration in [false, true] {
			await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
				"""
				\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `painterBuilder: @escaping (SafeDIScope_Painter) -> any Painter`, the builder for `Screen`'s `painter: any Painter`, which no @Instantiable declaration that module `Feature` can see fulfills. `Painter` is declared `package`. Declare `Painter` `public`; declare `Screen` `package`; make an @Instantiable declaration that fulfills `Painter` one module `Feature` reads, so `Screen`'s tree builds it; or declare the dependency tree on a `package` type that instantiates `Screen`.
				\(fixtures["Feature"]!["Painter.swift"]):13:1: note: `Painter` is declared `package` here.
				\(fixtures["Feature"]!["Painter.swift"]):13:1-13:8: fixit: public
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(
					modules: Self.configured(Self.screenModules(
						receives: [],
						instantiates: ["@Instantiated let painter: any Painter"],
						extraFeatureFiles: ["Painter.swift": Self.mockOnlyBlock(declaring: "public protocol Painter {}", elseDeclaring: "package protocol Painter {}")],
						hostForwards: nil,
					), isReleaseConfiguration: isReleaseConfiguration),
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPublicTier_whenSeamNamesTypeItsModuleDeclaresOnlyInMockOnlyBlock() async throws {
		// IFM2: `Token` is declared only in the block's `#if` clause, so a release build declares no `Token`: the seam's own
		// declaration, which names it, fails to compile there before the generated initializer does. SafeDI takes what the
		// block declares, as it does when no other declaration exists.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured(Self.screenModules(
					receives: ["@Received let token: Token"],
					extraFeatureFiles: ["Token.swift": Self.mockOnlyBlock(declaring: "public struct Token {}")],
					hostForwards: nil,
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: .moduleInfo,
				compileVerification: .returningOutcomeOnly,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: [], tiers: """
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_token token: Token) {
			        let cache = Cache()
			        self.init(token: token, cache: cache)
			    }
			""", guardHash: "1EB503BFA23A82BA"))
			if isReleaseConfiguration {
				try expectInputsFailToCompile(output, module: "Feature", containing: "cannot find type 'Token' in scope")
			} else {
				try expectEveryModuleCompiled(output)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPublicTier_whenOtherClauseOfMockOnlyBlockDeclaresTypeOnlyItsOwnModuleCanName() async throws {
		// IFM13: the `#else` clause declares `Theme` `internal`, which `Feature`, another module, cannot name, so to
		// `Feature` a release build declares no `Theme`, and its own declaration that names `Theme` fails to compile there.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured(Self.coreAndFeatureModules(
					coreFiles: ["Theme.swift": Self.mockOnlyBlock(declaring: "public struct Theme {}", elseDeclaring: "internal struct Theme {}")],
					receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"],
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: .moduleInfo,
				compileVerification: .returningOutcomeOnly,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Theme"], imports: ["Core"], tiers: """
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_theme theme: Theme?) {
			        let cache = Cache()
			        self.init(theme: theme, cache: cache)
			    }
			""", guardHash: "717280493A095F31"))
			if isReleaseConfiguration {
				try expectInputsFailToCompile(output, module: "Feature", containing: "cannot find type 'Theme' in scope")
			} else {
				try expectEveryModuleCompiled(output)
			}
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPublicMockOnPackageTier_whenOtherClauseOfMockOnlyBlockDeclaresTypeItReceivesOnlyIfAvailableNarrower(integration: MultiModuleIntegration) async throws {
		// IFM20: a public mock compiles only where `DEBUG` is active, but its signature reads `Theme` as a seam's does: the
		// `#else` clause's `package` `Theme` moves its parameter to a `package` mock, which the `public` mock calls.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured(Self.coreAndPublicMockFeatureModules(
					coreTheme: Self.mockOnlyBlock(declaring: "public struct Theme {}", elseDeclaring: "package struct Theme {}"),
					receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"],
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			let mockCode = generatedFileHeader + Self.importLines(["Core"]) + """
			#if DEBUG
			extension Screen {
			    public static func mock() -> Screen {
			        Screen.mock(theme: nil)
			    }

			    package static func mock(
			        theme: Theme? = nil
			    ) -> Screen {
			        return Screen(theme: theme)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_68FAB8E0F700DD87 {}
			}
			#endif
			"""
			switch integration {
			case .moduleInfo:
				#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": mockCode])
			case .swiftPackagePlugin:
				#expect(output.modules["Feature"]?.generatedFiles == ["Screen+SafeDIMock.swift": mockCode, "SafeDIMockConfiguration.swift": generatedFileHeader + Self.importLines(["Core"])])
			}
			try expectEveryModuleCompiled(output)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsAccessError_whenPublicMockRequiresTypeOtherClauseOfMockOnlyBlockDeclaresNarrower(integration: MultiModuleIntegration) async {
		// IFM21: IFM20 with a required receive: the public mock cannot take `Theme`, which a build where `DEBUG` is inactive
		// declares `package`, so generation fails, as for any `package` type.
		for isReleaseConfiguration in [false, true] {
			await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
				"""
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:29: error: SafeDI cannot generate the public mock of `Screen`: its `public` tier, which `generateMock: .public` requires, cannot take `theme: Theme`, which the initializer of `Screen` receives, and cannot pass `nil` for it, since it is required. `Theme` is declared `package` in module `Core`. Declare `Theme` `public` in module `Core`; receive it with `onlyIfAvailable: true` and an optional type; or use `generateMock: .internal`.
				\(Self.path(of: "Theme.swift", in: "Core", fixtures, integration)):13:1: note: `Theme` is declared `package` here.
				\(Self.path(of: "Theme.swift", in: "Core", fixtures, integration)):13:1-13:8: fixit: public
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):9:5: note: `Screen` receives `theme: Theme` here.
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(
					modules: Self.configured(Self.coreAndPublicMockFeatureModules(
						coreTheme: Self.mockOnlyBlock(declaring: "public struct Theme {}", elseDeclaring: "package struct Theme {}"),
						receives: ["@Received let theme: Theme"],
					), isReleaseConfiguration: isReleaseConfiguration),
					integration: integration,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_ignoresMockOnlyBlock_whenNoSeamNamesTypeItDeclares(integration: MultiModuleIntegration) async throws {
		// IFM22: the block declares `Theme` `public` and its `#else` `package`, but the seam names only `Window`.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured([Self.kit()] + Self.coreAndFeatureModules(
					coreFiles: ["Theme.swift": Self.mockOnlyBlock(declaring: "public struct Theme {}", elseDeclaring: "package struct Theme {}")],
					receives: ["@Received let window: Window"],
					featureImports: ["Core", "Kit"],
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Window"], imports: ["Core", "Kit"], tiers: """
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_window window: Window) {
			        let cache = Cache()
			        self.init(window: window, cache: cache)
			    }
			""", guardHash: "564C5E6539CF6AA0"))
			try expectEveryModuleCompiled(output)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypeAtSpelledLevel_whenPlatformBlockGuardingMockOnlyDeclarationsDeclaresIt(integration: MultiModuleIntegration) async throws {
		// IFM5: a platform condition, not the mock condition, decides the block that holds the `mockOnly` extension: SafeDI
		// reads both clauses as the compiler may select either, so `Theme` is `package` exactly, and the seam is generated.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured(Self.coreAndFeatureModules(
					coreFiles: ["Theme.swift": Self.mockOnlyBlock(condition: "os(Linux)", declaring: "package struct Theme {}", elseDeclaring: "package struct Theme {}")],
					receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"],
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["Feature"]?.generatedFiles == Self.packageThemeTiers(integration))
			try expectEveryModuleCompiled(output)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPublicTier_whenPlatformBlockGuardingMockOnlyDeclarationsDeclaresTypePublicInEveryClause(integration: MultiModuleIntegration) async throws {
		// IFM23: IFM5 with `Theme` `public` in both clauses: the platform block's clauses decide its level, whatever the
		// configuration.
		for isReleaseConfiguration in [false, true] {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.configured(Self.coreAndFeatureModules(
					coreFiles: ["Theme.swift": Self.mockOnlyBlock(condition: "os(Linux)", declaring: "public struct Theme {}", elseDeclaring: "public struct Theme {}")],
					receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"],
				), isReleaseConfiguration: isReleaseConfiguration),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Theme"], imports: ["Core"], tiers: """
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_theme theme: Theme?) {
			        let cache = Cache()
			        self.init(theme: theme, cache: cache)
			    }
			""", guardHash: "717280493A095F31"))
			try expectEveryModuleCompiled(output)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesSeam_whenRunAssertsMockConditionActive(integration: MultiModuleIntegration) async throws {
		// IFM10: `Screen` is declared in a production `#if DEBUG` block, so a run that reports `DEBUG` asserts it active in
		// every file it generates: `Token`, declared only in a block guarding mock-only declarations, is declared wherever
		// the initializer compiles.
		let screen = "import Kit\n#if DEBUG\n" + Self.screenSource(receives: ["@Received let token: Token"], imports: []) + "\n#endif"
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(),
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContentByFilePath: ["Screen.swift": screen, "Token.swift": Self.mockOnlyBlock(declaring: "public struct Token {}")],
					dependencies: ["Kit"],
					activeCompilationConditions: ["DEBUG"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: [], assertions: Self.activeAssertion("DEBUG"), tiers: """
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_token token: Token) {
		        let cache = Cache()
		        self.init(token: token, cache: cache)
		    }
		""", guardHash: "1EB503BFA23A82BA"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_capsTypeByExtension_whenFlagBlockInsideExtensionDeclaresIt() async {
		// IF12: a block inside an extension is read in the clause `FLAG` selects, and the declaration it holds is capped by
		// the extended type's, as one outside the block is.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `config: Space.Config`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Space.Config` is `package`: it is declared inside an extension of `Space`, whose own declaration is `package`. Declare `Space` `public`; declare `Screen` `package`; receive `config` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Space.swift"]):1:1: note: `Space` is declared `package` here.
			\(fixtures["Feature"]!["Space.swift"]):1:1-1:8: fixit: public
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `config: Space.Config` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(
					receives: ["@Received let config: Space.Config"],
					extraFeatureFiles: ["Space.swift": "package enum Space {}\n\nextension Space {\n    #if FLAG\n    public struct Config {\n        public init() {}\n    }\n    #endif\n}"],
					hostForwards: nil,
					featureConditions: ["FLAG"],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsTypeInExtension_whenFlagBlockDeclaresTheExtension(isFlagReported: Bool) async {
		// IF13: with `FLAG`, the extension inside the block is read, and `Space.Config` is declared `internal`; without it,
		// SafeDI reads no declaration of `Space.Config`, which counts as `Space`, the type it is nested in.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let screenPath = fixtures["Feature"]!["Screen.swift"]
			let spacePath = fixtures["Feature"]!["Space.swift"]
			return if isFlagReported {
				"""
				\(screenPath):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `config: Space.Config`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Space.Config` is declared `internal`. Declare `Space.Config` `public`; declare `Screen` `internal`; receive `config` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
				\(spacePath):5:5: note: `Space.Config` is declared `internal` here.
				\(spacePath):5:5-5:5: fixit: public\(" ")
				\(screenPath):10:5: note: `Screen` receives `config: Space.Config` here.
				"""
			} else {
				"""
				\(screenPath):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `config: Space.Config`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Space.Config` is nested in `Space`, which is declared `package`. Declare `Space` `public`; declare `Screen` `package`; receive `config` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
				\(spacePath):1:1: note: `Space` is declared `package` here.
				\(spacePath):1:1-1:8: fixit: public
				\(screenPath):10:5: note: `Screen` receives `config: Space.Config` here.
				"""
			}
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(
					receives: ["@Received let config: Space.Config"],
					extraFeatureFiles: ["Space.swift": "package enum Space {}\n\n#if FLAG\nextension Space {\n    struct Config {}\n}\n#endif"],
					hostForwards: nil,
					featureConditions: isFlagReported ? ["FLAG"] : [],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_selectsDependencysClauseByWriterOrByTarget_byIntegration(integration: MultiModuleIntegration) async throws {
		// IF17: `Core`'s run reports `FLAG` and `Feature`'s does not. A `.safedi` records the clause its writer's conditions
		// select, so `.moduleInfo` takes the `package` declaration; the plugin reads `Core`'s file with `Feature`'s
		// conditions, so it takes the `public` one, which fails to compile where `Core` is compiled with `FLAG`. That is the
		// Manual's limit: "a condition that guards a production declaration in a dependency must be active on every target
		// whose dependency tree reaches it".
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": Self.themeInEachClauseOfFlag], activeCompilationConditions: ["FLAG"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let theme: Theme?"], imports: ["Core"]),
				], dependencies: ["Core"]),
			],
			integration: integration,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: [], imports: ["Core"], tiers: """
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        self.init(__safeDI_theme: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    package init(__safeDI_theme theme: Theme?) {
			        let cache = Cache()
			        self.init(theme: theme, cache: cache)
			    }
			""", guardHash: "27F6F01DC5D0EF8E"))
			try expectEveryModuleCompiled(output)
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: [], imports: ["Core"], assertions: Self.inactiveAssertion("FLAG"), tiers: """
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_theme theme: Theme?) {
			        let cache = Cache()
			        self.init(theme: theme, cache: cache)
			    }
			""", guardHash: "717280493A095F31"))
			try expectModuleCompilationFails(output, module: "Feature", containing: "uses a package type")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assertsFlag_whenBlockDeclaresPlainTypeADeclarationMentions() async throws {
		// IF19: `Screen` mentions `Token`, which `Feature` declares only under `FLAG`: the tool, not given `FLAG`, asserts it
		// inactive, and a compile with `FLAG` stops at that assertion.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(files: Self.kitFiles.merging(["Token.swift": "public struct Token {\n    public init() {}\n}"]) { first, _ in first }),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let token: Token?"]),
					"Token.swift": "#if FLAG\nstruct Token {}\n#endif",
				], dependencies: ["Kit"], verificationCompilationConditions: ["FLAG"]),
			],
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Token"], assertions: Self.inactiveAssertion("FLAG"), tiers: """
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_token token: Token?) {
		        let cache = Cache()
		        self.init(token: token, cache: cache)
		    }
		""", guardHash: "029593DA1BB2FBD5"))
		try expectModuleCompilationFails(output, module: "Feature", containing: "assuming `#if FLAG` was inactive")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assertsNothing_whenNothingMentionsTheType() async throws {
		// IF19: no declaration SafeDI reads mentions `Unrelated`, so the block that declares it asserts nothing, and a
		// compile with `FLAG` succeeds.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received(onlyIfAvailable: true) let window: Window?"]),
					"Unrelated.swift": "#if FLAG\nstruct Unrelated {}\n#endif",
				], dependencies: ["Kit"], verificationCompilationConditions: ["FLAG"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Window"], tiers: """
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_window window: Window?) {
		        let cache = Cache()
		        self.init(window: window, cache: cache)
		    }
		""", guardHash: "39C26C2DBA820CDB"))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assertsFlag_whenGuardedTypeNestedInInstantiableTypeIsMentionedUnqualified() async throws {
		// `Owner`'s initializer names `Nested` by its own name, which resolves to the `Owner.Nested` the clause the conditions
		// select declares: the tool, not given `FLAG`, asserts it inactive, as a mention of a type `Owner` does not nest
		// would assert it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.rootBuildingOwner,
				Self.owner(initializer: "public init(style: Nested = Nested()) {}"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == ["Root+SafeDI.swift": generatedFileHeader + Self.inactiveAssertion("FLAG") + Self.rootBuildingOwnerExtension])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assertsNothing_whenGuardedTypeNestedInInstantiableTypeIsNotMentioned() async throws {
		// The twin: nothing names `Owner.Nested`, so no read resolves to a declaration the block holds, and the tool asserts
		// nothing about `FLAG`, though it keeps the declarations of the types nested in `Owner`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.rootBuildingOwner,
				Self.owner(initializer: "public init() {}"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == ["Root+SafeDI.swift": generatedFileHeader + Self.rootBuildingOwnerExtension])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assertsFlag_whenWriterPathKeepsPackageTypeNothingMentions() async throws {
		// IF20: a run that writes `Core`'s `.safedi` keeps every `package` declaration, so it asserts the flag that skips
		// `Theme`'s, though nothing in `Core` mentions it; `Feature` reads no declaration of `Theme`, and `Kit`'s counts as
		// `public`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kit(files: Self.kitFilesWithTheme),
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "#if FLAG\npackage struct Theme {}\n#endif"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received let theme: Theme"], imports: ["Core", "Kit"]),
				], dependencies: ["Kit", "Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + Self.inactiveAssertion("FLAG")])
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(.moduleInfo, comment: ["Theme"], imports: ["Core", "Kit"], tiers: """
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_theme theme: Theme) {
		        let cache = Cache()
		        self.init(theme: theme, cache: cache)
		    }
		""", guardHash: "DD923990A48765D6"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesDependencysPublicTypeInFlagClause_underEveryIntegration(integration: MultiModuleIntegration) async throws {
		// IF21 (Q4): `Paints` declares `Theme` `public` under `DEBUG`, which both runs report: the public tier takes it under
		// either integration. The plugin reads the record; a `.safedi` keeps no `public` one, so `.moduleInfo` reads no
		// declaration and counts `Theme` as `public` too.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Paints", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "#if DEBUG\npublic struct Theme {\n    public init() {}\n}\n#endif"], activeCompilationConditions: ["DEBUG"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Screen.swift": Self.screenSource(receives: ["@Received let theme: Theme"], imports: ["Paints"]),
				], dependencies: ["Paints"], activeCompilationConditions: ["DEBUG"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let assertions = integration == .swiftPackagePlugin ? Self.activeAssertion("DEBUG") : ""
		#expect(output.modules["Feature"]?.generatedFiles == Self.screenFiles(integration, comment: ["Theme"], imports: ["Paints"], assertions: assertions, tiers: """
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_theme theme: Theme) {
		        let cache = Cache()
		        self.init(theme: theme, cache: cache)
		    }
		""", guardHash: "DD923990A48765D6"))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsProtocolAndTypealias_whenFlagClauseDeclaresThem(integration: MultiModuleIntegration) async {
		// IF22: a protocol and a typealias inside the selected clause are recorded as any plain type is.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let rendererPath = Self.path(of: "Renderer.swift", in: "Core", fixtures, integration)
			let screenPath = Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)
			return """
			\(screenPath):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `id: ID`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `ID` is declared `package` in module `Core`. Declare `ID` `public` in module `Core`; declare `Screen` `package`; receive `id` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(rendererPath):3:1: note: `ID` is declared `package` here.
			\(rendererPath):3:1-3:8: fixit: public
			\(screenPath):12:5: note: `Screen` receives `id: ID` here.
			\(screenPath):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `renderer: any Renderer`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Renderer` is declared `package` in module `Core`. Declare `Renderer` `public` in module `Core`; declare `Screen` `package`; receive `renderer` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(rendererPath):2:1: note: `Renderer` is declared `package` here.
			\(rendererPath):2:1-2:8: fixit: public
			\(screenPath):11:5: note: `Screen` receives `renderer: any Renderer` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Renderer.swift": "#if FLAG\npackage protocol Renderer {}\npackage typealias ID = Int\n#endif"], activeCompilationConditions: ["FLAG"]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": Self.screenSource(receives: ["@Received let renderer: any Renderer", "@Received let id: ID"], imports: ["Core"]),
					], dependencies: ["Core"], activeCompilationConditions: ["FLAG"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_leavesUnreadableSpellingInMiddleState_whenClauseIsSelected() async {
		// IF24: U1's seam inside the clause `FLAG` selects: SafeDI still cannot read `[3 of Int]`, which only mentions prove.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):4:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `buffer: [3 of Int]`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `internal` (`Screen.init(buffer:cache:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Screen` `internal`; receive `buffer` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Screen.swift"]):11:5: note: `Screen` receives `buffer: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.kit(),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Screen.swift": "#if FLAG\n" + Self.screenSource(receives: ["@Received let buffer: [3 of Int]"]) + "\n#endif",
					], dependencies: ["Kit"], activeCompilationConditions: ["FLAG"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorBoundingEntryByExtension_whenExtendedTypeIsAnotherModulesInstantiable() async {
		// IF25: an `@Instantiable` type inside an extension of another module's `@Instantiable` type is bounded by the
		// extension SafeDI reads, not by the extended type's declaration, which is another module's: what this change
		// leaves to mentions, besides a spelling SafeDI cannot read.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `z: Y.Z`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Y.Z` is `internal` as far as SafeDI can tell: it is declared inside an extension of `Y` that spells no access level, which SafeDI counts as `internal`, since it reads `Y`'s access only from a declaration of `Y` in the same module that is outside every extension, or inside an extension of a type it reads the same way. If `Y` can be `public`, spell the extension's access level (`public extension Y { … }`, dropping the modifier on `Z` that Swift then reports as redundant; the compiler rejects a level wider than `Y`'s), or declare `Z` in `Y`'s body or at top level; mention `Y.Z` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Screen` `internal`; receive `z` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `z: Y.Z` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Base", packageName: "Shop", swiftFileContentByFilePath: ["Y.swift": "@Instantiable\npublic struct Y: Instantiable {\n    public init() {}\n}"]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Z.swift": "import Base\n\nextension Y {\n    @Instantiable\n    public struct Z: Instantiable {\n        public init() {}\n    }\n}",
						"Screen.swift": Self.screenSource(receives: ["@Received let z: Y.Z"], imports: ["Base"]),
					], dependencies: ["Base"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingEnclosingType_whenEntryIsInExtensionOfNestedTypeSafeDIReadsNoDeclarationOf() async {
		// `Gear`, which does not run SafeDI, declares `Space.Inner`, so SafeDI reads no declaration of it; `Space`, which
		// encloses it, is `Core`'s `package` declaration, which bounds `Space.Inner`, and so `Space.Inner.Shelf`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):5:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `shelf: Space.Inner.Shelf`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Space.Inner.Shelf` is `package`: it is declared inside an extension of `Space.Inner`, which is nested in `Space`, whose own declaration is `package`. Declare `Space` `public`; declare `Screen` `package`; receive `shelf` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Screen.swift"]):12:5: note: `Screen` receives `shelf: Space.Inner.Shelf` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Space.swift": "package enum Space {}"]),
					ModuleFixture(name: "Gear", packageName: "Shop", swiftFileContentByFilePath: ["Inner.swift": "import Core\n\nextension Space {\n    package enum Inner {}\n}"], dependencies: ["Core"], runsSafeDI: false),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Shelf.swift": "import Core\nimport Gear\n\nextension Space.Inner {\n    @Instantiable\n    public struct Shelf: Instantiable {\n        public init() {}\n    }\n}",
						"Screen.swift": Self.screenSource(receives: ["@Received let shelf: Space.Inner.Shelf"], imports: ["Core", "Gear", "SafeDI"]),
					], dependencies: ["Core", "Gear"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingEnclosingType_whenEntryIsInExtensionOfTypeNestedTwoLevelsInTypeSafeDIReads() async {
		// `Gear`, which does not run SafeDI, declares `Space.Inner` and `Space.Inner.Deep`, so SafeDI reads neither; the
		// nearest type enclosing `Space.Inner.Deep` that it reads is `Space`, two levels out, whose `package` declaration
		// bounds them.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):5:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `shelf: Space.Inner.Deep.Shelf`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Space.Inner.Deep.Shelf` is `package`: it is declared inside an extension of `Space.Inner.Deep`, which is nested in `Space`, whose own declaration is `package`. Declare `Space` `public`; declare `Screen` `package`; receive `shelf` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Screen.swift"]):12:5: note: `Screen` receives `shelf: Space.Inner.Deep.Shelf` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Space.swift": "package enum Space {}"]),
					ModuleFixture(name: "Gear", packageName: "Shop", swiftFileContentByFilePath: ["Inner.swift": "import Core\n\nextension Space {\n    package enum Inner {\n        package enum Deep {}\n    }\n}"], dependencies: ["Core"], runsSafeDI: false),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Shelf.swift": "import Core\nimport Gear\n\nextension Space.Inner.Deep {\n    @Instantiable\n    public struct Shelf: Instantiable {\n        public init() {}\n    }\n}",
						"Screen.swift": Self.screenSource(receives: ["@Received let shelf: Space.Inner.Deep.Shelf"], imports: ["Core", "Gear", "SafeDI"]),
					], dependencies: ["Core", "Gear"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorBoundingEntryByExtension_whenNearestEnclosingTypeSafeDIReadsIsAnotherModulesInstantiable() async {
		// `Gear`, which does not run SafeDI, declares `Y.Inner`, and the nearest type enclosing it that SafeDI reads is
		// `Base`'s `@Instantiable` `Y`, whose proof bounds only an entry of its own module: `Z` is bounded by the extension
		// SafeDI reads, as IF25's entry is.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):5:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `z: Y.Inner.Z`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Y.Inner.Z` is `internal` as far as SafeDI can tell: it is declared inside an extension of `Y.Inner` that spells no access level, which SafeDI counts as `internal`, since it reads `Y.Inner`'s access only from a declaration of `Y.Inner` in the same module that is outside every extension, or inside an extension of a type it reads the same way. Declare `Z` in `Y.Inner`'s body or at top level; mention `Y.Inner.Z` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Screen` `internal`; receive `z` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Screen.swift"]):12:5: note: `Screen` receives `z: Y.Inner.Z` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Base", packageName: "Shop", swiftFileContentByFilePath: ["Y.swift": "@Instantiable\npublic struct Y: Instantiable {\n    public init() {}\n}"]),
					ModuleFixture(name: "Gear", packageName: "Shop", swiftFileContentByFilePath: ["Inner.swift": "import Base\n\nextension Y {\n    public enum Inner {}\n}"], dependencies: ["Base"], runsSafeDI: false),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Z.swift": "import Base\nimport Gear\n\nextension Y.Inner {\n    @Instantiable\n    public struct Z: Instantiable {\n        public init() {}\n    }\n}",
						"Screen.swift": Self.screenSource(receives: ["@Received let z: Y.Inner.Z"], imports: ["Base", "Gear", "SafeDI"]),
					], dependencies: ["Base", "Gear"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingEnclosingEntry_whenEntryIsInExtensionOfNestedTypeDeclaredInClauseConditionsSkip() async {
		// `Feature` declares `A.B` only under `FLAG`, which the tool is not given, so SafeDI reads no declaration of it; the
		// nearest type enclosing it is `Feature`'s own `@Instantiable` `A`, whose `package` declaration bounds `A.B.X`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `x: A.B.X`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `A.B.X` is `package`: it is declared inside an extension of `A.B`, which is nested in `A`, whose own `@Instantiable` declaration is `package`. Declare `A` `public`; declare `Screen` `package`; receive `x` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `x: A.B.X` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.kit(),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"A.swift": "@Instantiable\npackage struct A: Instantiable {\n    package init() {}\n}",
						"B.swift": "#if FLAG\nextension A {\n    package enum B {}\n}\n#endif",
						"X.swift": "extension A.B {\n    @Instantiable\n    public struct X: Instantiable {\n        public init() {}\n    }\n}",
						"Screen.swift": Self.screenSource(receives: ["@Received let x: A.B.X"]),
					], dependencies: ["Kit"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersNoMockOnlyMock_whenPublicMockForwardsNarrowerTypeInsideConditionalBlock() async {
		// P9's error twin: `Token`, inside a platform block, is declared `package`, which the error says, with the fix-it at
		// its declaration; a `mockOnly` mock proves nothing a declaration SafeDI reads does not.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `token: Token`, which `Service` forwards, and cannot pass `nil` for it, since it is required. `Token` is declared `package`. Declare `Token` `public`; give `Token` a `mockOnly` mock; or use `generateMock: .internal`.
			\(fixtures["Token.swift"]):2:1: note: `Token` is declared `package` here.
			\(fixtures["Token.swift"]):2:1-2:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"@Instantiable(generateMock: .public)\npublic struct Service: Instantiable {\n    init(token: Token) {\n        self.token = token\n    }\n\n    @Forwarded let token: Token\n}",
				],
				swiftFileContentByFilePath: ["Token.swift": "#if canImport(Foundation)\npackage struct Token {\n    package init() {}\n}\n#endif"],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingNoMockOnlyMock_whenPublicMockForwardsTypeSafeDICannotRead() async {
		// P9 for a spelling SafeDI cannot read: only `Service`'s `package` initializer mentions `[3 of Int]`, and a `mockOnly`
		// mock is no remedy, since such a spelling names no type an extension can extend.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `token: [3 of Int]`, which `Service` forwards, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in this module or on a type that receives it is `package` (`Service.init(token:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; make `Service.init(token:)` `public`; or use `generateMock: .internal`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"@Instantiable(generateMock: .public)\npublic struct Service: Instantiable {\n    package init(token: [3 of Int]) {\n        self.token = token\n    }\n\n    @Forwarded let token: [3 of Int]\n}",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingNoMention_whenPublicMocksTreeReceivesTypeSafeDICannotReadThroughAlias() async {
		// B2.14 for a public mock: `Consumer` receives `session: [3 of Int]` through its alias `auth`, and no member SafeDI
		// records mentions `[3 of Int]`, so the error names `Consumer` and its alias.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:29: error: SafeDI cannot generate the public mock of `Screen`: its `public` tier, which `generateMock: .public` requires, cannot take `session: [3 of Int]`, which the initializer of `Consumer` receives through its alias `auth` (`fulfilledByDependencyNamed: "session"`), and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and no initializer, `instantiate(…)` or mock method SafeDI records mentions it. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; receive `auth` with `onlyIfAvailable: true` and an optional type; or use `generateMock: .internal`.
			\(fixtures["Consumer.swift"]):7:5: note: `Consumer` receives `auth: any Auth` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"@Instantiable(generateMock: .public)\npublic struct Screen: Instantiable {\n    public init(consumer: Consumer) {\n        self.consumer = consumer\n    }\n\n    @Instantiated let consumer: Consumer\n}",
					"public protocol Auth {}",
					"@Instantiable\npublic struct Consumer: Instantiable {\n    public init(auth: any Auth) {\n        self.auth = auth\n    }\n\n    @Received(fulfilledByDependencyNamed: \"session\", ofType: [3 of Int].self) let auth: any Auth\n}",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The root `Root`, which instantiates an `Instantiator<Owner>`.
	private static let rootBuildingOwner = """
	@Instantiable(isRoot: true)
	public struct Root: Instantiable {
	    public init(ownerBuilder: Instantiator<Owner>) {
	        self.ownerBuilder = ownerBuilder
	    }

	    @Instantiated let ownerBuilder: Instantiator<Owner>
	}
	"""

	/// `rootBuildingOwner`'s generated initializer, after its file's header and assertions.
	private static let rootBuildingOwnerExtension = """
	extension Root {
	    public init() {
	        func __safeDI_ownerBuilder() -> Owner {
	            Owner()
	        }
	        let ownerBuilder = Instantiator<Owner>(__safeDI_ownerBuilder)
	        self.init(ownerBuilder: ownerBuilder)
	    }
	}
	"""

	/// `Owner`, whose body holds `initializer` and declares `Owner.Nested` in either clause of `#if FLAG`.
	private static func owner(initializer: String) -> String {
		"""
		@Instantiable
		public struct Owner: Instantiable {
		    \(initializer)

		    #if FLAG
		    public struct Nested {
		        public init() {}
		    }
		    #else
		    public struct Nested {
		        public init() {}
		    }
		    #endif
		}
		"""
	}

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

	/// `kitFiles`, with a `public` `Theme`, which a module SafeDI reads may declare only in some clauses.
	private static let kitFilesWithTheme = kitFiles.merging(["Theme.swift": "public struct Theme {\n    public init() {}\n}"]) { first, _ in first }

	/// `Theme`, declared `package` when `FLAG` is active and `public` otherwise.
	private static let themeInEachClauseOfFlag = "#if FLAG\npackage struct Theme {}\n#else\npublic struct Theme {}\n#endif"

	/// A file whose `#if <condition>` block holds a `mockOnly` extension of `Fake` and, at line 11, `declaration`, with
	/// `elseIfFlagDeclaration` in an `#elseif FLAG` clause and `elseDeclaration` in its `#else` clause when they are given.
	private static func mockOnlyBlock(condition: String = "DEBUG", declaring declaration: String, elseIfFlagDeclaring elseIfFlagDeclaration: String? = nil, elseDeclaring elseDeclaration: String? = nil) -> String {
		"public struct Fake {}\n\n#if \(condition)\n@Instantiable(mockOnly: true)\nextension Fake {\n    public static func mock() -> Fake {\n        Fake()\n    }\n}\n\n\(declaration)\n"
			+ (elseIfFlagDeclaration.map { "#elseif FLAG\n\($0)\n" } ?? "")
			+ (elseDeclaration.map { "#else\n\($0)\n" } ?? "")
			+ "#endif"
	}

	/// A file that declares `Endpoint` `public` where `DEBUG` is inactive.
	private static let releaseEndpoint = "#if !DEBUG\npublic struct Endpoint {}\n#endif"

	/// The assertion `Feature`'s generated file carries, under `integration`, for the `#if !DEBUG` of `releaseEndpoint`
	/// in `Core`: the plugin reads `Core`'s files, and asserts the decision a mention of `Endpoint` resolves by, while a
	/// module info holds no record of a `public` type nothing in its module mentions.
	private static func releaseEndpointAssertion(_ integration: MultiModuleIntegration, isReleaseConfiguration: Bool) -> String {
		switch integration {
		case .moduleInfo:
			""
		case .swiftPackagePlugin:
			isReleaseConfiguration ? activeAssertion("!DEBUG") : inactiveAssertion("!DEBUG")
		}
	}

	/// `Feature`'s generated files under `integration` for a seam that takes `theme: Theme?` on its `package` tier only.
	private static func packageThemeTiers(_ integration: MultiModuleIntegration, assertions: String = "") -> [String: String] {
		screenFiles(integration, comment: [], imports: ["Core"], assertions: assertions, tiers: """
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_theme: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_theme theme: Theme?) {
		        let cache = Cache()
		        self.init(theme: theme, cache: cache)
		    }
		""", guardHash: "27F6F01DC5D0EF8E")
	}

	/// `Feature`'s generated files under `integration` for a seam that takes `config: Space.Config?` on its `package` tier
	/// only.
	private static func packageConfigTiers(_ integration: MultiModuleIntegration) -> [String: String] {
		screenFiles(integration, comment: [], imports: ["Core"], tiers: """
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_config: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_config config: Space.Config?) {
		        let cache = Cache()
		        self.init(config: config, cache: cache)
		    }
		""", guardHash: "8E7506DB08AFA75C")
	}

	/// `Core`, in `Feature`'s package, whose `Theme.swift` is `coreTheme`, and `Feature`, whose seam `Screen` receives
	/// `receives`, both run with `conditions`.
	private static func coreAndFeatureModules(coreTheme: String, receives: [String], conditions: [String], featureImports: [String] = ["Core"]) -> [ModuleFixture] {
		coreAndFeatureModules(coreFiles: ["Theme.swift": coreTheme], receives: receives, conditions: conditions, featureImports: featureImports)
	}

	/// `Core`, in `Feature`'s package, with `coreFiles`, and `Feature`, whose seam `Screen` receives `receives`, both run
	/// with `conditions`.
	private static func coreAndFeatureModules(coreFiles: [String: String], receives: [String], conditions: [String] = [], featureImports: [String] = ["Core"]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: coreFiles, activeCompilationConditions: conditions),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
				"Screen.swift": screenSource(receives: receives, imports: featureImports),
			], dependencies: featureImports, activeCompilationConditions: conditions),
		]
	}

	/// `Core`, in `Feature`'s package, whose `Theme.swift` is `coreTheme`, and `Feature`, whose `Screen` has a public
	/// mock (`publicMockScreenSource`) and receives `receives`.
	private static func coreAndPublicMockFeatureModules(coreTheme: String, receives: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": coreTheme]),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
				"Screen.swift": publicMockScreenSource(receives: receives, imports: ["Core"]),
			], dependencies: ["Core"]),
		]
	}

	/// `modules` as a debug build configures them, which reports `DEBUG` to the tool and defines it in the compile, or,
	/// when `isReleaseConfiguration`, as a release build does (`ModuleFixture.isReleaseConfiguration`).
	private static func configured(_ modules: [ModuleFixture], isReleaseConfiguration: Bool) -> [ModuleFixture] {
		modules.map { module in
			ModuleFixture(
				name: module.name,
				packageName: module.packageName,
				swiftFileContent: module.swiftFileContent,
				swiftFileContentByFilePath: module.swiftFileContentByFilePath,
				dependencies: module.dependencies,
				isCheckoutPackage: module.isCheckoutPackage,
				activeCompilationConditions: isReleaseConfiguration ? module.activeCompilationConditions : module.activeCompilationConditions + ["DEBUG"],
				buildSettingArguments: module.buildSettingArguments,
				verificationCompilationConditions: module.verificationCompilationConditions,
				mockConditionalCompilation: module.mockConditionalCompilation,
				deletesSwiftFilesAfterRunning: module.deletesSwiftFilesAfterRunning,
				omitsModuleName: module.omitsModuleName,
				omitsPackageName: module.omitsPackageName,
				isReleaseConfiguration: isReleaseConfiguration,
				runsSafeDI: module.runsSafeDI,
				compilerSettings: module.compilerSettings,
			)
		}
	}

	/// The compile-time assertion a generated file carries for a `#if <condition>` the tool evaluated as active, ending
	/// with the blank line that precedes what follows.
	private static func activeAssertion(_ condition: String) -> String {
		"""
		#if !(\(condition))
		#error("SafeDI scanned this module assuming `#if \(condition)` was active, but it is inactive in this compilation. Report the conditions this target compiles with to SafeDITool, as the \\"Reporting active conditions\\" section of the SafeDI manual describes for your build system.")
		#endif

		""" + "\n"
	}

	/// The compile-time assertion a generated file carries for a `#if <condition>` the tool evaluated as inactive, ending
	/// with the blank line that precedes what follows.
	private static func inactiveAssertion(_ condition: String) -> String {
		"""
		#if \(condition)
		#error("SafeDI scanned this module assuming `#if \(condition)` was inactive, but it is active in this compilation. Report the conditions this target compiles with to SafeDITool, as the \\"Reporting active conditions\\" section of the SafeDI manual describes for your build system.")
		#endif

		""" + "\n"
	}

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

	/// `Core`, in `Feature`'s package, whose `Token.swift`, a file without a SafeDI marker, holds `declaration`, and
	/// `Feature`, whose seam `Screen` has `receive`; both run with `conditions`.
	private static func tokenModules(declaration: String, receive: String, conditions: [String] = []) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Token.swift": declaration], activeCompilationConditions: conditions),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
				"Screen.swift": screenSource(receives: [receive], imports: ["Core"]),
			], dependencies: ["Core"], activeCompilationConditions: conditions),
		]
	}

	/// `Feature`, whose `Token.swift` holds `declaration` and whose seam `Screen` has `receive`.
	private static func featureDeclaringToken(_ declaration: String, receive: String = "@Received let token: Token") -> ModuleFixture {
		ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
			"Token.swift": declaration,
			"Screen.swift": screenSource(receives: [receive], imports: []),
		])
	}

	/// The comment the generated file carries above its first `public` declaration that names a type of `names`.
	private static func comment(_ names: [String]) -> String {
		let list = names.map { "`\($0)`" }.joinedAsTestList
		return names.count == 1
			? "// SafeDI counts \(list) as `public`: no module it reads declares it narrower. If \(list) is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies."
			: "// SafeDI counts \(list) as `public`: no module it reads declares them narrower. If one is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies."
	}

	/// `Feature`'s generated files under `integration` for the seam `Screen`, whose extension holds `tiers`, with the
	/// comment naming `comment` above the first tier under `.moduleInfo`, which runs without a target graph, and
	/// `assertions` after the imports.
	private static func screenFiles(_ integration: MultiModuleIntegration, comment names: [String], imports: [String] = ["Kit"], assertions: String = "", tiers: String, guardHash: String) -> [String: String] {
		let commentLine = integration == .moduleInfo && !names.isEmpty ? "    \(comment(names))\n" : ""
		// The comment is above the first `public` declaration that names one of `names`: the first tier, or where `tiers`
		// marks it.
		let commentedTiers = tiers.contains("    {COMMENT}\n") ? tiers.replacingOccurrences(of: "    {COMMENT}\n", with: commentLine) : commentLine + tiers
		let code = generatedFileHeader + importLines(imports) + assertions + """
		extension Screen {
		\(commentedTiers)
		}

		extension Screen {
		    public enum __safeDI_Screen_\(guardHash) {}
		}
		"""
		return [integration == .moduleInfo ? "Feature.swift" : "Screen+SafeDI.swift": code]
	}

	/// The lines a generated file repeats for a fixture's imports of `moduleNames`, with the blank line after them when
	/// there are any.
	private static func importLines(_ moduleNames: [String]) -> String {
		moduleNames.isEmpty ? "" : moduleNames.map { "#if canImport(\($0))\nimport \($0)\n#endif\n" }.joined() + "\n"
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

	/// Expects every module before `module` to compile, and `module`'s own inputs to fail to compile without the generated
	/// code, with an error containing `text`.
	private func expectInputsFailToCompile(_ output: MultiModuleTestOutput, module: String, containing text: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		let failure = try #require(compilation.failure, sourceLocation: sourceLocation)
		#expect(failure.moduleName == module, sourceLocation: sourceLocation)
		#expect(compilation.modules.dropLast().allSatisfy { $0.failure == nil }, sourceLocation: sourceLocation)
		switch failure.failure {
		case let .inputsFailedOnTheirOwn(inputsOnlyResult):
			#expect(inputsOnlyResult.stderr.contains(text), "Unexpected compiler output \(inputsOnlyResult.stderr)", sourceLocation: sourceLocation)
		case .generatedCodeFailedAlongsideInputs, nil:
			Issue.record("Expected \(module)'s inputs to fail to compile on their own, but its failure is \(String(describing: failure.failure)).", sourceLocation: sourceLocation)
		}
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
