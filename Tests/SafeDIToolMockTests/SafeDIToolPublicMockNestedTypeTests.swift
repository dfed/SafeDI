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

/// A public mock's module-level configuration of a type in its tree (`__safeDI_<Type>_MockConfiguration`) spells the
/// types of the type's default-valued parameters and of its builder's parameters outside the type, where a type nested
/// in it resolves only when qualified. Each cell's `MockCallSite.swift` sets every field the configuration declares.
struct SafeDIToolPublicMockNestedTypeTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – the type a default-valued parameter names

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeInPublicConfiguration_whenDefaultValuedParameterIsOfEnumNestedInConfiguredType() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.root(instantiating: "child: Child"),
				Self.childWithNestedTheme,
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoot() -> Root {
				    Root.mock(safeDIOverrides: .init(child: .init(theme: .dark, { theme in Child(theme: theme) })))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": Self.rootMock(building: "child", ofType: "Child", configuredBy: "__safeDI_Child_MockConfiguration", construction: "Child.__safeDI_init(theme: safeDIOverrides.child.theme, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)"),
			"SafeDIMockConfiguration.swift": generatedFileHeader + Self.childThemeConfiguration + "\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeInPublicConfiguration_whenNestedTypeIsDeclaredInExtensionInFileWithoutSafeDIContent() async throws {
		// `Theme` is declared in an extension of `Child` in a file that mentions no SafeDI marker, which the module reads
		// only for the plain declarations it keeps: `Child.Theme` among them, because `Child` is `@Instantiable`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.root(instantiating: "child: Child"),
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(theme: Theme = .light) {
				        self.theme = theme
				    }

				    public let theme: Theme
				}
				""",
			],
			swiftFileContentByFilePath: [
				"ChildTheme.swift": """
				extension Child {
				    public enum Theme: Sendable {
				        case light
				        case dark
				    }
				}
				""",
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoot() -> Root {
				    Root.mock(safeDIOverrides: .init(child: .init(theme: .dark, { theme in Child(theme: theme) })))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": Self.rootMock(building: "child", ofType: "Child", configuredBy: "__safeDI_Child_MockConfiguration", construction: "Child.__safeDI_init(theme: safeDIOverrides.child.theme, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)"),
			"SafeDIMockConfiguration.swift": generatedFileHeader + Self.childThemeConfiguration + "\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeInPublicConfiguration_whenTopLevelTypeOfSameNameAsNestedTypeExists() async throws {
		// Within `Child`, `Theme` names `Child.Theme`, as member lookup precedes the module's top level, so the
		// configuration names it too, rather than the top-level `Theme` an unqualified name names outside `Child`.
		let topLevelTheme = """
		public enum Theme: Sendable {
		    case other
		}
		"""
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				topLevelTheme,
				Self.root(instantiating: "child: Child"),
				Self.childWithNestedTheme,
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoot() -> Root {
				    Root.mock(safeDIOverrides: .init(child: .init(theme: .dark, { theme in Child(theme: theme) })))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": Self.rootMock(building: "child", ofType: "Child", configuredBy: "__safeDI_Child_MockConfiguration", construction: "Child.__safeDI_init(theme: safeDIOverrides.child.theme, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)"),
			"SafeDIMockConfiguration.swift": generatedFileHeader + Self.childThemeConfiguration + "\n",
		])

		// The public mock builds the `Child.Theme` default that a hand-written mock building `Child()` builds.
		let generatedFiles = try #require(output.generatedFiles)
		let fixtureFiles = ["Theme.swift": topLevelTheme, "Root.swift": Self.root(instantiating: "child: Child"), "Child.swift": Self.childWithNestedTheme]
		try expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: generatedFiles),
			knownRight: DifferentialValuePath(
				fixtureFiles: fixtureFiles,
				generatedFiles: ["Root+KnownRightMock.swift": "extension Root {\n    static func mock() -> Root {\n        Root(child: Child())\n    }\n}\n"],
			),
			probes: [DifferentialValueProbe("Root.mock()")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeInPublicConfiguration_whenNoDeclarationOfModuleNamesConfiguredType() async throws {
		// `Root` names only `AnyChild`, and `Child` only through `fulfilledByType:`, so no member of the module names
		// `Child`: the module keeps `Child.Theme`'s declaration because `Child` is `@Instantiable`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Root: Instantiable {
				    public init(child: AnyChild) {
				        self.child = child
				    }

				    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let child: AnyChild
				}
				""",
				"""
				public struct AnyChild {
				    public init(_ child: Child) {
				        self.child = child
				    }

				    public let child: Child
				}
				""",
				Self.childWithNestedTheme,
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoot() -> Root {
				    Root.mock(safeDIOverrides: .init(child: .init(theme: .dark, { theme in Child(theme: theme) })))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": Self.rootMock(building: "child", ofType: "AnyChild", configuredBy: "__safeDI_Child_MockConfiguration", construction: "AnyChild(Child.__safeDI_init(theme: safeDIOverrides.child.theme, safeDIBuilder: safeDIOverrides.child.safeDIBuilder))"),
			"SafeDIMockConfiguration.swift": generatedFileHeader + Self.childThemeConfiguration + "\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeInPublicConfigurationAndForwarder_whenDefaultValuedParametersAreOfStructNestedInConfiguredType() async throws {
		// The optional default's member defaults to a module-level forwarder, whose result type is qualified too, as is
		// the result type of the provider it forwards to; the default expression is evaluated as written.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.root(instantiating: "child: Child"),
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public struct Style: Sendable {
				        public init() {}
				    }

				    public init(style: Style = Style(), accent: Style? = Style()) {
				        self.style = style
				        self.accent = accent
				    }

				    public let style: Style
				    public let accent: Style?
				}
				""",
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoot() -> Root {
				    Root.mock(safeDIOverrides: .init(child: .init(style: Child.Style(), accent: nil, { style, accent in Child(style: style, accent: accent) })))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": Self.rootMock(building: "child", ofType: "Child", configuredBy: "__safeDI_Child_MockConfiguration", construction: "Child.__safeDI_init(style: safeDIOverrides.child.style, accent: safeDIOverrides.child.accent, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)"),
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Child` is constructed within the public mock trees of this module.
			public struct __safeDI_Child_MockConfiguration {
			    public init(
			        style: Child.Style? = nil,
			        accent: Child.Style? = __safeDI_Child_mockDefault_accent(),
			        _ safeDIBuilder: ((Child.Style, Child.Style?) -> Child)? = nil
			    ) {
			        self.style = style
			        self.accent = accent
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Child`'s `style`.
			    public let style: Child.Style?
			    /// The default of `Child`'s `accent` unless set.
			    public let accent: Child.Style?
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Child.Style, Child.Style?) -> Child)?
			}

			extension Child {
			    nonisolated static func __safeDI_mockDefault_accent() -> Child.Style? { Style() }
			    static func __safeDI_init(style: Child.Style?, accent: Child.Style?, safeDIBuilder: ((Child.Style, Child.Style?) -> Child)?) -> Child {
			        let style = style ?? (Style())
			        return if let safeDIBuilder { safeDIBuilder(style, accent) } else { Child(style: style, accent: accent) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_Child_mockDefault_accent() -> Child.Style? { Child.__safeDI_mockDefault_accent() }
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeInPublicConfiguration_whenInstantiateParameterIsOfEnumNestedInExtendedType() async throws {
		// An extension's `instantiate(…)` is written within the extended type, as an initializer is.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.root(instantiating: "gadget: Gadget"),
				"""
				public struct Gadget {
				    public enum Mode: Sendable {
				        case fast
				        case slow
				    }

				    public let mode: Mode
				}

				@Instantiable
				extension Gadget: Instantiable {
				    public static func instantiate(mode: Mode = .fast) -> Gadget {
				        Gadget(mode: mode)
				    }
				}
				""",
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoot() -> Root {
				    Root.mock(safeDIOverrides: .init(gadget: .init(mode: .slow, { mode in Gadget.instantiate(mode: mode) })))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": Self.rootMock(building: "gadget", ofType: "Gadget", configuredBy: "__safeDI_Gadget_MockConfiguration", construction: "Gadget.__safeDI_init(mode: safeDIOverrides.gadget.mode, safeDIBuilder: safeDIOverrides.gadget.safeDIBuilder)"),
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Gadget` is constructed within the public mock trees of this module.
			public struct __safeDI_Gadget_MockConfiguration {
			    public init(
			        mode: Gadget.Mode? = nil,
			        _ safeDIBuilder: ((Gadget.Mode) -> Gadget)? = nil
			    ) {
			        self.mode = mode
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Gadget`'s `mode`.
			    public let mode: Gadget.Mode?
			    /// Overrides how `Gadget` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Gadget.Mode) -> Gadget)?
			}

			extension Gadget {
			    static func __safeDI_init(mode: Gadget.Mode?, safeDIBuilder: ((Gadget.Mode) -> Gadget)?) -> Gadget {
			        let mode = mode ?? (.fast)
			        return if let safeDIBuilder { safeDIBuilder(mode) } else { Gadget.instantiate(mode: mode) }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeInPublicConfiguration_whenDefaultValuedParametersAreOfTypealiasOfFunctionTypeNestedInConfiguredType() async throws {
		// One parameter is declared `@escaping` and one is not; a public configuration holds each as an optional, which
		// escapes, and its builder takes each as the initializer declares it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.root(instantiating: "child: Child"),
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public typealias Handler = () -> Void

				    public init(onTap: @escaping Handler = {}, onFinish: Handler = {}) {
				        self.onTap = onTap
				        onFinish()
				    }

				    public let onTap: Handler
				}
				""",
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoot() -> Root {
				    Root.mock(safeDIOverrides: .init(child: .init(onTap: {}, onFinish: {}, { onTap, onFinish in Child(onTap: onTap, onFinish: onFinish) })))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": Self.rootMock(building: "child", ofType: "Child", configuredBy: "__safeDI_Child_MockConfiguration", construction: "Child.__safeDI_init(onTap: safeDIOverrides.child.onTap, onFinish: safeDIOverrides.child.onFinish, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)"),
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Child` is constructed within the public mock trees of this module.
			public struct __safeDI_Child_MockConfiguration {
			    public init(
			        onTap: Child.Handler? = nil,
			        onFinish: Child.Handler? = nil,
			        _ safeDIBuilder: ((@escaping Child.Handler, Child.Handler) -> Child)? = nil
			    ) {
			        self.onTap = onTap
			        self.onFinish = onFinish
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Child`'s `onTap`.
			    public let onTap: Child.Handler?
			    /// `nil` keeps the default of `Child`'s `onFinish`.
			    public let onFinish: Child.Handler?
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((@escaping Child.Handler, Child.Handler) -> Child)?
			}

			extension Child {
			    static func __safeDI_init(onTap: Child.Handler?, onFinish: Child.Handler?, safeDIBuilder: ((@escaping Child.Handler, Child.Handler) -> Child)?) -> Child {
			        let onTap = onTap ?? ({})
			        let onFinish = onFinish ?? ({})
			        return if let safeDIBuilder { safeDIBuilder(onTap, onFinish) } else { Child(onTap: onTap, onFinish: onFinish) }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypesInPublicConfiguration_whenDefaultValuedParametersAreOfTypesNestedTwoLevelsDeep() async throws {
		// Written within `Outer.Child`, `Theme` names `Outer.Child.Theme`, `Mode` names `Outer.Mode`, which `Outer.Child`
		// does not declare, and `Inner.Palette` names `Outer.Child.Inner.Palette`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.root(instantiating: "child: Outer.Child"),
				"""
				public enum Outer {
				    public enum Mode: Sendable {
				        case fast
				        case slow
				    }

				    @Instantiable
				    public final class Child: Instantiable {
				        public enum Theme: Sendable {
				            case light
				            case dark
				        }

				        public enum Inner {
				            public enum Palette: Sendable {
				                case warm
				                case cool
				            }
				        }

				        public init(theme: Theme = .light, mode: Mode = .fast, palette: Inner.Palette = .warm) {
				            self.theme = theme
				            self.mode = mode
				            self.palette = palette
				        }

				        public let theme: Theme
				        public let mode: Mode
				        public let palette: Inner.Palette
				    }
				}
				""",
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoot() -> Root {
				    Root.mock(safeDIOverrides: .init(child: .init(theme: .dark, mode: .slow, palette: .cool, { theme, mode, palette in Outer.Child(theme: theme, mode: mode, palette: palette) })))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": Self.rootMock(building: "child", ofType: "Outer.Child", configuredBy: "__safeDI_Outer_Child_MockConfiguration", construction: "Outer.Child.__safeDI_init(theme: safeDIOverrides.child.theme, mode: safeDIOverrides.child.mode, palette: safeDIOverrides.child.palette, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)"),
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Outer.Child` is constructed within the public mock trees of this module.
			public struct __safeDI_Outer_Child_MockConfiguration {
			    public init(
			        theme: Outer.Child.Theme? = nil,
			        mode: Outer.Mode? = nil,
			        palette: Outer.Child.Inner.Palette? = nil,
			        _ safeDIBuilder: ((Outer.Child.Theme, Outer.Mode, Outer.Child.Inner.Palette) -> Outer.Child)? = nil
			    ) {
			        self.theme = theme
			        self.mode = mode
			        self.palette = palette
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Outer.Child`'s `theme`.
			    public let theme: Outer.Child.Theme?
			    /// `nil` keeps the default of `Outer.Child`'s `mode`.
			    public let mode: Outer.Mode?
			    /// `nil` keeps the default of `Outer.Child`'s `palette`.
			    public let palette: Outer.Child.Inner.Palette?
			    /// Overrides how `Outer.Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Outer.Child.Theme, Outer.Mode, Outer.Child.Inner.Palette) -> Outer.Child)?
			}

			extension Outer.Child {
			    static func __safeDI_init(theme: Outer.Child.Theme?, mode: Outer.Mode?, palette: Outer.Child.Inner.Palette?, safeDIBuilder: ((Outer.Child.Theme, Outer.Mode, Outer.Child.Inner.Palette) -> Outer.Child)?) -> Outer.Child {
			        let theme = theme ?? (.light)
			        let mode = mode ?? (.fast)
			        let palette = palette ?? (.warm)
			        return if let safeDIBuilder { safeDIBuilder(theme, mode, palette) } else { Outer.Child(theme: theme, mode: mode, palette: palette) }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_provesAccessOfNestedTypes_whenPublicMockedTypesOwnDefaultValuedParametersAreOfTypesNestedInIt() async throws {
		// `Root`'s own `mock()` is declared in `Root`'s extension, where `Theme` and `Label` resolve as written, but their
		// access is `Root.Theme`'s and `Root.Label`'s: `Theme` is `internal`, so only the `internal` tier takes it. `Shell`'s
		// tree builds `Root`, whose module-level configuration names both qualified.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Root: Instantiable {
				    enum Theme: Sendable {
				        case light
				        case dark
				    }

				    public enum Label: Sendable {
				        case short
				        case long
				    }

				    init(child: Child, theme: Theme = .light, label: Label? = .short) {
				        self.child = child
				        self.theme = theme
				        self.label = label
				    }

				    @Instantiated let child: Child
				    let theme: Theme
				    let label: Label?
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(generateMock: .public)
				public struct Shell: Instantiable {
				    public init(root: Root) {
				        self.root = root
				    }

				    @Instantiated let root: Root
				}
				""",
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoots() -> (Root, Root, Shell, Shell) {
				    (
				        Root.mock(safeDIOverrides: .init(label: .long)),
				        Root.mock(theme: .dark),
				        Shell.mock(safeDIOverrides: .init(root: .init(label: .long))),
				        Shell.mock(safeDIOverrides: .init(root: .init(theme: .dark, label: nil, { child, theme, label in Root(child: child, theme: theme, label: label) })))
				    )
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    // These providers evaluate `Root`'s own defaults outside any actor, since SafeDI sees no isolation on it. If one
			    // reads the state of an actor `Root` takes from a conformance or a superclass and does not compile, give its
			    // `@Instantiable` `mockAttributes: "@MainActor"` (or that actor).
			    @usableFromInline nonisolated static func __safeDI_publicMockDefault_label() -> Root.Label? { .short }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            child: (() -> Child)? = nil,
			            label: Root.Label? = Root.__safeDI_publicMockDefault_label()
			        ) {
			            self.child = child
			            self.label = label
			        }

			        public let child: (() -> Child)?
			        /// The default of `Root`'s `label` unless set; `.init(label: nil)` passes `nil`.
			        public let label: Root.Label?
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.mock(theme: nil, safeDIOverrides: safeDIOverrides)
			    }

			    static func mock(
			        theme: Root.Theme? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let theme = theme ?? (.light)
			        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder() } else { Child() }
			        return Root(child: child, theme: theme, label: safeDIOverrides.label)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_95F68EAF30427699 {}
			}
			#endif
			""",
			"Shell+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Shell {
			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            root: __safeDI_Root_MockConfiguration = .init()
			        ) {
			            self.root = root
			        }

			        public let root: __safeDI_Root_MockConfiguration
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Shell {
			        func __safeDI_root() -> Root {
			            let child = if let safeDIBuilder = safeDIOverrides.root.child { safeDIBuilder() } else { Child() }
			            return Root.__safeDI_init(child: child, theme: safeDIOverrides.root.theme, label: safeDIOverrides.root.label, safeDIBuilder: safeDIOverrides.root.safeDIBuilder)
			        }
			        let root: Root = __safeDI_root()
			        return Shell(root: root)
			    }
			}

			extension Shell {
			    public enum __safeDI_Shell_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Root` is constructed within the public mock trees of this module.
			public struct __safeDI_Root_MockConfiguration {
			    public init(
			        child: (() -> Child)? = nil,
			        label: Root.Label? = __safeDI_Root_mockDefault_label()
			    ) {
			        self.child = child
			        self.theme = nil
			        self.label = label
			        self.safeDIBuilder = nil
			    }

			    init(
			        child: (() -> Child)? = nil,
			        theme: Root.Theme? = nil,
			        label: Root.Label? = __safeDI_Root_mockDefault_label(),
			        _ safeDIBuilder: ((Child, Root.Theme, Root.Label?) -> Root)? = nil
			    ) {
			        self.child = child
			        self.theme = theme
			        self.label = label
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public let child: (() -> Child)?
			    /// `nil` keeps the default of `Root`'s `theme`.
			    let theme: Root.Theme?
			    /// The default of `Root`'s `label` unless set.
			    public let label: Root.Label?
			    /// Overrides how `Root` is constructed. Parameters match the type’s initializer or custom mock method.
			    let safeDIBuilder: ((Child, Root.Theme, Root.Label?) -> Root)?
			}

			extension Root {
			    nonisolated static func __safeDI_mockDefault_label() -> Root.Label? { .short }
			    static func __safeDI_init(child: Child, theme: Root.Theme?, label: Root.Label?, safeDIBuilder: ((Child, Root.Theme, Root.Label?) -> Root)?) -> Root {
			        let theme = theme ?? (.light)
			        return if let safeDIBuilder { safeDIBuilder(child, theme, label) } else { Root(child: child, theme: theme, label: label) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_Root_mockDefault_label() -> Root.Label? { Root.__safeDI_mockDefault_label() }
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesNoNestedTypeInUnreadTypeComment_whenPublicMockedTypesOwnDefaultValuedParametersAreOfTypesNestedInIt() async throws {
		// A run that does not read every first-party module (Bazel, Tuist) comments on each type a public declaration
		// names that SafeDI reads no declaration of. `Theme` and `Label` are `Root.Theme` and `Root.Label`, whose
		// declarations SafeDI reads: the `public` tier names `Theme`, and the provider above it names `Label`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "App",
					packageName: "pkg",
					swiftFileContentByFilePath: [
						"Root.swift": """
						import SafeDI

						@Instantiable(generateMock: .public)
						public struct Root: Instantiable {
						    public enum Theme: Sendable {
						        case light
						        case dark
						    }

						    enum Label: Sendable {
						        case short
						        case long
						    }

						    init(theme: Theme = .light, label: Label? = .short) {
						        self.theme = theme
						        self.label = label
						    }

						    let theme: Theme
						    let label: Label?
						}
						""",
						"MockCallSite.swift": """
						#if DEBUG
						func mockRoots() -> (Root, Root) {
						    (
						        Root.mock(theme: .dark),
						        Root.mock(theme: .dark, label: .long)
						    )
						}
						#endif
						""",
					],
				),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    // These providers evaluate `Root`'s own defaults outside any actor, since SafeDI sees no isolation on it. If one
		    // reads the state of an actor `Root` takes from a conformance or a superclass and does not compile, give its
		    // `@Instantiable` `mockAttributes: "@MainActor"` (or that actor).
		    nonisolated static func __safeDI_publicMockDefault_label() -> Root.Label? { .short }

		    public static func mock(
		        theme: Root.Theme? = nil
		    ) -> Root {
		        Root.mock(theme: theme, label: Root.__safeDI_publicMockDefault_label())
		    }

		    static func mock(
		        theme: Root.Theme? = nil,
		        label: Root.Label? = Root.__safeDI_publicMockDefault_label()
		    ) -> Root {
		        let theme = theme ?? (.light)
		        return Root(theme: theme, label: label)
		    }
		}

		extension Root {
		    public enum __safeDI_Root_mock_523A7E0915F9DB2D {}
		}
		#endif
		"""])
	}

	// MARK: Tests – the types the builder takes

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypesInPublicConfigurationBuilder_whenBuilderParametersNameTypesNestedInConfiguredType() async throws {
		// `Child`'s closure-typed default takes a nested type, which its builder's parameter names inside the closure
		// type; `Badge` is built with its hand-written mock, whose default-valued parameter's nested type the builder
		// takes.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Root: Instantiable {
				    public init(badge: Badge, child: Child) {
				        self.badge = badge
				        self.child = child
				    }

				    @Instantiated let badge: Badge
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Badge: Instantiable {
				    public enum Tint: Sendable {
				        case red
				        case blue
				    }

				    public init() {
				        tint = .red
				    }

				    init(tint: Tint) {
				        self.tint = tint
				    }

				    public static func mock(tint: Tint = .blue) -> Badge {
				        Badge(tint: tint)
				    }

				    public let tint: Tint
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public enum Theme: Sendable {
				        case light
				        case dark
				    }

				    public init(onSelect: @escaping (Theme) -> Void = { _ in }) {
				        self.onSelect = onSelect
				    }

				    public let onSelect: (Theme) -> Void
				}
				""",
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoot() -> Root {
				    Root.mock(safeDIOverrides: .init(
				        badge: .init(tint: .red, { tint in Badge.mock(tint: tint) }),
				        child: .init(onSelect: { _ in }, { onSelect in Child(onSelect: onSelect) })
				    ))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            badge: __safeDI_Badge_MockConfiguration = .init(),
			            child: __safeDI_Child_MockConfiguration = .init()
			        ) {
			            self.badge = badge
			            self.child = child
			        }

			        public let badge: __safeDI_Badge_MockConfiguration
			        public let child: __safeDI_Child_MockConfiguration
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_badge() -> Badge {
			            return Badge.__safeDI_mock(tint: safeDIOverrides.badge.tint, safeDIBuilder: safeDIOverrides.badge.safeDIBuilder)
			        }
			        let badge: Badge = __safeDI_badge()
			        func __safeDI_child() -> Child {
			            return Child.__safeDI_init(onSelect: safeDIOverrides.child.onSelect, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)
			        }
			        let child: Child = __safeDI_child()
			        return Root(badge: badge, child: child)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Badge` is constructed within the public mock trees of this module.
			public struct __safeDI_Badge_MockConfiguration {
			    public init(
			        tint: Badge.Tint? = nil,
			        _ safeDIBuilder: ((Badge.Tint) -> Badge)? = nil
			    ) {
			        self.tint = tint
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Badge`'s `tint`.
			    public let tint: Badge.Tint?
			    /// Overrides how `Badge` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Badge.Tint) -> Badge)?
			}

			extension Badge {
			    static func __safeDI_mock(tint: Badge.Tint?, safeDIBuilder: ((Badge.Tint) -> Badge)?) -> Badge {
			        let tint = tint ?? (.blue)
			        return if let safeDIBuilder { safeDIBuilder(tint) } else { Badge.mock(tint: tint) }
			    }
			}

			/// Configuration for how `Child` is constructed within the public mock trees of this module.
			public struct __safeDI_Child_MockConfiguration {
			    public init(
			        onSelect: ((Child.Theme) -> Void)? = nil,
			        _ safeDIBuilder: ((@escaping (Child.Theme) -> Void) -> Child)? = nil
			    ) {
			        self.onSelect = onSelect
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Child`'s `onSelect`.
			    public let onSelect: ((Child.Theme) -> Void)?
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((@escaping (Child.Theme) -> Void) -> Child)?
			}

			extension Child {
			    static func __safeDI_init(onSelect: ((Child.Theme) -> Void)?, safeDIBuilder: ((@escaping (Child.Theme) -> Void) -> Child)?) -> Child {
			        let onSelect = onSelect ?? ({ _ in })
			        return if let safeDIBuilder { safeDIBuilder(onSelect) } else { Child(onSelect: onSelect) }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypesInPublicConfiguration_whenDefaultValuedParametersAreOfGenericAndCollectionTypesOfNestedTypes() async throws {
		// A generic nested type is qualified with its generic arguments, each qualified in turn, and so is a nested type
		// inside an array, a dictionary, or a metatype.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.root(instantiating: "child: Child"),
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public enum Theme: Sendable {
				        case light
				        case dark
				    }

				    public struct Box<Value: Sendable>: Sendable {
				        public init(_ value: Value) {
				            self.value = value
				        }

				        public let value: Value
				    }

				    public init(box: Box<Theme> = Box(.light), themes: [Theme] = [.light], themesByName: [String: Theme] = [:], kind: Theme.Type = Theme.self) {
				        self.box = box
				        self.themes = themes
				        self.themesByName = themesByName
				        self.kind = kind
				    }

				    public let box: Box<Theme>
				    public let themes: [Theme]
				    public let themesByName: [String: Theme]
				    public let kind: Theme.Type
				}
				""",
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoot() -> Root {
				    Root.mock(safeDIOverrides: .init(child: .init(
				        box: Child.Box(.dark),
				        themes: [.dark],
				        themesByName: ["dark": .dark],
				        kind: Child.Theme.self,
				        { box, themes, themesByName, kind in Child(box: box, themes: themes, themesByName: themesByName, kind: kind) }
				    )))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": Self.rootMock(building: "child", ofType: "Child", configuredBy: "__safeDI_Child_MockConfiguration", construction: "Child.__safeDI_init(box: safeDIOverrides.child.box, themes: safeDIOverrides.child.themes, themesByName: safeDIOverrides.child.themesByName, kind: safeDIOverrides.child.kind, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)"),
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Child` is constructed within the public mock trees of this module.
			public struct __safeDI_Child_MockConfiguration {
			    public init(
			        box: Child.Box<Child.Theme>? = nil,
			        themes: [Child.Theme]? = nil,
			        themesByName: [String: Child.Theme]? = nil,
			        kind: Child.Theme.Type? = nil,
			        _ safeDIBuilder: ((Child.Box<Child.Theme>, [Child.Theme], [String: Child.Theme], Child.Theme.Type) -> Child)? = nil
			    ) {
			        self.box = box
			        self.themes = themes
			        self.themesByName = themesByName
			        self.kind = kind
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Child`'s `box`.
			    public let box: Child.Box<Child.Theme>?
			    /// `nil` keeps the default of `Child`'s `themes`.
			    public let themes: [Child.Theme]?
			    /// `nil` keeps the default of `Child`'s `themesByName`.
			    public let themesByName: [String: Child.Theme]?
			    /// `nil` keeps the default of `Child`'s `kind`.
			    public let kind: Child.Theme.Type?
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Child.Box<Child.Theme>, [Child.Theme], [String: Child.Theme], Child.Theme.Type) -> Child)?
			}

			extension Child {
			    static func __safeDI_init(box: Child.Box<Child.Theme>?, themes: [Child.Theme]?, themesByName: [String: Child.Theme]?, kind: Child.Theme.Type?, safeDIBuilder: ((Child.Box<Child.Theme>, [Child.Theme], [String: Child.Theme], Child.Theme.Type) -> Child)?) -> Child {
			        let box = box ?? (Box(.light))
			        let themes = themes ?? ([.light])
			        let themesByName = themesByName ?? ([:])
			        let kind = kind ?? (Theme.self)
			        return if let safeDIBuilder { safeDIBuilder(box, themes, themesByName, kind) } else { Child(box: box, themes: themes, themesByName: themesByName, kind: kind) }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeInSendablePublicConfiguration_whenConfiguredTypeIsBuiltInSendableBuilderFunction() async throws {
		// A configuration a `@Sendable` builder function reads holds each default as a `@Sendable` closure that returns
		// the value, whose type is qualified as the value's is.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Root: Instantiable {
				    public init(childBuilder: SendableInstantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: SendableInstantiator<Child>
				}
				""",
				Self.childWithNestedTheme,
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoot() -> Root {
				    Root.mock(safeDIOverrides: .init(childBuilder: .init(theme: .dark, { theme in Child(theme: theme) })))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            childBuilder: __safeDI_Child_MockConfiguration = .init()
			        ) {
			            self.childBuilder = childBuilder
			        }

			        public let childBuilder: __safeDI_Child_MockConfiguration
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_childBuilder__childBuilder_theme = safeDIOverrides.childBuilder.theme
			        let __safeDI_childBuilder__safeDIBuilder = safeDIOverrides.childBuilder.safeDIBuilder
			        @Sendable func __safeDI_childBuilder() -> Child {
			            Child.__safeDI_init(theme: __safeDI_childBuilder__childBuilder_theme(), safeDIBuilder: __safeDI_childBuilder__safeDIBuilder)
			        }
			        let childBuilder = SendableInstantiator<Child>(__safeDI_childBuilder)
			        return Root(childBuilder: childBuilder)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Child` is constructed within the public mock trees of this module.
			public struct __safeDI_Child_MockConfiguration {
			    public init(
			        theme: @autoclosure @escaping @Sendable () -> Child.Theme? = nil,
			        _ safeDIBuilder: (@Sendable (Child.Theme) -> Child)? = nil
			    ) {
			        self.theme = theme
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Child`'s `theme`.
			    public let theme: @Sendable () -> Child.Theme?
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: (@Sendable (Child.Theme) -> Child)?
			}

			extension Child {
			    static func __safeDI_init(theme: Child.Theme?, safeDIBuilder: (@Sendable (Child.Theme) -> Child)?) -> Child {
			        let theme = theme ?? (.light)
			        return if let safeDIBuilder { safeDIBuilder(theme) } else { Child(theme: theme) }
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Tests – what stays as written

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsSpellingInPublicConfiguration_whenDefaultValuedParametersAreQualifiedOrOfTopLevelTypes() async throws {
		// `Child.Theme` is already qualified (`Child` declares no `Child`), `Mode` is declared at the top level, and
		// `Swift.Int` names its module: each names what it names anywhere in the module, so each is kept.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public enum Mode: Sendable {
				    case fast
				    case slow
				}
				""",
				Self.root(instantiating: "child: Child"),
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public enum Theme: Sendable {
				        case light
				        case dark
				    }

				    public init(theme: Child.Theme = .light, mode: Mode = .fast, count: Swift.Int = 0) {
				        self.theme = theme
				        self.mode = mode
				        self.count = count
				    }

				    public let theme: Child.Theme
				    public let mode: Mode
				    public let count: Swift.Int
				}
				""",
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoot() -> Root {
				    Root.mock(safeDIOverrides: .init(child: .init(theme: .dark, mode: .slow, count: 1, { theme, mode, count in Child(theme: theme, mode: mode, count: count) })))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": Self.rootMock(building: "child", ofType: "Child", configuredBy: "__safeDI_Child_MockConfiguration", construction: "Child.__safeDI_init(theme: safeDIOverrides.child.theme, mode: safeDIOverrides.child.mode, count: safeDIOverrides.child.count, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)"),
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Child` is constructed within the public mock trees of this module.
			public struct __safeDI_Child_MockConfiguration {
			    public init(
			        theme: Child.Theme? = nil,
			        mode: Mode? = nil,
			        count: Swift.Int? = nil,
			        _ safeDIBuilder: ((Child.Theme, Mode, Swift.Int) -> Child)? = nil
			    ) {
			        self.theme = theme
			        self.mode = mode
			        self.count = count
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Child`'s `theme`.
			    public let theme: Child.Theme?
			    /// `nil` keeps the default of `Child`'s `mode`.
			    public let mode: Mode?
			    /// `nil` keeps the default of `Child`'s `count`.
			    public let count: Swift.Int?
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Child.Theme, Mode, Swift.Int) -> Child)?
			}

			extension Child {
			    static func __safeDI_init(theme: Child.Theme?, mode: Mode?, count: Swift.Int?, safeDIBuilder: ((Child.Theme, Mode, Swift.Int) -> Child)?) -> Child {
			        let theme = theme ?? (.light)
			        let mode = mode ?? (.fast)
			        let count = count ?? (0)
			        return if let safeDIBuilder { safeDIBuilder(theme, mode, count) } else { Child(theme: theme, mode: mode, count: count) }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeInInternalConfiguration_whenInternalMockBesidePublicMockBuildsTypeWithNestedDefault() async throws {
		// `Other`'s internal mock reads `Child.SafeDIMockConfiguration`, which is declared in `Child`'s extension, and the
		// public mock's module-level configuration is declared outside `Child`: both name `Theme` qualified, as SafeDI
		// normalizes every type a declaration spells.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.root(instantiating: "child: Child"),
				"""
				@Instantiable(generateMock: true)
				public struct Other: Instantiable {
				    public init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
				Self.childWithNestedTheme,
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoots() -> (Root, Other) {
				    (
				        Root.mock(safeDIOverrides: .init(child: .init(theme: .dark, { theme in Child(theme: theme) }))),
				        Other.mock(safeDIOverrides: .init(child: .init(theme: .dark, { theme in Child(theme: theme) })))
				    )
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Other+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Other {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            child: Child.SafeDIMockConfiguration = .init()
			        ) {
			            self.child = child
			        }

			        let child: Child.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Other {
			        func __safeDI_child() -> Child {
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(safeDIOverrides.child.theme) } else { Child(theme: safeDIOverrides.child.theme) }
			        }
			        let child: Child = __safeDI_child()
			        return Other(child: child)
			    }
			}
			#endif
			""",
			"Root+SafeDIMock.swift": Self.rootMock(building: "child", ofType: "Child", configuredBy: "__safeDI_Child_MockConfiguration", construction: "Child.__safeDI_init(theme: safeDIOverrides.child.theme, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)"),
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Child {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            theme: Child.Theme = .light,
			            _ safeDIBuilder: ((Child.Theme) -> Child)? = nil
			        ) {
			            self.theme = theme
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let theme: Child.Theme
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((Child.Theme) -> Child)?
			    }
			}


			""" + Self.childThemePublicConfiguration + "\n#endif\n",
		])
	}

	// MARK: Tests – across modules

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeInPublicConfiguration_whenConfiguredTypeAndItsNestedTypeAreDeclaredInAnotherModule(integration: MultiModuleIntegration) async throws {
		// `App`'s configuration of `Core`'s `Child` reads `Child.Theme`'s declaration from `Core`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Child.swift": "import SafeDI\n\n" + Self.childWithNestedTheme]),
				ModuleFixture(
					name: "App",
					packageName: "pkg",
					swiftFileContentByFilePath: [
						"Root.swift": "import Core\nimport SafeDI\n\n" + Self.root(instantiating: "child: Child"),
						"MockCallSite.swift": """
						import Core

						#if DEBUG
						func mockRoot() -> Root {
						    Root.mock(safeDIOverrides: .init(child: .init(theme: .dark, { theme in Child(theme: theme) })))
						}
						#endif
						""",
					],
					dependencies: ["Core"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let imports = """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""
		let rootMock = """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            child: __safeDI_App_Child_MockConfiguration = .init()
		        ) {
		            self.child = child
		        }

		        public let child: __safeDI_App_Child_MockConfiguration
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_child() -> Child {
		            return Child.__safeDI_init(theme: safeDIOverrides.child.theme, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)
		        }
		        let child: Child = __safeDI_child()
		        return Root(child: child)
		    }
		}

		extension Root {
		    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
		}
		#endif
		"""
		let configuration = """
		#if DEBUG
		/// Configuration for how `Child` is constructed within the public mock trees of module `App`.
		public struct __safeDI_App_Child_MockConfiguration {
		    public init(
		        theme: Child.Theme? = nil,
		        _ safeDIBuilder: ((Child.Theme) -> Child)? = nil
		    ) {
		        self.theme = theme
		        self.safeDIBuilder = safeDIBuilder
		    }

		    /// `nil` keeps the default of `Child`'s `theme`.
		    public let theme: Child.Theme?
		    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
		    public let safeDIBuilder: ((Child.Theme) -> Child)?
		}

		extension Child {
		    static func __safeDI_init(theme: Child.Theme?, safeDIBuilder: ((Child.Theme) -> Child)?) -> Child {
		        let theme = theme ?? (.light)
		        return if let safeDIBuilder { safeDIBuilder(theme) } else { Child(theme: theme) }
		    }
		}
		#endif
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + imports + rootMock + "\n\n" + configuration + "\n"])
		case .swiftPackagePlugin:
			#expect(output.modules["App"]?.generatedFiles["Root+SafeDIMock.swift"] == generatedFileHeader + imports + rootMock)
			#expect(output.modules["App"]?.generatedFiles["SafeDIMockConfiguration.swift"] == generatedFileHeader + imports + configuration + "\n")
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A `Root` with a public mock that instantiates `dependency`, a `label: Type` pair.
	private static func root(instantiating dependency: String) -> String {
		"""
		@Instantiable(generateMock: .public)
		public struct Root: Instantiable {
		    public init(\(dependency)) {
		        self.\(dependency.prefix(while: { $0 != ":" })) = \(dependency.prefix(while: { $0 != ":" }))
		    }

		    @Instantiated let \(dependency)
		}
		"""
	}

	/// The public mock of `root(instantiating:)`, which builds `label`, configured by `configurationTypeName`, with
	/// `construction`.
	private static func rootMock(building label: String, ofType type: String, configuredBy configurationTypeName: String, construction: String) -> String {
		generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            \(label): \(configurationTypeName) = .init()
		        ) {
		            self.\(label) = \(label)
		        }

		        public let \(label): \(configurationTypeName)
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_\(label)() -> \(type) {
		            return \(construction)
		        }
		        let \(label): \(type) = __safeDI_\(label)()
		        return Root(\(label): \(label))
		    }
		}

		extension Root {
		    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
		}
		#endif
		"""
	}

	/// A `Child` whose initializer's default-valued parameter is of a `Theme` nested in it.
	private static let childWithNestedTheme = """
	@Instantiable
	public final class Child: Instantiable {
	    public enum Theme: Sendable {
	        case light
	        case dark
	    }

	    public init(theme: Theme = .light) {
	        self.theme = theme
	    }

	    public let theme: Theme
	}
	"""

	/// The module-level configuration of `childWithNestedTheme` that a public mock of this module generates, in the block
	/// that compiles it only where mocks compile.
	private static let childThemeConfiguration = "#if DEBUG\n" + childThemePublicConfiguration + "\n#endif"

	/// The module-level configuration of `childWithNestedTheme` that a public mock of this module generates.
	private static let childThemePublicConfiguration = """
	/// Configuration for how `Child` is constructed within the public mock trees of this module.
	public struct __safeDI_Child_MockConfiguration {
	    public init(
	        theme: Child.Theme? = nil,
	        _ safeDIBuilder: ((Child.Theme) -> Child)? = nil
	    ) {
	        self.theme = theme
	        self.safeDIBuilder = safeDIBuilder
	    }

	    /// `nil` keeps the default of `Child`'s `theme`.
	    public let theme: Child.Theme?
	    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
	    public let safeDIBuilder: ((Child.Theme) -> Child)?
	}

	extension Child {
	    static func __safeDI_init(theme: Child.Theme?, safeDIBuilder: ((Child.Theme) -> Child)?) -> Child {
	        let theme = theme ?? (.light)
	        return if let safeDIBuilder { safeDIBuilder(theme) } else { Child(theme: theme) }
	    }
	}
	"""
}
